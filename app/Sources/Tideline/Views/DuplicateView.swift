import SwiftUI

/// Collapsing duplicates: the same file, downloaded twice, sitting in the
/// folder twice under two names. Each group keeps a copy and sends the rest to
/// the Trash — never all of them, and never until this sheet says so.
struct DuplicateView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    /// The copies ticked to go. Everything but the newest of each group starts
    /// ticked, which is the answer nine times in ten.
    @State private var doomed: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            Group {
                if !didLoad {
                    scanning
                } else if controller.duplicates.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .sheetBody()

            Hairline()
            footer
        }
        .sheetSurface(width: 560, height: 500)
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("The same file, more than once", systemImage: "doc.on.doc")
                .font(.headline)

            Text("Files with the same name — bar a copy suffix — and byte-for-byte the same contents. The newest of each is kept and the rest go to the Trash.")
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
            Text("Comparing files…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Only files that already share a name and a size are read through.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing is here twice")
                .font(.body.weight(.medium))
            Text("No file in \(settings.downloadsURL.lastPathComponent), or in the folders Tideline made, matches another by name and contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
    }

    private var list: some View {
        List {
            ForEach(controller.duplicates) { group in
                Section {
                    ForEach(group.copies) { copy in
                        row(copy, in: group)
                    }
                } header: {
                    HStack {
                        Label(group.baseName, systemImage: "doc.on.doc")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(detail(for: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheetList()
    }

    private func row(_ copy: DuplicateCopy, in group: DuplicateGroup) -> some View {
        let isGoing = doomed.contains(copy.id)

        return HStack(spacing: 8) {
            Toggle(isOn: binding(for: copy, in: group)) {
                HStack(spacing: 8) {
                    Text(copy.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(isGoing, color: .secondary)
                        .foregroundStyle(isGoing ? Color.secondary : Color.primary)

                    if !isGoing {
                        Text("keeping")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.14), in: Capsule())
                    }
                }
            }
            .toggleStyle(.checkbox)
            .help(isGoing ? "Send this copy to the Trash" : "This copy stays")

            Spacer(minLength: 12)

            Text(copy.folder)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.hover, in: Capsule())

            Text(Self.day.string(from: copy.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .trailing)

            // The copies are byte-for-byte the same, so this is never about
            // which one to keep — it is about seeing what the thing actually is
            // before agreeing that nine of them can go.
            Button {
                controller.reveal(copy.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show \(copy.name) in Finder")
        }
        .contextMenu {
            Button("Show in Finder") { controller.reveal(copy.url) }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tally)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.dryRun {
                    Text("Preview mode — nothing will actually be trashed.")
                        .font(.caption)
                        .foregroundStyle(Theme.accentText)
                } else {
                    Text("Copies go to the Trash, so nothing is lost until you empty it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $settings.duplicateRestoreNames) {
                    Text("Give the copy that stays its plain name back")
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("artifact-1.zip becomes artifact.zip, but only where that name is free.")
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle) { collapse() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(doomed.isEmpty || controller.collapsing)
            }
        }
        .sheetBand()
    }

    // MARK: - Behaviour

    private func load() {
        didLoad = false
        controller.findDuplicates { found in
            // Everything but the newest of each group, which is the one at the top.
            doomed = Set(found.flatMap { $0.copies.dropFirst().map(\.id) })
            didLoad = true
        }
    }

    private func collapse() {
        controller.collapse(controller.duplicates, removing: doomed) { _ in isPresented = false }
    }

    /// Unticking is always allowed; ticking is refused when it would leave the
    /// group with nothing. A duplicate set always keeps a copy.
    private func binding(for copy: DuplicateCopy, in group: DuplicateGroup) -> Binding<Bool> {
        Binding(
            get: { doomed.contains(copy.id) },
            set: { isOn in
                guard isOn else {
                    doomed.remove(copy.id)
                    return
                }
                let keptElsewhere = group.copies.contains { $0.id != copy.id && !doomed.contains($0.id) }
                guard keptElsewhere else { return }
                doomed.insert(copy.id)
            }
        )
    }

    // MARK: - Labels

    private func detail(for group: DuplicateGroup) -> String {
        let each = Self.bytes.string(fromByteCount: group.byteSize)
        let count = group.copies.count
        return "\(count) copies · \(each) each"
    }

    private var actionTitle: String {
        let count = doomed.count
        let noun = count == 1 ? "Copy" : "Copies"
        if settings.dryRun { return "Preview Trashing \(count) \(noun)" }
        return count == 0 ? "Move to Trash" : "Move \(count) \(noun) to Trash"
    }

    private var tally: String {
        guard !controller.duplicates.isEmpty else { return "" }
        let bytes = controller.duplicates
            .flatMap(\.copies)
            .filter { doomed.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.byteSize }
        let sets = controller.duplicates.count
        let noun = sets == 1 ? "file" : "files"
        return "\(sets) \(noun) here more than once · \(doomed.count) selected · \(Self.bytes.string(fromByteCount: bytes)) back"
    }

    private static let bytes = FolderUsage.bytes

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
