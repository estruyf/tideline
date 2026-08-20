import Foundation

struct MoveRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var name: String
    var folder: String
    var wasPreview: Bool
}

struct RunResult {
    var moves: [MoveRecord] = []
    var inspected = 0
    var leftAlone = 0
    var errors: [String] = []
    var finishedAt = Date()

    var movedCount: Int { moves.count }
}

enum OrganizerError: LocalizedError {
    case folderMissing(String)
    case notReadable(String)

    var errorDescription: String? {
        switch self {
        case .folderMissing(let path): return "\(path) does not exist."
        case .notReadable(let path): return "\(path) could not be read. macOS may be blocking access."
        }
    }
}

/// The filing logic: today's downloads stay loose, older ones move into a dated folder.
enum Organizer {

    /// Extensions that mean "still downloading".
    private static let incompleteExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "opdownload", "tmp", "temp", "aria2",
    ]

    /// A file whose contents changed this recently is assumed to be still in flight.
    private static let settleSeconds: TimeInterval = 30

    /// Folder names this app creates itself, in either format, are never re-filed.
    private static let dayFolderPattern = try! NSRegularExpression(
        pattern: "^[0-9]{4}-[0-9]{2}(-[0-9]{2})?$"
    )

    static func isManagedFolderName(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return dayFolderPattern.firstMatch(in: name, range: range) != nil
    }

    /// Runs one sweep. Blocking — call it off the main thread.
    static func run(settings snapshot: RunConfiguration) throws -> RunResult {
        let fileManager = FileManager.default
        let root = snapshot.root

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OrganizerError.folderMissing(root.path)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .creationDateKey, .contentModificationDateKey, .fileSizeKey,
        ]

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw OrganizerError.notReadable(root.path)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = snapshot.folderFormat.dateFormat

        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day,
            value: -max(0, snapshot.keepRecentDays),
            to: calendar.startOfDay(for: Date())
        ) ?? calendar.startOfDay(for: Date())

        var result = RunResult()

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            result.inspected += 1
            let name = entry.lastPathComponent

            guard shouldConsider(entry, name: name, snapshot: snapshot) else {
                result.leftAlone += 1
                continue
            }

            guard let stamp = date(of: entry, basis: snapshot.dateBasis) else {
                result.leftAlone += 1
                continue
            }

            // Anything from today — or inside the grace window — stays loose.
            guard calendar.startOfDay(for: stamp) < cutoff else {
                result.leftAlone += 1
                continue
            }

            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            let isFolder = values?.isDirectory ?? false
            if !isFolder, !isSettled(entry) {
                result.leftAlone += 1
                continue
            }

            let folderName = formatter.string(from: stamp)
            let destination = root.appendingPathComponent(folderName, isDirectory: true)
            let target = freeTarget(in: destination, for: name)

            if snapshot.dryRun {
                result.moves.append(MoveRecord(date: Date(), name: name, folder: folderName, wasPreview: true))
                continue
            }

            do {
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
                try fileManager.moveItem(at: entry, to: target)
                result.moves.append(MoveRecord(date: Date(), name: name, folder: folderName, wasPreview: false))
            } catch {
                result.errors.append("\(name): \(error.localizedDescription)")
            }
        }

        result.finishedAt = Date()
        return result
    }

    // MARK: - Rules

    private static func shouldConsider(_ url: URL, name: String, snapshot: RunConfiguration) -> Bool {
        if isManagedFolderName(name) { return false }
        if matchesSkipList(name, patterns: snapshot.skipNames) { return false }

        let ext = url.pathExtension.lowercased()
        if incompleteExtensions.contains(ext) { return false }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            // Safari keeps in-progress downloads in a .download bundle.
            if ext == "download" { return false }
            if !snapshot.includeFolders { return false }
        }

        return true
    }

    /// Exact names, or shell-style globs such as `*.dmg`.
    static func matchesSkipList(_ name: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed == name { return true }
            if trimmed.contains("*") || trimmed.contains("?") || trimmed.contains("[") {
                if fnmatch(trimmed, name, 0) == 0 { return true }
            }
        }
        return false
    }

    private static func date(of url: URL, basis: DateBasis) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        switch basis {
        case .created:
            return values?.creationDate ?? values?.contentModificationDate
        case .modified:
            return values?.contentModificationDate ?? values?.creationDate
        }
    }

    /// Nothing has written to it recently, and its size holds still.
    private static func isSettled(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modified = values?.contentModificationDate else { return true }

        let age = Date().timeIntervalSince(modified)
        if age < settleSeconds { return false }

        // A slow writer can leave an old timestamp between flushes, so double-check
        // anything touched in the last ten minutes.
        if age < 600 {
            let first = values?.fileSize ?? -1
            Thread.sleep(forTimeInterval: 1.5)
            let second = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -2
            return first == second
        }

        return true
    }

    /// `report.pdf` → `report-1.pdf` when the name is taken. Nothing is overwritten.
    private static func freeTarget(in folder: URL, for name: String) -> URL {
        let fileManager = FileManager.default
        let candidate = folder.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while true {
            var attempt = "\(base)-\(index)"
            if !ext.isEmpty { attempt += ".\(ext)" }
            let url = folder.appendingPathComponent(attempt)
            if !fileManager.fileExists(atPath: url.path) { return url }
            index += 1
        }
    }
}

/// An immutable copy of the settings, so a sweep on a background thread never
/// reads a value the UI is busy changing.
struct RunConfiguration {
    var root: URL
    var keepRecentDays: Int = 0
    var folderFormat: FolderFormat = .daily
    var dateBasis: DateBasis = .created
    var includeFolders: Bool = true
    var dryRun: Bool = false
    var skipNames: [String] = []
}

extension RunConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        keepRecentDays = settings.keepRecentDays
        folderFormat = settings.folderFormat
        dateBasis = settings.dateBasis
        includeFolders = settings.includeFolders
        dryRun = settings.dryRun
        skipNames = settings.skipNames
    }
}
