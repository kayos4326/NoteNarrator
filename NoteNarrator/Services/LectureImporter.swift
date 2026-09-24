//  LectureImporter.swift
//  NoteNarrator

import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Creates a lecture from a file: extracts or transcribes its text, then generates study materials.
enum LectureImporter {

    static let supportedTypes: [UTType] = [
        .pdf,
        .plainText,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("org.openxmlformats.presentationml.presentation"),
        .mp3, .wav, .mpeg4Audio, .aiff,
        .mpeg4Movie, .quickTimeMovie,
    ].compactMap { $0 }

    private static let mediaExtensions: Set<String> = ["mp3", "wav", "m4a", "aac", "aiff", "mp4", "mov", "m4v"]

    static func isMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    static let waitingMessage = "Waiting for the other imports to finish…"

    /// Files waiting to be processed. Imports run one at a time: the on-device model handles
    /// one lecture's generation far better than several competing for it at once.
    private static var queue: [(lecture: Lecture, url: URL)] = []
    private static var isProcessingQueue = false
    private static var activeLecture: Lecture?
    private static var activeTask: Task<Void, Never>?

    static func cancel(_ lecture: Lecture) {
        if let index = queue.firstIndex(where: { $0.lecture === lecture }) {
            queue.remove(at: index)
            lecture.isProcessing = false
            lecture.generationProgress = ""
            lecture.generationError = "Import cancelled. Import the file again when you're ready."
        } else if activeLecture === lecture {
            lecture.generationProgress = "Stopping…"
            activeTask?.cancel()
        }
    }

    /// Inserts a lecture for each file right away (so they show up and can be opened while
    /// they wait), then extracts and generates them one after another.
    @discardableResult
    static func importLectures(from urls: [URL], into folder: Folder?, context: ModelContext, existingTitles: [String]) -> [Lecture] {
        let titles = uniqueNames(for: urls.map { $0.deletingPathExtension().lastPathComponent }, existing: existingTitles)
        let lectures = zip(urls, titles).map { url, title in
            let lecture = Lecture(
                title: title,
                sourceType: isMedia(url) ? "media" : "document",
                fileExtension: url.pathExtension.lowercased()
            )
            lecture.isProcessing = true
            lecture.generationProgress = waitingMessage
            lecture.folder = folder
            context.insert(lecture)
            queue.append((lecture, url))
            return lecture
        }
        folder?.isExpanded = true
        // Save now so the new lectures get permanent IDs before the sidebar lists them;
        // otherwise their IDs change at the next autosave and the list draws ghost rows.
        try? context.save()
        processQueue()
        return lectures
    }

