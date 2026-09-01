import AppKit
import QuickLookUI

/// Quick Look, the way the space bar does it in Finder.
///
/// Deciding whether a file really is an invoice is a question about what is
/// inside it, and a list of names cannot answer it. This opens the same panel
/// Finder does, so a doubtful row can be looked at before it is ticked.
///
/// `QLPreviewPanel` is one shared panel for the whole app, and it normally asks
/// the responder chain who is driving. A SwiftUI sheet is not usefully in that
/// chain, so this takes the panel directly: it holds the list, hands itself over
/// as the data source, and keeps the items alive for as long as the panel is up.
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()

    private var items: [URL] = []

    /// Opens the panel on one file, with the rest of the list behind it so the
    /// arrow keys walk the same rows the sheet is showing.
    func show(_ url: URL, within list: [URL] = []) {
        let all = list.contains(url) ? list : [url]
        items = all

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = all.firstIndex(of: url) ?? 0

        if panel.isVisible {
            panel.orderFront(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard items.indices.contains(index) else { return nil }
        // `NSURL` is what conforms to `QLPreviewItem`; a Swift `URL` does not.
        return items[index] as NSURL
    }
}
