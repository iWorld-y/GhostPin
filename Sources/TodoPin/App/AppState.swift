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
    private let hotKeyService = HotKeyService()
    private lazy var reminderService = ReminderService(
        todoStore: todoStore,
        preferences: preferences,
        notificationService: notificationService
    )
    private var cancellables: Set<AnyCancellable> = []

    lazy var windowCoordinator = WindowCoordinator(appState: self)

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
        do {
            try registerHotKeys()
        } catch {
            report(error)
        }
        reminderService.start()
        windowCoordinator.showBoard()

        let watcher = TodoFileWatcher(directoryURL: todosURL.deletingLastPathComponent()) { [weak self] in
            self?.reloadTodosFromDisk()
        }
        todoFileWatcher = watcher
        watcher.start()
    }

    func stop() {
        hotKeyService.unregister()
        reminderService.stop()
        todoFileWatcher?.stop()
    }

    func showQuickAdd() {
        windowCoordinator.showQuickAdd()
    }

    func showBoard() {
        windowCoordinator.showBoard()
    }

    func hideBoard() {
        windowCoordinator.hideBoard()
    }

    func toggleHUDMode() {
        preferences.hudMode = preferences.hudMode == .interactive ? .passthrough : .interactive
        windowCoordinator.updateHUD()
        windowCoordinator.applyHUDInteraction()
    }

    func updateHUD() {
        windowCoordinator.updateHUD()
    }

    func addTodo(title: String, reminderAt: Date? = nil) {
        do {
            _ = try todoStore.add(title: title, reminderAt: reminderAt)
        } catch {
            report(error)
        }
    }

    func setCompleted(_ item: TodoItem, completed: Bool) {
        do {
            try todoStore.setCompleted(item.id, completed: completed)
        } catch {
            report(error)
        }
    }

    func updateTodoTitle(_ item: TodoItem, title: String) {
        do {
            _ = try todoStore.updateTitle(item.id, title: title)
        } catch {
            report(error)
        }
    }

    func updateTodo(_ item: TodoItem, title: String, reminderAt: Date?) {
        do {
            _ = try todoStore.update(
                item.id,
                title: title,
                reminderAt: reminderAt,
                priority: item.priority,
                dueAt: item.dueAt,
                description: item.description
            )
        } catch {
            report(error)
        }
    }

    func delete(_ item: TodoItem) {
        do {
            try todoStore.delete(item.id)
        } catch {
            report(error)
        }
    }

    func updateTextHotKey(_ shortcut: HotKeyShortcut) {
        let previousShortcut = preferences.textHotKeyShortcut
        preferences.textHotKeyShortcut = shortcut

        do {
            try registerHotKeys()
            lastErrorMessage = nil
        } catch {
            preferences.textHotKeyShortcut = previousShortcut
            try? registerHotKeys()
            report(error)
        }
    }

    func updateHUDModeHotKey(_ shortcut: HotKeyShortcut) {
        guard shortcut != preferences.textHotKeyShortcut else {
            lastErrorMessage = "HUD 模式切换不能与文本录入使用同一个快捷键。"
            return
        }

        let previousShortcut = preferences.hudModeHotKeyShortcut
        preferences.hudModeHotKeyShortcut = shortcut

        do {
            try registerHotKeys()
            lastErrorMessage = nil
        } catch {
            preferences.hudModeHotKeyShortcut = previousShortcut
            try? registerHotKeys()
            report(error)
        }
    }

    func updateBoardLevel() {
        windowCoordinator.updateBoardLevel()
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

    private func registerHotKeys() throws -> Void {
        do {
            try hotKeyService.register([
                HotKeyRegistration(
                    id: 1,
                    shortcut: preferences.textHotKeyShortcut,
                    onTrigger: { [weak self] in
                        self?.showQuickAdd()
                    }
                ),
                HotKeyRegistration(
                    id: 3,
                    shortcut: preferences.hudModeHotKeyShortcut,
                    onTrigger: { [weak self] in
                        self?.toggleHUDMode()
                    }
                )
            ])
        } catch {
            report(error)
            throw error
        }
    }
}
