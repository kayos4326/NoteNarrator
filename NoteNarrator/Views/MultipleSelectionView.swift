//  MultipleSelectionView.swift
//  NoteNarrator

import SwiftData
import SwiftUI

/// Shown when several lectures are selected in the sidebar: organize or delete them together.
struct MultipleSelectionView: View {
    let lectures: [Lecture]
    let actions: LibraryActions

    @Query(sort: \Folder.name) private var folders: [Folder]

    private static let listedLimit = 8

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.brandAccent.opacity(0.14)))

                VStack(spacing: 4) {
                    Text("\(lectures.count) lectures selected")
                        .font(.title2.bold())
                    Text("Move them into a folder, pin them, or delete them together.")
                        .foregroundStyle(.secondary)
                }

                titles

                HStack(spacing: 10) {
                    Button("New Folder with These…", systemImage: "folder.badge.plus") {
                        actions.startNewFolder(moving: lectures)
                    }
                    .buttonStyle(.borderedProminent)

                    MoveToFolderMenu(lectures: lectures, folders: folders, actions: actions)
                        .fixedSize()

                    let allPinned = lectures.allSatisfy(\.isPinned)
                    Button(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin") {
                        LibraryActions.togglePin(lectures)
                    }
                }
                .controlSize(.large)

                Button("Delete \(lectures.count) Lectures…", systemImage: "trash", role: .destructive) {
                    actions.requestDelete(lectures)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)

                Text("⌘-click or ⇧-click lectures in the sidebar to change the selection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lectures.prefix(Self.listedLimit)) { lecture in
                Label {
                    Text(lecture.title)
                        .lineLimit(1)
                    Spacer()
                    if let folder = lecture.folder {
                        Text(folder.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: LectureRow.symbolName(forExtension: lecture.fileExtension))
                        .foregroundStyle(Color.brandAccent)
                }
            }
            if lectures.count > Self.listedLimit {
                Text("and \(lectures.count - Self.listedLimit) more")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .studyCard(padding: 16)
    }
}
