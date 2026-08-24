import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        let controller = Controller.shared
        controller.start()

        // Keep the menu bar title in step with what the app is doing.
        controller.$busy
            .combineLatest(controller.$access, settings.$isEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateStatusItemAppearance() }
            .store(in: &cancellables)

        if settings.notifyOnMove {
            controller.requestNotificationPermission()
        }

        Updater.shared.start()

        if !settings.hasCompletedFirstRun || !wasLaunchedAtLogin {
            showWindow(nil)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        settings.hasCompletedFirstRun = true
    }

    /// launchd sets XPC_SERVICE_NAME for login items; Finder launches do not.
    private var wasLaunchedAtLogin: Bool {
        let value = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? ""
        return !value.isEmpty && value != "0"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    // MARK: - Window

    @objc func showWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let hosting = NSHostingController(rootView: MainView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Tideline"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 580, height: 640))
            window.contentMinSize = NSSize(width: 520, height: 460)
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

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Title card: which app this is, and which version, without opening the window.
        let about = NSMenuItem(title: AppInfo.nameAndVersion, action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        menu.addItem(.separator())

        let status = NSMenuItem(title: "Not run yet", action: nil, keyEquivalent: "")
        status.tag = 1
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        menu.addItem(withTitle: "File Downloads Now", action: #selector(runNow), keyEquivalent: "r")
            .target = self

        let enabled = NSMenuItem(title: "Filing Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.tag = 2
        enabled.target = self
        menu.addItem(enabled)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Review Old Folders…", action: #selector(reviewCleanup), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        menu.addItem(withTitle: "Open Downloads Folder", action: #selector(openDownloads), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showWindow(_:)), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
            .target = self

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.tag = 3
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Tideline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }

    private func updateStatusItemAppearance() {
        let symbol = settings.isEnabled ? "tray.full" : "tray"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tideline")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.appearsDisabled = !settings.isEnabled
    }

    @objc private func runNow() {
        Controller.shared.run(trigger: .manual)
    }

    @objc private func toggleEnabled() {
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

    @objc private func openDownloads() {
        Controller.shared.revealDownloadsFolder()
    }

    @objc private func sendFeedback() {
        NSWorkspace.shared.open(AppInfo.newIssue)
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
        appMenu.addItem(withTitle: "Settings…", action: #selector(showWindow(_:)), keyEquivalent: ",").target = self
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

        if let status = menu.item(withTag: 1) {
            switch controller.access {
            case .denied:
                status.title = "No access to the Downloads folder"
            case .missing:
                status.title = "Watched folder is missing"
            default:
                status.title = controller.busy ? "Filing…" : controller.lastRunSummary
            }
        }

        if let enabled = menu.item(withTag: 2) {
            enabled.state = settings.isEnabled ? .on : .off
        }

        // Says what the last check found, rather than making you open the window
        // to learn there is nothing to do.
        if let updates = menu.item(withTag: 3) {
            let updater = Updater.shared
            updates.title = updater.pending.map { "Update to \($0.version)…" } ?? "Check for Updates…"
        }
    }
}
