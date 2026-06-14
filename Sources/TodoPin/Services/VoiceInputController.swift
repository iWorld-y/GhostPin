import Foundation
import TodoPinCore

enum VoiceInputState: Equatable {
    case idle
    case requestingPermission
    case recording
    case transcribing
    case ready
    case failed

    var label: String {
        switch self {
        case .idle:
            return "准备录入"
        case .requestingPermission:
            return "等待麦克风权限"
        case .recording:
            return "正在听"
        case .transcribing:
            return "正在转文字"
        case .ready:
            return "可保存"
        case .failed:
            return "可手动输入"
        }
    }
}

final class VoiceInputController: ObservableObject {
    @Published var text: String = ""
    @Published var state: VoiceInputState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var source: TodoSource = .text

    private let audioCapture: AudioCaptureService
    private let transcriber: SpeechTranscribing
    private let language: String
    private var didAutoStart = false

    init(
        audioCapture: AudioCaptureService = AudioCaptureService(),
        transcriber: SpeechTranscribing = LocalSpeechTranscriber(),
        language: String
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.language = language
        self.audioCapture.onElapsed = { [weak self] elapsed in
            DispatchQueue.main.async {
                self?.elapsed = elapsed
            }
        }
    }

    func startVoiceIfNeeded() {
        guard !didAutoStart else {
            return
        }
        didAutoStart = true
        startVoice()
    }

    func startVoice() {
        guard state != .requestingPermission,
              state != .recording,
              state != .transcribing else {
            return
        }
        elapsed = 0
        errorMessage = nil
        source = .voice
        state = .requestingPermission
        audioCapture.requestAndStart { [weak self] result in
            self?.handleRecordingResult(result)
        }
        if state == .requestingPermission {
            state = .recording
        }
    }

    func stopVoice() {
        audioCapture.stop()
    }

    func cancel() {
        audioCapture.cancel()
        state = .idle
    }

    func resetAfterSave() {
        text = ""
        elapsed = 0
        errorMessage = nil
        source = .text
        state = .idle
    }

    private func handleRecordingResult(_ result: Result<[Float], Error>) {
        switch result {
        case .success(let samples):
            transcribe(samples)
        case .failure(let error):
            state = .failed
            source = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .text : source
            errorMessage = error.localizedDescription
        }
    }

    private func transcribe(_ samples: [Float]) {
        state = .transcribing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            let result = Result {
                try self.transcriber.transcribe(samples: samples, language: self.language)
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let transcript):
                    if !transcript.isEmpty {
                        self.text = transcript
                        self.source = .voice
                        self.state = .ready
                    } else {
                        self.source = .text
                        self.state = .failed
                        self.errorMessage = "没听清，可以直接输入文字。"
                    }
                case .failure(let error):
                    self.source = .text
                    self.state = .failed
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
