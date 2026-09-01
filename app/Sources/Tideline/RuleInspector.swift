import Foundation

/// One file a rule turned up, and the test that claimed it.
struct RuleMatchSample: Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String
    /// How it was claimed, in the words the editor shows — `name contains
    /// invoice`, `downloaded from is stripe.com`. A match on a URL has to be
    /// distinguishable at a glance from a match on the name, because that is
    /// how a rule that catches too much gets noticed before it files anything.
    var reason: String
    /// The folder it sits in today: the root, or the dated folder holding it.
    var place: String
    var isFiledByDate: Bool
}

/// What one rule is actually catching, as the folder stands right now.
///
/// The counts are what this rule would *get*, not what its conditions describe:
/// a file a rule above already claimed is that rule's, and saying otherwise
/// would have every rule in an overlapping list reporting the same file.
struct RuleFinding: Equatable {
    /// Loose in the root — what the next sweep would hand this rule.
    var loose = 0
    /// Already tucked into a dated folder, which is what catching up reaches.
    var filedByDate = 0
    /// Matched, but claimed by a rule higher up the list first.
    var takenAbove = 0
    /// The first of them, for the editor's preview. Bounded, so a rule that
    /// matches four thousand files does not carry four thousand rows around.
    var samples: [RuleMatchSample] = []
    /// The rule above this one that claims every file this one does, and so
    /// never lets it fire.
    var shadowedBy: String?
    /// Where that rule sits, so the row can offer to move this one above it.
    var shadowedByIndex: Int?
    /// How many files are being claimed out from under it — every file it
    /// matches, since a shadowed rule gets none of them.
    var shadowedCount = 0

    var total: Int { loose + filedByDate }
    var isShadowed: Bool { shadowedBy != nil }
    /// True when more matched than were kept for the preview.
    var hasMoreThanSampled: Bool { total > samples.count }
}

/// Every rule's findings, by rule id.
struct RuleReport: Equatable {
    var findings: [String: RuleFinding] = [:]
    var takenAt: Date = .distantPast
    /// Nothing has been counted yet, so a row says "counting…" rather than
    /// claiming a rule matches nothing.
    var isFresh: Bool { takenAt != .distantPast }

    subscript(_ rule: Rule) -> RuleFinding? { findings[rule.id] }
}

/// Counts what the routing rules would catch, so the pane can say so.
///
/// A rule is written blind: a pattern with a typo looks exactly like one that
/// works, and stays looking like it for months. This walks the root and the
/// dated folders once and answers the two questions the window could never
/// answer before — how many files does this rule claim, and does a rule above
/// it claim them all first.
///
/// It reads and never writes, so it belongs on `inspectQueue`. The guards are
/// the ones filing uses, borrowed rather than restated, so a count can never
/// promise something a sweep would refuse to do.
enum RuleInspector {

    /// How many matches are kept per rule for the editor's preview.
    static let sampleLimit = 60

    static func report(inspection: RuleInspection) -> RuleReport {
        var report = RuleReport(takenAt: Date())
        guard !inspection.rules.isEmpty else { return report }

        let fileManager = FileManager.default
        let rules = inspection.rules
        let typeRouter = TypeRouter(rules: inspection.typeRules)
        let ruleRouter = RuleRouter(rules: rules)

        // Enabled, usably named, and with something to ask: only these can take
        // a file, and so only these can shadow the rule below them.
        let live = Set(rules.indices.filter { index in
            let rule = rules[index]
            return rule.isEnabled
                && Rule.isValidFolderName(rule.name.trimmingCharacters(in: .whitespacesAndNewlines))
                && !rule.filledTests.isEmpty
        })

        var findings = [RuleFinding](repeating: RuleFinding(), count: rules.count)
        /// Per rule: everything its conditions describe, whether or not it gets
        /// to keep it, and the earliest rule that took one away.
        var gross = [Int](repeating: 0, count: rules.count)
        var claimedBy = [Int?](repeating: nil, count: rules.count)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: inspection.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return report }

        // The root itself, then the dated folders newest first — the order the
        // preview reads best in, since what is loose is what moves next.
        var places: [Place] = [Place(url: inspection.root, label: inspection.root.lastPathComponent)]
        var datedFolders: [URL] = []

