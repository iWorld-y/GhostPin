import AppKit
import SwiftUI
import GhostPinCore

struct DesktopNotesBoardView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void
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
                            if !doingItems.isEmpty {
                                taskSectionHeader("Doing")
                                ForEach(doingItems) { item in
                                    taskCard(item)
                                }
                            }
                            if !todoItems.isEmpty {
                                taskSectionHeader("TODO")
                                ForEach(todoItems) { item in
                                    taskCard(item)
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
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .animation(.easeInOut(duration: 0.18), value: isGhostFading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            GhostPinLogoMark(size: 34, isMuted: !isActive)

            VStack(alignment: .leading, spacing: 2) {
                Text("GhostPin")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(hudItems.count) 个未完成")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .help("隐藏桌面便签")
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

    private var doingItems: [TodoItem] {
        hudItems.filter { $0.status == .doing }
    }

    private var todoItems: [TodoItem] {
        hudItems.filter { $0.status == .todo }
    }

    private func taskCard(_ item: TodoItem) -> some View {
        DesktopNoteCardView(
            item: item,
            isActive: isActive,
            onAdvanceStatus: {
                appState.advanceStatus(item)
            }
        )
    }

    private func taskSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 2)
    }

    private var isInteractive: Bool {
        appState.preferences.hudMode == .interactive
    }

    private var isActive: Bool {
        isInteractive
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
}

private struct DesktopNoteCardView: View {
    let item: TodoItem
    let isActive: Bool
    let onAdvanceStatus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button(action: onAdvanceStatus) {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.status == .doing ? .orange : (isActive ? .primary : .secondary))
            .help(item.status == .doing ? "标记完成" : "开始处理")

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .strikethrough(item.isOverdue(), color: .red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    priorityBadge
                }

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let dueAt = item.dueAt {
                    Text(Self.dueFormatter.string(from: dueAt))
                        .font(.caption2)
                        .foregroundStyle(item.isOverdue() ? .red : .secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
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

    private var priorityBadge: some View {
        Text(priorityLabel)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(priorityColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .foregroundStyle(priorityColor)
    }

    private var priorityLabel: String {
        switch item.priority {
        case .high:
            return "高"
        case .medium:
            return "中"
        case .low:
            return "低"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .high:
            return .red
        case .medium:
            return .orange
        case .low:
            return .secondary
        }
    }

    private static let dueFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
