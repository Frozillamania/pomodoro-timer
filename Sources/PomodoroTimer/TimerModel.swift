import AppKit
import SwiftUI

@MainActor
final class TimerModel: ObservableObject {
    @Published private(set) var state = TimerState()
    @Published private(set) var now = Date()
    @Published private(set) var readOnly = false
    @Published private(set) var message: String?
    @Published var showError = false
    @Published private(set) var completionBlink: CompletionBlink?
    private let store: StateStore
    private var ticker: Timer?
    private let completionSound = NSSound(named: "Glass")

    init(directory: URL? = nil, startTicker: Bool = true) {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--data-dir")
        let invalidPath = index.map { !args.indices.contains($0 + 1) || args[$0 + 1].hasPrefix("--") } ?? false
        let path = index.flatMap { !invalidPath ? URL(fileURLWithPath: args[$0 + 1], isDirectory: true) : nil }
        store = StateStore(directory: directory ?? path ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("POMODORO Timer"))
        do {
            guard !invalidPath else { throw StorageError.invalidState }
            state = try store.load()
            if state.timer.reconcile(at: now, focusMinutes: state.focusMinutes, breakMinutes: state.breakMinutes) {
                try store.save(state)
            }
        } catch {
            readOnly = true
            message = "Timer data could not be opened. The original file was preserved; changes are disabled. \(error.localizedDescription)"
        }
        if startTicker {
            ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        }
    }

    deinit { ticker?.invalidate() }

    var countdown: String {
        let seconds = Int(state.timer.seconds(at: now).rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    var completionAlertActive: Bool { completionBlink?.isActive(at: now) == true }

    @discardableResult
    func update(_ edit: (inout TimerState) -> Void) -> Bool {
        guard !readOnly else { return false }
        var candidate = state
        edit(&candidate)
        do {
            try store.save(candidate)
            state = candidate
            return true
        } catch {
            message = "Could not save timer changes: \(error.localizedDescription)"
            showError = true
            return false
        }
    }

    func tick() {
        now = Date()
        guard !readOnly else { return }
        var candidate = state
        guard candidate.timer.reconcile(at: now, focusMinutes: candidate.focusMinutes, breakMinutes: candidate.breakMinutes),
              update({ $0 = candidate }) else { return }
        if state.timerSoundEnabled, completionSound?.play() != true { NSSound.beep() }
        completionBlink = state.timerBlinkEnabled ? CompletionBlink(startedAt: now) : nil
    }

    func toggleTimer() {
        stopAlert()
        let wasRunning = state.timer.deadline != nil
        tick()
        if wasRunning, state.timer.deadline == nil { return }
        update {
            if $0.timer.deadline == nil { $0.timer.start(at: now) }
            else { $0.timer.pause(at: now) }
        }
    }
    func resetTimer() {
        stopAlert()
        update { $0.timer.reset(focusMinutes: $0.focusMinutes) }
    }
    func setTimer(minutes: Int) {
        stopAlert()
        update { $0.setTimer(minutes: minutes) }
    }
    func setTimerSound(_ enabled: Bool) {
        if update({ $0.timerSoundEnabled = enabled }), !enabled { completionSound?.stop() }
    }
    func setTimerBlink(_ enabled: Bool) {
        if update({ $0.timerBlinkEnabled = enabled }), !enabled { completionBlink = nil }
    }
    private func stopAlert() {
        completionSound?.stop()
        completionBlink = nil
    }
}
