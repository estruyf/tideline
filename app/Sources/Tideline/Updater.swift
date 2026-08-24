import AppKit
import Foundation
import Security
import UserNotifications

/// A version as it appears in a release tag — `v1.2.0` reads as 1.2.0.
/// Anything after a `-` (a pre-release marker) is kept for display and sorts
/// below the same numbers without one, the way semver says it should.
struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    var numbers: [Int]
    var prerelease: String?

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }

        // Build metadata never affects precedence, so it is dropped outright.
        if let plus = text.firstIndex(of: "+") { text = String(text[text.startIndex..<plus]) }

        var tail: String?
        if let dash = text.firstIndex(of: "-") {
            tail = String(text[text.index(after: dash)...])
            text = String(text[text.startIndex..<dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return nil }

        var values: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            values.append(value)
        }

        numbers = values
        prerelease = (tail?.isEmpty ?? true) ? nil : tail
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        // 1.3.0-beta.1 comes before 1.3.0.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        case (let left?, let right?): return left < right
        }
    }

    var description: String {
        let core = numbers.map(String.init).joined(separator: ".")
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}

/// A published release, reduced to what the app needs to show and fetch.
struct Release: Equatable, Sendable {
    var version: AppVersion
    var notes: String
    var page: URL
    var download: URL
    var size: Int64
    var publishedAt: Date?

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// "released 3 days ago", or nothing when GitHub did not say. The formatter
    /// is built here rather than shared: this reads once, when a card is drawn.
    var releasedText: String? {
        guard let publishedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "released \(formatter.localizedString(for: publishedAt, relativeTo: Date()))"
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(Release)
    case downloading(Double)
    case installing
    case restarting
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing, .restarting: return true
        default: return false
        }
    }
}

enum UpdateError: LocalizedError {
    case notAnApp
    case translocated
    case notWritable(String)
    case noAsset(String)
    case badResponse(Int)
    case rateLimited
    case unreadableArchive
    case unpackFailed(String)
    case signatureMismatch(String)
    case wrongPayload(String)

    var errorDescription: String? {
        switch self {
        case .notAnApp:
            return "This build is not running from an app bundle, so it can't replace itself. Download the release from GitHub instead."
        case .translocated:
            return "macOS is running Tideline from a temporary read-only copy. Move it to your Applications folder, reopen it, and try again."
        case .notWritable(let path):
            return "No permission to replace \(path). Move Tideline somewhere you can write to, or download the release from GitHub."
        case .noAsset(let tag):
            return "Release \(tag) has no macOS build attached yet. Try again in a few minutes, or download it from GitHub."
        case .badResponse(let code):
            return "GitHub replied with HTTP \(code)."
        case .rateLimited:
            return "GitHub is rate-limiting this Mac. Try again later, or check the releases page."
        case .unreadableArchive:
            return "The downloaded file did not contain a Tideline app."
        case .unpackFailed(let detail):
            return "Could not unpack the download: \(detail)"
        case .signatureMismatch(let detail):
            return "The downloaded app is not signed by the same developer as this one, so it was thrown away. (\(detail))"
        case .wrongPayload(let detail):
            return "The download did not look like the release it claimed to be: \(detail)"
        }
    }
}

