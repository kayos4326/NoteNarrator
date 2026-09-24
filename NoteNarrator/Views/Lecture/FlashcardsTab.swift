//  FlashcardsTab.swift
//  NoteNarrator

import SwiftUI

struct FlashcardsTab: View {
    let session: LectureSession

    var body: some View {
        let cards = session.lecture.orderedFlashcards
        if cards.isEmpty {
            GeneratePrompt(title: "Generate Flashcards", message: "No flashcards yet",
                           detail: "Get cards with a key term on the front and its meaning on the back.",
                           systemImage: "rectangle.on.rectangle.angled", action: .generateFlashcards, session: session)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(cards.count) \(cards.count == 1 ? "card" : "cards")")
                    .font(.headline)

                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    FlashcardView(card: card, number: index + 1, total: cards.count)
                }

                HStack(spacing: 12) {
                    GenerationButton(title: "New cards", systemImage: "arrow.clockwise",
                                     action: .regenerateFlashcards, session: session)
                    GenerationButton(title: "Add 5 cards", systemImage: "plus.circle",
                                     action: .addFlashcards, session: session)
                }
            }
        }
    }
}
