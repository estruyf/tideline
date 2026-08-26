import SwiftUI

/// The card the panes are built out of. `Form` draws these for a list of
/// settings; Overview and Reclaim space are not lists of settings, so they get
/// the same rounded, bordered box by hand and stay recognisably the same window.
struct Panel<Content: View>: View {
    var padding: CGFloat = 13
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.border))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8) }
}

/// A panel whose own rows draw the padding, so a list can run edge to edge and
/// its dividers can reach the border.
struct ListPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: shape)
            .overlay(shape.strokeBorder(Theme.border))
            .clipShape(shape)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8) }
}

/// `Divider()` draws a system grey that sits outside the palette. This is the
/// same hairline in the theme's own border colour.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

extension View {
    /// The ground the cards sit on — a shade back from a card, the way a
    /// grouped form sets itself off from its rows.
    func paneBackground() -> some View {
        background(Theme.pane)
    }

    /// The heading inside a card: what this box is, in as few words as it takes.
    func panelHeader() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(Theme.muted)
    }

    /// A settings pane. `Form` paints its own ground, which would leave a grey
    /// slab between two themed panes — this hands it the pane colour instead.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.pane)
    }

    /// A button that only navigates — it opens Finder, or moves you to another
    /// pane. The theme gives those its link blue rather than the accent, so a
    /// yellow control always means something is about to happen to a file.
    func linkButton() -> some View {
        buttonStyle(.link).foregroundStyle(Theme.link)
    }
}
