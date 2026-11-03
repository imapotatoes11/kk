import AppKit
import CoreGraphics
import ScreenCaptureKit

struct ScreenSnapshot: Sendable {
    let image: CGImage
    let data: Data
}

struct ScreenCaptureService: Sendable {
    var permissionCheck: @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }
    var hasPassiveAccess: Bool { permissionCheck() }

    func capture(displayID: CGDirectDisplayID?) async throws -> Data {
        try await captureSnapshot(displayID: displayID).data
    }

    func captureSnapshot(displayID: CGDirectDisplayID?) async throws -> ScreenSnapshot {
        guard hasPassiveAccess else { throw KKError.screenCapturePermission }
        do {
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
                throw KKError.screenCaptureFailed("kk couldn't exclude its own panel from the screen capture.")
            }
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.queueDepth = 1

            // Preserve native pixels for a crisp frozen backdrop; only the submitted JPEG is resized.
            configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let data = try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.jpegData(from: image)
            }.value
            return ScreenSnapshot(image: image, data: data)
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
