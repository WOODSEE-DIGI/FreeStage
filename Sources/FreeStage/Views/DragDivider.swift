//
//  DragDivider.swift
//  FreeStage
//
//  AppKit-based vertical divider. Reports raw mouse deltaX during a drag so
//  the parent can resize columns reliably.
//

import SwiftUI
import AppKit

struct DragDivider: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> DragDividerView {
        let view = DragDividerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DragDividerView, context: Context) {
        context.coordinator.onDrag = onDrag
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrag: onDrag)
    }

    final class Coordinator: NSObject {
        var onDrag: (CGFloat) -> Void

        init(onDrag: @escaping (CGFloat) -> Void) {
            self.onDrag = onDrag
        }
    }
}

final class DragDividerView: NSView {
    weak var coordinator: DragDivider.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // Slightly tinted layer background so the full 14 pt strip participates
        // in hit-testing, not just the 1 pt visible line.
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.05).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setFill()
        let lineRect = NSRect(x: bounds.midX - 0.5, y: bounds.minY + 4, width: 1, height: bounds.height - 8)
        lineRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        _ = window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator?.onDrag(CGFloat(event.deltaX))
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
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseEnteredAndExited,
            .cursorUpdate,
            .inVisibleRect,
        ]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }
}
