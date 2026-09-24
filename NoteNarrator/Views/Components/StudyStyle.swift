//  StudyStyle.swift
//  NoteNarrator
//
//  The shared look of the study tabs: soft rounded cards, green uppercase headings, and pills.
//  Colors are built from the primary color and the brand greens so they work in light and dark mode.

import SwiftUI

extension View {
    /// A rounded card. Highlighted cards get a green tint; outlined ones a green border.
    func studyCard(padding: CGFloat = 18, isHighlighted: Bool = false, isOutlined: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHighlighted ? Color.brandAccent.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isHighlighted || isOutlined ? Color.brandAccent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .animation(.easeOut(duration: 0.3), value: isHighlighted)
    }
}

/// A small green uppercase heading, e.g. "KEY CONCEPTS".
struct SectionHeading: View {
    let title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title.uppercased())
                .tracking(0.6)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(Color.brandAccent)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A capsule label for short status text, e.g. "2 left".
struct Pill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// A bullet line that renders the model's light markdown.
struct BulletText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.tertiary)
            MarkdownText(text)
        }
    }
}
