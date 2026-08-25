import SwiftUI

/// What a sweep would move, grouped by where it would go. Preview mode used to
/// say this in the log alone; this is the same answer where the other two
/// review sheets put theirs — on screen, before anything happens.
///
/// Nothing here has an action: the sweep that produced it touched nothing, and
/// the list is what it would have done.
struct PreviewView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            Group {
                if controller.plan.isEmpty {
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
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What a sweep would move", systemImage: "eye")
                .font(.headline)

            Text("Preview mode is on, so nothing was touched. This is where each item would have gone, had it not been.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing is due to move")
                .font(.body.weight(.medium))
            Text("Everything in \(settings.downloadsURL.lastPathComponent) is either inside the window you leave loose, or on the list of things never to touch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.folder) { group in
                Section {
                    ForEach(group.items) { move in
                        HStack(spacing: 8) {
                            Image(systemName: move.isFolder ? "folder" : "doc")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(move.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(Self.bytes.string(fromByteCount: move.byteSize))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    HStack {
                        Label(group.folder, systemImage: group.isByType ? "tag" : "folder")
                        Spacer()
                        Text(group.isByType ? "by type" : "by date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                Text("Preview mode — nothing was moved. Switch it off under Filing to let a sweep do this for real.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Done") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    // MARK: - Grouping

    private struct FolderGroup {
        var folder: String
        var isByType: Bool
        var items: [PlannedMove]
    }

    /// One section per destination, in the order the sweep would create them.
    private var groups: [FolderGroup] {
        var order: [String] = []
        var byFolder: [String: [PlannedMove]] = [:]

        for move in controller.plan {
            if byFolder[move.targetFolder] == nil { order.append(move.targetFolder) }
            byFolder[move.targetFolder, default: []].append(move)
        }

        return order.map {
            let items = byFolder[$0] ?? []
            return FolderGroup(folder: $0, isByType: items.first?.isByType ?? false, items: items)
        }
    }

    private var tally: String {
        let count = controller.plan.count
        guard count > 0 else { return "Checked \(settings.downloadsURL.lastPathComponent), found nothing due" }
        let bytes = controller.plan.reduce(Int64(0)) { $0 + $1.byteSize }
        let noun = count == 1 ? "item" : "items"
        let folders = Set(controller.plan.map(\.targetFolder)).count
        let where_ = folders == 1 ? "1 folder" : "\(folders) folders"
        return "\(count) \(noun) · \(Self.bytes.string(fromByteCount: bytes)) · into \(where_)"
    }

    private static let bytes = FolderUsage.bytes
}
