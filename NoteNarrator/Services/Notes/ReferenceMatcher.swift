//  ReferenceMatcher.swift
//  NoteNarrator

import Foundation

/// Resolves a reference like "Slide 4" to the notes section that covers it (e.g. "Slides 1–8").
/// Quiz questions, bookmarks, and notes are generated at different times — possibly with
/// different chunk boundaries — so exact string matching alone isn't reliable.
nonisolated enum ReferenceMatcher {

    struct ReferenceRange: Equatable {
        let kind: String
        let lower: Int
        let upper: Int
    }

    /// How far outside a section's range a reference may fall and still resolve to it,
    /// covering sections that were skipped because their extraction failed. Pages and slides
    /// count in units; recordings count in seconds, where one block of a recording is 90.
    private static func nearbyTolerance(for kind: String) -> Int {
        kind == "time" ? 90 : 2
    }

    /// How a reference is shown to the student. Notes saved before unmarked documents were
    /// numbered in "Parts" still say "Chunk 3"; that reads as "Part 3".
    static func displayName(for reference: String) -> String {
        guard reference.lowercased().hasPrefix("chunk ") else { return reference }
        return "Part " + reference.dropFirst("chunk ".count)
    }

    static func normalize(_ reference: String) -> String {
        reference
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: \.isWhitespace)
            // Trailing colons come from headings like "Slide 4:"; colons inside a timecode stay.
            .map { $0.hasSuffix(":") ? String($0.dropLast()) : String($0) }
            .joined(separator: " ")
    }

    static func parse(_ reference: String) -> ReferenceRange? {
        let normalized = normalize(reference)
        if let time = parseTimecodeRange(normalized) { return time }

        let parts = normalized.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        var kind = parts[0]
        if kind.hasSuffix("s") { kind.removeLast() }
        // Unmarked documents were once numbered "Chunk N"; notes saved then still resolve.
        if kind == "chunk" { kind = "part" }
        guard ["slide", "page", "part"].contains(kind) else { return nil }

        let bounds = parts[1].split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = bounds.first, let lower = Int(first) else { return nil }
        let upper = bounds.count > 1 ? (Int(bounds[1]) ?? lower) : lower
        return ReferenceRange(kind: kind, lower: min(lower, upper), upper: max(lower, upper))
    }

    /// Index of the section that best covers `target`, or nil when nothing plausibly does.
    static func bestSectionIndex(for target: String, in sectionReferences: [String]) -> Int? {
        let normalizedTarget = normalize(target)
        if let exact = sectionReferences.firstIndex(where: { normalize($0) == normalizedTarget }) {
            return exact
        }
        guard let wanted = parse(target) else { return nil }

        var best: (index: Int, overlap: Int, distance: Int)?
        for (index, reference) in sectionReferences.enumerated() {
            guard let candidate = parse(reference), areCompatible(candidate.kind, wanted.kind) else { continue }

            let overlap = max(0, min(candidate.upper, wanted.upper) - max(candidate.lower, wanted.lower) + 1)
            let distance = overlap > 0
                ? 0
                : min(abs(candidate.lower - wanted.upper), abs(wanted.lower - candidate.upper))
            guard overlap > 0 || distance <= nearbyTolerance(for: wanted.kind) else { continue }

            if let current = best {
                if overlap > current.overlap || (overlap == current.overlap && distance < current.distance) {
                    best = (index, overlap, distance)
                }
            } else {
                best = (index, overlap, distance)
            }
        }
        return best?.index
    }

    /// References in recordings are timecodes: "12:30" or "12:30–15:00", in seconds.
    private static func parseTimecodeRange(_ normalized: String) -> ReferenceRange? {
        guard !normalized.contains(" "), normalized.contains(":") else { return nil }
        let bounds = normalized.split(separator: "-").map(String.init)
        guard let first = bounds.first, let lower = Timecode.seconds(from: first) else { return nil }
        let upper = bounds.count > 1 ? (Timecode.seconds(from: bounds[1]) ?? lower) : lower
        return ReferenceRange(kind: "time", lower: Int(min(lower, upper)), upper: Int(max(lower, upper)))
    }

    /// Slides and pages are both numbered units of the source, so a student typing "Page 4"
    /// for a slide deck should still land in the right place. Part numbers and timecodes
    /// only compare with their own kind.
    private static func areCompatible(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        return ![a, b].contains(where: { $0 == "part" || $0 == "time" })
    }
}
