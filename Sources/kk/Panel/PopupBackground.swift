import AppKit
import SwiftUI

struct PopupBackground: View {
    let material: PopupMaterial
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency || material == .opaque {
            Color(nsColor: .windowBackgroundColor)
        } else if material == .liquidGlass {
            if #available(macOS 26, *) {
                LiquidGlassPopupMaterial()
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
    var body: some View {
        Color.clear
            .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.15)), in: RoundedRectangle(cornerRadius: PopupGeometry.cornerRadius))
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
