import SwiftUI

struct ErrorView: View {
    let error: KKError
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.primary)
            if let recovery = error.recoverySuggestion, recovery != error.localizedDescription {
                Text(recovery)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if [.invalidBaseURL, .invalidModel, .missingAPIKey, .unauthorized].contains(error) {
                    Button("Open Settings", action: onOpenSettings)
                        .buttonStyle(.link)
                } else {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
