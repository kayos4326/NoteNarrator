//  MediaExtractor.swift
//  NoteNarrator

import AVFoundation
import Foundation

/// Combines speech and text read from video frames into timecoded study text.
nonisolated enum MediaExtractor {

    /// Length of each recording section in seconds.
    static let blockSeconds: Double = 90

    /// A transcription error passed back to the import task.
    struct TranscriptionFailure: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    static func extract(from url: URL, progress: @escaping ExtractionProgress) async throws -> ExtractedContent {
        progress("Transcribing the recording…")

        // Read audio and frames in parallel.
        async let listening = transcribe(url)
        async let watching = readSlides(url, progress: progress)
        let (spoken, speechFailure) = await listening
        let (frames, budget) = await watching

        // Report an empty import instead of making a blank lecture.
        if spoken.isEmpty && frames.isEmpty, let speechFailure {
            throw speechFailure
        }

        var content = ExtractedContent()
        let duration = try? await AVURLAsset(url: url).load(.duration).seconds
        content.text = transcriptText(spoken: spoken, frames: frames, duration: duration)
        content.figures = frames.map {
            ExtractedFigure(reference: Timecode.label($0.seconds),
                            imageData: $0.imageData,
                            hasReadableText: $0.hasReadableText)
        }
        content.notice = notice(spokenIsEmpty: spoken.isEmpty, frames: frames,
                                couldNotTranscribe: speechFailure != nil, budget: budget)
        return content
    }

    private static func transcribe(_ url: URL) async -> ([SpokenSegment], TranscriptionFailure?) {
        do {
            return (try await AudioTranscriber.transcribe(url: url), nil)
        } catch {
            return ([], TranscriptionFailure(message: error.localizedDescription))
        }
    }

    private static func readSlides(_ url: URL, progress: @escaping ExtractionProgress) async -> ([SlideFrame], ExtractionBudget) {
        var budget = ExtractionBudget.videoFrames()
        let frames = await VideoFrameExtractor.slideFrames(from: url, budget: &budget) { seconds, duration in
            progress("Transcribing and reading the slides in the video (\(Timecode.label(seconds)) of \(Timecode.label(duration)))…")
        }
        return (frames, budget)
    }

    /// Put on-screen text and speech under the time interval where they occurred.
    static func transcriptText(spoken: [SpokenSegment], frames: [SlideFrame],
                               blockSeconds: Double = blockSeconds, duration: Double? = nil) -> String {
        var blocks: [Int: (slides: [String], words: [String])] = [:]
        let spokenText = spoken.map(\.text).joined(separator: " ")
        let logicGateLesson = spokenText.localizedCaseInsensitiveContains("and gate")
            || spokenText.localizedCaseInsensitiveContains("or gate")
            || frames.contains { $0.text.localizedCaseInsensitiveContains("NOT") }

        for frame in frames {
            let index = Int(frame.seconds / blockSeconds)
            blocks[index, default: ([], [])].slides.append(
                "On screen at \(Timecode.label(frame.seconds)):\n\(frame.text)")
        }
        for segment in spoken {
            let index = Int(segment.seconds / blockSeconds)
            blocks[index, default: ([], [])].words.append(segment.text)
        }

        return blocks.keys.sorted().compactMap { index -> String? in
            guard let block = blocks[index] else { return nil }
            let start = Double(index) * blockSeconds
            let end = duration.flatMap { $0.isFinite && $0 > start ? min(start + blockSeconds, $0) : nil }
                ?? start + blockSeconds
            var parts = ["Time \(Timecode.label(start))–\(Timecode.label(end)):"]
            parts.append(contentsOf: block.slides)
            let rawWords = block.words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let words = logicGateLesson ? normalizedLogicGateTerms(in: rawWords) : rawWords
            if !words.isEmpty { parts.append("Spoken:\n" + words) }
            return parts.count > 1 ? parts.joined(separator: "\n") : nil
        }
        .joined(separator: "\n\n")
    }

    /// Correct common logic-gate transcription errors in a confirmed gate lesson.
    static func normalizedLogicGateTerms(in text: String) -> String {
        text.replacingOccurrences(of: "\\bknot gate\\b", with: "NOT gate",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\blogic dates?\\b", with: "logic gates",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\blogic aids?\\b", with: "logic gates",
                                  options: [.regularExpression, .caseInsensitive])
    }

    private static func notice(spokenIsEmpty: Bool, frames: [SlideFrame], couldNotTranscribe: Bool, budget: ExtractionBudget) -> String {
        var lines: [String] = []
        if spokenIsEmpty, !frames.isEmpty {
            lines.append(!couldNotTranscribe
                ? "No speech was found in this recording, so the notes come from the slides shown on screen."
                : "The recording couldn't be transcribed, so the notes come from the slides shown on screen.")
        }
        if !budget.notice.isEmpty { lines.append(budget.notice) }
        return lines.joined(separator: " ")
    }
}
