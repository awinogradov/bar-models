import SwiftUI
import UsageCore

/// The dropdown: the current value + breakdown, a per-model breakdown, a one-tap
/// quick-switch list (live values, checkmark on active), and Settings/Quit.
struct MenuContentView: View {
    let model: AppModel
    @ObservedObject var updater: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.availability == .ready {
                if !model.modelBreakdown.isEmpty {
                    perModel
                }

                Divider()

                Text("Show in menu bar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(model.menuOptions, id: \.self) { option in
                    quickSwitchRow(option)
                }
            }

            Divider()

            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)

            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder private var header: some View {
        switch model.availability {
        case .loading:
            Label("Loading…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .noSource, .empty:
            if let empty = model.emptyState {
                VStack(alignment: .leading, spacing: 4) {
                    Label(empty.title, systemImage: "tray")
                        .font(.headline)
                    Text(empty.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .ready:
            Text(model.headerTitle).font(.headline)
            Text(model.headerValue)
                .font(.system(.title2, design: .rounded).monospacedDigit())
            if !model.breakdown.isEmpty {
                Text(model.breakdown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let detail = model.limitDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var perModel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("By model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.modelBreakdown) { line in
                HStack {
                    Text(line.name)
                    Spacer()
                    Text(line.value).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            if let note = model.unknownModelNote {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func quickSwitchRow(_ option: MetricSelection) -> some View {
        Button { model.select(option) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .opacity(model.isSelected(option) ? 1 : 0)
                    .frame(width: 12)
                Text(option.label)
                Spacer()
                Text(model.value(for: option))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }
}
