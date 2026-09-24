//  DocumentExtractor.swift
//  NoteNarrator

import Foundation

nonisolated enum DocumentExtractor {

    /// Reads a document: its typed text, the words in its pictures, and the pictures themselves.
    /// Each format decides which pictures are worth reading; a shared budget keeps the import quick.
    static func extract(from url: URL, progress: @escaping ExtractionProgress) async -> ExtractedContent {
        var budget = ExtractionBudget.documents()

        switch url.pathExtension.lowercased() {
        case "pdf":
            return await PDFExtractor.extract(from: url, budget: &budget, progress: progress)
        case "docx":
            return await DocxExtractor.extract(from: url, budget: &budget, progress: progress)
        case "pptx":
            return await PptxExtractor.extract(from: url, budget: &budget, progress: progress)
        case "txt", "text", "md":
            progress("Reading the file…")
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return ExtractedContent(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return ExtractedContent()
        }
    }
}
