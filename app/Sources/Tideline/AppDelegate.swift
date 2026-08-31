import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    /// The rows whose text changes while the app runs. Held rather than looked
    /// up by tag: the reviews and the update check now sit inside submenus, and
    /// `item(withTag:)` only ever searches one level.
    private var statusLine: NSMenuItem?
    private var usageLine: NSMenuItem?
    private var fileNowItem: NSMenuItem?
    private var enabledItem: NSMenuItem?
    private var helpMenuItem: NSMenuItem?
    private var updatesItem: NSMenuItem?

    private let settings = Settings.shared
    private let log = ActivityLog.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        let controller = Controller.shared
        controller.start()

        // Keep the menu bar title in step with what the app is doing.
        controller.$busy
            .combineLatest(controller.$access, settings.$isEnabled, settings.$hasStartedFiling)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in self?.updateStatusItemAppearance() }
            .store(in: &cancellables)

        // The size only appears beside the icon when asked for, but when it is
        // there it should follow the folder rather than the last time it was read.
        controller.$usage
            .combineLatest(settings.$showSizeInMenuBar)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateStatusItemAppearance() }
            .store(in: &cancellables)

        if settings.notifyOnMove {
            controller.requestNotificationPermission()
        }

        Updater.shared.start()

        if wasLaunchedAtLogin(notification) {
            NSApp.setActivationPolicy(.accessory)
            log.write("launched in the background — no window")
        } else {
            showWindow(nil)
            log.write("launched by hand — window opened")
        }
        settings.hasCompletedFirstRun = true
    }

    /// launchd starting the app at login marks the launch as not the default
    /// one; opening it from Finder, the Dock or Launchpad marks it as default.
    ///
    /// This used to read `XPC_SERVICE_NAME`, on the theory that only login
    /// items had one. Every Launch Services launch has one — a double-click
    /// included — so the test was true for every launch after the first, and
    /// the window stopped appearing when you opened the app. The key below is
    /// what the launch notification carries for exactly this question; it has
    /// no Swift name, so it is spelled out.
    private func wasLaunchedAtLogin(_ notification: Notification) -> Bool {
        let key = "NSApplicationLaunchIsDefaultLaunchKey"
        guard let isDefault = notification.userInfo?[key] as? Bool else { return false }
        return !isDefault
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    // MARK: - Window

    /// `⌘,` is a reflex on macOS and it should land somewhere that deserves the
    /// name — the rules, rather than wherever the window was last left.
    @objc func showSettings() {
        Controller.shared.reveal = .filing
        showWindow(nil)
    }

    @objc func showWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(rootView: MainView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Tideline"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            // The band under the titlebar already says the app's name, so the
            // titlebar itself does not say it a second time.
            window.titleVisibility = .hidden
            // The titlebar is transparent, so what shows through it is the
            // window's own background. Painting it the theme's chrome makes the
            // strip behind the traffic lights continue the header band rather
            // than sitting on a slab of system grey.
            window.backgroundColor = Theme.chromeNSColor
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 860, height: 620))
            window.contentMinSize = NSSize(width: 720, height: 520)
            window.center()
            self.window = window
        }

        Controller.shared.refreshLoginItem()
        Controller.shared.refreshAccess()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window drops the Dock icon; the app keeps filing in the background.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "tray.full",
            accessibilityDescription: "Tideline"
        )
        item.button?.image?.isTemplate = true
        item.menu = buildStatusMenu()
        statusItem = item
        updateStatusItemAppearance()
    }

    /// Three rows of state, the two things worth doing without the window, and
    /// then the reviews and the housekeeping folded into submenus. `badge` is
    /// what makes that possible — a count or a size sits on the trailing edge
    /// of a row, so a submenu can say what is inside it before it is opened.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Title card: which app this is, and which version, without opening the
        // window. The icon is the bundle's own, as the window's header is.
        let about = NSMenuItem(title: AppInfo.name, action: nil, keyEquivalent: "")
        about.image = Self.menuIcon
        about.badge = NSMenuItemBadge(string: AppInfo.version)
        about.isEnabled = false
        menu.addItem(about)

        // The state dot the window draws beside its headline, at menu size.
        let status = NSMenuItem(title: "Not run yet", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusLine = status

        // What the folder is holding, without opening the window for it.
        let usage = NSMenuItem(title: "Measuring…", action: nil, keyEquivalent: "")
        usage.isEnabled = false
        menu.addItem(usage)
        usageLine = usage

        menu.addItem(.separator())

        let fileNow = NSMenuItem(title: "File Downloads Now", action: #selector(runNow), keyEquivalent: "r")
        fileNow.target = self
        menu.addItem(fileNow)
        fileNowItem = fileNow

        // The window is Overview, Reclaim space and the activity log as much as
        // it is settings, so opening it says so and sits beside the sweep.
        menu.addItem(withTitle: "Open Tideline", action: #selector(showWindow(_:)), keyEquivalent: "o")
            .target = self

        let enabled = NSMenuItem(title: "Filing Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        menu.addItem(enabled)
        enabledItem = enabled

        menu.addItem(.separator())

        // The three reviews under the one question they answer. No figures:
        // the menu never scans, so anything it quoted would be as old as the
        // last time the window was open, and a stale number is worse than none.
        let reclaim = NSMenuItem(title: "Reclaim space", action: nil, keyEquivalent: "")
        let reclaimMenu = NSMenu()

        reclaimMenu.addItem(withTitle: "Duplicates", action: #selector(reviewDuplicates), keyEquivalent: "")
            .target = self
        reclaimMenu.addItem(withTitle: "Large files", action: #selector(reviewLargeFiles), keyEquivalent: "")
            .target = self
        reclaimMenu.addItem(withTitle: "Old dated folders", action: #selector(reviewCleanup), keyEquivalent: "")
            .target = self
        reclaimMenu.addItem(.separator())
        reclaimMenu.addItem(withTitle: "Review All in Tideline…", action: #selector(reviewAll), keyEquivalent: "")
            .target = self

        reclaim.submenu = reclaimMenu
        menu.addItem(reclaim)

        // Beside the reviews rather than beside the sweep: like them it finds
        // things and asks, and unlike the sweep it never acts on its own.
        menu.addItem(withTitle: "Move Out…", action: #selector(collect), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        menu.addItem(withTitle: "Open Downloads Folder", action: #selector(openDownloads), keyEquivalent: "d")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self

        // Everything that is about the app rather than the folder. It carries an
        // updates badge when there is one, which is the only reason to look.
        let help = NSMenuItem(title: "Help & Updates", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu()

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        helpMenu.addItem(updates)
        updatesItem = updates

        helpMenu.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
            .target = self
        helpMenu.addItem(withTitle: "Tideline on GitHub", action: #selector(openRepository), keyEquivalent: "")
            .target = self

        help.submenu = helpMenu
        menu.addItem(help)
        helpMenuItem = help

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Tideline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }

    /// The bundle's own icon at menu size. AppKit will not shrink a 512pt icon
    /// for us, so it is copied and resized rather than handed over whole.
    private static var menuIcon: NSImage? {
        guard let icon = AppIconImage.icon.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// The same dot, in the same colours, as the window's headline — a menu row
    /// has no room for a sentence explaining that filing is paused.
    private static func dot(_ color: Color) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(color)]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }

    private func updateStatusItemAppearance() {
        let active = settings.isEnabled && settings.hasStartedFiling
        let symbol = active ? "tray.full" : "tray"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tideline")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.appearsDisabled = !active

        if settings.showSizeInMenuBar, let usage = Controller.shared.usage {
            statusItem?.button?.title = " " + FolderUsage.bytes.string(fromByteCount: usage.totalBytes)
            statusItem?.button?.imagePosition = .imageLeading
        } else {
            statusItem?.button?.title = ""
            statusItem?.button?.imagePosition = .imageOnly
        }
    }

    /// In preview mode this files nothing; it opens the window on the sheet
    /// that lists what a sweep would have done.
    @objc private func runNow() {
        // Nothing has been agreed to yet, so this asks in the window rather
        // than filing a folder nobody has said it may touch.
        guard settings.hasStartedFiling else {
            showWindow(nil)
            DispatchQueue.main.async {
                Controller.shared.askingToStart = true
            }
            return
        }
        guard settings.dryRun else {
            Controller.shared.run(trigger: .manual)
            return
        }
        showWindow(nil)
        DispatchQueue.main.async {
            Controller.shared.run(trigger: .manual, showingPlan: true)
        }
    }

    @objc private func toggleEnabled() {
        guard settings.hasStartedFiling else {
            showWindow(nil)
            DispatchQueue.main.async {
                Controller.shared.askingToStart = true
            }
            return
        }
        settings.isEnabled.toggle()
    }

    /// Opens the window on the review sheet. The menu never clears anything by
    /// itself — the sheet is the only place a folder is agreed to.
    @objc private func reviewCleanup() {
        showWindow(nil)
        // A turn later, so the window is on screen before the sheet is asked for.
        DispatchQueue.main.async {
            Controller.shared.reviewingCleanup = true
        }
    }

    /// Same shape as reviewing old folders: the window comes up on the sheet,
    /// because nothing is trashed anywhere the sheet is not.
    @objc private func reviewDuplicates() {
        showWindow(nil)
        DispatchQueue.main.async {
            Controller.shared.reviewingDuplicates = true
        }
    }

    /// Same shape again: the window comes up on the sheet, because nothing is
    /// trashed anywhere the sheet is not.
    @objc private func reviewLargeFiles() {
        showWindow(nil)
        DispatchQueue.main.async {
            Controller.shared.reviewingLargeFiles = true
        }
    }

    /// Same shape as the reviews: the window comes up on the sheet, because
    /// nothing leaves the watched folder anywhere the sheet is not.
    @objc private func collect() {
        showWindow(nil)
        DispatchQueue.main.async {
            Controller.shared.reviewingCollect = true
        }
    }

    @objc private func openDownloads() {
        Controller.shared.revealDownloadsFolder()
    }

    /// Opens Reclaim space itself rather than one of its sheets. This is the
    /// only one of the four that starts the scans, which is why the submenu's
    /// figures can be older than the folder.
    @objc private func reviewAll() {
        Controller.shared.reveal = .reclaim
        showWindow(nil)
    }

    @objc private func sendFeedback() {
        NSWorkspace.shared.open(AppInfo.newIssue)
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(AppInfo.repository)
    }

    /// Opens the window on the update section and looks straight away, so the
    /// answer arrives where it can be acted on.
    @objc private func checkForUpdates() {
        showWindow(nil)
        DispatchQueue.main.async {
            Updater.shared.reveal = true
            Updater.shared.check(userInitiated: true)
        }
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tideline",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Tideline", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Tideline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

@MainActor
extension AppDelegate: NSMenuItemValidation {
    /// Reviewing is only meaningful once an age has been picked; with clearing
    /// set to Never there is nothing the sheet could offer.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(reviewCleanup) else { return true }
        return settings.cleanupAfterDays > 0
    }
}

@MainActor
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let controller = Controller.shared
        controller.refreshUsage()

        statusLine?.title = headline(for: controller)
        statusLine?.image = Self.dot(dotColour(for: controller))

        // The folder's name carries its size on the trailing edge, so the row
        // reads as a label and a figure rather than as a sentence.
        let folder = settings.downloadsURL.lastPathComponent
        if let usage = controller.usage {
            usageLine?.title = folder
            usageLine?.badge = NSMenuItemBadge(string: usage.totalDescription)
        } else {
            usageLine?.title = "Measuring \(folder)…"
            usageLine?.badge = nil
        }

        enabledItem?.state = settings.isEnabled && settings.hasStartedFiling ? .on : .off

        // Preview mode never files anything, so the item that would say it does
        // says what it actually does instead. Before filing has been agreed to,
        // neither is on offer: the row asks the question instead.
        if !settings.hasStartedFiling {
            fileNowItem?.title = "Start Filing…"
        } else {
            fileNowItem?.title = settings.dryRun ? "Preview a Sweep…" : "File Downloads Now"
        }

        // Says what the last check found, rather than making you open the window
        // to learn there is nothing to do.
        let updater = Updater.shared
        updatesItem?.title = updater.pending.map { "Update to \($0.version)…" } ?? "Check for Updates…"
        helpMenuItem?.badge = updater.pending == nil ? nil : NSMenuItemBadge.updates(count: 1)
    }

    /// What the window's headline says, in a row's worth of words.
    private func headline(for controller: Controller) -> String {
        switch controller.access {
        case .denied: return "No access to the Downloads folder"
        case .missing: return "Watched folder is missing"
        default: break
        }
        if !settings.hasStartedFiling { return "Not filing yet" }
        if controller.busy { return "Filing…" }
        return settings.isEnabled ? controller.lastRunSummary : "Filing paused"
    }

    /// The same three meanings the window's dot carries: a fault, something
    /// running, and everything as it should be.
    private func dotColour(for controller: Controller) -> Color {
        if controller.access == .denied || controller.access == .missing { return Theme.danger }
        if !settings.isEnabled || !settings.hasStartedFiling { return Theme.muted }
        return controller.busy ? Theme.accent : Theme.success
    }

}
