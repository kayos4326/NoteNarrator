//  LectureDetailView.swift
//  NoteNarrator

import SwiftData
import SwiftUI

struct LectureDetailView: View {
    @State private var session: LectureSession
    /// Tabs that have been opened. Each keeps its own scroll view alive after that, so coming
    /// back to a tab shows it where the student left off (quiz question 5 stays at question 5).
    @State private var openedTabs: Set<LectureSession.Tab> = []

    init(lecture: Lecture, context: ModelContext) {
        _session = State(initialValue: LectureSession(lecture: lecture, context: context))
    }

    private var lecture: Lecture { session.lecture }

    /// The header, banners, and tab content share one centered column, so they stay lined up
    /// in a wide or full-screen window.
    private static let columnWidth: CGFloat = 860
    private static let columnPadding: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !AIReadinessMonitor.shared.isReady {
                AIReadinessIndicator(readiness: AIReadinessMonitor.shared.readiness)
                    .frame(maxWidth: Self.columnWidth, alignment: .leading)
                    .padding(.horizontal, Self.columnPadding)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }

            if session.isBusy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(lecture.generationProgress.isEmpty ? "Generating…" : lecture.generationProgress)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(session.isStopping ? "Stopping…" : "Cancel") { session.cancelCurrentAction() }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .disabled(session.isStopping)
                }
                .padding(12)
                .background(Color.brandAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: Self.columnWidth)
                .padding(.horizontal, Self.columnPadding)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }

            if !lecture.generationError.isEmpty {
                Banner(message: lecture.generationError, style: .error) {
                    lecture.generationError = ""
                }
                .frame(maxWidth: Self.columnWidth + 2 * Self.columnPadding)
                .frame(maxWidth: .infinity)
            }
            if let message = session.infoMessage {
                Banner(message: message, style: .info)
                    .frame(maxWidth: Self.columnWidth + 2 * Self.columnPadding)
                    .frame(maxWidth: .infinity)
            }
            if !lecture.extractionNotice.isEmpty {
                Banner(message: lecture.extractionNotice, style: .info) {
                    lecture.extractionNotice = ""
                }
                .frame(maxWidth: Self.columnWidth + 2 * Self.columnPadding)
                .frame(maxWidth: .infinity)
            }
            if !lecture.failedChunkIndices.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(lecture.failedChunkIndices.count) lecture \(lecture.failedChunkIndices.count == 1 ? "section" : "sections") could not be read. Study materials are incomplete.")
                        Button("Retry missing sections") { session.perform(.retryFailedSections) }
                            .disabled(session.isBusy || lecture.isGenerating || lecture.isProcessing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: Self.columnWidth)
                .padding(.horizontal, Self.columnPadding)
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            }

            content
        }
        .confirmationDialog(
            "Remove bookmark?",
            isPresented: Binding(
                get: { !session.bookmarksPendingRemoval.isEmpty },
                set: { if !$0 { session.bookmarksPendingRemoval = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { session.confirmPendingBookmarkRemoval() }
        } message: {
            Text("The note you wrote on this bookmark will be deleted too.")
        }
    }

    // MARK: - Header

    /// Title and tabs share one row when there's room, and stack when the window is narrow.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 20) {
                titleBlock
                Spacer(minLength: 0)
                tabPicker
            }
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                tabPicker
            }
        }
        .frame(maxWidth: Self.columnWidth, alignment: .leading)
        .padding(.horizontal, Self.columnPadding)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let folder = lecture.folder {
                Label(folder.name, systemImage: "folder.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.brandAccent)
            } else {
                Label("Unfiled", systemImage: "tray")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(lecture.title)
                .font(.title.bold())
                .lineLimit(2)
        }
    }

    private var tabPicker: some View {
        Picker("Section", selection: $session.selectedTab) {
            ForEach(LectureSession.Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .controlSize(.large)
        .disabled(lecture.isProcessing || lecture.isGenerating)
    }

    // MARK: - Content

    private var processingTitle: String {
        if lecture.generationProgress == LectureImporter.waitingMessage { return "Waiting to import…" }
        return lecture.isMedia ? "Reading the recording…" : "Reading the file…"
    }

    @ViewBuilder
    private var content: some View {
        if lecture.isProcessing {
            ScrollView {
                column {
                    StatusView(title: processingTitle,
                               subtitle: lecture.generationProgress.isEmpty
                                   ? "This may take a moment."
                                   : lecture.generationProgress,
                               onCancel: { LectureImporter.cancel(lecture) })
                }
            }
        } else if lecture.isGenerating {
            ScrollView {
                column {
                    StatusView(title: "Generating study materials…",
                               subtitle: lecture.generationProgress.isEmpty
                                   ? "Creating summary, notes, quiz, and flashcards."
                                   : lecture.generationProgress,
                               onCancel: { LectureImporter.cancel(lecture) })
                }
            }
        } else {
            ScrollViewReader { proxy in
                ZStack {
                    ForEach(LectureSession.Tab.allCases) { tab in
                        if tab == session.selectedTab || openedTabs.contains(tab) {
                            tabScrollView(tab)
                        }
                    }
                }
                .onChange(of: session.selectedTab, initial: true) {
                    openedTabs.insert(session.selectedTab)
                }
                .onChange(of: session.notesJump) { _, jump in
                    guard let jump else { return }
                    scroll(to: jump, proxy: proxy)
                }
            }
        }
    }

    /// Hidden tabs stay mounted (keeping their scroll position, flipped cards, and typed notes)
    /// but can't be seen, clicked, focused, or read by VoiceOver.
    private func tabScrollView(_ tab: LectureSession.Tab) -> some View {
        let isSelected = tab == session.selectedTab
        return ScrollView {
            column { tabContent(tab) }
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .disabled(!isSelected)
        .accessibilityHidden(!isSelected)
    }

    @ViewBuilder
    private func tabContent(_ tab: LectureSession.Tab) -> some View {
        switch tab {
        case .summary: SummaryTab(session: session)
        case .notes: NotesTab(session: session)
        case .quiz: QuizTab(session: session)
        case .flashcards: FlashcardsTab(session: session)
        case .bookmarks: BookmarksTab(session: session)
        }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: Self.columnWidth)
            .padding(Self.columnPadding)
            .frame(maxWidth: .infinity)
    }

    private func scroll(to jump: LectureSession.NotesJump, proxy: ScrollViewProxy) {
        Task {
            // The Notes tab may mount in this same update: wait for layout, scroll, then
            // scroll again once long sections above the target have finished sizing.
            try? await Task.sleep(for: .milliseconds(80))
            guard session.notesJump == jump else { return }
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(jump.sectionID, anchor: .top) }
            session.highlightSection(jump.sectionID)

            try? await Task.sleep(for: .milliseconds(300))
            guard session.notesJump == jump else { return }
            proxy.scrollTo(jump.sectionID, anchor: .top)
        }
    }
}