        for entry in entries {
            let name = entry.lastPathComponent
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            if Organizer.isManagedFolderName(name) { datedFolders.append(entry) }
        }

        places += datedFolders
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { Place(url: $0, label: $0.lastPathComponent) }

        for place in places {
            let isRoot = place.url == inspection.root

            guard let contents = try? fileManager.contentsOfDirectory(
                at: place.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = item.lastPathComponent
                let ext = item.pathExtension.lowercased()

                // A folder the app made is a place to look inside, never a
                // thing a rule claims — and a destination folder's contents
                // have already arrived, so they are nobody's match.
                if isRoot, Organizer.isManagedFolderName(name) { continue }
                if isRoot, ruleRouter.owns(name) || typeRouter.owns(name) { continue }

                // The same guards a sweep uses, so a count cannot promise a
                // move filing would have refused.
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: inspection.skipNames) { continue }

                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                if isDirectory {
                    if ext == "download" { continue }
                    if !inspection.includeFolders { continue }
                }

                // One subject per entry, so the where-from attribute is read
                // once however many rules ask about it.
                let subject = RuleSubject(name: name, url: item)
                var firstLiveClaimer: Int?

                for index in rules.indices {
                    guard let test = rules[index].claimingTest(subject) else { continue }
                    gross[index] += 1

                    if let claimer = firstLiveClaimer {
                        // A rule above already has this one. Remembered rather
                        // than counted, so the row can say who took it.
                        findings[index].takenAbove += 1
                        if claimedBy[index] == nil { claimedBy[index] = claimer }
                    } else {
                        if isRoot {
                            findings[index].loose += 1
                        } else {
                            findings[index].filedByDate += 1
                        }

                        if findings[index].samples.count < sampleLimit {
                            findings[index].samples.append(RuleMatchSample(
                                path: item.path,
                                name: name,
                                reason: test.sentence ?? name,
                                place: place.label,
                                isFiledByDate: !isRoot
                            ))
                        }
                    }

                    if live.contains(index), firstLiveClaimer == nil { firstLiveClaimer = index }
                }
            }
        }

        // A rule never fires when every file it claims was taken by a rule
        // above it. Said of a rule that matches nothing it would be noise —
        // that rule is not shadowed, it is simply waiting.
        for index in rules.indices where live.contains(index) {
            guard gross[index] > 0, findings[index].total == 0,
                  let claimer = claimedBy[index] else { continue }
            findings[index].shadowedBy = rules[claimer].displayName
            findings[index].shadowedByIndex = claimer
            findings[index].shadowedCount = gross[index]
        }

        for (index, rule) in rules.enumerated() {
            report.findings[rule.id] = findings[index]
        }
        return report
    }
}

/// Whether one rule's destination folder is already there, and how much is in
/// it.
///
/// Asked for on its own rather than folded into the walk above, because the
/// folder is being *typed*: it changes a letter at a time while somebody names
/// a rule, and reading one directory per keystroke is nothing, while walking
/// the root and every dated folder per keystroke is a form that will not sit
/// still.
struct DestinationCheck: Equatable {
    /// The folder this answer is about, so a reply that arrives after the name
    /// moved on can be recognised as stale rather than shown against it.
    var folder: String
    var exists: Bool
    var items: Int

    static func take(folder: String, root: URL) -> DestinationCheck {
        let url = root.appendingPathComponent(folder, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else {
            return DestinationCheck(folder: folder, exists: false, items: 0)
        }
        return DestinationCheck(folder: folder, exists: true, items: items.count)
    }
}

/// An immutable copy of what counting needs, mirroring `RunConfiguration`.
///
/// Every rule travels, switched off ones included: the pane says what a rule
/// *would* catch, which is the only way to see whether one is worth switching
/// on before it moves anything.
struct RuleInspection {
    var root: URL
    var rules: [Rule] = []
    var typeRules: [TypeRule] = []
    var skipNames: [String] = []
    var includeFolders: Bool = true
}

extension RuleInspection {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        rules = settings.rules
        typeRules = settings.typeRules.filter(\.isEnabled)
        skipNames = settings.skipNames
        includeFolders = settings.includeFolders
    }
}
