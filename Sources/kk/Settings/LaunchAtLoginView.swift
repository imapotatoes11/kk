import AppKit
import ServiceManagement
import SwiftUI

struct LaunchAtLoginView: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at login", isOn: Binding(get: { enabled || needsApproval }, set: change))
            if needsApproval {
                Button("Allow in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func change(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = error.localizedDescription }
        refresh()
    }
    private func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
}
