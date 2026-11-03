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
struct LiquidGlassPopupMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = UIConstants.cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {}
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
