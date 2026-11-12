import AppKit

enum PalettePosition: String, CaseIterable, Identifiable {
    case top, right, left, bottom, popup
    var id: Self { self }
    var title: String { self == .popup ? "Next to popup" : rawValue.capitalized }
    func frame(in visible: CGRect, size: CGSize, popup: CGRect?) -> CGRect {
        var result = CGRect(origin: CGPoint(x: visible.midX - size.width / 2, y: visible.minY + 24), size: size)
        switch self {
        case .top: result.origin.y = visible.maxY - size.height - 24
        case .left: result.origin = CGPoint(x: visible.minX + 24, y: visible.midY - size.height / 2)
        case .right: result.origin = CGPoint(x: visible.maxX - size.width - 24, y: visible.midY - size.height / 2)
        case .bottom: break
        case .popup:
            if let popup {
                result.origin.x = popup.midX - size.width / 2
                let below = popup.minY - size.height - 12
                result.origin.y = below
            }
        }
        func clamped(_ frame: CGRect) -> CGRect {
            var frame = frame
            frame.size.width = min(frame.width, visible.width - 16)
            frame.size.height = min(frame.height, visible.height - 16)
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
            return frame
        }
        result = clamped(result)
        guard let popup, result.intersects(popup) else { return result }
        // Check the final on-screen frame, not just whether the ideal gap fits.
        // A smaller gap below is preferable to hiding the palette behind the header.
        let candidates = [
            CGRect(x: popup.midX - size.width / 2, y: popup.minY - size.height - 12, width: size.width, height: size.height),
            CGRect(x: popup.midX - size.width / 2, y: popup.maxY + 12, width: size.width, height: size.height),
            CGRect(x: popup.minX - size.width - 12, y: popup.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: popup.maxX + 12, y: popup.midY - size.height / 2, width: size.width, height: size.height)
        ].map(clamped)
        // For next-to-popup placement, always try below first, including the edge margin.
        if let free = candidates.first(where: { !$0.intersects(popup) }) { return free }
        // No side fits (for example, a manually maximized chat). Minimize overlap;
        // the controller raises the palette above chat in this unavoidable case.
        return candidates.min {
            let a = $0.intersection(popup), b = $1.intersection(popup)
            return a.width * a.height < b.width * b.height
        } ?? result
    }
}
