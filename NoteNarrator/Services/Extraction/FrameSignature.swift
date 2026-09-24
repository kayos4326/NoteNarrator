//  FrameSignature.swift
//  NoteNarrator

import CoreGraphics
import Foundation

/// A coarse grayscale thumbnail of a video frame, used to tell when the video has moved on to
/// the next slide. Comparing thumbnails cell by cell ignores a webcam bubble or a moving mouse
/// pointer (a few cells) but catches a new slide (a large part of the picture changes).
nonisolated struct FrameSignature: Sendable, Equatable {

    /// Grid the frame is reduced to, roughly 16:9.
    static let columns = 64
    static let rows = 36

    /// How different one cell's brightness must be to count as changed (0–255).
    private static let cellChangeThreshold = 16
    /// How much of the picture must change before it counts as a new slide.
    private static let slideChangeFraction = 0.02

    let cells: [UInt8]

    init?(of image: CGImage) {
        var cells = [UInt8](repeating: 0, count: Self.columns * Self.rows)
        let drawn: Bool = cells.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: Self.columns,
                height: Self.rows,
                bitsPerComponent: 8,
                bytesPerRow: Self.columns,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.columns, height: Self.rows))
            return true
        }
        guard drawn else { return nil }
        self.cells = cells
    }

    /// The share of the picture that changed, from 0 (identical) to 1.
    func changeFraction(from other: FrameSignature) -> Double {
        guard cells.count == other.cells.count, !cells.isEmpty else { return 1 }
        let changed = zip(cells, other.cells).count { abs(Int($0) - Int($1)) > Self.cellChangeThreshold }
        return Double(changed) / Double(cells.count)
    }

    func isDifferentSlide(from other: FrameSignature) -> Bool {
        changeFraction(from: other) > Self.slideChangeFraction
    }
}
