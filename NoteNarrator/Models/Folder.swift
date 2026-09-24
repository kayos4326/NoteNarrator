//  Folder.swift
//  NoteNarrator

import Foundation
import SwiftData

@Model
class Folder {
    var name: String
    var dateCreated: Date
    var isExpanded: Bool = true

    // Deleting a folder keeps its lectures — they just become unfiled.
    @Relationship(deleteRule: .nullify, inverse: \Lecture.folder) var lectures: [Lecture] = []

    init(name: String) {
        self.name = name
        self.dateCreated = Date()
    }
}
