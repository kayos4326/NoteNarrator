//  PDFExtractor.swift
//  NoteNarrator

import CoreGraphics
import Foundation
import PDFKit

nonisolated enum PDFExtractor {

    /// Below this many typed characters, a page is treated as a picture page even when no
    /// embedded image is found (charts and diagrams are often drawn, not photographed).
    private static let sparseTextThreshold = 120

    static func extract(from url: URL, budget: inout ExtractionBudget, progress: ExtractionProgress) async -> ExtractedContent {
        guard let pdf = PDFDocument(url: url) else { return ExtractedContent() }

        var content = ExtractedContent()
        var sections: [String] = []

        for index in 0..<pdf.pageCount {
            if Task.isCancelled { break }
            guard let page = pdf.page(at: index) else { continue }
            progress("Reading page \(index + 1) of \(pdf.pageCount)…")

            let reference = "Page \(index + 1)"
            let typed = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasPicture = PDFImageProbe.hasLargeImage(on: page)
            var text = typed

            if hasPicture || typed.count < sparseTextThreshold {
                if budget.takeSlot(), let image = ImageTools.render(page) {
                    let pictureText = await OCRExtractor.readText(in: image)
                    let readable = OCRExtractor.isReadable(pictureText)
                    text = TextMerge.merge(typed: typed, fromPicture: pictureText)

                    // Keep the page as a picture when it is one, or when reading it found little:
                    // the student can still look at the diagram themselves.
                    if hasPicture || !readable, let data = ImageTools.jpegData(from: image) {
                        content.figures.append(ExtractedFigure(reference: reference,
                                                               imageData: data,
                                                               hasReadableText: readable))
                    }
                }
            }

            if !text.isEmpty {
                sections.append("\(reference):\n\(text)")
            }
        }

        content.text = sections.joined(separator: "\n\n")
        content.notice = budget.notice
        return content
    }
}

/// Smaller images are bullets, rules, and logos. A file-scope constant because the callback
/// below becomes a C function pointer, which can't capture anything.
private let minimumImagePixels: CGPDFInteger = 200 * 200

/// Looks for embedded images in a PDF page without rendering it, so pages that are mostly
/// picture can be read with text recognition while plain text pages stay fast.
nonisolated enum PDFImageProbe {

    static func hasLargeImage(on page: PDFPage) -> Bool {
        guard let dictionary = page.pageRef?.dictionary else { return false }

        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return false }

        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else { return false }

        var found = false
        withUnsafeMutablePointer(to: &found) { pointer in
            CGPDFDictionaryApplyFunction(xObjects, { _, object, info in
                guard let info else { return }
                let found = info.assumingMemoryBound(to: Bool.self)
                guard !found.pointee else { return }

                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream),
                      let stream, let streamDictionary = CGPDFStreamGetDictionary(stream) else { return }

                var subtype: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(streamDictionary, "Subtype", &subtype),
                      let subtype, String(cString: subtype) == "Image" else { return }

                var width: CGPDFInteger = 0
                var height: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(streamDictionary, "Width", &width)
                CGPDFDictionaryGetInteger(streamDictionary, "Height", &height)
                if width * height >= minimumImagePixels { found.pointee = true }
            }, pointer)
        }
        return found
    }
}
