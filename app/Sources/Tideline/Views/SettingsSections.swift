import AppKit
import SwiftUI

// MARK: - Schedule

struct ScheduleSection: View {
    @ObservedObject private var settings = Settings.shared

    private var runTime: Binding<Date> {
        Binding(get: { settings.dailyRunTime }, set: { settings.dailyRunTime = $0 })
    }

    var body: some View {
        SettingsToggle(
            "As soon as the folder changes",
            "Waits a few seconds for downloads to finish arriving, then files what is due.",
            isOn: $settings.watchFolder
        )

        Hairline()

        SettingsToggle(
            "Once a day",
            "Files yesterday's downloads even on a morning where nothing new arrives.",
            isOn: $settings.dailyRunEnabled.animation(.easeInOut(duration: 0.18))
        )

        if settings.dailyRunEnabled {
            Hairline()

            SettingsField("Run at") {
                DatePicker("", selection: runTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .fixedSize()
            }
        }

        Hairline()

        SettingsToggle(
            "When the app starts",
            "Catches up after the Mac was shut down at the scheduled time.",
            isOn: $settings.runOnLaunch
        )
    }
}

// MARK: - Rules

struct RulesSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        SettingsField("Folder") {
            HStack(spacing: 8) {
                Text(shortPath)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(Theme.muted)
                Button("Choose…") { chooseFolder() }
            }
        }

        Hairline()

        SettingsField(
            "Leave loose in the root",
            "Anything older than this window moves into a dated folder."
        ) {
            Picker("", selection: $settings.keepRecentDays) {
                Text("Today only").tag(0)
                Text("Today and yesterday").tag(1)
                Text("The last 3 days").tag(2)
                Text("The last week").tag(6)
            }
            .labelsHidden()
            .fixedSize()
        }

        Hairline()

        SettingsField("Folder name") {
            Picker("", selection: $settings.folderFormat) {
                ForEach(FolderFormat.allCases) { format in
                    Text("\(format.label) — \(format.example)").tag(format)
                }
            }
            .labelsHidden()
            .fixedSize()
        }

        Hairline()

        SettingsField("Sort by", settings.dateBasis.explanation) {
            Picker("", selection: $settings.dateBasis) {
                ForEach(DateBasis.allCases) { basis in
                    Text(basis.label).tag(basis)
                }
            }
            .labelsHidden()
            .fixedSize()
        }

        Hairline()

        SettingsToggle(
            "File folders too",
            "Unzipped archives and downloaded folders move by their own date.",
            isOn: $settings.includeFolders
        )

        Hairline()

        SettingsToggle(
            "Preview mode",
            "Logs what would move without touching a single file.",
            isOn: $settings.dryRun
        )
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
        SettingsField(
            "Clear dated folders",
            "Measured from the end of the day or month the folder is named for."
        ) {
            Picker("", selection: $settings.cleanupAfterDays.animation(.easeInOut(duration: 0.18))) {
                Text("Never").tag(0)
                Text("Older than a month").tag(30)
                Text("Older than three months").tag(90)
                Text("Older than six months").tag(180)
                Text("Older than a year").tag(365)
            }
            .labelsHidden()
            .fixedSize()
        }

        if settings.cleanupAfterDays > 0 {
            Hairline()

            SettingsField(
                "Always keep",
                "Held back whatever their age, so a quiet month never empties the folder."
            ) {
                Picker("", selection: $settings.cleanupKeepNewest) {
                    Text("The newest folder").tag(1)
                    Text("The newest 3 folders").tag(3)
                    Text("The newest 5 folders").tag(5)
                    Text("The newest 10 folders").tag(10)
                }
                .labelsHidden()
                .fixedSize()
            }

            Hairline()

            SettingsToggle(
                "Clear on the daily sweep",
                "Off by default. Left off, folders only go when you review them below.",
                isOn: $settings.cleanupOnSchedule
            )

            Hairline()

            HStack {
                Button("Review Old Folders…") {
                    controller.reviewingCleanup = true
                }
                Spacer()
                if settings.cleanupOnSchedule {
                    Label("Runs unattended", systemImage: "clock.arrow.circlepath")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }
            }
            .settingsRow()
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
            row(for: rule)
                .settingsRow()

            if editing == rule.id {
                Hairline()
                editor(for: rule)
                    .padding(13)
                    .background(Theme.pane)
            }

            Hairline()
        }

