import SwiftUI

struct SessionInteractionDock: View {
    let chat: SessionChatModel
    let onShowAll: (String) -> Void
    @State private var selectedID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var metrics = SessionInteractionMetrics()

    private var items: [SessionNoticeModel] { chat.session.notices.notices.filter { $0.blocks(chat.session.id) } }
    private var selectedIndex: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    // Reserve the same peeking space for one or several cards, so resolving a
    // queued item does not resize the entire dock. Status text never measures it.
    private let peek: CGFloat = 12
    private var pageHeight: CGFloat {
        metrics.compactHeight
    }

    var body: some View {
        if !items.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            SessionInteractionCard(item: item, chat: chat,
                                page: items.count > 1 ? "\(index + 1)/\(items.count)" : nil,
                                height: pageHeight, onExpand: { onShowAll(item.id) })
                                .accessibilityAction(named: L("下一项")) { step(1) }
                                .accessibilityAction(named: L("上一项")) { step(-1) }
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, peek)
                }
                .compatScrollIndicators(.hidden).compatScrollBounceBehavior(.basedOnSize)
                .frame(height: pageHeight + peek * 2).clipped()
                .compatOnChange(of: items.map(\.id), initial: true) { old, next in
                    if let selectedID, next.contains(selectedID) { return }
                    let index = old.firstIndex(of: selectedID ?? "") ?? 0
                    selectedID = next.isEmpty ? nil : next[min(index, next.count - 1)]
                }
                .compatOnChange(of: selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
    private func step(_ delta: Int) {
        let index = selectedIndex + delta
        guard items.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selectedID = items[index].id }
    }
}
