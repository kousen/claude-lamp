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
    private var recovery = ConnectionRecovery()
    private var writes = LampWriteQueue()
    private var machine = StateMachine()
    private var started = Date().timeIntervalSince1970
    private var paused: Bool { recovery.paused }
    private var sleeping: Bool { recovery.sleeping }
    private var lockFD: Int32 = -1
    private var ownsLock = false
    private var connection = "Starting"
    private var lastCommand = ""
    private var quitting = false

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
        // Finish a queued LEDOFF even during the short graceful-quit window.
        guard !quitting else { sendNext(); return }
        let now = Date().timeIntervalSince1970
        if let data = try? Data(contentsOf: root.appendingPathComponent("event")), data.count <= 512,
           let text = String(data: data, encoding: .utf8),
           let event = LampEvent(text, now: now, started: started) {
            if machine.accept(event, now: now) { applyState() }
        }
        if machine.tick(now: now) { applyState() }
        if recovery.timedOut(now: now) { failConnection("Connection/discovery timed out") }
        if writes.timedOut(now: now) { failConnection("Lamp write timed out") }
        if recovery.retryDue(now: now) { scan() }
        sendNext()
    }

    private func applyState() {
        stateLine.title = machine.state.displayName
        log("State: \(machine.state.rawValue)")
        if characteristic != nil && !paused && !sleeping {
            writes.replace(with: machine.state.commands)
            sendNext()
        }
        snapshot()
    }

    private func sendNext() {
        guard let p = peripheral, p.state == .connected, let c = characteristic,
              let write = writes.next(now: Date().timeIntervalSince1970) else { return }
        let command = write.command
        lastCommand = command; log("TX \(command)")
        p.writeValue(Data(command.utf8), for: c, type: .withResponse)
        snapshot()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == self.peripheral, characteristic === self.characteristic,
              let active = writes.active else { return }
        if let error { failConnection("Write failed: \(error.localizedDescription)"); return }
        writes.acknowledge(active.id, now: Date().timeIntervalSince1970)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: recovery.setAvailability(.poweredOn); scan()
        case .unauthorized:
            recovery.setAvailability(.unauthorized); clearConnection(); report("Bluetooth permission needed — open Settings")
        case .poweredOff:
            recovery.setAvailability(.poweredOff); clearConnection(); report("Bluetooth is off")
        case .unsupported:
            recovery.setAvailability(.unsupported); clearConnection(); report("Bluetooth unavailable")
        default:
            recovery.setAvailability(.unknown); clearConnection(); report("Waiting for Bluetooth")
        }
    }

    private func scan() {
        guard peripheral == nil, recovery.beginScan(now: Date().timeIntervalSince1970) else { return }
        report("Looking for Halo…")
        // Existing Halo firmware is discovered by advertised name; NUS may not be in its advertisement.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral == nil, recovery.canConnect else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        guard name.uppercased().hasPrefix("MOONSIDE") else { return }
        if let pinned = UserDefaults.standard.string(forKey: "lampUUID"), pinned != p.identifier.uuidString { return }
        guard recovery.discovered(now: Date().timeIntervalSince1970) else { return }
        central.stopScan(); peripheral = p; p.delegate = self
        report("Connecting to \(name)…")
        central.connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p == peripheral, recovery.connected(now: Date().timeIntervalSince1970) else { return }
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
        guard recovery.ready() else { return }
        characteristic = c
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
        recovery.clear()
        central?.stopScan()
        let old = peripheral
        peripheral = nil; characteristic = nil; writes.clear()
        if let old { central.cancelPeripheralConnection(old) }
    }

    private func failConnection(_ reason: String) {
        clearConnection()
        guard let delay = recovery.failed(now: Date().timeIntervalSince1970) else { return }
        report("\(reason); retry in \(Int(delay))s")
    }

    @objc private func reconnect() {
        recovery.setPaused(false); pauseItem.title = "Pause & Disconnect"; recovery.resetBackoff()
        clearConnection(); scan()
    }
    @objc private func togglePause() {
        recovery.setPaused(!paused)
        pauseItem.title = paused ? "Resume" : "Pause & Disconnect"
        if paused { clearConnection(); report("Paused — lamp released for phone app") } else { scan() }
    }
    @objc private func willSleep() { recovery.setSleeping(true); clearConnection(); report("Sleeping") }
    @objc private func didWake() {
        recovery.setSleeping(false)
        if machine.tick(now: Date().timeIntervalSince1970) { applyState() }
        scan()
    }
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
        quitting = true; recovery.stop(); writes.replace(with: ["LEDOFF"])
        sendNext()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        guard ownsLock else { return }
        quitting = true; recovery.stop(); timer?.invalidate(); clearConnection()
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
