//  FlashcardView.swift
//  NoteNarrator

import SwiftUI

struct FlashcardView: View {
    let card: Flashcard
    let number: Int
    let total: Int
    @State private var showsBack = false

    var body: some View {
        Button {
            showsBack.toggle()
        } label: {
            ZStack {
                face(caption: "Card \(number) of \(total)", text: card.front, hint: "Click to reveal the answer",
                     isAnswer: false)
                    .modifier(FaceVisibility(angle: showsBack ? 180 : 0, isBack: false))
                face(caption: "Card \(number) · Answer", text: card.back, hint: "Click to see the term",
                     isAnswer: true)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .modifier(FaceVisibility(angle: showsBack ? 180 : 0, isBack: true))
            }
            .rotation3DEffect(.degrees(showsBack ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .animation(.spring(duration: 0.45, bounce: 0.15), value: showsBack)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsBack ? "Answer: \(card.back)" : "Card \(number): \(card.front)")
        .accessibilityHint(showsBack ? "Shows the term" : "Reveals the answer")
    }

    private func face(caption: String, text: String, hint: String, isAnswer: Bool) -> some View {
        VStack(spacing: 10) {
            Text(caption)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(text)
                .font(isAnswer ? .body : .title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(hint)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: isAnswer
                        ? [Color.brandGreen.mix(with: .black, by: 0.45), Color.brandGreen.mix(with: .black, by: 0.6)]
                        : [Color.brandGreen, Color.brandGreen.mix(with: .black, by: 0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Shows each side only while it faces the student, switching halfway through the flip.
private struct FaceVisibility: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity((angle > 90) == isBack ? 1 : 0)
    }
}
