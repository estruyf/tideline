import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var updater = Updater.shared

    @State private var showUninstall = false
    @State private var tab: MainTab = .status

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            // Losing access stops everything, so it is said once above the tabs
            // rather than on a tab you might not be looking at.
            if !controller.access.isUsable {
                Divider()
                AccessBanner()
            }

            Divider()
            TabStrip(selection: $tab)
                .background(.background)
            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 460)
        .sheet(isPresented: $showUninstall) {
            UninstallView(isPresented: $showUninstall)
        }
        .sheet(isPresented: $controller.reviewingCleanup) {
            CleanupView(isPresented: $controller.reviewingCleanup)
        }
        .onChange(of: updater.reveal) { reveal in
            // "Check for Updates…" in the menu bar lands on the section that
            // shows what the check found.
            if reveal {
                tab = .general
                updater.reveal = false
            }
        }
        .onChange(of: controller.reviewingCleanup) { reviewing in
            // Asked for from the menu bar, so dismissing the sheet leaves you on
            // the tab the sheet came from rather than wherever you last were.
            if reviewing { tab = .clearing }
        }
        .onAppear {
            controller.refreshLoginItem()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .status: StatusTab()
        case .schedule: ScheduleTab()
        case .filing: FilingTab()
        case .clearing: ClearingTab()
        case .general: GeneralTab(showUninstall: $showUninstall)
        }
    }
}

// MARK: - Status

private struct StatusTab: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            if showLoginSuggestion {
                Section { LoginSuggestionCard() }
            }

            // Only ever there when there is something to say about an update.
            if updater.hasNews {
                Section { UpdateBanner() }
            }

            Section {
                StatusRow()

                // Nothing else on this tab matters if the app is not running,
                // so the switch that decides that sits with the status.
                Toggle(isOn: Binding(
                    get: { controller.loginItemEnabled },
                    set: { controller.setLoginItem($0) }
                )) {
                    Text("Open at login")
                    Text("Starts in the background with no window and no Dock icon.")
                }
            } header: {
                Text("Status")
            }

            Section {
                ActivitySection()
            } header: {
                Text("Recent activity")
            }
        }
        .formStyle(.grouped)
    }

    /// Nudge shown until the user either opts in or waves it away once.
    private var showLoginSuggestion: Bool {
        !settings.hasAnsweredLoginSuggestion && !controller.loginItemEnabled
    }
}

// MARK: - Schedule

private struct ScheduleTab: View {
    var body: some View {
        Form {
            Section {
                ScheduleSection()
            } header: {
                Text("When it runs")
            } footer: {
                Text("A sweep is cheap — nothing moves unless a file is older than the window set under Filing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Filing

private struct FilingTab: View {
    var body: some View {
        Form {
            Section {
                RulesSection()
            } header: {
                Text("What gets filed")
            }

            Section {
                SkipListSection()
            } header: {
                Text("Never touch these")
            } footer: {
                Text("Exact names, or patterns such as *.dmg. Partial downloads, hidden files and the dated folders themselves are always left alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clearing

private struct ClearingTab: View {
    var body: some View {
        Form {
            Section {
                CleanupSection()
            } header: {
                Text("Clearing out")
            } footer: {
                Text("Only the dated folders Tideline made itself are ever cleared, and they go to the Trash. Loose files and folders you made yourself are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @Binding var showUninstall: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Notify me when files are filed", isOn: $settings.notifyOnMove)
                    .onChange(of: settings.notifyOnMove) { newValue in
                        if newValue { controller.requestNotificationPermission() }
                    }

                HStack {
                    Button("Open Log File") { controller.openLogFile() }
                    Button("Open Downloads Folder") { controller.revealDownloadsFolder() }
                    Spacer()
                    Button("Uninstall…") { showUninstall = true }
                }
            } header: {
                Text("Other")
            }

            Section {
                UpdateSection()
            } header: {
                Text("Updates")
            }

            Section {
                AboutSection()
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Open at login

private struct LoginSuggestionCard: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Have Tideline open at login", systemImage: "power")
                .font(.headline)

            Text("Filing only happens while Tideline is running. Started at login it comes up in the background — no window, no Dock icon — and keeps the folder tidy on its own.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open at Login") {
                    withAnimation(.easeInOut(duration: 0.2)) { controller.setLoginItem(true) }
                }
                .buttonStyle(.borderedProminent)

                Button("Not Now") {
                    withAnimation(.easeInOut(duration: 0.2)) { settings.hasAnsweredLoginSuggestion = true }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Header

private struct HeaderView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AppIconImage(size: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tideline")
                        .font(.title2.weight(.semibold))
                    Text("Today's downloads stay where you left them. Everything older is filed into a folder named for the day it arrived.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $settings.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(settings.isEnabled ? "Filing is on" : "Filing is paused")
            }

            // Above the tabs, so it still reads as the picture of what the app
            // does — and it keeps tracking the folder-name setting over on Filing.
            ExampleTree()
        }
        .padding(20)
        .background(.background)
    }
}

private struct ExampleTree: View {
    @ObservedObject private var settings = Settings.shared

    private var sample: String {
        let format = settings.folderFormat
        let older = format == .daily ? "2026-08-19" : "2026-07"
        return """
        Downloads/
        ├── \(older)/       filed away
        │   ├── invoice.pdf
        │   └── slides.key
        ├── report.pdf      arrived today, stays put
        └── archive.zip     arrived today, stays put
        """
    }

    var body: some View {
        Text(sample)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

// MARK: - Access

/// The same warning the form used to carry, restyled to sit above the tabs.
private struct AccessBanner: View {
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(controller.access == .unknown ? Color.secondary : Color.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.medium))

                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if controller.access == .denied {
                        Button("Open Privacy Settings") { controller.openPrivacySettings() }
                    }
                    Button("Check Again") { controller.refreshAccess() }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.orange.opacity(0.08))
    }

    private var title: String {
        switch controller.access {
        case .denied: return "Tideline can't read your Downloads folder"
        case .missing: return "That folder no longer exists"
        default: return "Checking access…"
        }
    }

    private var explanation: String {
        switch controller.access {
        case .denied:
            return "macOS is blocking access. Open Privacy & Security › Files and Folders, switch on Downloads Folder for Tideline, then quit and reopen the app."
        case .missing:
            return "\(settings.downloadsPath) is gone. Pick another folder under Filing."
        default:
            return "Asking macOS for permission to read \(settings.downloadsPath)."
        }
    }

    private var icon: String {
        controller.access == .unknown ? "hourglass" : "exclamationmark.triangle.fill"
    }
}

// MARK: - Status

private struct StatusRow: View {
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.body.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controller.run(trigger: .manual)
                } label: {
                    if controller.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(settings.dryRun ? "Preview Now" : "File Now")
                    }
                }
                .disabled(controller.busy)
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var dotColor: Color {
        if !settings.isEnabled { return .secondary }
        if controller.access == .denied || controller.access == .missing { return .orange }
        return .green
    }

    private var headline: String {
        if !settings.isEnabled { return "Paused" }
        if controller.access == .denied { return "Waiting for permission" }
        if controller.access == .missing { return "Folder missing" }
        return controller.busy ? "Filing…" : "Watching \(settings.downloadsURL.lastPathComponent)"
    }

    private var detail: String {
        var parts: [String] = [controller.lastRunSummary]
        if settings.isEnabled, let next = controller.nextRunAt {
            parts.append("next sweep \(Self.time.string(from: next))")
        }
        if settings.dryRun {
            parts.append("preview mode, nothing is moved")
        }
        return parts.joined(separator: " · ")
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
