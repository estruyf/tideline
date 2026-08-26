import SwiftUI

/// Catching up: everything already filed by date that the type folders now
/// claim, grouped by where it would go. Uncheck anything you would rather leave
/// where it is. Nothing moves until this sheet says so.
struct RegroupView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @State private var selection: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Group {
                if !didLoad {
                    scanning
                } else if controller.regroupable.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: 520, height: 480)
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Catch up on what's already filed", systemImage: "arrow.triangle.branch")
                .font(.headline)

            Text("Switching a type folder on only changes where new downloads go. These are files already sitting in a dated folder that the rules now claim.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var scanning: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Looking through the dated folders…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(hasRules ? "Everything is already where it belongs" : "No type folders are switched on")
                .font(.body.weight(.medium))
            Text(hasRules
                 ? "Nothing in the dated folders matches a type folder you have switched on."
                 : "Switch one on under Filing, then come back here to catch up.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.target) { group in
                Section {
                    ForEach(group.items) { candidate in
                        Toggle(isOn: binding(for: candidate)) {
                            HStack(spacing: 8) {
                                Text(candidate.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(candidate.currentFolder)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    HStack {
                        Label(group.target, systemImage: "folder")
                        Spacer()
                        Button(allSelected(in: group) ? "None" : "All") {
                            toggleAll(in: group)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tally)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.dryRun {
                    Text("Preview mode — nothing will actually move.")
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                } else if !chosen.isEmpty {
                    Text("A dated folder left empty by this goes to the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            Button(actionTitle) { apply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || controller.regrouping)
        }
        .padding(20)
    }

    // MARK: - Behaviour

    private func load() {
        didLoad = false
        controller.findRegroupable { found in
            selection = Set(found.map(\.id))
            didLoad = true
        }
    }

    private func apply() {
        let picked = controller.regroupable.filter { selection.contains($0.id) }
        controller.regroup(picked) { _ in isPresented = false }
    }

    private func binding(for candidate: RegroupCandidate) -> Binding<Bool> {
        Binding(
            get: { selection.contains(candidate.id) },
            set: { isOn in
                if isOn { selection.insert(candidate.id) } else { selection.remove(candidate.id) }
            }
        )
    }

    // MARK: - Grouping

    /// One section per destination, in the order the folders were found, so the
    /// list reads as "here is what Installers would take, here is Images".
    private struct TargetGroup {
        var target: String
        var items: [RegroupCandidate]
    }

    private var groups: [TargetGroup] {
        var order: [String] = []
        var byTarget: [String: [RegroupCandidate]] = [:]

        for candidate in controller.regroupable {
            if byTarget[candidate.targetFolder] == nil { order.append(candidate.targetFolder) }
            byTarget[candidate.targetFolder, default: []].append(candidate)
        }

        return order.map { TargetGroup(target: $0, items: byTarget[$0] ?? []) }
    }

    private func allSelected(in group: TargetGroup) -> Bool {
        group.items.allSatisfy { selection.contains($0.id) }
    }

    private func toggleAll(in group: TargetGroup) {
        if allSelected(in: group) {
            for item in group.items { selection.remove(item.id) }
        } else {
            for item in group.items { selection.insert(item.id) }
        }
    }

    // MARK: - Labels

    private var hasRules: Bool {
        settings.typeRules.contains { $0.isEnabled && !$0.extensions.isEmpty }
    }

    private var chosen: [RegroupCandidate] {
        controller.regroupable.filter { selection.contains($0.id) }
    }

    private var actionTitle: String {
        let count = chosen.count
        let noun = count == 1 ? "Item" : "Items"
        if settings.dryRun { return "Preview Moving \(count) \(noun)" }
        return count == 0 ? "Move" : "Move \(count) \(noun)"
    }

    private var tally: String {
        guard !controller.regroupable.isEmpty else { return "" }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.byteSize }
        let folders = Set(chosen.map(\.targetFolder)).count
        let noun = folders == 1 ? "folder" : "folders"
        return "\(chosen.count) of \(controller.regroupable.count) selected · \(folders) \(noun) · \(Self.bytes.string(fromByteCount: bytes))"
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
