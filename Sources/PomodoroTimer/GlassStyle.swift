import AppKit
import SwiftUI

enum FocusStyle {
    static let accent = Color(nsColor: NSColor(name: "PomodoroSilver") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.88, green: 0.90, blue: 0.92, alpha: 1)
            : NSColor(srgbRed: 0.22, green: 0.24, blue: 0.27, alpha: 1)
    })
}

@MainActor
enum ClearWindowFrame {
    static func install(on window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.titlebarAppearsTransparent = !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        guard let container = window.contentView?.superview,
              !container.subviews.contains(where: { $0 is DragFrameView }) else { return }
        let height = max(22, window.frame.height - window.contentLayoutRect.maxY)
        let origin = container.isFlipped ? container.bounds.minY : container.bounds.maxY - height
        let frame = DragFrameView(frame: NSRect(x: 0, y: origin, width: container.bounds.width, height: height))
        frame.autoresizingMask = [.width, container.isFlipped ? .maxYMargin : .minYMargin]
        container.addSubview(frame, positioned: .above, relativeTo: nil)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0.6
        container.layer?.borderColor = NSColor(white: 0.95, alpha: 0.18).cgColor
    }

    final class DragFrameView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window?.standardWindowButton(kind),
                   convert(button.bounds, from: button).insetBy(dx: -3, dy: -3).contains(local) {
                    if button.isEnabled { button.mouseDown(with: event) }
                    return
                }
            }
            window?.performDrag(with: event)
        }
        override func draw(_ dirtyRect: NSRect) {
            (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                ? NSColor.windowBackgroundColor : NSColor(white: 0.12, alpha: 0.02)).setFill()
            bounds.fill()
        }
    }
}

struct TimerControlStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.025), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.18), lineWidth: 0.6))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct SmokyGlassBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if !reduceTransparency { NativeGlass() }
            LinearGradient(colors: scheme == .dark
                ? [Color(red: 0.19, green: 0.20, blue: 0.22), Color(red: 0.09, green: 0.10, blue: 0.12)]
                : [Color(red: 0.93, green: 0.94, blue: 0.95), Color(red: 0.83, green: 0.85, blue: 0.87)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(reduceTransparency ? 1 : 0.055)
            if !reduceTransparency {
                Ellipse().fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.12))
                    .frame(width: 300, height: 180).blur(radius: 65).offset(x: -90, y: -230).opacity(0.2)
                Ellipse().fill(Color.white.opacity(0.035))
                    .frame(width: 260, height: 220).blur(radius: 65).offset(x: 120, y: 190).opacity(0.2)
            }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct NativeGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = GlassView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = 0.12
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    final class GlassView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
