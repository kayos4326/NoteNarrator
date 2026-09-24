//  SidebarRows.swift
//  NoteNarrator

import SwiftUI

struct LectureRow: View {
    let lecture: Lecture
    let showsFolder: Bool

    var body: some View {
        let isBusy = lecture.isProcessing || lecture.isGenerating
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                // One Label whose icon swaps, so the row keeps the same structure while busy.
                Label {
                    Text(lecture.title)
                } icon: {
                    Image(systemName: Self.symbolName(forExtension: lecture.fileExtension))
                        .opacity(isBusy ? 0 : 1)
                        .overlay {
                            if isBusy {
                                ProgressView().controlSize(.mini)
                            }
                        }
                }
                Spacer(minLength: 0)
                if lecture.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Pinned")
                }
                if !lecture.generationError.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(lecture.generationError)
                }
            }
            .lineLimit(1)

            if showsFolder, let folder = lecture.folder {
                Label(folder.name, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 24)
            }
        }
        .background(LectureRowMarker(lecture: lecture))
    }

    /// An icon for the kind of file the lecture was imported from.
    static func symbolName(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "pdf": "doc.richtext"
        case "pptx": "rectangle.on.rectangle"
        case "docx": "doc.text"
        case "txt": "doc.plaintext"
        case "mp3", "wav", "m4a", "aac", "aiff": "waveform"
        case "mp4", "mov", "m4v": "film"
        default: "doc"
        }
    }
}

/// A sidebar section heading with a count on the right, e.g. "FOLDERS    2 folders".
struct SidebarSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .tracking(0.6)
            Spacer()
            Text(detail)
                .fontWeight(.regular)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.trailing, 8)
    }
}

/// Reminds students that their files and the AI stay on their Mac.
struct PrivacyBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Color.brandAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.brandAccent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Runs locally on your Mac")
                    .font(.callout.weight(.medium))
                Text("Your files never leave this Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(10)
        .accessibilityElement(children: .combine)
    }
}

struct FolderRow<Row: View>: View {
    @Bindable var folder: Folder
    let lectures: [Lecture]
    let lectureRow: (Lecture) -> Row
    let onImport: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $folder.isExpanded) {
            if lectures.isEmpty {
                Text("Empty. Right-click the folder to import, or use Move to Folder on a lecture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lectures) { lectureRow($0) }
        } label: {
            HStack {
                Label {
                    Text(folder.name)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.brandAccent)
                }
                Spacer()
                Text("\(folder.lectures.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Import Lectures Here…", systemImage: "square.and.arrow.down", action: onImport)
                Button("Rename…", systemImage: "pencil", action: onRename)
                Divider()
                Button("Delete Folder…", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}
