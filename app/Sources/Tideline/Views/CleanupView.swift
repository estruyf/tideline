import SwiftUI

/// The manual path: see exactly which folders qualify, uncheck any you want to
/// keep, then send the rest to the Trash. Nothing is removed until this sheet says so.
struct CleanupView: View {
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
                } else if controller.clearable.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .sheetBody()

            Hairline()
            footer
        }
        .sheetSurface(width: 480, height: 460)
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Clearing out", systemImage: "trash")
                .font(.headline)

            Text("Dated folders Tideline made, older than \(Self.window(settings.cleanupAfterDays)). They go to the Trash, so nothing here is lost until you empty it.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheetBand()
    }

    private var scanning: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Measuring folders…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing is old enough to clear")
                .font(.body.weight(.medium))
            Text("The newest \(settings.cleanupKeepNewest) \(settings.cleanupKeepNewest == 1 ? "folder stays" : "folders stay") whatever their age.")
                .explanation()
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var list: some View {
        List {
            ForEach(controller.clearable) { candidate in
                Toggle(isOn: binding(for: candidate)) {
                    HStack(spacing: 8) {
                        Text(candidate.name)
                            .font(.body.monospacedDigit())
                        Spacer(minLength: 12)
                        Text(detail(for: candidate))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .sheetList()
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tally)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if settings.dryRun {
                    Text("Preview mode — nothing will actually move.")
                        .explanation()
                        .foregroundStyle(Theme.accentText)
                }
            }

            Spacer(minLength: 0)

            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            Button(actionTitle) { clear() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || controller.clearing)
        }
        .sheetBand()
    }

    // MARK: - Behaviour

    private func load() {
        didLoad = false
        // Selecting from the scan's own result, rather than watching `clearable`:
        // a rescan that finds the very same folders is not a change to observe.
        controller.findClearable { candidates in
            selection = Set(candidates.map(\.id))
            didLoad = true
        }
    }

    private func clear() {
        let chosen = controller.clearable.filter { selection.contains($0.id) }
        controller.clear(chosen) { _ in isPresented = false }
    }

    private func binding(for candidate: CleanupCandidate) -> Binding<Bool> {
        Binding(
            get: { selection.contains(candidate.id) },
            set: { isOn in
                if isOn { selection.insert(candidate.id) } else { selection.remove(candidate.id) }
            }
        )
    }

    private var chosen: [CleanupCandidate] {
        controller.clearable.filter { selection.contains($0.id) }
    }

    private var actionTitle: String {
        let count = chosen.count
        let noun = count == 1 ? "Folder" : "Folders"
        if settings.dryRun { return "Preview Clearing \(count) \(noun)" }
        return count == 0 ? "Move to Trash" : "Move \(count) \(noun) to Trash"
    }

    private var tally: String {
        guard !controller.clearable.isEmpty else { return "" }
        let bytes = chosen.reduce(Int64(0)) { $0 + $1.byteSize }
        let approximate = chosen.contains(where: \.sizeIsPartial)
        let size = Self.bytes.string(fromByteCount: bytes)
        return "\(chosen.count) of \(controller.clearable.count) selected · \(approximate ? "more than " : "")\(size)"
    }

    private func detail(for candidate: CleanupCandidate) -> String {
        let noun = candidate.itemCount == 1 ? "item" : "items"
        let size = Self.bytes.string(fromByteCount: candidate.byteSize)
        return "\(candidate.itemCount) \(noun) · \(candidate.sizeIsPartial ? "more than " : "")\(size)"
    }

    /// "90 days" reads better than "90 days" everywhere except the round months.
    static func window(_ days: Int) -> String {
        switch days {
        case 30: return "a month"
        case 90: return "three months"
        case 180: return "six months"
        case 365: return "a year"
        default: return "\(days) days"
        }
    }

    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
