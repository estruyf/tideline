import SwiftUI

/// The question a fresh install has to answer before anything moves. Tideline
/// rearranges a folder people care about, and doing that the moment the window
/// opens is a decision the app has taken on someone's behalf. So it asks — with
/// the rule it would follow, and what that first sweep would actually do to the
/// folder as it stands right now.
struct WelcomeView: View {
    @Binding var isPresented: Bool

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var controller = Controller.shared

    /// What a sweep would move, worked out for this sheet and nothing else.
    @State private var plan: SweepPlan?
    @State private var looked = false
    /// Access can arrive twice — the sheet appears, then the permission lands —
    /// and a second look started over the first is what leaves a spinner up
    /// after the answer has already come back.
    @State private var looking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            VStack(alignment: .leading, spacing: 14) {
                rule
                Hairline()

                switch controller.access {
                case .notAsked: permission
                case .unknown: asking
                case .granted: firstSweep
                case .denied, .missing: blocked
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Hairline()
            footer
        }
        .sheetSurface(width: 520, height: 460)
        .onAppear(perform: look)
        .onChange(of: controller.access) { _, _ in
            // The sheet opens before macOS has been asked, so the figure it
            // wants cannot be worked out yet. Permission arriving is the cue
            // to go and get it.
            look()
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIconImage(size: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tideline is not filing yet")
                    .font(.title3.weight(.semibold))
                Text("Nothing has moved, and nothing will until you say so.")
                    .explanation()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .sheetBand()
    }

    /// The rule, in the same words the README opens with, filled in with the
    /// settings this particular install would use.
    private var rule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Today's downloads stay loose in \(settings.downloadsURL.lastPathComponent)")
            } icon: {
                Image(systemName: "tray")
                    .foregroundStyle(Theme.accentText)
            }

            Label {
                Text(olderRule)
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accentText)
            }

            Label {
                Text("Nothing is deleted, nothing is overwritten, and every move is in the activity log")
            } icon: {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundStyle(Theme.accentText)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The state a fresh install opens in. macOS has not been asked anything
    /// yet — the app has not so much as listed the folder — so the window gets
    /// to say what the permission is for before the system alert lands on top
    /// of it.
    private var permission: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("First, the folder")
                .font(.callout.weight(.semibold))

            Text("Tideline has not looked at \(settings.downloadsURL.lastPathComponent) yet. macOS will ask whether it may — that prompt is scoped to this one folder, and nothing else on the disk becomes readable by allowing it.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Allowing it is not the same as starting: the folder is read so this sheet can tell you what a first sweep would do, and nothing moves until you say so below.")
                .explanation()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var asking: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for macOS…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var firstSweep: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The first sweep")
                .font(.callout.weight(.semibold))

            if !looked {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking at the folder…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("You can change the rules under Filing first, or switch on preview mode to watch a sweep without it touching anything.")
                .explanation()
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// No access means no sweep and no figure to quote, so the sheet says what
    /// is wrong and offers the two ways back rather than a dead button.
    private var blocked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("macOS is not letting Tideline read the folder", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.danger)

            Text("Choosing the folder yourself grants the same permission the prompt asked for.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Choose Downloads Folder…") { controller.chooseDownloadsFolder() }
                Button("Open Privacy Settings") { controller.openPrivacySettings() }
                Button("Check Again") { controller.refreshAccess { look() } }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(footerNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Not Yet") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            if controller.access == .notAsked {
                Button("Allow Access…") { controller.requestAccess() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start Filing") {
                    controller.startFiling()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.access.isUsable)
            }
        }
        .sheetBand()
    }

    // MARK: - Behaviour

    private func look() {
        guard controller.access.isUsable, !looking else { return }
        looking = true
        looked = false
        controller.inspectPlan { found in
            plan = found
            looking = false
            looked = true
        }
    }

    // MARK: - Labels

    private var footerNote: String {
        if controller.access == .notAsked {
            return "Nothing is read, and nothing is moved, until you press the button."
        }
        return "You can pause filing at any time with the switch at the top of the window."
    }

    private var olderRule: String {
        settings.folderFormat == .monthly
            ? "Anything older moves into a folder named for the month it arrived"
            : "Anything older moves into a folder named for the day it arrived"
    }

    private var summary: String {
        guard let plan else {
            return "The folder could not be read, so there is nothing to report yet."
        }
        guard !plan.moves.isEmpty else {
            return "Nothing in \(settings.downloadsURL.lastPathComponent) is old enough to file — \(plan.inspected) \(plan.inspected == 1 ? "item is" : "items are") staying exactly where they are."
        }

        let folders = Set(plan.moves.map(\.targetFolder)).count
        let items = plan.moves.count
        return "\(items) \(items == 1 ? "item" : "items") would move into \(folders) \(folders == 1 ? "folder" : "folders"). \(plan.leftAlone) \(plan.leftAlone == 1 ? "item stays" : "items stay") loose."
    }
}
