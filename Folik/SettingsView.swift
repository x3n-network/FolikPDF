import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

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
}
