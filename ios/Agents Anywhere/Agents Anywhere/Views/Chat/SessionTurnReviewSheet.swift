import SwiftUI

/// Mounted only for completed turns. Observing file-change payloads here keeps
/// token appends out of the timeline's structural grouping and earlier footers.
struct SessionTurnReviewFooter: View, Equatable {
    let action: TimelineTurnAction
    let root: String?
    let hasOlderItems: Bool
    let onFile: (String) -> Void
    @State private var showsReview = false
    @State private var pendingFile: String?
    @State private var memo = ReviewMemo()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.action == rhs.action && lhs.root == rhs.root && lhs.hasOlderItems == rhs.hasOlderItems
    }

    /// Parsing every diff of a completed turn is repeated only when one of
    /// its file-change items actually changed, not on each timeline invalidation.
    private final class ReviewMemo {
        var key: [ReviewKey] = []
        var root: String?
        var review: TimelineTurnReview?
    }
    private struct ReviewKey: Equatable { let id: String; let revision: Int; let updatedSeq: Int }

    private var review: TimelineTurnReview {
        let key = action.changes.map { ReviewKey(id: $0.id, revision: $0.value.revision, updatedSeq: $0.value.updatedSeq) }
        if let cached = memo.review, memo.key == key, memo.root == root { return cached }
        let windows = root?.range(of: #"^[A-Za-z]:[/\\]|^\\\\"#, options: .regularExpression) != nil
        let built = TimelineTurnReview.build(items: action.changes.map(\.value), root: root, caseInsensitive: windows)
        memo.key = key; memo.root = root; memo.review = built
        return built
    }

    var body: some View {
        if !action.changes.isEmpty {
            let review = review
            if !review.files.isEmpty {
                Button { showsReview = true } label: {
                    HStack(spacing: 6) {
                        AppSymbol("doc.text", size: 14)
                        Text(L("\(review.files.count) 个文件"))
                        Text("·")
                        Text("+\(review.additions)").foregroundColor(.green)
                        Text("−\(review.deletions)").foregroundColor(.red)
                        AppSymbol("chevron.right", size: 10)
                    }
                    .font(.footnote).compatMonospacedDigit().lineLimit(1)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
                .accessibilityHint(L("查看本轮文件和 diff"))
                .accessibilityIdentifier("chat.turn.review")
                .sheet(isPresented: $showsReview, onDismiss: {
                    if let path = pendingFile { pendingFile = nil; onFile(path) }
                }) {
                    SessionTurnReviewSheet(review: review, isPartial: hasOlderItems && action.startsMidTurn) { path in
                        pendingFile = path; showsReview = false
                    }
                }
            }
        }
    }
}

private struct SessionTurnReviewSheet: View {
    let review: TimelineTurnReview
    let isPartial: Bool
    let onFile: (String) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var expanded: Set<String> = []

    var body: some View {
        CompatPlainNavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if isPartial {
                        Text(L("此轮较早的记录尚未载入，当前显示已加载的文件变更。"))
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    Text(L("统计来自本轮记录的 diff；同一文件的多次修改按顺序保留。"))
                        .font(.footnote).foregroundColor(.secondary)
                    ForEach(review.files) { file in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                if !expanded.insert(file.id).inserted { expanded.remove(file.id) }
                            } label: {
                                HStack(spacing: 8) {
                                    AppSymbol(expanded.contains(file.id) ? "chevron.down" : "chevron.right", size: 10)
                                    Text(file.displayPath).font(.system(.subheadline, design: .monospaced))
                                        .lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("+\(file.additions)").foregroundColor(.green)
                                    Text("−\(file.deletions)").foregroundColor(.red)
                                }.font(.caption).compatMonospacedDigit().padding(12).frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if expanded.contains(file.id) {
                                HStack {
                                    Text(file.action.label).font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Button(L("打开文件预览"), systemImage: "arrow.up.right") { onFile(file.path) }
                                        .disabled(file.action == .delete)
                                }.font(.caption).padding(.horizontal, 12).frame(minHeight: 44)
                                if file.patches.isEmpty {
                                    Text(L("这条文件变更记录未提供 diff。"))
                                        .font(.footnote).foregroundColor(.secondary).padding(12)
                                }
                                ForEach(file.patches) { patch in
                                    TimelineCodePanel(label: patch.isDiff ? "diff" : "code", code: patch.text, isDiff: patch.isDiff)
                                }
                            }
                        }
                        .compatBackground(Color(UIColor.secondarySystemBackground), in: .rect(cornerRadius: 14))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(16)
            }
            .navigationTitle(L("本轮文件变更"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
        }
        .appSheetPresentation(.expanded)
    }
}
