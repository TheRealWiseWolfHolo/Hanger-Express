import SwiftUI

struct SettingsView: View {
    let appModel: AppModel
    let snapshot: HangarSnapshot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Account", value: appModel.session?.displayName ?? snapshot.accountHandle)
                    LabeledContent("Account Email", value: appModel.session?.email ?? "Unknown")
                    LabeledContent("Saved Login", value: appModel.session?.credentials?.loginIdentifier ?? "None")
                    LabeledContent("Session Mode", value: appModel.session?.authMode.rawValue ?? "None")
                    LabeledContent("Stored Cookies", value: "\(appModel.session?.cookies.count ?? 0)")
                    LabeledContent("Stored Credentials", value: appModel.session?.hasStoredCredentials == true ? "Keychain" : "None")
                    LabeledContent("Last Refresh", value: refreshLabel)
                } header: {
                    Text("Session")
                }

                Section {
                    Label("Read-only pledge sync", systemImage: "checkmark.circle")
                    Label("Buy-back visibility", systemImage: "checkmark.circle")
                    Label("Ship grouping and local notes", systemImage: "checkmark.circle")
                    Label("Melt, gift, and upgrade actions", systemImage: "hourglass")
                } header: {
                    Text("Roadmap")
                }

                Section {
                    Button("Sign Out and Remove Saved Credentials", role: .destructive) {
                        Task {
                            await appModel.clearSession()
                        }
                    }
                } footer: {
                    Text("Credentials and RSI cookies are stored in Keychain so later account actions can reuse the same authenticated session.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var refreshLabel: String {
        guard let lastRefreshAt = appModel.lastRefreshAt else {
            return "Not yet synced"
        }

        return lastRefreshAt.formatted(date: .abbreviated, time: .shortened)
    }
}
