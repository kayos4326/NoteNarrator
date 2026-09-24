//  QuizTab.swift
//  NoteNarrator

import SwiftUI

struct QuizTab: View {
    let session: LectureSession

    var body: some View {
        let questions = session.lecture.orderedQuizQuestions
        if questions.isEmpty {
            GeneratePrompt(title: "Generate Quiz", message: "No quiz yet",
                           detail: "Test yourself with multiple-choice questions. Each answer links back to your notes.",
                           systemImage: "checkmark.circle", action: .generateQuiz, session: session)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                scoreHeader(total: questions.count)

                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    QuizQuestionView(
                        question: question,
                        number: index + 1,
                        selectedOption: question.selectedOption,
                        isBookmarked: !session.bookmarks(matching: question.sourceReference).isEmpty,
                        onAnswer: { session.answer(question, with: $0) },
                        onToggleBookmark: { session.toggleBookmark(for: question.sourceReference) },
                        onLookBack: { session.jumpToNotes(question.sourceReference) }
                    )
                }

                HStack(spacing: 12) {
                    GenerationButton(title: "New quiz", systemImage: "arrow.clockwise",
                                     action: .regenerateQuiz, session: session)
                    GenerationButton(title: "Add 5 questions", systemImage: "plus.circle",
                                     action: .addQuizQuestions, session: session)
                }
            }
        }
    }

    private func scoreHeader(total: Int) -> some View {
        let answered = session.lecture.answeredQuestionCount
        return HStack(spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandAccent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Score: \(session.lecture.correctAnswerCount)/\(answered)")
                        .font(.title3.bold())
                        .monospacedDigit()
                    Pill(answered == total ? "Finished" : "\(total - answered) of \(total) left")
                }
                Text("Your answers are saved, so you can come back later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if answered > 0 {
                Button("Start over", systemImage: "arrow.counterclockwise") {
                    session.resetAnswers()
                }
                .help("Clear your answers and retake this quiz")
            }
        }
        .studyCard(padding: 16)
    }
}
