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
let recoveryTests = RecoveryTests()
let recoveryCases: [(String, () -> Void)] = [
    ("unavailable Bluetooth", recoveryTests.testUnavailableBluetoothNeverSchedulesAccess),
    ("permission granted", recoveryTests.testPermissionGrantedAfterDenialCanConnect),
    ("connection deadlines", recoveryTests.testDiscoveryAndHandshakeDeadlines),
    ("disconnect retry", recoveryTests.testDisconnectRetriesOnceAndSuccessResetsBackoff),
    ("Bluetooth off/on", recoveryTests.testBluetoothOffCancelsPendingRetryAndRecovers),
    ("sleep cancels retry", recoveryTests.testSleepCancelsRetryAndLateDiscovery),
    ("pause survives wake", recoveryTests.testPausePersistsAcrossSleepAndBluetoothToggle),
    ("serialized writes", recoveryTests.testWritesAreSerializedAndPaced),
    ("new state wins", recoveryTests.testNewStateSupersedesInFlightColorSequence),
    ("late acknowledgement", recoveryTests.testLateAcknowledgementCannotReleaseNewConnectionWrite),
    ("write timeout", recoveryTests.testWriteTimeoutDropsOldCommandsAndRetriesLatestState),
    ("permission revoked during write", recoveryTests.testPermissionRevokedDuringWriteStopsRetries),
    ("interrupted write error", recoveryTests.testInterruptedWriteErrorRestartsWholeLatestSequence),
    ("wake state expiry", recoveryTests.testWakeExpiresOldCompletionButPreservesRecentWork),
    ("quit during write", recoveryTests.testQuitPreemptsColorAndNeverRetries)
]
for (name, run) in recoveryCases { run(); print("PASS: \(name)") }
print("PASS: \(recoveryCases.count) recovery tests")
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
