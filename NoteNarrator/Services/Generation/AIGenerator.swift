//  AIGenerator.swift
//  NoteNarrator

import Foundation
import FoundationModels
import OSLog

/// Generates source-linked notes, summaries, quizzes, and flashcards on the Mac.
enum AIGenerator {

    enum Readiness: Equatable {
        case ready, downloading, disabled, unsupported

        var title: String {
            switch self {
            case .ready: "On-device AI ready"
            case .downloading: "On-device AI is preparing"
            case .disabled: "Apple Intelligence is off"
            case .unsupported: "On-device AI unavailable"
            }
        }

        var detail: String {
            switch self {
            case .ready: "Study materials can be generated offline."
            case .downloading: "Keep this Mac connected until Apple's model is ready, then check again."
            case .disabled: "Turn on Apple Intelligence in System Settings, then check again."
            case .unsupported: "This Mac does not support Apple's on-device model."
            }
        }
    }

    static var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available: .ready
        case .unavailable(.modelNotReady): .downloading
        case .unavailable(.appleIntelligenceNotEnabled): .disabled
        case .unavailable(.deviceNotEligible): .unsupported
        @unknown default: .unsupported
        }
    }

    /// Progress shown beside the Cancel button.
    typealias ProgressHandler = (String) -> Void

    private static let logger = Logger(subsystem: "com.notenarrator.NoteNarrator", category: "AIGenerator")

    static func prewarm() {
        if readiness == .ready { LanguageModelSession().prewarm() }
    }

    // MARK: - Public entry points

    static func generateAll(from text: String, onProgress: ProgressHandler = { _ in }) async throws -> GenerationResult {
        let batch = try await chunkKnowledge(from: text, onProgress: onProgress)
        return try await buildResult(from: batch, text: text, onProgress: onProgress)
    }

    /// Attempts only the source chunks that failed during the initial generation.
    static func retryFailed(from text: String, indices: [Int], onProgress: ProgressHandler = { _ in }) async throws -> GenerationResult {
        let batch = try await chunkKnowledge(from: text, indices: Set(indices), onProgress: onProgress)
        let share = Double(batch.pairs.count) / Double(max(batch.notesByChunk.count, 1))
        return try await buildResult(from: batch, text: text, share: share, onProgress: onProgress)
    }

    /// A retry asks for only its share of the quiz and flashcards.
    static func scaledTarget(_ full: Int, share: Double) -> Int {
        max(1, Int((Double(full) * min(max(share, 0), 1)).rounded(.up)))
    }

    private static func buildResult(from batch: ChunkBatch, text: String, share: Double = 1,
                                    onProgress: ProgressHandler) async throws -> GenerationResult {
        let summary = batch.pairs.isEmpty ? "" : await buildSummary(from: batch.pairs, onProgress: onProgress) ?? ""
        try Task.checkCancellation()
        let quiz = batch.pairs.isEmpty ? [] : await buildQuiz(
            from: batch.pairs, targetTotal: scaledTarget(quizCount(for: text), share: share), onProgress: onProgress)
        try Task.checkCancellation()
        let cards = batch.pairs.isEmpty ? [] : await buildFlashcards(
            from: batch.pairs, target: scaledTarget(flashcardCount(for: text), share: share), onProgress: onProgress)
        try Task.checkCancellation()
        return GenerationResult(summary: summary, notes: PartialGeneration.combinedNotes(batch.notesByChunk), quiz: quiz, cards: cards,
                                notesByChunk: batch.notesByChunk, failedChunkIndices: batch.failedIndices)
    }

    static func generateSummary(from text: String, onProgress: ProgressHandler = { _ in }) async throws -> String {
        let batch = try await chunkKnowledge(from: text, onProgress: onProgress)
        let summary = await buildSummary(from: batch.pairs, onProgress: onProgress)
        try Task.checkCancellation()
        guard let summary else {
            throw GenerationError.summaryFailed
        }
        return summary
    }

    static func generateNotes(from text: String, onProgress: ProgressHandler = { _ in }) async throws -> NotesGenerationResult {
        let batch = try await chunkKnowledge(from: text, onProgress: onProgress)
        try Task.checkCancellation()
        return NotesGenerationResult(notesByChunk: batch.notesByChunk, failedChunkIndices: batch.failedIndices)
    }

    static func generateQuiz(from text: String, targetCount: Int? = nil, onProgress: ProgressHandler = { _ in }) async throws -> [QuizData] {
        let batch = try await chunkKnowledge(from: text, onProgress: onProgress)
        let quiz = await buildQuiz(from: batch.pairs, targetTotal: targetCount ?? quizCount(for: text), onProgress: onProgress)
        try Task.checkCancellation()
        guard !quiz.isEmpty else { throw GenerationError.quizFailed }
        return quiz
    }

    static func generateFlashcards(from text: String, targetCount: Int? = nil, onProgress: ProgressHandler = { _ in }) async throws -> [CardData] {
        let batch = try await chunkKnowledge(from: text, onProgress: onProgress)
        let cards = await buildFlashcards(from: batch.pairs, target: targetCount ?? flashcardCount(for: text), onProgress: onProgress)
        try Task.checkCancellation()
        guard !cards.isEmpty else { throw GenerationError.flashcardsFailed }
        return cards
    }

    // MARK: - Output sizing

    static func quizCount(for text: String) -> Int {
        switch text.count {
        case ..<5000:  return 10
        case ..<15000: return 15
        case ..<30000: return 20
        default:       return 30
        }
    }

    static func flashcardCount(for text: String) -> Int {
        switch text.count {
        case ..<5000:  return 15
        case ..<15000: return 20
        case ..<30000: return 30
        default:       return 40
        }
    }

    // MARK: - Structured knowledge (shared intermediate step)

    private struct ChunkKnowledge {
        let chunk: SourceChunk
        let knowledge: StructuredKnowledge
    }

    private struct ChunkBatch {
        let pairs: [ChunkKnowledge]
        let notesByChunk: [String]
        let failedIndices: [Int]
    }

    /// Keep one slot per source chunk so recovered notes return to the right place.
    private static func chunkKnowledge(from text: String, indices: Set<Int>? = nil,
                                       onProgress: ProgressHandler) async throws -> ChunkBatch {
        guard readiness == .ready else { throw GenerationError.modelUnavailable }
        let chunks = TextChunker.splitIntoChunks(text)
        var results: [ChunkKnowledge] = []
        var notesByChunk = Array(repeating: "", count: chunks.count)
        var failedIndices: [Int] = []
        let targets = chunks.indices.filter { indices?.contains($0) ?? true }
        for (position, index) in targets.enumerated() {
            let chunk = chunks[index]
            try Task.checkCancellation()
            onProgress(progressMessage(for: chunk.reference, position: position, of: targets.count,
                                       isRetry: indices != nil))
            let pieces = TextChunker.retryPieces(of: chunk)
            var recovered: [ChunkKnowledge] = []
            // Retry smaller pieces when the full section failed.
            if indices == nil || pieces.count == 1 {
                if let knowledge = await extractKnowledge(from: chunk) {
                    recovered = [ChunkKnowledge(chunk: chunk, knowledge: knowledge)]
                }
            }
            if recovered.isEmpty && pieces.count > 1 {
                onProgress("Reading smaller parts of \(chunk.reference)…")
                for piece in pieces {
                    try Task.checkCancellation()
                    guard let knowledge = await extractKnowledge(from: piece) else { break }
                    recovered.append(ChunkKnowledge(chunk: piece, knowledge: knowledge))
                }
                // Do not mark a section complete if only one half worked.
                if recovered.count != pieces.count { recovered = [] }
            }
            try Task.checkCancellation()
            if recovered.isEmpty {
                failedIndices.append(index)
                notesByChunk[index] = sourceFallbackNotes(for: chunk)
            } else {
                for pair in recovered { checkCoverage(chunk: pair.chunk, knowledge: pair.knowledge) }
                results.append(contentsOf: recovered)
                notesByChunk[index] = recovered.map {
                    formatKnowledgeAsNotes($0.knowledge, reference: $0.chunk.reference)
                }.joined(separator: notesSectionSeparator)
            }
        }
        return ChunkBatch(pairs: results, notesByChunk: notesByChunk, failedIndices: failedIndices)
    }

    /// Retry model refusals with a fresh session; do not retry unrelated errors.
    static func withGuardrailRetries<T>(label: String, maxAttempts: Int = 3,
                                        _ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error where isGuardrailRefusal(error) && attempt < maxAttempts {
                try Task.checkCancellation()
                logger.notice("\(label, privacy: .public) refused by the model's guardrails; retrying (\(attempt + 1) of \(maxAttempts))")
                attempt += 1
            }
        }
    }

    nonisolated static func isGuardrailRefusal(_ error: Error) -> Bool {
        if let error = error as? LanguageModelSession.GenerationError, case .guardrailViolation = error {
            return true
        }
        if #available(macOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return true
            default: return false
            }
        }
        return false
    }

    /// Count progress within the current attempt, not the whole lecture.
    static func progressMessage(for reference: String, position: Int, of count: Int, isRetry: Bool) -> String {
        "\(isRetry ? "Retrying" : "Extracting") \(reference) (\(position + 1) of \(count))…"
    }

    private static func extractKnowledge(from chunk: SourceChunk) async -> StructuredKnowledge? {
        let instructions = """
        Extract study knowledge from the provided lecture section. Include distinct concepts, \
        definitions, facts, examples, and quiz topics. Avoid repetition and stay faithful to \
        the source; do not invent facts.
        """
        let prompt = """
        Extract structured knowledge from this section (\(chunk.reference)):

        \(chunk.text)
        """
        do {
            return try await withGuardrailRetries(label: chunk.reference) {
                try await LanguageModelSession(instructions: instructions)
                    .respond(to: prompt, generating: StructuredKnowledge.self).content
            }
        } catch {
            logger.error("Knowledge extraction failed for \(chunk.reference, privacy: .public): \(String(reflecting: error), privacy: .public)")
            return nil
        }
    }

    /// Log likely under-covered sections for debugging.
    private static func checkCoverage(chunk: SourceChunk, knowledge: StructuredKnowledge) {
        func contentWords(_ text: String) -> Set<String> {
            Set(normalizedWords(text).filter { $0.count > 4 })
        }
        let sourceWords = contentWords(chunk.text)
        guard sourceWords.count > 10 else { return }

        let knowledgeText = (knowledge.keyConcepts + knowledge.importantFacts + knowledge.examples
            + knowledge.definitions.map { "\($0.term) \($0.definition)" }).joined(separator: " ")
        let ratio = Double(sourceWords.intersection(contentWords(knowledgeText)).count) / Double(sourceWords.count)
        if ratio < 0.15 {
            logger.notice("\(chunk.reference, privacy: .public) may be under-covered (overlap \(ratio, format: .fixed(precision: 2)))")
        }
    }

    // MARK: - Notes

    /// Separates one chunk's notes section from the next.
    nonisolated static let notesSectionSeparator = "\n\n---\n\n"

    /// Show source text if AI fails, but keep the section marked incomplete.
    static func sourceFallbackNotes(for chunk: SourceChunk) -> String {
        let lines = chunk.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ([chunk.reference, "", PartialGeneration.sourceFallbackMarker] + lines.map { "- " + $0 })
            .joined(separator: "\n")
    }

    static func formatKnowledgeAsNotes(_ knowledge: StructuredKnowledge, reference: String) -> String {
        let groups: [(title: String, items: [String])] = [
            ("Key Concepts", knowledge.keyConcepts),
            ("Definitions", knowledge.definitions.map { "\($0.term): \($0.definition)" }),
            ("Important Facts", knowledge.importantFacts),
            ("Examples", knowledge.examples),
            ("Possible Quiz Points", knowledge.possibleQuizPoints),
        ]
        let body = groups
            .filter { !$0.items.isEmpty }
            .map { group in (["\(group.title):"] + group.items.map { "- \($0)" }).joined(separator: "\n") }
        return ([reference] + body).joined(separator: "\n\n")
    }

    private static func buildNotes(from pairs: [ChunkKnowledge]) -> String {
        pairs
            .map { formatKnowledgeAsNotes($0.knowledge, reference: $0.chunk.reference) }
            .joined(separator: notesSectionSeparator)
    }

    // MARK: - Summary

    private static func buildSummary(from pairs: [ChunkKnowledge], onProgress: ProgressHandler) async -> String? {
        onProgress("Writing summary…")
        let keyPoints = pairs.map { pair in
            "\(pair.chunk.reference): " + (pair.knowledge.keyConcepts + pair.knowledge.importantFacts).joined(separator: "; ")
        }.joined(separator: "\n")

        let instructions = """
        You are a helpful study assistant. Summarize lecture content clearly and concisely. \
        Focus on the key points a student needs to know. Use simple language.
        """
        let prompt = """
        Summarize the following key points from a lecture into a short paragraph followed by 3-5 key bullet points:

        \(keyPoints)
        """
        do {
            return try await LanguageModelSession(instructions: instructions).respond(to: prompt).content
        } catch {
            logger.error("Summary generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Quiz

    static func normalizedWords(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// Above this word-overlap similarity, two questions count as the same question.
    private static let duplicateThreshold = 0.6

    /// Removes exact and near-duplicate questions (by word overlap), keeping the first.
    static func dedupeQuestions(_ questions: [QuizData]) -> [QuizData] {
        var acceptedWords: [Set<String>] = []
        return questions.filter { question in
            let words = normalizedWords(question.question)
            guard !acceptedWords.contains(where: { jaccardSimilarity($0, words) > duplicateThreshold }) else {
                return false
            }
            acceptedWords.append(words)
            return true
        }
    }

    /// Filters out questions that duplicate already-saved ones, for topping up a quiz.
    static func dedupeAgainstExisting(_ candidates: [QuizData], existingQuestions: [String]) -> [QuizData] {
        let existingWords = existingQuestions.map { normalizedWords($0) }
        return candidates.filter { candidate in
            let words = normalizedWords(candidate.question)
            return !existingWords.contains { jaccardSimilarity($0, words) > duplicateThreshold }
        }
    }

    private static func generateQuizForChunk(_ pair: ChunkKnowledge, count: Int) async -> [QuizData] {
        let instructions = """
        You are a helpful study assistant. Create multiple choice quiz questions to test \
        a student's understanding. Each question must have exactly 4 options with one correct answer.
        """
        let prompt = """
        Create \(count) multiple choice questions based on this knowledge. Prioritize the \
        "Possible Quiz Points" listed below where present, then draw on the rest of the \
        knowledge to round out the questions:

        \(formatKnowledgeAsNotes(pair.knowledge, reference: pair.chunk.reference))
        """
        do {
            let response = try await LanguageModelSession(instructions: instructions)
                .respond(to: prompt, generating: GeneratedQuiz.self)
            return response.content.questions
                .map { QuizData(question: $0.question, options: $0.options, correctIndex: $0.correctIndex,
                                sourceReference: pair.chunk.reference) }
                .filter(\.isValid)
        } catch {
            logger.error("Quiz generation failed for \(pair.chunk.reference, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func buildQuiz(from pairs: [ChunkKnowledge], targetTotal: Int, onProgress: ProgressHandler) async -> [QuizData] {
        let perChunk = max(3, min(6, targetTotal / pairs.count))
        var raw: [QuizData] = []
        for (index, pair) in pairs.enumerated() {
            if Task.isCancelled { break }
            onProgress("Writing quiz questions for \(pair.chunk.reference) (\(index + 1) of \(pairs.count))…")
            raw += await generateQuizForChunk(pair, count: perChunk)
        }
        return Array(dedupeQuestions(raw).prefix(targetTotal))
    }

    // MARK: - Flashcards

    /// Builds flashcards straight from extracted definitions, then tops up with one more
    /// model call only if that falls short of the target.
    private static func buildFlashcards(from pairs: [ChunkKnowledge], target: Int, onProgress: ProgressHandler) async -> [CardData] {
        onProgress("Compiling flashcards…")
        var seenFronts = Set<String>()
        var cards: [CardData] = []

        for definition in pairs.flatMap(\.knowledge.definitions) {
            let key = definition.term.lowercased().trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, seenFronts.insert(key).inserted else { continue }
            cards.append(CardData(front: definition.term, back: definition.definition))
        }

        let facts = pairs.flatMap { $0.knowledge.keyConcepts + $0.knowledge.importantFacts }
        guard cards.count < target, !facts.isEmpty else { return cards }

        onProgress("Generating extra flashcards…")
        let instructions = """
        You are a helpful study assistant. Create flashcards to help a student memorize \
        key concepts. Each card has a question or term on the front and the answer on the back.
        """
        let prompt = """
        Create \(target - cards.count) flashcards based on these points (avoid repeating: \(seenFronts.joined(separator: ", "))):

        \(facts.map { "- \($0)" }.joined(separator: "\n"))
        """
        do {
            let response = try await LanguageModelSession(instructions: instructions)
                .respond(to: prompt, generating: GeneratedFlashcards.self)
            cards += response.content.cards.map { CardData(front: $0.front, back: $0.back) }
        } catch {
            logger.error("Extra flashcard generation failed: \(error.localizedDescription, privacy: .public)")
        }
        return cards
    }
}
