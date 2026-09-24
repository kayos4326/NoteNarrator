//  OfficeArchive.swift
//  NoteNarrator

import Foundation
import ZIPFoundation

/// Shared helpers for .docx and .pptx files, which are zip archives of XML parts.
nonisolated extension Archive {

    func data(at path: String) -> Data? {
        guard let entry = self[path] else { return nil }
        var data = Data()
        do {
            _ = try extract(entry) { data.append($0) }
        } catch {
            return nil
        }
        return data
    }

    func string(at path: String) -> String? {
        data(at: path).flatMap { String(data: $0, encoding: .utf8) }
    }
}

nonisolated enum OfficeXML {

    /// Strips tags from an Office XML part, turning each paragraph end into a newline.
    static func plainText(from xml: String, paragraphEndTag: String) -> String {
        xml.replacingOccurrences(of: paragraphEndTag, with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
