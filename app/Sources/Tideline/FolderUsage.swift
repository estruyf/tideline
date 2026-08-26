import Foundation

/// How much the watched folder is holding right now: the headline figure the
/// window and the menu bar show, plus enough of a split to say where it sits.
///
/// Measuring walks every file under the root, so it is done off the main thread
/// and cached — nothing here is needed to file anything, it only reports.
struct FolderUsage: Equatable {
    /// Everything under the root, loose files and folders alike.
    var totalBytes: Int64 = 0
    /// Files sitting loose in the root — today's downloads, in the usual case.
    var looseBytes: Int64 = 0
    var looseItems: Int = 0
    /// Folders Tideline made: dated ones, plus the type folders.
    var managedFolders: Int = 0
    /// Folders at the root that are none of Tideline's doing.
    var otherFolders: Int = 0
    /// Set when the folder was too large to walk to the end.
    var isPartial: Bool = false
    /// The cap the walk ran under, so a floor can say how far it got rather
    /// than only that it stopped somewhere.
    var itemCap: Int = FolderUsage.defaultCap
    var measuredAt: Date = .distantPast

    var filedBytes: Int64 { max(0, totalBytes - looseBytes) }

    /// "12.4 GB", or "more than 12.4 GB" when the walk was cut short.
    var totalDescription: String {
        (isPartial ? "more than " : "") + FolderUsage.bytes.string(fromByteCount: totalBytes)
    }

    var looseDescription: String {
        FolderUsage.bytes.string(fromByteCount: looseBytes)
    }

    var filedDescription: String {
        FolderUsage.bytes.string(fromByteCount: filedBytes)
    }

    /// "60,000" — the cap, written the way a sentence about it needs it.
    var itemCapDescription: String {
        FolderUsage.counts.string(from: NSNumber(value: itemCap)) ?? "\(itemCap)"
    }

    /// How far a walk goes before it reports a floor instead of a total. High
    /// enough that an ordinary Downloads folder is measured exactly, low enough
    /// that a pathological one cannot hold the inspect queue for a minute.
    static let defaultCap = 60_000

    static let counts: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}

extension FolderUsage {

    /// Walks the folder once. `cap` bounds the work on a folder with tens of
    /// thousands of files: past it the figure is reported as a floor rather
    /// than a total, which is still worth saying and costs a known amount.
    static func measure(root: URL, cap: Int = defaultCap, typeRules: [TypeRule] = []) -> FolderUsage {
        let fileManager = FileManager.default
        var usage = FolderUsage(itemCap: cap, measuredAt: Date())

        let router = TypeRouter(rules: typeRules)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return usage }

        var budget = cap

        for entry in entries {
            let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            )

            guard values?.isDirectory == true else {
                let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                usage.looseItems += 1
                usage.looseBytes += size
                usage.totalBytes += size
                budget -= 1
                continue
            }

            let name = entry.lastPathComponent
            if Organizer.isManagedFolderName(name) || router.owns(name) {
                usage.managedFolders += 1
            } else {
                usage.otherFolders += 1
            }

            let measured = size(of: entry, budget: budget)
            usage.totalBytes += measured.bytes
            usage.isPartial = usage.isPartial || measured.partial
            budget = measured.budget
        }

        usage.isPartial = usage.isPartial || budget <= 0
        return usage
    }

    /// The size of one folder, walked no further than the budget allows.
    static func size(of folder: URL, budget: Int) -> (bytes: Int64, partial: Bool, budget: Int) {
        guard budget > 0 else { return (0, true, 0) }

        guard let walker = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return (0, false, budget) }

        var bytes: Int64 = 0
        var left = budget

        for case let file as URL in walker {
            left -= 1
            if left <= 0 { return (bytes, true, 0) }

            let values = try? file.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }
            bytes += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }

        return (bytes, false, left)
    }

    /// Convenience for one folder on its own, used when planning a sweep.
    static func size(of folder: URL, cap: Int = 5_000) -> Int64 {
        size(of: folder, budget: cap).bytes
    }
}
