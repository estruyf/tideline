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

    private init() {
        history = log.loadHistory()
        lastRunAt = UserDefaults.standard.object(forKey: "lastRunAt") as? Date
        if let lastRunAt {
            lastRunSummary = "Last checked \(Self.relative.localizedString(for: lastRunAt, relativeTo: Date()))"
        }
        loginItemEnabled = Self.loginItemStatus == .enabled

        NotificationCenter.default.publisher(for: .settingsChanged)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reconfigure() }
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

    func run(trigger: RunTrigger) {
        guard !isRunning else { return }
        guard settings.isEnabled || trigger == .manual else { return }

        isRunning = true
        busy = true
        let configuration = RunConfiguration(settings)
        let notify = settings.notifyOnMove

        runQueue.async { [weak self] in
            let outcome: Result<RunResult, Error>
            do {
                outcome = .success(try Organizer.run(settings: configuration))
            } catch {
                outcome = .failure(error)
            }

            DispatchQueue.main.async {
                self?.finish(outcome, trigger: trigger, notify: notify)
            }
        }
    }

    private func finish(_ outcome: Result<RunResult, Error>, trigger: RunTrigger, notify: Bool) {
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

            if !result.moves.isEmpty {
                history.insert(contentsOf: result.moves.reversed(), at: 0)
                history = Array(history.prefix(300))
                log.save(history)

                for move in result.moves {
                    let verb = move.wasPreview ? "would move" : "moved"
                    log.write("\(verb) \(move.name) -> \(move.folder)/")
                }

                if notify, !configurationIsPreview(result) {
                    postNotification(for: result)
                }
            }

            let noun = result.movedCount == 1 ? "item" : "items"
            lastRunSummary = result.movedCount == 0
                ? "Nothing to file — checked \(result.inspected) \(result.inspected == 1 ? "item" : "items")"
                : "Filed \(result.movedCount) \(noun)"

            for failure in result.errors {
                log.write("error: \(failure)")
            }
        }
    }

    private func configurationIsPreview(_ result: RunResult) -> Bool {
        result.moves.allSatisfy { $0.wasPreview }
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
