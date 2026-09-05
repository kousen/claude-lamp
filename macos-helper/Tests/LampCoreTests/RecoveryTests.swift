import LampCore

final class RecoveryTests {
    func readyConnection(_ now: Double = 0) -> ConnectionRecovery {
        var r = ConnectionRecovery()
        r.setAvailability(.poweredOn)
        XCTAssertTrue(r.beginScan(now: now))
        XCTAssertTrue(r.discovered(now: now))
        XCTAssertTrue(r.connected(now: now))
        XCTAssertTrue(r.ready())
        return r
    }
    func testUnavailableBluetoothNeverSchedulesAccess() {
        for availability in [ConnectionRecovery.Availability.unknown, .unauthorized, .poweredOff, .unsupported] {
            var r = ConnectionRecovery(); r.setAvailability(availability)
            XCTAssertFalse(r.beginScan(now: 0)); XCTAssertNil(r.failed(now: 0))
            XCTAssertFalse(r.retryDue(now: 10_000)); XCTAssertNil(r.operationDeadline)
            XCTAssertFalse(r.discovered(now: 1)); XCTAssertFalse(r.connected(now: 2))
            XCTAssertFalse(r.ready())
        }
    }
    func testPermissionGrantedAfterDenialCanConnect() {
        var r = ConnectionRecovery(); r.setAvailability(.unauthorized)
        XCTAssertFalse(r.beginScan(now: 0))
        r.setAvailability(.poweredOn)
        XCTAssertTrue(r.beginScan(now: 1)); XCTAssertTrue(r.discovered(now: 2))
        XCTAssertTrue(r.connected(now: 3)); XCTAssertTrue(r.ready())
        XCTAssertEqual(r.phase, .ready)
    }
    func testDiscoveryAndHandshakeDeadlines() {
        var r = ConnectionRecovery(); r.setAvailability(.poweredOn)
        XCTAssertTrue(r.beginScan(now: 0)); XCTAssertFalse(r.beginScan(now: 1))
        XCTAssertFalse(r.timedOut(now: 9.99)); XCTAssertTrue(r.timedOut(now: 10))
        XCTAssertEqual(r.failed(now: 10), 1)
        XCTAssertFalse(r.retryDue(now: 10.99)); XCTAssertTrue(r.retryDue(now: 11))
        XCTAssertFalse(r.beginScan(now: 10.99)); XCTAssertTrue(r.beginScan(now: 11))
        XCTAssertTrue(r.discovered(now: 12))
        XCTAssertFalse(r.timedOut(now: 26.99)); XCTAssertTrue(r.timedOut(now: 27))
        XCTAssertTrue(r.connected(now: 26))
        XCTAssertFalse(r.timedOut(now: 35.99)); XCTAssertTrue(r.timedOut(now: 36))
        XCTAssertTrue(r.ready()); XCTAssertFalse(r.timedOut(now: 1000))
    }
    func testDisconnectRetriesOnceAndSuccessResetsBackoff() {
        var r = readyConnection()
        XCTAssertEqual(r.failed(now: 10), 1)
        XCTAssertFalse(r.beginScan(now: 10.5)); XCTAssertTrue(r.beginScan(now: 11))
        XCTAssertFalse(r.retryDue(now: 100)); XCTAssertFalse(r.beginScan(now: 12))
        XCTAssertEqual(r.failed(now: 21), 2)
        XCTAssertTrue(r.beginScan(now: 23)); XCTAssertTrue(r.discovered(now: 24))
        XCTAssertTrue(r.connected(now: 25)); XCTAssertTrue(r.ready())
        XCTAssertEqual(r.failed(now: 30), 1)
    }
    func testBluetoothOffCancelsPendingRetryAndRecovers() {
        var r = readyConnection(); _ = r.failed(now: 0)
        r.setAvailability(.poweredOff)
        XCTAssertNil(r.retryAt); XCTAssertFalse(r.beginScan(now: 100))
        r.setAvailability(.poweredOn)
        XCTAssertTrue(r.beginScan(now: 101))
    }
    func testSleepCancelsRetryAndLateDiscovery() {
        var r = readyConnection(); _ = r.failed(now: 10)
        r.setSleeping(true)
        XCTAssertFalse(r.retryDue(now: 100)); XCTAssertFalse(r.beginScan(now: 100))
        XCTAssertFalse(r.discovered(now: 100)); XCTAssertFalse(r.connected(now: 100))
        r.setSleeping(false)
        XCTAssertTrue(r.beginScan(now: 101))
        XCTAssertEqual(r.failed(now: 111), 1)
    }
    func testPausePersistsAcrossSleepAndBluetoothToggle() {
        var r = readyConnection(); r.setPaused(true); r.setSleeping(true)
        r.setAvailability(.poweredOff); r.setSleeping(false); r.setAvailability(.poweredOn)
        XCTAssertFalse(r.canConnect); XCTAssertFalse(r.beginScan(now: 100))
        r.setPaused(false); XCTAssertTrue(r.beginScan(now: 101))
    }
    func testWritesAreSerializedAndPaced() {
        var q = LampWriteQueue(); q.replace(with: LampState.working.commands)
        let first = q.next(now: 0)!
        XCTAssertEqual(first.command, "LEDON"); XCTAssertNil(q.next(now: 1))
        XCTAssertTrue(q.acknowledge(first.id, now: 1))
        XCTAssertNil(q.next(now: 1.119))
        XCTAssertEqual(q.next(now: 1.121)?.command, "BRIGH025")
    }
    func testNewStateSupersedesInFlightColorSequence() {
        var q = LampWriteQueue(); q.replace(with: LampState.done.commands)
        let old = q.next(now: 0)!
        q.replace(with: LampState.codexWorking.commands)
        XCTAssertNil(q.next(now: 1)); XCTAssertTrue(q.acknowledge(old.id, now: 1))
        var transmitted: [String] = []
        for time in [2.0, 3.0, 4.0] {
            let w = q.next(now: time)!; transmitted.append(w.command)
            XCTAssertTrue(q.acknowledge(w.id, now: time))
        }
        XCTAssertEqual(transmitted, ["LEDON", "BRIGH025", "COLOR000220255"])
        XCTAssertNil(q.next(now: 5))
    }
    func testLateAcknowledgementCannotReleaseNewConnectionWrite() {
        var q = LampWriteQueue(); q.replace(with: LampState.working.commands)
        let old = q.next(now: 0)!
        q.clear(); q.replace(with: LampState.codexInput.commands)
        let current = q.next(now: 1)!
        XCTAssertFalse(q.acknowledge(old.id, now: 2))
        XCTAssertEqual(q.active, current); XCTAssertNil(q.next(now: 3))
        XCTAssertTrue(q.acknowledge(current.id, now: 3))
    }
    func testWriteTimeoutDropsOldCommandsAndRetriesLatestState() {
        var r = readyConnection(); var q = LampWriteQueue()
        q.replace(with: LampState.working.commands); _ = q.next(now: 10)
        XCTAssertFalse(q.timedOut(now: 14.99)); XCTAssertTrue(q.timedOut(now: 15))
        q.clear(); XCTAssertEqual(r.failed(now: 15), 1)
        XCTAssertNil(q.next(now: 100)); XCTAssertFalse(q.timedOut(now: 100))
        XCTAssertTrue(r.beginScan(now: 16)); XCTAssertTrue(r.discovered(now: 17))
        XCTAssertTrue(r.connected(now: 18)); XCTAssertTrue(r.ready())
        q.replace(with: LampState.codexInput.commands)
        XCTAssertEqual(q.next(now: 19)?.command, "LEDON")
    }
    func testPermissionRevokedDuringWriteStopsRetries() {
        var r = readyConnection(); var q = LampWriteQueue()
        q.replace(with: LampState.input.commands); let w = q.next(now: 0)!
        r.setAvailability(.unauthorized); q.clear()
        XCTAssertFalse(q.acknowledge(w.id, now: 1)); XCTAssertNil(q.next(now: 10))
        XCTAssertNil(r.failed(now: 10)); XCTAssertFalse(r.retryDue(now: 100))
    }
    func testInterruptedWriteErrorRestartsWholeLatestSequence() {
        var r = readyConnection(); var q = LampWriteQueue()
        q.replace(with: LampState.working.commands)
        let on = q.next(now: 0)!; q.acknowledge(on.id, now: 0)
        XCTAssertEqual(q.next(now: 1)?.command, "BRIGH025")
        // GATT reports an error midway through a batch: drop the batch and disconnect.
        q.clear(); XCTAssertEqual(r.failed(now: 2), 1)
        XCTAssertTrue(r.beginScan(now: 3)); XCTAssertTrue(r.discovered(now: 4))
        XCTAssertTrue(r.connected(now: 5)); XCTAssertTrue(r.ready())
        q.replace(with: LampState.codexWorking.commands)
        var sent: [String] = []
        for time in [6.0, 7.0, 8.0] {
            let w = q.next(now: time)!; sent.append(w.command); q.acknowledge(w.id, now: time)
        }
        XCTAssertEqual(sent, ["LEDON", "BRIGH025", "COLOR000220255"])
    }
    func testWakeExpiresOldCompletionButPreservesRecentWork() {
        for (state, wake, expected) in [("codex-done", 110.0, LampState.idle),
                                       ("working", 110.0, .working),
                                       ("input", 2000.0, .idle)] {
            var m = StateMachine(); var r = readyConnection()
            let e = LampEvent("1\t100\tx\t\(state)", now: 100, started: 90)!
            m.accept(e, now: 100); r.setSleeping(true)
            r.setSleeping(false); m.tick(now: wake)
            XCTAssertTrue(r.beginScan(now: wake)); XCTAssertTrue(r.discovered(now: wake))
            XCTAssertTrue(r.connected(now: wake)); XCTAssertTrue(r.ready())
            var q = LampWriteQueue(); q.replace(with: m.state.commands)
            XCTAssertEqual(m.state, expected)
            XCTAssertEqual(q.next(now: wake)?.command, expected.commands.first)
        }
    }
    func testQuitPreemptsColorAndNeverRetries() {
        var r = readyConnection(); var q = LampWriteQueue()
        q.replace(with: LampState.done.commands)
        let active = q.next(now: 0)!
        r.stop(); q.replace(with: ["LEDOFF"])
        q.acknowledge(active.id, now: 0.1)
        XCTAssertNil(q.next(now: 0.2))
        let off = q.next(now: 0.3)!
        XCTAssertEqual(off.command, "LEDOFF"); q.acknowledge(off.id, now: 0.3)
        XCTAssertNil(q.next(now: 1)); XCTAssertNil(r.failed(now: 1))
        r.setAvailability(.poweredOn); r.setSleeping(false); r.setPaused(false)
        XCTAssertFalse(r.beginScan(now: 100))
    }
}
