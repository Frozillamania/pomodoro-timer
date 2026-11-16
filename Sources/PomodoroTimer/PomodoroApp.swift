import AppKit
import SwiftUI

@main
struct PomodoroApp: App {
    @StateObject private var model = TimerModel()
    private static let menuIcon: NSImage = {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "timer", accessibilityDescription: "POMODORO Timer") ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    var body: some Scene {
        Window("POMODORO Timer", id: "timer") { TimerView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
        MenuBarExtra {
            TimerMenu(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: Self.menuIcon)
                    .modifier(CompletionCueStyle(cue: model.completionBlink, now: model.now))
                if model.state.timer.deadline != nil { Text(model.countdown).monospacedDigit() }
            }
            .accessibilityLabel("POMODORO Timer, \(model.countdown) remaining")
        }
    }
}

struct TimerMenu: View {
    @ObservedObject var model: TimerModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("\(model.state.timer.phase.rawValue) · \(model.countdown)")
        Button(model.state.timer.deadline == nil ? "Start timer" : "Pause timer") { model.toggleTimer() }
            .disabled(model.readOnly)
        Button("Reset timer") { model.resetTimer() }.disabled(model.readOnly)
        Toggle("Keep on top", isOn: Binding(get: { model.state.alwaysOnTop }, set: { value in
            model.update { $0.alwaysOnTop = value }
        })).disabled(model.readOnly)
        Divider()
        Button("Open timer") { openWindow(id: "timer"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit POMODORO Timer") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct WindowSetup: NSViewRepresentable {
    let pinned: Bool
    func makeNSView(context: Context) -> SetupView { SetupView() }
    func updateNSView(_ view: SetupView, context: Context) {
        view.pinned = pinned
        view.apply()
    }
    final class SetupView: NSView {
        var pinned = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() {
            guard let window else { return }
            window.level = pinned ? .floating : .normal
            window.isReleasedWhenClosed = false
            ClearWindowFrame.install(on: window)
        }
    }
}