    private static func processQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        Task {
            while !queue.isEmpty {
                let next = queue.removeFirst()
                // Skip lectures deleted while they were waiting.
                guard !next.lecture.isDeleted else { continue }
                activeLecture = next.lecture
                let work = Task { await process(next.lecture, from: next.url) }
                activeTask = work
                await work.value
                activeTask = nil
                activeLecture = nil
            }
            isProcessingQueue = false
        }
    }

    /// Lectures left mid-extraction or mid-generation when the app last quit would otherwise
    /// show a spinner forever, since the work that would clear the flag is gone.
    static func recoverInterruptedLectures(in context: ModelContext) {
        let descriptor = FetchDescriptor<Lecture>(predicate: #Predicate { $0.isProcessing || $0.isGenerating })
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for lecture in stuck {
            lecture.isProcessing = false
            lecture.isGenerating = false
            lecture.generationProgress = ""
            lecture.generationError = lecture.transcript.isEmpty
                ? "Importing was interrupted when the app quit. Delete this lecture and import the file again."
                : "Generating was interrupted when the app quit. Use the Generate buttons in each tab to finish."
        }
    }

    /// Unique names for a batch, so two imported files with the same name don't collide either.
    static func uniqueNames(for baseNames: [String], existing: [String]) -> [String] {
        var taken = existing
        return baseNames.map { baseName in
            let name = uniqueName(baseName, existing: taken)
            taken.append(name)
            return name
        }
    }

    static func uniqueName(_ baseName: String, existing: [String]) -> String {
        guard existing.contains(baseName) else { return baseName }
        var counter = 1
        while existing.contains("\(baseName) (\(counter))") {
            counter += 1
        }
        return "\(baseName) (\(counter))"
    }

    // MARK: - Pipeline

    private static func process(_ lecture: Lecture, from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        lecture.generationProgress = ""
        let content: ExtractedContent
        do {
            content = try await extractOffMainThread(
                from: url,
                progress: { lecture.generationProgress = $0 },
                isAbandoned: { lecture.isDeleted }
            )
            try Task.checkCancellation()
        } catch {
            guard !lecture.isDeleted else { return }
            lecture.isProcessing = false
            lecture.generationProgress = ""
            lecture.generationError = Task.isCancelled || error is CancellationError
                ? "Import cancelled. Import the file again when you're ready."
                : error.localizedDescription
            return
        }

        // The student may have deleted the lecture while its file was being read.
        guard !lecture.isDeleted else { return }
        lecture.transcript = content.text
        lecture.extractionNotice = content.notice
        lecture.replaceFigures(with: content.figures)
        lecture.isProcessing = false
        guard !content.text.isEmpty else {
            lecture.generationError = content.figures.isEmpty
                ? "Couldn't find any text in this file. It may be empty, image-only in a format we can't read, or corrupted."
                : "Couldn't read any text in this file, but its pictures were saved — open the Notes tab to look at them."
            return
        }

        lecture.isGenerating = true
        do {
            let results = try await AIGenerator.generateAll(from: content.text) { progress in
                if !lecture.isDeleted { lecture.generationProgress = progress }
            }
            try Task.checkCancellation()
            guard !lecture.isDeleted else { return }
            lecture.summary = results.summary
            lecture.notes = results.notes
            lecture.notesByChunk = results.notesByChunk
            lecture.failedChunkIndices = results.failedChunkIndices
            lecture.appendQuiz(results.quiz)
            lecture.appendFlashcards(results.cards)
            if !results.missingOutputLabels.isEmpty {
                lecture.generationError = "Some study materials are missing (\(results.missingOutputLabels.joined(separator: ", "))). Open those tabs and use Generate to retry."
            }
        } catch {
            guard !lecture.isDeleted else { return }
            lecture.generationError = Task.isCancelled || error is CancellationError
                ? "Generation cancelled. Your extracted lecture is saved; use the Generate buttons to continue."
                : error.localizedDescription
        }
        lecture.isGenerating = false
        lecture.generationProgress = ""
    }

    /// Reading pictures and video frames is slow, so it runs off the main thread; progress
    /// messages come back through a stream and are applied here, on the main thread. If the
    /// student deletes the lecture meanwhile, the extraction is cancelled instead of finishing.
    private static func extractOffMainThread(
        from url: URL,
        progress: @MainActor (String) -> Void,
        isAbandoned: @MainActor () -> Bool
    ) async throws -> ExtractedContent {
        let (messages, continuation) = AsyncStream<String>.makeStream()
        let isMedia = isMedia(url)

        let work = Task.detached(priority: .userInitiated) { () throws -> ExtractedContent in
            defer { continuation.finish() }
            let report: ExtractionProgress = { continuation.yield($0) }
            return isMedia
                ? try await MediaExtractor.extract(from: url, progress: report)
                : await DocumentExtractor.extract(from: url, progress: report)
        }

        return try await withTaskCancellationHandler {
            for await message in messages {
                if isAbandoned() || Task.isCancelled {
                    work.cancel()
                    break
                }
                progress(message)
            }
            // Keep the security-scoped file open until detached extraction has stopped.
            let content = try await work.value
            try Task.checkCancellation()
            return content
        } onCancel: {
            work.cancel()
            continuation.finish()
        }
    }
}
