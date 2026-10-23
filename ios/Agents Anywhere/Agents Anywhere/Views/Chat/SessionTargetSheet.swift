import SwiftUI

struct SessionTargetSheet: View {
    @ObservedObject var model: NewSessionModel
    @State private var expandedDeviceID: String?
    @State private var applying: TargetSelection?
    @State private var selectionError: String?
    @Environment(\.presentationMode) private var presentationMode

    private var devices: [V2Connector] {
        model.connectors.sorted {
            ($0.status == .online ? 0 : 1, $0.name, $0.id) < ($1.status == .online ? 0 : 1, $1.name, $1.id)
        }
    }

    var body: some View {
        CompatPlainNavigationStack {
            List {
                if devices.isEmpty {
                    CompatContentUnavailableView(L("No devices"), appSymbol: "desktopcomputer")
                }
                Section {
                    ForEach(devices) { device in
                        InlineSelectionGroup(title: device.name, detail: deviceDetail(device),
                            isSelected: model.connectorID == device.id,
                            isExpanded: Binding(get: { expandedDeviceID == device.id }, set: { expandedDeviceID = $0 ? device.id : nil })) {
                            agents(on: device)
                        }
                        .compatTask(id: TargetInventoryKey(id: device.id, isExpanded: expandedDeviceID == device.id, connected: connected(device))) {
                            guard expandedDeviceID == device.id else { return }
                            await model.loadInventory(device.id)
                        }
                    }
                }
                if let error = selectionError ?? model.error {
                    Section { Text(error).font(.footnote).foregroundColor(.secondary) }
                }
            }
            .navigationTitle(L("运行目标")).navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetCloseToolbar(disabled: applying != nil) { presentationMode.wrappedValue.dismiss() } }
            .compatRefreshable {
                if let id = expandedDeviceID { await model.loadInventory(id) }
            }
        }
        .appSheetPresentation(.compact)
        .compatInteractiveDismissDisabled(applying != nil)
        .disabled(applying != nil)
    }

    @ViewBuilder private func agents(on device: V2Connector) -> some View {
        let inventory = instances(on: device.id)
        let loading = model.loadingDevices.contains(device.id)
        let error = model.inventoryErrors[device.id]
        if loading || (connected(device) && model.inventories[device.id] == nil && error == nil) {
            ProgressView(L("正在检查 Agent…"))
        } else if inventory.isEmpty, error == nil, connected(device) {
            Text(L("这台设备尚无已配置的 Agent。")).font(.footnote).foregroundColor(.secondary)
        }
        ForEach(inventory) { runtime in
            InlineSelectionButton(title: runtime.sessionDisplayName, detail: runtime.sessionUnavailableReason,
                isSelected: model.connectorID == device.id && model.runtimeID == runtime.id,
                isWorking: applying == TargetSelection(connectorID: device.id, runtimeID: runtime.id)) {
                apply(device: device, runtime: runtime)
            }
            .disabled(!connected(device) || !runtime.isReadyForSession || !model.isValid || model.isCreating)
        }
        if !connected(device) {
            Text(model.network.availability == .offline ? L("手机网络已断开") : L("目标设备离线"))
                .font(.footnote).foregroundColor(.secondary)
        }
        if let error {
            Text(error).font(.footnote).foregroundColor(.secondary)
            Button(L("重新加载")) { Task { await model.loadInventory(device.id) } }
                .disabled(!connected(device) || loading)
        }
    }

    private func connected(_ device: V2Connector) -> Bool {
        device.status == .online && model.network.availability != .offline
    }
    private func deviceDetail(_ device: V2Connector) -> String {
        let status = model.network.availability == .offline ? L("手机网络已断开") :
            device.status == .online ? L("Online") : L("Offline")
        return [device.deviceOs, status].compactMap { $0 }.joined(separator: " · ")
    }
    private func instances(on id: String) -> [V2DeviceRuntime] {
        (model.inventories[id] ?? []).sorted {
            ($0.isReadyForSession ? 0 : 1, $0.sessionDisplayName, $0.id) < ($1.isReadyForSession ? 0 : 1, $1.sessionDisplayName, $1.id)
        }
    }
    private func apply(device: V2Connector, runtime: V2DeviceRuntime) {
        guard applying == nil, connected(device), runtime.isReadyForSession else { return }
        let target = TargetSelection(connectorID: device.id, runtimeID: runtime.id)
        applying = target; selectionError = nil
        Task { @MainActor in
            let accepted = await model.selectTarget(connectorID: target.connectorID, runtimeID: target.runtimeID)
            applying = nil
            if accepted { presentationMode.wrappedValue.dismiss() }
            else { selectionError = model.error ?? L("当前设置未保存，请稍后重试。") }
        }
    }
}

private struct TargetSelection: Equatable { let connectorID: String; let runtimeID: String }
private struct TargetInventoryKey: Equatable { let id: String; let isExpanded: Bool; let connected: Bool }
