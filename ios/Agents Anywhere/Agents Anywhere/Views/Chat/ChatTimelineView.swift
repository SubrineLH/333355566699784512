import SwiftUI
#if DEBUG
import OSLog
#endif

/// iOS 14 rewrite of the timeline scroller.
///
/// The original relied on `ScrollPosition`, `onScrollPhaseChange` and
/// `onScrollGeometryChange`, none of which exist before iOS 17/18. This version
/// keeps the same decision logic in `TimelineScrollState`, and feeds it from two
/// iOS 14 primitives instead:
///
/// * geometry: a probe in a named coordinate space reports the content origin
///   and the content height, so viewport metrics are derived locally;
/// * phases: a simultaneous drag gesture reports `.interacting` while the finger
///   is down, and a short settle window after it lifts decides `.idle`.
///
/// Programmatic scrolling goes through `ScrollViewReader`, so restoration and
/// the return pill target row ids rather than raw pixel offsets.
struct ChatTimelineView: View {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void
    @State private var historyLayout: TimelineHistoryLayout?
    @State private var historyPosition: TimelineHistoryPosition?
    @State private var hasRequestedOlder = false
    @State private var scrolling = TimelineScrollState()
    @State private var viewportSample = ChatViewportSample()
    @State private var viewportUpdates = ChatLayoutUpdate<TimelineViewport>()
    @State private var historyUpdates = ChatLayoutUpdate<TimelineHistoryLayout>()
    @State private var latestPull = TimelineHistoryPull()
    @State private var olderPull = TimelineHistoryPull(edge: .older)
    @State private var olderPromptVisible = false
    @State private var olderLoadRequest: Int?
    @State private var latestPromptVisible = false
    @State private var latestLoadRequest: Int?
    @State private var nativePhase = TimelineScrollState.Phase.idle
    /// The return pill would sit on top of the keyboard while typing.
    @State private var keyboardIsVisible = false
    @State private var containerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarDrawerIsTransitioning) private var sidebarIsTransitioning
    @Environment(\.sidebarDrawerObscuresDetail) private var sidebarObscuresDetail
    @ScaledMetric(relativeTo: .caption) private var returnPillHeight: CGFloat = 32
#if DEBUG
    private static let drawerLayoutLog = Logger(subsystem: "agents.anywhere", category: "drawer-layout")
