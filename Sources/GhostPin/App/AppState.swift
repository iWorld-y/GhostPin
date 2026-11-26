import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI
import GhostPinCore

#if DEBUG
private let hudLogger = Logger(subsystem: "com.oyuxi.TodoPin", category: "HUD")
#endif

@MainActor
final class AppState: ObservableObject {
    let todoStore: TodoStore
    let preferences: AppPreferences

    @Published var lastErrorMessage: String?

    @Published var hotKeySetupState: HotKeySetupState = .disabled
    @Published var hotKeyNotice: String?

    /// 隐藏窗口或窗口失焦时递增，通知 HUD 视图清除当前拖动。
    @Published private(set) var hudDragCancelToken: Int = 0

    private let todosURL: URL
    private var todoFileWatcher: TodoFileWatcher?
    private var hotKeyService: HotKeyService?
    private var hotKeyStateBeforeRecording: HotKeySetupState?
    private let notificationService = NotificationService()
    private lazy var reminderService = ReminderService(
        todoStore: todoStore,
        notificationService: notificationService
    )
    private var cancellables: Set<AnyCancellable> = []
    private var dayChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var statusClickTimes: [TodoItem.ID: UInt64] = [:]

    private let statusClickCooldownNanoseconds: UInt64 = 500_000_000

    lazy var windowCoordinator = WindowCoordinator(appState: self)

    var isBoardVisible: Bool {
        windowCoordinator.isBoardVisible
    }

