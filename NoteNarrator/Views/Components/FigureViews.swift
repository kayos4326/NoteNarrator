//  FigureViews.swift
//  NoteNarrator

import SwiftUI

/// The pictures from a page, slide, or moment in a recording, shown under its notes so the
/// student can look at a diagram the app could only partly read.
struct FigureStrip: View {
    let figures: [LectureFigure]
    var showsHeading = true

    @State private var opened: LectureFigure?

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 10, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeading {
                SectionHeading(figures.count == 1 ? "Picture" : "Pictures", systemImage: "photo")
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(figures) { figure in
                    Button { opened = figure } label: {
                        FigureThumbnail(figure: figure)
                    }
                    .buttonStyle(.plain)
                    .help("Click to see \(ReferenceMatcher.displayName(for: figure.reference)) full size")
                }
            }
        }
        .sheet(item: $opened) { figure in
            FigureSheet(figure: figure) { opened = nil }
        }
    }
}

private struct FigureThumbnail: View {
    let figure: LectureFigure

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Every thumbnail gets the same box, so tall photos and wide slides line up in rows.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let image = NSImage(data: figure.imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Text(ReferenceMatcher.displayName(for: figure.reference))
                .font(.callout.weight(.medium))
            if !figure.hasReadableText {
                Text("No text found in this picture")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FigureSheet: View {
    let figure: LectureFigure
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(ReferenceMatcher.displayName(for: figure.reference))
                    .font(.headline)
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
                    .help("Close (Esc)")
            }
            .padding(12)

            Divider()

            if let image = NSImage(data: figure.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
        }
        // Large enough to read a slide's text, and still inside the smallest lecture window.
        .frame(width: 860, height: 600)
        .onExitCommand(perform: onClose)
    }
}
