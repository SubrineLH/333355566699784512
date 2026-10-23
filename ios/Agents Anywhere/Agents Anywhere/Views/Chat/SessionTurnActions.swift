import SwiftUI

struct SessionTurnActions: View, Equatable {
    let action: TimelineTurnAction
    @State private var copied = false

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.action == rhs.action }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                UIPasteboard.general.string = action.copyText; copied = true
            } label: { AppSymbol(copied ? "checkmark" : "document.on.document").frame(width: 44, height: 44) }
            .accessibilityLabel(copied ? L("已复制") : L("复制回复"))
            .compatTask(id: copied) {
                guard copied else { return }
                do { try await compatSleep(seconds: 2); copied = false } catch {}
            }
            CompatShareLink(text: { action.copyText }) {
                AppSymbol("square.and.arrow.up").frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("分享回复"))
        }
        .disabled(!action.hasReplyText)
        .buttonStyle(.plain).font(.system(size: 15)).foregroundColor(.secondary).padding(.leading, -10)
        .accessibilityIdentifier("chat.turn.actions")
    }
}
