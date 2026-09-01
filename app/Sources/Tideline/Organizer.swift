import Foundation

/// What a history entry records: a file filed away, a dated folder cleared out,
/// a duplicate copy trashed, a kept copy given its plain name back, or a file
/// collected out of the watched folder altogether.
enum RecordKind: String, Codable {
    case filed
    case cleared
    case removed
    case renamed
    case collected
}

struct MoveRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var name: String
    var folder: String
    var wasPreview: Bool
    var kind: RecordKind = .filed
    /// Extra context a name and a folder cannot carry — the name a duplicate
    /// was renamed from, for one. Only ever shown as a subtitle.
    var detail: String?
}

extension MoveRecord {
    private enum CodingKeys: String, CodingKey {
        case id, date, name, folder, wasPreview, kind, detail
    }

    /// History written before clearing existed has no `kind`; it was all filing.
    /// Decoded leniently so an upgrade never blanks the activity list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        name = try container.decode(String.self, forKey: .name)
        folder = try container.decode(String.self, forKey: .folder)
        wasPreview = try container.decodeIfPresent(Bool.self, forKey: .wasPreview) ?? false
        kind = try container.decodeIfPresent(RecordKind.self, forKey: .kind) ?? .filed
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }
}

/// One item a sweep would move, and where to. A plan is what the preview
/// sheet lists and what a real sweep then carries out.
struct PlannedMove: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// Where it would land — a dated folder, or a type folder.
    var targetFolder: String
    /// The date it was filed by, under the current "Sort by" setting.
    var stamp: Date
    var byteSize: Int64
    var isFolder: Bool
    /// True when a routing rule claimed it. Exclusive with `isByType`.
    var isByRule: Bool = false
    /// True when a type rule claimed it rather than the date.
    var isByType: Bool
}

struct SweepPlan {
    var moves: [PlannedMove] = []
    var inspected = 0
    var leftAlone = 0
}

struct RunResult {
    var moves: [MoveRecord] = []
    /// Only filled on a preview, where it is the whole point: what would move.
    var plan: [PlannedMove] = []
    var cleared: [MoveRecord] = []
    var inspected = 0
    var leftAlone = 0
    var errors: [String] = []
    var finishedAt = Date()

    var movedCount: Int { moves.count }
    var clearedCount: Int { cleared.count }
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
    static let incompleteExtensions: Set<String> = [
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

    /// Works out what a sweep would do, and touches nothing. `run` is this plus
    /// the moves, so what a preview shows and what a sweep does cannot drift.
    ///
    /// Sizes are measured only when asked for: a real sweep has no use for them,
    /// and measuring a downloaded folder means walking it.
    static func plan(settings snapshot: RunConfiguration, measuring: Bool = false) throws -> SweepPlan {
        let fileManager = FileManager.default
        let root = snapshot.root

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw OrganizerError.folderMissing(root.path)
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey,
            .fileSizeKey, .totalFileAllocatedSizeKey,
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

        let ruleRouter = RuleRouter(rules: snapshot.rules)
        let router = TypeRouter(rules: snapshot.typeRules)

        let calendar = Calendar.current
        let cutoff = calendar.date(
            byAdding: .day,
            value: -max(0, snapshot.keepRecentDays),
            to: calendar.startOfDay(for: Date())
        ) ?? calendar.startOfDay(for: Date())

        var plan = SweepPlan()

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            plan.inspected += 1
            let name = entry.lastPathComponent

            guard shouldConsider(
                entry, name: name, snapshot: snapshot, rules: ruleRouter, router: router
            ) else {
                plan.leftAlone += 1
                continue
            }

            guard let stamp = date(of: entry, basis: snapshot.dateBasis) else {
                plan.leftAlone += 1
                continue
            }

            // Anything from today — or inside the grace window — stays loose.
            guard calendar.startOfDay(for: stamp) < cutoff else {
                plan.leftAlone += 1
                continue
            }

            let values = try? entry.resourceValues(forKeys: [
                .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey,
            ])
            let isFolder = values?.isDirectory ?? false
            if !isFolder, !isSettled(entry) {
                plan.leftAlone += 1
                continue
            }

            // A rule decides where it goes; the window above already decided
            // that it goes at all. Routing rules are asked first, or `Documents`
            // would swallow an invoice before `Invoices` ever saw it.
            let subject = RuleSubject(name: name, url: entry)
            let byRule = ruleRouter.folderName(for: subject)
            let byType = byRule == nil ? router.folderName(forExtension: entry.pathExtension) : nil
            let folderName = byRule ?? byType ?? formatter.string(from: stamp)

            // The file's own length, as Finder lists it, rather than what it
            // takes up on disk — this is a list of files, not of space.
            let size: Int64
            if isFolder {
                size = measuring ? FolderUsage.size(of: entry) : 0
            } else {
                size = Int64(values?.fileSize ?? 0)
            }

            plan.moves.append(PlannedMove(
                url: entry,
                name: name,
                targetFolder: folderName,
                stamp: stamp,
                byteSize: size,
                isFolder: isFolder,
                isByRule: byRule != nil,
                isByType: byType != nil
            ))
        }

        return plan
    }

