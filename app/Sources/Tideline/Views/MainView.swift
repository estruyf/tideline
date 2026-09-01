import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var updater = Updater.shared

    @State private var showUninstall = false
    @State private var tab: MainTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            HeaderBand()

            // Losing access stops everything, so it is said once above the
            // sidebar rather than on a pane you might not be looking at. That
            // includes never having asked: waving away the welcome sheet with
            // the permission still ungranted used to leave a window with no
            // way to ask for it and nothing saying why it was empty.
            if !controller.access.isUsable {
                Hairline()
                AccessBanner()
            }

            Hairline()

            HStack(spacing: 0) {
                Sidebar(selection: $tab)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .tint(Theme.accent)
        .sheet(isPresented: $showUninstall) {
            UninstallView(isPresented: $showUninstall)
        }
        .sheet(isPresented: $controller.reviewingCleanup) {
            CleanupView(isPresented: $controller.reviewingCleanup)
        }
        .sheet(isPresented: $controller.reviewingRegroup) {
            RegroupView(isPresented: $controller.reviewingRegroup)
        }
        .sheet(isPresented: $controller.reviewingCollect) {
            CollectView(isPresented: $controller.reviewingCollect)
        }
        .sheet(isPresented: $controller.reviewingDuplicates) {
            DuplicateView(isPresented: $controller.reviewingDuplicates)
        }
        .sheet(isPresented: $controller.reviewingLargeFiles) {
            LargeFileView(isPresented: $controller.reviewingLargeFiles)
        }
        .sheet(isPresented: $controller.reviewingPlan) {
            PreviewView(isPresented: $controller.reviewingPlan)
        }
        .sheet(isPresented: $controller.reviewingRestore) {
            RestoreView(isPresented: $controller.reviewingRestore)
        }
        .sheet(isPresented: $controller.askingToStart) {
            WelcomeView(isPresented: $controller.askingToStart)
        }
        .onChange(of: updater.reveal) { _, reveal in
            // "Check for Updates…" in the menu bar lands on the pane that
            // shows what the check found.
            if reveal {
                tab = .general
                updater.reveal = false
            }
        }
        .onChange(of: controller.reviewingCleanup) { _, reviewing in
            // Asked for from the menu bar, so dismissing the sheet leaves you on
            // the pane the sheet came from rather than wherever you last were.
            if reviewing { tab = .reclaim }
        }
        .onChange(of: controller.reviewingDuplicates) { _, reviewing in
            if reviewing { tab = .reclaim }
        }
        .onChange(of: controller.reviewingLargeFiles) { _, reviewing in
            if reviewing { tab = .reclaim }
        }
        .onChange(of: controller.reviewingRegroup) { _, reviewing in
            // Catching up is offered from both rule panes, and it acts on both
            // kinds of rule, so asking from either one leaves you where you
            // asked. Only somewhere else lands you on a pane that explains it.
            if reviewing, tab != .rules, tab != .typeFolders { tab = .typeFolders }
        }
        .onChange(of: controller.reviewingCollect) { _, reviewing in
            if reviewing { tab = .collect }
        }
        .onChange(of: controller.reviewingRestore) { _, reviewing in
            if reviewing { tab = .filing }
        }
        .onChange(of: controller.reveal) { _, wanted in
            guard let wanted else { return }
            tab = wanted
            controller.reveal = nil
        }
        .onAppear {
            // A fresh install has said nothing about filing yet, so the window
            // asks before it does anything. Answered once, never again.
            if !settings.hasStartedFiling { controller.askingToStart = true }
            controller.refreshLoginItem()
            controller.refreshUsage()
            // The sidebar badge and Overview's "Waiting for you" are only worth
            // having if they are filled in before you go looking for them.
            controller.scanWhatIsCheap()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: OverviewTab(tab: $tab)
        case .reclaim: ReclaimTab(tab: $tab)
        case .schedule: ScheduleTab()
        case .filing: FilingTab()
        case .collect: CollectTab()
        case .rules: RoutingRuleTab()
        case .typeFolders: TypeFolderTab()
        case .clearing: ClearingTab()
        case .activity: ActivityTab()
        case .general: GeneralTab(showUninstall: $showUninstall)
        }
    }
}