/// Checks GitHub Releases for a newer build, and — once the download is proven
/// to carry the same signature as the running app — swaps it in and restarts.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let settings = Settings.shared
    private let log = ActivityLog.shared

    /// How long a check stays fresh before an automatic one runs again.
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    /// How often the timer wakes up to ask whether a check is due.
    private static let pollInterval: TimeInterval = 4 * 60 * 60

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastCheckedAt: Date?
    /// The newest release seen, kept even after the panel is closed, so the menu
    /// bar and the Status tab can mention it without checking again.
    @Published private(set) var pending: Release?
    /// Set from the menu bar to bring the window up on the update section.
    @Published var reveal = false

    private var pollTimer: Timer?
    private var checking = false

    private init() {
        lastCheckedAt = settings.lastUpdateCheckAt
    }

    // MARK: - Lifecycle

    func start() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        timer.tolerance = 60 * 30
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // A moment after launch, so a check never competes with the first sweep.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.checkIfDue()
        }
    }

    /// A quiet check, run only when automatic checks are on and the last one has aged out.
    func checkIfDue() {
        guard settings.automaticUpdateChecks, canSelfUpdate else { return }
        if let lastCheckedAt, Date().timeIntervalSince(lastCheckedAt) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    /// The update UI is only meaningful for an installed .app bundle.
    var canSelfUpdate: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Whether the Status tab has anything to show: an update worth mentioning,
    /// or one that is being fetched right now.
    var hasNews: Bool {
        if case .failed = state { return true }
        return nag != nil || state.isBusy
    }

    /// A release worth mentioning unprompted: newer, and not one that was skipped.
    var nag: Release? {
        guard let pending, settings.skippedUpdateVersion != pending.version.description else { return nil }
        return pending
    }

    // MARK: - Checking

    func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        if userInitiated || state == .idle { state = .checking }

        Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await Self.fetchLatest()
                self.finishCheck(with: release, userInitiated: userInitiated)
            } catch {
                self.checking = false
                // A failed background check stays quiet — it retries on its own.
                if userInitiated {
                    self.state = .failed(Self.message(for: error))
                } else if self.state == .checking {
                    self.state = .idle
                }
                self.log.write("update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishCheck(with release: Release?, userInitiated: Bool) {
        checking = false
        lastCheckedAt = Date()
        settings.lastUpdateCheckAt = lastCheckedAt

        guard let release, let current = AppVersion(AppInfo.version), release.version > current else {
            pending = nil
            state = .upToDate
            return
        }

        pending = release
        state = .available(release)
        log.write("update available: \(release.version) (running \(AppInfo.version))")

        if !userInitiated, settings.skippedUpdateVersion != release.version.description {
            notify(about: release)
        }
    }

    /// Stops this one version from being mentioned again; a later one still is.
    func skip(_ release: Release) {
        settings.skippedUpdateVersion = release.version.description
        state = .idle
    }

    // MARK: - Installing

    func install(_ release: Release) {
        guard !state.isBusy else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let target = try Self.installTarget()

                self.state = .downloading(0)
                let archive = try await Self.download(release) { [weak self] fraction in
                    self?.state = .downloading(fraction)
                }
                defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

                self.state = .installing
                let staged = try await Self.unpackAndVerify(archive: archive, release: release)

                self.log.write("installing \(release.version) over \(target.path)")
                self.state = .restarting
                try Self.swapIn(staged: staged, target: target)

                // The helper is waiting on this process to go away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSApp.terminate(nil)
                }
            } catch {
                self.state = .failed(Self.message(for: error))
                self.log.write("update failed: \(error.localizedDescription)")
            }
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(pending?.page ?? AppInfo.releasesPage)
    }

    func dismissFailure() {
        state = pending.map { .available($0) } ?? .idle
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Mentions a new version only where notifications were already allowed —
    /// finding an update is never a reason to raise a permission prompt.
    private func notify(about release: Release) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { status in
            guard status.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Tideline \(release.version) is available"
            content.body = "You are running \(AppInfo.version). Open Tideline to install it."
            let request = UNNotificationRequest(identifier: "update-\(release.version)",
                                                content: content, trigger: nil)
            center.add(request)
        }
    }
}

// MARK: - GitHub

extension Updater {
    private struct GitHubRelease: Decodable {
        var tagName: String
        var name: String?
        var body: String?
        var htmlUrl: URL
        var draft: Bool
        var prerelease: Bool
        var publishedAt: Date?
        var assets: [Asset]

        struct Asset: Decodable {
            var name: String
            var size: Int64
            var browserDownloadUrl: URL
        }
    }

    /// The newest published release, or nil when the repository has none.
    nonisolated static func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub turns away callers without one.
        request.setValue("Tideline/\(AppInfo.version) (+\(AppInfo.repository.absoluteString))",
                         forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.badResponse(0) }

        switch http.statusCode {
        case 200: break
        case 404: return nil // No releases published yet.
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.badResponse(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubRelease.self, from: data)

        guard !payload.draft, !payload.prerelease else { return nil }
        guard let version = AppVersion(payload.tagName) else { return nil }
        guard let asset = macAsset(in: payload.assets, version: version),
              asset.browserDownloadUrl.scheme?.lowercased() == "https"
        else { throw UpdateError.noAsset(payload.tagName) }

        return Release(
            version: version,
            notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            page: payload.htmlUrl,
            download: asset.browserDownloadUrl,
            size: asset.size,
            publishedAt: payload.publishedAt
        )
    }

    /// The universal build the release workflow attaches, with a loose fallback
    /// so a renamed asset still updates rather than sending you to the browser.
    private nonisolated static func macAsset(in assets: [GitHubRelease.Asset], version: AppVersion) -> GitHubRelease.Asset? {
        let expected = "Tideline-\(version)-macos-universal.zip"
        if let exact = assets.first(where: { $0.name == expected }) { return exact }
        return assets.first {
            $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().contains("tideline")
        }
    }

    private nonisolated static func download(
        _ release: Release,
        onProgress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let reporter = DownloadReporter { fraction in
            Task { @MainActor in onProgress(fraction) }
        }

        var request = URLRequest(url: release.download)
        request.setValue("Tideline/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: reporter)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdateError.badResponse(http.statusCode)
        }

        // URLSession deletes its own temporary file the moment this returns.
        let directory = try scratchDirectory("download")
        let archive = directory.appendingPathComponent("Tideline.zip")
        try FileManager.default.moveItem(at: temporary, to: archive)
        return archive
    }
}

/// Turns download callbacks into a 0…1 fraction.
private final class DownloadReporter: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    /// Required by the protocol; the async download API hands the file back itself.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

// MARK: - Unpacking, verifying and swapping

