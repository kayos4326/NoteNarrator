//  VideoFrameExtractor.swift
//  NoteNarrator

import AVFoundation
import CoreGraphics
import Foundation

/// A slide that was on screen in a video, with whatever text could be read from it.
nonisolated struct SlideFrame: Sendable {
    let seconds: Double
    let text: String
    let imageData: Data
    let hasReadableText: Bool
}

/// Reads the slides shown in a lecture video. Frames are sampled a few seconds apart, frames
/// that look like the one before are dropped, and only the remaining slide changes are read.
nonisolated enum VideoFrameExtractor {

    /// At most this many frames are looked at, however long the video is.
    private static let maxSamples = 90
    private static let minimumInterval: Double = 2
    private static let maximumInterval: Double = 10

    static func slideFrames(
        from url: URL,
        budget: inout ExtractionBudget,
        progress: @Sendable (_ seconds: Double, _ duration: Double) -> Void = { _, _ in }
    ) async -> [SlideFrame] {
        let asset = AVURLAsset(url: url)
        guard let hasVideo = try? await !asset.loadTracks(withMediaType: .video).isEmpty, hasVideo,
              let duration = try? await asset.load(.duration).seconds, duration > 1
        else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)

        let interval = min(max(duration / Double(maxSamples), minimumInterval), maximumInterval)
        generator.requestedTimeToleranceBefore = CMTime(seconds: interval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: interval / 2, preferredTimescale: 600)

        // Spread the pictures that may be read across the whole video, so a busy opening
        // (a playing clip, scrolling) can't use them all up in the first minute.
        let minimumGap = max(interval, duration / Double(budget.maxImages))

        var frames: [SlideFrame] = []
        var lastSignature: FrameSignature?
        var lastKeptTime = -Double.infinity
        var seconds = interval / 2

        while seconds < duration {
            if Task.isCancelled { break }
            progress(seconds, duration)

            let time = seconds
            seconds += interval
            guard let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image,
                  let signature = FrameSignature(of: image)
            else { continue }

            // Same slide as the frame before: nothing new to read.
            if let lastSignature, !signature.isDifferentSlide(from: lastSignature) { continue }
            lastSignature = signature
            guard time - lastKeptTime >= minimumGap else { continue }

            guard budget.takeSlot() else { continue }
            let text = await OCRExtractor.readText(in: image)
            guard OCRExtractor.isReadable(text) else { continue }

            // A slide can come back later, or stay up while a clip or cursor moves over it —
            // don't keep it again when it reads mostly the same.
            if frames.contains(where: { TextMerge.similarity($0.text, text) >= 0.6 }) { continue }

            guard let data = ImageTools.jpegData(from: image) else { continue }
            frames.append(SlideFrame(seconds: time, text: text, imageData: data, hasReadableText: true))
            lastKeptTime = time
        }
        return frames
    }
}
