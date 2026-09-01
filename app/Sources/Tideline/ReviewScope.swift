import Foundation

/// One folder a review looks in, under the name the window shows it by.
struct Place: Equatable {
    var url: URL
    /// The root's own name for a loose file, otherwise the dated or type
    /// folder holding it.
    var label: String
}

/// Where the reviews that read the folder — duplicates, big files — are allowed
/// to look: the root itself, plus the folders Tideline made. A folder you made
/// yourself is never opened, exactly as filing never opens one.
enum ReviewScope {

    static func places(root: URL, rules: [Rule], typeRules: [TypeRule]) -> [Place] {
        // Every rule's folder, on or off: a rule switched off still has files
        // sitting in the folder it made while it was on.
        let ruleRouter = RuleRouter(rules: rules)
        let router = TypeRouter(rules: typeRules)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var places = [Place(url: root, label: root.lastPathComponent)]

        for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            guard Organizer.isManagedFolderName(name) || ruleRouter.owns(name) || router.owns(name)
            else { continue }
            places.append(Place(url: entry, label: name))
        }

        return places
    }
}
