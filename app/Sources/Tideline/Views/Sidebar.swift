import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case overview, reclaim, schedule, filing, typeFolders, clearing, activity, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .reclaim: return "Reclaim space"
        case .schedule: return "Schedule"
        case .filing: return "Filing"
        case .typeFolders: return "Type folders"
        case .clearing: return "Clearing"
        case .activity: return "Activity log"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "info.circle"
        case .reclaim: return "trash"
        case .schedule: return "clock"
        case .filing: return "arrow.down.doc"
        case .typeFolders: return "folder"
        case .clearing: return "clock.arrow.circlepath"
        case .activity: return "list.bullet"
        case .general: return "gearshape"
        }
    }
}

/// The window's spine. A hand-rolled list rather than `NavigationSplitView`:
/// the tabs are a fixed set that never pushes anything, and the sidebar carries
/// a running badge and a footer that a split view has nowhere to put.
struct Sidebar: View {
    @Binding var selection: MainTab

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    /// The three panes on Reclaim space share one badge, because they share one
    /// question: how much of this could go.
    private var waiting: Int {
        controller.duplicates.count + controller.largeFiles.count + controller.clearable.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            item(.overview)
            item(.reclaim, badge: waiting)

            groupHeader("Rules")
            item(.schedule)
            item(.filing)
            item(.typeFolders)
            item(.clearing)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)

            item(.activity)
            item(.general)

            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 200, alignment: .leading)
        .background(sidebarBackground)
    }

    /// A flat fill rather than `.regularMaterial`: the theme's sidebar is a
    /// solid colour, and translucency would let whatever is behind the window
    /// tint it away from the palette every other surface is pinned to.
    private var sidebarBackground: some View {
        Rectangle()
            .fill(Theme.chrome)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Theme.border).frame(width: 1)
            }
            .ignoresSafeArea()
    }

    private func item(_ tab: MainTab, badge: Int = 0) -> some View {
        SidebarItem(
            tab: tab,
            badge: badge,
            isSelected: selection == tab
        ) {
            withAnimation(.easeOut(duration: 0.12)) { selection = tab }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 9)
            .padding(.top, 12)
            .padding(.bottom, 3)
    }

    /// Which folder all of this is about, and what it is holding. It belongs in
    /// the corner rather than in a pane — it is true on every one of them.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(shortPath)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.head)
            Text(holdings)
                .font(.caption2)
                .foregroundStyle(Theme.faint)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 9)
        .padding(.bottom, 2)
        .help(settings.downloadsPath)
    }

    private var shortPath: String {
        settings.downloadsPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var holdings: String {
        guard let usage = controller.usage else {
            return controller.access.isUsable ? "Measuring…" : "Not measured"
        }
        let filed = usage.managedFolders
        let noun = filed == 1 ? "folder" : "folders"
        return "\(usage.totalDescription) · \(filed) \(noun)"
    }
}

private struct SidebarItem: View {
    let tab: MainTab
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accentText : Theme.muted)
                    .frame(width: 16)

                Text(tab.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 6)

                if badge > 0 {
                    // Four figures would push the title into a second line, and
                    // past a hundred the exact count is not what you act on.
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.onAccent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(badge > 0 ? "\(tab.title), \(badge) waiting" : tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fill)
    }

    private var fill: Color {
        if isSelected { return Theme.selection }
        return isHovering ? Theme.hover : .clear
    }
}
