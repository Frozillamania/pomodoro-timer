import XCTest
@testable import PomodoroTimer

final class TimerTests: XCTestCase {
    func testDialClockwiseAndInvalidCoordinates() {
        XCTAssertEqual(FocusTimer.minutesForDial(x: 1, y: 0, scaleMinutes: 60), 15)
        XCTAssertEqual(FocusTimer.minutesForDial(x: 0, y: -1, scaleMinutes: 60), 30)
        XCTAssertEqual(FocusTimer.minutesForDial(x: -1, y: 0, scaleMinutes: 60), 45)
        XCTAssertEqual(FocusTimer.minutesForDial(x: 0, y: 1, scaleMinutes: 60), 1)
        XCTAssertEqual(FocusTimer.minutesForDial(x: .nan, y: 0, scaleMinutes: 60), 1)
    }

    func testPauseResumeAndBothPhaseTransitions() {
        let now = Date()
        var timer = FocusTimer(remaining: 120)
        timer.start(at: now)
        timer.pause(at: now.addingTimeInterval(20))
        XCTAssertNil(timer.deadline)
        XCTAssertEqual(timer.remaining, 100)
        timer.start(at: now.addingTimeInterval(40))
        XCTAssertFalse(timer.reconcile(at: now.addingTimeInterval(139), focusMinutes: 25, breakMinutes: 5))
        XCTAssertTrue(timer.reconcile(at: now.addingTimeInterval(140), focusMinutes: 25, breakMinutes: 5))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(timer.remaining, 300)
        XCTAssertNil(timer.deadline)
        timer.start(at: now.addingTimeInterval(140))
        XCTAssertTrue(timer.reconcile(at: now.addingTimeInterval(440), focusMinutes: 25, breakMinutes: 5))
        XCTAssertEqual(timer.phase, .focus)
        XCTAssertEqual(timer.remaining, 1500)
    }

    func testSetDurationClampsByPhaseAndPauses() {
        var state = TimerState()
        state.timer.start(at: Date())
        state.setTimer(minutes: 999)
        XCTAssertEqual(state.focusMinutes, 180)
        XCTAssertNil(state.timer.deadline)
        state.timer.phase = .rest
        state.setTimer(minutes: 999)
        XCTAssertEqual(state.breakMinutes, 60)
        state.setTimer(minutes: -1)
        XCTAssertEqual(state.timer.remaining, 60)
        state.timer.reset(focusMinutes: state.focusMinutes)
        XCTAssertEqual(state.timer.phase, .focus)
        XCTAssertEqual(state.timer.remaining, 10800)
    }

    func testRejectInvalidStateBeforeSaving() throws {
        var state = TimerState()
        state.version = 2
        XCTAssertThrowsError(try state.validate())
        state = TimerState()
        state.timer.remaining = .infinity
        XCTAssertThrowsError(try state.validate())
        state.timer.remaining = -1
        XCTAssertThrowsError(try state.validate())
        state.timer.remaining = 1500
        state.timer.deadline = Date().addingTimeInterval(20000)
        XCTAssertThrowsError(try state.validate())
        state.timer.deadline = nil
        state.breakMinutes = 0
        XCTAssertThrowsError(try state.validate())
    }

    func testAtomicPersistenceAndCorruptFilePreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = StateStore(directory: directory)
        XCTAssertEqual(try store.load(), TimerState())
        var state = TimerState()
        state.setTimer(minutes: 15)
        state.timer.start(at: Date())
        state.timerBlinkEnabled = true
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: store.file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.file), corrupt)
    }

    func testBlinkHasBoundedDurationAndReduceMotionFallback() {
        let now = Date()
        let cue = CompletionBlink(startedAt: now)
        XCTAssertEqual(cue.opacity(at: now.addingTimeInterval(1), reduceMotion: false), 0.35)
        XCTAssertEqual(cue.opacity(at: now.addingTimeInterval(1), reduceMotion: true), 1)
        XCTAssertFalse(cue.isActive(at: now.addingTimeInterval(6)))
        XCTAssertFalse(cue.isActive(at: now.addingTimeInterval(-1)))
    }

    func testModelPersistsControlsAndSilentlyReconcilesRelaunch() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = TimerModel(directory: directory, startTicker: false)
            model.setTimer(minutes: 15)
            model.setTimerBlink(true)
            model.toggleTimer()
            XCTAssertNotNil(model.state.timer.deadline)
            model.toggleTimer()
            XCTAssertNil(model.state.timer.deadline)
            let relaunched = TimerModel(directory: directory, startTicker: false)
            XCTAssertTrue(relaunched.state.timerBlinkEnabled)
            XCTAssertEqual(relaunched.state.focusMinutes, 15)
            var expired = relaunched.state
            expired.timer.deadline = Date().addingTimeInterval(-10)
            try StateStore(directory: directory).save(expired)
            let recovered = TimerModel(directory: directory, startTicker: false)
            XCTAssertEqual(recovered.state.timer.phase, .rest)
            XCTAssertNil(recovered.completionBlink)
            XCTAssertNil(recovered.state.timer.deadline)
            XCTAssertEqual(try StateStore(directory: directory).load(), recovered.state)
        }
    }

    func testModelCorruptFileIsReadOnlyAndSaveFailureKeepsState() async throws {
        try await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = StateStore(directory: directory)
            let corrupt = Data("bad data".utf8)
            try corrupt.write(to: store.file)
            let model = TimerModel(directory: directory, startTicker: false)
            XCTAssertTrue(model.readOnly)
            model.setTimer(minutes: 10)
            XCTAssertEqual(try Data(contentsOf: store.file), corrupt)
            try FileManager.default.removeItem(at: store.file)
            let valid = TimerModel(directory: directory, startTicker: false)
            try FileManager.default.createDirectory(at: store.file, withIntermediateDirectories: true)
            valid.setTimer(minutes: 10)
            XCTAssertEqual(valid.state.focusMinutes, 25)
            XCTAssertNotNil(valid.message)
        }
    }
}
