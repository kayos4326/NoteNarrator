//  ImageTools.swift
//  NoteNarrator

import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated enum ImageTools {

    /// Wide enough for text recognition to be accurate, small enough to stay fast.
    static let readingWidth: CGFloat = 1600
    /// What we keep on disk to show the student.
    static let thumbnailWidth: CGFloat = 900

    static func render(_ page: PDFPage, maxWidth: CGFloat = readingWidth) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // Small pages are drawn larger so text recognition has enough pixels to work with.
        let scale = min(maxWidth / bounds.width, 3)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width.rounded()),
            height: Int(size.height.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: readingWidth,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Pixel size without decoding the whole image, for skipping logos and bullets.
    static func pixelSize(ofImageData data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return CGSize(width: width, height: height)
    }

    static func jpegData(from image: CGImage, maxWidth: CGFloat = thumbnailWidth, quality: CGFloat = 0.7) -> Data? {
        let scaled = scaled(image, maxWidth: maxWidth) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func scaled(_ image: CGImage, maxWidth: CGFloat) -> CGImage? {
        guard CGFloat(image.width) > maxWidth else { return image }
        let scale = maxWidth / CGFloat(image.width)
        let size = CGSize(width: maxWidth, height: (CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
