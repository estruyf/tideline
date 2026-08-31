import Foundation

/// Collecting: taking things *out* of the watched folder.
///
/// Filing sorts the folder and never leaves it. This is the other direction —
/// the quarter's invoices into an accounting folder, a shoot's photos onto an
/// external drive — and it is the only thing the app does that writes anywhere
/// but the root.
///
/// It never runs on its own. Not on the timer, not when the folder changes, not
/// after a sweep: it happens when someone opens it, asks for something, and
/// ticks what they meant. That is deliberate. A rule that files an invoice into
/// `Downloads/Invoices` is easy to undo; a rule that posts it into somebody's
/// accounts months before they look is not, so the app proposes and a person
/// decides.
///
/// The window calls this **Move out**; the code and the contract call the
/// operation *collecting*, because it is one word for find-then-deposit and
/// `MoveFilesConfiguration` is not a name anybody wants to read. The app already
/// does this elsewhere — *Reclaim space* is `Deduper`, `Weigher` and `Cleaner`.
///
/// The contract is the *Collecting* section of `docs/behaviour.md`.
enum Collector {

    // MARK: - Finding

    /// Everything in scope that the query claims.
    ///
    /// Unlike a sweep this ignores the grace window. A sweep waits because
    /// nobody asked it to hurry; here somebody did, and a file that arrived an
    /// hour ago is as collectable as one from June.
    static func candidates(
        matching query: CollectQuery,
        configuration: CollectConfiguration
    ) -> CollectFindings {
        guard !query.isEmpty else { return .none }

        let fileManager = FileManager.default
        let places = ReviewScope.places(
            root: configuration.root,
            rules: configuration.rules,
            typeRules: configuration.typeRules
        )

        let ruleRouter = RuleRouter(rules: configuration.rules)
        let typeRouter = TypeRouter(rules: configuration.typeRules)
        var findings = CollectFindings(foldersSearched: places.count)
        var found: [CollectCandidate] = []

        for place in places {
            // Everything in the hunt's own folder belongs to it, whether or not
            // the file itself answers to a test.
            let isOwnFolder = query.folder?.caseInsensitiveCompare(place.label) == .orderedSame

            guard let contents = try? fileManager.contentsOfDirectory(
                at: place.url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = item.lastPathComponent
                let ext = item.pathExtension.lowercased()

                // The folders the app made are places to look inside, never
                // things to collect. Only the root can contain one.
                if Organizer.isManagedFolderName(name) { continue }
                if ruleRouter.owns(name) || typeRouter.owns(name) { continue }

                // The same guards filing uses, so collecting can never take
                // something a sweep would have refused to touch.
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: configuration.skipNames) { continue }

                let subject = RuleSubject(name: name, url: item)
                let claimed = query.claim(subject, extension: ext)
                guard claimed != nil || isOwnFolder else { continue }
                let incidental = claimed == nil
                let matched = claimed ?? "Sat in the \(place.label) folder"

                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    // Safari's in-progress bundle, and folders when filing them
                    // is off. Asking for something by hand is a reason to skip
                    // the grace window, not a reason to take a kind of thing the
                    // app has been told to leave alone.
                    if ext == "download" { continue }
                    if !configuration.includeFolders { continue }
                }

                found.append(CollectCandidate(
                    url: item,
                    name: name,
                    currentFolder: place.label,
                    matched: matched,
                    isIncidental: incidental,
                    stamp: Organizer.date(of: item, basis: configuration.dateBasis) ?? Date(),
                    byteSize: Int64(values?.fileSize ?? 0),
                    isFolder: values?.isDirectory ?? false
                ))
            }
        }

        findings.candidates = found
        return findings
    }

    /// How many things each of several hunts would turn up, in one walk of the
    /// folder rather than one walk each.
    ///
    /// The pane offers a rule as a starting point and says how much is waiting
    /// behind it, and doing that a rule at a time would read three hundred
    /// folders once per rule.
    static func tally(
        _ queries: [CollectQuery],
        configuration: CollectConfiguration
    ) -> [String: Int] {
        let live = queries.filter { !$0.isEmpty }
        guard !live.isEmpty else { return [:] }

        let fileManager = FileManager.default
        let places = ReviewScope.places(
            root: configuration.root,
            rules: configuration.rules,
            typeRules: configuration.typeRules
        )

        let ruleRouter = RuleRouter(rules: configuration.rules)
        let typeRouter = TypeRouter(rules: configuration.typeRules)
        var counts: [String: Int] = [:]

        for place in places {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: place.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents {
                let name = item.lastPathComponent
                let ext = item.pathExtension.lowercased()

                if Organizer.isManagedFolderName(name) { continue }
                if ruleRouter.owns(name) || typeRouter.owns(name) { continue }
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: configuration.skipNames) { continue }

                // One subject per entry, so a where-from is read once however
                // many hunts ask about it.
                let subject = RuleSubject(name: name, url: item)
                for query in live {
                    let own = query.folder?.caseInsensitiveCompare(place.label) == .orderedSame
                    if query.claim(subject, extension: ext) != nil || own {
                        counts[query.label, default: 0] += 1
                    }
                }
            }
        }

        return counts
    }

    // MARK: - Applying

    static func apply(
        _ candidates: [CollectCandidate],
        to destination: CollectDestination,
        as label: String,
        configuration: CollectConfiguration
    ) -> CollectResult {
        var result = CollectResult()

        guard let base = destination.resolve() else {
            result.errors.append("\(destination.name) could not be found. It may be on a volume that is not mounted.")
            return result
        }

        let fileManager = FileManager.default
        var touched: Set<String> = []
        var collected: [CollectedItem] = []

        for candidate in candidates {
            touched.insert(candidate.currentFolder)

            // Tokens resolve per file, so a batch that straddles the end of a
            // quarter lands in two folders — which is the answer the accounting
            // wanted and the one a single fixed destination could not give.
            let folder = destination.folder(under: base, on: candidate.stamp)
            let shown = destination.describe(on: candidate.stamp)

            if configuration.dryRun {
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: shown,
                    wasPreview: true, kind: .collected,
                    detail: "out of \(candidate.currentFolder)"
                ))
                continue
            }

            do {
                if !fileManager.fileExists(atPath: folder.path) {
                    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                let target = Organizer.freeTarget(in: folder, for: candidate.name)
                try fileManager.moveItem(at: candidate.url, to: target)

                collected.append(CollectedItem(
                    path: target.path,
                    name: target.lastPathComponent,
                    originFolder: candidate.currentFolder == configuration.root.lastPathComponent
                        ? "" : candidate.currentFolder,
                    byteSize: candidate.byteSize
                ))
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: shown,
                    wasPreview: false, kind: .collected,
                    detail: "out of \(candidate.currentFolder)"
                ))
            } catch {
                result.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        if configuration.removeEmptied {
            result.emptied = clearEmptied(
                touched,
                configuration: configuration,
                moving: Set(candidates.map(\.url.path))
            )
        }

        // One batch to one destination, recorded as one, so it comes back in one
        // gesture. This matters more here than anywhere else in the app: these
        // are the only files that leave the folder it watches, and putting
        // things back cannot reach them.
        if !collected.isEmpty {
            result.batch = CollectBatch(
                date: Date(),
                queryLabel: label,
                destinationName: destination.name,
                destinationID: destination.id,
                items: collected
            )
        }

        return result
    }

    /// The folders this run took files out of, once there is nothing left in
    /// them — and only the dated ones. An empty day is not a day, but a type or
    /// rule folder is a standing destination that the next sweep will fill
    /// again, so emptying one is not a reason to take it away.
    private static func clearEmptied(
        _ names: Set<String>,
        configuration: CollectConfiguration,
        moving: Set<String>
    ) -> [MoveRecord] {
        let fileManager = FileManager.default
        var cleared: [MoveRecord] = []

        for name in names.sorted() where Organizer.isManagedFolderName(name) {
            let folder = configuration.root.appendingPathComponent(name, isDirectory: true)

            guard let contents = try? fileManager.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            if configuration.dryRun {
                // Nothing has moved, so "empty afterwards" is a question about
                // what is leaving rather than about what is there.
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

    // MARK: - Undoing

    /// Puts a collection back: each file to the folder it was taken from, or to
    /// the root if that folder has since gone, under the same collision rules.
    static func undo(_ batch: CollectBatch, configuration: CollectConfiguration) -> CollectResult {
        let fileManager = FileManager.default
        var result = CollectResult()

        for item in batch.items {
            let source = URL(fileURLWithPath: item.path)
            guard fileManager.fileExists(atPath: source.path) else {
                // Moved on by hand since. Not an error worth stopping for, but
                // worth saying, since the file is not where it is about to be
                // reported as having come back from.
                result.errors.append("\(item.name) is no longer in \(batch.destinationName).")
                continue
            }

            let home = item.originFolder.isEmpty
                ? configuration.root
                : configuration.root.appendingPathComponent(item.originFolder, isDirectory: true)

            if configuration.dryRun {
                result.moved.append(MoveRecord(
                    date: Date(), name: item.name, folder: home.lastPathComponent,
                    wasPreview: true, kind: .collected, detail: "back out of \(batch.destinationName)"
                ))
                continue
            }

            do {
                if !fileManager.fileExists(atPath: home.path) {
                    try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
                }
                let target = Organizer.freeTarget(in: home, for: item.name)
                try fileManager.moveItem(at: source, to: target)
                result.moved.append(MoveRecord(
                    date: Date(), name: item.name, folder: home.lastPathComponent,
                    wasPreview: false, kind: .collected,
                    detail: "back out of \(batch.destinationName)"
                ))
            } catch {
                result.errors.append("\(item.name): \(error.localizedDescription)")
            }
        }

        return result
    }
}

// MARK: - What a collection is looking for

/// A hunt: a rule, a type folder, or a set of tests typed on the spot.
struct CollectQuery: Equatable {
    /// What the sheet calls it, and the name a saved rule would take.
    var label: String = ""
    var tests: [RuleTest] = []
    /// A type folder contributes its extensions rather than a test. The sweep's
    /// grammar has only `name` and `where_from`, and wanting to collect by
    /// extension is not a reason to add a third field to a contract two engines
    /// have to agree on.
    var extensions: [String] = []
    /// The folder this hunt owns, when it came from a rule. Everything sitting
    /// in it is offered too — a file dragged there by hand, or one that matched
    /// a pattern since edited, is still the rule's doing — but only ever
    /// unticked, and under a heading that says why.
    var folder: String?

    var isEmpty: Bool {
        extensions.isEmpty && filledTests.isEmpty && folder == nil
    }

    /// Tests with something actually typed in them.
    var filledTests: [RuleTest] {
        tests.filter { !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// How this file was claimed, in the words the list shows — so a match on a
    /// URL is distinguishable at a glance from a match on the name, which is how
    /// a false positive gets noticed before it lands in somebody's accounts.
    func claim(_ subject: RuleSubject, extension ext: String) -> String? {
        for test in filledTests where test.matches(subject) {
            let pattern = test.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(test.field.shortLabel) \(pattern)"
        }
        if !ext.isEmpty, extensions.contains(ext) { return "extension .\(ext)" }
        return nil
    }
}

extension CollectQuery {
    init(rule: Rule) {
        label = rule.name
        tests = rule.tests
        folder = rule.name
    }

    init(typeRule: TypeRule) {
        label = typeRule.name
        extensions = typeRule.extensions
        folder = typeRule.name
    }

    /// The rule this hunt would become. Only the tests travel: a rule has no
    /// notion of an extension, so a query built from a type folder cannot be
    /// saved as one.
    var savableAsRule: Bool { !filledTests.isEmpty }

    func asRule(named name: String) -> Rule {
        Rule(name: name, isEnabled: true, tests: filledTests)
    }
}

/// What one hunt turned up, and how much ground it covered — the sheet says
/// "14 matches · searched 299 folders", and the second half is what tells you
/// the search really did reach back through everything already filed.
struct CollectFindings {
    var candidates: [CollectCandidate] = []
    var foldersSearched: Int = 0

    static let none = CollectFindings()
}

/// One file a collection would take, and where it sits now.
struct CollectCandidate: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// The folder it sits in today — the root's own name for a loose file.
    var currentFolder: String
    /// The test that claimed it, as the list shows it.
    var matched: String
    /// True when nothing about the file itself matched — it is only here
    /// because it was sitting in the folder the hunt is named after. Worth
    /// offering, never worth ticking on somebody's behalf.
    var isIncidental: Bool = false
    /// The date its destination's tokens resolve from.
    var stamp: Date
    var byteSize: Int64
    var isFolder: Bool
}

struct CollectResult {
    var moved: [MoveRecord] = []
    /// Dated folders that had nothing left in them afterwards.
    var emptied: [MoveRecord] = []
    var errors: [String] = []
    /// What was taken, so it can be put back. Nil on a preview and when nothing
    /// moved.
    var batch: CollectBatch?

    var movedCount: Int { moved.count }
    var emptiedCount: Int { emptied.count }
}

// MARK: - Where it lands

/// A place to collect into, remembered as a bookmark rather than a path so it
/// survives a rename or an unmounted volume, plus the template that says which
/// folder under it a given file belongs in.
struct CollectDestination: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// What the favourite is called in the menu.
    var name: String
    /// Resolved to a URL on use. A path would break the first time the folder
    /// above it was renamed, and would break silently.
    var bookmark: Data
    /// The last path this resolved to, for showing in the UI without touching
    /// the disk — and as the fallback if the bookmark itself goes bad.
    var lastKnownPath: String
    /// Appended under the folder, with date tokens resolved per file:
    /// `{yyyy}/quarter {q}/in`. Empty means the folder itself.
    var template: String = ""

    init(id: UUID = UUID(), name: String, bookmark: Data, lastKnownPath: String, template: String = "") {
        self.id = id
        self.name = name
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.template = template
    }
}

extension CollectDestination {
    private enum CodingKeys: String, CodingKey {
        case id, name, bookmark, lastKnownPath, template
    }

    /// Decoded leniently, like everything else the app persists, so a version
    /// that adds a field never blanks somebody's saved places.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        bookmark = try container.decodeIfPresent(Data.self, forKey: .bookmark) ?? Data()
        lastKnownPath = try container.decodeIfPresent(String.self, forKey: .lastKnownPath) ?? ""
        template = try container.decodeIfPresent(String.self, forKey: .template) ?? ""
    }

    /// Makes one from a folder the user picked.
    ///
    /// Reading the folder here is deliberate: `~/Documents` and `~/Desktop` are
    /// protected, and reading one is what raises the system's prompt. Asking now,
    /// with the folder named and the picker still in mind, beats asking in the
    /// middle of a move.
    static func make(name: String, folder: URL, template: String = "") -> CollectDestination? {
        _ = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        guard let bookmark = try? folder.bookmarkData(includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return nil }

        return CollectDestination(
            name: name.isEmpty ? folder.lastPathComponent : name,
            bookmark: bookmark,
            lastKnownPath: folder.path,
            template: template
        )
    }

    /// The path as the window shows it, with the home folder abbreviated.
    var displayPath: String {
        let home = NSHomeDirectory()
        guard lastKnownPath.hasPrefix(home) else { return lastKnownPath }
        return "~" + lastKnownPath.dropFirst(home.count)
    }

    /// True when the folder lives on a volume that is not the boot disk, which
    /// is the difference between "unplug the drive" and "it is simply gone".
    var isOnAVolume: Bool { lastKnownPath.hasPrefix("/Volumes/") }

    /// The folder itself, following the bookmark. Nil when it cannot be found —
    /// an unmounted volume, or a folder that was deleted rather than moved.
    func resolve() -> URL? {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        // A bookmark that no longer resolves is not necessarily a lost folder:
        // the path may simply still be there.
        let fallback = URL(fileURLWithPath: lastKnownPath)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    /// Where a file stamped on this date belongs, under an already-resolved base.
    func folder(under base: URL, on date: Date) -> URL {
        let expanded = CollectDestination.expand(template, on: date)
        return expanded.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// The same thing as text, for the activity list and the preview.
    func describe(on date: Date) -> String {
        let expanded = CollectDestination.expand(template, on: date)
        return ([name] + expanded).joined(separator: "/")
    }

    /// `{yyyy}/quarter {q}` into path components, with the tokens filled in.
    ///
    /// Everything that is not a token is kept exactly as typed, so the folders
    /// can be named in whatever language the accounting is done in.
    static func expand(_ template: String, on date: Date) -> [String] {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 2000
        let month = parts.month ?? 1

        var text = template
        let values: [(String, String)] = [
            ("{yyyy}", String(format: "%04d", year)),
            ("{yy}", String(format: "%02d", year % 100)),
            ("{mm}", String(format: "%02d", month)),
            ("{dd}", String(format: "%02d", parts.day ?? 1)),
            ("{q}", String((month - 1) / 3 + 1)),
        ]
        for (token, value) in values {
            text = text.replacingOccurrences(of: token, with: value, options: .caseInsensitive)
        }

        return text
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    /// Every token the template understands, for the hint under the field.
    static let tokens = ["{yyyy}", "{yy}", "{mm}", "{dd}", "{q}"]
}

// MARK: - Putting a collection back

/// One collection, kept so it can be undone in a single gesture.
struct CollectBatch: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    /// What was being looked for — a rule's name, or the search as typed. The
    /// list reads "Invoices → 2026 · bookkeeping".
    var queryLabel: String = ""
    var destinationName: String
    /// The place it went to, so the list can tell "the drive is unplugged"
    /// apart from "somebody deleted the folder".
    var destinationID: UUID?
    var items: [CollectedItem]

    var count: Int { items.count }
    var byteSize: Int64 { items.reduce(0) { $0 + $1.byteSize } }
}

extension CollectBatch {
    private enum CodingKeys: String, CodingKey {
        case id, date, queryLabel, destinationName, destinationID, items
    }

    /// Decoded leniently, so a batch written before any of this existed still
    /// lists and still comes back.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        queryLabel = try container.decodeIfPresent(String.self, forKey: .queryLabel) ?? ""
        destinationName = try container.decodeIfPresent(String.self, forKey: .destinationName) ?? ""
        destinationID = try container.decodeIfPresent(UUID.self, forKey: .destinationID)
        items = try container.decodeIfPresent([CollectedItem].self, forKey: .items) ?? []
    }

    /// Whether the files could be reached to put them back. A batch on an
    /// unplugged drive is not lost, it is just not here.
    var isReachable: Bool {
        guard let first = items.first else { return false }
        let folder = URL(fileURLWithPath: first.path).deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: folder.path)
    }

    /// Why it cannot be reached, in the words the list uses.
    var unreachableReason: String {
        items.first?.path.hasPrefix("/Volumes/") == true ? "drive offline" : "folder missing"
    }
}

struct CollectedItem: Codable, Equatable {
    /// Where it ended up, after the collision rules had their say.
    var path: String
    var name: String
    /// The folder in the root it came out of. Empty means the root itself.
    var originFolder: String
    var byteSize: Int64 = 0
}

extension CollectedItem {
    private enum CodingKeys: String, CodingKey {
        case path, name, originFolder, byteSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        originFolder = try container.decodeIfPresent(String.self, forKey: .originFolder) ?? ""
        byteSize = try container.decodeIfPresent(Int64.self, forKey: .byteSize) ?? 0
    }
}

/// An immutable copy of what collecting needs, mirroring `RunConfiguration`.
struct CollectConfiguration {
    var root: URL
    var dateBasis: DateBasis = .added
    /// Every rule the app knows about, on or off — a folder filled while a rule
    /// was on is still worth looking in after it was switched off.
    var rules: [Rule] = []
    var typeRules: [TypeRule] = []
    var skipNames: [String] = []
    var includeFolders: Bool = true
    var dryRun: Bool = false
    /// Dated folders left empty by the move are tidied away.
    var removeEmptied: Bool = true
}

extension CollectConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        dateBasis = settings.dateBasis
        rules = settings.rules
        typeRules = settings.typeRules
        skipNames = settings.skipNames
        includeFolders = settings.includeFolders
        dryRun = settings.dryRun
    }
}
