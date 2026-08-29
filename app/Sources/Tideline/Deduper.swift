import CryptoKit
import Foundation

/// One copy of a file that exists more than once.
struct DuplicateCopy: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// The folder it sits in, as the window says it — the root's own name for
    /// a loose file, otherwise the dated or type folder holding it.
    var folder: String
    var date: Date
    var byteSize: Int64
    /// The number in its copy suffix — 1 for `artifact-1.zip`, 2 for
    /// `artifact (2).zip` — and nil for a name that carries no suffix at all.
    var copyNumber: Int?

    /// Its name carries a copy suffix: `artifact-1.zip`, `artifact (2).zip`.
    var isSuffixed: Bool { copyNumber != nil }
}

/// A set of files with the same name, bar a copy suffix, and the same contents.
struct DuplicateGroup: Identifiable, Equatable {
    var id: String
    /// The name without the suffix — `artifact.zip`.
    var baseName: String
    /// Newest first, so the one to keep is the one at the top.
    var copies: [DuplicateCopy]
    /// What one copy takes up; they are byte-for-byte identical.
    var byteSize: Int64

    /// What would come back by keeping only one of them.
    var reclaimable: Int64 { byteSize * Int64(max(0, copies.count - 1)) }
}

struct DedupeResult {
    var removed: [MoveRecord] = []
    var renamed: [MoveRecord] = []
    /// Dated folders that the removals left with nothing in them.
    var emptied: [MoveRecord] = []
    var errors: [String] = []
    var reclaimedBytes: Int64 = 0

    var removedCount: Int { removed.count }
}

/// Downloading the same file twice is what a Downloads folder does. The second
/// one lands as `artifact-1.zip`, the third as `artifact-2.zip`, and the name
/// stops telling you anything.
///
/// This finds those: files whose names match once a copy suffix is taken off,
/// which are the same size, and whose contents hash identically. Nothing else
/// counts as a duplicate — two files that merely look alike are left alone —
/// and a group always keeps at least one copy, whatever is ticked.
enum Deduper {

    /// Files bigger than this are hashed in chunks rather than read whole; the
    /// chunk size only decides memory, never what counts as a duplicate.
    private static let chunkSize = 1 << 20

    // MARK: - Finding