    init() {
        let fileManager = FileManager.default
        let fallbackDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GhostPin", isDirectory: true)

        let resolvedTodosURL: URL
        let legacyTodosURL: URL?
        let storageResolutionError: Error?
        do {
            let currentURL = try StorageLocations.todosURL(fileManager: fileManager)
            let legacyURL = try StorageLocations.legacyTodosURL(fileManager: fileManager)
            resolvedTodosURL = currentURL
            legacyTodosURL = legacyURL
            storageResolutionError = nil
        } catch {
            resolvedTodosURL = fallbackDirectory.appendingPathComponent("todos.json")
            legacyTodosURL = nil
            storageResolutionError = error
        }

        self.todosURL = resolvedTodosURL
        self.todoStore = TodoStore(fileURL: resolvedTodosURL, legacyFileURL: legacyTodosURL, fileManager: fileManager)
        self.preferences = AppPreferences(defaults: AppPreferences.liveDefaults())
        self.hotKeySetupState = preferences.hudModeHotKeyEnabled ? .pendingConfiguration : .disabled

        if let storageResolutionError {
            lastErrorMessage = storageResolutionError.localizedDescription
        } else {
            do {
                try todoStore.load()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        // 隔离验证不触碰真实登录项（打包 ID 与正式 App 相同，reconcile 可能注销用户登录项）。
        if !AppPreferences.isIsolatedVerification {
            do {
                try LaunchAtLoginService.reconcile(preferredEnabled: preferences.launchAtLogin)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        todoStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        // 隔离验证不发起真实系统通知授权请求。
        if !AppPreferences.isIsolatedVerification {
            notificationService.requestAuthorization()
        }
        reminderService.start()
        windowCoordinator.showBoard()

        let watcher = TodoFileWatcher(directoryURL: todosURL.deletingLastPathComponent()) { [weak self] in
            self?.reloadTodosFromDisk()
        }
        todoFileWatcher = watcher
        watcher.start()

        let service = HotKeyService { [weak self] in
            self?.toggleHUDMode()
        }
        hotKeyService = service
        restoreHotKeyRegistration()

        // 跨日与唤醒后重算「今天新增」和紧急程度；投影在渲染时取当前时间。
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main,
            using: refresh
        )
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main,
            using: refresh
        )
    }

    func stop() {
        reminderService.stop()
        todoFileWatcher?.stop()
        hotKeyService?.unregister()
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        dayChangeObserver = nil
        wakeObserver = nil
    }

    func showBoard() {
        windowCoordinator.showBoard()
    }

    func hideBoard() {
        windowCoordinator.hideBoard()
    }

    func toggleBoard() {
        windowCoordinator.toggleBoard()
    }

    func toggleHUDMode() {
        preferences.hudMode = preferences.hudMode == .interactive ? .passthrough : .interactive
        #if DEBUG
        hudLogger.info("toggleHUDMode mode=\(self.preferences.hudMode.rawValue, privacy: .public) view=\(self.preferences.effectiveHudView.rawValue, privacy: .public)")
        #endif
        windowCoordinator.updateHUD()
        windowCoordinator.applyHUDInteraction()
    }

    /// 交互模式下主动选择视图；穿透模式不提供切换入口。
    func setHudInteractiveView(_ view: HudView) {
        guard preferences.hudMode == .interactive, preferences.hudInteractiveView != view else {
            return
        }
        preferences.hudInteractiveView = view
        #if DEBUG
        hudLogger.info("setHudInteractiveView view=\(view.rawValue, privacy: .public)")
        #endif
        windowCoordinator.updateHUD()
    }

    func updateHUD() {
        windowCoordinator.updateHUD()
    }

    func setCompleted(_ item: TodoItem, completed: Bool) {
        do {
            try todoStore.setCompleted(item.id, completed: completed)
        } catch {
            report(error)
        }
    }

    func advanceStatus(_ item: TodoItem) {
        let now = DispatchTime.now().uptimeNanoseconds
        if let lastClick = statusClickTimes[item.id],
           now - lastClick < statusClickCooldownNanoseconds {
            return
        }

        do {
            guard try todoStore.advanceStatus(item.id) != nil else {
                return
            }
            statusClickTimes[item.id] = now
        } catch {
            report(error)
        }
    }

    func cancelHudDrag() {
        hudDragCancelToken += 1
    }

    /// HUD 四象限投放：模式、视图或范围已变化时静默取消，其余交给 Core 受限写入。
    /// 返回界面反馈文案；nil 表示无需提示。
    func dropTaskInQuadrants(_ item: TodoItem, from: HudQuadrant, to: HudQuadrant, startedIn scope: HudScope) -> String? {
        guard preferences.hudMode == .interactive,
              preferences.effectiveHudView == .quadrants,
              preferences.hudScope == scope else {
            return nil
        }
        do {
            switch try todoStore.dragToQuadrant(item.id, from: from, to: to, scope: scope) {
            case .moved:
                return "已移到「\(to.displayTitle)」"
            case .unchanged:
                return nil
            case .taskChanged:
                return "任务已变更，本次拖动未保存"
            case let .dueDateRestricted(latest):
                return latest.isOverdue() ? "已逾期的任务不能放入不紧急象限" : "今天到期的任务不能放入不紧急象限"
            }
        } catch {
            report(error)
            return "保存失败：\(error.localizedDescription)"
        }
    }

    /// HUD 单列投放：只在 Todo 与 Doing 之间切换，守卫与四象限投放一致。
    func dropTaskInList(_ item: TodoItem, from: TodoStatus, to: TodoStatus, startedIn scope: HudScope) -> String? {
        guard preferences.hudMode == .interactive,
              preferences.effectiveHudView == .list,
              preferences.hudScope == scope else {
            return nil
        }
        do {
            switch try todoStore.dragToStatus(item.id, from: from, to: to, scope: scope) {
            case .moved:
                return "已移到 \(to == .doing ? "Doing" : "Todo")"
            case .unchanged, .dueDateRestricted:
                return nil
            case .taskChanged:
                return "任务已变更，本次拖动未保存"
            }
        } catch {
            report(error)
            return "保存失败：\(error.localizedDescription)"
        }
    }

    func updateBoardLevel() {
        windowCoordinator.updateHUD()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            preferences.launchAtLogin = enabled
        } catch {
            preferences.launchAtLogin = false
            report(error)
        }
    }

    func setHudModeHotKeyEnabled(_ enabled: Bool) {
        hotKeyNotice = nil
        if enabled {
            guard let shortcut = preferences.hudModeHotKeyShortcut else {
                hotKeySetupState = .pendingConfiguration
                return
            }
            do {
                try hotKeyService?.register(shortcut)
                preferences.hudModeHotKeyEnabled = true
                hotKeySetupState = .registered
            } catch {
                hotKeySetupState = .failure(error.localizedDescription)
            }
        } else {
            hotKeyService?.unregister()
            preferences.hudModeHotKeyEnabled = false
            hotKeySetupState = .disabled
        }
    }

    func clearHudModeHotKeyShortcut() {
        hotKeyService?.unregister()
        preferences.hudModeHotKeyEnabled = false
        preferences.hudModeHotKeyShortcut = nil
        hotKeyNotice = nil
        hotKeySetupState = .disabled
    }

    func beginHotKeyRecording() {
        hotKeyNotice = nil
        hotKeyStateBeforeRecording = hotKeySetupState
        hotKeyService?.unregister()
    }

    func cancelHotKeyRecording() {
        guard let previous = hotKeyStateBeforeRecording else {
            return
        }
        hotKeyStateBeforeRecording = nil
        if case .registered = previous {
            restoreHotKeyRegistration()
        } else {
            hotKeySetupState = previous
        }
    }

    func submitHotKeyCandidate(_ candidate: HotKeyShortcut) {
        hotKeyStateBeforeRecording = nil
        let previousShortcut = preferences.hudModeHotKeyShortcut
        let wasEnabled = preferences.hudModeHotKeyEnabled

        do {
            try hotKeyService?.register(candidate)
            preferences.hudModeHotKeyShortcut = candidate
            preferences.hudModeHotKeyEnabled = true
            hotKeySetupState = .registered
            hotKeyNotice = nil
        } catch {
            restoreFailedCandidate(candidate, error: error, previousShortcut: previousShortcut, wasEnabled: wasEnabled)
        }
    }

    private func restoreFailedCandidate(
        _ candidate: HotKeyShortcut,
        error: Error,
        previousShortcut: HotKeyShortcut?,
        wasEnabled: Bool
    ) {
        if wasEnabled, let previousShortcut {
            do {
                try hotKeyService?.register(previousShortcut)
                hotKeySetupState = .registered
                hotKeyNotice = "「\(candidate.displayName)」不可用（\(error.localizedDescription)），已恢复原快捷键。"
            } catch {
                hotKeySetupState = .failure("「\(candidate.displayName)」不可用（\(error.localizedDescription)），且原快捷键恢复失败。")
            }
        } else {
            hotKeySetupState = .failure(error.localizedDescription)
        }
    }

    private func restoreHotKeyRegistration() {
        guard preferences.hudModeHotKeyEnabled, let shortcut = preferences.hudModeHotKeyShortcut else {
            hotKeySetupState = preferences.hudModeHotKeyEnabled ? .pendingConfiguration : .disabled
            return
        }
        if hotKeyService?.registeredShortcut == shortcut {
            hotKeySetupState = .registered
            return
        }
        do {
            try hotKeyService?.register(shortcut)
            hotKeySetupState = .registered
        } catch {
            hotKeySetupState = .failure(error.localizedDescription)
        }
    }

    private func reloadTodosFromDisk() {
        do {
            try todoStore.load()
        } catch {
            report(error)
        }
    }

    func report(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}

#if DEBUG
extension AppState {
    /// 拖动自测：隔离根内驱动真实投放入口，校验守卫、反馈与持久化；不创建窗口、不读桌面。
    func runDragSelfTest() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let dueToday = min(now.addingTimeInterval(60), calendar.ghostPinDayEnd(for: now))
        let overdueAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 - 3600))
        var ok = true
        func expect(_ name: String, _ condition: Bool) {
            print("SELFTEST \(name) \(condition ? "PASS" : "FAIL")")
            ok = ok && condition
        }

