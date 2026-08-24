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
        static let cleanupAfterDays = "cleanupAfterDays"
        static let cleanupOnSchedule = "cleanupOnSchedule"
        static let cleanupKeepNewest = "cleanupKeepNewest"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
        static let hasAnsweredLoginSuggestion = "hasAnsweredLoginSuggestion"
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
        cleanupAfterDays = defaults.integer(forKey: Key.cleanupAfterDays)
        cleanupOnSchedule = defaults.bool(forKey: Key.cleanupOnSchedule)
        cleanupKeepNewest = defaults.integer(forKey: Key.cleanupKeepNewest)
        hasAnsweredLoginSuggestion = defaults.bool(forKey: Key.hasAnsweredLoginSuggestion)
    }

    static var defaultDownloadsPath: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
    }

    // MARK: - Stored preferences

    @Published var isEnabled: Bool { didSet { store(isEnabled, Key.isEnabled) } }
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

    /// How old a dated folder has to be before it may be cleared. `0` means never.
    /// Nothing is ever removed on this setting alone — clearing runs by hand,
    /// unless `cleanupOnSchedule` is switched on as well.
    @Published var cleanupAfterDays: Int { didSet { store(cleanupAfterDays, Key.cleanupAfterDays) } }
    @Published var cleanupOnSchedule: Bool { didSet { store(cleanupOnSchedule, Key.cleanupOnSchedule) } }
    /// The newest folders are held back whatever their age.
    @Published var cleanupKeepNewest: Int { didSet { store(cleanupKeepNewest, Key.cleanupKeepNewest) } }

    /// Set once the user has either accepted or waved away the open-at-login suggestion.
    /// Kept out of `store` so answering it never triggers a reconfigure.
    @Published var hasAnsweredLoginSuggestion: Bool {
        didSet { defaults.set(hasAnsweredLoginSuggestion, forKey: Key.hasAnsweredLoginSuggestion) }
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
        downloadsPath = Settings.defaultDownloadsPath
        cleanupAfterDays = 90
        cleanupOnSchedule = false
        cleanupKeepNewest = 3
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
