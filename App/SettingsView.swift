import SwiftUI
import UsageCore

/// Small settings popover. M2: token definition, day-boundary timezone, and
/// the refresh cadence. Provider scope (M6) and launch-at-login (M5) join later.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
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

            Picker("Updates", selection: interval) {
                ForEach(RefreshInterval.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .help("Real-time watches ~/.claude for changes; the intervals also refresh on a timer.")
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .scenePadding()
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
