import SwiftUI

struct SessionInteractionDetailsSheet: View {
    let item: SessionNoticeModel
    let chat: SessionChatModel
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        CompatPlainNavigationStack {
            ScrollView {
                SessionInteractionContent(item: item, chat: chat, showsContext: true).padding(16)
            }
            .navigationTitle(L("操作详情")).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
        }.appSheetPresentation(.compact)
    }
}
