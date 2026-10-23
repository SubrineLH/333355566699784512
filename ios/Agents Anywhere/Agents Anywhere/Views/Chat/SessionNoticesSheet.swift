import SwiftUI

struct SessionNoticesSheet: View {
    let model: SessionChatModel
    var initialNoticeID: String? = nil
    @Environment(\.presentationMode) private var presentationMode
    var body: some View {
        CompatPlainNavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(model.session.notices.notices.filter(\.isVisible)) { item in
                            SessionInteractionContent(item: item, chat: model).id(item.id)
                        }
                    }.padding(16)
                }
                .onAppear { if let initialNoticeID { proxy.scrollTo(initialNoticeID, anchor: .top) } }
            }
            .navigationTitle(L("交互与通知"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
        }
        .appSheetPresentation(.compact)
    }
}
