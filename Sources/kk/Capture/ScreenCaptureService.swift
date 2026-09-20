import AppKit
import CoreGraphics
import ScreenCaptureKit

struct ScreenCaptureService: Sendable {
    func capture(displayID: CGDirectDisplayID?) async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else {
            throw KKError.screenCapturePermission
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
            guard let display else {
                throw KKError.screenCaptureFailed("No display was available for capture.")
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
            configuration.showsCursor = true
            configuration.queueDepth = 1

            let scale = min(1, CaptureConstants.maxLongEdge / CGFloat(max(display.width, display.height)))
            configuration.width = max(1, Int(CGFloat(display.width) * scale))
            configuration.height = max(1, Int(CGFloat(display.height) * scale))

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.jpegData(from: image)
            }.value
        } catch let error as KKError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw KKError.screenCaptureFailed(error.localizedDescription)
        }
    }

    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for rawValue in candidates {
            if let url = URL(string: rawValue), NSWorkspace.shared.open(url) { return }
        }
    }
}
