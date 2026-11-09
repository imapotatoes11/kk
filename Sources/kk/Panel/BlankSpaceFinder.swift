import CoreGraphics

/// A grid of visually quiet cells on a display: low variation, regardless of light or dark color.
struct BlankMap: Sendable, Equatable {
    let columns: Int
    let rows: Int
    let cell: CGFloat
    /// The area the grid covers, in AppKit screen coordinates. Row 0 is at the top.
    let bounds: CGRect
    let blank: [Bool]
    /// Summed-area table, so any rectangle's blank count is O(1).
    private let sums: [Int32]

    init(columns: Int, rows: Int, cell: CGFloat, bounds: CGRect, blank: [Bool]) {
        self.columns = columns
        self.rows = rows
        self.cell = cell
        self.bounds = bounds
        self.blank = blank
        var sums = [Int32](repeating: 0, count: (rows + 1) * (columns + 1))
        let stride = columns + 1
        for row in 0..<rows {
            var running: Int32 = 0
            for column in 0..<columns {
                if blank.indices.contains(row * columns + column), blank[row * columns + column] { running += 1 }
                sums[(row + 1) * stride + column + 1] = sums[row * stride + column + 1] + running
            }
        }
        self.sums = sums
    }

    /// Blank cells in rows `r0..<r1` and columns `c0..<c1`.
    func blankCount(rows r0: Int, _ r1: Int, columns c0: Int, _ c1: Int) -> Int {
        let r0 = max(0, min(rows, r0)), r1 = max(r0, min(rows, r1))
        let c0 = max(0, min(columns, c0)), c1 = max(c0, min(columns, c1))
        let stride = columns + 1
        return Int(sums[r1 * stride + c1] - sums[r0 * stride + c1] - sums[r1 * stride + c0] + sums[r0 * stride + c0])
    }

    func columnRange(_ rect: CGRect) -> (Int, Int) {
        (Int(((rect.minX - bounds.minX) / cell).rounded(.down)), Int(((rect.maxX - bounds.minX) / cell).rounded(.up)))
    }

    func rowRange(_ rect: CGRect) -> (Int, Int) {
        (Int(((bounds.maxY - rect.maxY) / cell).rounded(.down)), Int(((bounds.maxY - rect.minY) / cell).rounded(.up)))
    }

    /// The share of grid cells under `rect` that are blank. Areas outside the grid count as busy.
    func blankFraction(_ rect: CGRect) -> Double {
        let (c0, c1) = columnRange(rect), (r0, r1) = rowRange(rect)
        let total = max(0, c1 - c0) * max(0, r1 - r0)
        guard total > 0 else { return 0 }
        return Double(blankCount(rows: r0, r1, columns: c0, c1)) / Double(total)
    }
}

/// Local visual heuristic for placing chat in a quiet part of the screen, away from the window
/// the user is working in.
enum BlankSpaceFinder {
    static let cell: CGFloat = 12
    /// A row counts as quiet for vertical growth when this share of it is blank. Sparse icons
    /// or labels at the edges, such as a browser's tab strip, don't stop growth.
    static let quietRowFraction = 0.85
    static let margin: CGFloat = 8

    static func map(from image: CGImage, screenFrame: CGRect, visibleFrame: CGRect) -> BlankMap? {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let scale = min(1, 1440 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let usable = visibleFrame.insetBy(dx: 24, dy: 24).intersection(screenFrame)
        let columns = Int(usable.width / cell), rows = Int(usable.height / cell)
        guard columns > 0, rows > 0 else { return nil }
        var blank = [Bool](repeating: false, count: rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                let left = usable.minX + CGFloat(column) * cell
                let top = usable.maxY - CGFloat(row) * cell
                let x0 = max(0, Int((left - screenFrame.minX) / screenFrame.width * CGFloat(width)))
                let x1 = min(width, Int(ceil((left + cell - screenFrame.minX) / screenFrame.width * CGFloat(width))))
                // Screenshot rows start at the top; AppKit screen coordinates start at the bottom.
                let y0 = max(0, Int((screenFrame.maxY - top) / screenFrame.height * CGFloat(height)))
                let y1 = min(height, Int(ceil((screenFrame.maxY - top + cell) / screenFrame.height * CGFloat(height))))
                var channels = [[UInt8](), [UInt8](), [UInt8]()]
                for y in y0..<max(y0, y1) {
                    for x in x0..<max(x0, x1) {
                        for channel in 0..<3 {
                            channels[channel].append(pixels[(y * width + x) * 4 + channel])
                        }
                    }
                }
                blank[row * columns + column] = channels.allSatisfy { values in
                    let sorted = values.sorted()
                    guard let low = sorted.first, let high = sorted.last else { return false }
                    let range = Int(high) - Int(low)
                    if range <= 22 { return true }
                    // Ignore sparse, faint dividers (roughly 1–2 pixels per cell).
                    // Keep even sparse high-contrast text, punctuation, and icon strokes.
                    guard range <= 80 else { return false }
                    let trim = sorted.count / 5
                    return Int(sorted[sorted.count - 1 - trim]) - Int(sorted[trim]) <= 22
                }
            }
        }
        return BlankMap(columns: columns, rows: rows, cell: cell, bounds: usable, blank: blank)
    }

