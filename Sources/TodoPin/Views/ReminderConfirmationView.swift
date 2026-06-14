import SwiftUI
import TodoPinCore

struct PendingReminderDraft: Equatable {
    let title: String
    let source: TodoSource
    let parsedReminder: ParsedReminderTime
}

struct ReminderConfirmationView: View {
    let draft: PendingReminderDraft
    let onConfirm: () -> Void
    let onSaveWithoutReminder: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("识别到提醒时间")
                        .font(.caption)
                    Text(Self.formatter.string(from: draft.parsedReminder.date))
                        .font(.callout)
                        .fontWeight(.semibold)
                }
                Spacer()
            }

            Text(draft.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button("确认提醒", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button("仅保存待办", action: onSaveWithoutReminder)
                Spacer()
                Button("取消", action: onCancel)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        )
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
