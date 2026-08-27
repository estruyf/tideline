import SwiftUI

/// Putting it back: everything sitting in a folder Tideline made, grouped by
/// the folder it would come out of. Untick anything you would rather leave
/// filed. Nothing moves until this sheet says so.
struct RestoreView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @State private var selection: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            Group {
                if !didLoad {
                    scanning
                } else if controller.restorable.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .sheetBody()

            Hairline()
            footer
        }
        .sheetSurface(width: 520, height: 480)
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Put everything back", systemImage: "arrow.uturn.backward")
                .font(.headline)

            Text("Everything Tideline filed moves back into \(settings.downloadsURL.lastPathComponent), and the folders it leaves empty go to the Trash. Filing switches off afterwards, so the next sweep does not undo this.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheetBand()
    }

    private var scanning: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Looking through the folders Tideline made…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("There is nothing filed to put back")
                .font(.body.weight(.medium))
            Text("No dated folders and no type folders with anything in them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.folder) { group in
                Section {
                    ForEach(group.items) { candidate in
                        Toggle(isOn: binding(for: candidate)) {
                            HStack(spacing: 8) {
                                Text(candidate.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(Self.bytes.string(fromByteCount: candidate.byteSize))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    HStack {
                        Label(group.folder, systemImage: group.isByType ? "shippingbox" : "folder")
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
        .sheetList()
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
                    Text("A name already taken in the root counts up — report.pdf, report-1.pdf.")
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
                .disabled(selection.isEmpty || controller.restoring)
        }
        .sheetBand()
    }

    // MARK: - Behaviour

    private func load() {
        didLoad = false
        controller.findRestorable { found in
            selection = Set(found.map(\.id))
            didLoad = true
        }
    }

    private func apply() {
        let picked = controller.restorable.filter { selection.contains($0.id) }
        controller.restore(picked) { _ in isPresented = false }
    }

    private func binding(for candidate: RestoreCandidate) -> Binding<Bool> {
        Binding(
            get: { selection.contains(candidate.id) },
            set: { isOn in
                if isOn { selection.insert(candidate.id) } else { selection.remove(candidate.id) }
            }
        )
    }

    // MARK: - Grouping

    /// One section per folder it would come out of, newest first, the way the
    /// scan found them — so the list reads as the folder does.
    private struct SourceGroup {
        var folder: String
        var isByType: Bool
        var items: [RestoreCandidate]
    }

    private var groups: [SourceGroup] {
        var order: [String] = []
        var byFolder: [String: [RestoreCandidate]] = [:]

        for candidate in controller.restorable {
            if byFolder[candidate.currentFolder] == nil { order.append(candidate.currentFolder) }
            byFolder[candidate.currentFolder, default: []].append(candidate)
        }

        return order.map {
            SourceGroup(
                folder: $0,
                isByType: byFolder[$0]?.first?.isByType ?? false,
                items: byFolder[$0] ?? []
            )
        }
    }

    private func allSelected(in group: SourceGroup) -> Bool {
        group.items.allSatisfy { selection.contains($0.id) }
    }

    private func toggleAll(in group: SourceGroup) {
        if allSelected(in: group) {
            for item in group.items { selection.remove(item.id) }
        } else {
            for item in group.items { selection.insert(item.id) }
        }
    }

    // MARK: - Labels

    private var chosen: [RestoreCandidate] {
        controller.restorable.filter { selection.contains($0.id) }
    }

    private var actionTitle: String {
        let count = chosen.count
        let noun = count == 1 ? "Item" : "Items"
        if settings.dryRun { return "Preview Putting \(count) \(noun) Back" }
        return count == 0 ? "Put Back" : "Put \(count) \(noun) Back"
    }

    private var tally: String {
        guard !controller.restorable.isEmpty else { return "" }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.byteSize }
        let folders = Set(chosen.map(\.currentFolder)).count
        let noun = folders == 1 ? "folder" : "folders"
        return "\(chosen.count) of \(controller.restorable.count) selected · out of \(folders) \(noun) · \(Self.bytes.string(fromByteCount: bytes))"
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
