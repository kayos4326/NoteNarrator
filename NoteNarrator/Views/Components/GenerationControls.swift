//  GenerationControls.swift
//  NoteNarrator

import SwiftUI

/// A button that starts a generation action; only the one that's running shows a spinner.
struct GenerationButton: View {
    let title: String
    let systemImage: String
    let action: LectureSession.Action
    let session: LectureSession
    var prominent = false

    var body: some View {
        Button {
            session.perform(action)
        } label: {
            if session.runningAction == action {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(title)
                }
            } else {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(prominent ? Color.white : Color.brandAccent)
                }
            }
        }
        .controlSize(.large)
        .disabled(session.isBusy)
        .modifier(ProminentIf(prominent))
    }
}

private struct ProminentIf: ViewModifier {
    let isProminent: Bool
    init(_ isProminent: Bool) { self.isProminent = isProminent }

    func body(content: Content) -> some View {
        if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// The actual macOS model availability, not connectivity. Shared so every screen agrees, and
/// refreshed by the app whenever it becomes active.
@Observable
final class AIReadinessMonitor {
    static let shared = AIReadinessMonitor()

    private(set) var readiness = AIGenerator.readiness

    var isReady: Bool { readiness == .ready }

    func refresh() { readiness = AIGenerator.readiness }
}

/// Shown only while the on-device model can't be used, with what to do about it.
struct AIReadinessIndicator: View {
    let readiness: AIGenerator.Readiness

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(readiness.title).font(.callout.weight(.semibold))
                Text(readiness.detail).font(.caption).foregroundStyle(.secondary)
            }
            Button("Check again") { AIReadinessMonitor.shared.refresh() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .help(readiness.detail)
    }
}

/// An icon on a soft green rounded tile, used by empty and in-progress states.
private struct IconTile<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.system(size: 28))
            .foregroundStyle(Color.brandAccent)
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.brandAccent.opacity(0.14)))
    }
}

/// Empty state for a tab whose content hasn't been generated.
struct GeneratePrompt: View {
    let title: String
    let message: String
    let detail: String
    let systemImage: String
    let action: LectureSession.Action
    let session: LectureSession

    var body: some View {
        VStack(spacing: 14) {
            IconTile { Image(systemName: systemImage) }
            VStack(spacing: 4) {
                Text(message)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            if !session.lecture.transcript.isEmpty {
                GenerationButton(title: title, systemImage: "sparkles", action: action, session: session, prominent: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

struct StatusView: View {
    let title: String
    let subtitle: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            IconTile { ProgressView().controlSize(.regular) }
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            // Above the hint and with a short top margin, so Cancel stays visible in a short window.
            if let onCancel {
                Button(subtitle == "Stopping…" ? "Stopping…" : "Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .disabled(subtitle == "Stopping…")
            }
            Text("You can open other lectures while this runs.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}

struct Banner: View {
    enum Style { case error, info }

    let message: String
    let style: Style
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var tint: Color {
        style == .error ? .orange : .brandAccent
    }
}
