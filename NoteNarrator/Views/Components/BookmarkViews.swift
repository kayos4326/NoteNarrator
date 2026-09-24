//  BookmarkViews.swift
//  NoteNarrator

import SwiftUI

/// The student's own note on a bookmark, shown inside the notes section it points at.
struct BookmarkNoteField: View {
    @Bindable var bookmark: Bookmark
    let showsReference: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsReference {
                Text("Bookmarked from \(ReferenceMatcher.displayName(for: bookmark.reference))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Color.brandAccent)
                TextField("Add your own note to this bookmark…", text: $bookmark.note, axis: .vertical)
                    .textFieldStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.brandAccent.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.brandAccent.opacity(0.25), lineWidth: 1)
        )
    }
}

struct BookmarkRow: View {
    @Bindable var bookmark: Bookmark
    let section: NotesSection?
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(Color.brandAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ReferenceMatcher.displayName(for: bookmark.reference)).font(.headline)
                            details
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Notes")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete bookmark")
                .accessibilityLabel("Delete bookmark")
            }

            TextField("Add a note…", text: $bookmark.note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
        .studyCard(padding: 14)
    }

    @ViewBuilder
    private var details: some View {
        if let section {
            if !section.preview.isEmpty {
                Text(section.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if ReferenceMatcher.normalize(section.reference) != ReferenceMatcher.normalize(bookmark.reference) {
                Text("In notes under \(ReferenceMatcher.displayName(for: section.reference))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Not found in the current notes")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}
