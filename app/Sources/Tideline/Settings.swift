import Combine
import Foundation

extension Notification.Name {
    /// Posted whenever a setting that affects scheduling or filing changes.
    static let settingsChanged = Notification.Name("be.eliostruyf.Tideline.settingsChanged")
}

enum FolderFormat: String, CaseIterable, Identifiable {
    case daily
    case monthly

    var id: String { rawValue }

    var dateFormat: String {
        switch self {
        case .daily: return "yyyy-MM-dd"
        case .monthly: return "yyyy-MM"
        }
    }

    var label: String {
        switch self {
        case .daily: return "One folder per day"
        case .monthly: return "One folder per month"
        }
    }

    var example: String {
        switch self {
        case .daily: return "2026-08-19"
        case .monthly: return "2026-08"
        }
    }
}

enum DateBasis: String, CaseIterable, Identifiable {
    /// Finder's "Date Added" — when the item arrived in the folder it sits in now.
    case added
    case created
    case modified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: return "Date added to the folder"
        case .created: return "Date the file was created"
        case .modified: return "Date last modified"
        }
    }

    var explanation: String {
        switch self {
        case .added: return "The day the file arrived in the folder, even when it was made earlier — an AirDropped photo keeps the day it was shot as its creation date."
        case .created: return "The day the file itself was created, which for an AirDrop or a copy can pre-date its arrival."
        case .modified: return "The day the file was last written to. Editing an old file re-files it."
        }
    }
}

