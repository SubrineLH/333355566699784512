import SwiftUI

// iOS 14 has no `TextRenderer`, so the per-glyph reveal cannot be reproduced.
// The welcome copy keeps the same call sites and falls back to a whole-text
// fade, which is what the shipping client does anyway when the reveal is
// switched off (`ReplyPresentation.plainFadeKey`).

private struct StreamingGlyphAnimationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var streamingGlyphAnimation: Bool {
        get { self[StreamingGlyphAnimationKey.self] }
        set { self[StreamingGlyphAnimationKey.self] = newValue }
    }
}

/// Builds a `Text` whose underlined span can be laid out before it is revealed.
/// `Text` concatenation is available on iOS 13, so the whole string takes part
/// in line breaking from the first frame.
enum StreamingTextPhrase {
    static func text(_ text: String, underlined: Range<String.Index>? = nil) -> Text {
        guard let underlined, !underlined.isEmpty else {
            return Text(verbatim: text)
        }
        let prefix = String(text[text.startIndex..<underlined.lowerBound])
        let middle = String(text[underlined])
        let suffix = String(text[underlined.upperBound...])
        return Text(verbatim: prefix) + Text(verbatim: middle).underline() + Text(verbatim: suffix)
    }
}

struct StreamingGlyphReveal: ViewModifier {
    let ledger: GlyphRevealLedger
    let revealedPhraseCount: Int

    @Environment(\.streamingGlyphAnimation) private var animationEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var lastRevealedCount = 0

    private var shouldFade: Bool { animationEnabled && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || !shouldFade ? 1 : 0)
            .onAppear { revealIfNeeded() }
            .onChange(of: revealedPhraseCount) { count in
                guard count != lastRevealedCount else { return }
                lastRevealedCount = count
                revealIfNeeded()
            }
    }

    private func revealIfNeeded() {
        // Without the renderer there is no per-glyph progress to drive, so the
        // whole run fades in once. `ledger` stays owned by the caller.
        _ = ledger
        guard shouldFade else {
            isVisible = true
            return
        }
        guard !isVisible else { return }
        withAnimation(.easeOut(duration: ReplyPresentation.revealSeconds)) {
            isVisible = true
        }
    }
}
