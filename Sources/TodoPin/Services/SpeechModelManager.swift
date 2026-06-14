import Combine
import CryptoKit
import Foundation

enum SpeechModelStatus: Equatable {
    case missing
    case downloading
    case installed
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self {
            return true
        }
        return false
    }

    var label: String {
        switch self {
        case .missing:
            return "未安装"
        case .downloading:
            return "下载中"
        case .installed:
            return "已安装"
        case .failed:
            return "下载失败"
        }
    }
}

final class SpeechModelManager: ObservableObject {
    @Published private(set) var status: SpeechModelStatus = .missing

    var isModelInstalled: Bool {
        status.isInstalled
    }

    func refresh() {
        status = WhisperModelLocator.defaultModelURL() == nil ? .missing : .installed
    }

    func downloadModel() {
        guard !status.isDownloading else {
            return
        }

        status = .downloading
        Task {
            do {
                try await Self.downloadDefaultModel()
                await MainActor.run {
                    self.status = .installed
                }
            } catch {
                await MainActor.run {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private nonisolated static func downloadDefaultModel() async throws {
        let targetURL = try WhisperModelLocator.writableModelURL()
        let temporaryURL = targetURL.appendingPathExtension("tmp")
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: temporaryURL)

        let (downloadedURL, response) = try await URLSession.shared.download(from: WhisperModelLocator.downloadURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw SpeechModelDownloadError.badStatus(httpResponse.statusCode)
        }

        try fileManager.moveItem(at: downloadedURL, to: temporaryURL)
        let checksum = try sha256Hex(for: temporaryURL)
        guard checksum == WhisperModelLocator.expectedSHA256 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw SpeechModelDownloadError.checksumMismatch
        }

        try? fileManager.removeItem(at: targetURL)
        try fileManager.moveItem(at: temporaryURL, to: targetURL)
    }

    private nonisolated static func sha256Hex(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum SpeechModelDownloadError: LocalizedError {
    case badStatus(Int)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .badStatus(let status):
            return "模型下载失败，状态码 \(status)。"
        case .checksumMismatch:
            return "模型校验失败，请重新下载。"
        }
    }
}
