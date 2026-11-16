import SwiftUI

struct CompletionBlink: Equatable {
    let startedAt: Date

    func isActive(at now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed >= 0 && elapsed < 6
    }

    func opacity(at now: Date, reduceMotion: Bool) -> Double {
        guard isActive(at: now), !reduceMotion else { return 1 }
        return Int(now.timeIntervalSince(startedAt)) % 2 == 0 ? 1 : 0.35
    }
}

struct CompletionCueStyle: ViewModifier {
    let cue: CompletionBlink?
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(cue?.opacity(at: now, reduceMotion: reduceMotion) ?? 1)
            .overlay {
                if reduceMotion, cue?.isActive(at: now) == true {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.primary, lineWidth: 1.2)
                        .padding(-3).accessibilityHidden(true)
                }
            }
    }
}
