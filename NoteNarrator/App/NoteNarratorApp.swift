//  NoteNarratorApp.swift
//  NoteNarrator

import SwiftData
import SwiftUI

@main
struct NoteNarratorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer = {
        let schema = Schema([Lecture.self, Flashcard.self, QuizQuestion.self, Bookmark.self, Folder.self,
                             LectureFigure.self])
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
            LectureImporter.recoverInterruptedLectures(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Match the app icon's green even when the Mac's accent color is set to something else.
                .tint(Color("AccentColor"))
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { AIReadinessMonitor.shared.refresh() }
                }
        }
        .modelContainer(modelContainer)
    }
}
