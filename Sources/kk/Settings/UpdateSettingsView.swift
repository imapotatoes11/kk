import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates").font(.headline)
            Button("Check for updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isAvailable)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Automatically download and install updates", isOn: $updater.automaticallyDownloadsUpdates)
                .disabled(!updater.isAvailable || !updater.automaticallyChecksForUpdates)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = updater.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lastCheck = updater.lastCheck {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
