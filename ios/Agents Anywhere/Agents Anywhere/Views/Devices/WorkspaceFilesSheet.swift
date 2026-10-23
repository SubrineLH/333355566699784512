import SwiftUI

struct WorkspaceFilesSheet: View {
    @Environment(\.presentationMode) private var presentationMode

    let connectorId: V2ConnectorID
    let deviceName: String
    let workspace: V2DeviceWorkspace
    let service: V2WorkspaceFilesService

    var session: V2SessionModel?
    var permitsReading = true
    var onSelectDirectory: ((String) -> Void)? = nil
    var initialPath = "."
    @State private var destination: FileDestination?
    @State private var transfer: FileTransferRequest?
    @State private var previewErrorMessage: String?
    @State private var path: [WorkspaceDirectoryRoute] = []

    private enum FileDestination: Identifiable {
        case preview(V2WorkspaceEntry), save(WorkspaceDownloadedFile), open(WorkspaceDownloadedFile)
        var id: String {
            switch self {
            case .preview(let entry): "preview:" + entry.path
            case .save(let file): "save:" + file.id.absoluteString
            case .open(let file): "open:" + file.id.absoluteString
            }
        }
    }
    private struct FileTransferRequest: Equatable {
        let id = UUID()
        let entry: V2WorkspaceEntry
        let action: WorkspaceFileAction
    }

    var body: some View {
        CompatNavigationStack(path: $path) {
            WorkspaceDirectoryView(
                connectorId: connectorId,
                root: workspace.path,
                path: initialPath,
                title: deviceName,
                service: service,
                onOpenFile: openFile, onFileAction: startTransfer, canRead: canRead,
                canTransfer: canRead && transfer == nil, onSelectDirectory: onSelectDirectory,
                onOpenDirectory: openDirectory
            )
            .toolbar {
                SheetCloseToolbar { presentationMode.wrappedValue.dismiss() }
            }
            .compatSafeAreaInset(edge: .bottom) {
                if let transfer {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L("正在下载 \(transfer.entry.name)…")).font(.footnote).lineLimit(1)
                        Spacer(minLength: 0)
                        Button(L("取消")) { self.transfer = nil }.font(.footnote)
                    }
                    .padding(16)
                    .compatGlassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }
            }
        } destination: { route in
            WorkspaceDirectoryView(
                connectorId: connectorId,
                root: workspace.path,
                path: route.path,
                title: deviceName,
                service: service,
                onOpenFile: openFile, onFileAction: startTransfer, canRead: canRead,
                canTransfer: canRead && transfer == nil, onSelectDirectory: onSelectDirectory,
                onOpenDirectory: openDirectory
            )
        }
        .appSheetPresentation(.compact)
        .sheet(item: $destination) { destination in
            switch destination {
            case .preview(let entry):
                WorkspaceFilePreviewSheet(connectorId: connectorId, root: workspace.path,
                    path: entry.path, service: service, session: session)
            case .save(let file): WorkspaceFileExportPicker(file: file, onFinish: finishTransfer)
            case .open(let file): WorkspaceFileActivitySheet(file: file, onFinish: finishTransfer)
            }
        }
        .compatTask(id: transfer) {
            guard let request = transfer else { return }
            defer { if transfer?.id == request.id { transfer = nil } }
            do {
                let file = try await service.download(connectorId: connectorId, root: workspace.path, entry: request.entry)
                try Task.checkCancellation()
                guard transfer?.id == request.id, session?.isValid != false else { return }
                destination = request.action == .download ? .save(file) : .open(file)
            } catch { if !Task.isCancelled { previewErrorMessage = error.localizedDescription } }
        }
        .onDisappear { transfer = nil }
        .compatAlert(L("文件操作失败"), isPresented: previewErrorBinding) {
            Button(L("好"), role: .cancel) {
                previewErrorMessage = nil
            }
        } message: {
            Text(previewErrorMessage ?? "")
        }
    }

    private var previewErrorBinding: Binding<Bool> {
        Binding(
            get: { previewErrorMessage != nil },
            set: { isPresented in
                if !isPresented { previewErrorMessage = nil }
            }
        )
    }

    private var canRead: Bool {
        guard permitsReading else { return false }
        guard let session else { return true }
        return session.isValid && session.network.availability != .offline && session.metadata?.connectorStatus == .online
    }
    private func openFile(_ entry: V2WorkspaceEntry) {
        guard canRead else { previewErrorMessage = L("设备或网络已离线，请恢复连接后重试。"); return }
        destination = .preview(entry)
    }
    private func startTransfer(_ entry: V2WorkspaceEntry, action: WorkspaceFileAction) {
        guard canRead, entry.isFile, transfer == nil else { return }
        previewErrorMessage = nil
        transfer = FileTransferRequest(entry: entry, action: action)
    }
    private func finishTransfer(_ error: String?) {
        destination = nil
        if let error { previewErrorMessage = error }
    }
    /// iOS 14 pushes directory levels through the root path list; the nested
    /// directory views never own their own navigation state.
    private func openDirectory(_ path: String) {
        self.path.append(WorkspaceDirectoryRoute(path: path))
    }
}