// MARK: - Header

/// One band across the top: what the app is, and the one switch that decides
/// whether any of the rest of the window means anything.
private struct HeaderBand: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 12) {
            AppIconImage(size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tideline")
                    .font(.callout.weight(.semibold))
                Text("Today's downloads stay put · everything older is filed by the day it arrived")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            Text(stateLabel)
                .font(.callout)
                .foregroundStyle(Theme.muted)

            // Switching this on before the question has been answered asks the
            // question instead — the switch decides whether filing is paused,
            // not whether it was ever agreed to.
            Toggle("", isOn: Binding(
                get: { settings.isEnabled && settings.hasStartedFiling },
                set: { wanted in
                    if wanted, !settings.hasStartedFiling {
                        Controller.shared.askingToStart = true
                    } else {
                        settings.isEnabled = wanted
                    }
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(helpText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chrome)
    }

    private var stateLabel: String {
        if !settings.hasStartedFiling { return "Not started" }
        return settings.isEnabled ? "Filing on" : "Filing paused"
    }

    private var helpText: String {
        if !settings.hasStartedFiling { return "Filing has not been started yet" }
        return settings.isEnabled ? "Filing is on" : "Filing is paused"
    }
}

// MARK: - Overview

private struct OverviewTab: View {
    @Binding var tab: MainTab

    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // Only ever there when there is something to say about an update.
            if updater.hasNews {
                Panel { UpdateBanner() }
            }

            StatusPanel()

            // The picture of the folder takes whatever room the fixed cards
            // above and below it leave, and scrolls inside that.
            FolderPanel()
                .frame(maxHeight: .infinity)

            WaitingPanel(tab: $tab)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .paneBackground()
    }

}

/// Whether it is running, what it did last, and the button that runs it now.
private struct StatusPanel: View {
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.callout.weight(.semibold))
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Button {
                        // No permission means no sweep, so the button that
                        // would file asks macOS instead — pressing "File Now"
                        // must never be what raises the prompt.
                        guard controller.access != .notAsked else {
                            controller.requestAccess()
                            return
                        }
                        // Nothing has been agreed to yet, so the button that
                        // would file asks first, and files once it has an answer.
                        guard settings.hasStartedFiling else {
                            controller.askingToStart = true
                            return
                        }
                        // In preview mode the sweep touches nothing and what it
                        // would have done opens in a sheet, like the other reviews.
                        controller.run(trigger: .manual, showingPlan: settings.dryRun)
                    } label: {
                        if controller.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(actionTitle)
                                .foregroundStyle(Theme.onAccent)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.busy)

                    Button("Catch Up…") { controller.reviewingRegroup = true }
                        .disabled(!anyTypeRuleEnabled)
                        .help(anyTypeRuleEnabled
                              ? "Pull what the type folders claim out of the dated folders"
                              : "Switch a type folder on to have something to catch up on")
                }

                if let error = controller.lastError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Hairline()