    /// The largest area beside the focused window (left, right, above, or below) that can hold
    /// `minimum`. Without such an area, or a focused window on this display, the whole bounds.
    static func allowedRegion(in bounds: CGRect, avoiding window: CGRect?, minimum: CGSize) -> CGRect {
        guard let window, window.intersects(bounds) else { return bounds }
        let gap = margin
        let candidates = [
            CGRect(x: bounds.minX, y: bounds.minY, width: window.minX - gap - bounds.minX, height: bounds.height),
            CGRect(x: window.maxX + gap, y: bounds.minY, width: bounds.maxX - window.maxX - gap, height: bounds.height),
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: window.minY - gap - bounds.minY),
            CGRect(x: bounds.minX, y: window.maxY + gap, width: bounds.width, height: bounds.maxY - window.maxY - gap)
        ].map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width >= minimum.width && $0.height >= minimum.height }
        return candidates.max { $0.width * $0.height < $1.width * $1.height } ?? bounds
    }

    /// The position for a panel of `size` with the quietest surroundings within `region`,
    /// preferring spots near `preferred`. Overlapping `window` is penalized, which matters only
    /// when the region couldn't exclude it.
    static func placement(of size: CGSize, in map: BlankMap, region: CGRect, avoiding window: CGRect?, near preferred: CGPoint) -> CGRect {
        let area = region.intersection(map.bounds).isNull ? map.bounds : region.intersection(map.bounds)
        let size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        // Grid steps, plus the far edges, so the panel can sit flush against either side.
        func positions(from start: CGFloat, to end: CGFloat) -> [CGFloat] {
            guard end > start else { return [start] }
            var values = Array(stride(from: start, through: end, by: map.cell))
            if let last = values.last, end - last > 0.5 { values.append(end) }
            return values
        }
        var best: (score: Double, distance: CGFloat, rect: CGRect)?
        for y in positions(from: area.minY, to: area.maxY - size.height) {
            for x in positions(from: area.minX, to: area.maxX - size.width) {
                let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
                // Favor spots surrounded by quiet space, not just quiet underneath.
                let halo = rect.insetBy(dx: -40, dy: -40).intersection(map.bounds)
                var score = map.blankFraction(rect) * 0.6 + map.blankFraction(halo) * 0.4
                if let window, rect.intersects(window) {
                    let overlap = rect.intersection(window)
                    score -= 0.8 * Double(overlap.width * overlap.height / (rect.width * rect.height))
                }
                let distance = hypot(rect.midX - preferred.x, rect.midY - preferred.y)
                if let current = best {
                    if score > current.score + 0.01 || (abs(score - current.score) <= 0.01 && distance < current.distance) {
                        best = (score, distance, rect)
                    }
                } else {
                    best = (score, distance, rect)
                }
            }
        }
        return best?.rect ?? CGRect(origin: CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height), size: size)
    }

    /// Grows `rect` upward and downward through quiet rows within `region`, so a sent chat fills
    /// the quiet column it sits in. Height never drops below `minimumHeight`.
    static func expanded(_ rect: CGRect, in map: BlankMap, region: CGRect, minimumHeight: CGFloat) -> CGRect {
        let area = region.intersection(map.bounds).isNull ? map.bounds : region.intersection(map.bounds)
        let (c0, c1) = map.columnRange(rect)
        let (areaTop, areaBottom) = map.rowRange(area)
        var (top, bottom) = map.rowRange(rect)
        top = max(top, areaTop)
        bottom = min(max(bottom, top + 1), areaBottom)
        let width = max(1, min(map.columns, c1) - max(0, c0))
        func quiet(_ row: Int) -> Bool {
            Double(map.blankCount(rows: row, row + 1, columns: c0, c1)) / Double(width) >= quietRowFraction
        }
        while top > areaTop && quiet(top - 1) { top -= 1 }
        while bottom < areaBottom && quiet(bottom) { bottom += 1 }
        let columnTop = map.bounds.maxY - CGFloat(top) * map.cell
        let columnBottom = map.bounds.maxY - CGFloat(bottom) * map.cell
        let height = min(area.height, max(minimumHeight, columnTop - columnBottom - 2 * margin))
        var frame = CGRect(x: rect.minX, y: columnTop - margin - height, width: rect.width, height: height)
        if frame.minY < area.minY { frame.origin.y = area.minY }
        if frame.maxY > area.maxY { frame.origin.y = area.maxY - frame.height }
        return frame
    }
}
