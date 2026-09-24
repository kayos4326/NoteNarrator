//  AudioTranscriber.swift
//  NoteNarrator

import AVFoundation
import Foundation
import Speech

/// Something the speaker said, and when they said it.
nonisolated struct SpokenSegment: Sendable {
    let seconds: Double
    let text: String
}

nonisolated enum AudioTranscriber {

    enum TranscriptionError: LocalizedError {
        case languageNotSupported

        var errorDescription: String? {
            "English speech recognition isn't available on this Mac, so the recording couldn't be transcribed."
        }
    }

    /// Transcribes an audio or video file with on-device speech recognition, keeping the time
    /// of each phrase so notes and quiz questions can point back at "12:30".
    static func transcribe(url: URL) async throws -> [SpokenSegment] {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) else {
            throw TranscriptionError.languageNotSupported
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Downloads the speech model the first time it's needed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let transcription = transcriber.results.reduce(into: [SpokenSegment]()) { segments, result in
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let start = result.range.start
            segments.append(SpokenSegment(seconds: start.isNumeric ? start.seconds : 0, text: text))
        }

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await transcription
    }
}
