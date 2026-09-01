import Foundation

/// One filed item, and the folder it would come back out of.
struct RestoreCandidate: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// The folder it sits in today — a dated one, or a folder a rule made.
    var currentFolder: String
    /// True when a rule claimed it — routing or type — rather than the date.
    var isByRule: Bool
    var byteSize: Int64
}

struct RestoreResult {
    var moved: [MoveRecord] = []
    /// Folders that had nothing left in them afterwards.
    var emptied: [MoveRecord] = []
    var errors: [String] = []

    var movedCount: Int { moved.count }
    var emptiedCount: Int { emptied.count }
}

/// Putting it all back. Filing is the only thing this app does that a person
/// cannot undo with one gesture in Finder — a year of downloads is spread
/// across a hundred folders, and dragging them out again by hand is not an
/// answer. This walks the folders Tideline made, moves everything back into the
/// root, and takes the empty folders to the Trash behind it.
///
/// It is the mirror of `Organizer`, and it keeps the same promises: only the
/// folders the app made itself are opened, nothing is overwritten — a name
/// already taken counts up — and nothing is deleted, only trashed.
enum Restorer {

    // MARK: - Finding

    static func candidates(configuration: RestoreConfiguration) -> [RestoreCandidate] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: configuration.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let destinations = Set(configuration.destinationFolderNames)

        // Newest first, so the list opens on what was filed most recently —
        // which is what someone undoing filing is most likely to be looking for.
        let folders = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .filter {
                Organizer.isManagedFolderName($0.lastPathComponent)
                    || destinations.contains($0.lastPathComponent)
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        var found: [RestoreCandidate] = []

        for folder in folders {
            let name = folder.lastPathComponent
            guard let contents = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                // Only the immediate contents. A downloaded folder that was
                // filed as one thing comes back as one thing.
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                found.append(RestoreCandidate(
                    url: item,
                    name: item.lastPathComponent,
                    currentFolder: name,
                    isByRule: destinations.contains(name),
                    byteSize: Int64(values?.fileSize ?? 0)
                ))
            }
        }

        return found
    }

    // MARK: - Applying

    static func apply(
        _ candidates: [RestoreCandidate],
        configuration: RestoreConfiguration
    ) -> RestoreResult {
        var result = RestoreResult()
        let fileManager = FileManager.default
        let rootName = configuration.root.lastPathComponent

        // Remembered so a folder this empties can go afterwards, rather than
        // being left behind as a shell with nothing in it.
        var touched: Set<String> = []

        for candidate in candidates {
            touched.insert(candidate.currentFolder)

            if configuration.dryRun {
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: rootName,
                    wasPreview: true, detail: "back out of \(candidate.currentFolder)"
                ))
                continue
            }

            let target = Organizer.freeTarget(in: configuration.root, for: candidate.name)
            do {
                try fileManager.moveItem(at: candidate.url, to: target)
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name, folder: rootName,
                    wasPreview: false, detail: "back out of \(candidate.currentFolder)"
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

        return result
    }

    /// The folders this run took files out of, once there is nothing left in
    /// them. Unlike clearing, a type folder goes too: an empty `Installers` is
    /// not something the folder had before Tideline, so putting things back
    /// means putting that back as well.
    private static func clearEmptied(
        _ names: Set<String>,
        configuration: RestoreConfiguration,
        moving: Set<String>
    ) -> [MoveRecord] {
        let fileManager = FileManager.default
        var cleared: [MoveRecord] = []

        for name in names.sorted() {
            let folder = configuration.root.appendingPathComponent(name, isDirectory: true)
            guard folder.path != configuration.root.path else { continue }

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
}

/// An immutable copy of what putting things back needs, mirroring
/// `RunConfiguration`.
struct RestoreConfiguration {
    var root: URL
    /// Every folder a rule owns — routing and type both — switched on or not:
    /// a folder it filled last month is still its doing after the rule was
    /// switched off.
    var destinationFolderNames: [String] = []
    var dryRun: Bool = false
    /// Folders left empty by the move go to the Trash.
    var removeEmptied: Bool = true
}

extension RestoreConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        destinationFolderNames = settings.rules.map(\.name) + settings.typeRules.map(\.name)
        dryRun = settings.dryRun
    }
}
