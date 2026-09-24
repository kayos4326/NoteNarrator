//  GenerationTypes.swift
//  NoteNarrator

import Foundation
import FoundationModels

// MARK: - Structured output the on-device model fills in

@Generable
struct GeneratedDefinition {
    @Guide(description: "The term or concept being defined")
    var term: String
    @Guide(description: "A concise definition of the term")
    var definition: String
}

@Generable
struct StructuredKnowledge {
    @Guide(description: "Every key concept or term covered in this section — do not narrow this down to just the 2-3 most obvious ones. Just the term/concept name, not an explanation of it")
    var keyConcepts: [String]
    @Guide(description: "Definitions of every important term introduced in this section")
    var definitions: [GeneratedDefinition]
    @Guide(description: "Facts or rules from this section that are NOT already covered by a definition above — do not restate a definition here, only genuinely new information (a process, a rule, a consequence, a comparison)")
    var importantFacts: [String]
    @Guide(description: "Concrete worked examples, scenarios, or illustrations given in this section — not a restatement of a concept or fact, an actual example of it in use")
    var examples: [String]
    @Guide(description: "Topics from this section that would make good quiz questions, phrased as questions or prompts, not restated facts")
    var possibleQuizPoints: [String]
}

@Generable
struct GeneratedQuiz {
    @Guide(description: "A list of multiple choice questions")
    var questions: [GeneratedQuestion]
}

@Generable
struct GeneratedQuestion {
    @Guide(description: "The question text")
    var question: String
    @Guide(description: "Exactly 4 answer options")
    var options: [String]
    @Guide(description: "The index (0-3) of the correct option")
    var correctIndex: Int
}

@Generable
struct GeneratedFlashcards {
    @Guide(description: "A list of flashcards")
    var cards: [GeneratedCard]
}

@Generable
struct GeneratedCard {
    @Guide(description: "The front of the card: a question or term")
    var front: String
    @Guide(description: "The back of the card: the answer or definition")
    var back: String
}

// MARK: - Results handed back to the app

struct QuizData: Sendable {
    let question: String
    let options: [String]
    let correctIndex: Int
    let sourceReference: String

    static let optionCount = 4

    /// Drop questions that cannot be answered or scored.
    var isValid: Bool {
        options.count == Self.optionCount
            && options.indices.contains(correctIndex)
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct CardData: Sendable {
    let front: String
    let back: String
}

struct GenerationResult: Sendable {
    /// Empty when only the summary step failed; the Summary tab then offers to retry.
    let summary: String
    let notes: String
    let quiz: [QuizData]
    let cards: [CardData]
    /// One slot per source chunk; failed slots hold labeled source text.
    let notesByChunk: [String]
    let failedChunkIndices: [Int]

    var missingOutputLabels: [String] {
        var labels: [String] = []
        if summary.isEmpty { labels.append("summary") }
        if quiz.isEmpty { labels.append("quiz") }
        if cards.isEmpty { labels.append("flashcards") }
        return labels
    }
}

struct NotesGenerationResult: Sendable {
    let notesByChunk: [String]
    let failedChunkIndices: [Int]

    var notes: String { PartialGeneration.combinedNotes(notesByChunk) }
}

enum PartialGeneration {
    static let sourceFallbackMarker = "SOURCE TEXT — AI notes unavailable:"

    static func isSourceFallback(_ notes: String) -> Bool {
        notes.contains(sourceFallbackMarker)
    }

    static func merge(existing: [String], retry: GenerationResult) -> [String] {
        guard existing.count == retry.notesByChunk.count else { return existing }
        return merge(existing: existing, new: retry.notesByChunk)
    }

    /// Keep existing AI notes if regeneration returns only source text.
    static func merge(existing: [String], new: [String]) -> [String] {
        guard existing.count == new.count else { return new }
        var merged = existing
        for index in new.indices where !new[index].isEmpty {
            if isSourceFallback(new[index]) && !existing[index].isEmpty && !isSourceFallback(existing[index]) {
                continue
            }
            merged[index] = new[index]
        }
        return merged
    }

    static func combinedNotes(_ chunks: [String]) -> String {
        chunks.filter { !$0.isEmpty }.joined(separator: AIGenerator.notesSectionSeparator)
    }

    static func missingIndices(in chunks: [String]) -> [Int] {
        chunks.indices.filter { chunks[$0].isEmpty || isSourceFallback(chunks[$0]) }
    }

    /// A retry's summary covers only the recovered sections, so its points join the existing
    /// key-point list; the existing overview stays, since it describes the whole lecture.
    static func mergedSummary(existing: String, recovered: String) -> String {
        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return recovered }
        let content = SummaryContent.parse(recovered)
        let known = Set(SummaryContent.parse(existing).keyPoints.map { $0.lowercased() })
        let points = (content.keyPoints.isEmpty ? content.overview : content.keyPoints)
            .filter { !known.contains($0.lowercased()) }
        guard !points.isEmpty else { return existing }
        return existing + "\n" + points.map { "- " + $0 }.joined(separator: "\n")
    }
}

/// A complete model failure or a retry that did not recover any missing sections.
enum GenerationError: LocalizedError {
    case modelUnavailable
    case noKnowledgeProduced
    case summaryFailed
    case quizFailed
    case flashcardsFailed
    case noSectionsRecovered

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "The on-device AI is not ready. Check the AI readiness indicator, then try again."
        case .noKnowledgeProduced:
            "The on-device AI couldn't read this lecture. Try again; if it repeats, try a shorter file."
        case .summaryFailed:
            "The on-device AI couldn't write a summary. Your existing summary was kept; try again."
        case .quizFailed:
            "The on-device AI couldn't write quiz questions. Your existing quiz was kept; try again."
        case .flashcardsFailed:
            "The on-device AI couldn't write flashcards. Your existing cards were kept; try again."
        case .noSectionsRecovered:
            "No missing sections could be recovered. Your existing study material is unchanged; try again later."
        }
    }
}
