import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case microphoneDenied
    case inputUnavailable
    case conversionFailed
    case recordingInProgress

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "麦克风权限未开启，仍可直接输入文字。"
        case .inputUnavailable:
            return "没有找到可用的麦克风输入。"
        case .conversionFailed:
            return "录音格式转换失败。"
        case .recordingInProgress:
            return "正在录音，请先完成当前语音录入。"
        }
    }
}

final class AudioCaptureService {
    var onElapsed: ((TimeInterval) -> Void)?

    private static let activeCaptureLock = NSLock()
    private static var activeCaptureID: UUID?

    private let captureID = UUID()
    private let sampleRate: Double = 16_000
    private let maxDuration: TimeInterval = 30
    private let silenceDuration: TimeInterval = 1.25
    private let silenceThreshold: Float = 0.012

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var samples: [Float] = []
    private var sampleLock = NSLock()
    private var completion: ((Result<[Float], Error>) -> Void)?
    private var startedAt: Date?
    private var lastSpeechAt: Date?
    private var hasSpeech = false
    private var elapsedTimer: Timer?
    private var maxTimer: Timer?
    private var isRecording = false
    private var ownsCaptureSlot = false

    func requestAndStart(completion: @escaping (Result<[Float], Error>) -> Void) {
        guard acquireCaptureSlot() else {
            completion(.failure(AudioCaptureError.recordingInProgress))
            return
        }

        let currentCaptureID = captureID
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else {
                    Self.releaseCaptureSlot(for: currentCaptureID)
                    return
                }
                guard self.ownsCaptureSlot else {
                    return
                }
                guard granted else {
                    self.releaseCaptureSlotIfNeeded()
                    completion(.failure(AudioCaptureError.microphoneDenied))
                    return
                }
                self.start(completion: completion)
            }
        }
    }

    func stop() {
        finish()
    }

    func cancel() {
        finish(sendResult: false)
    }

    private func start(completion: @escaping (Result<[Float], Error>) -> Void) {
        stopLocalEngine(sendResult: false, releaseSlot: false)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0,
              inputFormat.sampleRate > 0 else {
            releaseCaptureSlotIfNeeded()
            completion(.failure(AudioCaptureError.inputUnavailable))
            return
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            releaseCaptureSlotIfNeeded()
            completion(.failure(AudioCaptureError.conversionFailed))
            return
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            releaseCaptureSlotIfNeeded()
            completion(.failure(AudioCaptureError.conversionFailed))
            return
        }

        self.engine = engine
        self.converter = converter
        self.outputFormat = outputFormat
        self.completion = completion
        self.startedAt = Date()
        self.lastSpeechAt = nil
        self.hasSpeech = false
        self.isRecording = true
        sampleLock.lock()
        samples = []
        sampleLock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, inputFormat: inputFormat, outputFormat: outputFormat)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            self.outputFormat = nil
            self.completion = nil
            self.isRecording = false
            releaseCaptureSlotIfNeeded()
            completion(.failure(error))
            return
        }

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let startedAt = self.startedAt else {
                return
            }
            self.onElapsed?(Date().timeIntervalSince(startedAt))
        }

        maxTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            self?.finish()
        }
    }

    private func handle(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        guard let converter else {
            return
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        guard conversionError == nil,
              let channel = outputBuffer.floatChannelData?[0],
              outputBuffer.frameLength > 0 else {
            return
        }

        let count = Int(outputBuffer.frameLength)
        let values = Array(UnsafeBufferPointer(start: channel, count: count))
        let rms = sqrt(values.reduce(Float(0)) { $0 + ($1 * $1) } / Float(max(count, 1)))
        let now = Date()

        sampleLock.lock()
        samples.append(contentsOf: values)
        sampleLock.unlock()

        if rms > silenceThreshold {
            hasSpeech = true
            lastSpeechAt = now
        } else if hasSpeech,
                  let lastSpeechAt,
                  now.timeIntervalSince(lastSpeechAt) >= silenceDuration,
                  let startedAt,
                  now.timeIntervalSince(startedAt) > 0.8 {
            DispatchQueue.main.async { [weak self] in
                self?.finish()
            }
        }
    }

    private func finish(sendResult: Bool = true) {
        guard isRecording else {
            if !sendResult {
                releaseCaptureSlotIfNeeded()
            }
            return
        }
        stopLocalEngine(sendResult: sendResult, releaseSlot: true)
    }

    private func stopLocalEngine(sendResult: Bool, releaseSlot: Bool) {
        let wasRecording = isRecording
        isRecording = false
        elapsedTimer?.invalidate()
        maxTimer?.invalidate()
        elapsedTimer = nil
        maxTimer = nil

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        outputFormat = nil

        sampleLock.lock()
        let capturedSamples = samples
        samples = []
        sampleLock.unlock()

        let completion = self.completion
        self.completion = nil

        guard sendResult else {
            if releaseSlot, wasRecording || ownsCaptureSlot {
                releaseCaptureSlotIfNeeded()
            }
            return
        }
        if releaseSlot {
            releaseCaptureSlotIfNeeded()
        }
        completion?(.success(capturedSamples))
    }

    private func acquireCaptureSlot() -> Bool {
        Self.activeCaptureLock.lock()
        defer { Self.activeCaptureLock.unlock() }

        guard Self.activeCaptureID == nil || Self.activeCaptureID == captureID else {
            return false
        }

        Self.activeCaptureID = captureID
        ownsCaptureSlot = true
        return true
    }

    private func releaseCaptureSlotIfNeeded() {
        guard ownsCaptureSlot else {
            return
        }
        Self.releaseCaptureSlot(for: captureID)
        ownsCaptureSlot = false
    }

    private static func releaseCaptureSlot(for id: UUID?) {
        activeCaptureLock.lock()
        defer { activeCaptureLock.unlock() }

        guard id == nil || activeCaptureID == id else {
            return
        }
        activeCaptureID = nil
    }
}
