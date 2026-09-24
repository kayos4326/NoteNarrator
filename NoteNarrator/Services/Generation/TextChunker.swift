//  TextChunker.swift
//  NoteNarrator

import Foundation

/// Text with its slide, page, or time reference.
struct SourceChunk: Sendable {
    let text: String
    let reference: String
}

/// Splits source text for the on-device model without losing references.
nonisolated enum TextChunker {

    // Small sections give the model a better chance to keep the details.
    static let singlePassLimit = 2200
    static let targetChunkSize = 1800

    static func splitIntoChunks(_ text: String) -> [SourceChunk] {
        let rawChunks = text.count <= singlePassLimit ? [text] : packIntoChunks(splitIntoBlocks(text), fallback: text)

        // A split continuation uses the preceding source heading.
        var lastHeading: String?
        return rawChunks.enumerated().map { index, chunkText in
            let markers = markers(in: chunkText)
            let reference = label(for: markers) ?? lastHeading ?? "Part \(index + 1)"
            if let last = markers.last { lastHeading = label(for: [last]) }
            return SourceChunk(text: chunkText, reference: reference)
        }
    }

    static func isSectionBoundary(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let markers = ["slide ", "page ", "chapter ", "section ", "part ", "lecture ", "topic ", "unit "]
        let lower = trimmed.lowercased()
        if markers.contains(where: lower.hasPrefix) || trimmed.hasPrefix("#") || timecodeHeading(trimmed) != nil {
            return true
        }

        // Short all-caps lines are usually slide titles.
        return trimmed.count < 60
            && trimmed == trimmed.uppercased()
            && trimmed.rangeOfCharacter(from: .letters) != nil
    }

    /// Label a chunk from its source headings, or use Part N if there are none.
    static func referenceLabel(for text: String, index: Int) -> String {
        label(for: markers(in: text)) ?? "Part \(index)"
    }

    /// A source marker found in a transcript heading.
    private enum Marker {
        case numbered(kind: String, number: Int)
        case time(start: String, end: String)
    }

    private static func markers(in text: String) -> [Marker] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let time = timecodeHeading(trimmed) {
                return .time(start: time.start, end: time.end)
            }
            let lower = trimmed.lowercased()
            for kind in ["slide", "page"] where lower.hasPrefix(kind + " ") {
                return Int(lower.dropFirst(kind.count + 1).prefix(while: \.isNumber))
                    .map { .numbered(kind: kind, number: $0) }
            }
            return nil
        }
    }

    /// Format the markers as a slide, page, or time range.
    private static func label(for markers: [Marker]) -> String? {
        let times = markers.compactMap { marker -> (start: String, end: String)? in
            if case let .time(start, end) = marker { return (start, end) }
            return nil
        }
        if let first = times.first, let last = times.last {
            return first.start == last.end ? first.start : "\(first.start)–\(last.end)"
        }

        let numbered = markers.compactMap { marker -> (kind: String, number: Int)? in
            if case let .numbered(kind, number) = marker { return (kind, number) }
            return nil
        }
        guard let kind = numbered.first?.kind else { return nil }
        let numbers = numbered.filter { $0.kind == kind }.map(\.number)
        guard let first = numbers.first, let last = numbers.last else { return nil }
        let name = kind == "slide" ? "Slide" : "Page"
        return first == last ? "\(name) \(first)" : "\(name)s \(first)–\(last)"
    }

    /// Accept recording headings such as "Time 1:30–3:00:".
    private static func timecodeHeading(_ line: String) -> (start: String, end: String)? {
        guard line.lowercased().hasPrefix("time ") else { return nil }
        let value = line.dropFirst("time ".count).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        let bounds = value.components(separatedBy: CharacterSet(charactersIn: "–-")).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let start = bounds.first, Timecode.seconds(from: start) != nil else { return nil }
        let end = bounds.count > 1 && Timecode.seconds(from: bounds[1]) != nil ? bounds[1] : start
        return (start, end)
    }

    private static func splitIntoBlocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []

        func closeBlock() {
            let block = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty { blocks.append(block) }
            current = []
        }

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeBlock()
            } else {
                if isSectionBoundary(line) { closeBlock() }
                current.append(line)
            }
        }
        closeBlock()
        return blocks
    }

    private static func packIntoChunks(_ blocks: [String], fallback: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for block in blocks {
            // Never put two recording intervals under one time reference.
            let startsNewTime = block.components(separatedBy: .newlines).first
                .flatMap(timecodeHeading) != nil
            if !current.isEmpty && (startsNewTime || current.count + block.count > targetChunkSize) {
                chunks.append(current)
                current = block
            } else {
                current += current.isEmpty ? block : "\n\n" + block
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [fallback] : chunks
    }

    /// Split a failed section in two, keeping its original reference.
    static func retryPieces(of chunk: SourceChunk) -> [SourceChunk] {
        let blocks = chunk.text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard blocks.count > 1 else { return [chunk] }
        let midpoint = chunk.text.count / 2
        let split = (1..<blocks.count).min { left, right in
            let leftLength = blocks[..<left].reduce(0) { $0 + $1.count + 2 }
            let rightLength = blocks[..<right].reduce(0) { $0 + $1.count + 2 }
            return abs(leftLength - midpoint) < abs(rightLength - midpoint)
        } ?? 1
        let first = blocks[..<split].joined(separator: "\n\n")
        let second = blocks[split...].joined(separator: "\n\n")
        return [SourceChunk(text: first, reference: chunk.reference),
                SourceChunk(text: second, reference: chunk.reference)]
    }
}
