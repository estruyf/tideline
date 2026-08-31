import Foundation

/// Rules that claim a file by what it is called, or by where it came from.
///
/// A type rule asks what a file *is*, which settles a `.dmg` and settles nothing
/// about an invoice: an invoice is a PDF like every other PDF. What marks one out
/// is its name, or the URL it arrived from — so a rule is a folder and a list of
/// tests, and any one of them matching is enough.
///
/// Rules are consulted before the type rules and after everything that decides
/// whether a file moves at all. They answer *where*, never *when*.
///
/// The contract is `docs/behaviour.md`; the cases are `fixtures/sweep-cases.json`.

/// What a test looks at.
enum RuleField: String, Codable, CaseIterable, Identifiable {
    /// The entry's own name, extension included.
    case name
    /// Each URL the download was recorded as arriving from, in turn.
    case whereFrom = "where_from"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return "Name"
        case .whereFrom: return "Downloaded from"
        }
    }

    /// How a match reads back in a list — `name *invoice*`, `downloaded from
    /// stripe.com`. Lower case, because it is a fragment of a sentence rather
    /// than a heading.
    var shortLabel: String {
        switch self {
        case .name: return "name"
        case .whereFrom: return "downloaded from"
        }
    }

    var placeholder: String {
        switch self {
        case .name: return "*invoice*"
        case .whereFrom: return "*stripe*"
        }
    }
}

/// One thing a rule asks about a file.
struct RuleTest: Codable, Identifiable, Equatable {
    var id = UUID()
    var field: RuleField = .name
    /// The skip list's grammar — `*`, `?`, `[a-z]`, `[!abc]` — so `*invoice*`
    /// means "contains" without needing a second operator.
    var pattern: String = ""
    /// Off by default, unlike the skip list. A skip pattern names a file you can
    /// already see in the folder; a rule is a hunt for a word that could have
    /// been typed either way, and a rule that quietly stops matching is not
    /// something anyone notices.
    var matchCase: Bool = false

    init(id: UUID = UUID(), field: RuleField = .name, pattern: String = "", matchCase: Bool = false) {
        self.id = id
        self.field = field
        self.pattern = pattern
        self.matchCase = matchCase
    }
}

extension RuleTest {
    private enum CodingKeys: String, CodingKey {
        case id, field, pattern, matchCase
    }

    /// Decoded leniently, like everything else the app persists: a test written
    /// by the Windows app carries no `id`, and an unknown field falls back to the
    /// name rather than failing the whole rule list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        field = try container.decodeIfPresent(RuleField.self, forKey: .field) ?? .name
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        matchCase = try container.decodeIfPresent(Bool.self, forKey: .matchCase) ?? false
    }

    /// Whether this test claims the file.
    ///
    /// An empty pattern claims nothing: a half-written rule in the settings
    /// window would otherwise match everything the moment the field was cleared.
    func matches(_ subject: RuleSubject) -> Bool {
        let pattern = self.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }

        switch field {
        case .name:
            return RuleTest.glob(pattern, matches: subject.name, matchCase: matchCase)
        case .whereFrom:
            // The interesting word is often escaped inside a query string, so the
            // URL is decoded before it is matched: someone who typed
            // `*/facturen/*` means to find `?path=%2Ffacturen%2F`.
            return subject.whereFrom.contains { url in
                RuleTest.glob(pattern, matches: RuleTest.percentDecoded(url), matchCase: matchCase)
            }
        }
    }

    /// `fnmatch`, with the case rule spelled out rather than left to the platform.
    ///
    /// Folding is done here rather than with `FNM_CASEFOLD` because that calls
    /// `tolower` and so answers to the process locale. The contract says ASCII
    /// `A`–`Z` and nothing else, in every locale and on both platforms, so that a
    /// rule cannot mean one thing here and another in the Rust engine.
    static func glob(_ pattern: String, matches name: String, matchCase: Bool) -> Bool {
        guard !matchCase else { return fnmatch(pattern, name, 0) == 0 }
        return fnmatch(asciiFolded(pattern), asciiFolded(name), 0) == 0
    }

    /// `A`–`Z` down to `a`–`z`, and every other scalar left exactly as it is.
    static func asciiFolded(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 90 }) else {
            return text
        }
        var folded = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value >= 65, scalar.value <= 90 {
                folded.append(UnicodeScalar(scalar.value + 32) ?? scalar)
            } else {
                folded.append(scalar)
            }
        }
        return String(folded)
    }

    /// `%2F` back to `/`, so a pattern can be written the way the path reads.
    ///
    /// Written out rather than handed to `removingPercentEncoding`, which gives
    /// up on the whole string when one escape is malformed. Anything that is not
    /// a valid escape is left exactly as it was: a lone `%` in a
    /// filename-turned-URL is likelier than a typo in an escape, and mangling it
    /// would lose a character the pattern might be looking for.
    static func percentDecoded(_ text: String) -> String {
        guard text.contains("%") else { return text }

        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                out.append(high * 16 + low)
                index += 3
                continue
            }
            out.append(bytes[index])
            index += 1
        }

        // A percent escape can name a byte that is not valid UTF-8 on its own.
        // The pattern could never have matched it anyway, so a replacement
        // character is a better answer than throwing the whole URL away.
        return String(decoding: out, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return byte - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}

