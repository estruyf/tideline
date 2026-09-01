import SwiftUI

/// The big ones. Filing tidies a folder; it never shrinks one, and this is
/// where that gets dealt with: the largest files in the root and in the folders
/// Tideline made, biggest first, each one openable in Finder before you decide.
///
/// Nothing starts ticked. A duplicate always leaves a copy behind — a big file
/// is the only copy there is, so every row here is a deliberate choice.
struct LargeFileView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    @State private var doomed: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            Group {
                if !didLoad {
                    scanning
                } else if controller.largeFiles.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .sheetBody()

            Hairline()
            footer
        }
        .sheetSurface(width: 580, height: 520)
        .onAppear(perform: load)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What is taking up the room", systemImage: "scalemass")
                .font(.headline)

            Text("The biggest files in \(settings.downloadsURL.lastPathComponent), and in the folders Tideline made. Nothing is ticked for you — have a look in Finder first, then send what you are done with to the Trash.")
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
            Text("Measuring files…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing in there is that big")
                .font(.body.weight(.medium))
            Text("No file over \(Self.threshold(settings.largeFileThresholdMB)). Try a smaller size below — folders you made yourself are never looked in.")
                .explanation()
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
    }

    private var list: some View {
        List {
            ForEach(controller.largeFiles) { file in
                row(file)
            }
        }
        .sheetList()
    }

    private func row(_ file: LargeFile) -> some View {
        let isGoing = doomed.contains(file.id)

        return HStack(spacing: 8) {
            Toggle(isOn: binding(for: file)) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .strikethrough(isGoing, color: .secondary)
                    .foregroundStyle(isGoing ? Color.secondary : Color.primary)
            }
            .toggleStyle(.checkbox)
            .help(isGoing ? "Send this file to the Trash" : "This file stays")

            Spacer(minLength: 12)

            Text(Self.bytes.string(fromByteCount: file.byteSize))
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(width: 80, alignment: .trailing)

            Text(file.folder)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.hover, in: Capsule())

            Text(Self.day.string(from: file.date))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)

            Button {
                controller.reveal(file.url)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show \(file.name) in Finder")
                .accessibilityLabel("Show \(file.name) in Finder")
        }
        .contextMenu {
            Button("Show in Finder") { controller.reveal(file.url) }
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tally)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if settings.dryRun {
                    Text("Preview mode — nothing will actually be trashed.")
                        .explanation()
                        .foregroundStyle(Theme.accentText)
                } else {
                    Text("Files go to the Trash, so nothing is lost until you empty it.")
                        .explanation()
                        .foregroundStyle(.secondary)
                }

                // Kept beside the list rather than only in settings: the right
                // size to ask about is the one that shows you something.
                Picker("Bigger than", selection: $settings.largeFileThresholdMB) {
                    ForEach(Settings.largeFileThresholds, id: \.self) { megabytes in
                        Text(Self.threshold(megabytes)).tag(megabytes)
                    }
                }
                .pickerStyle(.menu)
                .font(.callout)
                .fixedSize()
                .onChange(of: settings.largeFileThresholdMB) { _, _ in load() }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(actionTitle) { trim() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(doomed.isEmpty || controller.trimming)
            }
        }
        .sheetBand()
    }

    // MARK: - Behaviour

    private func load() {
        didLoad = false
        // Ticks are dropped on every scan: a row that is no longer listed must
        // never stay selected behind the sheet's back.
        doomed = []
        controller.findLargeFiles { _ in didLoad = true }
    }

    private func trim() {
        controller.trim(controller.largeFiles, removing: doomed) { _ in isPresented = false }
    }

    private func binding(for file: LargeFile) -> Binding<Bool> {
        Binding(
            get: { doomed.contains(file.id) },
            set: { isOn in
                if isOn { doomed.insert(file.id) } else { doomed.remove(file.id) }
            }
        )
    }

    // MARK: - Labels

    private var actionTitle: String {
        let count = doomed.count
        let noun = count == 1 ? "File" : "Files"
        if settings.dryRun { return "Preview Trashing \(count) \(noun)" }
        return count == 0 ? "Move to Trash" : "Move \(count) \(noun) to Trash"
    }

    private var tally: String {
        guard !controller.largeFiles.isEmpty else { return "" }
        let total = controller.largeFiles.reduce(Int64(0)) { $0 + $1.byteSize }
        let chosen = controller.largeFiles
            .filter { doomed.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.byteSize }
        let count = controller.largeFiles.count
        let noun = count == 1 ? "file" : "files"
        return "\(count) \(noun) · \(Self.bytes.string(fromByteCount: total)) between them · \(doomed.count) selected · \(Self.bytes.string(fromByteCount: chosen)) back"
    }

    /// "500 MB", "1 GB" — the same units the rows are measured in.
    static func threshold(_ megabytes: Int) -> String {
        bytes.string(fromByteCount: Int64(megabytes) * 1_000_000)
    }

    private static let bytes = FolderUsage.bytes

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
