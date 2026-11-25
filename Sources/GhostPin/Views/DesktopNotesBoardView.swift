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
    private static let headerHeight: CGFloat = 39
    private static let toolbarHeight: CGFloat = 40
    private static let footerHeight: CGFloat = 25
    private static let maximumBodyHeight: CGFloat = 396
    private static let emptyBodyHeight: CGFloat = 80

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = maximumBodyHeight

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
    }

    private func quadrantHeading(_ cell: HudQuadrantCell) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(quadrantTitle(cell.quadrant))
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

    private func quadrantTitle(_ quadrant: HudQuadrant) -> String {
        switch quadrant {
        case .importantUrgent:
            return "优先处理"
        case .importantNotUrgent:
            return "安排时间"
        case .generalUrgent:
            return "及时处理"
        case .generalNotUrgent:
            return "稍后处理"
        }
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
                    item: item, quadrant: effectiveQuadrant, isOverdue: item.isOverdue(now: now), isInteractive: isInteractive
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

private struct DesktopNoteRowView: View {
    let item: TodoItem
    let quadrant: HudQuadrant
    let isOverdue: Bool
    let isInteractive: Bool
    let onAdvanceStatus: () -> Void

    @State private var isHovering = false
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(isHovering && isInteractive ? 0.06 : 0))
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
