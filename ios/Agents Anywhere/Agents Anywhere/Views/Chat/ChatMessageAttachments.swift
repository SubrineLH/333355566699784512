import SwiftUI
import UIKit

struct ChatMessageAttachments: View {
    let files: [ChatMessageAttachment]
    let onOpen: (V2AttachmentContent) -> Void
    let loadThumbnail: (V2AttachmentContent) async throws -> Data?
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            ForEach(files) { file in
                if file.content.isImage {
                    ChatMessageImage(file: file, onOpen: onOpen, loadThumbnail: loadThumbnail)
                } else {
                    Button { onOpen(file.content) } label: {
                        HStack(spacing: 12) {
                            AppSymbol(AppFileSymbol.name(for: file.content.name ?? ""), size: 24).frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.content.name ?? L("附件")).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(description(file.content)).font(.caption).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            AppSymbol("arrow.up.right", size: 14).foregroundColor(.secondary)
                        }.padding(12).frame(maxWidth: 320, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.quaternaryLabel).opacity(0.6)))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func description(_ file: V2AttachmentContent) -> String {
        let ext = ((file.name ?? "") as NSString).pathExtension.uppercased()
        return [ext.isEmpty ? L("文件") : ext, file.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ChatMessageImage: View {
    let file: ChatMessageAttachment
    let onOpen: (V2AttachmentContent) -> Void
    let loadThumbnail: (V2AttachmentContent) async throws -> Data?
    @State private var image: UIImage?
    @State private var visible = false
    @State private var failed = false
    @State private var retry = 0

    var body: some View {
        Button {
            if failed && image == nil { failed = false; retry += 1 }
            else { onOpen(file.content) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.quaternaryLabel).opacity(0.6))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if failed {
                    Label(L("轻点重试预览"), appSymbol: "arrow.clockwise").font(.caption).foregroundColor(.secondary)
                } else {
                    ProgressView().progressViewStyle(.circular)
                }
            }
            // Fixed preview footprint: decoding or switching from local bytes
            // to a remote thumbnail cannot move the surrounding conversation.
            .aspectRatio(4.0 / 3.0, contentMode: .fit).frame(maxWidth: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).accessibilityLabel(file.content.name ?? L("图片附件"))
        .onAppear { if image == nil, let data = file.previewData { image = UIImage(data: data) } }
        // The row is built lazily by the timeline's lazy stack, so its first
        // appearance is the iOS 14 stand-in for becoming visible.
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .compatTask(id: Request(visible: visible, key: file.content.cacheKey, retry: retry)) {
            guard visible, image == nil else { return }
            do {
                let data = try await loadThumbnail(file.content)
                guard !Task.isCancelled else { return }
                image = data.flatMap { UIImage(data: $0) }
                failed = image == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
    private struct Request: Equatable { let visible: Bool; let key: String; let retry: Int }
}

struct ChatComposerAttachment: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void
    @State private var image: UIImage?
    var body: some View {
        Group {
            if attachment.isImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.quaternaryLabel))
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                    else { AppSymbol("photo").foregroundColor(.secondary) }
                }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    AppSymbol(AppFileSymbol.name(for: attachment.name), size: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.name).font(.caption.weight(.medium)).lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                            .font(.caption2).foregroundColor(.secondary)
                    }.frame(maxWidth: 140, alignment: .leading)
                }.padding(.horizontal, 12).padding(.trailing, 20).frame(height: 72)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.07)))
            }
        }
        .compatOverlay(alignment: .topTrailing) {
            Button(action: onRemove) {
                AppSymbol("xmark.circle.fill").compatSymbolRenderingMode()
                    .foregroundColor(.white).font(.system(size: 19))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).offset(x: 9, y: -9).accessibilityLabel(L("移除 \(attachment.name)"))
        }
        .compatTask(id: attachment.id) {
            if let data = attachment.previewData { image = UIImage(data: data) }
        }
        .accessibilityLabel(attachment.name)
    }
}
