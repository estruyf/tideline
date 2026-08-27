import AppKit
import SwiftUI

// MARK: - General tab

/// The full picture: which version is running, when it last looked, and
/// whatever the last check turned up.
struct UpdateSection: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(checkedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Now") { updater.check(userInitiated: true) }
                    .disabled(updater.state.isBusy)
            }
        } label: {
            Text("This copy")
            Text("Version \(AppInfo.version)")
        }

        Toggle(isOn: $settings.automaticUpdateChecks) {
            Text("Check for updates automatically")
            Text("Once a day, over the GitHub releases page. Nothing is ever downloaded or installed without you saying so.")
        }

        Toggle(isOn: $settings.notifyOnUpdate) {
            Text("Notify me when a new version is out")
            Text("A notice in Notification Centre, once per version, and only for a check that ran on its own — asking here always answers in the window instead. It appears where you have already allowed Tideline to notify you; finding an update is not a reason to ask.")
        }
        // A notice can only come from a check, so the switch means nothing
        // without one. Turning it on is the moment to ask for permission;
        // finding an update is not.
        .disabled(!settings.automaticUpdateChecks)
        .onChange(of: settings.notifyOnUpdate) { _, newValue in
            if newValue { Controller.shared.requestNotificationPermission() }
        }

        if !updater.canSelfUpdate {
            Label("This build is not running from an installed app, so it can't replace itself.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        UpdateStatusView(compact: false)
    }

    private var checkedText: String {
        guard let checked = updater.lastCheckedAt else { return "Never checked" }
        return "Checked \(Controller.relative.localizedString(for: checked, relativeTo: Date()))"
    }
}

// MARK: - Status tab

/// A quieter version of the same thing, shown on Status only while there is
/// genuinely something new to say.
struct UpdateBanner: View {
    var body: some View {
        UpdateStatusView(compact: true)
    }
}

// MARK: - Shared body

private struct UpdateStatusView: View {
    /// The Status tab card leaves out the notes and the up-to-date line.
    let compact: Bool

    @ObservedObject private var updater = Updater.shared

    var body: some View {
        switch updater.state {
        case .idle:
            if let release = updater.nag {
                AvailableCard(release: release, compact: compact)
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub for a newer version…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            if !compact {
                Label("Tideline \(AppInfo.version) is the latest release.", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            }

        case .available(let release):
            AvailableCard(release: release, compact: compact)

        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading Tideline \(updater.pending?.version.description ?? "")…")
                    .font(.callout.weight(.medium))
                ProgressView(value: fraction)
                Text(fraction > 0 ? "\(Int(fraction * 100))% of \(updater.pending?.sizeText ?? "")" : "Starting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the download is signed by the same developer…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .restarting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing and restarting…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("The update did not go through", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.danger)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Download from GitHub") { updater.openReleasePage() }
                    Button("Dismiss") { updater.dismissFailure() }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 2)
        }
    }
}

private struct AvailableCard: View {
    let release: Release
    let compact: Bool

    @ObservedObject private var updater = Updater.shared
    @State private var showingNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.accentText)
                Text("Tideline \(release.version.description) is available")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Text([release.releasedText, release.sizeText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("You are running \(AppInfo.version). The update is downloaded from GitHub, checked against this app's own signature, and only then swapped in — Tideline restarts once it is done.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !compact, !release.notes.isEmpty {
                DisclosureGroup("What's new", isExpanded: $showingNotes) {
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .frame(maxHeight: 160)
                }
                .font(.caption.weight(.medium))
            }

            HStack {
                Button("Update & Restart") { updater.install(release) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updater.canSelfUpdate || updater.state.isBusy)

                Button("Release Notes") { NSWorkspace.shared.open(release.page) }

                Spacer()

                Button("Skip This Version") { updater.skip(release) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    /// GitHub bodies are markdown; keeping the line breaks matters more here
    /// than rendering headings, so only inline styling is interpreted.
    private var notes: AttributedString {
        (try? AttributedString(
            markdown: release.notes,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(release.notes)
    }
}
