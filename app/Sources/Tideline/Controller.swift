import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

enum AccessState: Equatable {
    /// Nobody has asked macOS yet, and deliberately so: reading the folder is
    /// what raises the permission prompt, and a prompt that arrives before the
    /// window has said what the app is for is a question with no context.
    case notAsked
    case unknown
    case granted
    case denied
    case missing

    var isUsable: Bool { self == .granted }

    /// Whether looking at the folder at all is allowed. A scan, a measurement
    /// and a sweep all read it, and reading it before `notAsked` has been
    /// answered would ask the question this state exists to hold back.
    var mayRead: Bool { self == .unknown || self == .granted }
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

    @Published private(set) var access: AccessState = .notAsked
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
    /// Published, because the window offers a full measurement of a folder too
    /// large to total under the usual cap and has to say when one is running.
    @Published private(set) var measuring = false

    /// Set once someone has asked for the exact figure. Every measurement for
    /// the rest of the session then walks the whole folder, however long that
    /// takes — quietly dropping back to the floor after the next sweep would
    /// undo the asking.
    private var measureInFull = false

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

    /// Drives the sheet that asks whether to start filing at all. Owned here
    /// rather than by the view, because the menu bar has to be able to ask for
    /// it too — nothing starts filing without it.
    @Published var askingToStart = false

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
    /// What each routing rule is catching as the folder stands right now —
    /// counts, the files behind them, and whether a rule above claims them all
    /// first. Refreshed when the rules pane asks and after anything moves.
    @Published private(set) var ruleReport = RuleReport()
    @Published private(set) var ruleScanning = false
    /// Whether the open rule's destination folder is already there. Kept apart
    /// from the report because it answers to a name being typed rather than to
    /// the rules changing.
    @Published private(set) var destination: DestinationCheck?
    /// A rule changed while a count was running, so the answer in flight is
    /// already out of date and another walk follows it.
    private var ruleInspectAgain = false

    @Published private(set) var regroupable: [RegroupCandidate] = []
    @Published var reviewingRegroup = false
    @Published private(set) var regroupScanning = false
    @Published private(set) var regrouping = false

    /// Collecting. `collectable` is what the last hunt turned up; `collections`
    /// is what has already been taken and can still be put back.
    @Published private(set) var collectable: [CollectCandidate] = []
    @Published private(set) var collectFoldersSearched = 0
    @Published var reviewingCollect = false
    @Published private(set) var collectScanning = false
    @Published private(set) var collecting = false
    @Published private(set) var collections: [CollectBatch] = []
    /// How much each rule would turn up right now, for the starting points the
    /// pane offers. Empty until the pane asks.
    @Published private(set) var collectWaiting: [String: Int] = [:]
    @Published private(set) var collectTallying = false
    /// The hunt the sheet should open on, set when a starting point is pressed.
    @Published var collectOpeningQuery: CollectQuery?

    /// Everything sitting in a folder Tideline made, as of the last scan —
    /// what putting it all back would move.
    @Published private(set) var restorable: [RestoreCandidate] = []
    @Published var reviewingRestore = false
    @Published private(set) var restoreScanning = false
    @Published private(set) var restoring = false

