import Foundation

/// Watches a folder and calls back once things go quiet again.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var debounce: DispatchWorkItem?

    private let queue = DispatchQueue(label: "be.eliostruyf.Tideline.watcher")
    private let quietPeriod: TimeInterval = 8

    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    var isWatching: Bool { source != nil }

    func start(url: URL) {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                // The folder itself moved away; re-attach shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.start(url: url)
                }
                return
            }
            self.scheduleCallback()
        }

        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }

        source.resume()
        self.source = source
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    /// Downloads arrive in bursts; wait for the folder to settle before sweeping.
    private func scheduleCallback() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + quietPeriod, execute: work)
    }
}
