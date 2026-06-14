import SwiftUI
import UsageCore

/// Settings window. Grouped into General (launch-at-login), Display (token
/// definition + day boundaries), and Updates (refresh cadence). Provider scope
/// arrives with M6.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
                    .help("Start inline-usage automatically when you log in. Requires the installed app bundle; in System Settings › General › Login Items you can revoke it.")
            }

            Section("Display") {
                Picker("Token metric", selection: tokenDefinition) {
                    Text("Input + output").tag(TokenDefinition.inputOutputOnly)
                    Text("Input + output + cache write").tag(TokenDefinition.withCacheWrite)
                    Text("Billable total (incl. cache read)").tag(TokenDefinition.billableTotal)
                }
                .help("Cache reads dominate raw totals (~97%), so input+output is the most intuitive headline.")

                Picker("Day boundaries", selection: zone) {
                    Text("Local time").tag(PeriodBucketer.Zone.local)
                    Text("UTC").tag(PeriodBucketer.Zone.utc)
                }
                .help("Which clock defines \"today\" and the week — your local time zone or UTC.")
            }

            Section("Updates") {
                Picker("Refresh", selection: interval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .help("Real-time watches ~/.claude for changes; the intervals also refresh on a timer.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .scenePadding()
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }

    private var tokenDefinition: Binding<TokenDefinition> {
        Binding(get: { model.selection.tokenDefinition }, set: { model.setTokenDefinition($0) })
    }

    private var zone: Binding<PeriodBucketer.Zone> {
        Binding(get: { model.zone }, set: { model.setZone($0) })
    }

    private var interval: Binding<RefreshInterval> {
        Binding(get: { model.refreshInterval }, set: { model.setRefreshInterval($0) })
    }
}
