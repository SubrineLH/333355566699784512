import SwiftUI

struct RuntimeEnvironmentRowEditor: View {
    @ObservedObject var row: RuntimeEnvironmentRow
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(L("Variable name"), text: $row.key)
                        .runtimeConfigInput()
                    TextField(L("Value"), text: $row.value)
                        .runtimeConfigInput().disabled(row.removesInherited)
                }
                Menu {
                    Toggle(L("Remove inherited variable"), isOn: $row.removesInherited)
                    Button(L("Remove variable"), systemImage: "trash", role: .destructive) {
                        CompatKeyboard.dismiss()
                        onRemove()
                    }
                } label: { AppSymbol("ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel(L("Variable actions"))
            }
        }
        .padding(.vertical, 8)
    }
}

struct RuntimeCustomModelRowEditor: View {
    @ObservedObject var row: RuntimeCustomModelRow
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("Custom model")).font(.subheadline.weight(.medium))
                Spacer()
                Button(L("Remove model"), appSymbol: "trash", role: .destructive) {
                    CompatKeyboard.dismiss()
                    onRemove()
                }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            TextField(L("Model ID"), text: $row.modelID)
                .runtimeConfigInput()
            TextField(L("Display name"), text: $row.displayName)
                .runtimeConfigInput()
            HStack {
                Text(L("Reasoning efforts")).font(.subheadline.weight(.medium))
                Spacer()
                Button(L("Add effort"), appSymbol: "plus") {
                    row.efforts.append(.init())
                }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            if row.efforts.isEmpty {
                Text(L("This model has no custom reasoning efforts."))
                    .font(.footnote).foregroundColor(.secondary)
            }
            ForEach(row.efforts) { effort in
                Divider()
                RuntimeEffortRowEditor(row: effort) { row.removeEffort(effort.id) }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct RuntimeEffortRowEditor: View {
    @ObservedObject var row: RuntimeEffortRow
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("Effort ID"), text: $row.effortID)
                    .runtimeConfigInput()
                TextField(L("dashboard.device.customEffortDisplayName"), text: $row.displayName)
                    .runtimeConfigInput()
            }
            Button(L("Remove effort"), appSymbol: "trash", role: .destructive) {
                CompatKeyboard.dismiss()
                onRemove()
            }.buttonStyle(.borderless).labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
    }
}

private enum RuntimeConfigurationInput: Hashable { case identifier, value }
