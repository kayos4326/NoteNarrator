//  NotesTab.swift
//  NoteNarrator

import SwiftUI

struct NotesTab: View {
    let session: LectureSession

    var body: some View {
        let sections = session.notesSections
        if sections.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                if session.lecture.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(session.lecture.figures.isEmpty ? "No study text found" : "Pictures saved")
                            .font(.title3.weight(.semibold))
                        Text(session.lecture.figures.isEmpty
                             ? "This file has no readable text to make notes from."
                             : "The pictures are below. The on-device AI can read words in images, but cannot explain a diagram or photo without text.")
                            .foregroundStyle(.secondary)
                    }
                    .studyCard(padding: 20)
                } else {
                    GeneratePrompt(title: "Generate Notes", message: "No notes yet",
                                   detail: "Get organized notes for each part of the lecture, with page and slide references.",
                                   systemImage: "list.bullet.rectangle", action: .generateNotes, session: session)
                }
                if !session.lecture.figures.isEmpty {
                    FigureStrip(figures: session.lecture.orderedFigures)
                        .studyCard(padding: 20)
                }
            }
        } else {
            let bookmarksBySection = session.bookmarksBySection
            let figuresBySection = session.figuresBySection
            let titles = NotesSection.displayTitles(for: sections)
            VStack(alignment: .leading, spacing: 20) {
                header(sections, titles: titles)
                ForEach(sections) { section in
                    NotesSectionCard(
                        section: section,
                        title: titles[section.index],
                        bookmarks: bookmarksBySection[section.index] ?? [],
                        figures: figuresBySection[section.index] ?? [],
                        isHighlighted: session.highlightedSectionID == section.id,
                        onToggleBookmark: { session.toggleBookmark(for: section.reference) }
                    )
                    .id(section.id)
                }
                // Pictures from parts of the file the notes don't cover.
                if let extras = figuresBySection[-1], !extras.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Other pictures")
                            .font(.title3.weight(.semibold))
                        FigureStrip(figures: extras, showsHeading: false)
                    }
                    .studyCard(padding: 20)
                }
                GenerationButton(title: "Regenerate notes", systemImage: "arrow.clockwise",
                                 action: .generateNotes, session: session)
            }
        }
    }

    private func header(_ sections: [NotesSection], titles: [String]) -> some View {
        HStack {
            Text("\(sections.count) \(sections.count == 1 ? "section" : "sections")")
                .font(.headline)
            Spacer()
            if sections.count > 1 {
                Menu("Jump to section") {
                    ForEach(sections) { section in
                        Button(titles[section.index]) { session.jump(toSection: section) }
                    }
                }
                .fixedSize()
            }
        }
    }
}

private struct NotesSectionCard: View {
    let section: NotesSection
    let title: String
    let bookmarks: [Bookmark]
    let figures: [LectureFigure]
    let isHighlighted: Bool
    let onToggleBookmark: () -> Void

    private var isBookmarked: Bool { !bookmarks.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.brandAccent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: onToggleBookmark) {
                    Label(isBookmarked ? "Bookmarked" : "Bookmark",
                          systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.bordered)
                .tint(isBookmarked ? Color.brandAccent : nil)
                .help(isBookmarked ? "Remove this section's bookmark" : "Bookmark this section")
            }

            Divider()

            ForEach(Array(section.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 6) {
                    if !group.title.isEmpty {
                        SectionHeading(group.title)
                    }
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                        BulletText(item)
                    }
                }
            }

            if !figures.isEmpty {
                FigureStrip(figures: figures)
            }

            ForEach(bookmarks) { bookmark in
                BookmarkNoteField(
                    bookmark: bookmark,
                    showsReference: ReferenceMatcher.normalize(bookmark.reference)
                        != ReferenceMatcher.normalize(section.reference)
                )
            }
        }
        .studyCard(padding: 20, isHighlighted: isHighlighted, isOutlined: isBookmarked)
    }
}
