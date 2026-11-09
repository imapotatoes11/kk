import CoreGraphics

/// Local visual heuristic: blank means low variation, regardless of light/dark color.
/// Find a square anchor, then use the blank rows above and below it at that width.
enum BlankSpaceFinder {
    static func find(in image: CGImage, screenFrame: CGRect, visibleFrame: CGRect, near preferred: CGPoint) -> CGRect? {
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
        let cell: CGFloat = 12
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
        guard let square = largestSquare(blank: blank, columns: columns, rows: rows, cell: cell, bounds: usable, near: preferred) else { return nil }
        return extendingVertically(square, blank: blank, columns: columns, rows: rows, cell: cell, bounds: usable)
    }

    static func extendingVertically(_ square: CGRect, blank: [Bool], columns: Int, rows: Int, cell: CGFloat, bounds: CGRect) -> CGRect {
        let left = Int(((square.minX - bounds.minX) / cell).rounded())
        let right = Int(((square.maxX - bounds.minX) / cell).rounded())
        var top = Int(((bounds.maxY - square.maxY) / cell).rounded())
        var bottom = Int(((bounds.maxY - square.minY) / cell).rounded())
        guard left >= 0, right <= columns, left < right, top >= 0, bottom <= rows,
              blank.count == columns * rows else { return square }
        func rowIsBlank(_ row: Int) -> Bool {
            (left..<right).allSatisfy { blank[row * columns + $0] }
        }
        while top > 0 && rowIsBlank(top - 1) { top -= 1 }
        while bottom < rows && rowIsBlank(bottom) { bottom += 1 }
        return CGRect(x: square.minX, y: bounds.maxY - CGFloat(bottom) * cell,
            width: square.width, height: CGFloat(bottom - top) * cell)
    }

    static func largestSquare(blank: [Bool], columns: Int, rows: Int, cell: CGFloat, bounds: CGRect, near preferred: CGPoint) -> CGRect? {
        guard columns > 0, rows > 0, blank.count == columns * rows else { return nil }
        var previous = [Int](repeating: 0, count: columns + 1)
        var best: CGRect?
        var bestSide = 0
        var bestDistance = CGFloat.infinity
        for row in 0..<rows {
            var current = [Int](repeating: 0, count: columns + 1)
            for column in 0..<columns where blank[row * columns + column] {
                let side = 1 + min(previous[column], previous[column + 1], current[column])
                current[column + 1] = side
                guard side >= bestSide else { continue }
                let rect = CGRect(x: bounds.minX + CGFloat(column + 1 - side) * cell,
                    y: bounds.maxY - CGFloat(row + 1) * cell,
                    width: CGFloat(side) * cell, height: CGFloat(side) * cell)
                let distance = pow(rect.midX - preferred.x, 2) + pow(rect.midY - preferred.y, 2)
                if side > bestSide || distance < bestDistance {
                    best = rect
                    bestSide = side
                    bestDistance = distance
                }
            }
            previous = current
        }
        // Smaller specks cannot hold a usable chat, even with a compromise.
        guard let best, best.width >= 160 else { return nil }
        return best
    }

    static func fittedFrame(in space: CGRect, desired: CGSize, minimum: CGSize, visible: CGRect, fillHeight: Bool = false) -> CGRect {
        // Narrow first; if needed reduce height too. Keep the composer usable when the
        // detected square is too small, accepting a little overlap on both axes.
        let size = CGSize(width: max(minimum.width, min(desired.width, space.width - 16)),
            height: max(minimum.height, fillHeight ? space.height - 16 : min(desired.height, space.height - 16)))
        return PanelPositioning.clamped(CGRect(x: space.midX - size.width / 2,
            y: space.maxY - 8 - size.height, width: size.width, height: size.height), in: visible)
    }
}
