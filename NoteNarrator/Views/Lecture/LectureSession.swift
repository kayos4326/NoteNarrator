//  LectureSession.swift
//  NoteNarrator

import SwiftData
import SwiftUI

/// Handles study actions and source navigation for an open lecture.
@Observable
final class LectureSession {

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case notes = "Notes"
        case quiz = "Quiz"
        case flashcards = "Flashcards"
        case bookmarks = "Bookmarks"

        var id: Self { self }
    }

    enum Action: Hashable {
        case generateSummary, generateNotes
        case generateQuiz, regenerateQuiz, addQuizQuestions
        case generateFlashcards, regenerateFlashcards, addFlashcards
        case retryFailedSections
    }

    /// The ID lets repeated jumps to the same section work.
    struct NotesJump: Equatable {
        let sectionID: String
        let id = UUID()
    }

    let lecture: Lecture
    private let context: ModelContext

    var selectedTab: Tab = .summary
    private(set) var runningAction: Action?
    private(set) var isStopping = false
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    private(set) var notesJump: NotesJump?
    private(set) var highlightedSectionID: String?
    private(set) var infoMessage: String?
    var bookmarksPendingRemoval: [Bookmark] = []

    @ObservationIgnored private var parsedNotes: (source: String, sections: [NotesSection])?

    private static let addMoreCount = 5

    init(lecture: Lecture, context: ModelContext) {
        self.lecture = lecture
        self.context = context
    }

    var isBusy: Bool { runningAction != nil }

    // MARK: - Notes

    var notesSections: [NotesSection] {
        if let parsedNotes, parsedNotes.source == lecture.notes {
            return parsedNotes.sections
        }
        let sections = NotesSection.parse(lecture.notes)
        parsedNotes = (lecture.notes, sections)
        return sections
    }

    func sectionIndex(for reference: String) -> Int? {
        ReferenceMatcher.bestSectionIndex(for: reference, in: notesSections.map(\.reference))
    }

    func jumpToNotes(_ reference: String) {
        let sections = notesSections
        guard !sections.isEmpty else {
            showInfo("Notes haven't been generated for this lecture yet.")
            return
        }
        guard let index = sectionIndex(for: reference) else {
            showInfo("Couldn't find “\(ReferenceMatcher.displayName(for: reference))” in these notes. Regenerating the notes should fix this.")
            return
        }
        selectedTab = .notes
        notesJump = NotesJump(sectionID: sections[index].id)
    }

    /// Jump by section ID when several sections share a reference.
    func jump(toSection section: NotesSection) {
        selectedTab = .notes
        notesJump = NotesJump(sectionID: section.id)
    }

    func highlightSection(_ sectionID: String) {
        highlightedSectionID = sectionID
        Task {
            try? await Task.sleep(for: .seconds(2))
            if highlightedSectionID == sectionID {
                withAnimation { highlightedSectionID = nil }
            }
        }
    }

    private func showInfo(_ message: String) {
        withAnimation { infoMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if infoMessage == message {
                withAnimation { infoMessage = nil }
            }
        }
    }

    // MARK: - Quiz answers

    func answer(_ question: QuizQuestion, with option: Int) {
        guard !question.isAnswered, question.options.indices.contains(option) else { return }
        question.selectedOption = option
    }

    func resetAnswers() {
        lecture.quizQuestions.forEach { $0.selectedOption = nil }
    }

    // MARK: - Figures

    /// Keep each picture beside its source section when possible.
    var figuresBySection: [Int: [LectureFigure]] {
        let references = notesSections.map(\.reference)
        return Dictionary(grouping: lecture.orderedFigures) { figure in
            ReferenceMatcher.bestSectionIndex(for: figure.reference, in: references) ?? -1
        }
    }

    // MARK: - Bookmarks

    /// Bookmarks grouped by the notes section they resolve to.
    var bookmarksBySection: [Int: [Bookmark]] {
        let references = notesSections.map(\.reference)
        return Dictionary(grouping: lecture.bookmarks.sorted { $0.dateAdded < $1.dateAdded }) { bookmark in
            ReferenceMatcher.bestSectionIndex(for: bookmark.reference, in: references) ?? -1
        }
    }

    /// Match a bookmark to any question from the same source section.
    func bookmarks(matching reference: String) -> [Bookmark] {
        if let index = sectionIndex(for: reference) {
            return bookmarksBySection[index] ?? []
        }
        let target = ReferenceMatcher.normalize(reference)
        return lecture.bookmarks.filter { ReferenceMatcher.normalize($0.reference) == target }
    }

    func toggleBookmark(for reference: String) {
        let existing = bookmarks(matching: reference)
        if existing.isEmpty {
            // Anchor to the section's own heading so the bookmark always resolves back to it.
            addBookmark(reference: sectionIndex(for: reference).map { notesSections[$0].reference } ?? reference)
        } else if existing.contains(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            bookmarksPendingRemoval = existing
        } else {
            existing.forEach(deleteBookmark)
        }
    }

    func addBookmark(reference: String, note: String = "") {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return }
        let bookmark = Bookmark(reference: reference, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(bookmark)
        lecture.bookmarks.append(bookmark)
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        lecture.bookmarks.removeAll { $0 === bookmark }
        context.delete(bookmark)
    }

    func confirmPendingBookmarkRemoval() {
        bookmarksPendingRemoval.forEach(deleteBookmark)
        bookmarksPendingRemoval = []
    }

    // MARK: - Generation

    func perform(_ action: Action) {
        guard runningAction == nil, !lecture.isProcessing, !lecture.isGenerating else { return }
        if action == .retryFailedSections && lecture.failedChunkIndices.isEmpty { return }
        runningAction = action
        isStopping = false
        lecture.generationError = ""
        lecture.generationProgress = ""

        activeTask = Task {
            do {
                try await run(action)
            } catch is CancellationError {
                showInfo("Generation cancelled. Existing study material was kept.")
            } catch {
                lecture.generationError = error.localizedDescription
                AIReadinessMonitor.shared.refresh()
            }
            lecture.generationProgress = ""
            runningAction = nil
            isStopping = false
            activeTask = nil
        }
    }

    func cancelCurrentAction() {
        guard activeTask != nil, !isStopping else { return }
        isStopping = true
        lecture.generationProgress = "Stopping…"
        activeTask?.cancel()
    }

    private func run(_ action: Action) async throws {
        let lecture = self.lecture
        let transcript = lecture.transcript
        let progress: AIGenerator.ProgressHandler = {
            if !Task.isCancelled { lecture.generationProgress = $0 }
        }

        switch action {
        case .generateSummary:
            let summary = try await AIGenerator.generateSummary(from: transcript, onProgress: progress)
            try Task.checkCancellation()
            lecture.summary = summary

        case .generateNotes:
            let result = try await AIGenerator.generateNotes(from: transcript, onProgress: progress)
            try Task.checkCancellation()
            let merged = PartialGeneration.merge(existing: lecture.notesByChunk, new: result.notesByChunk)
            lecture.notesByChunk = merged
            lecture.failedChunkIndices = PartialGeneration.missingIndices(in: merged)
            lecture.notes = PartialGeneration.combinedNotes(merged)

        case .generateQuiz, .regenerateQuiz:
            // Generate first so a failure leaves the existing quiz in place.
            let questions = try await AIGenerator.generateQuiz(from: transcript, onProgress: progress)
            try Task.checkCancellation()
            removeAll(lecture.quizQuestions)
            lecture.quizQuestions = []
            lecture.appendQuiz(questions)

        case .addQuizQuestions:
            let existing = lecture.quizQuestions.map(\.question)
            let candidates = try await AIGenerator.generateQuiz(
                from: transcript, targetCount: Self.addMoreCount + 3, onProgress: progress)
            try Task.checkCancellation()
            lecture.appendQuiz(Array(AIGenerator.dedupeAgainstExisting(candidates, existingQuestions: existing)
                .prefix(Self.addMoreCount)))

        case .generateFlashcards, .regenerateFlashcards:
            let cards = try await AIGenerator.generateFlashcards(from: transcript, onProgress: progress)
            try Task.checkCancellation()
            removeAll(lecture.flashcards)
            lecture.flashcards = []
            lecture.appendFlashcards(cards)

        case .addFlashcards:
            let existingFronts = Set(lecture.flashcards.map { Self.cardKey($0.front) })
            let candidates = try await AIGenerator.generateFlashcards(
                from: transcript, targetCount: lecture.flashcards.count + Self.addMoreCount * 2, onProgress: progress)
            try Task.checkCancellation()
            lecture.appendFlashcards(Array(candidates
                .filter { !existingFronts.contains(Self.cardKey($0.front)) }
                .prefix(Self.addMoreCount)))

        case .retryFailedSections:
            let recovered = try await AIGenerator.retryFailed(
                from: transcript, indices: lecture.failedChunkIndices, onProgress: progress)
            try Task.checkCancellation()
            let count = try applyRecovered(recovered)
            showInfo(count == 0
                ? "AI could not recover those sections. Their source text is available in Notes."
                : "Recovered \(count) lecture \(count == 1 ? "section" : "sections").")
        }
    }

    /// Apply recovered material without discarding existing study work.
    @discardableResult
    func applyRecovered(_ recovered: GenerationResult) throws -> Int {
        let missingBefore = lecture.failedChunkIndices.count
        let merged = PartialGeneration.merge(existing: lecture.notesByChunk, retry: recovered)
        guard merged != lecture.notesByChunk else { throw GenerationError.noSectionsRecovered }

        let newQuestions = AIGenerator.dedupeAgainstExisting(
            recovered.quiz, existingQuestions: lecture.quizQuestions.map(\.question))
        let existingFronts = Set(lecture.flashcards.map { Self.cardKey($0.front) })
        let newCards = recovered.cards.filter { !existingFronts.contains(Self.cardKey($0.front)) }

        lecture.notesByChunk = merged
        lecture.failedChunkIndices = PartialGeneration.missingIndices(in: merged)
        lecture.notes = PartialGeneration.combinedNotes(merged)
        if !recovered.summary.isEmpty {
            lecture.summary = PartialGeneration.mergedSummary(existing: lecture.summary, recovered: recovered.summary)
        }
        lecture.appendQuiz(newQuestions)
        lecture.appendFlashcards(newCards)
        return missingBefore - lecture.failedChunkIndices.count
    }

    private func removeAll(_ models: [some PersistentModel]) {
        models.forEach(context.delete)
    }

    private static func cardKey(_ front: String) -> String {
        front.lowercased().trimmingCharacters(in: .whitespaces)
    }
}
