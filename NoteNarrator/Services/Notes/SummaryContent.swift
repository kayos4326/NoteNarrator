//  SummaryContent.swift
//  NoteNarrator

import Foundation

/// A generated summary split into its overview paragraphs and its key-point bullets, so the two
/// can be shown separately. The model's formatting varies, so headings and labels are dropped
/// and any list style counts as a key point.
struct SummaryContent: Equatable {
    let overview: [String]
    let keyPoints: [String]

    static func parse(_ summary: String) -> SummaryContent {
        var paragraphs: [String] = []
        var paragraph: [String] = []
        var keyPoints: [String] = []

        func closeParagraph() {
            if !paragraph.isEmpty {
                paragraphs.append(paragraph.joined(separator: " "))
                paragraph = []
            }
        }

        for rawLine in summary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                closeParagraph()
            } else if let point = listItem(line) {
                closeParagraph()
                // An indented bullet belongs to the one above it ("Staff Roles:" and its duties),
                // so it joins that key point instead of becoming a card of its own.
                if isIndented(rawLine), let parent = keyPoints.popLast() {
                    keyPoints.append(joined(parent, point))
                } else {
                    keyPoints.append(point)
                }
            } else if isHeading(line) {
                closeParagraph()
            } else {
                paragraph.append(line)
            }
        }
        closeParagraph()

        return SummaryContent(overview: paragraphs, keyPoints: keyPoints)
    }

    /// The text of a "- ", "* ", "• ", "1. " or "1) " list line.
    private static func listItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return clean(line.dropFirst(marker.count))
        }
        let digits = line.prefix(while: \.isNumber)
        let rest = line.dropFirst(digits.count)
        if !digits.isEmpty, rest.hasPrefix(". ") || rest.hasPrefix(") ") {
            return clean(rest.dropFirst(2))
        }
        return nil
    }

    private static let labels: Set<String> = ["summary", "overview", "key points", "key takeaways", "main points"]

    /// "### Summary", "**Key Points:**", "Summary:" and similar labels.
    private static func isHeading(_ line: String) -> Bool {
        if line.hasPrefix("#") { return true }
        let bare = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("**") && bare.hasSuffix(":") { return true }
        let label = bare.hasSuffix(":") ? String(bare.dropLast()) : bare
        return labels.contains(label.lowercased())
    }

    private static func isIndented(_ line: String) -> Bool {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count >= 2
    }

    private static func joined(_ parent: String, _ child: String) -> String {
        let endsSentence = [":", ":**", "."].contains(where: parent.hasSuffix)
        return parent + (endsSentence ? " " : "; ") + child
    }

    private static func clean(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
