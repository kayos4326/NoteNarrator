//  PptxExtractor.swift
//  NoteNarrator

import CoreGraphics
import Foundation
import ZIPFoundation

nonisolated enum PptxExtractor {

    /// Pictures smaller than this are bullets, icons, and dividers.
    private static let minimumPixels: CGFloat = 200
    /// Reading more than a couple of pictures per slide rarely adds anything.
    private static let maxPicturesPerSlide = 2

    static func extract(from url: URL, budget: inout ExtractionBudget, progress: ExtractionProgress) async -> ExtractedContent {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return ExtractedContent()
        }

        // First pass: the slides, in the order the deck shows them, and the pictures each one uses.
        let order = slideOrder(
            presentationXML: archive.string(at: "ppt/presentation.xml"),
            relationshipsXML: archive.string(at: "ppt/_rels/presentation.xml.rels"),
            slidePaths: archive.map(\.path).filter(isSlidePath)
        )
        var slides: [(number: Int, xml: String, imagePaths: [String])] = []
        for path in order {
            guard let xml = archive.string(at: path) else { continue }
            slides.append((slides.count + 1, xml, imagePaths(forSlideAt: path, in: archive)))
        }
        let decoration = decorationImages(in: slides.map(\.imagePaths))

        var content = ExtractedContent()
        var sections: [String] = []

        for slide in slides {
            if Task.isCancelled { break }
            progress("Reading slide \(slide.number) of \(slides.count)…")

            let reference = "Slide \(slide.number)"
            let typed = OfficeXML.plainText(from: slide.xml, paragraphEndTag: "</a:p>")
            var text = typed

            let pictures = slide.imagePaths
                .filter { !decoration.contains($0) }
                .compactMap { path -> (data: Data, area: CGFloat)? in
                    guard let data = archive.data(at: path), let size = ImageTools.pixelSize(ofImageData: data),
                          size.width >= minimumPixels, size.height >= minimumPixels else { return nil }
                    return (data, size.width * size.height)
                }
                .sorted { $0.area > $1.area }
                .prefix(maxPicturesPerSlide)

            var readable = false
            for picture in pictures {
                guard budget.takeSlot(), let image = ImageTools.image(from: picture.data) else { continue }
                let pictureText = await OCRExtractor.readText(in: image)
                if OCRExtractor.isReadable(pictureText) { readable = true }
                text = TextMerge.merge(typed: text, fromPicture: pictureText)
            }

            // The slide's main picture is kept so the student can look at the diagram itself.
            if let largest = pictures.first, let image = ImageTools.image(from: largest.data),
               let data = ImageTools.jpegData(from: image) {
                content.figures.append(ExtractedFigure(reference: reference,
                                                       imageData: data,
                                                       hasReadableText: readable))
            }

            if !text.isEmpty {
                sections.append("\(reference):\n\(text)")
            }
        }

        content.text = sections.joined(separator: "\n\n")
        content.notice = budget.notice
        return content
    }

    /// Logos and template art repeat across slides: reading them every time is slow and fills
    /// the notes with the same words over and over.
    static func decorationImages(in slideImagePaths: [[String]], appearingOnAtLeast threshold: Int = 3) -> Set<String> {
        var counts: [String: Int] = [:]
        for paths in slideImagePaths {
            for path in Set(paths) { counts[path, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value >= threshold }.keys)
    }

    /// Slide files in the order the deck presents them. Slide files keep the number they were
    /// created with, so once slides are moved or deleted the file numbers have gaps and no longer
    /// match what the student sees; the presentation's own slide list is the real order.
    static func slideOrder(presentationXML: String?, relationshipsXML: String?, slidePaths: [String]) -> [String] {
        let available = Set(slidePaths)
        if let presentationXML, let relationshipsXML {
            let targets = relationshipTargets(in: relationshipsXML)
            let ordered = matches(of: #"<p:sldId\b[^>]*\br:id="([^"]+)""#, in: presentationXML)
                .compactMap { targets[$0] }
                .map(resolvedSlidePath)
                .filter(available.contains)
            if !ordered.isEmpty { return ordered }
        }
        // No slide list to follow: fall back to the file numbers, compared as numbers (2 before 10).
        return slidePaths.sorted { slideFileNumber($0) < slideFileNumber($1) }
    }

    static func isSlidePath(_ path: String) -> Bool {
        path.hasPrefix("ppt/slides/slide") && path.hasSuffix(".xml") && !path.contains("/_rels/")
    }

    private static func slideFileNumber(_ path: String) -> Int {
        Int(path.dropFirst("ppt/slides/slide".count).prefix(while: \.isNumber)) ?? .max
    }

    /// "slides/slide3.xml" (relative to ppt/) or "/ppt/slides/slide3.xml" → "ppt/slides/slide3.xml".
    private static func resolvedSlidePath(_ target: String) -> String {
        target.hasPrefix("/") ? String(target.dropFirst()) : "ppt/" + target
    }

    /// Relationship ids mapped to their targets. Attributes can come in any order.
    private static func relationshipTargets(in xml: String) -> [String: String] {
        var targets: [String: String] = [:]
        for element in matches(of: #"(<Relationship\b[^>]*>)"#, in: xml) {
            if let id = matches(of: #"\bId="([^"]+)""#, in: element).first,
               let target = matches(of: #"\bTarget="([^"]+)""#, in: element).first {
                targets[id] = target
            }
        }
        return targets
    }

    /// Images embedded in one slide, resolved through its relationship file rather than
    /// taking every image in the deck's shared media folder.
    private static func imagePaths(forSlideAt path: String, in archive: Archive) -> [String] {
        let fileName = (path as NSString).lastPathComponent
        guard let rels = archive.string(at: "ppt/slides/_rels/\(fileName).rels") else { return [] }
        return mediaPaths(in: rels)
    }

    /// PowerPoint writers may use relative or package-root image targets.
    static func mediaPaths(in relationshipsXML: String) -> [String] {
        matches(of: #"Target="(?:\.\./media/|/ppt/media/)([^"]+)""#, in: relationshipsXML)
            .map { "ppt/media/\($0)" }
    }

    /// The first capture group of every match of `pattern`.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
