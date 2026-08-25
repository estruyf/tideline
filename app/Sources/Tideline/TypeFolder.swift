import Foundation

/// A folder at the root of the watched folder that claims files by extension:
/// with `Installers` switched on, a `.dmg` lands in `Installers/` rather than in
/// the folder named for the day it arrived.
///
/// A type folder is flat — no dated folders inside it — and it does not change
/// *when* something moves. A file still waits out the "leave loose in the root"
/// window; the rule only decides where it goes once it is due.
struct TypeRule: Codable, Identifiable, Equatable {
    /// Stable across renames, so a shipped rule the user renamed is still
    /// recognised as that rule the next time the app starts.
    var id: String
    var name: String
    var extensions: [String]
    var isEnabled: Bool
    /// The rules the app ships with. They can be renamed, re-scoped and switched
    /// off, but not removed — resetting one puts its shipped extensions back.
    var isBuiltIn: Bool

    init(id: String, name: String, extensions: [String], isEnabled: Bool = false, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.extensions = TypeRule.normalize(extensions)
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }
}

extension TypeRule {

    // MARK: - Shipped rules

    /// Every rule the app knows about, all switched off. Nothing is filed by
    /// type until the user says so.
    static let builtIns: [TypeRule] = [
        TypeRule(id: "installers", name: "Installers",
                 extensions: ["dmg", "pkg", "mpkg", "iso", "app"], isBuiltIn: true),
        TypeRule(id: "archives", name: "Archives",
                 extensions: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"], isBuiltIn: true),
        TypeRule(id: "images", name: "Images",
                 extensions: ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg"],
                 isBuiltIn: true),
        TypeRule(id: "documents", name: "Documents",
                 extensions: ["pdf", "doc", "docx", "pages", "rtf", "txt", "md", "odt", "epub"], isBuiltIn: true),
        TypeRule(id: "spreadsheets", name: "Spreadsheets",
                 extensions: ["xls", "xlsx", "numbers", "csv", "tsv", "ods"], isBuiltIn: true),
        TypeRule(id: "presentations", name: "Presentations",
                 extensions: ["ppt", "pptx", "key", "odp"], isBuiltIn: true),
        TypeRule(id: "audio", name: "Audio",
                 extensions: ["mp3", "m4a", "wav", "aac", "flac", "aiff", "aif", "ogg"], isBuiltIn: true),
        TypeRule(id: "video", name: "Video",
                 extensions: ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"], isBuiltIn: true),
        TypeRule(id: "fonts", name: "Fonts",
                 extensions: ["ttf", "otf", "ttc", "woff", "woff2"], isBuiltIn: true),
    ]

    /// Stored rules, with any shipped rule the stored list has never seen
    /// appended — so a version that adds a preset shows it, switched off,
    /// without disturbing what the user has already set up.
    static func merged(with stored: [TypeRule]) -> [TypeRule] {
        var result = stored
        let known = Set(stored.map(\.id))
        for rule in builtIns where !known.contains(rule.id) {
            result.append(rule)
        }
        return result
    }

    /// The shipped version of a rule, for the reset button.
    static func builtIn(id: String) -> TypeRule? {
        builtIns.first { $0.id == id }
    }

    // MARK: - Extensions

    /// Lower-cased, leading dots dropped, duplicates removed, order kept.
    static func normalize(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .drop { $0 == "." }
            guard !cleaned.isEmpty else { continue }
            let ext = String(cleaned)
            if seen.insert(ext).inserted { result.append(ext) }
        }
        return result
    }

    /// Accepts whatever separator comes to hand — `dmg, pkg`, `dmg pkg`, `.dmg;.pkg`.
    static func parseExtensions(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ", ;\n\t")
        return normalize(text.components(separatedBy: separators))
    }

    /// `.dmg, .pkg` — how the list reads back in the settings window.
    var displayExtensions: String {
        extensions.map { ".\($0)" }.joined(separator: ", ")
    }

    /// What the extension field is seeded with when the editor opens.
    var editableExtensions: String {
        extensions.joined(separator: ", ")
    }

    // MARK: - Names

    /// A folder name has to be usable as one, and must not look like something
    /// the app files by date — a rule called `2026-08` would collide with the
    /// dated folders, and clearing out would take it away.
    static func isValidFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
        guard !trimmed.hasPrefix(".") else { return false }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else { return false }
        return !Organizer.isManagedFolderName(trimmed)
    }
}

/// Decides which type folder, if any, claims a given file, and knows the names
/// of the folders those rules own so filing never files them away.
///
/// Built once per sweep from an immutable snapshot of the rules.
struct TypeRouter {
    private let folderForExtension: [String: String]
    private let ownedNames: Set<String>

    /// Only enabled rules are given to this. Where two of them claim the same
    /// extension the one higher up the list wins, which is the order the
    /// settings window shows.
    init(rules: [TypeRule]) {
        var folders: [String: String] = [:]
        var names: Set<String> = []

        for rule in rules {
            let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TypeRule.isValidFolderName(name) else { continue }
            names.insert(name.lowercased())
            for ext in rule.extensions where folders[ext] == nil {
                folders[ext] = name
            }
        }

        folderForExtension = folders
        ownedNames = names
    }

    var isEmpty: Bool { folderForExtension.isEmpty }

    /// The folder this file belongs in, or nil to let the date decide.
    func folderName(forExtension ext: String) -> String? {
        guard !ext.isEmpty else { return nil }
        return folderForExtension[ext.lowercased()]
    }

    /// A type folder is never itself filed into a dated one.
    func owns(_ name: String) -> Bool {
        ownedNames.contains(name.lowercased())
    }

    /// Extensions more than one enabled rule asks for. The second rule never
    /// sees them, so the settings window says so rather than letting it puzzle.
    static func conflicts(in rules: [TypeRule]) -> [String] {
        var seen = Set<String>()
        var clashing: [String] = []
        for rule in rules where rule.isEnabled {
            for ext in rule.extensions where !seen.insert(ext).inserted {
                if !clashing.contains(ext) { clashing.append(ext) }
            }
        }
        return clashing
    }
}
