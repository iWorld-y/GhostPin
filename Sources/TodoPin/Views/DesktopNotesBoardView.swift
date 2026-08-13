import AppKit
import SwiftUI
import TodoPinCore

struct DesktopNotesBoardView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void
    @State private var editingID: TodoItem.ID?
    @State private var editingTitle = ""
    @State private var editingReminderEnabled = false
    @State private var editingReminderAt = Date()
    @State private var isHovering = false

    var body: some View {
        ZStack {
            boardBackground

            VStack(alignment: .leading, spacing: 12) {
                header

                if hudItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(hudItems) { item in
                                if editingID == item.id {
                                    DesktopNoteEditorView(
                                        title: $editingTitle,
                                        reminderEnabled: $editingReminderEnabled,
                                        reminderAt: $editingReminderAt,
                                        onSave: { saveEdit(item) },
                                        onCancel: cancelEdit
                                    )
                                } else {
                                    DesktopNoteCardView(
                                        item: item,
                                        isActive: isActive,
                                        onComplete: {
                                            appState.setCompleted(item, completed: true)
                                        },
                                        onEdit: {
                                            startEdit(item)
                                        },
                                        onDelete: {
                                            appState.delete(item)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 310, minHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(strokeOpacity, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isActive ? 0.18 : 0.11), radius: isActive ? 22 : 12, y: isActive ? 12 : 6)
        .opacity(boardOpacity)
        .saturation(isActive ? 1 : 0.88)
        .blur(radius: isActive ? 0 : 0.08)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onChange(of: appState.preferences.hudMode) { _, mode in
            if mode == .passthrough {
                isHovering = false
                editingID = nil
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .animation(.easeInOut(duration: 0.18), value: isGhostFading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            TodoPinLogoMark(size: 34, isMuted: !isActive)

            VStack(alignment: .leading, spacing: 2) {
                Text("TodoPin")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(hudItems.count) 个未完成")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    appState.showQuickAdd()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .help("添加待办")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .help("隐藏桌面便签")
            }
            .opacity(isActive ? 1 : 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有未完成待办")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isActive ? activeGradientColors : inactiveGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var activeGradientColors: [Color] {
        [
            Color.white.opacity(0.38),
            Color(red: 0.56, green: 0.73, blue: 0.47).opacity(0.20),
            Color(red: 0.95, green: 0.70, blue: 0.23).opacity(0.16)
        ]
    }

    private var inactiveGradientColors: [Color] {
        [
            Color.white.opacity(0.14),
            Color(red: 0.34, green: 0.55, blue: 0.38).opacity(0.24),
            Color.black.opacity(0.03)
        ]
    }

    private var hudItems: [TodoItem] {
        appState.todoStore.hudItems(
            scope: appState.preferences.hudScope,
            maxCount: appState.preferences.hudMaxItems
        )
    }

    private var isInteractive: Bool {
        appState.preferences.hudMode == .interactive
    }

    private var isActive: Bool {
        isInteractive || editingID != nil
    }

    private var isGhostFading: Bool {
        !isInteractive && isHovering
    }

    private var boardOpacity: Double {
        if isGhostFading {
            return 0.4
        }
        return isActive ? 1 : 0.86
    }

    private var strokeOpacity: Color {
        if isGhostFading {
            return .white.opacity(0.10)
        }
        return .white.opacity(isActive ? 0.34 : 0.26)
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

private struct DesktopNoteCardView: View {
    let item: TodoItem
    let isActive: Bool
    let onComplete: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? .primary : .secondary)
            .help("标记完成")

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Label(Self.createdFormatter.string(from: item.createdAt), systemImage: "clock")
                    if let reminderAt = item.reminderAt {
                        Label(Self.reminderFormatter.string(from: reminderAt), systemImage: "bell")
                    }
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("编辑")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("删除")
            }
            .opacity(isActive ? 1 : 0)
        }
        .padding(12)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.32 : 0.22), lineWidth: 1)
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isActive ? 0.22 : 0.18),
                        Color(red: 0.95, green: 0.75, blue: 0.25).opacity(isActive ? 0.16 : 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
    }

    private static let createdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let reminderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

private struct DesktopNoteEditorView: View {
    @Binding var title: String
    @Binding var reminderEnabled: Bool
    @Binding var reminderAt: Date
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("待办内容", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)

            Toggle("提醒", isOn: $reminderEnabled)

            if reminderEnabled {
                DatePicker(
                    "时间",
                    selection: $reminderAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }

            HStack(spacing: 8) {
                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .frame(width: 28, height: 26)
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("保存")

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 26)
                }
                .help("取消")
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        )
    }
}
