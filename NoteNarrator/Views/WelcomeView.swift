//  WelcomeView.swift
//  NoteNarrator

import SwiftUI

struct WelcomeView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            Text("Welcome to NoteNarrator")
                .font(.largeTitle.bold())

            Text("Import lecture slides, a document, or a recording, and get a summary, notes, a quiz, and flashcards.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button("Import Lectures…", systemImage: "square.and.arrow.down", action: onImport)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            if !AIReadinessMonitor.shared.isReady {
                AIReadinessIndicator(readiness: AIReadinessMonitor.shared.readiness)
            }

            Text("PDF, PowerPoint, Word, text, audio, or video — select several files at once")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView {}
}
