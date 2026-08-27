import AppKit
import SwiftUI

/// The bundle's real icon, drawn straight from the app itself rather than
/// approximated with an SF Symbol — the window and the Dock cannot drift apart.
struct AppIconImage: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// `applicationIconImage` is what the Dock shows. Unbundled — a plain
    /// `swift run` — it falls back to the icns, then to the old symbol. The menu
    /// bar's title card reads it too, so all three show the one icon.
    static var icon: NSImage {
        if let running = NSApp?.applicationIconImage { return running }
        if let bundled = NSImage(named: "AppIcon") { return bundled }
        return NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: nil) ?? NSImage()
    }
}
