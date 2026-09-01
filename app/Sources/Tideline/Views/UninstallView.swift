import AppKit
import SwiftUI

struct UninstallView: View {
    @Binding var isPresented: Bool
    @State private var confirming = false

    private var paths: [String] {
        [
            "~/Library/Application Support/Tideline",
            "~/Library/Logs/Tideline.log",
            "~/Library/Preferences/be.eliostruyf.Tideline.plist",
            Bundle.main.bundleURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            VStack(alignment: .leading, spacing: 14) {
                steps
                deletions
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Hairline()
            footer
        }
        .sheetSurface(width: 470, height: 470)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Uninstall Tideline")
                .font(.title3.weight(.semibold))

            Text("Your downloads and every dated folder stay exactly where they are. Only the app and its own settings go away.")
                .explanation()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheetBand()
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Step(number: 1, title: "Let the app clean up after itself",
                 detail: "Removes the login item, the saved settings, the history and the log file, then quits.")
            Step(number: 2, title: "Drag the app to the Trash",
                 detail: "Finder opens on the app once it has quit.")
            Step(number: 3, title: "Optional: clear the permission",
                 detail: "System Settings › Privacy & Security › Files and Folders, then remove Tideline.")
        }
    }

    private var deletions: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("What gets deleted")
                    .panelHeader()

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(paths, id: \.self) { path in
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)

            Spacer(minLength: 0)

            Button(confirming ? "Really Remove & Quit" : "Clean Up & Quit") {
                if confirming {
                    uninstall()
                } else {
                    confirming = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(confirming ? Theme.danger : Theme.accent)
        }
        .sheetBand()
    }

    private func uninstall() {
        Controller.shared.removeTraces()
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // A filled badge, so it takes the colour that goes on the accent
            // rather than the label colour the system would pick.
            Text("\(number)")
                .font(.callout.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
