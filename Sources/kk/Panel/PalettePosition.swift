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
                result.origin.y = below >= visible.minY + 12 ? below : popup.maxY + 12
            }
        }
        result.origin.x = min(max(result.minX, visible.minX + 12), visible.maxX - size.width - 12)
        result.origin.y = min(max(result.minY, visible.minY + 12), visible.maxY - size.height - 12)
        return result
    }
}
