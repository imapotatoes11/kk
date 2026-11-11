import AppKit

/// Resolve file access and the drag image before AppKit starts tracking a drag.
@MainActor
struct PreparedDragApp {
    let appURL: URL
    let icon: NSImage
    let isReady: Bool
    let error: String?

    static func prepare(appURL: URL,
                        readDirectory: (URL) throws -> Void = { url in
                            // Touch only the containing folder, without keeping or logging its contents.
                            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                        },
                        loadIcon: (URL) -> NSImage = { icon(for: $0) }) -> Self {
        do {
            guard appURL.pathExtension == "app",
                  appURL == Bundle.main.bundleURL || FileManager.default.fileExists(atPath: appURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try readDirectory(appURL.deletingLastPathComponent())
            let icon = NSImage(size: NSSize(width: 64, height: 64))
            icon.lockFocus()
            loadIcon(appURL).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            icon.unlockFocus()
            return Self(appURL: appURL, icon: icon, isReady: true, error: nil)
        } catch {
            return Self(appURL: appURL, icon: NSImage(systemSymbolName: "app", accessibilityDescription: "kk")!, isReady: false,
                        error: "Allow access to kk’s folder, then open this helper again.")
        }
    }

    /// kk's own bundle uses the icon chosen in Settings → About. Finder's icon for a bundle can
    /// be stale (macOS caches it per path) and doesn't follow that choice.
    static func icon(for appURL: URL, style: AppIconStyle = .saved()) -> NSImage {
        if appURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL, let image = style.image { return image }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