        if let clash = conflictNote {
            Label(clash, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .settingsRow()

            Hairline()
        }

        addRow
            .settingsRow()

        Hairline()

        // Switching a rule on only steers what arrives next. This is how you
        // bring the files that are already filed by date into line with it.
        SettingsField(
            "Files already filed by date",
            anyRuleEnabled
                ? "Pull what these folders claim out of the dated folders."
                : "Switch a folder on above to have something to catch up on."
        ) {
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
                SettingsLabel(
                    title: rule.name,
                    explanation: rule.extensions.isEmpty
                        ? "No extensions yet — nothing will match"
                        : rule.displayExtensions
                )
            }
            .toggleStyle(.switch)

            Spacer(minLength: 12)

            Button {
                toggleEditor(for: rule)
            } label: {
                Image(systemName: editing == rule.id ? "chevron.up" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(editing == rule.id ? "Close" : "Edit \(rule.name)")
            .accessibilityLabel(editing == rule.id ? "Close" : "Edit \(rule.name)")
        }
    }

    @ViewBuilder
    private func editor(for rule: TypeRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Folder name") {
                TextField("Folder name", text: $nameDraft, prompt: Text("What the folder is called"))
                    .labelsHidden()
                    .themedField()
                    .onSubmit { commit(rule) }
            }
            .labeledContentStyle(.settings)

            LabeledContent("Extensions") {
                TextField("Extensions", text: $extensionsDraft, prompt: Text("Extensions to match, separated by commas"))
                    .labelsHidden()
                    .themedField()
                    .onSubmit { commit(rule) }
            }
            .labeledContentStyle(.settings)

            if !TypeRule.isValidFolderName(nameDraft) {
                Text("Pick a name that is not empty, has no slashes, and does not read as a date.")
                    .explanation()
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
                    .buttonStyle(.borderedProminent)
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
                    TextField("Folder name", text: $newName, prompt: Text("What the folder is called"))
                        .labelsHidden()
                        .themedField()
                        .onSubmit(add)
                }
                .labeledContentStyle(.settings)

                LabeledContent("Extensions") {
                    TextField("Extensions", text: $newExtensions, prompt: Text("Extensions to match, separated by commas"))
                        .labelsHidden()
                        .themedField()
                        .onSubmit(add)
                }
                .labeledContentStyle(.settings)

                HStack {
                    Button("Cancel") { cancelAdding() }
                    Spacer()
                    Button("Add Folder", action: add)
                        .buttonStyle(.borderedProminent)
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
        SettingsField(
            "Undo filing",
            settings.dryRun
                ? "Preview mode — the review will show what would come back and move nothing."
                : "Lists everything filed, grouped by the folder it would come out of. Nothing moves until you say so."
        ) {
            Button("Put Everything Back…") { controller.reviewingRestore = true }
                .disabled(controller.restoring)
        }
    }
}

struct SkipListSection: View {
    @ObservedObject private var settings = Settings.shared
    @State private var draft = ""

    var body: some View {
        ForEach(Array(settings.skipNames.enumerated()), id: \.offset) { index, name in
            HStack {
                Image(systemName: name.contains("*") ? "asterisk" : "folder")
                    .foregroundStyle(Theme.muted)
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
                .accessibilityLabel("Stop skipping \(name)")
            }
            .settingsRow()

            Hairline()
        }

        HStack {
            TextField("Name or pattern", text: $draft)
                .themedField()
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .settingsRow()
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
                .foregroundStyle(Theme.muted)
                .settingsRow()
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
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 12)
                    Text(record.folder)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.hover, in: Capsule())
                }
                .settingsRow()

                Hairline()
            }

            HStack {
                Text(tally)
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Clear List") { controller.clearHistory() }
                    .buttonStyle(.borderless)
            }
            .settingsRow()
        }
    }

    private func icon(for record: MoveRecord) -> String {
        if record.wasPreview { return "eye" }
        switch record.kind {
        case .filed: return "arrow.right.doc.on.clipboard"
        case .cleared: return "trash"
        case .removed: return "doc.on.doc"
        case .renamed: return "character.cursor.ibeam"
        case .collected: return "tray.and.arrow.up"
        }
    }

    private func tint(for record: MoveRecord) -> Color {
        if record.wasPreview { return Theme.muted }
        switch record.kind {
        case .filed, .renamed: return Theme.link
        case .cleared, .removed: return Theme.accentText
        // Collecting is the one move that leaves the folder the app watches,
        // so it reads in the colour the app uses for what it is about to touch.
        case .collected: return Theme.accentText
        }
    }

    /// The list holds five kinds now, so "filed in total" would undercount.
    private var tally: String {
        var counts: [RecordKind: Int] = [:]
        for record in controller.history { counts[record.kind, default: 0] += 1 }

        var parts: [String] = []
        if let filed = counts[.filed] { parts.append("\(filed) filed") }
        if let cleared = counts[.cleared] { parts.append("\(cleared) cleared") }
        if let removed = counts[.removed] { parts.append("\(removed) duplicates trashed") }
        if let renamed = counts[.renamed] { parts.append("\(renamed) renamed") }
        if let collected = counts[.collected] { parts.append("\(collected) moved out") }
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
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Link("Send Feedback", destination: AppInfo.newIssue)
                .linkButton()
        }
        .settingsRow()

        Hairline()

        LabeledContent {
            Link(AppInfo.repository.absoluteString.replacingOccurrences(of: "https://", with: ""),
                 destination: AppInfo.repository)
        } label: {
            Text("Source code")
        }
        .labeledContentStyle(.settings)
        .settingsRow()

        Hairline()

        LabeledContent {
            Link("Open on GitHub", destination: AppInfo.issues)
        } label: {
            Text("Issues and ideas")
        }
        .labeledContentStyle(.settings)
        .settingsRow()

        Hairline()

        LabeledContent {
            Link(AppInfo.author, destination: AppInfo.authorProfile)
        } label: {
            Text("Made by")
        }
        .labeledContentStyle(.settings)
        .settingsRow()
    }
}
