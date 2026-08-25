import Combine
import Foundation
import SwiftUI
import GhostPinCore

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
        let storageResolutionError: Error?
        do {
            resolvedTodosURL = try StorageLocations.todosURL(fileManager: fileManager)
            storageResolutionError = nil
        } catch {
            resolvedTodosURL = fallbackDirectory.appendingPathComponent("todos.json")
            storageResolutionError = error
        }

        self.todosURL = resolvedTodosURL
        self.todoStore = TodoStore(fileURL: resolvedTodosURL, fileManager: fileManager)
        self.preferences = AppPreferences()
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

        do {
            try LaunchAtLoginService.reconcile(preferredEnabled: preferences.launchAtLogin)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        todoStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        notificationService.requestAuthorization()
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
    }

    func stop() {
        reminderService.stop()
        todoFileWatcher?.stop()
        hotKeyService?.unregister()
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
        windowCoordinator.updateHUD()
        windowCoordinator.applyHUDInteraction()
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

        guard let current = todoStore.items.first(where: { $0.id == item.id }) else {
            return
        }
        let nextStatus: TodoStatus?
        switch current.status {
        case .todo:
            nextStatus = .doing
        case .doing:
            nextStatus = .done
        case .done:
            nextStatus = nil
        }
        guard let nextStatus else {
            return
        }

        do {
            guard let updated = try todoStore.setStatus(item.id, status: nextStatus),
                  updated.status == nextStatus else {
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
