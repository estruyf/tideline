import SwiftUI
import UniformTypeIdentifiers

/// Folders that claim files by what they are called or where they came from.
///
/// The order is the whole model — rules are tried top down and the first match
/// wins — so the list is numbered and draggable, and every row says what it
/// catches, where that goes, and how many files that is right now. A rule
/// written blind is the thing this pane exists to prevent: a pattern with a
/// typo looks exactly like one that works until you can see it matching nothing.
struct RoutingRulePane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    /// The rule whose editor is open, by id. Only one at a time — a second one
    /// open would be an inspector column, and this is a single view.
    @State private var editing: String?
    /// How each condition of the open rule is currently spelled, so the popups
    /// do not rewrite themselves under someone mid-word.
    @State private var spellings: [UUID: Spelling] = [:]
    @State private var showingAllMatches = false

    /// The row a dragged rule would land on.
    @State private var dropTarget: String?
    /// Counting walks the folder, so it happens a beat after the typing stops.
    @State private var pending: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heading
                order
                list
                footnote
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.pane)
        .onAppear { controller.inspectRules() }
        .onChange(of: matchSignature) { _, _ in scheduleCount() }
        // The destination follows the name being typed on its own, so renaming
        // a folder does not drag the whole count along behind it.
        .onChange(of: openFolder) { _, folder in controller.checkDestination(folder) }
        // A sweep, a catch-up or a change of folder throws the count away,
        // because it was about a folder that has since moved on. The pane is
        // the only thing that reads it, so the pane is what asks again.
        .onChange(of: controller.ruleReport.isFresh) { _, fresh in
            if !fresh { scheduleCount() }
        }
    }

    // MARK: - Heading

    private var heading: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Routing rules")
                    .font(.title2.weight(.semibold))
                Text("A rule sends matching files to a folder at the root instead of the dated folder.")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: addRule) {
                Label("New rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Rules, then type folders, then the date. Drawn once, because it is the
    /// sequence the whole pane depends on and a paragraph saying it in prose is
    /// a paragraph nobody reads twice.
    private var order: some View {
        Panel(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("A new file is checked in this order")
                        .font(.callout.weight(.medium))

                    step("1", "Routing rules", isHere: true)
                    arrow
                    Button { controller.reveal = .typeFolders } label: {
                        step("2", "Type folders", isHere: false)
                    }
                    .buttonStyle(.plain)
                    .help("Open Type folders")
                    arrow
                    step("3", "Dated folder", isHere: false)

                    Spacer(minLength: 0)
                }

                Text(settings.rules.count > 1
                     ? "The first rule that matches wins — drag to change which that is."
                     : "The first rule that matches wins.")
                    .explanation()
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.callout)
            .foregroundStyle(Theme.muted)
    }

    private func step(_ number: String, _ label: String, isHere: Bool) -> some View {
        HStack(spacing: 5) {
            Text(number).monospacedDigit()
            Text(label)
        }
        .font(.callout.weight(isHere ? .semibold : .regular))
        .foregroundStyle(isHere ? Theme.onAccent : Theme.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isHere ? Theme.accent : Theme.hover, in: Capsule())
    }

    // MARK: - The list

    @ViewBuilder
    private var list: some View {
        if settings.rules.isEmpty {
            empty
        } else {
            ListPanel {
                ForEach(Array(settings.rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Hairline() }

                    VStack(alignment: .leading, spacing: 0) {
                        // The line a drop would land on, drawn above the row it
                        // would take the place of.
                        Rectangle()
                            .fill(dropTarget == rule.id ? Theme.accent : .clear)
                            .frame(height: 2)

                        // Only the row is draggable. The editor below it is full
                        // of text fields, and a drag started inside one of those
                        // is somebody selecting a word.
                        row(rule, at: index)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                            .draggable(rule.id) {
                                Text(rule.displayName).padding(6)
                            }
                            .contextMenu { menu(for: rule, at: index) }

                        if editing == rule.id {
                            Hairline()
                            editor(rule, at: index)
                                .padding(13)
                                .background(Theme.pane)
                        }
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let dragged = items.first else { return false }
                        return move(dragged, to: index)
                    } isTargeted: { targeted in
                        dropTarget = targeted ? rule.id : (dropTarget == rule.id ? nil : dropTarget)
                    }
                }
            }
        }
    }

    private var empty: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("No rules yet")
                    .font(.callout.weight(.medium))
                Text("A rule is a folder and the conditions that send files to it. An invoice is a PDF like every other PDF, so what marks it out is its name or the site it came from.")
                    .explanation()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: some View {
        Label(
            "Anything no rule claims still waits out the window set under Filing, then goes to its dated folder.",
            systemImage: "info.circle"
        )
        .explanation()
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - One row

    private func row(_ rule: Rule, at index: Int) -> some View {
        let finding = controller.ruleReport[rule]

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.callout)
                .foregroundStyle(Theme.faint)
                .help("Drag to change the order")
                .accessibilityHidden(true)

            Text("\(index + 1)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .frame(width: 16, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if !rule.folder.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "arrow.right")
                            .font(.callout)
                            .foregroundStyle(Theme.faint)
                        Label("\(rule.folder)/", systemImage: "folder")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }

                subtitle(rule, finding: finding)
            }
            .opacity(rule.isEnabled ? 1 : 0.55)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                countLabel(rule, finding: finding)
                secondaryAction(rule, finding: finding)
            }

            Toggle("", isOn: binding(for: rule).isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(rule.displayName)

            Button {
                toggleEditor(rule)
            } label: {
                Image(systemName: editing == rule.id ? "chevron.up" : "chevron.down")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help(editing == rule.id ? "Close" : "Edit \(rule.displayName)")
            .accessibilityLabel(editing == rule.id ? "Close" : "Edit \(rule.displayName)")
        }
    }

    /// The rule itself, in words — the second line was a subtitle that lied
    /// until you opened it, and now it is what the rule actually asks.
    @ViewBuilder
    private func subtitle(_ rule: Rule, finding: RuleFinding?) -> some View {
        if !rule.isEnabled {
            Text("Off — files fall through to the dated folder")
                .explanation()
                .foregroundStyle(Theme.muted)
        } else if let shadowedBy = finding?.shadowedBy, let count = finding?.shadowedCount {
            Label(
                "Never fires — \(shadowedBy) catches all \(count) of these first",
                systemImage: "exclamationmark.triangle"
            )
            .explanation()
            .foregroundStyle(Theme.accentText)
        } else if rule.filledTests.isEmpty {
            Text("Nothing to match on yet — open it and add a condition")
                .explanation()
                .foregroundStyle(Theme.muted)
        } else {
            Text(sentence(for: rule))
                .explanation()
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
    }

    /// `name contains invoice, or downloaded from is stripe.com`. The joiner is
    /// the rule's own — a rule that needs every condition reads *and*.
    private func sentence(for rule: Rule) -> String {
        let joiner = rule.match == .all ? ", and " : ", or "
        return rule.filledTests.compactMap(\.sentence).joined(separator: joiner)
    }

    @ViewBuilder
    private func countLabel(_ rule: Rule, finding: RuleFinding?) -> some View {
        if !controller.ruleReport.isFresh {
            Text("counting…")
                .explanation()
                .foregroundStyle(Theme.faint)
        } else if rule.filledTests.isEmpty || finding?.isShadowed == true {
            // A rule with nothing written down has nothing to count, and a
            // number beside "never fires" would only argue with it.
            EmptyView()
        } else if let finding, finding.loose > 0 {
            // A rule that is switched off is being weighed up rather than run,
            // and the count is the argument for switching it on.
            Text(rule.isEnabled
                 ? "\(finding.loose) \(finding.loose == 1 ? "file" : "files") match"
                 : "\(finding.loose) would match")
                .explanation()
                .foregroundStyle(rule.isEnabled ? Theme.text : Theme.muted)
        } else {
            Text("nothing loose matches")
                .explanation()
                .foregroundStyle(Theme.faint)
        }
    }

    /// The one thing worth offering from a row: reaching back for what a rule
    /// would have caught, or straightening out a rule that can never fire.
    @ViewBuilder
    private func secondaryAction(_ rule: Rule, finding: RuleFinding?) -> some View {
        if let target = finding?.shadowedByIndex, rule.isEnabled {
            Button("Move above \(settings.rules[target].displayName)") {
                move(rule.id, to: target)
            }
            .buttonStyle(.link)
            .foregroundStyle(Theme.accentText)
            .font(.callout)
        } else if let filed = finding?.filedByDate, filed > 0, rule.isEnabled {
            Button("\(filed) filed by date — catch up…") {
                controller.reviewingRegroup = true
            }
            .buttonStyle(.link)
            .foregroundStyle(Theme.accentText)
            .font(.callout)
        }
    }

    @ViewBuilder
    private func menu(for rule: Rule, at index: Int) -> some View {
        Button("Move Up") { move(rule.id, to: index - 1) }
            .disabled(index == 0)
        Button("Move Down") { move(rule.id, to: index + 1) }
            .disabled(index == settings.rules.count - 1)
        Button("Move to Top") { move(rule.id, to: 0) }
            .disabled(index == 0)
        Divider()
        Button("Duplicate") { duplicate(rule, at: index) }
        Button("Delete Rule", role: .destructive) { remove(rule) }
    }

    // MARK: - The editor

    private func editor(_ rule: Rule, at index: Int) -> some View {
        let binding = binding(for: rule)
        let finding = controller.ruleReport[rule]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Rule \(index + 1) of \(settings.rules.count)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: Capsule())
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Rule name") {
                    TextField(
                        "Rule name",
                        text: Binding(
                            get: { rule.title ?? rule.name },
                            // Taking focus writes the field's own value straight
                            // back. A rule that has only ever been known by its
                            // folder must not gain a title of the same words
                            // just because somebody clicked in it — that is a
                            // change to the rules, and a change to the rules is
                            // a fresh count.
                            set: { typed in
                                guard typed != (rule.title ?? rule.name) else { return }
                                binding.wrappedValue.title = typed
                            }
                        ),
                        prompt: Text("What to call it in this list")
                    )
                    .labelsHidden()
                    .themedField()
                }
                .labeledContentStyle(.settings)

                LabeledContent("Send them to") {
                    TextField("Folder", text: binding.name, prompt: Text("Invoices"))
                        .labelsHidden()
                        .themedField(icon: "folder")
                }
                .labeledContentStyle(.settings)

                destinationNote(rule)
            }

            conditions(rule, binding: binding)

            preview(rule, finding: finding)

            HStack {
                Button("Delete rule", role: .destructive) { remove(rule) }
                Spacer()
                Text("Saved as you type")
                    .explanation()
                    .foregroundStyle(Theme.faint)
                Button("Done") { close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
    }

    /// Where the files will actually end up, spelled out as a path, and whether
    /// that folder is already there. The destination is the point of the rule,
    /// so it should never be possible to wonder what it means.
    @ViewBuilder
    private func destinationNote(_ rule: Rule) -> some View {
        let folder = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if !Rule.isValidFolderName(folder) {
            Text("Pick a name that is not empty, has no slashes, and does not read as a date.")
                .explanation()
                .foregroundStyle(Theme.danger)
        } else {
            let root = settings.downloadsURL.lastPathComponent
            // An answer about a folder that has since been renamed is not an
            // answer about this one, so the line waits rather than saying
            // something true of a name nobody is looking at any more.
            let check = controller.destination?.folder == folder ? controller.destination : nil
            let state = check.map { found in
                found.exists
                    ? "exists, \(found.items) \(found.items == 1 ? "item" : "items")"
                    : "will be made the first time something lands there"
            }

            (Text("~/\(root)/\(folder)/").monospaced() + Text(state.map { " · \($0)" } ?? ""))
                .explanation()
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    // MARK: Conditions

    private func conditions(_ rule: Rule, binding: Binding<Rule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Catch a file when")
                Picker("", selection: binding.match) {
                    ForEach(RuleMatch.allCases) { match in
                        Text(match.label).tag(match)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Any or all conditions")
                Text(rule.match == .all ? "of these are true" : "of these is true")
            }
            .font(.callout)

            ForEach(rule.tests) { test in
                conditionRow(test, in: binding)
            }

            HStack(spacing: 10) {
                Button {
                    var updated = binding.wrappedValue
                    let test = RuleTest()
                    updated.tests.append(test)
                    spellings[test.id] = Spelling()
                    binding.wrappedValue = updated
                } label: {
                    Label("Add a condition", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accentText)

                Text("The name, or the site it came from")
                    .explanation()
                    .foregroundStyle(Theme.faint)
            }
            .controlSize(.small)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }

    private func conditionRow(_ test: RuleTest, in rule: Binding<Rule>) -> some View {
        let spelling = spellings[test.id] ?? Spelling(test)

        return HStack(spacing: 8) {
            Picker("", selection: field(of: test, in: rule)) {
                ForEach(RuleField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            .accessibilityLabel("What to look at")

            Picker("", selection: op(of: test, in: rule)) {
                ForEach(RuleOperator.allCases) { op in
                    Text(op.label).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .accessibilityLabel("How to compare it")

            TextField(
                "",
                text: value(of: test, in: rule),
                prompt: Text(spelling.op == .glob
                             ? currentField(test, in: rule).placeholder
                             : currentField(test, in: rule).valueHint)
            )
            .labelsHidden()
            .themedField()
            .accessibilityLabel("What to look for")

            Toggle("Match case", isOn: matchCase(of: test, in: rule))
                .toggleStyle(.checkbox)
                .help("Compare exactly, upper and lower case included")

            Button {
                var updated = rule.wrappedValue
                updated.tests.removeAll { $0.id == test.id }
                spellings[test.id] = nil
                rule.wrappedValue = updated
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this condition")
            .accessibilityLabel("Remove this condition")
        }
        .controlSize(.small)
    }

    // MARK: Preview

    /// What the rule is claiming right now, with the condition that claimed
    /// each file beside it. A pattern that catches too much is obvious here and
    /// invisible everywhere else.
    @ViewBuilder
    private func preview(_ rule: Rule, finding: RuleFinding?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Matching right now")
                    .font(.callout.weight(.medium))

                Text(tally(for: rule, finding: finding))
                    .explanation()
                    .foregroundStyle(Theme.muted)

                Spacer(minLength: 12)

                if let filed = finding?.filedByDate, filed > 0 {
                    Button("Catch up on the \(filed)…") { controller.reviewingRegroup = true }
                        .buttonStyle(.link)
                        .foregroundStyle(Theme.accentText)
                        .font(.callout)
                }
            }

            if let finding, !finding.samples.isEmpty {
                let shown = showingAllMatches ? finding.samples : Array(finding.samples.prefix(3))

                ForEach(shown) { sample in
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.callout)
                            .foregroundStyle(Theme.faint)
                        Text(sample.name)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(sample.isFiledByDate ? "\(sample.reason) · in \(sample.place)" : sample.reason)
                            .explanation()
                            .foregroundStyle(Theme.faint)
                            .lineLimit(1)
                    }
                }

                if finding.samples.count > 3 {
                    Button(showingAllMatches
                           ? "show fewer"
                           : "\(finding.samples.count - 3) more · show all \(finding.samples.count)") {
                        showingAllMatches.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .foregroundStyle(Theme.accentText)
                }

                if finding.hasMoreThanSampled {
                    Text("Only the first \(finding.samples.count) are listed.")
                        .explanation()
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }

    private func tally(for rule: Rule, finding: RuleFinding?) -> String {
        guard controller.ruleReport.isFresh else { return "counting…" }
        guard !rule.filledTests.isEmpty else { return "nothing yet — a rule with no conditions claims nothing" }
        guard let finding else { return "nothing in the folder matches" }

        guard finding.total > 0 else {
            return finding.takenAbove > 0
                ? "nothing — a rule above claims all \(finding.takenAbove) of these first"
                : "nothing in the folder matches"
        }

        let root = settings.downloadsURL.lastPathComponent
        var parts = ["\(finding.loose) in \(root)"]
        if finding.filedByDate > 0 { parts.append("\(finding.filedByDate) already filed by date") }
        // The files this rule describes and a rule above it takes. Worth
        // saying: it is the difference between a pattern that is wrong and a
        // list that is in the wrong order.
        if finding.takenAbove > 0 { parts.append("\(finding.takenAbove) taken by a rule above") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Editing

    /// Rules live in an array on `Settings`, so a row edits through its id
    /// rather than an index that a removal could shift out from under it.
    private func binding(for rule: Rule) -> Binding<Rule> {
        Binding(
            get: { settings.rules.first { $0.id == rule.id } ?? rule },
            set: { updated in
                guard let index = settings.rules.firstIndex(where: { $0.id == rule.id }) else { return }
                settings.rules[index] = updated
            }
        )
    }

    /// The three bindings a condition row needs. The operator and the words are
    /// held apart from the pattern they compose into, because deriving them
    /// back out on every keystroke would rewrite the popup under someone's
    /// fingers the moment they typed a `*`.
    private func field(of test: RuleTest, in rule: Binding<Rule>) -> Binding<RuleField> {
        Binding(
            get: { current(test, in: rule)?.field ?? test.field },
            set: { chosen in
                var updated = rule.wrappedValue
                guard let index = updated.tests.firstIndex(where: { $0.id == test.id }) else { return }
                updated.tests[index].field = chosen
                rule.wrappedValue = updated
            }
        )
    }

    private func op(of test: RuleTest, in rule: Binding<Rule>) -> Binding<RuleOperator> {
        Binding(
            get: { (spellings[test.id] ?? Spelling(test)).op },
            set: { chosen in
                var spelling = spellings[test.id] ?? Spelling(test)
                spelling.value = RuleOperator.reword(spelling.value, from: spelling.op, to: chosen)
                spelling.op = chosen
                spellings[test.id] = spelling
                store(spelling, for: test, in: rule)
            }
        )
    }

    private func value(of test: RuleTest, in rule: Binding<Rule>) -> Binding<String> {
        Binding(
            get: { (spellings[test.id] ?? Spelling(test)).value },
            set: { typed in
                var spelling = spellings[test.id] ?? Spelling(test)
                spelling.value = typed
                spellings[test.id] = spelling
                store(spelling, for: test, in: rule)
            }
        )
    }

    private func matchCase(of test: RuleTest, in rule: Binding<Rule>) -> Binding<Bool> {
        Binding(
            get: { current(test, in: rule)?.matchCase ?? test.matchCase },
            set: { wanted in
                var updated = rule.wrappedValue
                guard let index = updated.tests.firstIndex(where: { $0.id == test.id }) else { return }
                updated.tests[index].matchCase = wanted
                rule.wrappedValue = updated
            }
        )
    }

    private func current(_ test: RuleTest, in rule: Binding<Rule>) -> RuleTest? {
        rule.wrappedValue.tests.first { $0.id == test.id }
    }

    private func currentField(_ test: RuleTest, in rule: Binding<Rule>) -> RuleField {
        current(test, in: rule)?.field ?? test.field
    }

    private func store(_ spelling: Spelling, for test: RuleTest, in rule: Binding<Rule>) {
        var updated = rule.wrappedValue
        guard let index = updated.tests.firstIndex(where: { $0.id == test.id }) else { return }
        updated.tests[index].pattern = spelling.op.pattern(for: spelling.value)
        rule.wrappedValue = updated
    }

    private func toggleEditor(_ rule: Rule) {
        if editing == rule.id { return close() }
        open(rule)
    }

    /// A rule with nothing to ask about opens with an empty condition rather
    /// than an empty list, so there is somewhere to type.
    private func open(_ rule: Rule) {
        // Only one editor at a time, so whatever was open is tidied away first
        // — otherwise "New rule" twice leaves an untouched rule behind.
        tidy()

        var opened = rule
        if opened.tests.isEmpty {
            opened.tests = [RuleTest()]
            binding(for: rule).wrappedValue = opened
        }
        spellings = Dictionary(uniqueKeysWithValues: opened.tests.map { ($0.id, Spelling($0)) })
        showingAllMatches = false
        editing = rule.id
    }

    private func close() {
        tidy()
        editing = nil
        spellings = [:]
    }

    /// What the rule being edited is worth keeping.
    private func tidy() {
        guard let editing, let index = settings.rules.firstIndex(where: { $0.id == editing })
        else { return }

        // A rule opened, looked at and closed again without a word written in
        // it is not a rule. Dropping it keeps "New rule" from being a way to
        // leave empty rows behind.
        let rule = settings.rules[index]
        if rule.filledTests.isEmpty,
           rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (rule.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.rules.remove(at: index)
            return
        }

        // A condition nobody filled in is not a condition. Keeping it would
        // claim nothing but would read as though the rule asked more than it
        // does — and under *all* it would stop the rule matching anything.
        settings.rules[index].tests = rule.filledTests
    }

    // MARK: - Adding, moving, removing

    /// A new rule opens straight into its editor with one empty condition: the
    /// conditions are the whole of it, and asking for a name and then hiding
    /// them would be a form with the interesting half missing. It arrives
    /// switched off, because a rule that files things before anybody has
    /// written what it catches is a rule nobody asked for.
    private func addRule() {
        let rule = Rule(name: "", isEnabled: false, tests: [RuleTest()])
        settings.rules.append(rule)
        open(rule)
    }

    private func duplicate(_ rule: Rule, at index: Int) {
        var copy = rule
        copy.id = UUID().uuidString
        copy.title = "\(rule.displayName) copy"
        copy.tests = rule.tests.map { RuleTest(field: $0.field, pattern: $0.pattern, matchCase: $0.matchCase) }
        copy.isEnabled = false
        settings.rules.insert(copy, at: index + 1)
    }

    private func remove(_ rule: Rule) {
        if editing == rule.id { editing = nil; spellings = [:] }
        settings.rules.removeAll { $0.id == rule.id }
    }

    /// Moves a rule to a place in the list. Order is the model, so this is the
    /// one edit the pane makes that changes what a sweep would do.
    @discardableResult
    private func move(_ id: String, to index: Int) -> Bool {
        guard let from = settings.rules.firstIndex(where: { $0.id == id }) else { return false }
        let to = max(0, min(index, settings.rules.count - 1))
        guard from != to else { return false }

        var rules = settings.rules
        let rule = rules.remove(at: from)
        rules.insert(rule, at: to)
        settings.rules = rules
        dropTarget = nil
        return true
    }

    // MARK: - Counting

    /// What a count actually depends on: which rules are switched on, in what
    /// order, and what each of them asks.
    ///
    /// Deliberately not the names. Typing a rule's name changes nothing about
    /// what it matches, and counting on every keystroke put the preview list —
    /// and so everything below it — through a fresh height on every letter.
    /// A form must not move under the pointer while it is being filled in.
    /// The folder of the rule whose editor is open, as it currently reads.
    private var openFolder: String? {
        guard let editing else { return nil }
        return settings.rules
            .first { $0.id == editing }?
            .folder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchSignature: String {
        settings.rules.map { rule in
            let tests = rule.filledTests
                .map { "\($0.field.rawValue)\u{1}\($0.pattern)\u{1}\($0.matchCase)" }
                .joined(separator: "\u{2}")
            return "\(rule.id)\u{3}\(rule.isEnabled)\u{3}\(rule.match.rawValue)\u{3}\(tests)"
        }
        .joined(separator: "\u{4}")
    }

    /// Counted a beat behind the typing. Every keystroke walking the root and
    /// every dated folder would make the field unusable.
    private func scheduleCount() {
        pending?.cancel()
        let work = DispatchWorkItem { controller.inspectRules() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// One condition as the editor is currently showing it: the operator picked and
/// the words typed, before they are composed back into a glob.
private struct Spelling: Equatable {
    var op: RuleOperator = .contains
    var value: String = ""

    init() {}

    init(_ test: RuleTest) {
        let spelled = test.spelledOut
        op = spelled.op
        value = spelled.value
    }
}