extension Updater {
    /// An unpacked, verified app and the temporary directory holding it, which
    /// the swap script clears out once the copy is in place.
    struct StagedApp {
        var app: URL
        var scratch: URL
    }

    /// Where the running app lives, once it is clear it can be replaced at all.
    private nonisolated static func installTarget() throws -> URL {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { throw UpdateError.notAnApp }
        // Gatekeeper runs quarantined apps from a read-only shadow copy.
        guard !bundle.path.contains("/AppTranslocation/") else { throw UpdateError.translocated }

        let parent = bundle.deletingLastPathComponent()
        let manager = FileManager.default
        guard manager.isWritableFile(atPath: parent.path), manager.isWritableFile(atPath: bundle.path) else {
            throw UpdateError.notWritable(bundle.path)
        }
        return bundle
    }

    /// Unpacks the archive and refuses anything that is not the same app, signed
    /// by the same developer. Runs off the main thread — it spawns tools and
    /// walks the whole bundle.
    private nonisolated static func unpackAndVerify(archive: URL, release: Release) async throws -> StagedApp {
        try await Task.detached(priority: .userInitiated) {
            let directory = try scratchDirectory("staged")
            let unpacked = directory.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)

            let ditto = try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])
            guard ditto.status == 0 else {
                try? FileManager.default.removeItem(at: directory)
                throw UpdateError.unpackFailed(ditto.output.isEmpty ? "ditto exited \(ditto.status)" : ditto.output)
            }

            guard let app = try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else {
                try? FileManager.default.removeItem(at: directory)
                throw UpdateError.unreadableArchive
            }

            do {
                try checkPayload(app, matches: release)
                try checkSignature(of: app)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }

            return StagedApp(app: app, scratch: directory)
        }.value
    }

    /// The bundle has to be Tideline, and the version it carries has to be the
    /// one the release advertised.
    private nonisolated static func checkPayload(_ app: URL, matches release: Release) throws {
        guard let bundle = Bundle(url: app),
              let identifier = bundle.bundleIdentifier,
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        else { throw UpdateError.wrongPayload("no readable Info.plist") }

        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongPayload("bundle identifier \(identifier)")
        }
        guard AppVersion(version) == release.version else {
            throw UpdateError.wrongPayload("it contains \(version), not \(release.version)")
        }
    }

    /// The download must satisfy the same Developer ID requirement the running
    /// app does. A locally built, ad-hoc signed copy has no team to pin to, so
    /// it falls back to demanding a valid Apple-anchored Developer ID signature.
    private nonisolated static func checkSignature(of app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.signatureMismatch("unreadable signature")
        }

        let text: String
        if let team = teamIdentifier(of: Bundle.main.bundleURL) {
            text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        } else {
            text = "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { throw UpdateError.signatureMismatch("could not build the requirement") }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else {
            throw UpdateError.signatureMismatch("OSStatus \(status)")
        }

        // Notarization is Apple's own check, and only it can catch a build that
        // was signed with a stolen-but-revoked identity.
        let assessment = try? run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        if let assessment, assessment.status != 0 {
            throw UpdateError.signatureMismatch("Gatekeeper rejected it: \(assessment.output)")
        }
    }

    private nonisolated static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Hands the swap to a detached script: the app cannot overwrite itself
    /// while it is the thing running. The script waits for this process to go,
    /// puts the old bundle aside, copies the new one in and reopens it — and
    /// puts the old one back untouched if anything goes wrong.
    private nonisolated static func swapIn(staged: StagedApp, target: URL) throws {
        let helpers = try scratchDirectory("install")
        let script = helpers.appendingPathComponent("swap.sh")
        let backup = helpers.appendingPathComponent("previous.app")

        let body = """
        #!/bin/bash
        # Written by Tideline to replace itself; safe to delete.
        trap '' HUP INT TERM

        STAGED=\(quote(staged.app.path))
        TARGET=\(quote(target.path))
        BACKUP=\(quote(backup.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)

        # Wait up to 30s for the old app to quit.
        for _ in $(seq 1 300); do
          /bin/kill -0 "$PID" 2>/dev/null || break
          /bin/sleep 0.1
        done
        if /bin/kill -0 "$PID" 2>/dev/null; then
          /bin/kill "$PID" 2>/dev/null
          /bin/sleep 1
        fi

        /bin/rm -rf "$BACKUP"
        if ! /bin/mv "$TARGET" "$BACKUP"; then
          /usr/bin/open "$TARGET"
          exit 1
        fi

        if ! /usr/bin/ditto "$STAGED" "$TARGET"; then
          /bin/rm -rf "$TARGET"
          /bin/mv "$BACKUP" "$TARGET"
          /usr/bin/open "$TARGET"
          exit 1
        fi

        # The signature was checked before this script was written.
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null

        /bin/rm -rf "$BACKUP" \(quote(staged.scratch.path))
        /usr/bin/open "$TARGET"
        """

        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: - Small helpers

    private nonisolated static func scratchDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tideline-update-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }

    private nonisolated static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
