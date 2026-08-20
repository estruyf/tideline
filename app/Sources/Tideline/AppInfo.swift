import Foundation

/// The handful of constants that name the app: used by the About section, the
/// menu bar title and the feedback link, so they can never drift apart.
enum AppInfo {
    static let name = "Tideline"
    static let author = "Elio Struyf"

    static let repository = URL(string: "https://github.com/estruyf/tideline")!
    static let issues = URL(string: "https://github.com/estruyf/tideline/issues")!
    static let newIssue = URL(string: "https://github.com/estruyf/tideline/issues/new")!
    static let authorProfile = URL(string: "https://github.com/estruyf")!

    /// Stamped into Info.plist at build time from package.json.
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    /// A build timestamp, regenerated on every build — worth quoting in a bug report.
    static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"

    static var nameAndVersion: String { "\(name) \(version)" }
    static var versionLine: String { "Version \(version) · build \(build)" }
}
