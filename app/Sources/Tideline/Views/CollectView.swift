import AppKit
import SwiftUI

/// Moving things out of the watched folder altogether.
///
/// You say what you are looking for, the app says what it found and *which
/// condition found it*, you untick anything it got wrong, and only then does
/// anything move. That order is the whole point — this is the one thing the app
/// does that putting things back cannot reach.
struct CollectView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @State private var kind: SourceKind = .byHand
    @State private var ruleID: String = ""
    @State private var typeRuleID: String = ""
    @State private var conditions: [RuleTest] = [RuleTest()]

    @State private var selection: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var hovered: String?
    @State private var didHunt = false
    @State private var pending: DispatchWorkItem?

    @State private var destinationID: UUID?
    @State private var savingRule = false
    @State private var newRuleName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            results.sheetBody()
            Hairline()
            footer
        }
        .sheetSurface(width: 720, height: 700)
        .onAppear(perform: start)
        .onDisappear { pending?.cancel() }
    }

    // MARK: - Saying what to look for

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Move things out of Downloads", systemImage: "tray.and.arrow.up")
                    .font(.headline)

                Spacer(minLength: 12)

                if didHunt {
                    Text("\(controller.collectable.count) matches · searched \(controller.collectFoldersSearched) folders")
                        .explanation()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Picker("", selection: $kind) {
                    ForEach(SourceKind.allCases) { one in
                        Text(one.label).tag(one)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if kind == .rule {
                    Menu(namedRule?.name ?? "Choose a rule") {
                        ForEach(settings.rules) { rule in
                            Button(rule.name) { ruleID = rule.id }
                        }
                    }
                    .frame(width: 150)

                    if namedRule != nil {
                        Button("Edit rule…") {
                            isPresented = false
                            controller.reveal = .rules
                        }
                        .linkButton()
                    }
                }

                if kind == .typeFolder {
                    Menu(namedTypeRule?.name ?? "Choose a folder") {
                        ForEach(settings.typeRules) { rule in
                            Button(rule.name) { typeRuleID = rule.id }
                        }
                    }
                    .frame(width: 150)
                }

                Spacer(minLength: 0)
            }

            if kind == .byHand { conditionEditor }
        }
        .sheetBand()
        .onChange(of: kind) { _, _ in scheduleHunt() }
        .onChange(of: ruleID) { _, _ in scheduleHunt() }
        .onChange(of: typeRuleID) { _, _ in scheduleHunt() }
        .onChange(of: conditions) { _, _ in scheduleHunt() }
    }

    /// The rules' own grammar, typed on the spot and matched as you type.
    private var conditionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($conditions) { $condition in
                HStack(spacing: 8) {
                    Picker("", selection: $condition.field) {
                        ForEach(RuleField.allCases) { field in
                            Text(field.label).tag(field)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("", text: $condition.pattern, prompt: Text(condition.field.placeholder))
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.pane, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))

                    Button {
                        conditions.removeAll { $0.id == condition.id }
                        if conditions.isEmpty { conditions = [RuleTest()] }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this condition")
                    .accessibilityLabel("Remove this condition")
                }
            }

            HStack(spacing: 12) {
                Button {
                    conditions.append(RuleTest())
                } label: {
                    Label("Add a condition", systemImage: "plus")
                }
                .buttonStyle(.borderless)

                Text("Matches as you type · ✳ stands for anything")
                    .explanation()
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                // Seeing what a search catches and then keeping it is the
                // intended way to write a rule, rather than a settings form
                // with empty fields and a "trust me" button.
                if query.savableAsRule {
                    Button("Save as a rule…") { savingRule = true }
                        .linkButton()
                }
            }
        }
        .popover(isPresented: $savingRule) { saveRulePopover }
    }

    private var saveRulePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep this as a rule")
                .font(.headline)
            Text("New downloads that match will be filed into a folder of this name, and it will be one of the starting points here next time.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Folder name", text: $newRuleName, prompt: Text("Invoices"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveRule)

            HStack {
                Button("Cancel") { savingRule = false }
                Spacer()
                Button("Save Rule", action: saveRule)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!Rule.isValidFolderName(newRuleName))
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func saveRule() {
        let name = newRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Rule.isValidFolderName(name) else { return }

        let rule = query.asRule(named: name)
        settings.rules.append(rule)
        savingRule = false
        newRuleName = ""

        // Carry straight on with the hunt, now under its own name.
        kind = .rule
        ruleID = rule.id
    }

    // MARK: - What it found

    @ViewBuilder
    private var results: some View {
        if query.isEmpty {
            centred {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Looking in Downloads and every folder Tideline has filed")
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("Filing only ever sees today. Moving things out reaches back through the dated folders too — a search written now finds what arrived in June.")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        } else if controller.collectScanning && !didHunt {
            centred {
                ProgressView().controlSize(.small)
                Text("Looking through Downloads and every folder Tideline has filed…")
                    .explanation()
                    .foregroundStyle(.secondary)
            }
        } else if didHunt && controller.collectable.isEmpty {
            centred {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Nothing matched")
                    .font(.body.weight(.medium))
                Text("Nothing in Downloads, or in anything Tideline filed, answers to that.")
                    .explanation()
                    .foregroundStyle(.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(matchGroups, id: \.matched) { group in
                        card(for: group, warning: false)
                    }
                    if let incidentalGroup {
                        card(for: incidentalGroup, warning: true)
                    }
                }
                .padding(14)
            }
        }
    }

    private func centred<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 10, content: content)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    /// One card per condition that matched, so a pattern that is too loose shows
    /// up as one long card of things that do not belong together.
    private func card(for group: MatchGroup, warning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader(group, warning: warning)

            ForEach(shown(in: group)) { candidate in
                Hairline()
                row(for: candidate, warning: warning)
            }

            if group.items.count > Self.collapsedRows, !expanded.contains(group.matched) {
                Hairline()
                Button {
                    expanded.insert(group.matched)
                } label: {
                    Text("\(group.items.count - Self.collapsedRows) more · show")
                        .explanation()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(warning ? Theme.accent : Theme.border)
        )
    }

    private func cardHeader(_ group: MatchGroup, warning: Bool) -> some View {
        HStack(spacing: 8) {
            tickBox(
                state(of: group),
                label: warning ? "Everything worth a look" : "Everything matched by \(group.matched)"
            ) { toggleAll(in: group) }

            if warning {
                Text("Worth a look before you move it")
                    .font(.callout.weight(.medium))
            } else {
                Text("matched")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(group.matched)
                    .font(.callout.monospaced())
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            }

            Spacer(minLength: 12)

            Text(summary(of: group, warning: warning))
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(state(of: group) == .none ? "Tick all" : "Untick all") {
                toggleAll(in: group)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func row(for candidate: CollectCandidate, warning: Bool) -> some View {
        HStack(spacing: 8) {
            tickBox(
                selection.contains(candidate.id) ? .all : .none,
                label: candidate.name
            ) { toggle(candidate) }

            Image(systemName: candidate.isFolder ? "folder" : "doc")
                .foregroundStyle(.secondary)

            Text(candidate.name)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            if warning {
                Text("matched only because it sat in a folder named \(candidate.currentFolder)")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(place(of: candidate))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(age(of: candidate.stamp))
                    .font(.callout)
                    .foregroundStyle(Theme.faint)
            }

            Spacer(minLength: 12)

            if hovered == candidate.id {
                Button {
                    QuickLook.shared.show(candidate.url, within: controller.collectable.map(\.url))
                } label: {
                    Label("Quick Look", systemImage: "eye")
                }
                .controlSize(.small)

                Button {
                    controller.reveal(candidate.url)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .controlSize(.small)
            } else {
                Text(Self.bytes.string(fromByteCount: candidate.byteSize))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovered == candidate.id ? Theme.hover : Color.clear)
        .onHover { inside in
            if inside { hovered = candidate.id } else if hovered == candidate.id { hovered = nil }
        }
        .contextMenu {
            Button("Quick Look") {
                QuickLook.shared.show(candidate.url, within: controller.collectable.map(\.url))
            }
            Button("Show in Finder") { controller.reveal(candidate.url) }
        }
    }

    /// Drawn rather than a `Toggle`, which fills itself with the *system* accent
    /// when it is on — the one colour the palette does not own — and cannot show
    /// "some of these" at all.
    private func tickBox(
        _ state: TickState, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: state.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state == .none ? Theme.muted : Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(state.spoken)
    }

    // MARK: - Where it lands

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("Move to")
                    .font(.callout)
                    .frame(width: 72, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(settings.collectDestinations) { place in
                        destinationRow(place)
                    }

                    Button("Other folder…", action: addPlace)
                        .linkButton()
                        .padding(.leading, 9)
                }
            }

            Hairline()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tally)
                        .font(.callout.weight(.medium))
                    if settings.dryRun {
                        Text("Preview mode — nothing will actually move.")
                            .explanation()
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Text("They leave Downloads for good. Put Back returns the whole batch.")
                            .explanation()
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle) { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty || destination == nil || controller.collecting)
            }
        }
        .sheetBand()
    }

    private func destinationRow(_ place: CollectDestination) -> some View {
        let reachable = place.resolve() != nil
        let picked = destinationID == place.id

        return Button {
            destinationID = place.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(picked ? Theme.accent : Theme.muted)

                Text(place.name)
                    .font(.callout.weight(picked ? .medium : .regular))

                Text(reachable ? place.displayPath : "not mounted")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                picked ? Theme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(picked ? Theme.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!reachable)
        .opacity(reachable ? 1 : 0.55)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Behaviour

    private func start() {
        if let opening = controller.collectOpeningQuery {
            adopt(opening)
            controller.collectOpeningQuery = nil
        } else if !settings.lastCollectSearch.isEmpty {
            conditions = settings.lastCollectSearch
        }
        if destinationID == nil {
            destinationID = settings.collectDestinations.first { $0.resolve() != nil }?.id
        }
        scheduleHunt()
    }

    /// Opens on a hunt the pane started.
    private func adopt(_ opening: CollectQuery) {
        if let rule = settings.rules.first(where: { $0.name == opening.label }) {
            kind = .rule
            ruleID = rule.id
        } else if let type = settings.typeRules.first(where: { $0.name == opening.label }) {
            kind = .typeFolder
            typeRuleID = type.id
        } else {
            kind = .byHand
            conditions = opening.tests.isEmpty ? [RuleTest()] : opening.tests
        }
    }

    /// Matched as you type, a beat behind the typing. Every keystroke reading
    /// three hundred folders would make the field unusable.
    private func scheduleHunt() {
        pending?.cancel()
        guard !query.isEmpty else {
            didHunt = false
            return
        }

        let work = DispatchWorkItem { hunt() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hunt() {
        let asked = query
        guard !asked.isEmpty else { return }

        if kind == .byHand { settings.lastCollectSearch = asked.filledTests }

        controller.findCollectable(matching: asked) { found in
            // Anything offered only because of where it sat starts unticked;
            // the whole point of that card is that somebody looks.
            selection = Set(found.filter { !$0.isIncidental }.map(\.id))
            expanded = []
            didHunt = true
        }
    }

    private func apply() {
        guard let destination else { return }
        controller.collect(chosen, to: destination, as: query.label) { _ in isPresented = false }
    }

    private func addPlace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder to move things into."

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard let place = CollectDestination.make(name: folder.lastPathComponent, folder: folder) else { return }

        // Picked mid-move, so it is used and kept. The pane is where a place
        // gets renamed or given a template.
        settings.collectDestinations.append(place)
        destinationID = place.id
    }

    private func toggle(_ candidate: CollectCandidate) {
        if selection.contains(candidate.id) {
            selection.remove(candidate.id)
        } else {
            selection.insert(candidate.id)
        }
    }

    private func toggleAll(in group: MatchGroup) {
        if state(of: group) == .none {
            for item in group.items { selection.insert(item.id) }
        } else {
            for item in group.items { selection.remove(item.id) }
        }
    }

    // MARK: - Reading it back

    private var query: CollectQuery {
        switch kind {
        case .byHand:
            return CollectQuery(label: describeConditions(), tests: conditions)
        case .rule:
            guard let namedRule else { return CollectQuery() }
            return CollectQuery(rule: namedRule)
        case .typeFolder:
            guard let namedTypeRule else { return CollectQuery() }
            return CollectQuery(typeRule: namedTypeRule)
        }
    }

    /// A hand search has no name, so a batch made from one is labelled with the
    /// search itself — `name *invoice*` reads back well enough a month later.
    private func describeConditions() -> String {
        let filled = conditions.filter { !$0.pattern.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !filled.isEmpty else { return "" }
        return filled
            .map { "\($0.field.shortLabel) \($0.pattern.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: " or ")
    }

    private var namedRule: Rule? { settings.rules.first { $0.id == ruleID } }
    private var namedTypeRule: TypeRule? { settings.typeRules.first { $0.id == typeRuleID } }

    private var destination: CollectDestination? {
        guard let destinationID else { return nil }
        return settings.collectDestinations.first { $0.id == destinationID }
    }

    private var chosen: [CollectCandidate] {
        controller.collectable.filter { selection.contains($0.id) }
    }

    struct MatchGroup {
        var matched: String
        var items: [CollectCandidate]
    }

    private var matchGroups: [MatchGroup] {
        group(controller.collectable.filter { !$0.isIncidental })
    }

    private var incidentalGroup: MatchGroup? {
        let items = controller.collectable.filter(\.isIncidental)
        guard !items.isEmpty else { return nil }
        return MatchGroup(matched: "Worth a look before you move it", items: items)
    }

    private func group(_ items: [CollectCandidate]) -> [MatchGroup] {
        var order: [String] = []
        var byMatch: [String: [CollectCandidate]] = [:]
        for item in items {
            if byMatch[item.matched] == nil { order.append(item.matched) }
            byMatch[item.matched, default: []].append(item)
        }
        return order.map { MatchGroup(matched: $0, items: byMatch[$0] ?? []) }
    }

    private static let collapsedRows = 3

    private func shown(in group: MatchGroup) -> [CollectCandidate] {
        expanded.contains(group.matched) ? group.items : Array(group.items.prefix(Self.collapsedRows))
    }

    private func state(of group: MatchGroup) -> TickState {
        let ticked = group.items.filter { selection.contains($0.id) }.count
        if ticked == 0 { return .none }
        return ticked == group.items.count ? .all : .some
    }

    private func summary(of group: MatchGroup, warning: Bool) -> String {
        let noun = group.items.count == 1 ? "file" : "files"
        if warning {
            let ticked = group.items.filter { selection.contains($0.id) }.count
            return "\(group.items.count) \(noun) · \(ticked == 0 ? "unticked" : "\(ticked) ticked")"
        }
        let bytes = group.items.reduce(Int64(0)) { $0 + $1.byteSize }
        return "\(group.items.count) \(noun) · \(Self.bytes.string(fromByteCount: bytes))"
    }

    private func place(of candidate: CollectCandidate) -> String {
        candidate.currentFolder == settings.downloadsURL.lastPathComponent
            ? "Downloads/"
            : "\(candidate.currentFolder)/"
    }

    private var tally: String {
        guard didHunt, !controller.collectable.isEmpty else { return "Type a condition to see matches" }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.byteSize }
        let folders = Set(chosen.map(\.currentFolder)).count
        let noun = folders == 1 ? "folder" : "folders"
        return "Moving \(chosen.count) of \(controller.collectable.count) · \(folders) \(noun) · \(Self.bytes.string(fromByteCount: bytes))"
    }

    private var actionTitle: String {
        let count = chosen.count
        let noun = count == 1 ? "item" : "items"
        let target = destination.map { " to \($0.name)" } ?? ""
        if settings.dryRun { return "Preview Moving \(count) \(noun)\(target)" }
        return count == 0 ? "Move" : "Move \(count) \(noun)\(target)"
    }

    private func age(of date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    enum SourceKind: String, CaseIterable, Identifiable {
        case rule, typeFolder, byHand

        var id: String { rawValue }

        var label: String {
            switch self {
            case .rule: return "A rule I wrote"
            case .typeFolder: return "A type folder"
            case .byHand: return "Search by hand"
            }
        }
    }

    enum TickState {
        case none, some, all

        var symbol: String {
            switch self {
            case .none: return "square"
            case .some: return "minus.square.fill"
            case .all: return "checkmark.square.fill"
            }
        }

        /// What VoiceOver says the box is set to. The drawn box has no state of
        /// its own to read.
        var spoken: String {
            switch self {
            case .none: return "not ticked"
            case .some: return "partly ticked"
            case .all: return "ticked"
            }
        }
    }
}

// MARK: - The pane

/// Where moving out lives when the sheet is shut: the ways in, the places
/// things go, and the batches that can still come back.
///
/// Not a `Form`, because this is not a list of settings — the same hand-built
/// panels Overview and Reclaim space use.
struct CollectPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @State private var editing: UUID?
    @State private var nameDraft = ""
    @State private var opened: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                startingPoints
                places
                if !controller.collections.isEmpty { history }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.pane)
        .onAppear { controller.tallyCollectable() }
    }

    // MARK: Heading

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move out")
                    .font(.title2.weight(.semibold))
                Text("Filing sorts Downloads. This takes things out of it — and it is the only thing here that writes outside the folder Tideline watches.")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                controller.startCollecting()
            } label: {
                Label("New search…", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.access.mayRead)
        }
    }

    // MARK: Ways in

    @ViewBuilder
    private var startingPoints: some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start from something you already have")
                    .panelHeader()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(chips, content: chip) }
                        .padding(.vertical, 1)
                }
            }
        }
    }

    private func chip(_ start: StartingPoint) -> some View {
        Button {
            controller.startCollecting(start.query)
        } label: {
            HStack(spacing: 7) {
                Text(start.kind)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                Text(start.name)
                    .font(.callout)
                Text(start.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
    }

    /// A rule worth starting from is one with something waiting behind it. The
    /// last hand search is offered too, so picking up where you left off does
    /// not mean typing it again.
    private var chips: [StartingPoint] {
        var found: [StartingPoint] = []

        for rule in settings.rules where rule.isEnabled {
            let waiting = controller.collectWaiting[rule.name] ?? 0
            guard waiting > 0 || controller.collectWaiting.isEmpty else { continue }
            found.append(StartingPoint(
                id: "rule-\(rule.id)",
                kind: "RULE",
                name: rule.name,
                detail: controller.collectTallying ? "counting…" : "\(waiting) waiting",
                query: CollectQuery(rule: rule)
            ))
        }

        let last = settings.lastCollectSearch.filter {
            !$0.pattern.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if !last.isEmpty {
            let described = last
                .map { "\($0.field.shortLabel) \($0.pattern.trimmingCharacters(in: .whitespaces))" }
                .joined(separator: " or ")
            found.append(StartingPoint(
                id: "last",
                kind: "LAST",
                name: described,
                detail: "",
                query: CollectQuery(label: described, tests: last)
            ))
        }

        return found
    }

    struct StartingPoint: Identifiable {
        var id: String
        var kind: String
        var name: String
        var detail: String
        var query: CollectQuery
    }

    // MARK: Places

    private var places: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Places you move into")
                    .panelHeader()
                Text("Offered as destinations inside the sheet")
                    .explanation()
                    .foregroundStyle(Theme.faint)
            }

            ListPanel {
                if settings.collectDestinations.isEmpty {
                    Text("None yet. Add one here, or pick a folder the first time you move something. A place is remembered as a bookmark rather than a path, so it keeps working when the folder above it is renamed.")
                        .explanation()
                        .foregroundStyle(.secondary)
                        .padding(12)
                }

                ForEach(settings.collectDestinations) { place in
                    placeRow(place)
                    if editing == place.id {
                        Hairline()
                        editor(for: place).padding(12)
                    }
                    Hairline()
                }

                Button(action: addPlace) {
                    Label("Add a place…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
        }
    }

    private func placeRow(_ place: CollectDestination) -> some View {
        let reachable = place.resolve() != nil
        let moved = controller.collections
            .filter { $0.destinationName == place.name }
            .reduce(0) { $0 + $1.count }

        return HStack(spacing: 10) {
            Image(systemName: place.isOnAVolume ? "externaldrive" : "folder")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.body.weight(.medium))
                Text(place.template.isEmpty ? place.displayPath : "\(place.displayPath)/\(place.template)")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if reachable {
                if moved > 0 {
                    Text("\(moved) \(moved == 1 ? "item" : "items") moved here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Reveal") { controller.reveal(place.resolve() ?? URL(fileURLWithPath: place.lastKnownPath)) }
                    .linkButton()
            } else {
                Text("NOT MOUNTED")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: 4))
            }

            Button {
                toggleEditor(for: place)
            } label: {
                Image(systemName: editing == place.id ? "chevron.up" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(editing == place.id ? "Close" : "Edit \(place.name)")
            .accessibilityLabel(editing == place.id ? "Close" : "Edit \(place.name)")
        }
        .padding(12)
    }

    @ViewBuilder
    private func editor(for place: CollectDestination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Name") {
                TextField("Name", text: $nameDraft, prompt: Text("What to call this place"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commit(place) }
            }

            LabeledContent("Inside") {
                TextField("Template", text: templateBinding(for: place), prompt: Text("{yyyy}/kwartaal {q}"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            Text("\(CollectDestination.tokens.joined(separator: "  ")) — filled in from each file's own date, so a batch that straddles a quarter lands in two folders.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Remove", role: .destructive) { remove(place) }
                Spacer()
                Button("Done") { commit(place) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(nameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
        }
    }

    // MARK: Putting it back

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Moved out")
                    .panelHeader()
                Text("Every batch can go back where it came from")
                    .explanation()
                    .foregroundStyle(Theme.faint)
            }

            ListPanel {
                ForEach(Array(controller.collections.enumerated()), id: \.element.id) { index, batch in
                    if index > 0 { Hairline() }
                    batchRow(batch)
                    if opened.contains(batch.id) {
                        batchItems(batch)
                    }
                }
            }
        }
    }

    private func batchRow(_ batch: CollectBatch) -> some View {
        HStack(spacing: 10) {
            Button {
                if opened.contains(batch.id) { opened.remove(batch.id) } else { opened.insert(batch.id) }
            } label: {
                Image(systemName: opened.contains(batch.id) ? "chevron.down" : "chevron.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(opened.contains(batch.id)
                                ? "Hide what was moved"
                                : "Show what was moved")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(batch.queryLabel.isEmpty ? "Moved out" : batch.queryLabel)
                        .font(.body.weight(.medium))
                    Image(systemName: "arrow.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(batch.destinationName)
                        .font(.body)
                }
                Text("\(batch.count) \(batch.count == 1 ? "item" : "items") · \(Self.bytes.string(fromByteCount: batch.byteSize)) · \(when(batch.date))")
                    .explanation()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if !batch.isReachable {
                Text(batch.unreachableReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button("Put Back") { controller.undoCollection(batch) }
                .disabled(controller.collecting || !batch.isReachable)
        }
        .padding(12)
    }

    private func batchItems(_ batch: CollectBatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(batch.items.prefix(3), id: \.path) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.originFolder.isEmpty ? "was loose in Downloads" : "was in \(item.originFolder)/")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            if batch.items.count > 3 {
                Text("and \(batch.items.count - 3) more")
                    .font(.callout)
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.leading, 22)
    }

    // MARK: Editing

    private func addPlace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder to move things into."

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard let place = CollectDestination.make(name: folder.lastPathComponent, folder: folder) else { return }

        settings.collectDestinations.append(place)
        toggleEditor(for: place)
    }

    private func toggleEditor(for place: CollectDestination) {
        if editing == place.id {
            commit(place)
            return
        }
        editing = place.id
        nameDraft = place.name
    }

    private func commit(_ place: CollectDestination) {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = settings.collectDestinations.firstIndex(where: { $0.id == place.id })
        else { return }
        settings.collectDestinations[index].name = name
        editing = nil
    }

    private func remove(_ place: CollectDestination) {
        // Only the app forgets it. Nothing that went there is touched: those
        // files are somebody's, in a folder they chose.
        settings.collectDestinations.removeAll { $0.id == place.id }
        editing = nil
    }

    private func templateBinding(for place: CollectDestination) -> Binding<String> {
        Binding(
            get: { settings.collectDestinations.first { $0.id == place.id }?.template ?? "" },
            set: { text in
                guard let index = settings.collectDestinations.firstIndex(where: { $0.id == place.id })
                else { return }
                settings.collectDestinations[index].template = text
            }
        )
    }

    private func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "today \(Self.time.string(from: date))"
            : Self.day.string(from: date)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