        preferences.hudMode = .interactive
        preferences.hudInteractiveView = .quadrants
        preferences.hudScope = .all

        guard let later = try? todoStore.add(title: "自测稍后", group: "默认", important: false, urgent: false, createdAt: now),
              let today = try? todoStore.add(title: "自测今天到期", group: "默认", important: false, urgent: false, createdAt: now, dueAt: dueToday),
              let manual = try? todoStore.add(title: "自测手动紧急", group: "默认", important: false, urgent: true, createdAt: now) else {
            print("SELFTEST seed FAIL")
            return false
        }

        let movedNotice = dropTaskInQuadrants(later, from: .generalNotUrgent, to: .importantUrgent, startedIn: .all)
        let movedItem = todoStore.items.first { $0.id == later.id }
        expect("quadrantMove", movedNotice == "已移到「优先处理」" && movedItem?.important == true && movedItem?.urgent == true)
        let projection = todoStore.hudQuadrantProjection(scope: .all)
        expect("quadrantCounts", projection.cell(.importantUrgent).count == 1 && projection.cell(.generalUrgent).count == 2 && projection.cell(.generalNotUrgent).count == 0)
        expect("sameCell", dropTaskInQuadrants(later, from: .importantUrgent, to: .importantUrgent, startedIn: .all) == nil)

        let blockedNotice = dropTaskInQuadrants(today, from: .generalUrgent, to: .generalNotUrgent, startedIn: .all)
        let blockedItem = todoStore.items.first { $0.id == today.id }
        expect("dueBlocked", blockedNotice == "今天到期的任务不能放入不紧急象限" && blockedItem?.important == false && blockedItem?.urgent == false)

