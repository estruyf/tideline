import AppKit
import SwiftUI

// MARK: - Schedule

struct ScheduleSection: View {
    @ObservedObject private var settings = Settings.shared

    private var runTime: Binding<Date> {
        Binding(get: { settings.dailyRunTime }, set: { settings.dailyRunTime = $0 })
    }

    var body: some View {
        Toggle(isOn: $settings.watchFolder) {
            Text("As soon as the folder changes")
            Text("Waits a few seconds for downloads to finish arriving, then files what is due.")
        }

        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $settings.dailyRunEnabled.animation(.easeInOut(duration: 0.18))) {
                Text("Once a day")
                Text("Files yesterday's downloads even on a morning where nothing new arrives.")
            }

            if settings.dailyRunEnabled {
                Divider()
                    .padding(.vertical, 10)

                LabeledContent {
                    DatePicker("", selection: runTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .fixedSize()
                } label: {
                    Text("Run at")
                }
            }
        }

        Toggle(isOn: $settings.runOnLaunch) {
            Text("When the app starts")
            Text("Catches up after the Mac was shut down at the scheduled time.")
        }
    }
}

// MARK: - Rules

struct RulesSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        LabeledContent("Folder") {
            HStack(spacing: 8) {
                Text(shortPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                Button("Choose…") { chooseFolder() }
            }
        }

        Picker(selection: $settings.keepRecentDays) {
            Text("Today only").tag(0)
            Text("Today and yesterday").tag(1)
            Text("The last 3 days").tag(2)
            Text("The last week").tag(6)
        } label: {
            Text("Leave loose in the root")
            Text("Anything older than this window moves into a dated folder.")
        }

        Picker(selection: $settings.folderFormat) {
            ForEach(FolderFormat.allCases) { format in
                Text("\(format.label) — \(format.example)").tag(format)
            }
        } label: {
            Text("Folder name")
        }

        Picker(selection: $settings.dateBasis) {
            ForEach(DateBasis.allCases) { basis in
                Text(basis.label).tag(basis)
            }
        } label: {
            Text("Sort by")
            Text(settings.dateBasis.explanation)
        }

        Toggle(isOn: $settings.includeFolders) {
            Text("File folders too")
            Text("Unzipped archives and downloaded folders move by their own date.")
        }

        Toggle(isOn: $settings.dryRun) {
            Text("Preview mode")
            Text("Logs what would move without touching a single file.")
        }
    }

    private var shortPath: String {
        settings.downloadsPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadsURL
        panel.prompt = "Choose"
        panel.message = "Pick the folder Tideline should keep tidy."

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadsPath = url.path
            controller.refreshAccess()
        }
    }
}

// MARK: - Clearing out

struct CleanupSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        Picker(selection: $settings.cleanupAfterDays.animation(.easeInOut(duration: 0.18))) {
            Text("Never").tag(0)
            Text("Older than a month").tag(30)
            Text("Older than three months").tag(90)
            Text("Older than six months").tag(180)
            Text("Older than a year").tag(365)
        } label: {
            Text("Clear dated folders")
            Text("Measured from the end of the day or month the folder is named for.")
        }

        if settings.cleanupAfterDays > 0 {
            Picker(selection: $settings.cleanupKeepNewest) {
                Text("The newest folder").tag(1)
                Text("The newest 3 folders").tag(3)
                Text("The newest 5 folders").tag(5)
                Text("The newest 10 folders").tag(10)
            } label: {
                Text("Always keep")
                Text("Held back whatever their age, so a quiet month never empties the folder.")
            }

            Toggle(isOn: $settings.cleanupOnSchedule) {
                Text("Clear on the daily sweep")
                Text("Off by default. Left off, folders only go when you review them below.")
            }

            HStack {
                Button("Review Old Folders…") {
                    controller.reviewingCleanup = true
                }
                Spacer()
                if settings.cleanupOnSchedule {
                    Label("Runs unattended", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Skip list

struct SkipListSection: View {
    @ObservedObject private var settings = Settings.shared
    @State private var draft = ""

    var body: some View {
        ForEach(Array(settings.skipNames.enumerated()), id: \.offset) { index, name in
            HStack {
                Image(systemName: name.contains("*") ? "asterisk" : "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(name)
                Spacer()
                Button {
                    settings.skipNames.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Stop skipping \(name)")
            }
        }

        HStack {
            TextField("Name or pattern", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !settings.skipNames.contains(value) else { return }
        settings.skipNames.append(value)
        draft = ""
    }
}

// MARK: - Activity

struct ActivitySection: View {
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        if controller.history.isEmpty {
            Text("Nothing has been filed yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(controller.history.prefix(12)) { record in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: record))
                        .font(.system(size: 12))
                        .foregroundStyle(tint(for: record))
                        .frame(width: 16)
                    Text(record.kind == .cleared ? "\(record.name)/" : record.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(record.folder)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .padding(.vertical, 1)
            }

            HStack {
                Text(tally)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear List") { controller.clearHistory() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func icon(for record: MoveRecord) -> String {
        if record.wasPreview { return "eye" }
        return record.kind == .cleared ? "trash" : "arrow.right.doc.on.clipboard"
    }

    private func tint(for record: MoveRecord) -> Color {
        if record.wasPreview { return .secondary }
        return record.kind == .cleared ? .orange : .accentColor
    }

    /// The list holds both kinds now, so "filed in total" would undercount.
    private var tally: String {
        let filed = controller.history.filter { $0.kind == .filed }.count
        let cleared = controller.history.count - filed

        var parts: [String] = []
        if filed > 0 { parts.append("\(filed) filed") }
        if cleared > 0 { parts.append("\(cleared) cleared") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - About

struct AboutSection: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIconImage(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name)
                    .font(.body.weight(.medium))
                Text(AppInfo.versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Link("Send Feedback", destination: AppInfo.newIssue)
                .buttonStyle(.link)
        }
        .padding(.vertical, 2)

        LabeledContent {
            Link(AppInfo.repository.absoluteString.replacingOccurrences(of: "https://", with: ""),
                 destination: AppInfo.repository)
        } label: {
            Text("Source code")
        }

        LabeledContent {
            Link("Open on GitHub", destination: AppInfo.issues)
        } label: {
            Text("Issues and ideas")
        }

        LabeledContent {
            Link(AppInfo.author, destination: AppInfo.authorProfile)
        } label: {
            Text("Made by")
        }
    }
}
