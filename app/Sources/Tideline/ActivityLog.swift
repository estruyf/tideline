import Foundation

/// Recent moves, kept for the UI, plus a plain-text log on disk.
final class ActivityLog {
    static let shared = ActivityLog()

    private let maximumEntries = 300
    private let maximumCollections = 40
    private let queue = DispatchQueue(label: "be.eliostruyf.Tideline.log")

    private lazy var supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let directory = base.appendingPathComponent("Tideline", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private lazy var historyURL = supportDirectory.appendingPathComponent("history.json")

    /// Collections are kept apart from the activity list because they are the
    /// only thing the app can undo, and the list is trimmed to its last few
    /// hundred entries — an undo that expired because someone downloaded a lot
    /// would be a poor promise.
    private lazy var collectionsURL = supportDirectory.appendingPathComponent("collections.json")

    lazy var logURL: URL = {
        let logs = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("Tideline.log")
    }()

    func loadHistory() -> [MoveRecord] {
        guard let data = try? Data(contentsOf: historyURL),
              let records = try? JSONDecoder().decode([MoveRecord].self, from: data)
        else { return [] }
        return records
    }

    func save(_ records: [MoveRecord]) {
        let trimmed = Array(records.prefix(maximumEntries))
        queue.async { [historyURL] in
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    /// The collections that can still be put back, newest first.
    func loadCollections() -> [CollectBatch] {
        guard let data = try? Data(contentsOf: collectionsURL),
              let batches = try? JSONDecoder().decode([CollectBatch].self, from: data)
        else { return [] }
        return batches
    }

    func save(_ batches: [CollectBatch]) {
        let trimmed = Array(batches.prefix(maximumCollections))
        queue.async { [collectionsURL] in
            guard let data = try? JSONEncoder().encode(trimmed) else { return }
            try? data.write(to: collectionsURL, options: .atomic)
        }
    }

    func write(_ message: String) {
        queue.async { [logURL] in
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp)  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    /// Used by the in-app uninstaller.
    func eraseAll() {
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: collectionsURL)
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: supportDirectory)
    }
}