    private init() {
        history = log.loadHistory()
        collections = log.loadCollections()
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

    /// Filing runs on two answers, not one: the switch in the header, and the
    /// question asked once on a fresh install. Both have to be yes.
    var filingActive: Bool { settings.isEnabled && settings.hasStartedFiling }

    /// Says yes to the question the welcome sheet asks, and sweeps straight
    /// away — the answer was to a button marked "Start Filing", so waiting for
    /// midnight to act on it would be the wrong kind of cautious.
    func startFiling() {
        settings.hasStartedFiling = true
        settings.isEnabled = true
        log.write("filing started by the user")
        reconfigure()
        run(trigger: .manual)
    }

    func start() {
        // Reading the folder is what raises the permission prompt, so at launch
        // it is only ever read where that cannot happen: an install that has
        // been granted access already, or one that is filing and so plainly
        // was. Anywhere else the window opens first and asks in its own words.
        guard settings.hasGrantedAccess || settings.hasStartedFiling else {
            access = .notAsked
            return
        }

        // Everything below reads the folder, and a read only happens once the
        // state is off `notAsked` — `refreshAccess` declines to probe until it
        // is. The guard above has just established that this install was
        // granted access or has been filing, so the probe is silent; without
        // this line it never runs, and the window asks for a permission the
        // app already holds.
        access = .unknown

        refreshAccess { [weak self] in
            guard let self else { return }
            self.reconfigure()
            self.refreshUsage(force: true)
            self.invalidateScans()
            if self.filingActive, self.settings.runOnLaunch, self.access.isUsable {
                self.run(trigger: .launch)
            } else {
                self.catchUpIfMissed()
            }
        }
    }

    /// Raises the macOS permission prompt, on purpose and at a moment someone
    /// chose. Reading the folder is what asks — there is no API for "ask me" —
    /// so the first read is the request, and everything the window does with
    /// the folder waits behind it.
    func requestAccess() {
        access = .unknown

        refreshAccess { [weak self] in
            guard let self else { return }
            self.reconfigure()
            self.refreshUsage(force: true)
            self.scanWhatIsCheap()
        }
    }

    /// Rebuilds the watcher and the timer from the current settings.
    func reconfigure() {
        dailyTimer?.invalidate()
        dailyTimer = nil
        watcher?.stop()
        watcher = nil
        nextRunAt = nil

        guard filingActive else { return }

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
        guard filingActive else { return }
        // Timers can drift across sleep, so rebuild and cover anything missed.
        reconfigure()
        catchUpIfMissed()
    }

    /// Runs if the scheduled time passed while the Mac was asleep or powered off.
    private func catchUpIfMissed() {
        guard filingActive, settings.dailyRunEnabled, access.isUsable else { return }
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
        // Until filing has been agreed to, the only sweep on offer is one that
        // moves nothing: a preview is how you decide, so it cannot be gated on
        // the decision.
        guard settings.hasStartedFiling || (trigger == .manual && settings.dryRun) else { return }

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
            case .collected:
                log.write("\(record.wasPreview ? "would move out" : "moved out") \(record.name) -> \(record.folder) \(record.detail ?? "")")
            }
        }
    }

    // MARK: - Clearing out

    /// Looks for folders old enough to go. Measuring them touches every file
    /// inside, so it runs off the main thread like a sweep does.
    func findClearable(completion: @escaping ([CleanupCandidate]) -> Void = { _ in }) {
        guard access.mayRead else { return completion([]) }
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

    // MARK: - What the rules catch

    /// Counts what every routing rule would claim, in one walk of the root and
    /// the dated folders.
    ///
    /// On `inspectQueue` with the other readers: the pane asks for this every
    /// time a pattern is typed into, and a long look must never delay a sweep.
    func inspectRules() {
        guard access.mayRead else { return }
        // A rule edited while the last count was still running would otherwise
        // be counted under the rules as they were a moment ago, and the pane
        // would sit there showing the wrong number until something else moved.
        guard !ruleScanning else { return ruleInspectAgain = true }
        guard !settings.rules.isEmpty else {
            ruleReport = RuleReport(takenAt: Date())
            return
        }

        ruleScanning = true
        ruleInspectAgain = false
        let inspection = RuleInspection(settings)

        inspectQueue.async { [weak self] in
            let report = RuleInspector.report(inspection: inspection)
            DispatchQueue.main.async {
                guard let self else { return }
                self.ruleReport = report
                self.ruleScanning = false
                if self.ruleInspectAgain { self.inspectRules() }
            }
        }
    }

    /// Looks up one rule's destination folder. One directory read, so it can
    /// follow the name being typed without the pane having to wait for it.
    func checkDestination(_ folder: String?) {
        guard let folder, Rule.isValidFolderName(folder), access.mayRead else {
            return destination = nil
        }

        let root = settings.downloadsURL
        inspectQueue.async { [weak self] in
            let found = DestinationCheck.take(folder: folder, root: root)
            DispatchQueue.main.async { self?.destination = found }
        }
    }

    // MARK: - Catching up

    /// Walks the dated folders for anything the type rules now claim. Reads
    /// every dated folder, so it runs off the main thread like a sweep does.
    func findRegroupable(completion: @escaping ([RegroupCandidate]) -> Void = { _ in }) {
        guard access.mayRead else { return completion([]) }
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

    // MARK: - Collecting

    /// Hunts for what a query claims, across the root and every folder the app
    /// made. Reads a lot of folders, so it goes on `inspectQueue` — a long look
    /// must never delay a sweep.
    func findCollectable(
        matching query: CollectQuery,
        completion: @escaping ([CollectCandidate]) -> Void = { _ in }
    ) {
        guard access.mayRead else { return completion([]) }
        collectScanning = true
        let configuration = CollectConfiguration(settings)

        inspectQueue.async { [weak self] in
            let findings = Collector.candidates(matching: query, configuration: configuration)
            DispatchQueue.main.async {
                self?.collectable = findings.candidates
                self?.collectFoldersSearched = findings.foldersSearched
                self?.collectScanning = false
                completion(findings.candidates)
            }
        }
    }

    /// How much each rule and type folder would turn up, in one walk. Asked for
    /// by the pane, which offers them as starting points.
    func tallyCollectable() {
        guard access.mayRead, !collectTallying else { return }
        collectTallying = true

        let configuration = CollectConfiguration(settings)
        let queries = settings.rules.filter(\.isEnabled).map { CollectQuery(rule: $0) }
            + settings.typeRules.filter(\.isEnabled).map { CollectQuery(typeRule: $0) }

        inspectQueue.async { [weak self] in
            let counts = Collector.tally(queries, configuration: configuration)
            DispatchQueue.main.async {
                self?.collectWaiting = counts
                self?.collectTallying = false
            }
        }
    }

    /// Opens the sheet already looking for something.
    func startCollecting(_ query: CollectQuery? = nil) {
        collectOpeningQuery = query
        reviewingCollect = true
    }

    /// Moves the ticked files out. On `runQueue`, because it moves files and a
    /// sweep must not be doing the same thing at the same time.
    func collect(
        _ selected: [CollectCandidate],
        to destination: CollectDestination,
        as label: String,
        completion: @escaping (CollectResult) -> Void
    ) {
        guard !collecting, !selected.isEmpty else { return }
        collecting = true
        let configuration = CollectConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Collector.apply(
                selected, to: destination, as: label, configuration: configuration
            )
            DispatchQueue.main.async {
                self?.finishCollecting(outcome, undoing: false)
                completion(outcome)
            }
        }
    }

    /// Puts a whole collection back where it came from.
    func undoCollection(_ batch: CollectBatch, completion: @escaping (CollectResult) -> Void = { _ in }) {
        guard !collecting else { return }
        collecting = true
        let configuration = CollectConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Collector.undo(batch, configuration: configuration)
            DispatchQueue.main.async {
                if !configuration.dryRun, outcome.errors.count < batch.count {
                    self?.forget(batch)
                }
                self?.finishCollecting(outcome, undoing: true)
                completion(outcome)
            }
        }
    }

    private func finishCollecting(_ outcome: CollectResult, undoing: Bool) {
        collecting = false
        lastError = outcome.errors.first
        remember(outcome.moved + outcome.emptied)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        if let batch = outcome.batch {
            collections.insert(batch, at: 0)
            log.save(collections)
        }

        guard !outcome.moved.isEmpty else { return }

        let done = Set(outcome.moved.map(\.name))
        collectable.removeAll { done.contains($0.name) }
        refreshUsage(force: true)
        invalidateScans()

        let noun = outcome.movedCount == 1 ? "item" : "items"
        let verb = outcome.moved.allSatisfy(\.wasPreview)
            ? (undoing ? "Previewed putting back" : "Previewed moving out")
            : (undoing ? "Put back" : "Moved out")
        var summary = "\(verb) \(outcome.movedCount) \(noun)"
        if outcome.emptiedCount > 0 {
            let folders = outcome.emptiedCount == 1 ? "folder" : "folders"
            summary += " · \(outcome.emptiedCount) empty \(folders) to the Trash"
        }
        lastRunSummary = summary
    }

    private func forget(_ batch: CollectBatch) {
        collections.removeAll { $0.id == batch.id }
        log.save(collections)
    }

    /// What a sweep would move, worked out and thrown away. `run` is the only
    /// thing that files, and this never calls it — the welcome sheet needs a
    /// figure to put in front of someone before they decide, and asking the
    /// planner is how you get one without touching the folder.
    func inspectPlan(completion: @escaping (SweepPlan?) -> Void) {
        let configuration = RunConfiguration(settings)
        // Not on `inspectQueue`, which is serial: granting access starts a
        // measurement of the whole folder on it, and a plan queued behind that
        // is a spinner someone watches for as long as the walk takes. Planning
        // only lists the root — it never opens a subfolder — so it is quick
        // enough to run beside the walk rather than after it.
        DispatchQueue.global(qos: .userInitiated).async {
            let plan = try? Organizer.plan(settings: configuration)
            DispatchQueue.main.async { completion(plan) }
        }
    }

    // MARK: - Putting it back

    /// Walks every folder the app made for what it would take back out. Reads
    /// all of them, so it runs off the main thread like a sweep does.
    func findRestorable(completion: @escaping ([RestoreCandidate]) -> Void = { _ in }) {
        guard access.mayRead else { return completion([]) }
        restoreScanning = true
        let configuration = RestoreConfiguration(settings)

        inspectQueue.async { [weak self] in
            let found = Restorer.candidates(configuration: configuration)
            DispatchQueue.main.async {
                self?.restorable = found
                self?.restoreScanning = false
                completion(found)
            }
        }
    }

    func restore(_ selected: [RestoreCandidate], completion: @escaping (RestoreResult) -> Void) {
        guard !restoring, !selected.isEmpty else { return }
        restoring = true
        let configuration = RestoreConfiguration(settings)

        runQueue.async { [weak self] in
            let outcome = Restorer.apply(selected, configuration: configuration)
            DispatchQueue.main.async {
                self?.finishRestoring(outcome)
                completion(outcome)
            }
        }
    }

    private func finishRestoring(_ outcome: RestoreResult) {
        restoring = false
        lastError = outcome.errors.first
        remember(outcome.moved + outcome.emptied)

        for failure in outcome.errors {
            log.write("error: \(failure)")
        }

        guard !outcome.moved.isEmpty else { return }

        let done = Set(outcome.moved.map(\.name))
        restorable.removeAll { done.contains($0.name) }
        refreshUsage(force: true)
        invalidateScans()

        // A real restore pauses filing. The next sweep would put back exactly
        // what was just taken out, which is not an argument worth having with
        // your own downloads folder — so the app stops and says it has, and
        // starting again is a switch away.
        if !outcome.moved.allSatisfy(\.wasPreview), settings.isEnabled {
            settings.isEnabled = false
            log.write("filing paused after putting everything back")
        }

        let noun = outcome.movedCount == 1 ? "item" : "items"
        var summary = outcome.moved.allSatisfy(\.wasPreview)
            ? "Previewed putting \(outcome.movedCount) \(noun) back"
            : "Put \(outcome.movedCount) \(noun) back · filing paused"
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
        guard access.mayRead else {
            usage = nil
            snapshot = nil
            return
        }
        guard !measuring else { return }
        if !force, let usage, Date().timeIntervalSince(usage.measuredAt) < 30 { return }

        measuring = true
        let cap = measureInFull ? Int.max : FolderUsage.defaultCap
        let root = settings.downloadsURL
        let rules = settings.typeRules
        let configuration = RunConfiguration(settings)

        inspectQueue.async { [weak self] in
            let measured = FolderUsage.measure(root: root, cap: cap, typeRules: rules)
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

    /// Walks the folder without the cap, because someone asked what it
    /// actually comes to. Nothing here reads a file through — it is the same
    /// walk, only allowed to finish — but on a folder with hundreds of
    /// thousands of items it is slow, which is why it is asked for rather than
    /// done every time.
    func measureFolderInFull() {
        measureInFull = true
        refreshUsage(force: true)
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
        // A count of what a rule catches is about a folder that just changed.
        // Cleared rather than recounted: the pane asks when it is on screen,
        // and nothing else in the window reads it.
        ruleReport = RuleReport()
    }

    // MARK: - Duplicates

    /// Looks for files that exist more than once. Hashing every candidate is
    /// the slow part, so this runs off the main thread and the sheet waits.
    func findDuplicates(completion: @escaping ([DuplicateGroup]) -> Void = { _ in }) {
        guard access.mayRead else { return completion([]) }
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
        guard access.mayRead else { return completion([]) }
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
        // While the question has not been put, nobody probes. Reading the
        // folder is what raises the prompt, so `requestAccess` — which clears
        // this state first — is the only way in. Opening the window, checking
        // again and recovering from an error all go through here, and none of
        // them should be able to raise a system alert on their own.
        guard access != .notAsked else {
            completion?()
            return
        }

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
                // Remembered so the next launch knows a read is silent, and
                // forgotten again the moment it stops being true — a
                // permission withdrawn in System Settings puts the app back to
                // asking rather than to prompting out of nowhere.
                self?.settings.hasGrantedAccess = state == .granted
                completion?()
            }
        }
    }

    /// The way back from a refused prompt. macOS asks for a protected folder
    /// once and never again, so a "no" — or a prompt dismissed by accident —
    /// leaves the app with no way to ask a second time. Choosing the folder in
    /// an open panel is the second way in: picking it yourself is the same
    /// permission, granted by hand rather than by answering an alert, and it
    /// works without a trip through System Settings or a restart.
    ///
    /// Whatever is chosen becomes the watched folder, so the same button also
    /// answers the case where the old one has been moved or deleted.
    func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"
        panel.message = "Choose your Downloads folder to give Tideline access to it."
        panel.directoryURL = FileManager.default.fileExists(atPath: settings.downloadsURL.path)
            ? settings.downloadsURL
            : URL(fileURLWithPath: NSHomeDirectory())

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let chosen = panel.url else { return }

        if chosen.path != settings.downloadsPath {
            settings.downloadsPath = chosen.path
        }
        log.write("access granted by hand for \(chosen.path)")
        refreshAccess { [weak self] in
            self?.refreshUsage(force: true)
            self?.invalidateScans()
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
