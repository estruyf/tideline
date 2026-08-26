import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

enum AccessState: Equatable {
    case unknown
    case granted
    case denied
    case missing

    var isUsable: Bool { self == .granted }
}

enum RunTrigger: String {
    case manual = "run by hand"
    case launch = "app started"
    case schedule = "scheduled sweep"
    case watch = "folder changed"
    case wake = "Mac woke up"
    case settings = "settings changed"
}

/// Owns the schedule, the watcher and the run state. One instance, on the main actor.
@MainActor
final class Controller: ObservableObject {
    static let shared = Controller()

    private let settings = Settings.shared
    private let log = ActivityLog.shared
    private let runQueue = DispatchQueue(label: "be.eliostruyf.Tideline.run")
    /// Reading, never writing: measuring the folder and hashing files for
    /// duplicates. Kept off `runQueue` so a long look never delays a sweep.
    private let inspectQueue = DispatchQueue(label: "be.eliostruyf.Tideline.inspect", qos: .utility)

    private var watcher: FolderWatcher?
    private var dailyTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    @Published private(set) var access: AccessState = .unknown
    @Published private(set) var history: [MoveRecord] = []
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var lastRunSummary: String = "Not run yet"
    @Published private(set) var nextRunAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var busy = false
    @Published var loginItemEnabled = false

    /// What the watched folder is holding, as of the last measurement. Nil
    /// until the first one lands, or while the folder cannot be read.
    @Published private(set) var usage: FolderUsage?
    private var measuring = false

    /// What is in the root right now, for the panel on Overview that draws it.
    /// Taken alongside the measurement — both only look, and the window wants
    /// the figure and the picture at the same moment.
    @Published private(set) var snapshot: FolderSnapshot?

    /// What a preview found: everything a sweep would move, for the sheet that
    /// shows it. Filled by a manual preview only — the daily one just logs.
    /// A pane the window should jump to when it next comes up, set by the menu
    /// bar. The window clears it once it has moved, the way the updater does.
    @Published var reveal: MainTab?

    @Published private(set) var plan: [PlannedMove] = []
    @Published var reviewingPlan = false

    /// Files that exist more than once, as of the last scan.
    @Published private(set) var duplicates: [DuplicateGroup] = []
    @Published var reviewingDuplicates = false
    @Published private(set) var duplicateScanning = false
    @Published private(set) var collapsing = false

    /// When the two cheap scans last finished. Opening Reclaim space starts
    /// them, and this is what stops it starting the same walk again every time
    /// you come back to the pane. Cleared whenever the answer could have moved.
    @Published private(set) var largeFilesScannedAt: Date?
    @Published private(set) var clearableScannedAt: Date?

    /// Whether each has run at all, so a card can tell "not looked yet" apart
    /// from "looked, and there is nothing".
    var hasScannedLargeFiles: Bool { largeFilesScannedAt != nil }
    var hasScannedClearable: Bool { clearableScannedAt != nil }

    /// Files big enough to be worth a look, as of the last scan.
    @Published private(set) var largeFiles: [LargeFile] = []
    @Published var reviewingLargeFiles = false
    @Published private(set) var largeFileScanning = false
    @Published private(set) var trimming = false

    /// Dated folders old enough to clear, as of the last scan.
    @Published private(set) var clearable: [CleanupCandidate] = []
    /// Drives the review sheet. Owned here rather than by the view, so the menu
    /// bar can ask for it too — clearing is never triggered without that sheet.
    @Published var reviewingCleanup = false
    @Published private(set) var scanning = false
    @Published private(set) var clearing = false

    /// Files already filed by date that the type rules now claim, as of the
    /// last scan. Switching a type folder on never moves anything on its own —
    /// catching up is always asked for, and always reviewed.
    @Published private(set) var regroupable: [RegroupCandidate] = []
    @Published var reviewingRegroup = false
    @Published private(set) var regroupScanning = false
    @Published private(set) var regrouping = false

