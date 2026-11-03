import AppKit
import SwiftUI

struct PopupBackground: View {
    let material: PopupMaterial
    var cornerRadius: CGFloat = PopupGeometry.cornerRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency || material == .opaque {
            Color(nsColor: .windowBackgroundColor)
        } else if material == .liquidGlass {
            if #available(macOS 26, *) {
                LiquidGlassPopupMaterial(cornerRadius: cornerRadius)
            } else {
                TranslucentPopupMaterial()
            }
        } else {
            TranslucentPopupMaterial()
        }
    }
}

@available(macOS 26, *)
struct LiquidGlassPopupMaterial: View {
    var cornerRadius: CGFloat = PopupGeometry.cornerRadius
    var body: some View {
        Color.clear
            .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.15)), in: RoundedRectangle(cornerRadius: cornerRadius))
            .materialActiveAppearance(.active)
    }
}

struct TranslucentPopupMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
