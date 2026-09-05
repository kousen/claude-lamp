import LampCore

final class StateTests {
    func event(_ state: String, _ id: String = "a", _ time: Double = 100) -> LampEvent {
        LampEvent("1\t\(time)\t\(id)\t\(state)", now: time, started: 90)!
    }
    func testPalettesAndOff() {
        XCTAssertEqual(LampState.working.commands, ["LEDON", "BRIGH025", "COLOR000060255"])
        XCTAssertEqual(LampState.codexWorking.commands, ["LEDON", "BRIGH025", "COLOR000220255"])
        XCTAssertEqual(LampState.input.commands.last, "COLOR200000255")
        XCTAssertEqual(LampState.codexInput.commands.last, "COLOR255120000")
        XCTAssertEqual(LampState.done.commands.last, "COLOR000255060")
        XCTAssertEqual(LampState.codexDone.commands.last, "COLOR255255255")
        XCTAssertEqual(LampState.off.commands, ["LEDOFF"])
    }
    func testNewWorkCancelsCompletionWithoutWritingMailbox() {
        var m = StateMachine()
        XCTAssertTrue(m.accept(event("done"), now: 100))
        XCTAssertTrue(m.accept(event("codex-working", "b", 101), now: 101))
        XCTAssertFalse(m.tick(now: 104))
        XCTAssertEqual(m.state, .codexWorking)
    }
    func testDoneExpiresAndRepeatedEventCannotReplay() {
        var m = StateMachine(); let e = event("codex-done")
        XCTAssertTrue(m.accept(e, now: 100))
        XCTAssertFalse(m.tick(now: 102.9)); XCTAssertTrue(m.tick(now: 103))
        XCTAssertFalse(m.accept(e, now: 104)); XCTAssertEqual(m.state, .idle)
        XCTAssertTrue(m.accept(event("codex-done", "b", 105), now: 105))
    }
    func testRejectMalformedStaleFutureAndPrelaunchEvents() {
        for text in ["", "working", "1\t100\tx\tunknown", "1\tnan\tx\tidle", "1\t107\tx\tidle",
                     "1\t89\tx\tidle", "1\t89\tx\tdone"] {
            XCTAssertNil(LampEvent(text, now: 100, started: 90), text)
        }
        XCTAssertNil(LampEvent("1\t100\tx\tdone", now: 111, started: 90))
    }
    func testRepeatedWorkingRefreshesLeaseAndOldEventCannotWin() {
        var m = StateMachine()
        _ = m.accept(event("working"), now: 100)
        XCTAssertFalse(m.accept(event("working", "b", 110), now: 110))
        XCTAssertFalse(m.accept(event("off", "old", 101), now: 110))
        XCTAssertFalse(m.tick(now: 1900)); XCTAssertTrue(m.tick(now: 1910))
    }
    func testReconnectBackoffIsBoundedAndResettable() {
        var b = Backoff()
        XCTAssertEqual((0..<10).map { _ in b.next() }, [1,2,4,8,16,32,60,60,60,60])
        b.reset(); XCTAssertEqual(b.next(), 1)
    }
}