    private init() {
        history = log.loadHistory()
        lastRunAt = UserDefaults.standard.object(forKey: "lastRunAt") as? Date
        if let lastRunAt {
            lastRunSummary = "Last checked \(Self.relative.localizedString(for: lastRunAt, relativeTo: Date()))"
        }
        loginItemEnabled = Self.loginItemStatus == .enabled

        NotificationCenter.default.publisher(for: .settingsChanged)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                // The size threshold, the clearing age and the folder itself
                // all decide what a scan finds.
                self?.invalidateScans()
                self?.reconfigure()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        refreshAccess { [weak self] in
            guard let self else { return }
            self.reconfigure()
            self.refreshUsage(force: true)
            self.invalidateScans()
            if self.settings.isEnabled, self.settings.runOnLaunch, self.access.isUsable {
                self.run(trigger: .launch)
            } else {
                self.catchUpIfMissed()
            }
        }
    }

    /// Rebuilds the watcher and the timer from the current settings.
    func reconfigure() {
        dailyTimer?.invalidate()
        dailyTimer = nil
        watcher?.stop()
        watcher = nil
        nextRunAt = nil

        guard settings.isEnabled else { return }

        if settings.watchFolder {
            let watcher = FolderWatcher { [weak self] in
                Task { @MainActor in self?.run(trigger: .watch) }
            }
            watcher.start(url: settings.downloadsURL)
            self.watcher = watcher
        }

        if settings.dailyRunEnabled {
            scheduleDailyTimer()
        }
    }

