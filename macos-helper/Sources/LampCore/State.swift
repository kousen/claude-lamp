import Foundation

public enum LampState: String, CaseIterable {
    case idle, off, working, input, done
    case codexWorking = "codex-working", codexInput = "codex-input", codexDone = "codex-done"

    public var isCompletion: Bool { self == .done || self == .codexDone }
    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .off: return "Turn Off"
        case .working: return "Claude: Working"
        case .input: return "Claude: Needs Input"
        case .done: return "Claude: Done"
        case .codexWorking: return "Codex: Working"
        case .codexInput: return "Codex: Needs Input"
        case .codexDone: return "Codex: Done"
        }
    }
    public var commands: [String] {
        let color: String
        switch self {
        case .idle, .off: return ["LEDOFF"]
        case .working: color = "COLOR000060255"
        case .input: color = "COLOR200000255"
        case .done: color = "COLOR000255060"
        case .codexWorking: color = "COLOR000220255"
        case .codexInput: color = "COLOR255120000"
        case .codexDone: color = "COLOR255255255"
        }
        let brightness = self == .working || self == .codexWorking ? "BRIGH025" : "BRIGH100"
        return ["LEDON", brightness, color]
    }
}

public struct LampEvent {
    public let time: TimeInterval
    public let id: String
    public let state: LampState
    // Small, versioned, tab-delimited messages written atomically by the hook.
    public init?(_ text: String, now: TimeInterval, started: TimeInterval) {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count == 4, parts[0] == "1", let time = Double(parts[1]), time.isFinite,
              let state = LampState(rawValue: String(parts[3])),
              time >= started, time <= now + 5,
              now - time <= (state.isCompletion ? 10 : 1800) else { return nil }
        self.time = time; self.id = String(parts[2]); self.state = state
    }
}

public struct StateMachine {
    public private(set) var state: LampState = .idle
    public private(set) var deadline: TimeInterval?
    public private(set) var lastID: String?
    private var lastTime: TimeInterval = 0
    public init() {}
    @discardableResult public mutating func accept(_ event: LampEvent, now: TimeInterval) -> Bool {
        guard event.id != lastID, event.time >= lastTime else { return false }
        lastID = event.id; lastTime = event.time
        let changed = state != event.state || event.state.isCompletion
        state = event.state
        deadline = state.isCompletion ? now + 3 : event.time + 1800
        return changed
    }
    @discardableResult public mutating func tick(now: TimeInterval) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        let changed = state != .idle && state != .off
        state = .idle
        return changed
    }
    public mutating func reset() { state = .idle; deadline = nil }
}

public struct Backoff {
    private var attempt = 0
    public init() {}
    public mutating func next() -> Double {
        let delay = min(60, pow(2, Double(attempt)))
        attempt = min(attempt + 1, 6)
        return delay
    }
    public mutating func reset() { attempt = 0 }
}
