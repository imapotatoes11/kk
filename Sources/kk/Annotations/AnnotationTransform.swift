import CoreGraphics

struct AnnotationHit: Equatable {
    let index: Int
    let corner: Int?
}

enum AnnotationTransform {
    static func corners(of mark: ScreenAnnotation) -> [CGPoint] {
        guard [.ellipse, .rectangle, .arrow].contains(mark.tool), let first = mark.points.first, let last = mark.points.last else { return [] }
        if mark.tool == .arrow { return [first, last] }
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: max(1, abs(last.x - first.x)), height: max(1, abs(last.y - first.y)))
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    static func hitsStroke(_ point: CGPoint, mark: ScreenAnnotation) -> Bool {
        mark.path.copy(strokingWithWidth: max(12, mark.lineWidth + 10), lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }

    static func hit(at point: CGPoint, marks: [ScreenAnnotation], hovered: Int?) -> AnnotationHit? {
        if let hovered, marks.indices.contains(hovered),
           let corner = corners(of: marks[hovered]).firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) <= 9 }) {
            return AnnotationHit(index: hovered, corner: corner)
        }
        for index in marks.indices.reversed() where hitsStroke(point, mark: marks[index]) {
            return AnnotationHit(index: index, corner: nil)
        }
        return nil
    }

    static func moved(_ mark: ScreenAnnotation, by offset: CGPoint) -> ScreenAnnotation {
        var result = mark
        result.points = mark.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
        return result
    }

    static func resized(_ mark: ScreenAnnotation, corner: Int, to point: CGPoint) -> ScreenAnnotation {
        let handles = corners(of: mark)
        guard handles.indices.contains(corner), let first = mark.points.first, let last = mark.points.last else { return mark }
        if mark.tool == .arrow {
            var result = mark
            result.points = [first, last]
            result.points[corner] = point
            return result
        }
        let anchor = handles[(corner + 2) % 4]
        let original = handles[corner]
        let sx = (point.x - anchor.x) / (original.x - anchor.x)
        let sy = (point.y - anchor.y) / (original.y - anchor.y)
        var result = mark
        result.points = mark.points.enumerated().map { index, p in
            // Degenerate arrows still have draggable corners and can gain a second dimension.
            let x = abs(last.x - first.x) < 1 ? (index == 0 ? handles[0].x : handles[2].x) : p.x
            let y = abs(last.y - first.y) < 1 ? (index == 0 ? handles[0].y : handles[2].y) : p.y
            return CGPoint(x: anchor.x + (x - anchor.x) * sx, y: anchor.y + (y - anchor.y) * sy)
        }
        return result
    }
}
