import SwiftUI
import UIKit

// The three block widgets the Markdown renderer hands off to. They replace
// Textual's table and image attachments, neither of which can run on iOS 14.

// MARK: - Code block

struct ChatMarkdownCodeBlock<Code: View>: View {
    let code: String
    let language: String?
    let content: Code

    @State private var copied = false

    init(code: String, language: String? = nil, @ViewBuilder content: () -> Code) {
        self.code = code
        self.language = language
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let language, !language.isEmpty {
                    Text(verbatim: language)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: copied ? "Copied" : "Copy code"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                content
            }
        }
        .background(CompatPalette.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: copied) { value in
            guard value else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        }
    }
}

// MARK: - Table

struct ChatMarkdownTable: View {
    let header: [String]
    let rows: [[String]]
    let alignments: [CompatTableAlignment]

    private let columnWidth: CGFloat = 180

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(header, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    row(cells, isHeader: false)
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .background(CompatPalette.secondarySystemBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                let alignment = index < alignments.count ? alignments[index] : .leading
                CompatAttributedText(
                    attributed: ChatMarkdownStyle.attributed(
                        cell,
                        font: isHeader
                            ? UIFont.preferredFont(forTextStyle: .callout)
                            : UIFont.preferredFont(forTextStyle: .callout)
                    )
                )
                .frame(width: columnWidth, alignment: frameAlignment(alignment))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func frameAlignment(_ alignment: CompatTableAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Image

struct ChatMarkdownImage: View {
    let urlString: String
    let description: String

    @State private var showsPreview = false

    var body: some View {
        CompatAsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 420, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { showsPreview = true }
                    .sheet(isPresented: $showsPreview) {
                        ChatMarkdownImagePreview(urlString: urlString, description: description)
                    }
            case .failure:
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text(verbatim: description.isEmpty ? "Image unavailable" : description)
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(10)
                .background(CompatPalette.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(CompatPalette.secondarySystemBackground)
            .frame(width: 240, height: 160)
            .overlay(ProgressView())
    }
}

struct ChatMarkdownImagePreview: View {
    let urlString: String
    let description: String

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        CompatPlainNavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                CompatAsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Text(verbatim: "Image unavailable")
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationBarTitle(Text(verbatim: description), displayMode: .inline)
            .navigationBarItems(
                trailing: Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text(verbatim: "Done")
                }
            )
        }
    }
}
