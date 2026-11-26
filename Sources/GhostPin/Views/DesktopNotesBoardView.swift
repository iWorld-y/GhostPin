import AppKit
import SwiftUI
import GhostPinCore

struct DesktopNotesBoardView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void
    let onPreferredHeightChange: (CGFloat) -> Void

    static let defaultWidth: CGFloat = 380
    static let minimumSize = NSSize(width: 320, height: 144)
    /// 交互列表最小高度：header 39 + toolbar 40 + 空状态 80 + footer 25。
    static let interactiveMinimumSize = NSSize(width: 320, height: 184)
    static let quadrantsDefaultSize = NSSize(width: 720, height: 592)
    static let quadrantsMinimumSize = NSSize(width: 560, height: 320)
    static let hudCoordinateSpace = "GhostPinHUD"
    private static let headerHeight: CGFloat = 39
    private static let toolbarHeight: CGFloat = 40
    private static let footerHeight: CGFloat = 25
    private static let maximumBodyHeight: CGFloat = 396
    private static let emptyBodyHeight: CGFloat = 80
    /// 预览放置用的保守外框：宽 220 + 水平内边距，高按两行文案预留。
    static let dragPreviewSize = CGSize(width: 240, height: 44)
    private static let dragPreviewMargin: CGFloat = 8
    private static let dragPreviewGap: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = maximumBodyHeight
    @State private var dragLifecycle = HudDragLifecycle()
    @State private var dragNotice: String?
    @State private var dropFrames: [HudDropTarget: CGRect] = [:]

    private var drag: TaskDragSession? { dragLifecycle.session }
    private var dragContext: HudDragContext {
        HudDragContext(
            isInteractive: isInteractive,
            view: appState.preferences.effectiveHudView,
            scope: appState.preferences.hudScope,
            cancelToken: appState.hudDragCancelToken
        )
    }

    var body: some View {
        let view = appState.preferences.effectiveHudView
        let now = Date()
        // 仅计算当前视图所需的投影，避免每次 body 都排序两份。
        let listProjection: HudProjection? = view == .list ? projectList(now: now) : nil
        let quadrantProjection: HudQuadrantProjection? = view == .quadrants ? projectQuadrants(now: now) : nil
        let isEmpty = listProjection.map { $0.doing.isEmpty && $0.todo.isEmpty } ?? false
        let doingCount = quadrantProjection?.doingCount ?? listProjection?.doingCount ?? 0
        let todoCount = quadrantProjection?.todoCount ?? listProjection?.todoCount ?? 0
        let visibleCount = quadrantProjection.map { $0.doingCount + $0.todoCount }
            ?? listProjection.map { $0.doing.count + $0.todo.count } ?? 0

        GeometryReader { geometry in
            VStack(spacing: 0) {
                header(doingCount: doingCount, todoCount: todoCount)
                    .frame(height: Self.headerHeight)

                if isInteractive {
                    viewToolbar
                        .frame(height: Self.toolbarHeight)
                }

                boardBody(
                    view,
                    listProjection: listProjection,
                    quadrantProjection: quadrantProjection,
                    now: now,
                    availableHeight: geometry.size.height - Self.headerHeight - Self.footerHeight - (isInteractive ? Self.toolbarHeight : 0)
                )

                if view == .list {
                    Spacer(minLength: 0)
                }

                footer(visibleCount: visibleCount, totalCount: doingCount + todoCount)
                    .frame(height: Self.footerHeight)
            }
            .overlay(alignment: .topLeading) { dragPreviewOverlay(boardSize: geometry.size) }
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(isInteractive ? 0.14 : 0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            if let dragNotice {
                dragNoticeView(dragNotice)
            }
        }
        .shadow(color: .black.opacity(isInteractive ? 0.18 : 0.11), radius: 20, y: 8)
        .saturation(isInteractive ? 1 : 0.88)
        .onHover { hovering in
            // 指针隐身仍由窗口层处理，视图只提供指针位置事实。
            appState.windowCoordinator.setPointerInsideHUD(hovering)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isInteractive)
        .onAppear {
            if isEmpty {
                reportPreferredHeight(Self.emptyBodyHeight)
            }
        }
        .onChange(of: isEmpty) { _, empty in
            if empty {
                reportPreferredHeight(Self.emptyBodyHeight)
            }
        }
        .coordinateSpace(name: Self.hudCoordinateSpace)
        .onPreferenceChange(HudDropFrameKey.self) { frames in
            dropFrames = frames
        }
        .onChange(of: isInteractive) { _, _ in dragLifecycle.cancel() }
        .onChange(of: view) { _, _ in dragLifecycle.cancel() }
        .onChange(of: appState.preferences.hudScope) { _, _ in dragLifecycle.cancel() }
        .onChange(of: appState.hudDragCancelToken) { _, _ in dragLifecycle.cancel() }
    }

    @ViewBuilder
    private func boardBody(
        _ view: HudView,
        listProjection: HudProjection?,
        quadrantProjection: HudQuadrantProjection?,
        now: Date,
        availableHeight: CGFloat
    ) -> some View {
        if view == .quadrants, let quadrantProjection {
            quadrantGrid(quadrantProjection, now: now, height: max(0, availableHeight))
        } else if let listProjection {
            if listProjection.doing.isEmpty && listProjection.todo.isEmpty {
                emptyState
            } else {
                taskList(listProjection, now: now, availableHeight: availableHeight)
            }
        }
    }

    private var viewToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                viewButton("单列", view: .list)
                viewButton("四象限", view: .quadrants)
            }
            .padding(2)
            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("待办视图")

            Spacer(minLength: 4)

            Text("范围")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker("范围", selection: hudScopeBinding) {
                Text("全部未完成").tag(HudScope.all)
                Text("今天新增").tag(HudScope.today)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 11))
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func viewButton(_ title: String, view: HudView) -> some View {
        let selected = appState.preferences.hudInteractiveView == view
        return Button {
            appState.setHudInteractiveView(view)
        } label: {
            Text(title)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    selected ? Color(nsColor: .windowBackgroundColor) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .accessibilityLabel("\(title)视图")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var hudScopeBinding: Binding<HudScope> {
        Binding(
            get: { appState.preferences.hudScope },
            set: { appState.preferences.hudScope = $0 }
        )
    }

    private func quadrantGrid(_ projection: HudQuadrantProjection, now: Date, height: CGFloat) -> some View {
        let cellHeight = max(0, (height - 0.5) / 2)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                quadrantCell(projection.cell(.importantUrgent), now: now)
                quadrantSeparator(width: 0.5)
                quadrantCell(projection.cell(.importantNotUrgent), now: now)
            }
            .frame(height: cellHeight)
            quadrantSeparator(height: 0.5)
            HStack(spacing: 0) {
                quadrantCell(projection.cell(.generalUrgent), now: now)
                quadrantSeparator(width: 0.5)
                quadrantCell(projection.cell(.generalNotUrgent), now: now)
            }
            .frame(height: cellHeight)
        }
        .frame(height: height)
    }

    private func quadrantSeparator(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func quadrantCell(_ cell: HudQuadrantCell, now: Date) -> some View {
        VStack(spacing: 0) {
            quadrantHeading(cell)
            if cell.count == 0 {
                quadrantEmptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        if !cell.doing.isEmpty {
                            taskSection("Doing", items: cell.doing, count: cell.doing.count, isDoing: true, now: now, quadrant: cell.quadrant)
                        }
                        if !cell.todo.isEmpty {
                            taskSection("Todo", items: cell.todo, count: cell.todo.count, isDoing: false, now: now, quadrant: cell.quadrant)
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropFrameReporter(.quadrant(cell.quadrant)))
        .overlay {
            if let drag, dropTarget(at: drag.location) == .quadrant(cell.quadrant) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dropStrokeColor(for: .quadrant(cell.quadrant), session: drag), lineWidth: 2)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func quadrantHeading(_ cell: HudQuadrantCell) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(cell.quadrant.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(cell.quadrant == .importantUrgent ? Color.red : Color.primary)
                Text(quadrantSubtitle(cell.quadrant))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\(cell.count)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(cell.count) 个未完成任务")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private var quadrantEmptyState: some View {
        VStack(spacing: 4) {
            Text("暂无任务")
                .font(.system(size: 12))
            Text(appState.preferences.hudScope == .today ? "今天新增的任务中没有此类待办" : "符合分类的未完成任务会显示在这里")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quadrantSubtitle(_ quadrant: HudQuadrant) -> String {
        switch quadrant {
        case .importantUrgent:
            return "重要 · 紧急"
        case .importantNotUrgent:
            return "重要 · 不紧急"
        case .generalUrgent:
            return "一般 · 紧急"
        case .generalNotUrgent:
            return "一般 · 不紧急"
        }
    }

    private func header(doingCount: Int, todoCount: Int) -> some View {
        HStack(spacing: 8) {
            GhostPinLogoMark(size: 21, isMuted: !isInteractive)
            Text("GhostPin")
                .font(.system(size: 12.5, weight: .semibold))

            Spacer(minLength: 4)

            Text("Doing \(doingCount) · Todo \(todoCount)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("隐藏桌面便签")
            .accessibilityLabel("隐藏桌面便签")
            .disabled(!isInteractive)
            .opacity(isInteractive ? 1 : 0)
            .accessibilityHidden(!isInteractive)
        }
        .padding(.horizontal, 12)
    }

    private func taskList(_ projection: HudProjection, now: Date, availableHeight: CGFloat) -> some View {
        let viewportHeight = min(contentHeight, Self.maximumBodyHeight, max(0, availableHeight))

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if !projection.doing.isEmpty {
                    taskSection("Doing", items: projection.doing, count: projection.doingCount, isDoing: true, now: now)
                }
                if !projection.todo.isEmpty {
                    taskSection("Todo", items: projection.todo, count: projection.todoCount, isDoing: false, now: now)
                }
            }
            .padding(.bottom, 6)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: HUDContentHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: viewportHeight)
        .overlay(alignment: .bottom) {
            if contentHeight > viewportHeight + 1 {
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor).opacity(0), Color(nsColor: .windowBackgroundColor).opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            // 拖动期间的临时落点：不计入条数上限，也不改变窗口尺寸。
            if drag != nil {
                HStack(spacing: 8) {
                    listDropZone(.todo, title: "Todo")
                    listDropZone(.doing, title: "Doing")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }
        }
        .onPreferenceChange(HUDContentHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
            reportPreferredHeight(min(height, Self.maximumBodyHeight))
        }
    }

    private func taskSection(
        _ title: String,
        items: [TodoItem],
        count: Int,
        isDoing: Bool,
        now: Date,
        quadrant: HudQuadrant? = nil
    ) -> some View {
        let nextDayStart = Calendar.current.ghostPinNextDayStart(after: now)
        return Section {
            ForEach(items) { item in
                let effectiveQuadrant = quadrant ?? HudQuadrant.classify(
                    important: item.important, urgent: item.urgent, dueAt: item.dueAt, nextDayStart: nextDayStart
                )
                DesktopNoteRowView(
                    item: item, quadrant: effectiveQuadrant, isOverdue: item.isOverdue(now: now), isInteractive: isInteractive,
                    isDragSource: drag?.item.id == item.id,
                    onDragEvent: { event in handleDragEvent(event, item: item, quadrant: effectiveQuadrant) }
                ) {
                    appState.advanceStatus(item)
                }
                // 状态变化时重建行，避免跨分区移动后复用旧图标和动作说明。
                .id("\(item.id):\(item.status.rawValue)")
                .overlay(alignment: .top) {
                    if item.id != items.first?.id {
                        Rectangle()
                            .fill(.primary.opacity(0.08))
                            .frame(height: 0.5)
                            .allowsHitTesting(false)
                    }
                }
            }
        } header: {
            HStack(spacing: 5) {
                if isDoing {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                }
                Text(title.uppercased())
                    .tracking(1)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
            }
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .accessibilityElement(children: .combine)
        }
    }

    private func footer(visibleCount: Int, totalCount: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isInteractive ? Color.primary : Color.secondary)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
                Text(isInteractive ? "交互模式" : "穿透模式")
            }

            Spacer(minLength: 4)

            Text("\(visibleCount) / \(totalCount)")
            Text(appState.preferences.hudScope == .all ? "全部" : "今天新增")

            if appState.preferences.hudModeHotKeyEnabled,
               case .registered = appState.hotKeySetupState,
               let shortcut = appState.preferences.hudModeHotKeyShortcut {
                Text(shortcut.displayName)
            }
        }
        .font(.system(size: 9.5, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("没有未完成待办")
                .font(.system(size: 12.5, weight: .medium))
            Text("ghostpin-cli add --help")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.emptyBodyHeight)
    }

    private func projectList(now: Date) -> HudProjection {
        appState.todoStore.hudProjection(
            scope: appState.preferences.hudScope,
            maxCount: appState.preferences.hudMaxItems,
            focusDoing: appState.preferences.hudFocusDoing,
            now: now
        )
    }

    private func projectQuadrants(now: Date) -> HudQuadrantProjection {
        appState.todoStore.hudQuadrantProjection(scope: appState.preferences.hudScope, now: now)
    }

    private var isInteractive: Bool {
        appState.preferences.hudMode == .interactive
    }

    private func handleDragEvent(_ event: HudDragGestureEvent, item: TodoItem, quadrant: HudQuadrant) {
        switch event {
        case .began:
            dragLifecycle.begin()
        case let .moved(location):
            dragLifecycle.move(item, quadrant: quadrant, to: location, context: dragContext)
        case let .ended(location):
            finishDrag(item, at: location)
        case .gestureReset:
            dragLifecycle.gestureFinished(item.id)
        case .sourceDisappeared:
            dragLifecycle.cancelSource(item.id)
        }
    }

    private func finishDrag(_ item: TodoItem, at location: CGPoint) {
        guard let session = dragLifecycle.end(item, at: location, context: dragContext) else { return }
        var notice: String?
        if let target = dropTarget(at: location) {
            switch target {
            case let .quadrant(to):
                if to != session.startQuadrant {
                    notice = appState.dropTaskInQuadrants(session.item, from: session.startQuadrant, to: to, startedIn: session.startContext.scope)
                }
            case let .status(to):
                if to != session.startStatus {
                    notice = appState.dropTaskInList(session.item, from: session.startStatus, to: to, startedIn: session.startContext.scope)
                }
            }
        }
        if let notice {
            dragNotice = notice
        }
    }

    /// 原分区/原状态不是有效目标：不显示有效高亮，投放也不改动。
    private func isSourceTarget(_ target: HudDropTarget, session: TaskDragSession) -> Bool {
        switch target {
        case let .quadrant(quadrant): return quadrant == session.startQuadrant
        case let .status(status): return status == session.startStatus
        }
    }

    private func dropStrokeColor(for target: HudDropTarget, session: TaskDragSession) -> Color {
        if isSourceTarget(target, session: session) {
            return .primary.opacity(0.2)
        }
        if isBlocked(target, item: session.item) {
            return .red.opacity(0.7)
        }
        return .accentColor.opacity(0.8)
    }

    private func dropTarget(at point: CGPoint) -> HudDropTarget? {
        if appState.preferences.effectiveHudView == .quadrants {
            for quadrant in HudQuadrant.allCases {
                if dropFrames[.quadrant(quadrant)]?.contains(point) == true {
                    return .quadrant(quadrant)
                }
            }
        } else {
            for status in [TodoStatus.doing, .todo] {
                if dropFrames[.status(status)]?.contains(point) == true {
                    return .status(status)
                }
            }
        }
        return nil
    }

    private func isBlocked(_ target: HudDropTarget, item: TodoItem) -> Bool {
        guard case let .quadrant(quadrant) = target, !quadrant.isUrgentColumn else { return false }
        let nextDayStart = Calendar.current.ghostPinNextDayStart(after: Date())
        return item.dueAt.map { $0 < nextDayStart } ?? false
    }

    private func blockReason(for item: TodoItem) -> String {
        item.isOverdue() ? "已逾期的任务不能放入不紧急象限" : "今天到期的任务不能放入不紧急象限"
    }

    private func dropTitle(_ target: HudDropTarget) -> String {
        switch target {
        case let .quadrant(quadrant): return quadrant.displayTitle
        case let .status(status): return status == .doing ? "Doing" : "Todo"
        }
    }

    private func dropFrameReporter(_ target: HudDropTarget) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: HudDropFrameKey.self, value: [target: proxy.frame(in: .named(Self.hudCoordinateSpace))])
        }
        .allowsHitTesting(false)
    }

    /// 预览默认在指针右下；贴近右/下边缘时翻到另一侧，并夹回板面可见区域。
    static func dragPreviewOffset(for location: CGPoint, boardSize: CGSize) -> CGPoint {
        let size = dragPreviewSize
        let maxX = max(dragPreviewMargin, boardSize.width - dragPreviewMargin - size.width)
        let maxY = max(dragPreviewMargin, boardSize.height - dragPreviewMargin - size.height)
        var x = location.x + dragPreviewGap
        if x > maxX {
            x = location.x - dragPreviewGap - size.width
        }
        var y = location.y + dragPreviewGap
        if y > maxY {
            y = location.y - dragPreviewGap - size.height
        }
        return CGPoint(x: min(max(x, dragPreviewMargin), maxX), y: min(max(y, dragPreviewMargin), maxY))
    }

    @ViewBuilder
    private func dragPreviewOverlay(boardSize: CGSize) -> some View {
        if let drag {
            let offset = Self.dragPreviewOffset(for: drag.location, boardSize: boardSize)
            dragPreview(drag)
                .offset(x: offset.x, y: offset.y)
                .allowsHitTesting(false)
        }
    }

    private func dragPreview(_ session: TaskDragSession) -> some View {
        let target = dropTarget(at: session.location)
        let isSource = target.map { isSourceTarget($0, session: session) } ?? false
        let blocked = target.map { isBlocked($0, item: session.item) } ?? false
        return VStack(alignment: .leading, spacing: 2) {
            Text(session.item.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if isSource {
                Text("放回原处，不改动")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if blocked {
                Text(blockReason(for: session.item))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            } else if let target {
                Text(dropTitle(target))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(blocked && !isSource ? Color.red.opacity(0.6) : .primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

    private func dragNoticeView(_ notice: String) -> some View {
        Text(notice)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.12), lineWidth: 0.5))
            .padding(.bottom, Self.footerHeight + 6)
            .allowsHitTesting(false)
            .task(id: notice) {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if !Task.isCancelled, dragNotice == notice {
                    dragNotice = nil
                }
            }
    }

    private func listDropZone(_ status: TodoStatus, title: String) -> some View {
        let hovered = drag.flatMap { dropTarget(at: $0.location) } == .status(status)
        let isSource = drag.map { isSourceTarget(.status(status), session: $0) } ?? false
        let active = hovered && !isSource
        return Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(active ? Color.accentColor : (hovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.15)), lineWidth: active ? 2 : 1)
            )
            .background(dropFrameReporter(.status(status)))
            .accessibilityLabel("\(title) 落点")
    }

    private func reportPreferredHeight(_ bodyHeight: CGFloat) {
        let toolbar = isInteractive ? Self.toolbarHeight : 0
        onPreferredHeightChange(Self.headerHeight + toolbar + bodyHeight + Self.footerHeight)
    }
}

private struct HUDContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum HudDropTarget: Hashable {
    case quadrant(HudQuadrant)
    case status(TodoStatus)
}

private struct HudDropFrameKey: PreferenceKey {
    static let defaultValue: [HudDropTarget: CGRect] = [:]

    static func reduce(value: inout [HudDropTarget: CGRect], nextValue: () -> [HudDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// 手柄命中区：禁止窗口背景拖动抢占，事件仍交给 SwiftUI 手势。
private struct DragHandleSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        HandleHitView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class HandleHitView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

extension HudQuadrant {
    var displayTitle: String {
        switch self {
        case .importantUrgent: return "优先处理"
        case .importantNotUrgent: return "安排时间"
        case .generalUrgent: return "及时处理"
        case .generalNotUrgent: return "稍后处理"
        }
    }
}

private struct DesktopNoteRowView: View {
    let item: TodoItem
    let quadrant: HudQuadrant
    let isOverdue: Bool
    let isInteractive: Bool
    var isDragSource: Bool = false
    var onDragEvent: ((HudDragGestureEvent) -> Void)? = nil
    let onAdvanceStatus: () -> Void

    @State private var isHovering = false
    /// 本行物理手势已上报开始；松手、复位或手柄移除时清零。
    @State private var hasBegun = false
    /// 手势结束或被系统取消时自动复位，作为不依赖 onEnded 的清理信号。
    @GestureState private var isGestureActive = false
    @FocusState private var isStatusFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: onAdvanceStatus) {
                Image(systemName: item.status == .doing ? "circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(item.status == .doing ? 0.64 : 0.35))
            .focusable()
            .focusEffectDisabled()
            .focused($isStatusFocused)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                guard isInteractive else { return .ignored }
                onAdvanceStatus()
                return .handled
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor.opacity(isStatusFocused ? 1 : 0), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .help(item.status == .doing ? "标记完成" : "开始处理")
            .accessibilityLabel("\(item.status == .doing ? "标记完成" : "开始处理")：\(item.title)")
            .disabled(!isInteractive)
            // 27 pt 命中区借用行内边距，布局仍按 15 pt 状态列对齐。
            .padding(-6)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .strikethrough(isOverdue, color: .red)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(quadrantLabel)
                        .font(.system(size: 10, weight: quadrant == .generalNotUrgent ? .regular : .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(quadrantColor)

                    Text(item.group)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: Self.groupTextWidth)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }

                if let dueAt = item.dueAt {
                    Text(Self.dueFormatter.string(from: dueAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(isOverdue ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 84, alignment: .trailing)

            if isInteractive, let onDragEvent {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(isHovering ? 0.9 : 0.45))
                    .frame(width: 16, height: 27)
                    .background(DragHandleSurface())
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named(DesktopNotesBoardView.hudCoordinateSpace))
                            .updating($isGestureActive) { _, state, _ in state = true }
                            .onChanged { value in
                                if !hasBegun {
                                    hasBegun = true
                                    onDragEvent(.began)
                                }
                                onDragEvent(.moved(value.location))
                            }
                            .onEnded { value in
                                hasBegun = false
                                onDragEvent(.ended(value.location))
                            }
                    )
                    .onChange(of: isGestureActive) { _, active in
                        if !active {
                            hasBegun = false
                            onDragEvent(.gestureReset)
                        }
                    }
                    .onDisappear {
                        hasBegun = false
                        onDragEvent(.sourceDisappeared)
                    }
                    .help("拖动调整")
                    .accessibilityLabel("拖动：\(item.title)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovering && isInteractive ? 0.06 : 0))
        .opacity(isDragSource ? 0.35 : 1)
        .onHover { isHovering = $0 }
    }

    private static let groupTextWidth = ("汉汉汉" as NSString).size(
        withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]
    ).width

    private var quadrantLabel: String {
        switch quadrant {
        case .importantUrgent: return "急重"
        case .importantNotUrgent: return "重要"
        case .generalUrgent: return "紧急"
        case .generalNotUrgent: return "稍后"
        }
    }

    private var quadrantColor: Color {
        switch quadrant {
        case .importantUrgent: return .red
        case .importantNotUrgent: return .primary.opacity(0.84)
        case .generalUrgent: return .orange
        case .generalNotUrgent: return .secondary
        }
    }

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
