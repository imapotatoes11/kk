import AppKit
import CoreGraphics
import ImageIO

enum ImageProcessor {
    static func jpegData(from image: CGImage) throws -> Data {
        let first = try encode(image, longEdge: CaptureConstants.maxLongEdge, quality: CaptureConstants.jpegQuality)
        if first.count <= CaptureConstants.softMaxBytes { return first }

        let second = try encode(image, longEdge: CaptureConstants.maxLongEdge, quality: CaptureConstants.fallbackJPEGQuality)
        if second.count <= CaptureConstants.softMaxBytes { return second }

        return try encode(image, longEdge: CaptureConstants.fallbackLongEdge, quality: CaptureConstants.fallbackJPEGQuality)
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Draws the image over white so transparent regions don't turn black in JPEG output.
    static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// A small PNG for attachment chips.
    static func thumbnailPNG(from image: CGImage, maxPixel: CGFloat = 96) -> Data? {
        NSBitmapImageRep(cgImage: resizedImage(image, longEdge: maxPixel)).representation(using: .png, properties: [:])
    }

    static func jpegData(from image: CGImage, longEdge: CGFloat, quality: CGFloat) throws -> Data {
        try encode(image, longEdge: longEdge, quality: quality)
    }

    private static func encode(_ image: CGImage, longEdge: CGFloat, quality: CGFloat) throws -> Data {
        let target = resizedImage(image, longEdge: longEdge)
        let rep = NSBitmapImageRep(cgImage: target)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw KKError.screenCaptureFailed("kk couldn't process the captured screen.")
        }
        return data
    }

    private static func resizedImage(_ image: CGImage, longEdge: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, longEdge / max(width, height))
        guard scale < 1 else { return image }

        let size = CGSize(width: floor(width * scale), height: floor(height * scale))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage() ?? image
    }
}
