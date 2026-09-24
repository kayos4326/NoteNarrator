//  QuizQuestionView.swift
//  NoteNarrator

import SwiftUI

struct QuizQuestionView: View {
    let question: QuizQuestion
    let number: Int
    let selectedOption: Int?
    let isBookmarked: Bool
    let onAnswer: (Int) -> Void
    let onToggleBookmark: () -> Void
    let onLookBack: () -> Void

    @State private var hoveredOption: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(Text("Q\(number).").foregroundStyle(Color.brandAccent))  \(question.question)")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(option, index: index)
                }
            }

            if let selectedOption {
                Divider()
                result(isCorrect: selectedOption == question.correctIndex)
            }
        }
        .studyCard(padding: 20)
    }

    private func optionRow(_ option: String, index: Int) -> some View {
        Button {
            onAnswer(index)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: index))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(iconColor(for: index))
                Text(option)
                    .foregroundStyle(textStyle(for: index))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill(for: index)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(border(for: index), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(selectedOption != nil)
        .onHover { hoveredOption = $0 ? index : (hoveredOption == index ? nil : hoveredOption) }
    }

    private func result(isCorrect: Bool) -> some View {
        HStack(spacing: 14) {
            Label(isCorrect ? "Correct" : "Incorrect", systemImage: isCorrect ? "checkmark" : "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(isCorrect ? Color.brandAccent : .red)

            if !question.sourceReference.isEmpty {
                Button(action: onLookBack) {
                    Label("Look back at \(ReferenceMatcher.displayName(for: question.sourceReference))",
                          systemImage: "arrow.uturn.backward")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandAccent)
                .pointerStyle(.link)
                .help("Open this part of the notes")

                Spacer()

                Button(action: onToggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.body)
                        .foregroundStyle(isBookmarked ? Color.brandAccent : .secondary)
                }
                .buttonStyle(.plain)
                .help(isBookmarked ? "Remove bookmark" : "Bookmark this section")
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark this section")
            }
        }
    }

    // MARK: - Option states

    private enum OptionState { case unanswered, correct, wrongChoice, other }

    private func state(for index: Int) -> OptionState {
        guard let selectedOption else { return .unanswered }
        if index == question.correctIndex { return .correct }
        return index == selectedOption ? .wrongChoice : .other
    }

    private func icon(for index: Int) -> String {
        switch state(for: index) {
        case .unanswered, .other: "circle"
        case .correct: "checkmark.circle.fill"
        case .wrongChoice: "xmark.circle.fill"
        }
    }

    private func iconColor(for index: Int) -> Color {
        switch state(for: index) {
        case .unanswered, .other: .secondary
        case .correct: .brandAccent
        case .wrongChoice: .red
        }
    }

    // Other options stay readable after answering, so the student can see why they were wrong.
    private func textStyle(for index: Int) -> Color {
        state(for: index) == .other ? .secondary : .primary
    }

    private func fill(for index: Int) -> Color {
        switch state(for: index) {
        case .unanswered: Color.primary.opacity(hoveredOption == index ? 0.07 : 0.03)
        case .correct: Color.brandAccent.opacity(0.12)
        case .wrongChoice: Color.red.opacity(0.12)
        case .other: .clear
        }
    }

    private func border(for index: Int) -> Color {
        switch state(for: index) {
        case .unanswered: Color.primary.opacity(0.08)
        case .correct: Color.brandAccent.opacity(0.5)
        case .wrongChoice: Color.red.opacity(0.5)
        case .other: Color.primary.opacity(0.05)
        }
    }
}
