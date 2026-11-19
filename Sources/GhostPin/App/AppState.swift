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
