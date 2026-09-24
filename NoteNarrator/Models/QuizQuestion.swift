//  QuizQuestion.swift
//  NoteNarrator

import Foundation
import SwiftData

@Model
class QuizQuestion {
    var question: String
    var options: [String]
    var correctIndex: Int
    var sourceReference: String = ""  // e.g. "Slide 3", where this question came from
    var createdAt: Date = Date()      // keeps question order stable; relationships are unordered
    var selectedOption: Int?          // the student's answer, saved so progress survives relaunching

    var isAnswered: Bool { selectedOption != nil }
    var isAnsweredCorrectly: Bool { selectedOption == correctIndex }

    init(question: String, options: [String], correctIndex: Int, sourceReference: String = "", createdAt: Date = Date()) {
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.sourceReference = sourceReference
        self.createdAt = createdAt
    }
}
