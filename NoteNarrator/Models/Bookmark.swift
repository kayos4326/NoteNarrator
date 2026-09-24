//  Bookmark.swift
//  NoteNarrator

import Foundation
import SwiftData

@Model
class Bookmark {
    var reference: String   // e.g. "Slide 3" or "Page 2" — where to look back
    var note: String        // optional student-added label
    var dateAdded: Date

    init(reference: String, note: String = "") {
        self.reference = reference
        self.note = note
        self.dateAdded = Date()
    }
}