/// A folder in the root, and the tests that send files to it.
struct Rule: Codable, Identifiable, Equatable {
    /// Stable across renames, so a rule the user renamed is still the same rule
    /// the next time the app starts.
    var id: String
    var name: String
    var isEnabled: Bool
    var tests: [RuleTest]

    init(id: String = UUID().uuidString, name: String, isEnabled: Bool = true, tests: [RuleTest] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.tests = tests
    }
}

extension Rule {
    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, tests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        tests = try container.decodeIfPresent([RuleTest].self, forKey: .tests) ?? []
    }

    /// Tests are OR'd: any one of them is enough. A rule with none claims
    /// nothing, which is what a rule someone has only just added looks like.
    func matches(_ subject: RuleSubject) -> Bool {
        tests.contains { $0.matches(subject) }
    }

    /// A rule's folder is held to the same standard as a type folder's, since
    /// both end up as a folder in the root.
    static func isValidFolderName(_ name: String) -> Bool {
        TypeRule.isValidFolderName(name)
    }
}

/// What a rule is allowed to ask about one file.
///
/// The where-froms are read the first time a test asks for them and not before:
/// they live in an extended attribute, and a sweep whose rules only look at names
/// should not be reading one per file. A class rather than a struct so the answer
/// is remembered across the tests of every rule in the list.
final class RuleSubject {
    let name: String
    private let url: URL
    private var loaded: [String]?

    init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    var whereFrom: [String] {
        if let loaded { return loaded }
        let urls = WhereFrom.urls(for: url)
        loaded = urls
        return urls
    }
}

/// Decides which rule, if any, claims a given file, and knows the names of the
/// folders those rules own so filing never files one of them away.
///
/// Built once per sweep from an immutable snapshot of the rules.
struct RuleRouter {
    /// Enabled rules whose folder name is usable, in the order they are tried.
    private let rules: [Rule]
    private let ownedNames: Set<String>

    /// Only enabled rules are given to this. They are tried in order and the
    /// first match wins, which is the order the settings window shows.
    init(rules: [Rule]) {
        var kept: [Rule] = []
        var names: Set<String> = []

        for rule in rules {
            let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Rule.isValidFolderName(name) else { continue }
            names.insert(name.lowercased())
            var trimmed = rule
            trimmed.name = name
            kept.append(trimmed)
        }

        self.rules = kept
        ownedNames = names
    }

    var isEmpty: Bool { rules.isEmpty }

    /// The folder this file belongs in, or nil to let the type rules and then
    /// the date decide.
    func folderName(for subject: RuleSubject) -> String? {
        rules.first { $0.matches(subject) }?.name
    }

    /// A rule's folder is never itself filed into a dated one.
    func owns(_ name: String) -> Bool {
        ownedNames.contains(name.lowercased())
    }

    /// Names claimed by more than one enabled rule. The second never sees a
    /// file the first has already taken, so the settings window says so rather
    /// than letting it puzzle.
    static func duplicateNames(in rules: [Rule]) -> [String] {
        var seen: Set<String> = []
        var clashing: [String] = []
        for rule in rules where rule.isEnabled {
            let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if !seen.insert(name.lowercased()).inserted, !clashing.contains(name) {
                clashing.append(name)
            }
        }
        return clashing
    }
}

/// Where a download came from, as macOS recorded it.
///
/// Safari, Chrome and the rest write the source URL and the referrer into an
/// extended attribute, and the attribute travels with the file — which is what
/// lets a rule recognise something that was renamed by hand, and lets a rule
/// written today match what arrived last month.
///
/// Windows keeps the same information in the `Zone.Identifier` alternate data
/// stream; `docs/behaviour.md` has the pair.
enum WhereFrom {
    static let attribute = "com.apple.metadata:kMDItemWhereFroms"

    /// Every URL recorded for this file, source first. Empty is normal and never
    /// an error: a file saved out of a mail client, dropped in over AirDrop or
    /// fetched with `curl` carries none.
    static func urls(for url: URL) -> [String] {
        guard let data = attributeData(at: url.path) else { return [] }
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ),
            let list = plist as? [Any]
        else { return [] }

        return list.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }

    /// The raw attribute, which is a binary plist holding an array of strings.
    private static func attributeData(at path: String) -> Data? {
        path.withCString { cPath -> Data? in
            let length = getxattr(cPath, attribute, nil, 0, 0, 0)
            guard length > 0 else { return nil }

            var buffer = [UInt8](repeating: 0, count: length)
            let read = buffer.withUnsafeMutableBytes { raw in
                getxattr(cPath, attribute, raw.baseAddress, length, 0, 0)
            }
            guard read > 0 else { return nil }

            return Data(buffer.prefix(read))
        }
    }
}
