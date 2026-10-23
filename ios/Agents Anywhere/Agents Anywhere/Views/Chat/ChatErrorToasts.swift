import SwiftUI

/// Non-inline errors float below the header. Paging only changes the visible
/// toast; retry is always an explicit read, never a replay of the failed action.
struct ChatErrorToasts: View {
    let store: ChatToastStore
    let isRetrying: Bool
    let onRetry: (String) async -> Void
    @State private var selected: String?
    @ScaledMetric(relativeTo: .footnote) private var lineHeight: CGFloat = 18
    private var height: CGFloat { min(220, max(136, lineHeight * 4 + 74)) }

    var body: some View {
        if !store.items.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                            ToastCard(
                                item: item,
                                index: index,
                                total: store.items.count,
                                height: height,
                                isRetrying: isRetrying,
                                onDismiss: { store.dismiss($0) },
                                onRetry: onRetry
                            )
                            .id(item.id)
                        }
                    }
                }
                .frame(height: height)
                .padding(.horizontal, ChatControlMetrics.collapsedHorizontalInset)
                .padding(.top, 4).padding(.bottom, 10)
                .frame(maxWidth: ChatControlMetrics.maximumContentWidth)
                .compatOnChange(of: store.items.map(\.id), initial: true) { _, ids in
                    if selected == nil || !ids.contains(selected ?? "") { selected = ids.first }
                    guard let selected else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(selected, anchor: .center) }
                }
                .accessibilityHint(store.items.count > 1 ? L("左右滑动查看其他提示") : "")
            }
        }
    }
}

/// One toast card. Split out of `ChatErrorToasts.body`: the inline tree alone
/// exceeded the type-checker's budget on the iOS 14 toolchain.
private struct ToastCard: View {
    let item: ChatToast
    let index: Int
    let total: Int
    let height: CGFloat
    let isRetrying: Bool
    let onDismiss: (String) -> Void
    let onRetry: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppSymbol("exclamationmark.circle").foregroundColor(.secondary)
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                if total > 1 {
                    Text("\(index + 1)/\(total)").font(.caption2).compatMonospacedDigit().foregroundColor(.secondary)
                }
                Button { onDismiss(item.id) } label: {
                    AppSymbol("xmark", size: 11).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(L("关闭此提示"))
            }
            ScrollView(.vertical) {
                Text(item.message).font(.footnote).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).compatTextSelection()
            }.compatScrollBounceBehavior(.basedOnSize)
            if item.canRetry {
                Button(isRetrying ? L("正在刷新…") : L("刷新状态")) { Task { await onRetry(item.id) } }
                    .font(.footnote.weight(.medium)).frame(minHeight: 36).disabled(isRetrying)
            }
        }
        .padding(.leading, 16).padding(.trailing, 4).padding(.bottom, 12)
        .frame(height: height)
        .compatContainerRelativeFrame(.horizontal)
        .compatGlassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
