//  LibraryActions.swift
//  NoteNarrator

import Foundation
import Observation

/// Pending library changes that need a dialog (rename, new folder, delete), plus the edits that
/// apply to several lectures at once. Shared by the sidebar, which shows the dialogs, and the
/// multiple-selection view, which can start them.
@Observable
final class LibraryActions {
    enum RenameTarget {
        case lecture(Lecture)
        case folder(Folder)
    }

    var renameTarget: RenameTarget?
    var renameText = ""

    var isCreatingFolder = false
    var newFolderName = ""
    /// Lectures to move into the folder being created.
    private(set) var lecturesForNewFolder: [Lecture] = []

    var lecturesPendingDeletion: [Lecture] = []
    var folderPendingDeletion: Folder?

    func startRename(_ target: RenameTarget, name: String) {
        renameText = name
        renameTarget = target
    }

    func startNewFolder(moving lectures: [Lecture] = []) {
        lecturesForNewFolder = lectures
        newFolderName = ""
        isCreatingFolder = true
    }

    func finishNewFolder() {
        lecturesForNewFolder = []
    }

    func requestDelete(_ lectures: [Lecture]) {
        lecturesPendingDeletion = lectures
    }

    // MARK: - Edits on several lectures

    static func move(_ lectures: [Lecture], to folder: Folder?) {
        lectures.forEach { $0.folder = folder }
        folder?.isExpanded = true
    }

    /// Pins them all, or unpins them all when every one is already pinned.
    static func togglePin(_ lectures: [Lecture]) {
        let pin = !lectures.allSatisfy(\.isPinned)
        lectures.forEach { $0.isPinned = pin }
    }

    static func allInFolder(_ lectures: [Lecture], _ folder: Folder?) -> Bool {
        !lectures.isEmpty && lectures.allSatisfy { $0.folder == folder }
    }

    static func countLabel(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