    private func scheduleDailyTimer() {
        guard let next = nextOccurrence(after: Date()) else { return }
        nextRunAt = next

        let timer = Timer(fireAt: next, interval: 0, target: self,
                          selector: #selector(dailyTimerFired), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        dailyTimer = timer
    }

    @objc private func dailyTimerFired() {
        run(trigger: .schedule)
        scheduleDailyTimer()
    }

    private func handleWake() {
        guard settings.isEnabled else { return }
        // Timers can drift across sleep, so rebuild and cover anything missed.
        reconfigure()
        catchUpIfMissed()
    }

    /// Runs if the scheduled time passed while the Mac was asleep or powered off.
    private func catchUpIfMissed() {
        guard settings.isEnabled, settings.dailyRunEnabled, access.isUsable else { return }
        guard let previous = previousOccurrence(before: Date()) else { return }
        if let lastRunAt, lastRunAt >= previous { return }
        run(trigger: .schedule)
    }

    private func nextOccurrence(after date: Date) -> Date? {
        var components = DateComponents()
        components.hour = settings.dailyRunHour
        components.minute = settings.dailyRunMinute
        components.second = 0
        return Calendar.current.nextDate(after: date, matching: components,
                                         matchingPolicy: .nextTime, direction: .forward)
    }

    private func previousOccurrence(before date: Date) -> Date? {
        var components = DateComponents()
        components.hour = settings.dailyRunHour
        components.minute = settings.dailyRunMinute
        components.second = 0
        return Calendar.current.nextDate(after: date, matching: components,
                                         matchingPolicy: .nextTime, direction: .backward)
    }

    // MARK: - Running

    /// `showingPlan` is for the manual preview: the sweep it runs touches
    /// nothing, and what it would have done opens in a sheet afterwards.
    func run(trigger: RunTrigger, showingPlan: Bool = false) {
        guard !isRunning else { return }
        guard settings.isEnabled || trigger == .manual else { return }

        isRunning = true
        busy = true
        let configuration = RunConfiguration(settings)
        let notify = settings.notifyOnMove
        let cleanup = clearsAutomatically(on: trigger) ? CleanupConfiguration(settings) : nil

        runQueue.async { [weak self] in
            let outcome: Result<RunResult, Error>
            do {
                var result = try Organizer.run(settings: configuration)

                // Filing first, then clearing, so a folder that just received
                // today's straggler is measured with it already inside.
                if let cleanup {
                    let swept = Cleaner.clear(
                        Cleaner.candidates(configuration: cleanup),
                        dryRun: cleanup.dryRun
                    )
                    result.cleared = swept.cleared
                    result.errors.append(contentsOf: swept.errors)
                }

                outcome = .success(result)
            } catch {
                outcome = .failure(error)
            }

            DispatchQueue.main.async {
                self?.finish(outcome, trigger: trigger, notify: notify, showingPlan: showingPlan)
            }
        }
    }

    private func finish(
        _ outcome: Result<RunResult, Error>, trigger: RunTrigger, notify: Bool, showingPlan: Bool = false
    ) {
        isRunning = false
        busy = false

        switch outcome {
        case .failure(let error):
            lastError = error.localizedDescription
            log.write("error (\(trigger.rawValue)): \(error.localizedDescription)")
            refreshAccess()

        case .success(let result):
            lastError = result.errors.first
            lastRunAt = result.finishedAt
            UserDefaults.standard.set(result.finishedAt, forKey: "lastRunAt")

            remember(result.moves + result.cleared)

            if !result.moves.isEmpty, notify, !configurationIsPreview(result) {
                postNotification(for: result)
            }

            let noun = result.movedCount == 1 ? "item" : "items"
            var summary = result.movedCount == 0
                ? "Nothing to file — checked \(result.inspected) \(result.inspected == 1 ? "item" : "items")"
                : "Filed \(result.movedCount) \(noun)"
            if result.clearedCount > 0 {
                summary += " · cleared \(result.clearedCount) \(result.clearedCount == 1 ? "folder" : "folders")"
            }
            lastRunSummary = summary

            for failure in result.errors {
                log.write("error: \(failure)")
            }

            // Only ever after a sweep that moved nothing. Preview mode could
            // have been switched off between the click and the answer, and the
            // sheet has no business claiming a real sweep was a preview.
            if showingPlan, configurationIsPreview(result) {
                plan = result.plan
                reviewingPlan = true
            }

            if result.movedCount > 0 || result.clearedCount > 0 {
                refreshUsage(force: true)
                invalidateScans()
            }
        }
    }

    private func configurationIsPreview(_ result: RunResult) -> Bool {
        result.moves.allSatisfy { $0.wasPreview }
    }

    /// Clearing rides along with the daily sweep only — never with the watcher,
    /// so a file landing in the folder can never trigger a removal.
    private func clearsAutomatically(on trigger: RunTrigger) -> Bool {
        trigger == .schedule && settings.cleanupOnSchedule && settings.cleanupAfterDays > 0
    }

    private func remember(_ records: [MoveRecord]) {
        guard !records.isEmpty else { return }

        history.insert(contentsOf: records.reversed(), at: 0)
        history = Array(history.prefix(300))
        log.save(history)

        for record in records {
            switch record.kind {
            case .filed:
                log.write("\(record.wasPreview ? "would move" : "moved") \(record.name) -> \(record.folder)/")
            case .cleared:
                log.write("\(record.wasPreview ? "would clear" : "cleared") \(record.name)/ -> Trash")
            case .removed:
                log.write("\(record.wasPreview ? "would trash" : "trashed") \(record.name) — \(record.detail ?? "duplicate")")
            case .renamed:
                log.write("\(record.wasPreview ? "would rename" : "renamed") \(record.detail ?? "") -> \(record.name) in \(record.folder)/")
            }
        }
    }

    // MARK: - Clearing out

    /// Looks for folders old enough to go. Measuring them touches every file
    /// inside, so it runs off the main thread like a sweep does.
    func findClearable(completion: @escaping ([CleanupCandidate]) -> Void = { _ in }) {
        scanning = true
        let configuration = CleanupConfiguration(settings)

        runQueue.async { [weak self] in
            let found = Cleaner.candidates(configuration: configuration)
            DispatchQueue.main.async {
                self?.clearable = found
                self?.clearableScannedAt = Date()
                self?.scanning = false
                completion(found)
            }
        }
    }

    func clear(_ selected: [CleanupCandidate], completion: @escaping (CleanupResult) -> Void) {
        guard !clearing, !selected.isEmpty else { return }
        clearing = true
        let dryRun = settings.dryRun

        runQueue.async { [weak self] in
            let outcome = Cleaner.clear(selected, dryRun: dryRun)
            DispatchQueue.main.async {
                self?.finishClearing(outcome)
                completion(outcome)
            }
        }
    }

    private func finishClearing(_ outcome: CleanupResult) {
        clearing = false
        lastError = outcome.errors.first
        remember(outcome.cleared)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        if !outcome.cleared.isEmpty {
            let gone = Set(outcome.cleared.map(\.name))
            clearable.removeAll { gone.contains($0.name) }

            refreshUsage(force: true)
            invalidateScans()

            let noun = outcome.clearedCount == 1 ? "folder" : "folders"
            lastRunSummary = outcome.cleared.allSatisfy(\.wasPreview)
                ? "Previewed clearing \(outcome.clearedCount) \(noun)"
                : "Cleared \(outcome.clearedCount) \(noun) to the Trash"
        }
    }

    // MARK: - Catching up

    /// Walks the dated folders for anything the type rules now claim. Reads
    /// every dated folder, so it runs off the main thread like a sweep does.
    func findRegroupable(completion: @escaping ([RegroupCandidate]) -> Void = { _ in }) {
        regroupScanning = true
        let configuration = RegroupConfiguration(settings)

        runQueue.async { [weak self] in
            let found = Regrouper.candidates(configuration: configuration)
            DispatchQueue.main.async {
                self?.regroupable = found
                self?.regroupScanning = false
                completion(found)
            }
        }
    }

    func regroup(_ selected: [RegroupCandidate], completion: @escaping (RegroupResult) -> Void) {
        guard !regrouping, !selected.isEmpty else { return }
        regrouping = true
        let configuration = RegroupConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Regrouper.apply(selected, configuration: configuration)
            DispatchQueue.main.async {
                self?.finishRegrouping(outcome)
                completion(outcome)
            }
        }
    }

