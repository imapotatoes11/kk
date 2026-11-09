import AppKit
import CoreGraphics
import ScreenCaptureKit

struct ScreenSnapshot: Sendable {
    let image: CGImage
    let data: Data
}

/// A transient discovery failure, distinct from permission denial or screenshot errors.
enum ScreenCaptureAttemptError: Error {
    case selfExclusionUnavailable
}

struct ScreenCaptureService: Sendable {
    var permissionCheck: @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }
    var captureAttempt: (@Sendable (CGDirectDisplayID?) async throws -> ScreenSnapshot)? = nil
    var retryDelay: Duration = .milliseconds(250)
    static let selfExclusionFailureMessage = "kk couldn't exclude its own panel from the screen capture. Try closing and reopening the kk popup, or relaunching kk."
    var hasPassiveAccess: Bool { permissionCheck() }

    func capture(displayID: CGDirectDisplayID?) async throws -> Data {
        try await captureSnapshot(displayID: displayID).data
    }

    func captureSnapshot(displayID: CGDirectDisplayID?) async throws -> ScreenSnapshot {
        do {
            for attempt in 0...1 {
                try Task.checkCancellation()
                guard hasPassiveAccess else { throw KKError.screenCapturePermission }
                do {
                    let snapshot: ScreenSnapshot
                    if let captureAttempt { snapshot = try await captureAttempt(displayID) }
                    else { snapshot = try await captureOnce(displayID: displayID) }
                    try Task.checkCancellation()
                    return snapshot
                } catch ScreenCaptureAttemptError.selfExclusionUnavailable {
                    guard attempt == 0 else { throw KKError.screenCaptureFailed(Self.selfExclusionFailureMessage) }
                    // WindowServer can register the newly opened popup after the first discovery.
                    // Re-enumerate once, keeping the UI in its capturing state until this settles.
                    try await Task.sleep(for: retryDelay)
                }
            }
            throw KKError.screenCaptureFailed(Self.selfExclusionFailureMessage)
        } catch let error as KKError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue {
                throw KKError.screenCapturePermission
            }
            throw KKError.screenCaptureFailed(error.localizedDescription)
        }
    }

    private func captureOnce(displayID: CGDirectDisplayID?) async throws -> ScreenSnapshot {
        let image = try await captureImage(displayID: displayID)
        let data = try await Task.detached(priority: .userInitiated) {
            try ImageProcessor.jpegData(from: image)
        }.value
        return ScreenSnapshot(image: image, data: data)
    }

    /// Placement never requests permission, encodes an attachment, or sends pixels to a provider.
    func capturePlacementImage(displayID: CGDirectDisplayID?) async throws -> CGImage {
        guard hasPassiveAccess else { throw KKError.screenCapturePermission }
        return try await captureImage(displayID: displayID, maximumDimension: 1440)
    }

    private func captureImage(displayID: CGDirectDisplayID?, maximumDimension: CGFloat? = nil) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let displayID, let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw KKError.screenCaptureFailed("The selected display is no longer available for capture.")
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let excludedApps = content.applications.filter { $0.processID == currentProcessID }
        let selfWindows = content.windows.filter { $0.owningApplication?.processID == currentProcessID }
        let filter: SCContentFilter
        if !excludedApps.isEmpty {
            filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        } else if !selfWindows.isEmpty {
            filter = SCContentFilter(display: display, excludingWindows: selfWindows)
        } else {
            throw ScreenCaptureAttemptError.selfExclusionUnavailable
        }
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.queueDepth = 1

        // Preserve native pixels for a crisp frozen backdrop; only the submitted JPEG is resized.
        configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        if let maximumDimension {
            let scale = min(1, maximumDimension / CGFloat(max(configuration.width, configuration.height)))
            configuration.width = max(1, Int(CGFloat(configuration.width) * scale))
            configuration.height = max(1, Int(CGFloat(configuration.height) * scale))
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    func hasAccess() async -> Bool { hasPassiveAccess }

    @MainActor
    func requestAccess() -> Bool {
        if hasPassiveAccess { return true }
        // The drag-to-Settings flow does not need a second native request dialog.
        openSystemSettings()
        return hasPassiveAccess
    }

    @MainActor
    func openSystemSettings() { PermissionAssistant.shared.open() }
}
