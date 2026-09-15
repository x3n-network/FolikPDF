import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appLock: AppLockManager

    private let companyWebsite = URL(string: "https://x3n.network")!
    private let openSourceWebsite = URL(string: "https://www.x3n.network/opensource/folik/")!
    private let feedbackEmail = URL(string: "mailto:team@x3n.network?subject=Folik%20Feedback")!
    private let standardEULA = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    private var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        FolikWordmark()
                        Text("A capable PDF workspace with no accounts, ads, subscriptions, or in-app purchases.")
                            .font(.body)
                            .foregroundStyle(FolikTheme.mutedInk)
                            .multilineTextAlignment(.center)
                        Text(versionDescription)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowBackground(Color.clear)
                }

                Section("Library") {
                    NavigationLink { RecentlyDeletedView() } label: {
                        Label("Recently Deleted", systemImage: "trash")
                    }
                    .accessibilityIdentifier("settings.recentlyDeleted")
                }

                Section("Help") {
                    NavigationLink {
                        FolikHelpView()
                    } label: {
                        Label("Using Folik", systemImage: "questionmark.circle")
                    }
                    .accessibilityIdentifier("settings.help")
                }

                Section("Automation") {
                    ShortcutsLink()
                        .accessibilityIdentifier("settings.shortcuts")
                    Text("Use Sanitize PDF in Shortcuts, Siri, Spotlight, or an automation. Processing stays on-device and returns a new file without changing the original.")
                        .font(.footnote)
                        .foregroundStyle(FolikTheme.mutedInk)
                }

                Section("X3N") {
                    Link(destination: companyWebsite) {
                        ExternalLinkRow(
                            title: "Company Website",
                            detail: "x3n.network",
                            systemImage: "globe"
                        )
                    }
                    .accessibilityIdentifier("settings.website")
                    .accessibilityLabel("Company Website, x3n.network")
                    .accessibilityHint("Opens in your browser")

                    Link(destination: openSourceWebsite) {
                        ExternalLinkRow(
                            title: "Open Source Project",
                            detail: "Source code, license, and contributions",
                            systemImage: "chevron.left.forwardslash.chevron.right"
                        )
                    }
                    .accessibilityIdentifier("settings.openSource")
                    .accessibilityLabel("Folik Open Source Project")
                    .accessibilityHint("Opens the Folik open source website in your browser")

                    Link(destination: feedbackEmail) {
                        ExternalLinkRow(
                            title: "Send Feedback",
                            detail: "team@x3n.network",
                            systemImage: "envelope"
                        )
                    }
                    .accessibilityIdentifier("settings.feedback")
                    .accessibilityLabel("Send Feedback, team at x3n dot network")
                    .accessibilityHint("Opens a new email addressed to the Folik team")
                }

                Section("Privacy") {
                    Toggle("App Lock", isOn: Binding(
                        get: { appLock.isEnabled },
                        set: appLock.setEnabled
                    ))
                    .disabled(appLock.isAuthenticating)
                    .accessibilityIdentifier("settings.appLock")
                    if appLock.isAuthenticating && !appLock.isEnabled {
                        ProgressView("Confirming App Lock…")
                    }
                    if let error = appLock.errorMessage, !appLock.isEnabled {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if appLock.isEnabled {
                        Picker("Require Authentication", selection: Binding(
                            get: { appLock.delay },
                            set: appLock.setDelay
                        )) {
                            ForEach(AppLockDelay.allCases) { delay in
                                Text(delay.title).tag(delay)
                            }
                        }
                        Text("App Lock uses Face ID, Touch ID, or your device passcode and hides document previews in the app switcher. It does not add encryption to individual PDFs.")
                            .font(.footnote)
                            .foregroundStyle(FolikTheme.mutedInk)
                    }
                    Label("Documents stay on this device", systemImage: "iphone.and.arrow.forward")
                    Label("Scans and text recognition run locally", systemImage: "text.viewfinder")
                    Label("Folik includes no analytics or advertising SDKs", systemImage: "hand.raised")
                }

                Section("What Folik can do") {
                    Label("Read, search, scan, and organize PDFs", systemImage: "doc.text.magnifyingglass")
                    Label("Fill forms and add signatures", systemImage: "signature")
                    Label("Annotate, bookmark, and export", systemImage: "square.and.pencil")
                }

                Section {
                    Text("Folik is open source and licensed under the MIT License. Visit the project website above to view the source code or contribute.")
                        .font(.footnote)
                        .foregroundStyle(FolikTheme.mutedInk)
                }

                Section("Legal") {
                    Link(destination: standardEULA) {
                        ExternalLinkRow(
                            title: "Apple Standard EULA",
                            detail: "View license terms",
                            systemImage: "doc.text"
                        )
                    }
                    .accessibilityIdentifier("settings.eula")
                    .accessibilityLabel("Apple Standard EULA")
                    .accessibilityHint("Opens Apple’s license terms in your browser")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(FolikTheme.cobalt)
    }
}

private struct FolikHelpView: View {
    var body: some View {
        List {
            Section("Getting started") {
                helpRow(
                    "Open, sign, and share",
                    icon: "signature",
                    detail: "Choose a PDF or scan paper, open Forms or Annotations to sign it, then use Share to create an editable or flattened copy."
                )
                helpRow(
                    "Find text",
                    icon: "magnifyingglass",
                    detail: "Search your whole library from Library. Tap a matching excerpt to open that page in Find. Scans need Make PDF Searchable first."
                )
                helpRow(
                    "Keep work organized",
                    icon: "folder",
                    detail: "Use a document’s actions to rename, favorite, duplicate, add folders or tags, or open PDF tools."
                )
            }

            Section("Forms") {
                helpRow(
                    "Fill",
                    icon: "list.clipboard",
                    detail: "Use Fill for existing fields, completion progress, required-field review, and signing. Entries save into your local library copy."
                )
                helpRow(
                    "Build",
                    icon: "hammer",
                    detail: "Make a fillable copy, choose a field type, and tap repeatedly to place fields. Arrange, edit, duplicate, align, and reorder them without changing the original PDF."
                )
            }

            Section("Sharing") {
                helpRow(
                    "Editable copy",
                    icon: "square.and.arrow.up",
                    detail: "Keeps supported forms and annotations editable for compatible PDF apps."
                )
                helpRow(
                    "Flattened copy",
                    icon: "checkmark.seal",
                    detail: "Makes visible entries and annotations part of each page. Review the preview because editing, search, links, and accessibility text may be removed."
                )
            }

            Section {
                Text("Folik works locally and never uploads your documents. Keep an original copy of important PDFs while checking compatibility with the apps used by your recipients.")
                    .font(.footnote)
                    .foregroundStyle(FolikTheme.mutedInk)
            }
        }
        .navigationTitle("Using Folik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(_ title: String, icon: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(FolikTheme.mutedInk)
            }
            .padding(.vertical, 4)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(FolikTheme.cobalt)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExternalLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(FolikTheme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(FolikTheme.mutedInk)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FolikTheme.mutedInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppLockManager())
}