    private func finishRegrouping(_ outcome: RegroupResult) {
        regrouping = false
        lastError = outcome.errors.first
        remember(outcome.moved + outcome.emptied)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        guard !outcome.moved.isEmpty else { return }

        let done = Set(outcome.moved.map(\.name))
        regroupable.removeAll { done.contains($0.name) }
        refreshUsage(force: true)
        invalidateScans()

        let noun = outcome.movedCount == 1 ? "item" : "items"
        var summary = outcome.moved.allSatisfy(\.wasPreview)
            ? "Previewed regrouping \(outcome.movedCount) \(noun)"
            : "Regrouped \(outcome.movedCount) \(noun) by type"
        if outcome.emptiedCount > 0 {
            let folders = outcome.emptiedCount == 1 ? "folder" : "folders"
            summary += " · \(outcome.emptiedCount) empty \(folders) to the Trash"
        }
        lastRunSummary = summary
    }

    // MARK: - What the folder holds

    /// Measures the watched folder. Walking it is not free, so a figure this
    /// fresh is left alone unless the caller insists — after a sweep, say.
    func refreshUsage(force: Bool = false) {
        guard access != .denied, access != .missing else {
            usage = nil
            snapshot = nil
            return
        }
        guard !measuring else { return }
        if !force, let usage, Date().timeIntervalSince(usage.measuredAt) < 30 { return }

        measuring = true
        let root = settings.downloadsURL
        let rules = settings.typeRules
        let configuration = RunConfiguration(settings)

        inspectQueue.async { [weak self] in
            let measured = FolderUsage.measure(root: root, typeRules: rules)
            // The listing is a shallow one and the plan behind it touches
            // nothing, so it rides along with the walk rather than costing a
            // second pass over the folder.
            let listed = FolderSnapshot.take(configuration: configuration)
            DispatchQueue.main.async {
                self?.usage = measured
                self?.snapshot = listed
                self?.measuring = false
            }
        }
    }

    /// The two scans cheap enough to run without being asked: a directory
    /// listing for the big files, and a walk of the dated folders for the ones
    /// old enough to clear. Neither reads a file through.
    ///
    /// Duplicates are deliberately not here. Finding them means hashing, which
    /// means reading candidates end to end, and the app's promise is that
    /// nothing is compared until you ask — so that one keeps its button.
    func scanWhatIsCheap(force: Bool = false) {
        guard access.isUsable else { return }

        if force || largeFilesScannedAt == nil {
            findLargeFiles()
        }

        // With clearing switched off nothing is ever old enough, so the walk
        // would only ever come back empty.
        if settings.cleanupAfterDays > 0, force || clearableScannedAt == nil {
            findClearable()
        }
    }

