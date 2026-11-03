import AppKit
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case freehand, ellipse, rectangle, arrow
    var id: Self { self }
    var key: String { switch self { case .freehand: "f"; case .ellipse: "e"; case .rectangle: "r"; case .arrow: "a" } }
    var title: String {
        switch self {
        case .freehand: "Freehand"
        case .ellipse: "Ellipse"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        }
    }
    var symbol: String {
        switch self {
        case .freehand: "pencil.tip"
        case .ellipse: "circle"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple, white, black
    var id: Self { self }
    var title: String { rawValue.capitalized }
    // Fixed sRGB colors keep the on-screen mark identical to the submitted image.
    var components: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .red: (1, 0.23, 0.19)
        case .orange: (1, 0.58, 0)
        case .yellow: (1, 0.84, 0.04)
        case .green: (0.19, 0.82, 0.35)
        case .blue: (0.04, 0.52, 1)
        case .purple: (0.75, 0.35, 0.95)
        case .white: (1, 1, 1)
        case .black: (0, 0, 0)
        }
    }
    var cgColor: CGColor {
        let (r, g, b) = components
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
    var color: Color { Color(cgColor: cgColor) }
}

struct ScreenAnnotation: Equatable, Sendable {
    let tool: AnnotationTool
    let color: AnnotationColor
    let lineWidth: CGFloat
    var smoothed: Bool = false
    var points: [CGPoint]

    var isVisible: Bool {
        guard let start = points.first, let end = points.last else { return false }
        return tool == .freehand || hypot(end.x - start.x, end.y - start.y) >= 3
    }

    var path: CGPath {
        let path = CGMutablePath()
        guard let start = points.first, let end = points.last else { return path }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        switch tool {
        case .freehand:
            path.move(to: start)
            if points.count == 1 {
                path.addLine(to: CGPoint(x: start.x + 0.1, y: start.y))
            } else {
                if smoothed && points.count > 2 {
                    for i in 1..<points.count {
                        let previous = points[i - 1], point = points[i]
                        path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
                    }
                    path.addLine(to: end)
                } else { for point in points.dropFirst() { path.addLine(to: point) } }
            }
        case .ellipse: path.addEllipse(in: rect)
        case .rectangle: path.addRect(rect)
        case .arrow:
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(max(12, lineWidth * 4), hypot(end.x - start.x, end.y - start.y) * 0.4)
            for offset: CGFloat in [-.pi / 6, .pi / 6] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x - length * cos(angle + offset), y: end.y - length * sin(angle + offset)))
            }
        }
        return path
    }
}

enum AnnotationRenderer {
    static func draw(_ annotations: [ScreenAnnotation], in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for annotation in annotations where annotation.isVisible {
            context.setStrokeColor(annotation.color.cgColor)
            context.setLineWidth(annotation.lineWidth)
            context.addPath(annotation.path)
            context.strokePath()
        }
    }

    static func composite(_ annotations: [ScreenAnnotation], onto image: CGImage, canvasSize: CGSize) throws -> CGImage {
        guard canvasSize.width > 0, canvasSize.height > 0,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw KKError.screenCaptureFailed("Couldn't prepare the annotated screen.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.scaleBy(x: CGFloat(image.width) / canvasSize.width, y: CGFloat(image.height) / canvasSize.height)
        draw(annotations, in: context)
        guard let result = context.makeImage() else { throw KKError.screenCaptureFailed("Couldn't render annotations.") }
        return result
    }
}

@MainActor
final class AnnotationDocument: ObservableObject {
    @Published private(set) var annotations: [ScreenAnnotation] = []
    @Published private(set) var current: ScreenAnnotation?
    private var undoHistory: [[ScreenAnnotation]] = []
    @Published private(set) var canUndo = false
    func beginTransform() { saveUndo() }
    func replace(at index: Int, with mark: ScreenAnnotation) {
        guard annotations.indices.contains(index) else { return }
        annotations[index] = mark
    }
    private func saveUndo() { undoHistory.append(annotations); if undoHistory.count > 100 { undoHistory.removeFirst() }; canUndo = true }
    @Published var isDrawing = true
    @Published var isPreparing = false
    @Published var isFrozen = false

    var needsDiscardConfirmation: Bool { requiresDiscardConfirmation(strokeThreshold: 160) }
    func requiresDiscardConfirmation(strokeThreshold: CGFloat) -> Bool {
        let marks = visibleAnnotations
        return marks.count > 1 || marks.contains { mark in
            zip(mark.points, mark.points.dropFirst()).reduce(CGFloat.zero) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } > strokeThreshold
        }
    }
    func setSmoothing(_ enabled: Bool) { current?.smoothed = enabled }
    var visibleAnnotations: [ScreenAnnotation] { annotations + (current.map { [$0] } ?? []) }
    func begin(at point: CGPoint, tool: AnnotationTool, color: AnnotationColor, lineWidth: CGFloat) {
        guard isDrawing, !isPreparing else { return }
        current = ScreenAnnotation(tool: tool, color: color, lineWidth: lineWidth, points: [point])
    }
    func move(to point: CGPoint) {
        guard var mark = current else { return }
        if mark.tool == .freehand { mark.points.append(point) }
        else { mark.points = [mark.points[0], point] }
        current = mark
    }
    func finish() {
        if let current, current.isVisible { saveUndo(); annotations.append(current) }
        current = nil
    }
    func cancelCurrent() { current = nil }
    func undo() { current = nil; if let previous = undoHistory.popLast() { annotations = previous }; canUndo = !undoHistory.isEmpty }
    func clear() { current = nil; if !annotations.isEmpty { saveUndo() }; annotations = [] }
    func reset() { clear(); undoHistory = []; canUndo = false; isDrawing = true; isPreparing = false; isFrozen = false }
}
