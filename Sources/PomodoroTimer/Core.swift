import Foundation

struct FocusTimer: Codable, Equatable {
    enum Phase: String, Codable { case focus = "Focus", rest = "Break" }
    var phase: Phase = .focus
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?

    static func minutesForDial(x: Double, y: Double, scaleMinutes: Int) -> Int {
        guard x.isFinite, y.isFinite else { return 1 }
        var angle = atan2(x, y)
        if angle < 0 { angle += 2 * .pi }
        let scale = max(1, min(180, scaleMinutes))
        return max(1, Int((angle / (2 * .pi) * Double(scale)).rounded()))
    }

    func seconds(at now: Date) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(now) } ?? remaining)
    }

    mutating func start(at now: Date) {
        guard deadline == nil else { return }
        deadline = now.addingTimeInterval(max(1, remaining))
    }

    mutating func pause(at now: Date) {
        remaining = seconds(at: now)
        deadline = nil
    }

    mutating func reset(focusMinutes: Int) {
        phase = .focus
        remaining = TimeInterval(focusMinutes * 60)
        deadline = nil
    }

    @discardableResult
    mutating func reconcile(at now: Date, focusMinutes: Int, breakMinutes: Int) -> Bool {
        guard let deadline, deadline <= now else { return false }
        phase = phase == .focus ? .rest : .focus
        self.deadline = nil
        remaining = TimeInterval((phase == .focus ? focusMinutes : breakMinutes) * 60)
        return true
    }
}

struct TimerState: Codable, Equatable {
    var version = 1
    var timer = FocusTimer()
    var focusMinutes = 25
    var breakMinutes = 5
    var timerSoundEnabled = false
    var timerBlinkEnabled = false
    var alwaysOnTop = false

    mutating func setTimer(minutes: Int) {
        let minutes = max(1, min(timer.phase == .focus ? 180 : 60, minutes))
        if timer.phase == .focus { focusMinutes = minutes } else { breakMinutes = minutes }
        timer.remaining = TimeInterval(minutes * 60)
        timer.deadline = nil
    }

    func validate() throws {
        let maximum = TimeInterval((timer.phase == .focus ? 180 : 60) * 60)
        guard version == 1, (1...180).contains(focusMinutes), (1...60).contains(breakMinutes),
              timer.remaining.isFinite, timer.remaining >= 0, timer.remaining <= maximum,
              timer.deadline.map({ $0.timeIntervalSinceNow.isFinite && $0.timeIntervalSinceNow <= maximum }) ?? true else {
            throw StorageError.invalidState
        }
    }
}

enum StorageError: LocalizedError {
    case invalidState
    var errorDescription: String? { "Saved state is invalid or from an unsupported version. Original file was preserved." }
}

struct StateStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("state.json") }
    func load() throws -> TimerState {
        guard FileManager.default.fileExists(atPath: file.path) else { return TimerState() }
        let state = try JSONDecoder().decode(TimerState.self, from: Data(contentsOf: file))
        try state.validate()
        return state
    }
    func save(_ state: TimerState) throws {
        try state.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