                // Filing only happens while the app is running, so the switch
                // that decides whether it is belongs with the state it governs
                // — not three panes away under General.
                Toggle(isOn: Binding(
                    get: { controller.loginItemEnabled },
                    set: { controller.setLoginItem($0) }
                )) {
                    Text("Open at login")
                        .font(.callout)
                    Text("Starts in the background with no window and no Dock icon. Left off, nothing is filed until you open Tideline yourself.")
                        .explanation()
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var anyTypeRuleEnabled: Bool {
        settings.typeRules.contains { $0.isEnabled && !$0.extensions.isEmpty }
    }

    private var actionTitle: String {
        if controller.access == .notAsked { return "Allow Access…" }
        if !settings.hasStartedFiling { return "Start Filing…" }
        return settings.dryRun ? "Preview Now" : "File Now"
    }

    /// What is in the way comes first. A folder that cannot be read stops
    /// filing whatever the switches say, so it outranks paused and not-started
    /// — the card should name the thing you would have to fix.
    private var dotColor: Color {
        if controller.access == .denied || controller.access == .missing { return Theme.danger }
        if controller.access == .notAsked { return Theme.accentText }
        if !settings.hasStartedFiling || !settings.isEnabled { return Theme.muted }
        return Theme.success
    }

    private var headline: String {
        if controller.access == .denied || controller.access == .notAsked { return "Waiting for permission" }
        if controller.access == .missing { return "Folder missing" }
        if !settings.hasStartedFiling { return "Not filing yet" }
        if !settings.isEnabled { return "Paused" }
        return controller.busy ? "Filing…" : "Watching \(settings.downloadsURL.lastPathComponent)"
    }

    private var detail: String {
        guard controller.access != .notAsked else {
            return "macOS has not been asked yet, and nothing is filed until it says yes."
        }
        guard settings.hasStartedFiling else {
            return "Nothing has been moved. Tideline files older downloads once you start it."
        }

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

/// What is actually in the folder, right now. The window used to draw a sketch
/// of a tidy Downloads folder here; this is the real one, and what it marks as
/// due to move is what the next sweep would move.
private struct FolderPanel: View {
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    private var snapshot: FolderSnapshot? { controller.snapshot }

    var body: some View {
        ListPanel {
            header
            Hairline()

            if let snapshot, !snapshot.isEmpty {
                ScrollView {
                    rows(of: snapshot)
                }
            } else {
                // Given the height of the pane, an empty card should fill it
                // the way a full one does — a box sized to one line of text
                // leaves the pane looking like three cards adrift in a void.
                Text(emptyNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Hairline()
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Downloads right now")
                .panelHeader()

            Spacer(minLength: 12)

            Text(tally)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Open in Finder") { controller.revealDownloadsFolder() }
                .linkButton()
                .font(.callout)

            // Reading the folder again also re-measures it, since both happen
            // in the same look.
            Button {
                controller.refreshUsage(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Read the folder again")
                .accessibilityLabel("Read the folder again")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func rows(of snapshot: FolderSnapshot) -> some View {
        let folders = snapshot.entries.filter(\.isFolder)
        let files = snapshot.entries.filter { !$0.isFolder }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(folders) { entry in
                EntryRow(entry: entry)
            }

            // What is filed away, then what is still loose — the split the
            // whole app is about, drawn where it happens.
            if !folders.isEmpty && !files.isEmpty {
                Hairline().padding(.horizontal, 13).padding(.vertical, 4)
            }

            ForEach(files) { entry in
                EntryRow(entry: entry)
            }

            if snapshot.isTruncated {
                Text("…and more — open the folder in Finder for the rest")
                    .explanation()
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tally: String {
        guard let snapshot else { return "" }
        let loose = snapshot.looseItems == 1 ? "1 loose" : "\(snapshot.looseItems) loose"
        let filed = "\(snapshot.filedFolders) filed"
        guard snapshot.dueItems > 0 else { return "\(loose) · \(filed)" }
        return "\(loose) · \(filed) · \(snapshot.dueItems) due"
    }

    private var emptyNote: String {
        guard controller.access != .notAsked else {
            return "Tideline has not looked at the folder yet.\nAllow Access… asks macOS first."
        }
        guard controller.access.isUsable else {
            return "Nothing to show until macOS grants access to the folder."
        }
        return controller.snapshot == nil ? "Looking…" : "The folder is empty."
    }

    private var footer: some View {
        Text("Anything older than \(window) moves into \(destination).")
            .explanation()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
    }

    private var window: String {
        switch settings.keepRecentDays {
        case 0: return "today"
        case 1: return "yesterday"
        case 2: return "the last three days"
        default: return "the last \(settings.keepRecentDays + 1) days"
        }
    }

    private var destination: String {
        settings.folderFormat == .daily
            ? "a folder named for the day it arrived"
            : "a folder named for the month it arrived"
    }
}

private struct EntryRow: View {
    let entry: FolderSnapshot.Entry

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: entry.isFolder ? "folder.fill" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(entry.isFolder ? Theme.accentText : Theme.muted)
                .frame(width: 14)

            Text(entry.isFolder ? "\(entry.name)/" : entry.name)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Text(note)
                .font(.callout)
                .foregroundStyle(entry.isDue ? Theme.accentText : Theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 3)
    }

    private var note: String {
        let items = entry.itemCount == 1 ? "1 item" : "\(entry.itemCount) items"

        switch entry.kind {
        case .typeFolder:
            return "by type · \(items)"
        case .datedFolder:
            return "filed · \(items)"
        case .ownFolder:
            return entry.isDue ? "yours · moves next sweep" : "yours · \(items)"
        case .file:
            guard let stamp = entry.stamp else { return entry.isDue ? "moves next sweep" : "stays put" }
            let arrived = "arrived \(Self.arrival.localizedString(for: stamp, relativeTo: Date()))"
            return entry.isDue ? "\(arrived) · moves next sweep" : "\(arrived) · stays put"
        }
    }

    private static let arrival: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// What the scans turned up, and the way through to doing something about it.
/// The card that used to sit beside this one only ever repeated the folder size
/// the sidebar already carries; this is the half that was worth the room.
private struct WaitingPanel: View {
    @Binding var tab: MainTab

    @ObservedObject private var controller = Controller.shared

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("Waiting for you")
                        .panelHeader()

                    Spacer(minLength: 12)

                    if reclaimable > 0 {
                        Text("\(FolderUsage.bytes.string(fromByteCount: reclaimable)) could go")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.accentText)

                        Button("Reclaim space") { tab = .reclaim }
                            .linkButton()
                            .font(.callout)
                    }
                }

                if rows.isEmpty {
                    Text(emptyNote)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Look for Space to Reclaim") { tab = .reclaim }
                        .linkButton()
                        .font(.callout)
                } else {
                    ForEach(rows, id: \.label) { row in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.accentText)
                                .frame(width: 6, height: 6)
                            Text(row.label)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button("Review") { row.review() }
                                .linkButton()
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }

    private struct Row {
        var label: String
        var review: () -> Void
    }

    private var reclaimable: Int64 { controller.reclaimable.bytes }

    private var rows: [Row] {
        var found: [Row] = []

        if !controller.duplicates.isEmpty {
            let sets = controller.duplicates.count == 1 ? "1 duplicate set" : "\(controller.duplicates.count) duplicate sets"
            let bytes = controller.duplicates.reduce(Int64(0)) { $0 + $1.reclaimable }
            found.append(Row(label: "\(sets) · \(FolderUsage.bytes.string(fromByteCount: bytes))") {
                controller.reviewingDuplicates = true
            })
        }

        if !controller.largeFiles.isEmpty {
            let files = controller.largeFiles.count == 1 ? "1 big file" : "\(controller.largeFiles.count) big files"
            let bytes = controller.largeFiles.reduce(Int64(0)) { $0 + $1.byteSize }
            found.append(Row(label: "\(files) · \(FolderUsage.bytes.string(fromByteCount: bytes))") {
                controller.reviewingLargeFiles = true
            })
        }

        if !controller.clearable.isEmpty {
            let folders = controller.clearable.count == 1 ? "1 old folder" : "\(controller.clearable.count) old folders"
            let bytes = controller.clearable.reduce(Int64(0)) { $0 + $1.byteSize }
            found.append(Row(label: "\(folders) · \(FolderUsage.bytes.string(fromByteCount: bytes))") {
                controller.reviewingCleanup = true
            })
        }

        return found
    }

    private var emptyNote: String {
        if controller.duplicateScanning || controller.largeFileScanning || controller.scanning {
            return "Looking…"
        }
        // Big files and old folders have already been looked for by the time
        // this is read, so an empty panel means there was nothing — bar the one
        // scan that still waits to be asked.
        return controller.hasScannedLargeFiles
            ? "Nothing big or old enough to bother with. Duplicates are only compared when you ask."
            : "Nothing found yet."
    }
}

// MARK: - Reclaim space

/// Filing never removes anything, so everything that could give space back is
/// in one place: what was found, what it is worth, and a review before it goes.
private struct ReclaimTab: View {
    @Binding var tab: MainTab

    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            headline
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    duplicates
                    largeFiles
                    oldFolders
                }
                .padding(18)
            }

            Hairline()
            footnote
        }
        .paneBackground()
        .onAppear {
            // Opening this pane is the asking. The two that only look at names
            // and sizes go straight away; duplicates keep their button, because
            // finding those means reading files through.
            controller.scanWhatIsCheap()
        }
        .onChange(of: settings.largeFileThresholdMB) { _, _ in
            // The threshold is set on this pane, so the list it governs should
            // answer to it without a second trip.
            controller.findLargeFiles()
        }
    }

    private var headline: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Could be freed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(reclaimable > 0 ? FolderUsage.bytes.string(fromByteCount: reclaimable) : "—")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(reclaimable > 0 ? Theme.accentText : Theme.muted)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if needsFullScan {
                    Button("Scan the folder in full") { controller.measureFolderInFull() }
                        .linkButton()
                        .font(.callout)
                        .disabled(controller.measuring)
                        .help("Walks every file in \(shortPath) to replace the floor with the real total")
                }
            }

            Spacer(minLength: 12)

            Button("Rescan") { scanEverything() }
                .disabled(busy)
                .help("Look again, duplicates included")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text(footnoteText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    /// The overlap note only appears when there is one, and it belongs down
    /// here with the other caveats rather than crowding the figure.
    private var footnoteText: String {
        let base = "Big files and old folders are looked for when this pane opens; a look only reads. Duplicates wait to be asked, because matching them means reading the candidates through. Everything you tick goes to the Trash, never straight to delete, and a duplicate set always keeps one copy."
        guard overlaps else { return base }
        return base + " A big file inside a folder old enough to clear is counted once, not twice."
    }

    // MARK: Cards

    private var duplicates: some View {
        ScanCard(
            title: "Duplicates",
            summary: duplicateSummary,
            bytes: controller.duplicates.reduce(Int64(0)) { $0 + $1.reclaimable },
            isScanning: controller.duplicateScanning,
            reviewTitle: "Review Duplicates…",
            review: { controller.reviewingDuplicates = true },
            scan: { controller.findDuplicates() },
            rows: controller.duplicates.prefix(3).map { group in
                ScanCard.Row(
                    name: group.copies.dropFirst().first?.name ?? group.baseName,
                    detail: "copy of \(group.baseName)",
                    size: FolderUsage.bytes.string(fromByteCount: group.reclaimable)
                )
            }
        )
    }

    private var largeFiles: some View {
        ScanCard(
            title: "Big files",
            summary: largeFileSummary,
            bytes: controller.largeFiles.reduce(Int64(0)) { $0 + $1.byteSize },
            isScanning: controller.largeFileScanning,
            hasScanned: controller.hasScannedLargeFiles,
            reviewTitle: "Review Large Files…",
            review: { controller.reviewingLargeFiles = true },
            scan: { controller.findLargeFiles() },
            rows: controller.largeFiles.prefix(3).map { file in
                ScanCard.Row(
                    name: file.name,
                    detail: "\(file.folder)/",
                    size: FolderUsage.bytes.string(fromByteCount: file.byteSize)
                )
            }
        ) {
            // Filing goes by age; this goes by size, and the size is the only
            // thing here worth setting — so it sits with the results.
            Picker("Bigger than", selection: $settings.largeFileThresholdMB) {
                ForEach(Settings.largeFileThresholds, id: \.self) { megabytes in
                    Text(LargeFileView.threshold(megabytes)).tag(megabytes)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var oldFolders: some View {
        if settings.cleanupAfterDays == 0 {
            Panel {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Old dated folders")
                            .font(.callout.weight(.semibold))
                        Text("Clearing is switched off, so no folder is ever old enough to go.")
                            .explanation()
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Set an Age…") { tab = .clearing }
                }
            }
        } else {
            ScanCard(
                title: "Old dated folders",
                summary: cleanupSummary,
                bytes: controller.clearable.reduce(Int64(0)) { $0 + $1.byteSize },
                isScanning: controller.scanning,
                hasScanned: controller.hasScannedClearable,
                reviewTitle: "Review Old Folders…",
                review: { controller.reviewingCleanup = true },
                scan: { controller.findClearable() },
                rows: controller.clearable.prefix(3).map { candidate in
                    ScanCard.Row(
                        name: "\(candidate.name)/",
                        detail: candidate.itemCount == 1 ? "1 item" : "\(candidate.itemCount) items",
                        size: (candidate.sizeIsPartial ? "more than " : "")
                            + FolderUsage.bytes.string(fromByteCount: candidate.byteSize)
                    )
                }
            )
        }
    }

    // MARK: Summaries

    private var duplicateSummary: String {
        if controller.duplicateScanning { return "Comparing files…" }
        guard !controller.duplicates.isEmpty else {
            return "Files that are here more than once. Nothing is compared until you ask — matching them means reading the candidates through."
        }
        let sets = controller.duplicates.count == 1 ? "set" : "sets"
        return "\(controller.duplicates.count) \(sets) · the newest copy is kept"
    }

    private var largeFileSummary: String {
        if controller.largeFileScanning { return "Measuring files…" }
        let threshold = LargeFileView.threshold(settings.largeFileThresholdMB)
        guard !controller.largeFiles.isEmpty else {
            return "The biggest files in the folder, largest first, with nothing ticked until you tick it."
        }
        let noun = controller.largeFiles.count == 1 ? "file" : "files"
        return "\(controller.largeFiles.count) \(noun) over \(threshold)"
    }

    private var cleanupSummary: String {
        if controller.scanning { return "Looking through the dated folders…" }
        guard !controller.clearable.isEmpty else {
            return "Only the dated folders Tideline made itself, once they are past the age set under Clearing."
        }
        let noun = controller.clearable.count == 1 ? "folder" : "folders"
        let kept = settings.cleanupKeepNewest == 1 ? "the newest is" : "the newest \(settings.cleanupKeepNewest) are"
        return "\(controller.clearable.count) \(noun) old enough · \(kept) always kept"
    }

    // MARK: Scanning

    private var busy: Bool {
        controller.duplicateScanning || controller.largeFileScanning || controller.scanning
    }

    private var hasScanned: Bool {
        !controller.duplicates.isEmpty || !controller.largeFiles.isEmpty || !controller.clearable.isEmpty
    }

    /// Three separate looks at the folder, none of which moves anything. They
    /// all queue behind each other on the inspect queue, so a sweep is never
    /// held up by them.
    private func scanEverything() {
        controller.findDuplicates()
        controller.scanWhatIsCheap(force: true)
    }

    /// Only what a scan actually found — a figure that guessed at the folders
    /// nobody has looked at yet would be worth nothing. The counting itself
    /// lives on `Controller`, so this pane and Overview cannot disagree.
    private var reclaimable: Int64 { controller.reclaimable.bytes }

    /// True when at least one byte was claimed by more than one scan.
    private var overlaps: Bool { controller.reclaimable.overlaps }

    private var subtitle: String {
        guard hasScanned else {
            return busy
                ? "Looking. A scan only reads — it moves nothing."
                : "Nothing found so far. A scan only reads — it moves nothing."
        }

        guard let usage = controller.usage else {
            return "Nothing goes until you say so."
        }

        // Measuring stops at a cap, so on a folder past it the total is a floor
        // rather than a total — and the scans below are not bounded the same
        // way, so they can find more than the floor admits is there. "11.55 GB
        // of more than 10.66 GB" reads as a fault rather than as the two
        // different measurements it is, so say what happened and offer the walk
        // that settles it instead of quoting a figure that cannot be compared.
        if usage.isPartial {
            if controller.measuring {
                return "Measuring \(shortPath) in full. It walks every file, so it takes a moment."
            }
            return "in \(shortPath) · more than \(usage.itemCapDescription) items here, so a full scan is needed to say what the folder comes to"
        }

        return "of \(usage.totalDescription) in \(shortPath) · nothing goes until you say so"
    }

    /// The folder was too large to total under the usual cap, so the exact
    /// figure is there to be asked for.
    private var needsFullScan: Bool {
        hasScanned && controller.usage?.isPartial == true
    }

    private var shortPath: String {
        settings.downloadsPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

/// One of the three looks at the folder: what it found, the top of the list,
/// and the sheet that does the actual deciding.
private struct ScanCard<Accessory: View>: View {
    struct Row: Identifiable {
        var id: String { name + detail }
        var name: String
        var detail: String
        var size: String
    }

    let title: String
    let summary: String
    let bytes: Int64
    let isScanning: Bool
    /// Set once this scan has run. Without it a scan that found nothing looks
    /// exactly like one that never happened, and offers a pointless button.
    var hasScanned: Bool = false
    let reviewTitle: String
    let review: () -> Void
    let scan: () -> Void
    let rows: [Row]
    @ViewBuilder var accessory: Accessory

    var body: some View {
        ListPanel {
            HStack(spacing: 9) {
                Circle()
                    .fill(rows.isEmpty ? Theme.muted.opacity(0.5) : Theme.accentText)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if bytes > 0 {
                            Text(FolderUsage.bytes.string(fromByteCount: bytes))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.accentText)
                        }
                    }
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                accessory

                if isScanning {
                    ProgressView().controlSize(.small)
                } else if !rows.isEmpty {
                    Button(reviewTitle, action: review)
                } else if hasScanned {
                    Text("Nothing to reclaim")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                } else {
                    Button("Scan", action: scan)
                }
            }
            .padding(13)

            if !rows.isEmpty {
                Hairline()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 9) {
                            Text(row.name)
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(row.detail)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(row.size)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

extension ScanCard where Accessory == EmptyView {
    init(
        title: String,
        summary: String,
        bytes: Int64,
        isScanning: Bool,
        hasScanned: Bool = false,
        reviewTitle: String,
        review: @escaping () -> Void,
        scan: @escaping () -> Void,
        rows: [Row]
    ) {
        self.init(
            title: title,
            summary: summary,
            bytes: bytes,
            isScanning: isScanning,
            hasScanned: hasScanned,
            reviewTitle: reviewTitle,
            review: review,
            scan: scan,
            rows: rows,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Schedule

private struct ScheduleTab: View {
    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "When it runs",
                footer: "A sweep is cheap — nothing moves unless a file is older than the window set under Filing."
            ) {
                ScheduleSection()
            }
        }
    }
}

// MARK: - Filing

private struct FilingTab: View {
    var body: some View {
        SettingsPane {
            SettingsGroup(title: "What gets filed") {
                RulesSection()
            }

            SettingsGroup(
                title: "Never touch these",
                footer: "Exact names, or patterns such as *.dmg. Partial downloads, hidden files and the dated folders themselves are always left alone."
            ) {
                SkipListSection()
            }

            SettingsGroup(
                title: "Putting it back",
                footer: "Everything Tideline filed goes back into the root, and the folders it leaves empty go to the Trash. Filing switches off afterwards, so the next sweep does not undo it."
            ) {
                RestoreSection()
            }
        }
    }
}

// MARK: - Move out

private struct CollectTab: View {
    var body: some View { CollectPane() }
}

// MARK: - Routing rules

private struct RoutingRuleTab: View {
    var body: some View { RoutingRulePane() }
}

// MARK: - Type folders

private struct TypeFolderTab: View {
    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Type folders",
                footer: "A folder at the root that takes everything with one of its extensions, instead of the dated folder. Files still wait out the window set under Filing — a type folder decides where something goes, not when. Everything here starts switched off."
            ) {
                TypeFolderSection()
            }
        }
    }
}

// MARK: - Clearing

private struct ClearingTab: View {
    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Clearing out",
                footer: "Only the dated folders Tideline made itself are ever cleared, and they go to the Trash. Loose files and folders you made yourself are never touched. What a clear-out would take back is listed under Reclaim space."
            ) {
                CleanupSection()
            }
        }
    }
}

// MARK: - Activity log

private struct ActivityTab: View {
    var body: some View {
        SettingsPane {
            SettingsGroup(
                title: "Recent activity",
                footer: "The last few hundred things Tideline moved, cleared or renamed. The full record, sweep by sweep, is in the log file under General."
            ) {
                ActivitySection()
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @Binding var showUninstall: Bool

    var body: some View {
        SettingsPane {
            SettingsGroup(title: "Other") {
                SettingsToggle(
                    "Notify me when files are filed",
                    isOn: $settings.notifyOnMove
                )
                .onChange(of: settings.notifyOnMove) { _, newValue in
                    if newValue { controller.requestNotificationPermission() }
                }

                Hairline()

                SettingsToggle(
                    "Show the folder size in the menu bar",
                    "Next to the icon, rather than only inside the menu.",
                    isOn: $settings.showSizeInMenuBar
                )

                Hairline()

                HStack {
                    Button("Open Log File") { controller.openLogFile() }
                    Button("Open Downloads Folder") { controller.revealDownloadsFolder() }
                    Spacer()
                    Button("Uninstall…") { showUninstall = true }
                }
                .settingsRow()
            }

            SettingsGroup(title: "Updates") {
                UpdateSection()
            }

            SettingsGroup(title: "About") {
                AboutSection()
            }
        }
    }
}

// MARK: - Access

/// The same warning the form used to carry, restyled to sit above the sidebar.
private struct AccessBanner: View {
    @ObservedObject private var controller = Controller.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColour)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.medium))

                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    if controller.access == .notAsked {
                        // The one button that raises the macOS prompt. Nothing
                        // else in the window may, so this is the whole way in.
                        Button("Allow Access…") { controller.requestAccess() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        // The prompt macOS shows is a one-time offer, so the
                        // way back from a "no" is to hand the folder over
                        // yourself. Not while the answer is still coming,
                        // though — there is nothing to grant until macOS has
                        // actually refused.
                        if controller.access != .unknown {
                            Button("Choose Downloads Folder…") { controller.chooseDownloadsFolder() }
                        }
                        if controller.access == .denied {
                            Button("Open Privacy Settings") { controller.openPrivacySettings() }
                        }
                        Button("Check Again") { controller.refreshAccess() }
                    }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(banner)
    }

    private var iconColour: Color {
        switch controller.access {
        case .notAsked: return Theme.accentText
        case .unknown: return Theme.muted
        default: return Theme.danger
        }
    }

    /// Waiting on macOS to answer is not a fault yet, so the strip only turns
    /// red once the answer is no.
    private var banner: Color {
        switch controller.access {
        // Not having asked is not a fault, and neither is waiting on an
        // answer, so neither turns the strip red. The accent is the app's
        // "something is about to happen" colour, which is what this is.
        case .notAsked: return Theme.accent.opacity(0.12)
        case .unknown: return Theme.hover
        default: return Theme.danger.opacity(0.12)
        }
    }

    private var title: String {
        switch controller.access {
        case .notAsked: return "Tideline still needs access to your Downloads folder"
        case .denied: return "Tideline can't read your Downloads folder"
        case .missing: return "That folder no longer exists"
        default: return "Checking access…"
        }
    }

    private var explanation: String {
        switch controller.access {
        case .notAsked:
            return "Nothing has been read yet, and nothing can be filed until macOS is asked. The prompt covers this one folder and nothing else on the disk."
        case .denied:
            return "macOS asks about a folder once, and that answer was no. Choose the folder yourself to grant the same permission, or switch on Downloads Folder for Tideline under Privacy & Security › Files and Folders."
        case .missing:
            return "\(settings.downloadsPath) is gone. Choose another folder here, or under Filing."
        default:
            return "Asking macOS for permission to read \(settings.downloadsPath)."
        }
    }

    private var icon: String {
        switch controller.access {
        case .notAsked: return "lock"
        case .unknown: return "hourglass"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
