//  OCRExtractor.swift
//  NoteNarrator

import CoreGraphics
import Foundation
import Vision

/// Reads the words in a picture with Vision's on-device document recognition, which returns
/// paragraphs, bullet lists, and real tables instead of loose lines — so a table on a slide
/// stays a table and two-column slides read in the right order.
nonisolated enum OCRExtractor {

    static func readText(in image: CGImage) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true

        guard let observation = try? await request.perform(on: image).first else { return "" }
        return text(of: observation.document)
    }

    /// Flattens a recognized document: title, paragraphs, lists as bullets, tables row by row.
    /// The recognizer also reports a table's cells and a list's items as paragraphs, so those
    /// are skipped here instead of appearing twice.
    static func text(of container: DocumentObservation.Container) -> String {
        let tableAreas = container.tables.map { $0.boundingRegion.normalizedPath.boundingBox.insetBy(dx: -0.01, dy: -0.01) }
        func isInsideTable(_ text: DocumentObservation.Container.Text) -> Bool {
            let box = text.boundingRegion.normalizedPath.boundingBox
            return tableAreas.contains { $0.contains(CGPoint(x: box.midX, y: box.midY)) }
        }

        var lines: [String] = []
        var collected = ""
        func add(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TextMerge.normalize(trimmed)
            // Checked against everything so far as one run of text, so a line the recognizer
            // split in two elsewhere still counts as already said.
            guard !key.isEmpty, !collected.contains(key) else { return }
            lines.append(trimmed)
            collected += key
        }

        if let title = container.title { add(title.transcript) }
        container.paragraphs.filter { !isInsideTable($0) }.forEach { add($0.transcript) }
        container.lists.flatMap(\.items).forEach { add("- " + $0.itemString) }
        for table in container.tables {
            for row in table.rows {
                let cells = row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard cells.contains(where: { !$0.isEmpty }) else { continue }
                add(cells.joined(separator: " | "))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// A picture counts as readable when recognition found words, not a stray number or axis
    /// label. A slide title like "Minimum Edit Distance" counts; "Fig 3" doesn't.
    static func isReadable(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.count >= 2 && text.count >= 10
    }
}
