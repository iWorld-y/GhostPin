import Combine
import Foundation
import SwiftUI
import TodoPinCore

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

    lazy var windowCoordinator = WindowCoordinator(appState: self)

    var isBoardVisible: Bool {
        windowCoordinator.isBoardVisible
    }

    init() {
        let fileManager = FileManager.default
        let fallbackDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TodoPin", isDirectory: true)

        self.todosURL = (try? StorageLocations.todosURL(fileManager: fileManager))
            ?? fallbackDirectory.appendingPathComponent("todos.json")

        self.todoStore = TodoStore(fileURL: self.todosURL, fileManager: fileManager)
        self.preferences = AppPreferences()

        do {
            try todoStore.load()
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