/// Every user-facing preference, backed by UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    static let defaultSkipNames = ["Inbox", "Screenshots"]

    private enum Key {
        static let isEnabled = "isEnabled"
        static let downloadsPath = "downloadsPath"
        static let keepRecentDays = "keepRecentDays"
        static let folderFormat = "folderFormat"
        static let dateBasis = "dateBasis"
        static let watchFolder = "watchFolder"
        static let dailyRunEnabled = "dailyRunEnabled"
        static let dailyRunHour = "dailyRunHour"
        static let dailyRunMinute = "dailyRunMinute"
        static let runOnLaunch = "runOnLaunch"
        static let dryRun = "dryRun"
        static let includeFolders = "includeFolders"
        static let notifyOnMove = "notifyOnMove"
        static let skipNames = "skipNames"
        static let rules = "rules"
        static let collectDestinations = "collectDestinations"
        static let lastCollectSearch = "lastCollectSearch"
        static let typeRules = "typeRules"
        static let cleanupAfterDays = "cleanupAfterDays"
        static let cleanupOnSchedule = "cleanupOnSchedule"
        static let cleanupKeepNewest = "cleanupKeepNewest"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
        static let hasStartedFiling = "hasStartedFiling"
        static let hasGrantedAccess = "hasGrantedAccess"
        static let hasAnsweredLoginSuggestion = "hasAnsweredLoginSuggestion"
        static let duplicateRestoreNames = "duplicateRestoreNames"
        static let largeFileThresholdMB = "largeFileThresholdMB"
        static let showSizeInMenuBar = "showSizeInMenuBar"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let notifyOnUpdate = "notifyOnUpdate"
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
        static let skippedUpdateVersion = "skippedUpdateVersion"
        static let notifiedUpdateVersion = "notifiedUpdateVersion"
    }

    private init() {
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.keepRecentDays: 0,
            Key.folderFormat: FolderFormat.daily.rawValue,
            Key.dateBasis: DateBasis.added.rawValue,
            Key.watchFolder: true,
            Key.dailyRunEnabled: true,
            Key.dailyRunHour: 0,
            Key.dailyRunMinute: 5,
            Key.runOnLaunch: true,
            Key.dryRun: false,
            Key.includeFolders: true,
            Key.notifyOnMove: false,
            Key.skipNames: Settings.defaultSkipNames,
            Key.cleanupAfterDays: 90,
            Key.cleanupOnSchedule: false,
            Key.cleanupKeepNewest: 3,
            Key.duplicateRestoreNames: true,
            Key.largeFileThresholdMB: 100,
            Key.showSizeInMenuBar: false,
            Key.automaticUpdateChecks: true,
            Key.notifyOnUpdate: true,
        ])

        isEnabled = defaults.bool(forKey: Key.isEnabled)
        downloadsPath = defaults.string(forKey: Key.downloadsPath) ?? Settings.defaultDownloadsPath
        keepRecentDays = defaults.integer(forKey: Key.keepRecentDays)
        folderFormat = FolderFormat(rawValue: defaults.string(forKey: Key.folderFormat) ?? "") ?? .daily
        dateBasis = DateBasis(rawValue: defaults.string(forKey: Key.dateBasis) ?? "") ?? .added
        watchFolder = defaults.bool(forKey: Key.watchFolder)
        dailyRunEnabled = defaults.bool(forKey: Key.dailyRunEnabled)
        dailyRunHour = defaults.integer(forKey: Key.dailyRunHour)
        dailyRunMinute = defaults.integer(forKey: Key.dailyRunMinute)
        runOnLaunch = defaults.bool(forKey: Key.runOnLaunch)
        dryRun = defaults.bool(forKey: Key.dryRun)
        includeFolders = defaults.bool(forKey: Key.includeFolders)
        notifyOnMove = defaults.bool(forKey: Key.notifyOnMove)
        skipNames = defaults.stringArray(forKey: Key.skipNames) ?? Settings.defaultSkipNames
        rules = Settings.loadRules(from: defaults)
        collectDestinations = Settings.loadDestinations(from: defaults)
        lastCollectSearch = Settings.loadTests(from: defaults)
        typeRules = Settings.loadTypeRules(from: defaults)
        cleanupAfterDays = defaults.integer(forKey: Key.cleanupAfterDays)
        cleanupOnSchedule = defaults.bool(forKey: Key.cleanupOnSchedule)
        cleanupKeepNewest = defaults.integer(forKey: Key.cleanupKeepNewest)
        duplicateRestoreNames = defaults.bool(forKey: Key.duplicateRestoreNames)
        largeFileThresholdMB = defaults.integer(forKey: Key.largeFileThresholdMB)
        showSizeInMenuBar = defaults.bool(forKey: Key.showSizeInMenuBar)
        hasAnsweredLoginSuggestion = defaults.bool(forKey: Key.hasAnsweredLoginSuggestion)
        hasStartedFiling = Settings.loadStartedFiling(from: defaults)
        // An install that has been filing plainly had access to file with.
        hasGrantedAccess = defaults.object(forKey: Key.hasGrantedAccess) as? Bool
            ?? defaults.bool(forKey: Key.hasCompletedFirstRun)
        automaticUpdateChecks = defaults.bool(forKey: Key.automaticUpdateChecks)
        notifyOnUpdate = defaults.bool(forKey: Key.notifyOnUpdate)
    }

    /// Whether filing has ever been agreed to. A fresh install has not: the
    /// window asks before the first sweep, because an app that rearranges a
    /// folder the moment it opens has taken a decision that was not its to
    /// take. An install that predates the question is treated as having
    /// answered it — it has been filing for weeks, and an update is no reason
    /// to stop and ask.
    private static func loadStartedFiling(from defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: Key.hasStartedFiling) != nil {
            return defaults.bool(forKey: Key.hasStartedFiling)
        }

        let upgraded = defaults.bool(forKey: Key.hasCompletedFirstRun)
        defaults.set(upgraded, forKey: Key.hasStartedFiling)
        return upgraded
    }

    static var defaultDownloadsPath: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    // MARK: - Stored preferences

    @Published var isEnabled: Bool { didSet { store(isEnabled, Key.isEnabled) } }

    /// Set once someone has said yes to filing. Nothing is swept until they
    /// have — not on launch, not on a folder change, not on the daily timer.
    /// It goes through `store` because the answer is what the watcher and the
    /// timer are waiting for.
    @Published var hasStartedFiling: Bool { didSet { store(hasStartedFiling, Key.hasStartedFiling) } }

    /// Set once macOS has actually let the app read the folder. It is the only
    /// thing that makes reading it at launch safe: there is no way to ask for
    /// access except by reading, so a read on an install that was never granted
    /// anything is a permission prompt landing over a window that has not
    /// introduced itself yet. Somewhere this is true, the read is silent.
    /// Kept out of `store`: it changes nothing about the schedule.
    @Published var hasGrantedAccess: Bool {
        didSet { defaults.set(hasGrantedAccess, forKey: Key.hasGrantedAccess) }
    }

    @Published var downloadsPath: String { didSet { store(downloadsPath, Key.downloadsPath) } }
    @Published var keepRecentDays: Int { didSet { store(keepRecentDays, Key.keepRecentDays) } }
    @Published var folderFormat: FolderFormat { didSet { store(folderFormat.rawValue, Key.folderFormat) } }
    @Published var dateBasis: DateBasis { didSet { store(dateBasis.rawValue, Key.dateBasis) } }
    @Published var watchFolder: Bool { didSet { store(watchFolder, Key.watchFolder) } }
    @Published var dailyRunEnabled: Bool { didSet { store(dailyRunEnabled, Key.dailyRunEnabled) } }
    @Published var dailyRunHour: Int { didSet { store(dailyRunHour, Key.dailyRunHour) } }
    @Published var dailyRunMinute: Int { didSet { store(dailyRunMinute, Key.dailyRunMinute) } }
    @Published var runOnLaunch: Bool { didSet { store(runOnLaunch, Key.runOnLaunch) } }
    @Published var dryRun: Bool { didSet { store(dryRun, Key.dryRun) } }
    @Published var includeFolders: Bool { didSet { store(includeFolders, Key.includeFolders) } }
    @Published var notifyOnMove: Bool { didSet { store(notifyOnMove, Key.notifyOnMove) } }
    @Published var skipNames: [String] { didSet { store(skipNames, Key.skipNames) } }

    /// Folders that claim files by what they are called or where they came
    /// from, tried before the type rules and in this order. Nothing is shipped:
    /// a rule only exists because someone wrote it.
    @Published var rules: [Rule] { didSet { storeRules() } }

    /// Places to collect into, outside the watched folder. Each is a bookmark
    /// and a template rather than a path, so a saved place survives the folder
    /// above it being renamed.
    @Published var collectDestinations: [CollectDestination] { didSet { storeDestinations() } }

    /// The last search typed by hand, offered as a starting point next time.
    /// One search, not a history: the point is to pick up where you left off.
    @Published var lastCollectSearch: [RuleTest] { didSet { storeLastSearch() } }

    /// Folders that claim files by extension — `Installers`, `Images` — instead
    /// of letting the date decide. Every rule ships switched off.
    @Published var typeRules: [TypeRule] { didSet { storeTypeRules() } }

    /// How old a dated folder has to be before it may be cleared. `0` means never.
    /// Nothing is ever removed on this setting alone — clearing runs by hand,
    /// unless `cleanupOnSchedule` is switched on as well.
    @Published var cleanupAfterDays: Int { didSet { store(cleanupAfterDays, Key.cleanupAfterDays) } }
    @Published var cleanupOnSchedule: Bool { didSet { store(cleanupOnSchedule, Key.cleanupOnSchedule) } }
    /// The newest folders are held back whatever their age.
    @Published var cleanupKeepNewest: Int { didSet { store(cleanupKeepNewest, Key.cleanupKeepNewest) } }

    /// After the other copies of a file go to the Trash, the one left standing
    /// can have its plain name back — `artifact-1.zip` becomes `artifact.zip`,
    /// but only where that name is free. Kept out of `store`: it changes
    /// nothing about filing, so it need not rebuild the watcher.
    @Published var duplicateRestoreNames: Bool {
        didSet { defaults.set(duplicateRestoreNames, forKey: Key.duplicateRestoreNames) }
    }

    /// How big a file has to be before the big-file review lists it, in
    /// megabytes. Only ever decides what is *shown* — nothing is trashed on
    /// this setting, or on any schedule, without the sheet saying so. Kept out
    /// of `store`: it changes nothing about filing.
    @Published var largeFileThresholdMB: Int {
        didSet { defaults.set(largeFileThresholdMB, forKey: Key.largeFileThresholdMB) }
    }

    /// The sizes the review offers, in megabytes.
    static let largeFileThresholds = [50, 100, 250, 500, 1_000, 5_000]

    /// Puts the folder's size next to the menu bar icon, rather than only in
    /// the menu itself.
    @Published var showSizeInMenuBar: Bool {
        didSet { defaults.set(showSizeInMenuBar, forKey: Key.showSizeInMenuBar) }
    }

    /// Set once the user has either accepted or waved away the open-at-login suggestion.
    /// Kept out of `store` so answering it never triggers a reconfigure.
    /// Set the first time the login switch is touched. Nothing reads it now
    /// that the switch is on Overview rather than behind a first-run card, but
    /// it is kept so an upgrade never re-runs an onboarding that was answered.
    @Published var hasAnsweredLoginSuggestion: Bool {
        didSet { defaults.set(hasAnsweredLoginSuggestion, forKey: Key.hasAnsweredLoginSuggestion) }
    }

    /// Checked once a day at most, and never installs anything on its own —
    /// finding an update only offers it. Kept out of `store` so switching it
    /// never triggers a reconfigure of the watcher and the timer.
    @Published var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks) }
    }

    /// Whether a background check that finds a new version says so in
    /// Notification Centre. On by default: an update people never hear about is
    /// the same as no update. It is still only ever a notice — nothing is
    /// downloaded or installed by it — and it is never a reason to raise a
    /// permission prompt. Kept out of `store` for the same reason the setting
    /// above is: updates have nothing to do with the sweep schedule.
    @Published var notifyOnUpdate: Bool {
        didSet { defaults.set(notifyOnUpdate, forKey: Key.notifyOnUpdate) }
    }

    /// When the last check for updates finished.
    var lastUpdateCheckAt: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheckAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheckAt) }
    }

    /// A version the user waved away; a newer one is still offered.
    var skippedUpdateVersion: String? {
        get { defaults.string(forKey: Key.skippedUpdateVersion) }
        set { defaults.set(newValue, forKey: Key.skippedUpdateVersion) }
    }

    /// The last version a notification went out for. Checks run every day and a
    /// release sits there for weeks, so without this the same news would arrive
    /// every morning until it is installed.
    var notifiedUpdateVersion: String? {
        get { defaults.string(forKey: Key.notifiedUpdateVersion) }
        set { defaults.set(newValue, forKey: Key.notifiedUpdateVersion) }
    }

    /// Set once the very first launch has shown the welcome screen.
    var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstRun) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstRun) }
    }

    // MARK: - Derived

    var downloadsURL: URL { URL(fileURLWithPath: downloadsPath).standardizedFileURL }

    /// The time of day the scheduled sweep fires, as `Date` for a SwiftUI DatePicker.
    var dailyRunTime: Date {
        get {
            var components = DateComponents()
            components.hour = dailyRunHour
            components.minute = dailyRunMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyRunHour = components.hour ?? 0
            dailyRunMinute = components.minute ?? 5
        }
    }

    func resetToDefaults() {
        keepRecentDays = 0
        folderFormat = .daily
        dateBasis = .added
        watchFolder = true
        dailyRunEnabled = true
        dailyRunHour = 0
        dailyRunMinute = 5
        runOnLaunch = true
        dryRun = false
        includeFolders = true
        skipNames = Settings.defaultSkipNames
        rules = []
        collectDestinations = []
        lastCollectSearch = []
        typeRules = TypeRule.builtIns
        downloadsPath = Settings.defaultDownloadsPath
        cleanupAfterDays = 90
        cleanupOnSchedule = false
        cleanupKeepNewest = 3
        duplicateRestoreNames = true
        largeFileThresholdMB = 100
        showSizeInMenuBar = false
        automaticUpdateChecks = true
        notifyOnUpdate = true
    }

    /// Stored as JSON rather than a plist array, so the shape can grow without
    /// a migration. A list that fails to decode falls back to the shipped rules,
    /// all of which are off — filing carries on by date, which is what it did
    /// before and never the destructive answer.
    /// Stored as JSON, like the type rules. A list that fails to decode falls
    /// back to none at all: filing carries on by date and by type, which is
    /// what it did before the rule was written and never the destructive answer.
    private static func loadRules(from defaults: UserDefaults) -> [Rule] {
        guard
            let data = defaults.data(forKey: Key.rules),
            let stored = try? JSONDecoder().decode([Rule].self, from: data)
        else { return [] }

        return stored
    }

    private func storeRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        store(data, Key.rules)
    }

    /// A saved place that fails to decode is dropped rather than guessed at: a
    /// destination is a folder the app is about to write into, and half of one
    /// is not something to act on.
    private static func loadDestinations(from defaults: UserDefaults) -> [CollectDestination] {
        guard
            let data = defaults.data(forKey: Key.collectDestinations),
            let stored = try? JSONDecoder().decode([CollectDestination].self, from: data)
        else { return [] }

        return stored.filter { !$0.bookmark.isEmpty }
    }

    private func storeDestinations() {
        guard let data = try? JSONEncoder().encode(collectDestinations) else { return }
        store(data, Key.collectDestinations)
    }

    private static func loadTests(from defaults: UserDefaults) -> [RuleTest] {
        guard
            let data = defaults.data(forKey: Key.lastCollectSearch),
            let stored = try? JSONDecoder().decode([RuleTest].self, from: data)
        else { return [] }
        return stored
    }

    private func storeLastSearch() {
        guard let data = try? JSONEncoder().encode(lastCollectSearch) else { return }
        store(data, Key.lastCollectSearch)
    }

    private static func loadTypeRules(from defaults: UserDefaults) -> [TypeRule] {
        guard
            let data = defaults.data(forKey: Key.typeRules),
            let stored = try? JSONDecoder().decode([TypeRule].self, from: data)
        else { return TypeRule.builtIns }

        return TypeRule.merged(with: stored)
    }

    private func storeTypeRules() {
        guard let data = try? JSONEncoder().encode(typeRules) else { return }
        store(data, Key.typeRules)
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
