//  ContentView.swift
//  NoteNarrator

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var lectures: [Lecture]

    @State private var selection: Set<Lecture> = []
    @State private var libraryActions = LibraryActions()
    @State private var isImporting = false
    @State private var importTargetFolder: Folder?
    @State private var importError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, actions: libraryActions, onImport: startImport)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 420)
        } detail: {
            if selection.count > 1 {
                MultipleSelectionView(
                    lectures: selection.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                    actions: libraryActions
                )
            } else if let lecture = selection.first {
                LectureDetailView(lecture: lecture, context: modelContext)
                    .id(lecture.persistentModelID)
            } else {
                WelcomeView { startImport(into: nil) }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: LectureImporter.supportedTypes,
                      allowsMultipleSelection: true) { result in
            finishImport(result)
        }
        .alert("Couldn't import the file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onAppear { AIGenerator.prewarm() }
    }

    private func startImport(into folder: Folder?) {
        importTargetFolder = folder
        isImporting = true
    }

    private func finishImport(_ result: Result<[URL], Error>) {
        defer { importTargetFolder = nil }
        switch result {
        case .success(let urls):
            let imported = LectureImporter.importLectures(
                from: urls, into: importTargetFolder, context: modelContext, existingTitles: lectures.map(\.title))
            if let first = imported.first {
                selection = [first]
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