        preferences.hudMode = .passthrough
        expect("modeGuard", dropTaskInQuadrants(manual, from: .generalUrgent, to: .importantUrgent, startedIn: .all) == nil)
        preferences.hudMode = .interactive
        preferences.hudInteractiveView = .list
        expect("viewGuard", dropTaskInQuadrants(manual, from: .generalUrgent, to: .importantUrgent, startedIn: .all) == nil)
        preferences.hudInteractiveView = .quadrants
        expect("scopeGuard", dropTaskInQuadrants(manual, from: .generalUrgent, to: .importantUrgent, startedIn: .today) == nil)
        expect("guardNoWrite", todoStore.items.first { $0.id == manual.id }?.important == false)

        preferences.hudInteractiveView = .list
        preferences.hudFocusDoing = true
        preferences.hudMaxItems = 8
        let listNotice = dropTaskInList(manual, from: .todo, to: .doing, startedIn: .all)
        expect("listMove", listNotice == "已移到 Doing" && todoStore.items.first { $0.id == manual.id }?.status == .doing)

        guard let second = try? todoStore.add(title: "自测第二条", group: "默认", important: false, urgent: false, createdAt: now) else {
            print("SELFTEST seedSecond FAIL")
            return false
        }
        _ = try? todoStore.setStatus(second.id, status: .doing)
        let backNotice = dropTaskInList(manual, from: .doing, to: .todo, startedIn: .all)
        let focused = todoStore.hudProjection(scope: .all, maxCount: 8, focusDoing: true)
        expect("focusBack", backNotice == "已移到 Todo" && focused.doing.map(\.id) == [second.id] && focused.todo.isEmpty && focused.todoCount >= 1)

        preferences.hudFocusDoing = false
        preferences.hudMaxItems = 1
        let limited = todoStore.hudProjection(scope: .all, maxCount: 1, focusDoing: false)
        expect("limitHidden", limited.doing.count == 1 && limited.todo.isEmpty)
        let limitNotice = dropTaskInList(second, from: .doing, to: .todo, startedIn: .all)
        expect("limitMove", limitNotice == "已移到 Todo" && todoStore.items.first { $0.id == second.id }?.status == .todo)

        guard let overdueItem = try? todoStore.add(title: "自测逾期", group: "默认", important: true, urgent: false, createdAt: now, dueAt: overdueAt) else {
            print("SELFTEST seedOverdue FAIL")
            return false
        }
        _ = try? todoStore.setStatus(overdueItem.id, status: .doing)
        let overdueNotice = dropTaskInList(overdueItem, from: .doing, to: .todo, startedIn: .all)
        let overdueLatest = todoStore.items.first { $0.id == overdueItem.id }
        expect("overdueSwitch", overdueNotice == "已移到 Todo" && overdueLatest?.status == .todo && overdueLatest?.dueAt == overdueAt)

        try? todoStore.delete(second.id)
        expect("deletedRejected", dropTaskInList(second, from: .todo, to: .doing, startedIn: .all) == "任务已变更，本次拖动未保存")

        let reloaded = TodoStore(fileURL: todosURL)
        try? reloaded.load()
        expect("persisted", reloaded.items.first { $0.id == later.id }?.important == true
            && reloaded.items.first { $0.id == manual.id }?.status == .todo
            && reloaded.items.first { $0.id == overdueItem.id }?.status == .todo)