    static func scan(configuration: DedupeConfiguration) -> [DuplicateGroup] {
        let fileManager = FileManager.default
        let places = ReviewScope.places(root: configuration.root, typeRules: configuration.typeRules)

        var buckets: [String: [DuplicateCopy]] = [:]

        for place in places {
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

                // Only plain files. A folder — a `.app`, an unzipped download —
                // is never compared, so nothing about them can be removed here.
                guard values?.isDirectory != true else { continue }

                let ext = item.pathExtension.lowercased()
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: configuration.skipNames) { continue }
                if !Organizer.isSettled(item) { continue }

                // Size comes from the logical length here, not the allocated
                // one: two identical files can sit differently on disk.
                let size = Int64(values?.fileSize ?? 0)
                guard size > 0 else { continue }

                let stem = stem(of: name)
                let key = "\(stem.base.lowercased())|\(ext)|\(size)"

                buckets[key, default: []].append(DuplicateCopy(
                    url: item,
                    name: name,
                    folder: place.label,
                    date: Organizer.date(of: item, basis: configuration.dateBasis) ?? .distantPast,
                    byteSize: size,
                    copyNumber: stem.copy
                ))
            }
        }

        var groups: [DuplicateGroup] = []

        // Hashing is the expensive part, so it only ever runs on files that
        // already share a name and a size.
        for (_, copies) in buckets where copies.count > 1 {
            var byDigest: [String: [DuplicateCopy]] = [:]
            for copy in copies {
                guard let digest = digest(of: copy.url) else { continue }
                byDigest[digest, default: []].append(copy)
            }

            for (digest, identical) in byDigest where identical.count > 1 {
                let sorted = identical.sorted(by: isNewer)
                groups.append(DuplicateGroup(
                    id: digest,
                    baseName: plainName(for: sorted),
                    copies: sorted,
                    byteSize: sorted[0].byteSize
                ))
            }
        }

        // Biggest saving first — the reason to look at this list at all.
        return groups.sorted {
            $0.reclaimable == $1.reclaimable
                ? $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
                : $0.reclaimable > $1.reclaimable
        }
    }

    /// Newest first, which decides which copy a group keeps.
    ///
    /// The comparison is by day, not by instant. "Date added" is kept to the
    /// microsecond, and copies that arrived together — ten written in a row, a
    /// folder restored from a backup, a synced folder landing at once — end up
    /// microseconds apart in whatever order the copying walked them, which is
    /// usually alphabetical. That put `(9)` after `(10)`, and the group kept
    /// the wrong one. Sub-second order is an artefact of what moved the files,
    /// never a record of when they were downloaded.
    ///
    /// Within a day the copy suffix is the reliable signal, because it is the
    /// downloader's own count: `(10)` exists only because `(9)` was already
    /// there, and a name with no suffix at all came before either. Days apart
    /// still separate them first, so a file downloaded again today beats the
    /// copy left over from January. The finer timestamp and then the path only
    /// settle two copies the suffix cannot — the same plain name in two
    /// folders — so the same folder always produces the same list.
    private static func isNewer(_ left: DuplicateCopy, _ right: DuplicateCopy) -> Bool {
        let calendar = Calendar.current
        let leftDay = calendar.startOfDay(for: left.date)
        let rightDay = calendar.startOfDay(for: right.date)
        if leftDay != rightDay { return leftDay > rightDay }

        let leftCopy = left.copyNumber ?? 0
        let rightCopy = right.copyNumber ?? 0
        if leftCopy != rightCopy { return leftCopy > rightCopy }

        if left.date != right.date { return left.date > right.date }
        return left.url.path < right.url.path
    }

    // MARK: - Collapsing

    /// Sends the ticked copies to the Trash. Never `unlink`, and never the last
    /// copy of anything: a group with every copy ticked keeps its newest.
    static func collapse(
        _ groups: [DuplicateGroup],
        removing: Set<String>,
        configuration: DedupeConfiguration
    ) -> DedupeResult {
        var result = DedupeResult()
        let fileManager = FileManager.default

        // Remembered so a dated folder emptied by this can be tidied away
        // after, exactly as catching up does.
        var touched: Set<String> = []
        var everythingRemoved: Set<String> = []

        for group in groups {
            var doomed = group.copies.filter { removing.contains($0.id) }
            var kept = group.copies.filter { !removing.contains($0.id) }

            // The belt to the view's braces. Something always survives.
            if kept.isEmpty {
                guard let newest = doomed.first else { continue }
                kept = [newest]
                doomed.removeAll { $0.id == newest.id }
            }
            guard !doomed.isEmpty else { continue }

            var removedPaths: Set<String> = []

            for copy in doomed {
                touched.insert(copy.url.deletingLastPathComponent().path)

                if configuration.dryRun {
                    removedPaths.insert(copy.url.path)
                    everythingRemoved.insert(copy.url.path)
                    result.removed.append(MoveRecord(
                        date: Date(), name: copy.name, folder: "Trash",
                        wasPreview: true, kind: .removed,
                        detail: "duplicate of \(group.baseName) in \(copy.folder)"
                    ))
                    result.reclaimedBytes += copy.byteSize
                    continue
                }

                do {
                    try fileManager.trashItem(at: copy.url, resultingItemURL: nil)
                    removedPaths.insert(copy.url.path)
                    everythingRemoved.insert(copy.url.path)
                    result.removed.append(MoveRecord(
                        date: Date(), name: copy.name, folder: "Trash",
                        wasPreview: false, kind: .removed,
                        detail: "duplicate of \(group.baseName) in \(copy.folder)"
                    ))
                    result.reclaimedBytes += copy.byteSize
                } catch {
                    result.errors.append("\(copy.name): \(error.localizedDescription)")
                }
            }

            guard configuration.restoreNames,
                  kept.count == 1,
                  let survivor = kept.first,
                  survivor.isSuffixed
            else { continue }

            if let record = restoreName(
                of: survivor,
                to: group.baseName,
                freedBy: removedPaths,
                dryRun: configuration.dryRun
            ) {
                result.renamed.append(record)
            }
        }

        result.emptied = Cleaner.clearEmptied(
            touched,
            root: configuration.root,
            moving: everythingRemoved,
            dryRun: configuration.dryRun
        )
        return result
    }

    /// The point of collapsing: with the other copies gone, `artifact-1.zip`
    /// can have its real name back. Only ever when that name is free — nothing
    /// is overwritten to make room for it.
    private static func restoreName(
        of copy: DuplicateCopy,
        to plain: String,
        freedBy removed: Set<String>,
        dryRun: Bool
    ) -> MoveRecord? {
        let fileManager = FileManager.default
        let target = copy.url.deletingLastPathComponent().appendingPathComponent(plain)
        guard target.lastPathComponent != copy.name else { return nil }

        if dryRun {
            // Nothing actually moved, so a name is free if it is about to be.
            let taken = fileManager.fileExists(atPath: target.path) && !removed.contains(target.path)
            guard !taken else { return nil }
            return MoveRecord(
                date: Date(), name: plain, folder: copy.folder,
                wasPreview: true, kind: .renamed, detail: "was \(copy.name)"
            )
        }

        guard !fileManager.fileExists(atPath: target.path) else { return nil }
        guard (try? fileManager.moveItem(at: copy.url, to: target)) != nil else { return nil }

        return MoveRecord(
            date: Date(), name: plain, folder: copy.folder,
            wasPreview: false, kind: .renamed, detail: "was \(copy.name)"
        )
    }

    // MARK: - Names

    /// `artifact-1.zip`, `artifact (2).zip` and `artifact(3).zip` all reduce to
    /// `artifact`. Four digits or more is a year or a version, not a copy, so
    /// `invoice-2024.pdf` keeps its name whole.
    static func stem(of name: String) -> (base: String, copy: Int?) {
        let withoutExtension = (name as NSString).deletingPathExtension
        guard !withoutExtension.isEmpty else { return (name, nil) }

        for pattern in suffixPatterns {
            let range = NSRange(withoutExtension.startIndex..<withoutExtension.endIndex, in: withoutExtension)
            guard let match = pattern.firstMatch(in: withoutExtension, range: range),
                  match.numberOfRanges > 2,
                  let base = Range(match.range(at: 1), in: withoutExtension),
                  let number = Range(match.range(at: 2), in: withoutExtension)
            else { continue }

            let stripped = String(withoutExtension[base]).trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }
            return (stripped, Int(withoutExtension[number]))
        }

        return (withoutExtension, nil)
    }

    /// `artifact-1` and `artifact (2)`, as browsers and this app write them.
    private static let suffixPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^(.+?)\s*\((\d{1,3})\)$"#),
        try! NSRegularExpression(pattern: #"^(.+?)-(\d{1,3})$"#),
    ]

    /// The name to show a group by: the copy that never carried a suffix, if
    /// one of them still exists, otherwise the shared stem plus the extension.
    private static func plainName(for copies: [DuplicateCopy]) -> String {
        if let plain = copies.first(where: { !$0.isSuffixed }) { return plain.name }
        guard let first = copies.first else { return "" }
        let ext = (first.name as NSString).pathExtension
        let base = stem(of: first.name).base
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    // MARK: - Contents

    /// Read in chunks, so a 6 GB disk image is compared without being held in
    /// memory. A file that cannot be read is simply never called a duplicate.
    private static func digest(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// An immutable copy of what collapsing needs, mirroring `RunConfiguration`.
struct DedupeConfiguration {
    var root: URL
    /// Every rule, switched on or not — their folders are looked in either way.
    var typeRules: [TypeRule] = []
    var skipNames: [String] = []
    var dateBasis: DateBasis = .added
    var dryRun: Bool = false
    /// Give the last copy standing its plain name back, where that name is free.
    var restoreNames: Bool = true
}

extension DedupeConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        typeRules = settings.typeRules
        skipNames = settings.skipNames
        dateBasis = settings.dateBasis
        dryRun = settings.dryRun
        restoreNames = settings.duplicateRestoreNames
    }
}
