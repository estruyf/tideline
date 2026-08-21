import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case status, schedule, filing, clearing, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .schedule: return "Schedule"
        case .filing: return "Filing"
        case .clearing: return "Clearing"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "gauge"
        case .schedule: return "clock"
        case .filing: return "arrow.down.doc"
        case .clearing: return "trash"
        case .general: return "gearshape"
        }
    }
}

/// A flat tab strip. `TabView` on macOS draws a bordered box around its content,
/// which sits badly around a grouped form — this keeps the chrome to one row.
struct TabStrip: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                TabStripButton(tab: tab, isSelected: selection == tab) {
                    withAnimation(.easeOut(duration: 0.12)) { selection = tab }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct TabStripButton: View {
    let tab: MainTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(fill)
    }

    private var fill: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }
}
