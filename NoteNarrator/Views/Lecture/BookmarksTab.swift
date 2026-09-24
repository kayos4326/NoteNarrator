//  BookmarksTab.swift
//  NoteNarrator

import SwiftUI

struct BookmarksTab: View {
    let session: LectureSession

    @State private var selectedSectionIndex = 0
    @State private var typedReference = ""
    @State private var note = ""

    var body: some View {
        let sections = session.notesSections
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved sections")
                    .font(.headline)
                Text("Click a bookmark to open that part of your notes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if session.lecture.bookmarks.isEmpty {
                emptyState
            } else {
                ForEach(session.lecture.bookmarks.sorted { $0.dateAdded > $1.dateAdded }) { bookmark in
                    BookmarkRow(
                        bookmark: bookmark,
                        section: session.sectionIndex(for: bookmark.reference).map { sections[$0] },
                        onOpen: { session.jumpToNotes(bookmark.reference) },
                        onDelete: { session.deleteBookmark(bookmark) }
                    )
                }
            }

            addForm(sections)
                .padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 28))
                .foregroundStyle(Color.brandAccent)
            Text("No bookmarks yet")
                .font(.headline)
            Text("Bookmark a section in Notes, or use the bookmark button after answering a quiz question.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .studyCard(padding: 28)
    }

    private func addForm(_ sections: [NotesSection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Add Bookmark", systemImage: "bookmark")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if sections.isEmpty {
                    TextField("Reference (e.g. Slide 4)", text: $typedReference)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                } else {
                    Picker("Section", selection: $selectedSectionIndex) {
                        ForEach(sections) { section in
                            Text(ReferenceMatcher.displayName(for: section.reference)).tag(section.index)
                        }
                    }
                    .fixedSize()
                }
                TextField("Your note (optional)", text: $note)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let reference = sections.isEmpty
                        ? typedReference
                        : sections[sections.indices.contains(selectedSectionIndex) ? selectedSectionIndex : 0].reference
                    session.addBookmark(reference: reference, note: note)
                    typedReference = ""
                    note = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(sections.isEmpty && typedReference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .studyCard()
    }
}
