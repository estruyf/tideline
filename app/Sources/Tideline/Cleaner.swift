import Foundation

/// One dated folder that is old enough to go, with enough detail to decide by.
struct CleanupCandidate: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// First moment *after* the day or month the folder is named for.
    var periodEnd: Date
    var itemCount: Int
    var byteSize: Int64
    /// Set when the folder was too large to measure exactly.
    var sizeIsPartial: Bool = false
}

struct CleanupResult {
    var cleared: [MoveRecord] = []
    var errors: [String] = []
    var reclaimedBytes: Int64 = 0

    var clearedCount: Int { cleared.count }
}

/// Clearing out: dated folders Tideline made itself, once they are old enough,
/// go to the Trash. Nothing else in the folder is ever considered.
enum Cleaner {

    /// Folders larger than this are reported as "more than", rather than walked to the end.
    private static let measurementCap = 20_000

    // MARK: - Finding

    /// Every managed folder old enough to clear, newest first, with the most
    /// recent `keepNewest` folders held back whatever their age.
    static func candidates(configuration: CleanupConfiguration) -> [CleanupCandidate] {
        guard configuration.olderThanDays > 0 else { return [] }

        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: configuration.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Every dated folder in the root, whatever its age — the floor below has
        // to count folders we are keeping, not just ones we would remove.
        var managed: [(url: URL, name: String, end: Date)] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard Organizer.isManagedFolderName(name) else { continue }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard let end = periodEnd(of: name) else { continue }
            managed.append((entry, name, end))
        }

        managed.sort { $0.end > $1.end }

        // The newest few always stay, so a long quiet spell never empties the folder.
        let floor = max(0, configuration.keepNewest)
        let clearable = managed.count > floor ? Array(managed.dropFirst(floor)) : []

        // Measured from the end of the period, so a folder is never cleared
        // sooner than its name suggests.
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -configuration.olderThanDays, to: Date()
        ) ?? Date.distantPast

        return clearable
            .filter { $0.end <= cutoff }
            .map { folder in
                let measured = measure(folder.url)
                return CleanupCandidate(
                    url: folder.url,
                    name: folder.name,
                    periodEnd: folder.end,
                    itemCount: measured.items,
                    byteSize: measured.bytes,
                    sizeIsPartial: measured.partial
                )
            }
    }

    // MARK: - Clearing

    /// Moves each folder to the Trash. Recoverable by design — nothing is unlinked.
    static func clear(_ candidates: [CleanupCandidate], dryRun: Bool) -> CleanupResult {
        var result = CleanupResult()

        for candidate in candidates {
            if dryRun {
                result.cleared.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: "Trash",
                    wasPreview: true, kind: .cleared
                ))
                result.reclaimedBytes += candidate.byteSize
                continue
            }

            do {
                try FileManager.default.trashItem(at: candidate.url, resultingItemURL: nil)
                result.cleared.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: "Trash",
                    wasPreview: false, kind: .cleared
                ))
                result.reclaimedBytes += candidate.byteSize
            } catch {
                result.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        return result
    }

    // MARK: - Dates

    /// The folder name is the date — and unlike the folder's own timestamp it
    /// does not move every time filing drops something new inside.
    static func periodEnd(of name: String) -> Date? {
        let calendar = Calendar.current

        if let day = dayParser.date(from: name) {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
        }
        if let month = monthParser.date(from: name) {
            return calendar.date(byAdding: .month, value: 1, to: month)
        }
        return nil
    }

    private static let dayParser = parser(format: "yyyy-MM-dd")
    private static let monthParser = parser(format: "yyyy-MM")

    private static func parser(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    // MARK: - Measuring

    /// Top-level item count, as Finder shows it, plus the size of everything within.
    private static func measure(_ url: URL) -> (items: Int, bytes: Int64, partial: Bool) {
        let fileManager = FileManager.default

        let items = (try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ))?.count ?? 0

        guard let walker = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return (items, 0, false) }

        var bytes: Int64 = 0
        var seen = 0

        for case let file as URL in walker {
            seen += 1
            if seen > measurementCap { return (items, bytes, true) }

            let values = try? file.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            bytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }

        return (items, bytes, false)
    }
}

/// An immutable copy of the clearing settings, mirroring `RunConfiguration`.
struct CleanupConfiguration {
    var root: URL
    var olderThanDays: Int
    var keepNewest: Int
    var dryRun: Bool
}

extension CleanupConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        olderThanDays = settings.cleanupAfterDays
        keepNewest = settings.cleanupKeepNewest
        dryRun = settings.dryRun
    }
}

// MARK: - Folders left empty

extension Cleaner {

    /// A dated folder whose last file has just gone is no longer telling you
    /// anything. It goes to the Trash like any other cleared folder — never
    /// unlinked — and only ever a dated one: a type folder stays whether or not
    /// there is anything in it.
    ///
    /// In preview mode nothing has actually moved, so a folder counts as
    /// emptied when everything still inside it is on its way out.
    ///
    /// Shared by everything that takes files out of a dated folder: collapsing
    /// duplicates, catching up by type, and trimming the big ones.
    static func clearEmptied(
        _ paths: Set<String>,
        root: URL,
        moving: Set<String>,
        dryRun: Bool
    ) -> [MoveRecord] {
        let fileManager = FileManager.default
        var cleared: [MoveRecord] = []

        for path in paths.sorted() {
            let folder = URL(fileURLWithPath: path)
            let name = folder.lastPathComponent
            guard folder.path != root.path else { continue }
            guard Organizer.isManagedFolderName(name) else { continue }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            if dryRun {
                guard contents.allSatisfy({ moving.contains($0.path) }) else { continue }
                cleared.append(MoveRecord(
                    date: Date(), name: name, folder: "Trash", wasPreview: true, kind: .cleared
                ))
                continue
            }

            guard contents.isEmpty else { continue }
            if (try? fileManager.trashItem(at: folder, resultingItemURL: nil)) != nil {
                cleared.append(MoveRecord(
                    date: Date(), name: name, folder: "Trash", wasPreview: false, kind: .cleared
                ))
            }
        }

        return cleared
    }
}
