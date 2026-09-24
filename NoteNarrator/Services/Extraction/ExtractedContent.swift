//  ExtractedContent.swift
//  NoteNarrator

import Foundation

/// Reports what the import is doing right now, e.g. "Reading page 3 of 40…".
typealias ExtractionProgress = @Sendable (String) -> Void

/// A picture from a page, slide, or video frame, kept so the student can look at it even when
/// the app couldn't read any words in it.
nonisolated struct ExtractedFigure: Sendable {
    let reference: String       // "Page 12", "Slide 4", or a timecode like "12:30"
    let imageData: Data         // small JPEG
    let hasReadableText: Bool
}

/// Everything read out of one file: the text the AI works from, the pictures worth keeping,
/// and a note about anything that was skipped to keep the import quick.
nonisolated struct ExtractedContent: Sendable {
    var text: String = ""
    var figures: [ExtractedFigure] = []
    var notice: String = ""
}

/// Keeps an import quick: reading pictures is the slow part, so it's capped both by how many
/// pictures are read and by how long the whole file may take.
nonisolated struct ExtractionBudget: Sendable {
    let maxImages: Int
    let deadline: Date
    private(set) var imagesRead = 0
    private(set) var skipped = 0

    init(maxImages: Int, seconds: TimeInterval, now: Date = Date()) {
        self.maxImages = maxImages
        self.deadline = now.addingTimeInterval(seconds)
    }

    /// Documents: most decks are well under this, and a 200-page book still finishes.
    static func documents(now: Date = Date()) -> ExtractionBudget {
        ExtractionBudget(maxImages: 60, seconds: 75, now: now)
    }

    /// Video frames, on top of transcribing the audio.
    static func videoFrames(now: Date = Date()) -> ExtractionBudget {
        ExtractionBudget(maxImages: 24, seconds: 60, now: now)
    }

    /// Returns true when there's room to read one more picture; otherwise counts it as skipped.
    mutating func takeSlot(now: Date = Date()) -> Bool {
        guard imagesRead < maxImages, now < deadline else {
            skipped += 1
            return false
        }
        imagesRead += 1
        return true
    }

    var notice: String {
        guard skipped > 0 else { return "" }
        return "\(skipped) picture\(skipped == 1 ? " wasn't" : "s weren't") read, to keep this import quick, "
            + "so words inside \(skipped == 1 ? "it" : "them") may be missing from the notes."
    }
}

/// Timecodes for recordings, e.g. 75 seconds → "1:15" and 3725 → "1:02:05".
nonisolated enum Timecode {

    static func label(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Reads "1:15" or "1:02:05" back into seconds.
    static func seconds(from label: String) -> Double? {
        let parts = label.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap(Int.init)
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0.0) { $0 * 60 + Double($1) }
    }
}

/// Merges text read from a picture into the text that was already typed on the page, so a slide
/// that has both doesn't repeat itself.
nonisolated enum TextMerge {

    static func merge(typed: String, fromPicture ocr: String) -> String {
        let typedTrimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ocr.isEmpty else { return typedTrimmed }

        let haystack = normalize(typedTrimmed)
        var kept: [String] = []
        var seen = Set<String>()

        for line in ocr.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let key = normalize(trimmed)
            guard key.count >= 4, !seen.contains(key), !haystack.contains(key) else { continue }
            seen.insert(key)
            kept.append(trimmed)
        }

        guard !kept.isEmpty else { return typedTrimmed }
        let addition = kept.joined(separator: "\n")
        return typedTrimmed.isEmpty ? addition : typedTrimmed + "\n" + addition
    }

    /// How much two texts share, by their distinct words: 0 (nothing) to 1 (the same words).
    static func similarity(_ first: String, _ second: String) -> Double {
        let a = words(first), b = words(second)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }

    /// Lowercased letters and digits only, so spacing and punctuation differences don't matter.
    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
