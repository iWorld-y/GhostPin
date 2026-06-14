import Foundation
import TodoPinCore
import whisper

enum WhisperEngineError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(URL)
    case emptyAudio
    case transcriptionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "没有找到本地语音模型。可以在设置里下载模型，或继续手动输入。"
        case .modelLoadFailed(let url):
            return "模型加载失败：\(url.lastPathComponent)。"
        case .emptyAudio:
            return "没有录到有效语音。"
        case .transcriptionFailed(let status):
            return "本地转写失败，状态码 \(status)。"
        }
    }
}

protocol SpeechTranscribing {
    func transcribe(samples: [Float], language: String) throws -> String
}

final class LocalSpeechTranscriber: SpeechTranscribing {
    private var engine: WhisperEngine?
    private let lock = NSLock()

    func transcribe(samples: [Float], language: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        if engine == nil {
            engine = try WhisperEngine(modelURL: WhisperModelLocator.defaultModelURL())
        }
        return try engine?.transcribe(samples: samples, language: language) ?? ""
    }
}

final class WhisperEngine {
    private let context: OpaquePointer

    init(modelURL: URL?) throws {
        guard let modelURL else {
            throw WhisperEngineError.modelNotFound
        }

        let params = whisper_context_default_params()
        guard let context = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw WhisperEngineError.modelLoadFailed(modelURL)
        }
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(samples: [Float], language: String) throws -> String {
        guard !samples.isEmpty else {
            throw WhisperEngineError.emptyAudio
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(2, min(ProcessInfo.processInfo.processorCount, 6)))
        params.no_context = true
        params.no_timestamps = true
        params.single_segment = true
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false

        let status: Int32 = language.withCString { languagePointer in
            params.language = language.isEmpty ? nil : languagePointer
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
        }

        guard status == 0 else {
            throw WhisperEngineError.transcriptionFailed(status)
        }

        let segmentCount = whisper_full_n_segments(context)
        var text = ""
        for index in 0..<segmentCount {
            if let segment = whisper_full_get_segment_text(context, index) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperModelLocator {
    static let defaultModelName = "ggml-base-q5_1"
    static let defaultModelExtension = "bin"
    static let expectedSHA256 = "422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
    static let downloadURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(defaultModelFileName)")!

    static var defaultModelFileName: String {
        "\(defaultModelName).\(defaultModelExtension)"
    }

    static func defaultModelURL(fileManager: FileManager = .default) -> URL? {
        candidateURLs().first { fileManager.fileExists(atPath: $0.path) }
    }

    static func writableModelURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try StorageLocations.applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Models", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(defaultModelFileName)
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let userModelURL = try? writableModelURL() {
            urls.append(userModelURL)
        }

        if let mainResourceURL = Bundle.main.resourceURL {
            urls.append(mainResourceURL.appendingPathComponent("Models/\(defaultModelFileName)"))
            urls.append(mainResourceURL.appendingPathComponent("Resources/Models/\(defaultModelFileName)"))
        }

        if let moduleURL = Bundle.module.url(
            forResource: defaultModelName,
            withExtension: defaultModelExtension,
            subdirectory: "Resources/Models"
        ) {
            urls.append(moduleURL)
        }

        let checkoutURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/TodoPin/Resources/Models/\(defaultModelName).\(defaultModelExtension)")
        urls.append(checkoutURL)

        return urls
    }
}
