import SwiftUI

struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(role: .close, action: action) {
            Label(L("Close"), appSymbol: "xmark")
        }
        .labelStyle(.iconOnly)
        .keyboardShortcut(.cancelAction)
    }
}

/// Sheet dismissal always uses the same leading X. Native navigation continues
/// to own the separate Back action on pushed pages.
struct SheetCloseToolbar: ToolbarContent {
    var disabled = false
    let action: () -> Void
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            SheetCloseButton(action: action).disabled(disabled)
        }
    }
}

extension SheetCloseToolbar {
    /// The toolbar builder in `AuthLayout` needs a `View`, and `ToolbarContent`
    /// only fits inside `.toolbar { }` on iOS 16. This wrapper keeps the same
    /// button while letting the call site stay a plain view.
    struct Standalone: View {
        var disabled = false
        let action: () -> Void

        var body: some View {
            SheetCloseButton(action: action).disabled(disabled)
        }
    }
}

struct SheetEditorToolbar: ToolbarContent {
    var saveTitle = L("Save")
    var isWorking = false
    var saveDisabled = false
    let onCancel: () -> Void
    let onSave: () -> Void
    var body: some ToolbarContent {
        SheetCloseToolbar(disabled: isWorking, action: onCancel)
        SheetSaveToolbar(saveTitle: saveTitle, isWorking: isWorking, saveDisabled: saveDisabled, onSave: onSave)
    }
}

/// Pushed editors keep the system Back button and interactive pop gesture.
struct SheetSaveToolbar: ToolbarContent {
    var saveTitle = L("Save")
    var isWorking = false
    var saveDisabled = false
    let onSave: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .confirm, action: onSave) {
                Text(saveTitle).opacity(isWorking ? 0 : 1)
                    .compatOverlay { if isWorking { ProgressView().compatControlSize(.small) } }
            }
            .disabled(isWorking || saveDisabled).keyboardShortcut("s", modifiers: .command)
        }
    }
}

extension View {
    func confirmDiscardChanges(_ isPresented: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        compatConfirmationDialog(L("Discard unsaved changes?"), isPresented: isPresented, titleVisibility: .visible) {
            Button(L("Discard changes"), role: .destructive, action: onDiscard)
            Button(L("Keep editing"), role: .cancel) {}
        }
    }
}
