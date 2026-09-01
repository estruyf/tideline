import Foundation

/// One file already filed into a dated folder that a rule now claims.
struct RegroupCandidate: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    /// The dated folder it sits in today.
    var currentFolder: String
    /// The folder a rule would take it to.
    var targetFolder: String
    var byteSize: Int64
}

struct RegroupResult {
    var moved: [MoveRecord] = []
    /// Dated folders that had nothing left in them afterwards.
    var emptied: [MoveRecord] = []
    var errors: [String] = []

    var movedCount: Int { moved.count }
    var emptiedCount: Int { emptied.count }
}

/// Catching up. Switching on `Installers`, or writing a rule that finds
/// invoices, only changes where *future* downloads go — everything already
/// tucked into a dated folder stays there. This walks the dated folders the app
/// made and pulls out what the rules now claim, which is what makes a rule
/// written today reach what arrived last month.
///
/// Only folders matching the dated pattern are opened, only their immediate
/// contents are considered, and nothing that is not claimed by a rule is
/// touched. Folders you made yourself are never looked inside.
enum Regrouper {

    // MARK: - Finding

    static func candidates(configuration: RegroupConfiguration) -> [RegroupCandidate] {
        let ruleRouter = RuleRouter(rules: configuration.rules)
        let router = TypeRouter(rules: configuration.typeRules)
        guard !ruleRouter.isEmpty || !router.isEmpty else { return [] }

        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: configuration.root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let dated = entries
            .filter { Organizer.isManagedFolderName($0.lastPathComponent) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        var found: [RegroupCandidate] = []

        for folder in dated {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = item.lastPathComponent
                let ext = item.pathExtension.lowercased()

                // The same guards filing uses, so catching up can never do
                // something a normal sweep would have refused to do.
                if Organizer.incompleteExtensions.contains(ext) { continue }
                if Organizer.matchesSkipList(name, patterns: configuration.skipNames) { continue }

                // The same order a sweep asks in: a routing rule first, then a
                // type rule, or catching up would file things somewhere filing
                // never would.
                let subject = RuleSubject(name: name, url: item)
                let claimed = ruleRouter.folderName(for: subject)
                    ?? router.folderName(forExtension: ext)
                guard let target = claimed else { continue }

                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true {
                    // Safari's in-progress bundle, and folders when filing them is off.
                    if ext == "download" { continue }
                    if !configuration.includeFolders { continue }
                }

                found.append(RegroupCandidate(
                    url: item,
                    name: name,
                    currentFolder: folder.lastPathComponent,
                    targetFolder: target,
                    byteSize: Int64(values?.fileSize ?? 0)
                ))
            }
        }

        return found
    }

    // MARK: - Applying

    static func apply(
        _ candidates: [RegroupCandidate],
        configuration: RegroupConfiguration
    ) -> RegroupResult {
        var result = RegroupResult()
        let fileManager = FileManager.default

        // Remembered so a folder emptied by the move can be tidied away after,
        // rather than left behind as an empty shell.
        var touchedFolders: Set<String> = []

        for candidate in candidates {
            touchedFolders.insert(candidate.currentFolder)

            if configuration.dryRun {
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name,
                    folder: candidate.targetFolder, wasPreview: true
                ))
                continue
            }

            let destination = configuration.root
                .appendingPathComponent(candidate.targetFolder, isDirectory: true)
            let target = Organizer.freeTarget(in: destination, for: candidate.name)

            do {
                if !fileManager.fileExists(atPath: destination.path) {
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                }
                try fileManager.moveItem(at: candidate.url, to: target)
                result.moved.append(MoveRecord(
                    date: Date(), name: candidate.name,
                    folder: candidate.targetFolder, wasPreview: false
                ))
            } catch {
                result.errors.append("\(candidate.name): \(error.localizedDescription)")
            }
        }

        if configuration.removeEmptied {
            let paths = touchedFolders.map {
                configuration.root.appendingPathComponent($0, isDirectory: true).path
            }
            result.emptied = Cleaner.clearEmptied(
                Set(paths),
                root: configuration.root,
                moving: Set(candidates.map(\.url.path)),
                dryRun: configuration.dryRun
            )
        }

        return result
    }
}

/// An immutable copy of what catching up needs, mirroring `RunConfiguration`.
struct RegroupConfiguration {
    var root: URL
    /// Only the rules that are switched on, routing rules first.
    var rules: [Rule] = []
    var typeRules: [TypeRule] = []
    var skipNames: [String] = []
    var includeFolders: Bool = true
    var dryRun: Bool = false
    /// Dated folders left empty by the move are tidied away.
    var removeEmptied: Bool = true
}

extension RegroupConfiguration {
    @MainActor
    init(_ settings: Settings) {
        root = settings.downloadsURL
        rules = settings.rules.filter(\.isEnabled)
        typeRules = settings.typeRules.filter(\.isEnabled)
        skipNames = settings.skipNames
        includeFolders = settings.includeFolders
        dryRun = settings.dryRun
    }
}
