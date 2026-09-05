import Foundation

/// Pure connection policy shared by the real CoreBluetooth adapter and tests.
/// The caller supplies time; no timers, hardware, or sleeps are needed in tests.
public struct ConnectionRecovery {
    public enum Availability { case poweredOn, poweredOff, unauthorized, unsupported, unknown }
    public enum Phase { case idle, scanning, connecting, discovering, ready, waiting }
    public private(set) var availability: Availability = .unknown
    public private(set) var phase: Phase = .idle
    public private(set) var paused = false
    public private(set) var sleeping = false
    public private(set) var stopped = false
    public private(set) var operationDeadline: TimeInterval?
    public private(set) var retryAt: TimeInterval?
    private var backoff = Backoff()
    public init() {}
    public var canConnect: Bool { availability == .poweredOn && !paused && !sleeping && !stopped }
    public mutating func clear() { phase = .idle; operationDeadline = nil; retryAt = nil }
    public mutating func setAvailability(_ value: Availability) {
        availability = value
        if !canConnect { clear() }
    }
    public mutating func setPaused(_ value: Bool) { paused = value; clear() }
    public mutating func setSleeping(_ value: Bool) { sleeping = value; clear(); if !value { backoff.reset() } }
    public mutating func stop() { stopped = true; clear() }
    public mutating func resetBackoff() { backoff.reset() }
    @discardableResult public mutating func beginScan(now: TimeInterval) -> Bool {
        guard canConnect, phase == .idle || phase == .waiting,
              retryAt == nil || now >= retryAt! else { return false }
        phase = .scanning; retryAt = nil; operationDeadline = now + 10; return true
    }
    @discardableResult public mutating func discovered(now: TimeInterval) -> Bool {
        guard canConnect, phase == .scanning else { return false }
        phase = .connecting; operationDeadline = now + 15; return true
    }
    @discardableResult public mutating func connected(now: TimeInterval) -> Bool {
        guard canConnect, phase == .connecting else { return false }
        phase = .discovering; operationDeadline = now + 10; return true
    }
    @discardableResult public mutating func ready() -> Bool {
        guard canConnect, phase == .discovering else { return false }
        phase = .ready; operationDeadline = nil; retryAt = nil; backoff.reset(); return true
    }
    public func timedOut(now: TimeInterval) -> Bool { operationDeadline.map { now >= $0 } ?? false }
    public func retryDue(now: TimeInterval) -> Bool { canConnect && (retryAt.map { now >= $0 } ?? false) }
    public mutating func failed(now: TimeInterval) -> Double? {
        clear()
        guard canConnect else { return nil }
        let delay = backoff.next(); phase = .waiting; retryAt = now + delay; return delay
    }
}

/// One outstanding GATT write. Replacing desired commands never queues an old color
/// behind a newer state. Clearing a connection invalidates outstanding write IDs.
public struct LampWriteQueue {
    public struct Write: Equatable { public let id: UInt64; public let command: String }
    public private(set) var active: Write?
    private var pending: [String] = []
    private var serial: UInt64 = 0
    private var deadline: TimeInterval?
    private var readyAt: TimeInterval = 0
    public init() {}
    public mutating func replace(with commands: [String]) { pending = commands }
    public mutating func clear() { active = nil; pending = []; deadline = nil; readyAt = 0 }
    public mutating func next(now: TimeInterval) -> Write? {
        guard active == nil, !pending.isEmpty, now >= readyAt else { return nil }
        serial += 1
        let write = Write(id: serial, command: pending.removeFirst())
        active = write; deadline = now + 5; return write
    }
    @discardableResult public mutating func acknowledge(_ id: UInt64, now: TimeInterval) -> Bool {
        guard active?.id == id else { return false }
        active = nil; deadline = nil; readyAt = now + 0.12; return true
    }
    public func timedOut(now: TimeInterval) -> Bool { deadline.map { now >= $0 } ?? false }
}