#endif

    static let space = "chat.timeline.scroll"

    private var hasInteractions: Bool {
        model.session.notices.notices.contains { $0.isVisible && $0.notice.type == "interaction" }
    }
    private var viewport: TimelineViewport { viewportSample.value ?? scrolling.viewport }
    private var navigationIsSuspended: Bool { sidebarIsTransitioning || sidebarObscuresDetail }
    var body: some View {
        // A sibling overlay receives taps independently of the scroll view's
        // deceleration recognizer. The explicit return intent survives its callbacks.
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    ChatTimelineContent(model: model, onAttachment: onAttachment, onFile: onFile,
                        latestPullReady: latestPull.isReady, isLoadingLatest: latestLoadRequest != nil,
                        olderPullReady: olderPull.isReady, isLoadingOlder: olderLoadRequest != nil,
                        keepsOlderPrompt: hasRequestedOlder, historyAnchor: historyPosition?.origin,
                        onLoadOlder: loadOlder, onLoadLatest: loadLatest,
                        onHistoryLayout: { layout in historyDidLayOut(layout, proxy: proxy) },
                        onPromptVisibility: { latestPromptVisible = $0 },
                        onOlderPromptVisibility: { olderPromptVisible = $0 },
                        onTailVisibility: { region, visible in scrolling.tailVisibilityChanged(region, visible: visible) })
                        .equatable()
                        .compatBackground { ChatPageScrollEdge() }
                        .compatBackground { CompatScrollContentProbe(space: Self.space) }
                }
                .compatScrollMetrics(space: Self.space,
                    thresholds: ["older-prompt": 0.9, "newer-prompt": 0.5, "tail-near": 0.01, "tail-end": 0.5],
                    onMetrics: applyGeometry,
                    onVisibility: visibilityChanged)
                .compatScrollDismissesKeyboard(.interactively)
                .compatScrollIndicators(.hidden)
                .compatScrollBounceBehavior(.always, axes: .vertical)
                .compatScrollEdgeEffectStyle(.soft, for: .top)
                .allowsHitTesting(model.isOpeningReady)
                .accessibilityHidden(!model.isOpeningReady)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in userDragged() }
                        .onEnded { _ in userDragEnded() }
                )
                                .compatOnChange(of: navigationIsSuspended, initial: true) { _, suspended in
                    viewportUpdates.cancel()
                    scrolling.setNavigationSuspended(suspended)
                    if suspended {
                        releaseScrollPosition()
                        latestPull.cancel(); olderPull.cancel()
                    } else {
                        scrolling.phaseChanged(nativePhase, viewport: viewport)
                        if let historyLayout { historyDidLayOut(historyLayout, proxy: proxy) }
                    }
                }
                .compatOnChange(of: model.session.pendingMessages.last?.id) { _, id in
                    if model.isOpeningReady, id != nil && !hasInteractions { scrolling.requestBottom() }
                }
                .compatOnChange(of: model.responseRevision) { _, _ in
                    if model.isOpeningReady { scrolling.requestBottom() }
                }
                .compatOnChange(of: hasInteractions, initial: true) { _, presented in
                    scrolling.setInteractionPresented(presented)
                }
                .compatOnChange(of: model.isOpeningReady, initial: true) { _, ready in
                    if ready { scrolling.open(interactionPresented: hasInteractions) }
                }
                .compatOnChange(of: scrolling.navigationGeneration) { _, _ in
                    releaseScrollPosition()
                }
                .compatTask(id: scrolling.pendingBottomRequest) {
                    guard let request = scrolling.pendingBottomRequest, !navigationIsSuspended else { return }
                    // Coalesce actual layout changes. Scrolling through the same
                    // layout cannot restart this animation on every offset callback.
                    do { try await compatSleep(milliseconds: 24) } catch { return }
                    guard !Task.isCancelled, !navigationIsSuspended, let command = scrolling.begin(request) else { return }
                    scrollToBottom(command, proxy: proxy)
                }
                .compatTask(id: UserScrollSettlement(needed: scrolling.needsUserScrollSettlement,
                    tail: scrolling.tail, generation: scrolling.navigationGeneration)) {
                    guard scrolling.needsUserScrollSettlement else { return }
                    // Reconcile visibility after the settle window. This never
                    // holds opening behind a spinner or repeats a scroll.
                    do { try await compatSleep(milliseconds: 64) } catch { return }
                    guard !Task.isCancelled else { return }
                    scrolling.settleUserScroll()
                }
                .compatTask(id: olderLoadRequest) {
                    guard let request = olderLoadRequest else { return }
                    await model.session.loadOlder()
                    guard !Task.isCancelled, historyPosition?.id == request else { return }
                    if !model.session.isValid { historyPosition = nil; olderLoadRequest = nil; return }
                    historyPosition?.receivedPage(firstRowID: model.session.timeline.first { $0.value.isVisibleInChat }?.id)
                }
                .compatTask(id: HistorySettlement(id: historyPosition?.id, ready: historyPosition?.isReadyToFinish == true,
                    offset: historyPosition?.restoredOffset)) {
                    guard historyPosition?.id != nil, historyPosition?.isReadyToFinish == true else { return }
                    // Let the point correction reach layout before ending the spinner.
                    do { try await compatSleep(milliseconds: 64) } catch { return }
                    guard !Task.isCancelled else { return }
                    historyPosition = nil; olderLoadRequest = nil
                }
                .compatTask(id: latestLoadRequest) {
                    guard let generation = latestLoadRequest else { return }
                    await model.session.loadLatest()
                    guard !Task.isCancelled else { return }
                    // A drag during the fetch must not be undone when it finishes.
                    if scrolling.navigationGeneration == generation { scrolling.requestBottom() }
                    latestLoadRequest = nil
                }
            }
            if !keyboardIsVisible, scrolling.showsBottomButton() {
                Button {
                    latestPull.cancel(); olderPull.cancel()
                    historyPosition?.cancelRestoration()
                    scrolling.requestBottom()
                } label: {
                    Label(L("到底部"), appSymbol: "arrow.down").font(.caption.weight(.medium)).foregroundColor(.primary)
                        .padding(.horizontal, 12).frame(height: returnPillHeight)
                        .compatGlassEffect(.regular.interactive(), in: .capsule)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("chat.timeline.bottom")
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .compatOnGeometryChange(of: { $0.size.height }) { height in containerHeight = height }
        .traceChatLayout("timeline-viewport")
        .onDisappear { viewportUpdates.cancel(); historyUpdates.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsVisible = false
        }
    }

    private func visibilityChanged(_ id: String, _ visible: Bool) {
        switch id {
        case "older-prompt": olderPromptVisible = visible; onOlderPromptVisibilityChanged(visible)
        case "newer-prompt": latestPromptVisible = visible
        case "tail-near": scrolling.tailVisibilityChanged(.near, visible: visible)
        case "tail-end": scrolling.tailVisibilityChanged(.end, visible: visible)
        default: break
        }
    }

    private func onOlderPromptVisibilityChanged(_ visible: Bool) {
        // The prompt's own visibility only gates the pull-to-load affordance.
        _ = visible
    }

    // MARK: - Scroll phase

    private func userDragged() {
        guard !navigationIsSuspended else { return }
        guard nativePhase != .tracking else { return }
        nativePhase = .tracking
        _ = scrolling.phaseChanged(.tracking, viewport: viewport)
        nativePhase = .interacting
        if scrolling.phaseChanged(.interacting, viewport: viewport) {
            releaseScrollPosition()
            beginPulls(at: viewport)
        }
    }

    private func userDragEnded() {
        guard !navigationIsSuspended else { return }
        let wasInteracting = scrolling.phase == .interacting
        nativePhase = .idle
        if scrolling.phaseChanged(.idle, viewport: viewport) {
            let shouldLoadLatest = latestPull.end(), shouldLoadOlder = olderPull.end()
            if wasInteracting {
                if shouldLoadOlder { loadOlder() }
                else if shouldLoadLatest { loadLatest() }
            }
        }
    }

    private func beginPulls(at current: TimelineViewport) {
        historyPosition?.cancelRestoration()
        olderPull.begin(at: current, promptVisible: olderPromptVisible,
            canLoad: model.session.hasOlderItems && !model.session.isLoadingHistory && olderLoadRequest == nil && latestLoadRequest == nil)
        latestPull.begin(at: current, promptVisible: latestPromptVisible,
            canLoad: model.session.hasNewerItems && !model.session.isLoadingHistory && latestLoadRequest == nil && olderLoadRequest == nil)
    }

    private func applyGeometry(_ metrics: CompatScrollMetrics) {
        let current = TimelineViewport(contentHeight: metrics.contentHeight,
            containerHeight: containerHeight, topInset: 0, bottomInset: 0,
            offsetY: metrics.offsetY)
#if DEBUG
        // A device recording cannot distinguish a changed native offset from an
        // upstream reflow. Record only vertical changes during drawer navigation,
        // without logging message contents.
        if ChatLayoutDiagnostics.isEnabled, navigationIsSuspended,
           let previous = viewportSample.value,
           abs(current.contentHeight - previous.contentHeight) > 1
            || abs(current.visibleHeight - previous.visibleHeight) > 1
            || abs(current.offsetY - previous.offsetY) > 1 {
            Self.drawerLayoutLog.debug("Drawer geometry: content \(previous.contentHeight, privacy: .public) -> \(current.contentHeight, privacy: .public), viewport \(previous.visibleHeight, privacy: .public) -> \(current.visibleHeight, privacy: .public), offset \(previous.offsetY, privacy: .public) -> \(current.offsetY, privacy: .public)")
        }
#endif
        viewportUpdates.submit(current) { value in
            // Offset samples are needed for restoration, but do not change the
            // rendered page. Publish only dimensions used by following.
            let previous = viewportSample.value
            viewportSample.value = value
            let prior = previous ?? scrolling.viewport
            if prior.contentHeight != value.contentHeight || prior.visibleHeight != value.visibleHeight
                || prior.topInset != value.topInset {
                scrolling.geometryChanged(value)
            }
            if !navigationIsSuspended && scrolling.phase == .interacting {
                var latest = latestPull, older = olderPull
                latest.update(value); older.update(value)
                if latest != latestPull { latestPull = latest }
                if older != olderPull { olderPull = older }
            }
        }
    }

    // MARK: - Paging

    private func loadOlder() {
        guard model.session.isValid, model.session.hasOlderItems,
              !model.session.isLoadingHistory, olderLoadRequest == nil, latestLoadRequest == nil else { return }
        olderPull.cancel(); latestPull.cancel()
        scrolling.browseHistory()
        let layout = historyLayout.flatMap { $0.firstRowID == model.timeline.rows.first?.id ? $0 : nil }
        historyPosition = TimelineHistoryPosition(id: scrolling.navigationGeneration, layout: layout,
            offsetY: viewport.offsetY, topInset: viewport.topInset)
        hasRequestedOlder = true
        olderLoadRequest = scrolling.navigationGeneration
    }
    private func loadLatest() {
        guard model.session.isValid, model.session.hasNewerItems,
              !model.session.isLoadingHistory, latestLoadRequest == nil, olderLoadRequest == nil else { return }
        olderPull.cancel(); latestPull.cancel()
        historyPosition?.cancelRestoration()
        scrolling.requestBottom()
        latestLoadRequest = scrolling.navigationGeneration
    }
    private func scrollToBottom(_ command: TimelineScrollState.BottomCommand, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            // The tail spacer is a stable id; anchoring to its bottom edge is the
            // iOS 14 equivalent of `.scrollTo(edge: .bottom)`.
            proxy.scrollTo("tail", anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if scrolling.complete(command) { releaseScrollPosition() }
        }
    }
    private func releaseScrollPosition() {}
    private func historyDidLayOut(_ layout: TimelineHistoryLayout, proxy: ScrollViewProxy) {
        historyUpdates.submit(layout) { layout in
            if historyLayout != layout { historyLayout = layout }
            guard !navigationIsSuspended, var restoration = historyPosition else { return }
            let offset = restoration.laidOut(layout, generation: scrolling.navigationGeneration)
            if historyPosition != restoration { historyPosition = restoration }
            guard offset != nil else { return }
            // Pixel-accurate restoration is unavailable before iOS 17; re-anchor
            // to the row the page was measured against instead.
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(layout.anchorRowID, anchor: layout.edge == .top ? .top : .bottom)
            }
        }
    }
    private struct HistorySettlement: Equatable {
        let id: Int?
        let ready: Bool
        let offset: CGFloat?
    }
    private struct UserScrollSettlement: Equatable {
        let needed: Bool
        let tail: TimelineTailVisibility
        let generation: Int
    }
}

