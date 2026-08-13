import Combine
import Foundation
import SwiftUI
import TodoPinCore

final class AppState: ObservableObject {
    let todoStore: TodoStore
    let summaryStore: SummaryStore
    let preferences: AppPreferences
    let speechModelManager: SpeechModelManager

    @Published var lastErrorMessage: String?


    private let notificationService = NotificationService()
    private let hotKeyService = HotKeyService()
    private lazy var reminderService = ReminderService(
        todoStore: todoStore,
        summaryStore: summaryStore,
        preferences: preferences,
        notificationService: notificationService
    )
    private var cancellables: Set<AnyCancellable> = []

    lazy var windowCoordinator = WindowCoordinator(appState: self)

    init() {
        let fileManager = FileManager.default
        let fallbackDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TodoPin", isDirectory: true)

        let todosURL = (try? StorageLocations.todosURL(fileManager: fileManager))
            ?? fallbackDirectory.appendingPathComponent("todos.json")
        let summariesURL = (try? StorageLocations.summariesURL(fileManager: fileManager))
            ?? fallbackDirectory.appendingPathComponent("summaries.json")

        self.todoStore = TodoStore(fileURL: todosURL, fileManager: fileManager)
        self.summaryStore = SummaryStore(fileURL: summariesURL, fileManager: fileManager)
        self.preferences = AppPreferences()
        self.speechModelManager = SpeechModelManager()

        do {
            try todoStore.load()
            try summaryStore.load()
            try summaryStore.generateMissingSummaries(upTo: Date(), todos: todoStore.items)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        todoStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        summaryStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        speechModelManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func start() {
        speechModelManager.refresh()
        notificationService.requestAuthorization()
        do {
            try registerHotKeys()
        } catch {
            report(error)
        }
        reminderService.start()
        windowCoordinator.showBoard()
    }

    func stop() {
        hotKeyService.unregister()
        reminderService.stop()
    }

    func showQuickAdd() {
        windowCoordinator.showQuickAdd()
    }

    func startVoiceCapture() {
        speechModelManager.refresh()
        windowCoordinator.showVoiceCapture()
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

    func showSummary() {
        windowCoordinator.showSummary()
    }

    func addTodo(title: String, source: TodoSource, reminderAt: Date? = nil) {
        do {
            _ = try todoStore.add(title: title, source: source, reminderAt: reminderAt)
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
            _ = try todoStore.update(item.id, title: title, reminderAt: reminderAt)
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

    func generateTodaySummary() {
        do {
            let summary = try summaryStore.generateSummary(for: Date(), todos: todoStore.items)
            notificationService.sendSummary(summary)
        } catch {
            report(error)
        }
    }

    func updateTextHotKey(_ shortcut: HotKeyShortcut) {
        guard shortcut != preferences.voiceHotKeyShortcut else {
            lastErrorMessage = "文本录入和语音录入不能使用同一个快捷键。"
            return
        }

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

    func updateVoiceHotKey(_ shortcut: HotKeyShortcut) {
        guard shortcut != preferences.textHotKeyShortcut else {
            lastErrorMessage = "文本录入和语音录入不能使用同一个快捷键。"
            return
        }

        let previousShortcut = preferences.voiceHotKeyShortcut
        preferences.voiceHotKeyShortcut = shortcut

        do {
            try registerHotKeys()
            lastErrorMessage = nil
        } catch {
            preferences.voiceHotKeyShortcut = previousShortcut
            try? registerHotKeys()
            report(error)
        }
    }

    func updateHUDModeHotKey(_ shortcut: HotKeyShortcut) {
        guard shortcut != preferences.textHotKeyShortcut,
              shortcut != preferences.voiceHotKeyShortcut else {
            lastErrorMessage = "HUD 模式切换不能与文本录入或语音录入使用同一个快捷键。"
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
                    id: 2,
                    shortcut: preferences.voiceHotKeyShortcut,
                    onTrigger: { [weak self] in
                        self?.startVoiceCapture()
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
