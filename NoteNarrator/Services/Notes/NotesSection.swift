//  NotesSection.swift
//  NoteNarrator

import Foundation

/// One chunk's section of a lecture's notes: its source reference plus titled groups of bullets.
nonisolated struct NotesSection: Identifiable, Equatable {

    struct Group: Equatable {
        let title: String
        let items: [String]
    }

    let index: Int
    let reference: String
    let groups: [Group]

    var id: String { "notes-section-\(index)" }

    /// The first few bullets, for a one-line preview.
    var preview: String {
        groups.flatMap(\.items).prefix(3).joined(separator: " · ")
    }

    /// Headings to show for each section. A long page or stretch of a recording can span several
    /// sections that share one reference; the later ones read "(continued)" so they're told apart.
    static func displayTitles(for sections: [NotesSection]) -> [String] {
        var seen = Set<String>()
        return sections.map { section in
            let key = ReferenceMatcher.normalize(section.reference)
            defer { seen.insert(key) }
            let name = ReferenceMatcher.displayName(for: section.reference)
            return seen.contains(key) ? "\(name) (continued)" : name
        }
    }

    /// Parses notes produced by `AIGenerator.formatKnowledgeAsNotes`, joined by the section separator.
    static func parse(_ notes: String) -> [NotesSection] {
        notes
            .components(separatedBy: AIGenerator.notesSectionSeparator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, block in parseSection(block, index: index) }
    }

    private static func parseSection(_ block: String, index: Int) -> NotesSection {
        var lines = block.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let reference = lines.removeFirst()

        var groups: [Group] = []
        var title = ""
        var items: [String] = []

        func closeGroup() {
            if !items.isEmpty || !title.isEmpty {
                groups.append(Group(title: title, items: items))
            }
            title = ""
            items = []
        }

        for line in lines where !line.isEmpty {
            if line.hasPrefix("- ") {
                items.append(String(line.dropFirst(2)))
            } else if line.hasSuffix(":") {
                closeGroup()
                title = String(line.dropLast())
            } else {
                items.append(line)
            }
        }
        closeGroup()

        return NotesSection(index: index, reference: reference, groups: groups)
    }
}
