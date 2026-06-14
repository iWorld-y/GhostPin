import SwiftUI
import TodoPinCore

struct VoiceCaptureOverlayView: View {
    @ObservedObject var appState: AppState
    @StateObject private var voiceInput: VoiceInputController
    @State private var didStart = false
    @State private var didFinish = false
    @State private var savedMessage: String?
    private let timeParser = TodoTimeParser()

    let onClose: () -> Void

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        _voiceInput = StateObject(wrappedValue: VoiceInputController(language: appState.preferences.speechLanguage))
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: pulseSize, height: pulseSize)
                    .scaleEffect(voiceInput.state == .recording ? 1.08 : 1)
                    .opacity(voiceInput.state == .recording ? 0.82 : 0.55)

                Circle()
                    .fill(Color.accentColor.opacity(0.22))
                    .frame(width: 68, height: 68)

                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: voiceInput.state == .recording)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if voiceInput.state == .recording {
                Button {
                    voiceInput.stopVoice()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .controlSize(.small)
            } else if voiceInput.state == .transcribing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 250)
        .frame(minHeight: 210)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
        .onAppear(perform: startIfNeeded)
        .onChange(of: voiceInput.state) { _, state in
            handleStateChange(state)
        }
    }

    private var panelBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color(red: 0.28, green: 0.52, blue: 0.43).opacity(0.14),
                    Color.white.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var pulseSize: CGFloat {
        voiceInput.state == .recording ? 112 : 94
    }

    private var iconName: String {
        switch voiceInput.state {
        case .recording:
            return "waveform"
        case .transcribing:
            return "text.magnifyingglass"
        case .ready:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        default:
            return "mic.fill"
        }
    }

    private var title: String {
        if savedMessage != nil {
            return "已保存"
        }
        if !appState.speechModelManager.isModelInstalled {
            return "语音模型未安装"
        }
        switch voiceInput.state {
        case .recording:
            return "正在听"
        case .transcribing:
            return "正在转文字"
        case .failed:
            return "录入失败"
        default:
            return "语音录入"
        }
    }

    private var detail: String {
        if let savedMessage {
            return savedMessage
        }
        if !appState.speechModelManager.isModelInstalled {
            return "可在设置中下载本地模型，或使用文本录入。"
        }
        if voiceInput.state == .recording {
            return String(format: "说完后停顿一下会自动保存  %.1f 秒", voiceInput.elapsed)
        }
        if voiceInput.state == .transcribing {
            return "正在本机识别，不上传云端。"
        }
        if let errorMessage = voiceInput.errorMessage {
            return errorMessage
        }
        return "准备打开麦克风"
    }

    private func startIfNeeded() {
        guard !didStart else {
            return
        }
        didStart = true

        guard appState.speechModelManager.isModelInstalled else {
            close(after: 2.0)
            return
        }

        voiceInput.startVoice()
    }

    private func handleStateChange(_ state: VoiceInputState) {
        switch state {
        case .ready:
            saveTranscript()
        case .failed:
            close(after: 2.4)
        default:
            break
        }
    }

    private func saveTranscript() {
        guard !didFinish else {
            return
        }
        didFinish = true

        let title = voiceInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            savedMessage = "没有识别到内容"
            close(after: 1.4)
            return
        }

        let parsedReminder = timeParser.parse(title)
        appState.addTodo(title: title, source: .voice, reminderAt: parsedReminder?.date)
        if let parsedReminder {
            savedMessage = "已加入待办，并设置 \(ReminderConfirmationView.formatter.string(from: parsedReminder.date)) 提醒"
        } else {
            savedMessage = title
        }
        voiceInput.resetAfterSave()
        close(after: 1.2)
    }

    private func close(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            voiceInput.cancel()
            onClose()
        }
    }
}
