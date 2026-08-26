import Foundation

/// What the watched folder is holding right now, listed rather than added up.
///
/// The window used to draw a sketch of a tidy Downloads folder — the right idea
/// with the wrong contents, because it was the same picture whatever was
/// actually in there. This is the real thing: the root, one level deep, with
/// each entry marked for what it is and whether the next sweep would move it.
///
/// Which of it is due comes straight from `Organizer.plan`, so the panel and a
/// sweep read the rules from the same place and cannot disagree about a file.
struct FolderSnapshot: Equatable {

    struct Entry: Identifiable, Equatable {
        enum Kind: Equatable {
            /// A folder a type rule owns — files land in it whatever the day.
            case typeFolder
            /// A dated folder Tideline made.
            case datedFolder
            /// A folder that is none of Tideline's doing.
            case ownFolder
            case file
        }

        var id: String { name }
        var name: String
        var kind: Kind
        /// Folders only: how many things are in there.
        var itemCount: Int
        /// The date the filing rules would sort it by, when it has one.
        var stamp: Date?
        /// Set when the next sweep would move this entry.
        var isDue: Bool

        var isFolder: Bool { kind != .file }
    }

    /// Newest first within each group, folders before loose files.
    var entries: [Entry] = []
    /// Every loose file in the root, including the ones past `entries`.
    var looseItems: Int = 0
    /// Dated and type folders together — what Tideline has filed into.
    var filedFolders: Int = 0
    /// How many of the loose items the next sweep would move.
    var dueItems: Int = 0
    /// Set when the root held more than the listing shows.
    var isTruncated: Bool = false
    var takenAt: Date = .distantPast

    var isEmpty: Bool { entries.isEmpty }
}

extension FolderSnapshot {

    /// Lists the root. `limit` bounds what is kept for display; the counts are
    /// of everything, so a folder with a thousand items still reports honestly.
    static func take(configuration: RunConfiguration, limit: Int = 60) -> FolderSnapshot {
        let fileManager = FileManager.default
        var snapshot = FolderSnapshot(takenAt: Date())

        guard let contents = try? fileManager.contentsOfDirectory(
            at: configuration.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return snapshot }

        // Asking the planner rather than re-deciding here: the grace window,
        // the skip list and the settling rule all live in one place.
        let due = Set((try? Organizer.plan(settings: configuration))?.moves.map(\.name) ?? [])
        let router = TypeRouter(rules: configuration.typeRules)

        var found: [Entry] = []

        for url in contents {
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            let kind: Entry.Kind
            if !isDirectory {
                kind = .file
            } else if Organizer.isManagedFolderName(name) {
                kind = .datedFolder
            } else if router.owns(name) {
                kind = .typeFolder
            } else {
                kind = .ownFolder
            }

            switch kind {
            case .datedFolder, .typeFolder: snapshot.filedFolders += 1
            case .ownFolder: break
            case .file: snapshot.looseItems += 1
            }

            let isDue = due.contains(name)
            if isDue { snapshot.dueItems += 1 }

            found.append(Entry(
                name: name,
                kind: kind,
                itemCount: isDirectory ? count(in: url) : 0,
                stamp: Organizer.date(of: url, basis: configuration.dateBasis),
                isDue: isDue
            ))
        }

        found.sort(by: precedes)
        snapshot.isTruncated = found.count > limit
        snapshot.entries = Array(found.prefix(limit))
        return snapshot
    }

    /// Type folders, then the dated folders newest first, then folders of your
    /// own, then the loose files newest first — the order Finder would show a
    /// filed folder in, near enough, with what is due to move at the bottom.
    private static func precedes(_ a: Entry, _ b: Entry) -> Bool {
        if rank(a.kind) != rank(b.kind) { return rank(a.kind) < rank(b.kind) }

        switch a.kind {
        case .typeFolder, .ownFolder:
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        case .datedFolder:
            // The names sort as dates already, newest last, so this reverses them.
            return a.name.localizedStandardCompare(b.name) == .orderedDescending
        case .file:
            guard let left = a.stamp, let right = b.stamp else { return a.stamp != nil }
            if left == right { return a.name.localizedStandardCompare(b.name) == .orderedAscending }
            return left > right
        }
    }

    private static func rank(_ kind: Entry.Kind) -> Int {
        switch kind {
        case .typeFolder: return 0
        case .datedFolder: return 1
        case .ownFolder: return 2
        case .file: return 3
        }
    }

    /// One level, and only to say "6 items" next to a folder name.
    private static func count(in folder: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).count) ?? 0
    }
}
