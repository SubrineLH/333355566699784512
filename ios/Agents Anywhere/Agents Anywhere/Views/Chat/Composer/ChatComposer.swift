import SwiftUI

struct ChatComposer: View {
    @ObservedObject var draft: ComposerDraft
    let editor: ComposerEditorController
    let isStreaming: Bool
    var canSend = true
    var canStop = true
    var isBusy = false
    var placeholder = L("询问 Agents")
    let maximumEditorHeight: CGFloat
    let controls: ChatControlMetrics
    let onSend: () -> Void
    let onStop: () -> Void
    let onOptions: () -> Void
    /// Shown beside send when the session's runtime offers slash commands.
    var showsCommands = false
    var commandsActive = false
    var onCommands: () -> Void = {}
    /// Reports draft mutations from this subtree only. Persisting the draft
    /// must not make the page root observe the editor's text.
    var onDraftChange: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass


    private var optionsButton: some View {
        Button(action: onOptions) {
            AppSymbol("plus", size: 24)
                .frame(width: controls.touchTarget, height: controls.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("附件与对话选项"))
        .accessibilityIdentifier("chat.composer.options")
    }

    private var editorArea: some View {
        ZStack(alignment: .topLeading) {
            if draft.text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
                    .allowsHitTesting(false)
            }
            NativeComposerEditor(draft: draft, controller: editor, maximumHeight: maximumEditorHeight, onCommandSend: onSend)
        }
        .frame(maxHeight: maximumEditorHeight)
    }

    private var sendButton: some View {
        Button(action: isStreaming ? onStop : onSend) {
            AppSymbol(isStreaming ? "stop.fill" : "arrow.up", size: isStreaming ? 13 : 18)
                .compatContentTransition(.interpolate)
                .foregroundColor(AppTheme.primaryControlForeground(colorScheme))
                .frame(width: controls.sendDiameter, height: controls.sendDiameter)
                .compatBackground(AppTheme.primaryControlBackground(colorScheme).opacity((isStreaming ? canStop : canSend && draft.canAttemptSend) && !isBusy ? 1 : 0.42), in: Circle())
                .frame(width: controls.touchTarget, height: controls.touchTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || (isStreaming ? !canStop : !canSend || !draft.canAttemptSend))
        .accessibilityLabel(isStreaming ? L("停止生成") : L("发送消息"))
        .accessibilityHint(draft.isComposing ? L("请先确认输入法候选文字") : "")
        .accessibilityIdentifier("chat.composer.send")
    }

    @ViewBuilder private var commandsButton: some View {
        if showsCommands {
            Button(action: onCommands) {
                AppSymbol("command", size: 18)
                    .foregroundColor(commandsActive ? Color.accentColor : Color.secondary)
                    .frame(width: controls.touchTarget, height: controls.touchTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("指令"))
            .accessibilityAddTraits(commandsActive ? .isSelected : [])
            .accessibilityIdentifier("chat.composer.commands")
        }
    }

    private var collapsedRow: some View {
        HStack(spacing: 0) {
            optionsButton
            editorArea.frame(maxWidth: .infinity)
            commandsButton
            sendButton
        }
        .padding(.leading, controls.collapsedInset + controls.collapsedTextGap)
        .padding(.trailing, controls.collapsedInset)
        .frame(height: controls.diameter)
    }

    private var expandedRow: some View {
        VStack(spacing: 0) {
            editorArea
                .padding(.horizontal, controls.textInset)
                .padding(.top, controls.textInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                optionsButton
                Spacer(minLength: 0)
                commandsButton
                sendButton
            }
            .padding(.horizontal, controls.textInset - controls.collapsedInset)
            .padding(.top, controls.textToActions)
            .padding(.bottom, controls.expandedBottomInset)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !draft.attachments.isEmpty { attachmentTray }
            if draft.isExpanded { expandedRow } else { collapsedRow }
        }
        .compatGlassEffect(.regular.interactive(), in: .rect(cornerRadius: draft.isExpanded ? controls.expandedCornerRadius : controls.collapsedCornerRadius))
        .padding(.horizontal, draft.isExpanded ? ChatControlMetrics.expandedHorizontalInset : ChatControlMetrics.collapsedHorizontalInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24))
        // The composer is the only subtree that already re-evaluates on every
        // keystroke, including each Chinese IME marked-text update. Observing
        // the draft from the page root re-evaluated the whole conversation.
        .compatOnChange(of: draft.text) { _, _ in onDraftChange() }
        .compatOnChange(of: draft.attachments) { _, _ in onDraftChange() }
    }

    private var attachmentTray: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(draft.attachments) { attachment in
                    ChatComposerAttachment(attachment: attachment) {
                        draft.attachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
        }
        .compatScrollIndicators(.hidden)
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}
