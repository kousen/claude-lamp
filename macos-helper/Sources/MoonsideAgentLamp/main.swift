import AppKit
import CoreBluetooth
import ServiceManagement
import LampCore
import OSLog
import Darwin

let serviceID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
let writeID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

final class LampApp: NSObject, NSApplicationDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Moonside Agent Lamp", isDirectory: true)
    private let logger = Logger(subsystem: "com.kousenit.moonside-agent-lamp", category: "lamp")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var statusItem: NSStatusItem!
    private var statusLine = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var stateLine = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
    private var pauseItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var timer: Timer?
    private var reconnectTask: DispatchWorkItem?
    private var operationDeadline: Date?
    private var writeDeadline: Date?
    private var writePending = false
    private var commands: [String] = []
    private var machine = StateMachine()
    private var backoff = Backoff()
    private var started = Date().timeIntervalSince1970
    private var paused = false
    private var sleeping = false
    private var lockFD: Int32 = -1
    private var ownsLock = false
    private var connection = "Starting"
    private var lastCommand = ""
    private var quitting = false
    private var eventVersion = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            lockFD = open(root.appendingPathComponent("helper.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
            ownsLock = true
        } catch { showError(error); NSApp.terminate(nil); return }
        makeMenu()
        if CommandLine.arguments.contains("--enable-login"), SMAppService.mainApp.status != .enabled {
            toggleLogin()
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        central = CBCentralManager(delegate: self, queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer!, forMode: .common)
        log("Started bundle \(Bundle.main.bundleIdentifier ?? "unknown"); path \(Bundle.main.bundlePath)")
    }

    private func makeMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Moonside Agent Lamp")
        let menu = NSMenu()
        menu.addItem(statusLine); menu.addItem(stateLine); menu.addItem(.separator())
        add(menu, "Reconnect", #selector(reconnect))
        pauseItem = add(menu, "Pause & Disconnect", #selector(togglePause))
        let testMenu = NSMenu()
        for state in LampState.allCases where state != .idle {
            let item = NSMenuItem(title: state.displayName, action: #selector(testColor(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = state.rawValue; testMenu.addItem(item)
        }
        let testItem = NSMenuItem(title: "Test Lamp", action: nil, keyEquivalent: "")
        testItem.submenu = testMenu; menu.addItem(testItem)
        menu.addItem(.separator())
        loginItem = add(menu, "Start at Login", #selector(toggleLogin))
        add(menu, "Bluetooth Settings…", #selector(openSettings))
        add(menu, "Show Diagnostics…", #selector(openDiagnostics))
        menu.addItem(.separator()); add(menu, "Quit", #selector(quit))
        statusItem.menu = menu
        refreshLogin()
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item); return item
    }

    private func log(_ text: String) {
        logger.info("\(text, privacy: .public)")
        let url = root.appendingPathComponent("helper.log")
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 1_000_000 {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("helper.previous.log"))
            try? FileManager.default.moveItem(at: url, to: root.appendingPathComponent("helper.previous.log"))
        }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data("\(ISO8601DateFormatter().string(from: Date())) \(text)\n".utf8))
        }
    }

    private func report(_ text: String) {
        if connection != text { log(text) }
        connection = text; statusLine.title = text
        statusItem.button?.toolTip = "Moonside: \(text)"
        snapshot()
    }

    private func snapshot() {
        let status: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "bundle": Bundle.main.bundleIdentifier ?? "unknown", "connection": connection,
            "authorization": CBManager.authorization.rawValue,
            "state": machine.state.rawValue, "lastCommand": lastCommand,
            "paused": paused, "loginEnabled": SMAppService.mainApp.status == .enabled,
            "device": peripheral?.identifier.uuidString ?? "", "updated": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("status.json"), options: .atomic)
        }
    }

    private func poll() {
        guard !quitting else { return }
        let now = Date().timeIntervalSince1970
        if let data = try? Data(contentsOf: root.appendingPathComponent("event")), data.count <= 512,
           let text = String(data: data, encoding: .utf8),
           let event = LampEvent(text, now: now, started: started) {
            if machine.accept(event, now: now) { applyState() }
        }
        if machine.tick(now: now) { applyState() }
        if let deadline = operationDeadline, Date() >= deadline { failConnection("Connection/discovery timed out") }
        if let deadline = writeDeadline, Date() >= deadline { failConnection("Lamp write timed out") }
    }

    private func applyState() {
        eventVersion += 1
        stateLine.title = machine.state.displayName
        log("State: \(machine.state.rawValue)")
        if characteristic != nil && !paused && !sleeping {
            commands = machine.state.commands
            if !writePending { sendNext() }
        }
        snapshot()
    }

    private func sendNext() {
        guard !writePending, !commands.isEmpty, let p = peripheral, p.state == .connected,
              let c = characteristic else { return }
        let command = commands.removeFirst()
        lastCommand = command; log("TX \(command)")
        writePending = true; writeDeadline = Date().addingTimeInterval(5)
        p.writeValue(Data(command.utf8), for: c, type: .withResponse)
        snapshot()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral else { return }
        writeDeadline = nil
        if let error { failConnection("Write failed: \(error.localizedDescription)"); return }
        let version = eventVersion
        // Space commands, and never let a delayed old color overwrite a newer event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.peripheral == peripheral else { return }
            self.writePending = false
            if version != self.eventVersion { self.commands = self.machine.state.commands }
            self.sendNext()
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: if !paused && !sleeping { scan() }
        case .unauthorized: clearConnection(); report("Bluetooth permission needed — open Settings")
        case .poweredOff: clearConnection(); report("Bluetooth is off")
        case .unsupported: clearConnection(); report("Bluetooth unavailable")
        default: clearConnection(); report("Waiting for Bluetooth")
        }
    }

    private func scan() {
        guard !paused, !sleeping, central.state == .poweredOn, peripheral == nil else { return }
        reconnectTask?.cancel(); reconnectTask = nil
        report("Looking for Halo…")
        // Existing Halo firmware is discovered by advertised name; NUS may not be in its advertisement.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        operationDeadline = Date().addingTimeInterval(10)
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral == nil, !paused else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        guard name.uppercased().hasPrefix("MOONSIDE") else { return }
        if let pinned = UserDefaults.standard.string(forKey: "lampUUID"), pinned != p.identifier.uuidString { return }
        central.stopScan(); peripheral = p; p.delegate = self
        report("Connecting to \(name)…"); operationDeadline = Date().addingTimeInterval(15)
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p == peripheral else { return }
        operationDeadline = Date().addingTimeInterval(10)
        p.discoverServices([serviceID])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p == peripheral else { return }
        guard error == nil, let service = p.services?.first(where: { $0.uuid == serviceID }) else {
            failConnection("Moonside UART service unavailable"); return
        }
        p.discoverCharacteristics([writeID], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard p == peripheral else { return }
        guard error == nil, let c = service.characteristics?.first(where: { $0.uuid == writeID }),
              c.properties.contains(.write) else { failConnection("Moonside write characteristic unavailable"); return }
        characteristic = c; operationDeadline = nil; backoff.reset()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: "lampUUID")
        report("Connected to \(p.name ?? "Halo")")
        _ = machine.tick(now: Date().timeIntervalSince1970)
        applyState()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        guard p == peripheral else { return }; failConnection("Could not connect to Halo")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p == peripheral else { return }; failConnection("Halo disconnected")
    }

    private func clearConnection() {
        reconnectTask?.cancel(); reconnectTask = nil
        central?.stopScan()
        let old = peripheral
        peripheral = nil; characteristic = nil; commands = []; writePending = false
        writeDeadline = nil; operationDeadline = nil
        if let old { central.cancelPeripheralConnection(old) }
    }

    private func failConnection(_ reason: String) {
        clearConnection()
        guard !paused, !sleeping, central.state == .poweredOn else { return }
        let delay = backoff.next()
        report("\(reason); retry in \(Int(delay))s")
        let task = DispatchWorkItem { [weak self] in self?.scan() }
        reconnectTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    @objc private func reconnect() {
        paused = false; pauseItem.title = "Pause & Disconnect"; backoff.reset()
        clearConnection(); scan()
    }
    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "Resume" : "Pause & Disconnect"
        if paused { clearConnection(); report("Paused — lamp released for phone app") } else { scan() }
    }
    @objc private func willSleep() { sleeping = true; clearConnection(); report("Sleeping") }
    @objc private func didWake() { sleeping = false; backoff.reset(); _ = machine.tick(now: Date().timeIntervalSince1970); scan() }
    @objc private func testColor(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? String else { return }
        let now = Date().timeIntervalSince1970
        if let event = LampEvent("1\t\(now)\t\(UUID().uuidString)\t\(state)", now: now, started: started) {
            _ = machine.accept(event, now: now); applyState()
        }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { showError(error) }
        refreshLogin(); snapshot()
    }
    private func refreshLogin() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if SMAppService.mainApp.status == .requiresApproval {
            loginItem.title = "Start at Login — approve in System Settings"
        } else { loginItem.title = "Start at Login" }
    }
    @objc private func openSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!) }
    @objc private func openDiagnostics() { NSWorkspace.shared.selectFile(root.appendingPathComponent("helper.log").path, inFileViewerRootedAtPath: root.path) }
    private func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Moonside Agent Lamp"
        alert.informativeText = error.localizedDescription; alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsLock, characteristic != nil, !quitting else { return .terminateNow }
        quitting = true; commands = ["LEDOFF"]
        if !writePending { sendNext() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        guard ownsLock else { return }
        quitting = true; timer?.invalidate(); clearConnection()
        log("Helper stopped; hook events cannot launch Bluetooth")
        try? FileManager.default.removeItem(at: root.appendingPathComponent("status.json"))
        if lockFD >= 0 { close(lockFD) }
    }
}

let app = NSApplication.shared
let delegate = LampApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
