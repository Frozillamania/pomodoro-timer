import AppKit
import SwiftUI

struct TimerView: View {
    @ObservedObject var model: TimerModel
    var body: some View {
        VStack(spacing: 9) {
            VisualTimerDial(model: model)
            if model.message != nil {
                Button { model.showError = true } label: { Image(systemName: "exclamationmark.triangle") }
                    .accessibilityLabel("Show saved-state error")
                    .alert("Timer state", isPresented: $model.showError) {
                        Button("OK", role: .cancel) {}
                    } message: { Text(model.message ?? "") }
            }
            HStack(spacing: 8) {
                Button(model.state.timer.deadline == nil ? "Start" : "Pause") { model.toggleTimer() }
                    .accessibilityLabel(model.state.timer.deadline == nil ? "Start timer" : "Pause timer")
                Button("Reset") { model.resetTimer() }.accessibilityLabel("Reset timer")
            }.disabled(model.readOnly).buttonStyle(TimerControlStyle())
                .shadow(color: Color(white: 0.08).opacity(0.85), radius: 1, y: 1)
            HStack(spacing: 14) {
                Button { model.setTimerSound(!model.state.timerSoundEnabled) } label: {
                    Image(systemName: model.state.timerSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }
                .accessibilityLabel("Timer sound")
                .accessibilityValue(model.state.timerSoundEnabled ? "On" : "Off")
                .help("Completion sound")
                Button { model.setTimerBlink(!model.state.timerBlinkEnabled) } label: {
                    Image(systemName: model.state.timerBlinkEnabled ? "lightbulb" : "lightbulb.slash")
                        .frame(width: 28, height: 24).contentShape(Rectangle())
                }
                .accessibilityLabel("Timer blink")
                .accessibilityValue(model.state.timerBlinkEnabled ? "On" : "Off")
                .help("Blink on completion")
            }
            .font(.system(size: 14)).buttonStyle(.plain).disabled(model.readOnly)
            .shadow(color: Color(white: 0.08).opacity(0.85), radius: 1, y: 1)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 18)
                .overlay(WindowDragGrip().accessibilityHidden(true))
                .accessibilityLabel("Timer move grip")
                .shadow(color: Color(white: 0.08).opacity(0.85), radius: 1, y: 1)
        }
        .padding(14).frame(width: 230)
        .background(SmokyGlassBackground())
        .preferredColorScheme(.dark)
        .background(WindowSetup(pinned: model.state.alwaysOnTop))
    }
}

struct VisualTimerDial: View {
    @ObservedObject var model: TimerModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dialMinutes: Int?
    private var displayTime: String {
        dialMinutes.map { String(format: "%02d:00", $0) } ?? model.countdown
    }
    private var scaleMinutes: Int {
        let duration = model.state.timer.phase == .focus ? model.state.focusMinutes : model.state.breakMinutes
        return max(60, ((duration + 59) / 60) * 60)
    }
    private var remainingSeconds: Double {
        if let minutes = dialMinutes { return Double(minutes * 60) }
        return model.state.timer.seconds(at: model.now)
    }
    private var dialFace: some View {
    Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - 18
        let totalSeconds: Double = Double(scaleMinutes * 60)
        let fraction: Double = min(1, max(0, remainingSeconds / totalSeconds))
        let face = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: face), with: .color(.white.opacity(0.055)))
        var wedge = Path()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                     endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        wedge.closeSubpath()
        context.fill(wedge, with: .color(Color(red: 0.78, green: 0.28, blue: 0.30).opacity(0.68)))
        context.addFilter(.shadow(color: Color(white: 0.08).opacity(0.85), radius: 1, y: 1))
        for minute in 0..<60 {
            let angle: CGFloat = CGFloat(minute) * .pi / 30 - .pi / 2
            let outer = radius - 3
            let inner = outer - (minute % 5 == 0 ? 9 : 4)
            var tick = Path()
            tick.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            tick.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(tick, with: .color(.primary.opacity(0.65)), lineWidth: minute % 5 == 0 ? 1.2 : 0.6)
        }
        for mark in 0..<12 {
            let angle: CGFloat = CGFloat(mark) * .pi / 6 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * (radius + 10), y: center.y + sin(angle) * (radius + 10))
            let minuteLabel = String(mark * scaleMinutes / 12)
                        let label = Text(minuteLabel).font(.system(size: 9, weight: .medium)).foregroundColor(Color.primary)
                        context.draw(label, at: point)
        }
    }
    }
    var body: some View {
            ZStack {
                dialFace
                Text(displayTime).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                .shadow(color: Color(white: 0.08).opacity(0.85), radius: 1, y: 1)
                .padding(10).background(Color(white: 0.12).opacity(reduceTransparency ? 0.9 : 0.12), in: Circle())
                .modifier(CompletionCueStyle(cue: model.completionBlink, now: model.now))
            }
            .frame(width: 180, height: 180)
            .contentShape(Circle())
            .overlay {
                DialMouseInput(preview: { point in
                    guard !model.readOnly else { return }
                    dialMinutes = FocusTimer.minutesForDial(x: Double(point.x - 90),
                                                            y: Double(90 - point.y),
                                                            scaleMinutes: scaleMinutes)
                }, commit: {
                    if let minutes = dialMinutes { model.setTimer(minutes: minutes) }
                    dialMinutes = nil
                })
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Visual timer, \(displayTime) remaining in \(model.state.timer.phase.rawValue)")
            .accessibilityHint("Drag clockwise to set minutes, then press Start")
            .accessibilityValue(model.completionAlertActive ? "Session finished" : "")
            .accessibilityAdjustableAction { direction in
                let current = Int(model.state.timer.seconds(at: model.now) / 60)
                switch direction {
                case .increment: model.setTimer(minutes: current + 1)
                case .decrement: model.setTimer(minutes: current - 1)
                @unknown default: break
                }
            }
    }
}

struct DialMouseInput: NSViewRepresentable {
    let preview: (CGPoint) -> Void
    let commit: () -> Void
    func makeNSView(context: Context) -> MouseView { MouseView() }
    func updateNSView(_ view: MouseView, context: Context) {
        view.preview = preview
        view.commit = commit
    }
    final class MouseView: NSView {
        var preview: (CGPoint) -> Void = { _ in }
        var commit: () -> Void = {}
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { preview(convert(event.locationInWindow, from: nil)) }
        override func mouseDragged(with event: NSEvent) { preview(convert(event.locationInWindow, from: nil)) }
        override func mouseUp(with event: NSEvent) {
            preview(convert(event.locationInWindow, from: nil))
            commit()
        }
    }
}

struct WindowDragGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
