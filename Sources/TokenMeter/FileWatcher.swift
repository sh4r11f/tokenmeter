import Foundation

/// Watches a single file path for writes/renames and calls back on the
/// main queue. Deliberately thin — `AppState` also polls every 10s as a
/// safety net for the gap between "file doesn't exist yet" (nothing to
/// open a descriptor on) and its first write, and for events missed
/// across sleep/wake.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1

    init(url: URL, onChange: @escaping () -> Void) {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler(handler: onChange)
        let fd = fileDescriptor
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
