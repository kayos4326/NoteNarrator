//  SidebarDragSelection.swift
//  NoteNarrator

import AppKit
import SwiftUI

/// Selects every lecture the mouse passes over while the button is held, like Finder.
///
/// The sidebar's List doesn't do this itself: on mouse-down it runs its own tracking loop that
/// only moves the single selection along, and that loop hides the drag events from everyone else.
/// So a plain click on a lecture row is handled here instead — the click, the drag, and the
/// release. ⌘-click, ⇧-click, right-click, and clicks on folder rows still go to the List.
///
/// Rows are found through AppKit (the List is an outline view), so this keeps working while the
/// list scrolls. Each lecture row carries an invisible `LectureRowMarker` naming its lecture.
@MainActor
final class SidebarDragSelection {
    var currentSelection: () -> Set<Lecture> = { [] }
    var onSelect: (Set<Lecture>) -> Void = { _ in }

    private var monitor: Any?
    private weak var tableView: NSTableView?
    private var anchorRow = -1
    private var selected: Set<Lecture> = []
    private var didLeaveAnchorRow = false
    /// Pressing on a lecture that's part of a larger selection keeps the selection (so it can be
    /// right-clicked or dragged over) until the button is released without moving to another row.
    private var lectureToSelectOnRelease: Lecture?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            nonisolated(unsafe) let event = event
            let isHandled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return isHandled ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        reset()
    }

    /// Returns true when the event was handled here and shouldn't reach the List.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            return begin(with: event)
        case .leftMouseDragged:
            guard let tableView, anchorRow >= 0 else { return false }
            extend(to: event, in: tableView)
            return true
        case .leftMouseUp:
            guard anchorRow >= 0 else { return false }
            if let lecture = lectureToSelectOnRelease, !didLeaveAnchorRow {
                onSelect([lecture])
            }
            reset()
            return true
        default:
            return false
        }
    }

    private func begin(with event: NSEvent) -> Bool {
        reset()
        // Modified clicks keep the List's behavior, and so does the click that activates the window.
        guard event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
              let window = event.window, window.isKeyWindow,
              let hitView = window.contentView?.hitTest(event.locationInWindow),
              let table = hitView.enclosingTableView
        else { return false }

        let row = table.row(at: table.convert(event.locationInWindow, from: nil))
        guard row >= 0, let lecture = lecture(atRow: row, in: table) else { return false }

        tableView = table
        anchorRow = row
        window.makeFirstResponder(table)  // so Delete and ⌘A still reach the list

        let selection = currentSelection()
        if selection.count > 1 && selection.contains(lecture) {
            lectureToSelectOnRelease = lecture
        } else {
            onSelect([lecture])
        }
        return true
    }

    private func extend(to event: NSEvent, in table: NSTableView) {
        table.autoscroll(with: event)
        let point = table.convert(event.locationInWindow, from: nil)
        var row = table.row(at: point)
        if row < 0 {
            row = point.y < 0 ? 0 : table.numberOfRows - 1
        }
        if row != anchorRow {
            didLeaveAnchorRow = true
        }
        guard didLeaveAnchorRow else { return }

        let lectures = Set((min(anchorRow, row)...max(anchorRow, row)).compactMap { lecture(atRow: $0, in: table) })
        guard lectures != selected, !lectures.isEmpty else { return }
        selected = lectures
        onSelect(lectures)
    }

    /// Folder rows and section headers have no marker, so they're skipped.
    private func lecture(atRow row: Int, in table: NSTableView) -> Lecture? {
        table.rowView(atRow: row, makeIfNecessary: false)?
            .firstDescendant(of: LectureRowMarker.MarkerView.self)?
            .lecture
    }

    private func reset() {
        tableView = nil
        anchorRow = -1
        selected = []
        didLeaveAnchorRow = false
        lectureToSelectOnRelease = nil
    }
}

/// An invisible view inside a lecture row that tells `SidebarDragSelection` which lecture it is.
struct LectureRowMarker: NSViewRepresentable {
    let lecture: Lecture

    final class MarkerView: NSView {
        var lecture: Lecture?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.lecture = lecture
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: MarkerView, context: Context) {
        view.lecture = lecture
    }
}

private extension NSView {
    var enclosingTableView: NSTableView? {
        sequence(first: self, next: \.superview).lazy.compactMap { $0 as? NSTableView }.first
    }

    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
