//  SidebarView.swift
//  NoteNarrator

import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    /// ⌘-click and ⇧-click select several lectures; right-click and Delete act on all of them.
    @Binding var selection: Set<Lecture>
    let actions: LibraryActions
    let onImport: (Folder?) -> Void

    @Query(sort: \Lecture.dateAdded, order: .reverse) private var lectures: [Lecture]
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var searchText = ""
    @State private var dragSelection = SidebarDragSelection()

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        @Bindable var actions = actions
        List(selection: $selection) {
            if query.isEmpty {
                browseContent
            } else {
                searchContent
            }
        }
        .onDeleteCommand {
            if !selection.isEmpty { actions.requestDelete(sortedSelection) }
        }
        .onAppear {
            let selection = $selection
            dragSelection.currentSelection = { selection.wrappedValue }
            dragSelection.onSelect = { selection.wrappedValue = $0 }
            dragSelection.start()
        }
        .onDisappear { dragSelection.stop() }
        .safeAreaInset(edge: .bottom) { PrivacyBadge() }
        .navigationTitle("NoteNarrator")
        .searchable(text: $searchText, prompt: "Search lectures or folders")
        // A single toolbar item: the sidebar is narrow, and extra items get pushed into the
        // window's overflow (») menu, where they look like they disappeared.
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Import Lectures…", systemImage: "square.and.arrow.down") { onImport(nil) }
                    Button("New Folder…", systemImage: "folder.badge.plus") { actions.startNewFolder() }
                } label: {
                    Label("Add", systemImage: "plus")
                } primaryAction: {
                    onImport(nil)
                }
                .help("Import lectures (hold for more options)")
            }
        }
        .alert("New Folder", isPresented: $actions.isCreatingFolder) {
            TextField("Subject name, e.g. Database Systems", text: $actions.newFolderName)
            Button("Cancel", role: .cancel) { actions.finishNewFolder() }
            Button("Create") { createFolder() }
        } message: {
            newFolderMessage
        }
        .alert(renameTitle, isPresented: Binding(
            get: { actions.renameTarget != nil },
            set: { if !$0 { actions.renameTarget = nil } }
        )) {
            TextField("Name", text: $actions.renameText)
            Button("Cancel", role: .cancel) { actions.renameTarget = nil }
            Button("Rename") { confirmRename() }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { !actions.lecturesPendingDeletion.isEmpty },
                set: { if !$0 { actions.lecturesPendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(actions.lecturesPendingDeletion.count == 1 ? "Delete Lecture" : "Delete Lectures",
                   role: .destructive) { deletePendingLectures() }
        } message: {
            Text(actions.lecturesPendingDeletion.count == 1
                 ? "Its summary, notes, quiz, flashcards, and bookmarks will be deleted too."
                 : "Their summaries, notes, quizzes, flashcards, and bookmarks will be deleted too.")
        }
        .confirmationDialog(
            "Delete “\(actions.folderPendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { actions.folderPendingDeletion != nil },
                set: { if !$0 { actions.folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) { deletePendingFolder() }
        } message: {
            Text("The lectures inside won't be deleted — they'll move to Unfiled.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var browseContent: some View {
        if lectures.isEmpty && folders.isEmpty {
            Text("No lectures yet. Click + above to import.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !folders.isEmpty {
            Section {
                ForEach(folders) { folder in
                    FolderRow(
                        folder: folder,
                        lectures: pinnedFirst(folder.lectures),
                        lectureRow: { lectureRow($0, showsFolder: false) },
                        onImport: { onImport(folder) },
                        onRename: { actions.startRename(.folder(folder), name: folder.name) },
                        onDelete: { actions.folderPendingDeletion = folder }
                    )
                }
            } header: {
                SidebarSectionHeader(title: "Folders", detail: LibraryActions.countLabel(folders.count, "folder"))
            }
        }

        let unfiled = pinnedFirst(lectures.filter { $0.folder == nil })
        if !unfiled.isEmpty {
            Section {
                ForEach(unfiled) { lectureRow($0, showsFolder: false) }
            } header: {
                SidebarSectionHeader(title: folders.isEmpty ? "Lectures" : "Unfiled",
                                     detail: LibraryActions.countLabel(unfiled.count, "lecture"))
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let results = pinnedFirst(lectures.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.folder?.name.localizedCaseInsensitiveContains(query) ?? false)
        })
        if results.isEmpty {
            Text("No lectures match “\(query)”")
                .foregroundStyle(.secondary)
        } else {
            Section {
                ForEach(results) { lectureRow($0, showsFolder: true) }
            } header: {
                SidebarSectionHeader(title: "Results", detail: LibraryActions.countLabel(results.count, "lecture"))
            }
        }
    }

    private func lectureRow(_ lecture: Lecture, showsFolder: Bool) -> some View {
        LectureRow(lecture: lecture, showsFolder: showsFolder)
            .tag(lecture)
            .contextMenu { lectureMenu(for: targets(forRightClickOn: lecture)) }
    }

    /// Like Finder: right-clicking a selected lecture acts on the whole selection,
    /// right-clicking any other lecture acts on just that one.
    private func targets(forRightClickOn lecture: Lecture) -> [Lecture] {
        selection.contains(lecture) ? sortedSelection : [lecture]
    }

    @ViewBuilder
    private func lectureMenu(for targets: [Lecture]) -> some View {
        let isSingle = targets.count == 1
        if isSingle, let lecture = targets.first {
            Button("Rename…", systemImage: "pencil") {
                actions.startRename(.lecture(lecture), name: lecture.title)
            }
        }
        let allPinned = targets.allSatisfy(\.isPinned)
        Button(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin") {
            LibraryActions.togglePin(targets)
        }
        MoveToFolderMenu(lectures: targets, folders: folders, actions: actions)
        Divider()
        Button(isSingle ? "Delete…" : "Delete \(targets.count) Lectures…", systemImage: "trash", role: .destructive) {
            actions.requestDelete(targets)
        }
    }

    // MARK: - Dialogs

    private var sortedSelection: [Lecture] {
        selection.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Pinned lectures first, each group newest first.
    private func pinnedFirst(_ items: [Lecture]) -> [Lecture] {
        let byDate = items.sorted { $0.dateAdded > $1.dateAdded }
        return byDate.filter(\.isPinned) + byDate.filter { !$0.isPinned }
    }

    private var newFolderMessage: Text {
        let moving = actions.lecturesForNewFolder
        if moving.count == 1, let lecture = moving.first {
            return Text("“\(lecture.title)” will be moved into it.")
        } else if moving.count > 1 {
            return Text("The \(moving.count) selected lectures will be moved into it.")
        }
        return Text("Group lectures from the same subject.")
    }

    private func createFolder() {
        defer { actions.finishNewFolder() }
        let name = actions.newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let folder = Folder(name: LectureImporter.uniqueName(name, existing: folders.map(\.name)))
        modelContext.insert(folder)
        LibraryActions.move(actions.lecturesForNewFolder, to: folder)
        folder.isExpanded = true
        try? modelContext.save()  // permanent ID before the sidebar lists it
    }

    private var renameTitle: String {
        if case .folder = actions.renameTarget { return "Rename Folder" }
        return "Rename Lecture"
    }

    private func confirmRename() {
        defer { actions.renameTarget = nil }
        let name = actions.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch actions.renameTarget {
        case .lecture(let lecture): lecture.title = name
        case .folder(let folder): folder.name = name
        case nil: break
        }
    }

    private var deletionTitle: String {
        let pending = actions.lecturesPendingDeletion
        if pending.count == 1, let lecture = pending.first {
            return "Delete “\(lecture.title)”?"
        }
        return "Delete \(pending.count) lectures?"
    }

    private func deletePendingLectures() {
        let pending = actions.lecturesPendingDeletion
        // Deselect first so the detail view never shows a deleted lecture.
        selection.subtract(pending)
        pending.forEach { modelContext.delete($0) }
        actions.lecturesPendingDeletion = []
    }

    private func deletePendingFolder() {
        guard let folder = actions.folderPendingDeletion else { return }
        folder.lectures.forEach { $0.folder = nil }
        modelContext.delete(folder)
        actions.folderPendingDeletion = nil
    }
}

/// "Move to Folder" for one or more lectures; a folder is checked when they're all in it.
struct MoveToFolderMenu: View {
    let lectures: [Lecture]
    let folders: [Folder]
    let actions: LibraryActions

    var body: some View {
        Menu("Move to Folder", systemImage: "folder") {
            Toggle("No Folder", isOn: Binding(
                get: { LibraryActions.allInFolder(lectures, nil) },
                set: { if $0 { LibraryActions.move(lectures, to: nil) } }
            ))
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Toggle(folder.name, isOn: Binding(
                    get: { LibraryActions.allInFolder(lectures, folder) },
                    set: { if $0 { LibraryActions.move(lectures, to: folder) } }
                ))
            }
            Divider()
            Button("New Folder…") { actions.startNewFolder(moving: lectures) }
        }
    }
}

#Preview {
    SidebarView(selection: .constant([]), actions: LibraryActions(), onImport: { _ in })
        .modelContainer(for: [Lecture.self, Folder.self], inMemory: true)
}
