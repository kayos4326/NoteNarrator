//  DocxExtractor.swift
//  NoteNarrator

import CoreGraphics
import Foundation
import ZIPFoundation

nonisolated enum DocxExtractor {

    /// Pictures smaller than this are icons and dividers.
    private static let minimumPixels: CGFloat = 200

    static func extract(from url: URL, budget: inout ExtractionBudget, progress: ExtractionProgress) async -> ExtractedContent {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return ExtractedContent()
        }

        progress("Reading the document…")
        var content = ExtractedContent()
        content.text = archive.string(at: "word/document.xml")
            .map { OfficeXML.plainText(from: $0, paragraphEndTag: "</w:p>") } ?? ""

        let pictures = archive.map(\.path)
            .filter { $0.hasPrefix("word/media/") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }  // image2 before image10
            .compactMap { path -> Data? in
                guard let data = archive.data(at: path), let size = ImageTools.pixelSize(ofImageData: data),
                      size.width >= minimumPixels, size.height >= minimumPixels else { return nil }
                return data
            }

        var readTexts: [String] = []
        for (index, picture) in pictures.enumerated() {
            if Task.isCancelled { break }
            progress("Reading picture \(index + 1) of \(pictures.count)…")
            guard budget.takeSlot(), let image = ImageTools.image(from: picture) else { continue }

            let pictureText = await OCRExtractor.readText(in: image)
            let readable = OCRExtractor.isReadable(pictureText)
            if readable { readTexts.append("Picture \(index + 1):\n\(pictureText)") }
            if let data = ImageTools.jpegData(from: image) {
                content.figures.append(ExtractedFigure(reference: "Picture \(index + 1)",
                                                       imageData: data,
                                                       hasReadableText: readable))
            }
        }

        if !readTexts.isEmpty {
            content.text += "\n\n" + readTexts.joined(separator: "\n\n")
        }
        content.text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        content.notice = budget.notice
        return content
    }
}
