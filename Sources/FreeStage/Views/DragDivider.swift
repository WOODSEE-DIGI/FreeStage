//
//  DragDivider.swift
//  FreeStage
//
//  AppKit-based vertical divider. Reports raw mouse deltaX during a drag so
//  the parent can resize columns reliably. Implemented as an
//  NSViewControllerRepresentable because that gives more reliable mouse-event
//  delivery inside SwiftUI than NSViewRepresentable for interactive controls.
//

import SwiftUI
import AppKit

struct DragDivider: NSViewControllerRepresentable {
    let onDrag: (CGFloat) -> Void

    func makeNSViewController(context: Context) -> DragDividerViewController {
        let controller = DragDividerViewController()
        controller.onDrag = onDrag
        return controller
    }

    func updateNSViewController(_ nsViewController: DragDividerViewController, context: Context) {
        nsViewController.onDrag = onDrag
    }
}

final class DragDividerViewController: NSViewController {
    var onDrag: ((CGFloat) -> Void)?

    override func loadView() {
        view = DragDividerView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? DragDividerView)?.onDrag = { [weak self] delta in
            self?.onDrag?(delta)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        (view as? DragDividerView)?.onDrag = { [weak self] delta in
            self?.onDrag?(delta)
        }
    }
}

final class DragDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?

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
        autoresizingMask = [.width, .height]
        // A near-transparent layer background ensures the full 14 pt strip
        // participates in hit-testing, not just the 1 pt visible line.
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.001).cgColor
    }

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
