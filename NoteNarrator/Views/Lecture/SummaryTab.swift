//  SummaryTab.swift
//  NoteNarrator

import SwiftUI

struct SummaryTab: View {
    let session: LectureSession

    var body: some View {
        if session.lecture.summary.isEmpty {
            GeneratePrompt(title: "Generate Summary", message: "No summary yet",
                           detail: "Get a short overview of this lecture and its key points.",
                           systemImage: "text.alignleft", action: .generateSummary, session: session)
        } else {
            let content = SummaryContent.parse(session.lecture.summary)
            VStack(alignment: .leading, spacing: 24) {
                if !content.overview.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeading("Overview", systemImage: "text.alignleft")
                        ForEach(Array(content.overview.enumerated()), id: \.offset) { _, paragraph in
                            MarkdownText(paragraph)
                                .lineSpacing(4)
                        }
                    }
                    .studyCard(padding: 20)
                }

                if !content.keyPoints.isEmpty {
                    keyPoints(content.keyPoints)
                }

                GenerationButton(title: "Regenerate summary", systemImage: "arrow.clockwise",
                                 action: .generateSummary, session: session)
            }
        }
    }

    private func keyPoints(_ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading("Key Points", systemImage: "checklist")
                Spacer()
                Text("\(points.count) \(points.count == 1 ? "point" : "points")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.callout.bold())
                            .monospacedDigit()
                            .foregroundStyle(Color.brandAccent)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.brandAccent.opacity(0.15)))
                        MarkdownText(point)
                            .padding(.top, 3)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .studyCard(padding: 14)
                }
            }
        }
    }
}
