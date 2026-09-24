//  MarkdownText.swift
//  NoteNarrator

import SwiftUI

/// Renders the light markdown the model tends to produce — headings, bullet lists, **bold** —
/// instead of showing the raw `#` and `**` characters.
struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text(Self.attributed(source))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func attributed(_ source: String) -> AttributedString {
        let lines = source.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                return heading.isEmpty ? "" : "**\(heading.replacingOccurrences(of: "**", with: ""))**"
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return "• " + trimmed.dropFirst(2)
            }
            return line
        }
        let markdown = lines.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(source)
    }
}
