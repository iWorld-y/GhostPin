import Combine
import Foundation
import SwiftUI
import GhostPinCore

final class AppState: ObservableObject {
    let todoStore: TodoStore
    let preferences: AppPreferences

    @Published var lastErrorMessage: String?

    private let todosURL: URL
    private var todoFileWatcher: TodoFileWatcher?
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
    }

    func stop() {
        reminderService.stop()
        todoFileWatcher?.stop()
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
