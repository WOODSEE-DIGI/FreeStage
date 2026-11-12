//
//  DragDivider.swift
//  FreeStage
//
//  AppKit-based vertical divider. Reports raw mouse deltaX during a drag so
//  the parent can resize columns reliably even when the divider's own frame
//  moves. This avoids the SwiftUI gesture coordinate-space problems that made
//  the previous dividers glitchy.
//

import SwiftUI
import AppKit

struct DragDivider: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> DragDividerView {
        let view = DragDividerView()
        view.onDrag = onDrag
        return view
    }

    func updateNSView(_ nsView: DragDividerView, context: Context) {
        nsView.onDrag = onDrag
    }
}

final class DragDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
        let lineRect = NSRect(x: bounds.midX - 0.5, y: bounds.minY + 4, width: 1, height: bounds.height - 8)
        lineRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(CGFloat(event.deltaX))
    }

    override func mouseUp(with event: NSEvent) {
        window?.makeFirstResponder(nil)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
}
