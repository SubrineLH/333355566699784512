import SwiftUI
import UniformTypeIdentifiers

struct SessionDetailsSheet: View {
    let chat: SessionChatModel
    let service: V2SessionDetailService
    @Environment(\.presentationMode) private var presentationMode
    @State private var exportRequest: String?
    @State private var document: TimelineJSONDocument?
    @State private var showsExporter = false
    @State private var error: String?
    var body: some View {
        CompatPlainNavigationStack {
            List {
                if let meta = chat.session.metadata {
                    Section(header: Text(L("会话"))) {
                        row(L("标题"), meta.title ?? L("未命名会话"))
                        row(L("设备"), meta.connectorId)
                        row(L("Agent"), meta.runtimeName ?? meta.runtime)
                        row(L("Agent 类型"), meta.runtimeTypeDisplayName ?? meta.runtimeType ?? meta.runtime)
                        row(L("状态"), (chat.session.runtime.state?.status ?? meta.status).displayName)
                        row(L("dashboard.session.workspace"), meta.cwd ?? L("无"))
                        row(L("接管"), meta.takeover ? L("已开启") : L("只读"))
                    }
                    Section(header: Text(L("标识与时间线"))) {
                        row(L("Session ID"), meta.id)
                        row(L("外部 Session ID"), meta.externalSessionId ?? L("无"))
                        row(L("已加载条目"), String(chat.session.timeline.count))
                        row(L("待回应交互"), String(chat.session.notices.notices.filter { $0.isVisible && $0.notice.type == "interaction" }.count))
                    }
                    Section {
                        Button { exportRequest = "memory" } label: { Label(L("导出已加载时间线 JSON"), appSymbol: "square.and.arrow.up") }
                            .disabled(exportRequest != nil)
                        Button { exportRequest = "remote" } label: { Label(L("导出服务器时间线 JSON"), appSymbol: "arrow.down.document") }
                            .disabled(exportRequest != nil || chat.session.network.availability == .offline)
                        if exportRequest != nil {
                            HStack { ProgressView(); Text(L("正在准备导出…")); Spacer(); Button(L("取消")) { exportRequest = nil } }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundColor(.secondary) } }
            }
            .navigationTitle(L("会话详情")).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar { presentationMode.wrappedValue.dismiss() } }
        }
        .appSheetPresentation(.expanded)
        .compatTask(id: exportRequest) {
            guard let source = exportRequest, let meta = chat.session.metadata else { return }
            error = nil
            do {
                let export: SessionTimelineExport
                if source == "remote" { export = try await service.exportTimeline(sessionId: meta.id) }
                else {
                    let items = chat.session.timeline.map(\.value)
                    export = SessionTimelineExport(source: "memory", session: meta, items: items, notices: chat.session.runtime.notices,
                        nextSeq: items.map(\.updatedSeq).max() ?? 0, hasMore: chat.session.hasOlderItems || chat.session.hasNewerItems)
                }
                try Task.checkCancellation()
                guard chat.session.isValid else { return }
                document = TimelineJSONDocument(data: try export.encoded(), name: "timeline-\(source)-\(meta.id.prefix(8))")
                showsExporter = true
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { exportRequest = nil }
        }
        .fileExporter(isPresented: $showsExporter, document: document, contentType: .json, defaultFilename: document?.name ?? "timeline") { result in
            if case let .failure(failure) = result { error = failure.localizedDescription }
            document = nil
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        CompatLabeledContent(title) { Text(value).compatTextSelection().font(.subheadline).multilineTextAlignment(.trailing) }
    }
}

private struct TimelineJSONDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data
    let name: String
    init(data: Data, name: String) { self.data = data; self.name = name }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data(); name = "timeline" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
