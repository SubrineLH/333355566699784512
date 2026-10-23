import SwiftUI
import UIKit

// Markdown rendering for iOS 14.
//
// iOS 14 cannot build a `Text` from an attributed string, so every inline run
// (bold, italic, code, links) is drawn by a `UITextView` that reports its own
// height. That also gives selection and link tapping for free, which the
// shipping client gets from Textual.

// MARK: - Environment

private struct ChatMarkdownFontKey: EnvironmentKey {
    static let defaultValue: Font = .callout
}

private struct ChatLayoutTraceOwnerKey: EnvironmentKey {
    static let defaultValue = "markdown"
}

extension EnvironmentValues {
    var chatMarkdownFont: Font {
        get { self[ChatMarkdownFontKey.self] }
        set { self[ChatMarkdownFontKey.self] = newValue }
    }

    var chatLayoutTraceOwner: String {
        get { self[ChatLayoutTraceOwnerKey.self] }
        set { self[ChatLayoutTraceOwnerKey.self] = newValue }
    }
}

// MARK: - Text view

/// Draws an attributed string with selection and tappable links.
struct CompatAttributedText: UIViewRepresentable {
    let attributed: NSAttributedString
    var isSelectable = true
    var onOpenURL: ((URL) -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText != attributed {
            view.attributedText = attributed
        }
        view.isSelectable = isSelectable
        context.coordinator.onOpenURL = onOpenURL
    }

    func makeCoordinator() -> Coordinator { Coordinator(onOpenURL: onOpenURL) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: ((URL) -> Void)?

        init(onOpenURL: ((URL) -> Void)?) {
            self.onOpenURL = onOpenURL
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            onOpenURL?(URL)
            return false
        }
    }
}

// MARK: - Styling

enum ChatMarkdownStyle {
    static func bodyFont() -> UIFont { .preferredFont(forTextStyle: .callout) }
    static func codeFont(scale: CGFloat = 0.9) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: .callout).pointSize * scale
        return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func headingFont(level: Int) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .callout).pointSize
        let scale: CGFloat = level == 1 ? 1.5 : level == 2 ? 1.25 : 1.08
        let weight: UIFont.Weight = level <= 2 ? .semibold : .medium
        return UIFont.systemFont(ofSize: base * scale, weight: weight)
    }

    static func attributed(_ text: String, font: UIFont, color: UIColor = .label) -> NSAttributedString {
        CompatMarkdownParser.inline(
            text,
            font: font,
            codeFont: codeFont(),
            color: color,
            secondaryColor: UIColor.secondarySystemFill
        )
    }
}

// MARK: - Blocks

/// One rendered block. Kept `Equatable` so streaming updates only redraw the
/// block whose text actually changed.
struct ChatMarkdownBlockView: View, Equatable {
    let block: CompatMarkdownBlock
    let isStreaming: Bool
    @Environment(\.openURL) private var openURL

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block && lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            CompatAttributedText(
                attributed: ChatMarkdownStyle.attributed(text, font: ChatMarkdownStyle.headingFont(level: level))
            )
            .padding(.top, level == 1 ? 8 : 4)

        case .paragraph(let text):
            CompatAttributedText(
                attributed: ChatMarkdownStyle.attributed(text, font: ChatMarkdownStyle.bodyFont())
            )

        case .quote(let text):
            HStack(spacing: 0) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 3)
                CompatAttributedText(
                    attributed: ChatMarkdownStyle.attributed(
                        text,
                        font: ChatMarkdownStyle.bodyFont(),
                        color: .secondaryLabel
                    )
                )
                .padding(.leading, 10)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .bullet(let depth, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: "•")
                    .foregroundColor(.secondary)
                CompatAttributedText(
                    attributed: ChatMarkdownStyle.attributed(text, font: ChatMarkdownStyle.bodyFont())
                )
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .numbered(let depth, let number, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(verbatim: "\(number).")
                    .foregroundColor(.secondary)
                CompatAttributedText(
                    attributed: ChatMarkdownStyle.attributed(text, font: ChatMarkdownStyle.bodyFont())
                )
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .codeBlock(let language, let code):
            ChatMarkdownCodeBlock(code: code, language: language) {
                Text(verbatim: code)
                    .font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }

        case .table(let header, let rows, let alignments):
            ChatMarkdownTable(header: header, rows: rows, alignments: alignments)

        case .image(let url, let alt):
            ChatMarkdownImage(urlString: url, description: alt)

        case .rule:
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Document

struct ChatMarkdownView: View {
    let text: String
    var isStreaming = false
    var resolvesFileReferences = false

    @State private var blocks: [CompatMarkdownBlock] = []
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                ChatMarkdownBlockView(block: block, isStreaming: isStreaming && index == blocks.count - 1)
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { scheduleParse() }
        .onChange(of: text) { _ in scheduleParse() }
        .onDisappear { parseTask?.cancel() }
    }

    private func scheduleParse() {
        parseTask?.cancel()
        let source = text
        parseTask = Task {
            // Parsing a long reply must not block scroll or drawer gestures.
            let parsed = await Task.detached(priority: .userInitiated) {
                CompatMarkdownParser.parse(source)
            }.value
            guard !Task.isCancelled else { return }
            if blocks != parsed { blocks = parsed }
        }
    }
}

// MARK: - Small leaf views

/// A single attributed run, no block splitting. Used for table cells and
/// anywhere the caller already knows the shape of the text.
struct ChatSelectableText: View {
    let text: String
    var isSelectable = true

    var body: some View {
        CompatAttributedText(
            attributed: ChatMarkdownStyle.attributed(text, font: ChatMarkdownStyle.bodyFont()),
            isSelectable: isSelectable
        )
    }
}
