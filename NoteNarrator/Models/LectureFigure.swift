//  LectureFigure.swift
//  NoteNarrator

import Foundation
import SwiftData

/// A picture from a page, slide, or moment in a recording. Kept so the student can look at a
/// diagram themselves — the on-device model reads words, it can't interpret a drawing.
@Model
final class LectureFigure {
    var reference: String      // "Page 12", "Slide 4", or a timecode like "12:30"
    @Attribute(.externalStorage) var imageData: Data
    var hasReadableText: Bool
    var order: Int
    var lecture: Lecture?

    init(reference: String, imageData: Data, hasReadableText: Bool, order: Int) {
        self.reference = reference
        self.imageData = imageData
        self.hasReadableText = hasReadableText
        self.order = order
    }
}