private enum WorkspaceFileAction: Equatable { case download, openIn }

private struct WorkspaceDirectoryRoute: Hashable {
    let path: String
}

private struct WorkspaceDirectoryView: View {
    let connectorId: V2ConnectorID
    let root: String
    let path: String
    let title: String
    let service: V2WorkspaceFilesService
    let onOpenFile: (V2WorkspaceEntry) -> Void
    let onFileAction: (V2WorkspaceEntry, WorkspaceFileAction) -> Void
    let canRead: Bool
    let canTransfer: Bool
    let onSelectDirectory: ((String) -> Void)?
    let onOpenDirectory: (String) -> Void

    @StateObject private var model = WorkspaceDirectoryModel()
    @State private var requestedPath: String?
    @State private var address: String?
    private var effectivePath: String { requestedPath ?? path }
    private var canSelect: Bool {
        canRead && !model.isLoading && model.selectablePath != nil && (address == nil || address == model.resolvedPath)
    }

    var body: some View {
        List {
            if !canRead {
                Label(L("设备或网络已离线，已加载的目录仍可查看。"), appSymbol: "wifi.slash")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if let error = model.errorMessage, !model.entries.isEmpty {
                Text(error).font(.footnote).foregroundColor(.secondary)
            }
            if model.isLoading && model.entries.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L("Loading files..."))
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage = model.errorMessage, model.entries.isEmpty {
                CompatContentUnavailable {
                    Label(L("Unable to Load Files"), appSymbol: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(L("Retry")) {
                        Task { await loadDirectory() }
                    }
                    .buttonStyle(CompatProminentButtonStyle()).disabled(!canRead)
                }
            } else if model.entries.isEmpty {
                CompatContentUnavailableView(
                    L("Empty Folder"),
                    appSymbol: "folder"
                )
            } else {
                ForEach(model.entries) { entry in
                    WorkspaceEntryRow(
                        entry: entry,
                        onOpenFile: onOpenFile,
                        onOpenDirectory: onOpenDirectory,
                        canRead: canRead
                    )
                    .contextMenu {
                        Button(L("复制路径"), systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.path }
                        if entry.isFile {
                            Button(L("下载"), systemImage: "arrow.down.to.line") { onFileAction(entry, .download) }
                                .disabled(!canTransfer)
                            Button(L("其他打开方式…"), systemImage: "square.and.arrow.up") { onFileAction(entry, .openIn) }
                                .disabled(!canTransfer)
                        }
                    }
                }
            }

            if model.isTruncated {
                Label(L("Some files are not shown."), appSymbol: "ellipsis.circle")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .compatScrollContentBackground(.hidden)
        .compatScrollEdgeEffectStyle(.soft, for: .all)
        .compatToolbarBackground(.hidden, for: .navigationBar)
        .compatSafeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if onSelectDirectory != nil {
                    HStack(spacing: 8) {
                        Button(L("上一级目录"), appSymbol: "arrow.up") {
                            if let parent = ProjectWorkspacePath.parent(model.resolvedPath) { navigate(parent) }
                        }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                            .disabled(!canRead || model.isLoading || ProjectWorkspacePath.parent(model.resolvedPath) == nil)
                        TextField(L("设备上的完整路径"), text: Binding(get: { address ?? currentDirectoryPath }, set: { address = $0 }))
                            .textFieldStyle(.plain)
                            .font(.system(.footnote, design: .monospaced)).compatTextInputAutocapitalization(.never).compatAutocorrectionDisabled()
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .compatGlassEffect(.regular, in: .capsule)
                            .compatOnSubmit { navigate(address ?? currentDirectoryPath) }
                        Button(L("打开目录"), appSymbol: "arrow.right") { navigate(address ?? currentDirectoryPath) }
                            .labelStyle(.iconOnly).frame(width: 44, height: 44).disabled(!canRead)
                    }.padding(.horizontal, 12)
                }
                Text(currentDirectoryLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .compatTextSelection()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .accessibilityLabel(L("当前目录：\(currentDirectoryLabel)"))
                    .contextMenu {
                        Button(L("复制路径"), systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = currentDirectoryPath
                        }
                    }
            }
        }
        .compatSafeAreaInset(edge: .bottom) {
            if let onSelectDirectory {
                AppGlassButton(L("使用此目录"), style: .prominent,
                    disabled: !canSelect) {
                    guard canSelect, let path = model.selectablePath else { return }
                    onSelectDirectory(path)
                }.padding(16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .compatRefreshable {
            await loadDirectory()
        }
        .compatTask(id: DirectoryRequest(connector: connectorId, root: root, path: effectivePath, canRead: canRead)) {
            await loadDirectory()
        }
    }

    private var currentDirectoryPath: String {
        // fs/list returns the device's resolved absolute directory. Keep its
        // POSIX/Windows spelling rather than interpreting it on the iOS host.
        if !model.resolvedPath.isEmpty { return model.resolvedPath }
        return effectivePath == "." ? root : effectivePath
    }

    /// Connector fs/list answers an empty Windows path with its drive list.
    private var currentDirectoryLabel: String {
        currentDirectoryPath.isEmpty ? L("所有盘符") : currentDirectoryPath
    }

    private struct DirectoryRequest: Equatable { let connector: String; let root: String; let path: String; let canRead: Bool }
    private func navigate(_ path: String) {
        guard canRead else { return }
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare "D:" is relative to that drive's current directory; open its root.
        if value.range(of: "^[A-Za-z]:$", options: .regularExpression) != nil { value += "\\" }
        let reloadsCurrent = effectivePath == value
        address = value; requestedPath = value
        if reloadsCurrent { Task { await loadDirectory() } }
    }

    private func loadDirectory() async {
        guard canRead else { return }
        let requested = effectivePath, previousAddress = address
        await model.load(
            connectorId: connectorId,
            root: root,
            path: requested,
            service: service
        )
        // A successfully resolved '~', symlink or normalized path is a valid
        // directory too. Keep any address the user edited during this request.
        if !Task.isCancelled, !model.isLoading, effectivePath == requested,
           address == previousAddress, model.selectablePath != nil { address = nil }
    }
}

private struct WorkspaceEntryRow: View {
    let entry: V2WorkspaceEntry
    let onOpenFile: (V2WorkspaceEntry) -> Void
    let onOpenDirectory: (String) -> Void
    let canRead: Bool

    var body: some View {
        if entry.isDirectory {
            Button {
                onOpenDirectory(entry.path)
            } label: {
                HStack(spacing: 8) {
                    label
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .disabled(!canRead)
        } else {
            Button {
                onOpenFile(entry)
            } label: {
                label
            }
            .disabled(!entry.isFile || !canRead)
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            AppSymbol(entry.isDirectory ? "folder" : AppFileSymbol.name(for: entry.name))
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let size = entry.size, entry.isFile {
                    Text(ByteCountFormatStyle(style: .file).format(Int64(size)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

        }
        .contentShape(Rectangle())
    }
}