        // 手势生命周期回归：与视图回调共用 HudDragLifecycle 判定。
        var lifecycle = HudDragLifecycle()
        let dragItem = todoStore.items.first { $0.id == later.id } ?? later
        let startContext = HudDragContext(isInteractive: true, view: .quadrants, scope: .all, cancelToken: 0)
        let cancelledContext = HudDragContext(isInteractive: true, view: .quadrants, scope: .all, cancelToken: 1)
        let origin = CGPoint(x: 40, y: 40)
        let dropPoint = CGPoint(x: 300, y: 60)

        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: startContext)
        expect("gestureSession", lifecycle.session?.item.id == dragItem.id
            && lifecycle.session?.startQuadrant == .importantUrgent
            && lifecycle.session?.startContext == startContext)

        // 环境取消后，同一物理手势的旧 change/up 全部无效。
        lifecycle.cancel()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: dropPoint, context: cancelledContext)
        expect("cancelBlocksStaleMove", lifecycle.session == nil)
        expect("cancelBlocksStaleEnd", lifecycle.end(dragItem, at: dropPoint, context: cancelledContext) == nil)

        // 松手后一次全新手势正常开始。
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("freshGestureAfterCancel", lifecycle.session != nil)

        // 投放同步核对取消代次/视图/范围，不依赖下一帧 onChange。
        expect("staleTokenEnd", lifecycle.end(dragItem, at: dropPoint, context: startContext) == nil)
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("staleViewEnd", lifecycle.end(dragItem, at: dropPoint, context: HudDragContext(isInteractive: true, view: .list, scope: .all, cancelToken: 1)) == nil)
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("staleScopeEnd", lifecycle.end(dragItem, at: dropPoint, context: HudDragContext(isInteractive: true, view: .quadrants, scope: .today, cancelToken: 1)) == nil)

        // 穿透模式：移动立即作废会话，投放被拒。
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        let passthroughContext = HudDragContext(isInteractive: false, view: .list, scope: .all, cancelToken: 1)
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: dropPoint, context: passthroughContext)
        expect("passthroughCancels", lifecycle.session == nil)
        expect("passthroughEnd", lifecycle.end(dragItem, at: dropPoint, context: passthroughContext) == nil)

        // 源手柄消失：清理会话并封锁残留回调；新手势仍可开始。
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        lifecycle.cancelSource(dragItem.id)
        expect("sourceGoneCancels", lifecycle.session == nil)
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: dropPoint, context: cancelledContext)
        expect("sourceGoneBlocksStaleMove", lifecycle.session == nil)
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("sourceGoneFreshGesture", lifecycle.session != nil)

        // 手势被系统取消（GestureState 复位，无 onEnded）：清理残留并解除封锁。
        lifecycle.gestureFinished(dragItem.id)
        expect("gestureResetCancels", lifecycle.session == nil)
        lifecycle.begin()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("gestureResetFreshGesture", lifecycle.session != nil)

        // 其他任务的旧 up 不影响当前会话；有效投放返回会话并清空。
        expect("otherItemEndIgnored", lifecycle.end(manual, at: dropPoint, context: cancelledContext) == nil && lifecycle.session != nil)
        let ended = lifecycle.end(dragItem, at: dropPoint, context: cancelledContext)
        expect("validEndReturnsSession", ended?.item.id == dragItem.id && ended?.location == dropPoint && lifecycle.session == nil)

        // 无会话时取消不应封锁后续手势。
        lifecycle.cancel()
        lifecycle.move(dragItem, quadrant: .importantUrgent, to: origin, context: cancelledContext)
        expect("idleCancelNoPoison", lifecycle.session != nil)
        lifecycle.gestureFinished(dragItem.id)

        // 预览放置：最小 HUD 与右下角不越界，指针处仍可命中落点。
        let preview = DesktopNotesBoardView.dragPreviewSize
        let margin: CGFloat = 8
        func previewFits(_ location: CGPoint, _ board: CGSize) -> Bool {
            let offset = DesktopNotesBoardView.dragPreviewOffset(for: location, boardSize: board)
            return offset.x >= margin && offset.y >= margin
                && offset.x + preview.width <= board.width - margin
                && offset.y + preview.height <= board.height - margin
        }
        let listMin = DesktopNotesBoardView.interactiveMinimumSize
        let quadrantMin = DesktopNotesBoardView.quadrantsMinimumSize
        let listBoard = CGSize(width: listMin.width, height: listMin.height)
        let quadrantBoard = CGSize(width: quadrantMin.width, height: quadrantMin.height)
        expect("previewCenter", DesktopNotesBoardView.dragPreviewOffset(for: CGPoint(x: 100, y: 60), boardSize: quadrantBoard) == CGPoint(x: 114, y: 74))
        expect("previewMinListCorner", previewFits(CGPoint(x: listBoard.width - 1, y: listBoard.height - 1), listBoard))
        expect("previewMinQuadrantCorner", previewFits(CGPoint(x: quadrantBoard.width - 1, y: quadrantBoard.height - 1), quadrantBoard))
        expect("previewRightEdge", previewFits(CGPoint(x: quadrantBoard.width - 2, y: 100), quadrantBoard))
        expect("previewBottomEdge", previewFits(CGPoint(x: 100, y: quadrantBoard.height - 2), quadrantBoard))
        expect("previewOutsideClamped", previewFits(CGPoint(x: quadrantBoard.width + 40, y: quadrantBoard.height + 40), quadrantBoard))
        let cornerOffset = DesktopNotesBoardView.dragPreviewOffset(for: CGPoint(x: listBoard.width - 1, y: listBoard.height - 1), boardSize: listBoard)
        expect("previewCornerClearsPointer", cornerOffset.x + preview.width < listBoard.width - 1 && cornerOffset.y + preview.height < listBoard.height - 1)

        let token = hudDragCancelToken
        cancelHudDrag()
        expect("cancelToken", hudDragCancelToken == token + 1)
        return ok
    }
}
#endif
