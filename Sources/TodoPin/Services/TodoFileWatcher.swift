import Foundation

final class TodoFileWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var pendingReload: DispatchWorkItem?

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    func start() {
        stop()
        let fd = open(directoryURL.path, O_EVTONLY)
        guard fd >= 0 else {
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingReload?.cancel()
        pendingReload = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        stop()
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}
