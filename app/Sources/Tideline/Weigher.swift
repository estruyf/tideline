import Foundation

/// One file big enough to be worth a second look.
struct LargeFile: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// The folder it sits in, as the window says it — the root's own name for a
    /// loose file, otherwise the dated or type folder holding it.
    var folder: String
    var date: Date
    var byteSize: Int64
}

struct TrimResult {
    var removed: [MoveRecord] = []
    /// Dated folders that the removals left with nothing in them.
    var emptied: [MoveRecord] = []
    var errors: [String] = []
    var reclaimedBytes: Int64 = 0

    var removedCount: Int { removed.count }
}

/// A Downloads folder fills up from the top: one installer, one screen
/// recording, one virtual machine image nobody remembers pulling down. Filing
/// tidies a folder; it never shrinks one, and a hundred neatly dated PDFs are
/// not what is taking up the space.
///
/// This lists what is — plain files in the root and in the folders Tideline
/// made, over a size you pick, biggest first. Nothing is chosen for you: unlike
/// a duplicate, a big file is the only copy there is, so every row starts
/// unticked and goes to the Trash only if you say so.
enum Weigher {

    // MARK: - Finding

    static func scan(configuration: LargeFileConfiguration) -> [LargeFile] {
        let threshold = configuration.thresholdBytes
        guard threshold > 0 else { return [] }

        let fileManager = FileManager.default
        var found: [LargeFile] = []

        for place in ReviewScope.places(root: configuration.root, typeRules: configuration.typeRules) {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: place.url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents {
                let name = item.lastPathComponent
                let values = try? item.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                ])

                // Only plain files. A folder — one you made, an unzipped
                // download, a `.app` — is never listed and so can never be
                // trashed from here; dated folders have their own review.
                guard values?.isDirectory != true else { continue }

                let ext = item.pathExtension.lowercased()
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: configuration.skipNames) { continue }

                // What the file takes up on disk, which is the figure that
                // matters when the question is where the space went.
                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                guard size >= threshold else { continue }

                // Checked last: it can pause on a file still being written, and
                // there is no reason to pause on one that is too small to list.
                if !Organizer.isSettled(item) { continue }

                found.append(LargeFile(
                    url: item,
                    name: name,
                    folder: place.label,
                    date: Organizer.date(of: item, basis: configuration.dateBasis) ?? .distantPast,
                    byteSize: size
                ))
            }
        }

        // Biggest first — the reason to look at this list at all.
        return found.sorted {
            $0.byteSize == $1.byteSize
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.byteSize > $1.byteSize
        }
    }

    // MARK: - Trimming

    /// Sends the ticked files to the Trash. Never `unlink`, and never anything
    /// that was not ticked — there is no "keep one" here to fall back on.
    static func trash(
        _ files: [LargeFile],
        removing: Set<String>,
        configuration: LargeFileConfiguration
    ) -> TrimResult {
        var result = TrimResult()
        let fileManager = FileManager.default

        // Remembered so a dated folder emptied by this can be tidied away
        // after, exactly as collapsing duplicates does.
        var touched: Set<String> = []
        var removedPaths: Set<String> = []

        for file in files where removing.contains(file.id) {
            touched.insert(file.url.deletingLastPathComponent().path)
            let size = FolderUsage.bytes.string(fromByteCount: file.byteSize)

            if configuration.dryRun {
                removedPaths.insert(file.url.path)
                result.removed.append(MoveRecord(
                    date: Date(), name: file.name, folder: "Trash",
                    wasPreview: true, kind: .removed,
                    detail: "\(size) in \(file.folder)"
                ))
                result.reclaimedBytes += file.byteSize
                continue
            }

            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                removedPaths.insert(file.url.path)
                result.removed.append(MoveRecord(
                    date: Date(), name: file.name, folder: "Trash",
                    wasPreview: false, kind: .removed,
                    detail: "\(size) in \(file.folder)"
                ))
                result.reclaimedBytes += file.byteSize
            } catch {
                result.errors.append("\(file.name): \(error.localizedDescription)")
            }
        }

        result.emptied = Cleaner.clearEmptied(
            touched,
            root: configuration.root,
            moving: removedPaths,
            dryRun: configuration.dryRun
        )

        return result
    }
}

/// An immutable copy of what a big-file review needs, mirroring `RunConfiguration`.
struct LargeFileConfiguration {
    var root: URL
    /// Every rule, switched on or not — their folders are looked in either way.
    var typeRules: [TypeRule] = []
    var skipNames: [String] = []
    var dateBasis: DateBasis = .added
    var dryRun: Bool = false
    /// How big a file has to be to appear, in megabytes as Finder counts them —
    /// a million bytes, so the number here matches the size the rows show.
    var thresholdMegabytes: Int = 100

    var thresholdBytes: Int64 { Int64(max(0, thresholdMegabytes)) * 1_000_000 }
}

extension LargeFileConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        typeRules = settings.typeRules
        skipNames = settings.skipNames
        dateBasis = settings.dateBasis
        dryRun = settings.dryRun
        thresholdMegabytes = settings.largeFileThresholdMB
    }
}