/// Keep the latest measurement without publishing View state inside a layout
/// callback. One main-queue delivery handles a burst; removal invalidates it.
@MainActor private final class ChatLayoutUpdate<Value> {
    private var pending: (() -> Void)?
    private var scheduled = false
    private var generation = 0

    func submit(_ value: Value, apply: @escaping (Value) -> Void) {
        pending = { apply(value) }
        guard !scheduled else { return }
        scheduled = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            let update = self.pending
            self.pending = nil
            self.scheduled = false
            update?()
        }
    }

    func cancel() {
        generation &+= 1
        pending = nil
        scheduled = false
    }
}

private struct ChatTimelineContent: View, Equatable {
    let model: SessionChatModel
    let onAttachment: (V2AttachmentContent) -> Void
    let onFile: (String) -> Void
    let latestPullReady: Bool
    let isLoadingLatest: Bool
    let olderPullReady: Bool
    let isLoadingOlder: Bool
    let keepsOlderPrompt: Bool
    let historyAnchor: TimelineHistoryLayout?
    let onLoadOlder: () -> Void
    let onLoadLatest: () -> Void
    let onHistoryLayout: (TimelineHistoryLayout) -> Void
    let onPromptVisibility: (Bool) -> Void
    let onOlderPromptVisibility: (Bool) -> Void
    let onTailVisibility: (TimelineTailVisibility.Region, Bool) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.latestPullReady == rhs.latestPullReady && lhs.isLoadingLatest == rhs.isLoadingLatest
            && lhs.olderPullReady == rhs.olderPullReady && lhs.isLoadingOlder == rhs.isLoadingOlder
            && lhs.keepsOlderPrompt == rhs.keepsOlderPrompt && lhs.historyAnchor == rhs.historyAnchor
    }
    var body: some View {
        let visibleNotices = model.session.notices.notices.filter { $0.isVisible && !$0.blocks(model.session.id) }
        let groups = TimelineGrouping.groups(model.timeline.rows, interactionTargets: Set(model.session.notices.notices
            .filter(\.isVisible).compactMap(\.timelineTargetID)))
        // Resolve notice targets once per body instead of once per row.
        let rowIDs = Set(model.timeline.rows.map(\.id))
        let noticesByTarget = Dictionary(grouping: visibleNotices.filter { $0.timelineTargetID != nil }) { $0.timelineTargetID! }
        let actions = TimelineTurnActions.build(groups: groups, suppressLatest: model.isRunning || model.session.hasNewerItems,
            hasPendingUserMessage: !model.session.hasNewerItems && (!model.timeline.pendingMessages.isEmpty || !model.session.pendingMessages.isEmpty))
        // Prefer a message whose start cannot move into a prefixed tool group.
        // For an all-tools page, retain the existing group's trailing edge.
        let anchorGroup = historyAnchor.flatMap { anchor in groups.first { $0.rows.contains { $0.id == anchor.anchorRowID } } }
            ?? groups.first { $0.rows.first?.structure.groupKind == .single } ?? groups.last
        let anchorEdge = historyAnchor?.edge ?? (anchorGroup?.rows.first?.structure.groupKind == .single ? .top : .bottom)
        // Keep actual row geometry available as Markdown grows and tool groups
        // change height. Hidden tool details own their deferred work separately.
        VStack(alignment: .leading, spacing: 20) {
            if model.session.hasOlderItems || keepsOlderPrompt {
                Group {
                    if isLoadingOlder {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular).compatControlSize(.small)
                            Text(L("正在加载较早的消息…"))
                        }.accessibilityElement(children: .combine)
                    } else if model.session.hasOlderItems {
                        Button(action: onLoadOlder) {
                            Text(olderPullReady ? L("松开加载较早的消息") : L("加载较早的消息"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }.disabled(model.session.isLoadingHistory || isLoadingLatest)
                    } else {
                        // Retain the prompt's footprint on the final page; removing
                        // it after restoring would move the reader by another row.
                        Text(L("已到达会话开头")).foregroundColor(.secondary)
                    }
                }
                .font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                .compatVisibilityProbe(id: "older-prompt", space: ChatTimelineView.space)
            }
            ForEach(groups) { group in
                SessionTimelineGroupView(group: group, chat: model, onAttachment: onAttachment, onFile: onFile,
                    turnAction: actions[group.id],
                    inlineNotices: group.rows.flatMap { noticesByTarget[$0.id] ?? [] })
                    .equatable()
                    .id(group.id)
                    .compatBackground {
                        if group.id == anchorGroup?.id, let firstRowID = model.timeline.rows.first?.id {
                            Color.clear.compatOnGeometryChange(of: { geometry in
                                let frame = geometry.frame(in: .named("chat.timeline.content"))
                                return TimelineHistoryLayout(firstRowID: firstRowID,
                                    anchorRowID: historyAnchor?.anchorRowID ?? group.id, edge: anchorEdge,
                                    y: anchorEdge == .top ? frame.minY : frame.maxY)
                            }, action: { layout in onHistoryLayout(layout) })
                        }
                    }
            }
            ForEach(visibleNotices.filter { notice in
                notice.timelineTargetID.map { !rowIDs.contains($0) } ?? true
            }) { item in SessionInteractionCard(item: item, chat: model) }
            ForEach(model.timeline.pendingMessages) { pending in
                PendingMessageRow(pending: pending, chat: model, onAttachment: onAttachment,
                    onDismiss: { model.session.dismissPendingMessage(id: pending.id) })
                    .id(pending.id)
            }
            if model.session.hasNewerItems {
                Button(action: onLoadLatest) {
                    Group {
                        if isLoadingLatest { ProgressView(L("正在加载更新的记录…")) }
                        else { Text(latestPullReady ? L("松开加载更新的记录") : L("继续上拉加载更新的记录")) }
                    }.font(.footnote).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.session.isLoadingHistory || isLoadingLatest || isLoadingOlder)
                .compatVisibilityProbe(id: "newer-prompt", space: ChatTimelineView.space)
            }
            // Constant breathing room: status text and card counts cannot
            // change this spacer or create a spurious follow request.
            Group {
                if let text = model.sendingPlaceholder {
                    HStack(spacing: 8) {
                        ProgressView().compatControlSize(.small)
                        Text(text).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                } else { Color.clear }
            }.frame(height: 32)
                .traceChatLayout("tail-spacer")
                .compatOverlay(alignment: .bottom) {
                    Color.clear.frame(height: 96)
                        .compatVisibilityProbe(id: "tail-near", space: ChatTimelineView.space)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .compatOverlay(alignment: .bottom) {
                    Color.clear.frame(height: 2)
                        .compatVisibilityProbe(id: "tail-end", space: ChatTimelineView.space)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .id("tail")
        }
        .modifier(ChatPageContentColumn(horizontalInset: nil))
        .coordinateSpace(name: "chat.timeline.content")
        .traceChatLayout("timeline-content", state: "groups=\(groups.count), footers=\(actions.count), running=\(model.isRunning)")
    }

}

/// Native offset storage deliberately does not invalidate the SwiftUI view tree.
@MainActor private final class ChatViewportSample {
    var value: TimelineViewport?
}
