import AppKit
import SwiftUI

/// The window's palette, taken from the Demo Time theme so the app and the
/// editor it was written in look like they belong together.
///
/// Every token carries a light value and a dark one and resolves through
/// `NSColor(name:dynamicProvider:)`, so the window still follows the system
/// appearance — switching to Light mode swaps the whole set, it does not leave
/// dark cards on a white page. What it no longer follows is the *system accent*:
/// `#ffd43b` is the app's own. `.tint` in `MainView` hands it to every control
/// in the window; a sheet is a window of its own and the tint does not cross,
/// so `sheetSurface` sets it again on that side.
enum Theme {

    // MARK: Brand

    /// Filled surfaces only — buttons, badges, the selected row. It is a bright
    /// yellow, so it never carries white text.
    static let accent = dynamic(light: 0xffd43b, dark: 0xffd43b)

    /// What sits *on* accent. Near-black in both appearances; white on `#ffd43b`
    /// is unreadable.
    static let onAccent = dynamic(light: 0x15181f, dark: 0x15181f)

    /// Accent as text or an icon. Yellow on white fails to read, so the light
    /// side darkens to the theme's own `focusBorder` rather than inventing one.
    static let accentText = dynamic(light: 0xa08000, dark: 0xffd43b)

    /// Accent behind a selected row, at the weight the theme uses for
    /// `list.activeSelectionBackground`.
    static var selection: Color { accent.opacity(0.18) }

    // MARK: Surfaces

    /// The header band and the sidebar — the chrome around the panes.
    static let chrome = dynamic(light: 0xf4f6fa, dark: 0x202736)

    /// The ground a pane's cards sit on. The darkest surface, as the editor
    /// background is in the theme.
    static let pane = dynamic(light: 0xf8f9fb, dark: 0x15181f)

    /// A card on a pane, and the row backgrounds inside one.
    static let card = dynamic(light: 0xffffff, dark: 0x202736)

    /// A row under the pointer, and the fill behind a small inset control.
    static let hover = dynamic(light: 0xe1e4e8, dark: 0x2d3142)

    /// Every hairline: card borders, dividers, the sidebar's edge.
    static let border = dynamic(light: 0xbcc4d1, dark: 0x374151)

    // MARK: Text

    static let text = dynamic(light: 0x202736, dark: 0xd9dbe1)
    static let muted = dynamic(light: 0x505869, dark: 0x9ba4b7)
    /// A third step down, for a note that should be there without being read.
    static let faint = dynamic(light: 0x6b7280, dark: 0x6b7280)

    // MARK: Meaning

    /// Something is wrong and the app cannot get on with it — no access, a
    /// failed move. Never the same colour as "here is something to look at".
    static let danger = dynamic(light: 0xd73a49, dark: 0xff6b6b)

    /// Running, watching, nothing to do.
    static let success = dynamic(light: 0x00b8a2, dark: 0x51cf66)

    /// A link, or a button that only navigates.
    static let link = dynamic(light: 0x005cc5, dark: 0x74c0fc)

    /// The chrome as an `NSColor`, for the one place AppKit asks rather than
    /// SwiftUI: the window's own background behind the transparent titlebar.
    static let chromeNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(hex: isDark ? 0x202736 : 0xf4f6fa)
    }

    // MARK: Building

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    /// `0xffd43b` as it is written in the theme file, so a token can be checked
    /// against the source by eye.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
