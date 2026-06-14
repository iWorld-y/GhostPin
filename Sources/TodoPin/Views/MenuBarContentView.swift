import AppKit
import SwiftUI
import TodoPinCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @State private var draftTitle = ""
    @State private var editingID: TodoItem.ID?
    @State private var editingTitle = ""
    @State private var editingReminderEnabled = false
    @State private var editingReminderAt = Date()
    @State private var pendingReminderDraft: PendingReminderDraft?
    private let timeParser = TodoTimeParser()

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quickAdd
            reminderConfirmation
            Divider()
            todoList
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 10) {
            TodoPinLogoMark(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("TodoPin")
                    .font(.headline)
                Text("\(openItems.count) 个未完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.startVoiceCapture()
            } label: {
                Image(systemName: "mic.circle")
            }
            .help("桌面语音录入")

            Button {
                appState.showBoard()
            } label: {
                Image(systemName: "note.text")
            }
            .help("显示桌面便签")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            TextField("输入一个待办", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addDraft)

            Button(action: addDraft) {
                Image(systemName: "plus")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                appState.startVoiceCapture()
            } label: {
                Image(systemName: "mic.fill")
            }
            .help("桌面语音录入")
        }
    }

    @ViewBuilder
    private var reminderConfirmation: some View {
        if let pendingReminderDraft {
            ReminderConfirmationView(
                draft: pendingReminderDraft,
                onConfirm: confirmPendingReminder,
                onSaveWithoutReminder: savePendingWithoutReminder,
                onCancel: cancelPendingReminder
            )
        }
    }

    private var todoList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if openItems.isEmpty {
                ContentUnavailableView(
                    "没有待办",
                    systemImage: "checkmark.circle",
                    description: Text("用文字或语音添加一个新的待办。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(openItems) { item in
                    todoRow(item)
                    if item.id != openItems.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = appState.lastErrorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                appState.hideBoard()
            } label: {
                Image(systemName: "note.text")
            }
            .help("隐藏桌面便签")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出 TodoPin")
        }
    }

    private var openItems: [TodoItem] {
        appState.todoStore.openItems()
    }

    private func todoRow(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                appState.setCompleted(item, completed: true)
            } label: {
                Image(systemName: "circle")
            }
            .buttonStyle(.plain)
            .help("标记完成")

            if editingID == item.id {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("待办内容", text: $editingTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveEdit(item) }

                    Toggle("提醒", isOn: $editingReminderEnabled)

                    if editingReminderEnabled {
                        DatePicker(
                            "时间",
                            selection: $editingReminderAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }

                    HStack {
                        Button {
                            saveEdit(item)
                        } label: {
                            Label("保存", systemImage: "checkmark")
                        }
                        .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            cancelEdit()
                        } label: {
                            Label("取消", systemImage: "xmark")
                        }
                    }
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(3)
                    Text(item.source == .voice ? "语音录入" : "手动录入")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let reminderAt = item.reminderAt {
                        Text("提醒：\(ReminderConfirmationView.formatter.string(from: reminderAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    startEdit(item)
                } label: {
                    Image(systemName: "pencil")
                }
                .help("编辑")

                Button {
                    appState.delete(item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除")
            }
        }
    }

    private func addDraft() {
        addTodoOrConfirmReminder(title: draftTitle, source: .text)
        draftTitle = ""
    }

    private func addTodoOrConfirmReminder(title: String, source: TodoSource) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if let parsedReminder = timeParser.parse(trimmed) {
            pendingReminderDraft = PendingReminderDraft(
                title: trimmed,
                source: source,
                parsedReminder: parsedReminder
            )
        } else {
            appState.addTodo(title: trimmed, source: source)
        }
    }

    private func confirmPendingReminder() {
        guard let pendingReminderDraft else {
            return
        }
        appState.addTodo(
            title: pendingReminderDraft.title,
            source: pendingReminderDraft.source,
            reminderAt: pendingReminderDraft.parsedReminder.date
        )
        self.pendingReminderDraft = nil
    }

    private func savePendingWithoutReminder() {
        guard let pendingReminderDraft else {
            return
        }
        appState.addTodo(title: pendingReminderDraft.title, source: pendingReminderDraft.source)
        self.pendingReminderDraft = nil
    }

    private func cancelPendingReminder() {
        pendingReminderDraft = nil
    }

    private func startEdit(_ item: TodoItem) {
        editingID = item.id
        editingTitle = item.title
        editingReminderEnabled = item.reminderAt != nil
        editingReminderAt = item.reminderAt ?? Date().addingTimeInterval(3600)
    }

    private func saveEdit(_ item: TodoItem) {
        appState.updateTodo(
            item,
            title: editingTitle,
            reminderAt: editingReminderEnabled ? editingReminderAt : nil
        )
        cancelEdit()
    }

    private func cancelEdit() {
        editingID = nil
        editingTitle = ""
        editingReminderEnabled = false
        editingReminderAt = Date()
    }
}