    /// Runs one sweep. Blocking — call it off the main thread.
    static func run(settings snapshot: RunConfiguration) throws -> RunResult {
        let plan = try plan(settings: snapshot, measuring: snapshot.dryRun)
        let fileManager = FileManager.default

        var result = RunResult()
        result.inspected = plan.inspected
        result.leftAlone = plan.leftAlone

        // Preview mode stops here: the plan is the answer, and nothing on disk
        // has been opened for writing to produce it.
        if snapshot.dryRun {
            result.plan = plan.moves
            result.moves = plan.moves.map {
                MoveRecord(date: Date(), name: $0.name, folder: $0.targetFolder, wasPreview: true)
            }
            result.finishedAt = Date()
            return result
        }

        for move in plan.moves {
            let destination = snapshot.root.appendingPathComponent(move.targetFolder, isDirectory: true)
            let target = freeTarget(in: destination, for: move.name)

            do {
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
                try fileManager.moveItem(at: move.url, to: target)
                result.moves.append(MoveRecord(
                    date: Date(), name: move.name, folder: move.targetFolder, wasPreview: false
                ))
            } catch {
                result.errors.append("\(move.name): \(error.localizedDescription)")
            }
        }

        result.finishedAt = Date()
        return result
    }

    // MARK: - Rules

    private static func shouldConsider(
        _ url: URL, name: String, snapshot: RunConfiguration,
        rules: RuleRouter, router: TypeRouter
    ) -> Bool {
        if isManagedFolderName(name) { return false }
        // A folder a rule owns is a destination, not something to file. This
        // holds even while the rule has no tests yet, so a folder is not filed
        // away in the middle of writing the rule that fills it.
        if rules.owns(name) { return false }
        if router.owns(name) { return false }
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

    /// `addedToDirectoryDate` is Finder's "Date Added": the moment the item turned up in
    /// this folder, whatever it had been through before. A photo AirDropped today carries
    /// the day it was shot as its creation date, so that is the wrong day to file it under.
    /// Volumes that don't keep the attribute return nil, hence the fallbacks.
    static func date(of url: URL, basis: DateBasis) -> Date? {
        let values = try? url.resourceValues(forKeys: [
            .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey,
        ])
        switch basis {
        case .added:
            return values?.addedToDirectoryDate ?? values?.creationDate ?? values?.contentModificationDate
        case .created:
            return values?.creationDate ?? values?.contentModificationDate
        case .modified:
            return values?.contentModificationDate ?? values?.creationDate
        }
    }

    /// Nothing has written to it recently, and its size holds still.
    static func isSettled(_ url: URL) -> Bool {
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
    static func freeTarget(in folder: URL, for name: String) -> URL {
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
    var dateBasis: DateBasis = .added
    var includeFolders: Bool = true
    var dryRun: Bool = false
    var skipNames: [String] = []
    /// Tried before the type rules, and in this order. Only the rules that are
    /// switched on ever reach a sweep.
    var rules: [Rule] = []
    /// Only the rules that are switched on ever reach a sweep.
    var typeRules: [TypeRule] = []
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
        rules = settings.rules.filter(\.isEnabled)
        typeRules = settings.typeRules.filter(\.isEnabled)
    }
}
