// Standalone assertions keep tests runnable with Command Line Tools, without XCTest/Xcode.
import Foundation
import LampCore
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "Expected \(b), got \(a)", file: file, line: line)
}
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value, "Expected false", file: file, line: line)
}
func XCTAssertNil<T>(_ value: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition(value == nil, "Expected nil: \(message)", file: file, line: line)
}
let tests = StateTests()
tests.testPalettesAndOff()
tests.testNewWorkCancelsCompletionWithoutWritingMailbox()
tests.testDoneExpiresAndRepeatedEventCannotReplay()
tests.testRejectMalformedStaleFutureAndPrelaunchEvents()
tests.testRepeatedWorkingRefreshesLeaseAndOldEventCannotWin()
tests.testReconnectBackoffIsBoundedAndResettable()
print("PASS: 6 test groups — palettes, completion races, replay, stale input, expiry, retry")
for path in CommandLine.arguments.dropFirst() {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
    guard let root = json as? [String: Any], let hooks = root["hooks"] as? [String: [[String: Any]]] else {
        fatalError("Invalid hooks example: \(path)")
    }
    for groups in hooks.values {
        for group in groups {
            guard let handlers = group["hooks"] as? [[String: Any]] else { fatalError("Missing handlers") }
            for handler in handlers {
                guard let command = handler["command"] as? String,
                      let state = command.split(separator: " ").last,
                      LampState(rawValue: String(state)) != nil else { fatalError("Unknown lamp command") }
            }
        }
    }
    print("PASS: hooks example \(path)")
}
