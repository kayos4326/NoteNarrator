//  Flashcard.swift
//  NoteNarrator

import Foundation
import SwiftData

@Model
class Flashcard {
    var front: String
    var back: String
    var createdAt: Date = Date()  // keeps card order stable; relationships are unordered

    init(front: String, back: String, createdAt: Date = Date()) {
        self.front = front
        self.back = back
        self.createdAt = createdAt
    }
}
