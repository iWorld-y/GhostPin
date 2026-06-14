import SwiftUI
import TodoPinCore

struct QuickAddPanelView: View {
    @ObservedObject var appState: AppState
    @State private var draftTitle = ""
    @State private var pendingReminderDraft: PendingReminderDraft?
    private let timeParser = TodoTimeParser()

    let onClose: () -> Void

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            captureField

            if let pendingReminderDraft {
                ReminderConfirmationView(
                    draft: pendingReminderDraft,
                    onConfirm: confirmPendingReminder,
                    onSaveWithoutReminder: savePendingWithoutReminder,
                    onCancel: cancelPendingReminder
                )
            }
        }
        .padding(18)
        .frame(width: 420)
        .frame(minHeight: 150, alignment: .top)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            TodoPinLogoMark(size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("快速捕捉")
                    .font(.system(size: 17, weight: .semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
    }

    private var captureField: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField("输入待办，或写上“明天 9 点提醒我”", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit(addDraft)

            Button(action: addDraft) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(addButtonBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(canAddDraft ? Color.white : Color.secondary)
            .disabled(!canAddDraft)
            .help("保存待办")
        }
        .padding(.leading, 13)
        .padding(.trailing, 7)
        .frame(height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(canAddDraft ? Color.accentColor.opacity(0.38) : .white.opacity(0.22), lineWidth: 1)
        )
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color(red: 0.23, green: 0.52, blue: 0.43).opacity(0.10),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var addButtonBackground: Color {
        canAddDraft ? Color.accentColor : Color.secondary.opacity(0.12)
    }

    private var statusText: String {
        "文字会保存在本机，提到时间时会先确认提醒"
    }

    private var canAddDraft: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            onClose()
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
        onClose()
    }

    private func savePendingWithoutReminder() {
        guard let pendingReminderDraft else {
            return
        }
        appState.addTodo(title: pendingReminderDraft.title, source: pendingReminderDraft.source)
        self.pendingReminderDraft = nil
        onClose()
    }

    private func cancelPendingReminder() {
        pendingReminderDraft = nil
    }
}