    /// Anything that could change what the scans would find puts them back to
    /// unscanned, so the next visit to Reclaim space looks again rather than
    /// showing a figure from before the folder moved underneath it.
    private func invalidateScans() {
        largeFilesScannedAt = nil
        clearableScannedAt = nil
    }

    // MARK: - Duplicates

    /// Looks for files that exist more than once. Hashing every candidate is
    /// the slow part, so this runs off the main thread and the sheet waits.
    func findDuplicates(completion: @escaping ([DuplicateGroup]) -> Void = { _ in }) {
        duplicateScanning = true
        let configuration = DedupeConfiguration(settings)

        inspectQueue.async { [weak self] in
            let found = Deduper.scan(configuration: configuration)
            DispatchQueue.main.async {
                self?.duplicates = found
                self?.duplicateScanning = false
                completion(found)
            }
        }
    }

    func collapse(
        _ groups: [DuplicateGroup],
        removing: Set<String>,
        completion: @escaping (DedupeResult) -> Void
    ) {
        guard !collapsing, !removing.isEmpty else { return }
        collapsing = true
        let configuration = DedupeConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Deduper.collapse(groups, removing: removing, configuration: configuration)
            DispatchQueue.main.async {
                self?.finishCollapsing(outcome)
                completion(outcome)
            }
        }
    }

    private func finishCollapsing(_ outcome: DedupeResult) {
        collapsing = false
        lastError = outcome.errors.first
        remember(outcome.removed + outcome.renamed + outcome.emptied)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        guard !outcome.removed.isEmpty else { return }

        // What is left is whatever the next scan says; the sheet asks for one
        // every time it opens, so a stale list is never shown.
        duplicates = []
        refreshUsage(force: true)
        invalidateScans()

        let noun = outcome.removedCount == 1 ? "copy" : "copies"
        let size = FolderUsage.bytes.string(fromByteCount: outcome.reclaimedBytes)
        var summary = outcome.removed.allSatisfy(\.wasPreview)
            ? "Previewed trashing \(outcome.removedCount) duplicate \(noun) · \(size)"
            : "Trashed \(outcome.removedCount) duplicate \(noun) · \(size) back"
        if !outcome.renamed.isEmpty {
            let names = outcome.renamed.count == 1 ? "name" : "names"
            summary += " · \(outcome.renamed.count) \(names) restored"
        }
        if !outcome.emptied.isEmpty {
            let folders = outcome.emptied.count == 1 ? "folder" : "folders"
            summary += " · \(outcome.emptied.count) empty \(folders) to the Trash"
        }
        lastRunSummary = summary
    }

    // MARK: - Big files

    /// Looks for the biggest files in the folder. Only a directory listing —
    /// nothing is read through — but it can pause on a file still being
    /// written, so it keeps off the main thread like the other scans.
    func findLargeFiles(completion: @escaping ([LargeFile]) -> Void = { _ in }) {
        largeFileScanning = true
        let configuration = LargeFileConfiguration(settings)

        inspectQueue.async { [weak self] in
            let found = Weigher.scan(configuration: configuration)
            DispatchQueue.main.async {
                self?.largeFiles = found
                self?.largeFilesScannedAt = Date()
                self?.largeFileScanning = false
                completion(found)
            }
        }
    }

    func trim(
        _ files: [LargeFile],
        removing: Set<String>,
        completion: @escaping (TrimResult) -> Void
    ) {
        guard !trimming, !removing.isEmpty else { return }
        trimming = true
        let configuration = LargeFileConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Weigher.trash(files, removing: removing, configuration: configuration)
            DispatchQueue.main.async {
                self?.finishTrimming(outcome)
                completion(outcome)
            }
        }
    }

    private func finishTrimming(_ outcome: TrimResult) {
        trimming = false
        lastError = outcome.errors.first
        remember(outcome.removed + outcome.emptied)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        guard !outcome.removed.isEmpty else { return }

        // What is left is whatever the next scan says; the sheet asks for one
        // every time it opens, so a stale list is never shown.
        largeFiles = []
        refreshUsage(force: true)
        invalidateScans()

        let noun = outcome.removedCount == 1 ? "file" : "files"
        let size = FolderUsage.bytes.string(fromByteCount: outcome.reclaimedBytes)
        var summary = outcome.removed.allSatisfy(\.wasPreview)
            ? "Previewed trashing \(outcome.removedCount) big \(noun) · \(size)"
            : "Trashed \(outcome.removedCount) big \(noun) · \(size) back"
        if !outcome.emptied.isEmpty {
            let folders = outcome.emptied.count == 1 ? "folder" : "folders"
            summary += " · \(outcome.emptied.count) empty \(folders) to the Trash"
        }
        lastRunSummary = summary
    }

    // MARK: - What could be freed

    /// What the three scans found, with each byte counted once.
    ///
    /// They overlap: a big file can sit inside a folder old enough to clear,
    /// and a duplicate copy can be either or both. Adding the three totals up
    /// claims more space than the folder holds, so this counts every byte by
    /// the widest thing that would take it. `overlaps` says whether any byte
    /// was claimed twice, which is the only reason the window mentions it.
    var reclaimable: (bytes: Int64, overlaps: Bool) {
        // Clearing takes whole folders, so anything inside one is already gone.
        let cleared = clearable.map { $0.url.path + "/" }
        func isCleared(_ url: URL) -> Bool { cleared.contains { url.path.hasPrefix($0) } }

        var total = clearable.reduce(Int64(0)) { $0 + $1.byteSize }
        var double = false
        var counted = Set<String>()

        for file in largeFiles {
            guard !isCleared(file.url) else { double = true; continue }
            counted.insert(file.url.path)
            total += file.byteSize
        }

        for group in duplicates {
            // The newest copy is kept, so only the rest are ever reclaimed.
            for copy in group.copies.dropFirst() {
                if isCleared(copy.url) || counted.contains(copy.url.path) {
                    double = true
                    continue
                }
                counted.insert(copy.url.path)
                total += copy.byteSize
            }
        }

        return (total, double)
    }

    // MARK: - Access

    func refreshAccess(then completion: (() -> Void)? = nil) {
        let url = settings.downloadsURL
        // Reading a protected folder is what triggers the macOS prompt, and it
        // blocks until the user answers — so never do it on the main thread.
        runQueue.async {
            let state: AccessState
            if !FileManager.default.fileExists(atPath: url.path) {
                state = .missing
            } else if (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil {
                state = .granted
            } else {
                state = .denied
            }

            DispatchQueue.main.async { [weak self] in
                self?.access = state
                completion?()
            }
        }
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }

    func revealDownloadsFolder() {
        NSWorkspace.shared.open(settings.downloadsURL)
    }

    /// Opens Finder on one item, selected — for having a proper look at
    /// something before agreeing it can go.
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openLogFile() {
        NSWorkspace.shared.open(log.logURL)
    }

    func clearHistory() {
        history = []
        log.save(history)
    }

    // MARK: - Login item

    private static var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func setLoginItem(_ enabled: Bool) {
        // Either answer settles the first-run suggestion, wherever it was toggled.
        settings.hasAnsweredLoginSuggestion = true

        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginItemEnabled {
                lastError = "macOS needs approval for this login item — check System Settings › General › Login Items."
            }
        } catch {
            loginItemEnabled = SMAppService.mainApp.status == .enabled
            lastError = "Could not change the login item: \(error.localizedDescription)"
        }
    }

    func refreshLoginItem() {
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func postNotification(for result: RunResult) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let folders = Set(result.moves.map(\.folder)).sorted()
        let content = UNMutableNotificationContent()
        content.title = "Downloads filed"
        let noun = result.movedCount == 1 ? "item" : "items"
        content.body = "\(result.movedCount) \(noun) moved into \(folders.joined(separator: ", "))"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Uninstall

    /// Undoes everything the app put outside its own bundle.
    func removeTraces() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        watcher?.stop()
        dailyTimer?.invalidate()
        log.eraseAll()
        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }
        UserDefaults.standard.synchronize()
    }

    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
