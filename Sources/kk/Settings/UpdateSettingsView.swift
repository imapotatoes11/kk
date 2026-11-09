import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Updates").font(.headline)
                Spacer()
                Button("Check for updates…", action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isAvailable)
            Toggle("Automatically download and install updates", isOn: $updater.automaticallyDownloadsUpdates)
                .disabled(!updater.isAvailable || !updater.automaticallyChecksForUpdates)
            if let reason = updater.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else if let lastCheck = updater.lastCheck {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: 440)
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
