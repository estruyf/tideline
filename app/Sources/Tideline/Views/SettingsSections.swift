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

// MARK: - Type folders

/// Folders that claim files by extension. Everything here is off out of the box,
/// and switching a rule on only changes *where* a file goes — never when.
struct TypeFolderSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    /// The rule whose editor is open, by id. Only one at a time.
    @State private var editing: String?
    @State private var nameDraft = ""
    @State private var extensionsDraft = ""

    @State private var newName = ""
    @State private var newExtensions = ""
    @State private var addingRule = false

    var body: some View {
        ForEach(settings.typeRules) { rule in
            VStack(alignment: .leading, spacing: 0) {
                row(for: rule)

                if editing == rule.id {
                    Divider()
                        .padding(.vertical, 10)
                    editor(for: rule)
                }
            }
        }

        if let clash = conflictNote {
            Label(clash, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        addRow

        // Switching a rule on only steers what arrives next. This is how you
        // bring the files that are already filed by date into line with it.
        Divider()

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Files already filed by date")
                Text(anyRuleEnabled
                     ? "Pull what these folders claim out of the dated folders."
                     : "Switch a folder on above to have something to catch up on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Catch Up…") { controller.reviewingRegroup = true }
                .disabled(!anyRuleEnabled)
        }
    }

    private var anyRuleEnabled: Bool {
        settings.typeRules.contains { $0.isEnabled && !$0.extensions.isEmpty }
    }

    // MARK: Rows

    private func row(for rule: TypeRule) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: binding(for: rule).isEnabled) {
                Text(rule.name)
                Text(rule.extensions.isEmpty
                     ? "No extensions yet — nothing will match"
                     : rule.displayExtensions)
            }

            Spacer(minLength: 12)

            Button {
                toggleEditor(for: rule)
            } label: {
                Image(systemName: editing == rule.id ? "chevron.up" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(editing == rule.id ? "Close" : "Edit \(rule.name)")
        }
    }

    @ViewBuilder
    private func editor(for rule: TypeRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Folder name") {
                TextField("Installers", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit(rule) }
            }

            LabeledContent("Extensions") {
                TextField("dmg, pkg, iso", text: $extensionsDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit(rule) }
            }

            if !TypeRule.isValidFolderName(nameDraft) {
                Text("Pick a name that is not empty, has no slashes, and does not read as a date.")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }

            HStack {
                if rule.isBuiltIn {
                    Button("Reset") { reset(rule) }
                        .disabled(TypeRule.builtIn(id: rule.id) == rule)
                } else {
                    Button("Remove", role: .destructive) { remove(rule) }
                }

                Spacer()

                Button("Done") { commit(rule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!TypeRule.isValidFolderName(nameDraft))
            }
            .controlSize(.small)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var addRow: some View {
        if addingRule {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Folder name") {
                    TextField("Torrents", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                }

                LabeledContent("Extensions") {
                    TextField("torrent, magnet", text: $newExtensions)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                }

                HStack {
                    Button("Cancel") { cancelAdding() }
                    Spacer()
                    Button("Add Folder", action: add)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canAdd)
                }
                .controlSize(.small)
            }
        } else {
            Button {
                editing = nil
                addingRule = true
            } label: {
                Label("Add a folder of your own", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: Editing

    /// Rules live in an array on `Settings`, so a row edits through its id
    /// rather than an index that a removal could shift out from under it.
    private func binding(for rule: TypeRule) -> Binding<TypeRule> {
        Binding(
            get: { settings.typeRules.first { $0.id == rule.id } ?? rule },
            set: { updated in
                guard let index = settings.typeRules.firstIndex(where: { $0.id == rule.id }) else { return }
                settings.typeRules[index] = updated
            }
        )
    }

    private func toggleEditor(for rule: TypeRule) {
        if editing == rule.id {
            commit(rule)
            return
        }
        addingRule = false
        editing = rule.id
        nameDraft = rule.name
        extensionsDraft = rule.editableExtensions
    }

    private func commit(_ rule: TypeRule) {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TypeRule.isValidFolderName(name) else { return }

        var updated = rule
        updated.name = name
        updated.extensions = TypeRule.parseExtensions(extensionsDraft)
        binding(for: rule).wrappedValue = updated

        editing = nil
    }

    private func reset(_ rule: TypeRule) {
        guard var shipped = TypeRule.builtIn(id: rule.id) else { return }
        // Resetting is about the name and the extensions; it does not switch a
        // folder off behind your back.
        shipped.isEnabled = rule.isEnabled
        binding(for: rule).wrappedValue = shipped
        nameDraft = shipped.name
        extensionsDraft = shipped.editableExtensions
    }

    private func remove(_ rule: TypeRule) {
        settings.typeRules.removeAll { $0.id == rule.id }
        editing = nil
    }

    // MARK: Adding

    private var canAdd: Bool {
        TypeRule.isValidFolderName(newName) && !TypeRule.parseExtensions(newExtensions).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        let rule = TypeRule(
            id: UUID().uuidString,
            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
            extensions: TypeRule.parseExtensions(newExtensions),
            isEnabled: true
        )
        settings.typeRules.append(rule)
        cancelAdding()
    }

    private func cancelAdding() {
        addingRule = false
        newName = ""
        newExtensions = ""
    }

    // MARK: Conflicts

    /// Two folders asking for the same extension is not an error — the one
    /// higher up wins — but it is worth saying out loud.
    private var conflictNote: String? {
        let clashing = TypeRouter.conflicts(in: settings.typeRules)
        guard !clashing.isEmpty else { return nil }
        let list = clashing.prefix(4).map { ".\($0)" }.joined(separator: ", ")
        let more = clashing.count > 4 ? " and \(clashing.count - 4) more" : ""
        return "\(list)\(more) is claimed more than once. The folder higher up the list takes it."
    }
}

// MARK: - Skip list

/// The one thing filing cannot be undone with a single gesture in Finder, so
/// the app offers the gesture itself. It only ever opens the review sheet —
/// nothing moves from a settings pane.
struct RestoreSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Undo filing")
                    .font(.callout)
                Text(settings.dryRun
                     ? "Preview mode — the review will show what would come back and move nothing."
                     : "Lists everything filed, grouped by the folder it would come out of. Nothing moves until you say so.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("Put Everything Back…") { controller.reviewingRestore = true }
                .disabled(controller.restoring)
        }
        .padding(.vertical, 2)
    }
}

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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.kind == .cleared ? "\(record.name)/" : record.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        // Only duplicates carry one: what a copy was a copy of,
                        // or the name a kept copy got back.
                        if let detail = record.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(record.folder)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.hover, in: Capsule())
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
        switch record.kind {
        case .filed: return "arrow.right.doc.on.clipboard"
        case .cleared: return "trash"
        case .removed: return "doc.on.doc"
        case .renamed: return "character.cursor.ibeam"
        }
    }

    private func tint(for record: MoveRecord) -> Color {
        if record.wasPreview { return Theme.muted }
        switch record.kind {
        case .filed, .renamed: return Theme.link
        case .cleared, .removed: return Theme.accentText
        }
    }

    /// The list holds four kinds now, so "filed in total" would undercount.
    private var tally: String {
        var counts: [RecordKind: Int] = [:]
        for record in controller.history { counts[record.kind, default: 0] += 1 }

        var parts: [String] = []
        if let filed = counts[.filed] { parts.append("\(filed) filed") }
        if let cleared = counts[.cleared] { parts.append("\(cleared) cleared") }
        if let removed = counts[.removed] { parts.append("\(removed) duplicates trashed") }
        if let renamed = counts[.renamed] { parts.append("\(renamed) renamed") }
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
                .linkButton()
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
