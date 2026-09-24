//  Lecture.swift
//  NoteNarrator

import Foundation
import SwiftData

@Model
class Lecture {
    var title: String
    var dateAdded: Date
    var sourceType: String     // "document" or "media"
    var fileExtension: String  // "pdf", "docx", "pptx", "mp3", "mp4", etc.
    var transcript: String     // extracted or transcribed text

    var summary: String
    var notes: String
    var isPinned: Bool
    var isProcessing: Bool     // extracting text or transcribing
    var isGenerating: Bool     // generating study materials right after import
    var generationError: String = ""
    var generationProgress: String = ""  // e.g. "Extracting Slide 3 of 6…"
    /// Persisted so a partial result is still visible and retryable after relaunch.
    var notesByChunk: [String] = []
    var failedChunkIndices: [Int] = []
    /// What the import had to skip, e.g. pictures left unread to keep it quick.
    var extractionNotice: String = ""
    var folder: Folder?        // nil means unfiled

    @Relationship(deleteRule: .cascade) var flashcards: [Flashcard] = []
    @Relationship(deleteRule: .cascade) var quizQuestions: [QuizQuestion] = []
    @Relationship(deleteRule: .cascade) var bookmarks: [Bookmark] = []
    @Relationship(deleteRule: .cascade) var figures: [LectureFigure] = []

    init(title: String, sourceType: String, fileExtension: String) {
        self.title = title
        self.dateAdded = Date()
        self.sourceType = sourceType
        self.fileExtension = fileExtension
        self.transcript = ""
        self.summary = ""
        self.notes = ""
        self.isPinned = false
        self.isProcessing = false
        self.isGenerating = false
    }

    var isMedia: Bool { sourceType == "media" }

    var orderedQuizQuestions: [QuizQuestion] {
        quizQuestions.sorted { $0.createdAt < $1.createdAt }
    }

    var answeredQuestionCount: Int {
        quizQuestions.filter(\.isAnswered).count
    }

    var correctAnswerCount: Int {
        quizQuestions.filter(\.isAnsweredCorrectly).count
    }

    var orderedFlashcards: [Flashcard] {
        flashcards.sorted { $0.createdAt < $1.createdAt }
    }

    var orderedFigures: [LectureFigure] {
        figures.sorted { $0.order < $1.order }
    }

    /// At most this many pictures are kept per lecture, so a long deck doesn't fill the disk.
    static let maxFigures = 60

    func replaceFigures(with extracted: [ExtractedFigure]) {
        figures.forEach { modelContext?.delete($0) }
        figures = extracted.prefix(Lecture.maxFigures).enumerated().map { order, figure in
            LectureFigure(reference: figure.reference, imageData: figure.imageData,
                          hasReadableText: figure.hasReadableText, order: order)
        }
    }

    func appendQuiz(_ questions: [QuizData]) {
        let start = Date()
        quizQuestions.append(contentsOf: questions.enumerated().map { offset, data in
            QuizQuestion(question: data.question, options: data.options, correctIndex: data.correctIndex,
                         sourceReference: data.sourceReference, createdAt: start.addingTimeInterval(Double(offset) / 1000))
        })
    }

    func appendFlashcards(_ cards: [CardData]) {
        let start = Date()
        flashcards.append(contentsOf: cards.enumerated().map { offset, card in
            Flashcard(front: card.front, back: card.back, createdAt: start.addingTimeInterval(Double(offset) / 1000))
        })
    }
}
