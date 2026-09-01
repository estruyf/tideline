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

/// A settings pane: cards on the pane's own ground, scrolling together.
///
/// `Form { Section }` drew these until now, and drew them in the *system's*
/// grouped-form colours — the last surface where the palette stopped at the
/// pane and the card inside it still belonged to macOS. A grouped `Section`
/// cannot be handed a background, so the panes build their own out of the same
/// `ListPanel` that Overview, Reclaim space and Routing rules already use.
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.pane)
    }
}

/// One card in a settings pane: what the group is, the rows, and the sentence
/// underneath that says what to expect of them.
///
/// Rows put their own `Hairline()` between themselves, the way every other list
/// in the window does — a card cannot know where its children end.
struct SettingsGroup<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ListPanel { content }

            if let footer {
                Text(footer)
                    .explanation()
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// A row that is a switch and the sentence explaining it.
///
/// The label stays inside the `Toggle` rather than being drawn beside one, so
/// clicking the words still flips the switch — which is what a grouped `Form`
/// gave for free and what anybody who has used one expects.
struct SettingsToggle: View {
    var title: String
    var explanation: String?
    @Binding var isOn: Bool

    init(_ title: String, _ explanation: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.explanation = explanation
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsLabel(title: title, explanation: explanation)
        }
        .toggleStyle(.switch)
        .settingsRow()
    }
}

/// A row that is a control with a name beside it — a popup, a stepper, a
/// button that opens something.
struct SettingsField<Control: View>: View {
    var title: String
    var explanation: String?
    @ViewBuilder var control: Control

    init(_ title: String, _ explanation: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.explanation = explanation
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SettingsLabel(title: title, explanation: explanation)
            Spacer(minLength: 12)
            control
        }
        .settingsRow()
    }
}

/// The name of a setting and the line under it. One shape, so a switch and a
/// popup describe themselves the same way.
struct SettingsLabel: View {
    var title: String
    var explanation: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let explanation {
                Text(explanation)
                    .explanation()
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `LabeledContent` outside a `Form` has no column to line its labels up in,
/// so a stack of them steps in and out as the words change length. This is that
/// column: a fixed-width name, then the control filling the rest.
struct SettingsLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.label
                .foregroundStyle(Theme.muted)
                .frame(width: 110, alignment: .leading)
            configuration.content
        }
    }
}

extension LabeledContentStyle where Self == SettingsLabeledContentStyle {
    static var settings: SettingsLabeledContentStyle { SettingsLabeledContentStyle() }
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
        font(.callout.weight(.semibold))
            .foregroundStyle(Theme.muted)
    }

    /// The padding every row in a settings card shares, so a row built by hand
    /// lines up with the ones `SettingsToggle` and `SettingsField` draw.
    func settingsRow() -> some View {
        padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Explanatory prose: the sentence under a heading, the note beside a
    /// control, the line that says what a setting will do.
    ///
    /// One step down from body, never two. The app had settled on `.caption`
    /// for this, which is the size for a number in a column rather than for
    /// something somebody actually has to read — a pane of it reads as small
    /// before it reads as anything else. Colour is left to the caller, since
    /// the same sentence is sometimes secondary and sometimes a warning.
    func explanation() -> some View {
        font(.callout)
    }

    /// A button that only navigates — it opens Finder, or moves you to another
    /// pane. The theme gives those its link blue rather than the accent, so a
    /// yellow control always means something is about to happen to a file.
    func linkButton() -> some View {
        buttonStyle(.link).foregroundStyle(Theme.link)
    }

    /// A text field on a card.
    ///
    /// `.roundedBorder` draws the *system* control background, which is one of
    /// the last surfaces the palette never reached — every field in the window
    /// sat in a grey the theme does not own, on cards it does. This is the
    /// recipe the Move out search box had already built by hand, named so the
    /// next field does not have to build it again: the pane colour recessed
    /// into the card it sits on, the theme's own hairline around it, and the
    /// accent while it has the keyboard.
    ///
    /// `icon` puts a symbol inside the box, on the left, the way a search field
    /// carries its magnifying glass.
    func themedField(icon: String? = nil) -> some View {
        modifier(ThemedField(icon: icon))
    }
}

private struct ThemedField: ViewModifier {
    var icon: String?

    /// Drawn rather than inherited: `.plain` gives up the system focus ring
    /// along with the system background, and a field with no sign of having the
    /// keyboard is worse than one in the wrong grey.
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(Theme.muted)
            }
            content
                .textFieldStyle(.plain)
                .focused($focused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.pane, in: shape)
        // `strokeBorder` insets, so the thicker focused edge is drawn inside
        // the same box and nothing around it moves when the field is clicked.
        .overlay(shape.strokeBorder(focused ? Theme.accentText : Theme.border,
                                    lineWidth: focused ? 1.5 : 1))
        .contentShape(shape)
        // The padding and the icon are part of the field as far as anyone
        // clicking is concerned, which is what `.roundedBorder` gave for free.
        // Simultaneous, not `.onTapGesture`: a plain gesture on the box wins
        // the click outright and the field never becomes first responder, so
        // clicking a field would stop working altogether.
        .simultaneousGesture(TapGesture().onEnded { focused = true })
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6) }
}

extension View {
    /// A sheet window. macOS hands a sheet the system window background, which
    /// is the one surface in the app the theme never reached — every review
    /// sheet sat on grey while the window behind it was `#15181f`. This paints
    /// it, and the two helpers below put the same chrome-over-pane sandwich
    /// inside it that the window itself uses.
    func sheetSurface(width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height)
            .background(Theme.pane)
            // A sheet is its own window, and the tint `MainView` sets does not
            // reach across — so the confirming button and every checkbox came
            // up in the system blue. This hands the sheet the app's accent the
            // same way the window hands it to its own controls.
            .tint(Theme.accent)
    }

    /// A sheet's header or footer. The window puts its chrome colour behind the
    /// header band and the sidebar; a sheet does the same above and below its
    /// list, so the two read as the same window.
    func sheetBand() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.chrome)
    }

    /// The ground between the two bands — a shade back from the chrome, the way
    /// a pane sets itself off from the header.
    func sheetBody() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pane)
    }

    /// A list filling a sheet's body. `List` paints its own system background,
    /// which would leave that grey slab back between the bands.
    func sheetList() -> some View {
        listStyle(.inset)
            .scrollContentBackground(.hidden)
    }
}
