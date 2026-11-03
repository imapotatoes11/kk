import SwiftUI

enum PopupGeometry {
    static let cornerRadius: CGFloat = 22
    static let palettePadding: CGFloat = 4
    static let actionHeight: CGFloat = 48
    static let actionRadius: CGFloat = cornerRadius - palettePadding
}

struct PopupSurface: ViewModifier {
    let material: PopupMaterial
    func body(content: Content) -> some View {
        content
            .materialActiveAppearance(.active)
            .background { PopupBackground(material: material) }
            .clipShape(RoundedRectangle(cornerRadius: PopupGeometry.cornerRadius))
            .overlay { RoundedRectangle(cornerRadius: PopupGeometry.cornerRadius).strokeBorder(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1).allowsHitTesting(false) }
    }
}

/// Native drag targets cover only known empty padding, never the controls inside it.
struct DraggableInsets: ViewModifier {
    var horizontal: CGFloat
    var vertical: CGFloat
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    if vertical > 0 {
                        PanelDragArea().frame(width: geometry.size.width, height: vertical)
                        PanelDragArea().frame(width: geometry.size.width, height: vertical).offset(y: max(0, geometry.size.height - vertical))
                    }
                    if horizontal > 0 {
                        PanelDragArea().frame(width: horizontal, height: max(0, geometry.size.height - 2 * vertical)).offset(y: vertical)
                        PanelDragArea().frame(width: horizontal, height: max(0, geometry.size.height - 2 * vertical)).offset(x: max(0, geometry.size.width - horizontal), y: vertical)
                    }
                }
            }
        }
    }
}
