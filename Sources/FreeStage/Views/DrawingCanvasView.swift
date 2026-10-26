//
//  DrawingCanvasView.swift
//  FreeStage
//
//  macOS drawing surface for a DrawingSource. Tracks mouse/tablet input,
//  supports freehand pen, eraser, shapes, arrows, and text placement.
//

import SwiftUI
import AppKit

struct DrawingCanvasView: NSViewRepresentable {
    @Binding var source: DrawingSource

    func makeNSView(context: Context) -> DrawingCanvasNSView {
        let view = DrawingCanvasNSView()
        view.delegate = context.coordinator
        view.update(source: source)
        return view
    }

    func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
        nsView.update(source: source)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(source: $source)
    }

    final class Coordinator: DrawingCanvasDelegate {
        @Binding var source: DrawingSource

        init(source: Binding<DrawingSource>) {
            self._source = source
        }

        func canvasDidUpdateSource(_ source: DrawingSource) {
            self.source = source
        }
    }
}

protocol DrawingCanvasDelegate: AnyObject {
    func canvasDidUpdateSource(_ source: DrawingSource)
}

final class DrawingCanvasNSView: NSView {
    weak var delegate: DrawingCanvasDelegate?
    private var source: DrawingSource?
    private var currentStroke: DrawingStroke?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(source: DrawingSource) {
        self.source = source
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let source else { return }

        if source.tool == .text {
            promptForText(at: event.locationInWindow)
            return
        }

        if source.tool.isShape {
            beginShape(at: event.locationInWindow)
        } else {
            beginFreehandStroke(at: event.locationInWindow, pressure: event.pressure)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if source?.tool.isShape == true {
            updateShape(at: event.locationInWindow)
        } else {
            appendFreehandPoint(at: event.locationInWindow, pressure: event.pressure)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if source?.tool.isShape == true {
            finishShape()
        } else {
            finishFreehandStroke()
        }
    }

    // MARK: - Freehand

    private func beginFreehandStroke(at point: CGPoint, pressure: Float) {
        guard let source else { return }
        currentStroke = DrawingStroke(
            points: [normalizedPoint(point, pressure: pressure)],
            color: source.color,
            width: source.brushWidth,
            tool: source.tool
        )
    }

    private func appendFreehandPoint(at point: CGPoint, pressure: Float) {
        guard currentStroke != nil else { return }
        currentStroke?.points.append(normalizedPoint(point, pressure: pressure))
        needsDisplay = true
    }

    private func finishFreehandStroke() {
        guard var source, var stroke = currentStroke, stroke.points.count > 1 else {
            currentStroke = nil
            return
        }

        if stroke.tool == .eraser {
            // Ensure eraser strokes have some width so the clear blend mode is visible.
            stroke.width = max(stroke.width, 8)
        }

        source.strokes.append(stroke)
        currentStroke = nil
        delegate?.canvasDidUpdateSource(source)
    }

    // MARK: - Shapes

    private func beginShape(at point: CGPoint) {
        guard let source else { return }
        currentStroke = DrawingStroke(
            points: [normalizedPoint(point, pressure: nil)],
            color: source.color,
            width: source.brushWidth,
            tool: source.tool
        )
    }

    private func updateShape(at point: CGPoint) {
        guard var stroke = currentStroke else { return }
        let normalized = normalizedPoint(point, pressure: nil)
        if stroke.points.count == 1 {
            stroke.points.append(normalized)
        } else {
            stroke.points[1] = normalized
        }
        currentStroke = stroke
        needsDisplay = true
    }

    private func finishShape() {
        guard var source, let stroke = currentStroke, stroke.points.count == 2 else {
            currentStroke = nil
            return
        }
        source.strokes.append(stroke)
        currentStroke = nil
        delegate?.canvasDidUpdateSource(source)
    }

    // MARK: - Text

    private func promptForText(at point: CGPoint) {
        guard var source else { return }
        let alert = NSAlert()
        alert.messageText = "Add Text"
        alert.informativeText = "Enter the text to place on the canvas."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        textField.placeholderString = "Text"
        alert.accessoryView = textField

        alert.beginSheetModal(for: window ?? NSApp.mainWindow!) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let text = textField.stringValue
            guard !text.isEmpty else { return }

            let stroke = DrawingStroke(
                points: [self?.normalizedPoint(point, pressure: nil) ?? DrawingPoint(x: 0, y: 0)],
                color: source.color,
                width: source.brushWidth,
                tool: .text,
                text: text
            )
            source.strokes.append(stroke)
            self?.delegate?.canvasDidUpdateSource(source)
        }
    }

    // MARK: - Helpers

    private func normalizedPoint(_ point: CGPoint, pressure: Float?) -> DrawingPoint {
        let localPoint = convert(point, from: nil)
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return DrawingPoint(x: 0, y: 0) }
        return DrawingPoint(
            x: Double(localPoint.x / size.width),
            y: Double(localPoint.y / size.height),
            pressure: pressure.map { Double($0) }
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let source else { return }

        let bg = source.backgroundColor
        context.setFillColor(CGColor(red: bg.r, green: bg.g, blue: bg.b, alpha: bg.a))
        context.fill(bounds)

        for stroke in source.strokes {
            drawStroke(stroke, in: context)
        }

        if let currentStroke {
            drawStroke(currentStroke, in: context)
        }
    }

    private func drawStroke(_ stroke: DrawingStroke, in context: CGContext) {
        switch stroke.tool {
        case .pen, .eraser:
            drawFreehandStroke(stroke, in: context)
        case .rectangle:
            drawRectangle(stroke, in: context)
        case .ellipse:
            drawEllipse(stroke, in: context)
        case .line, .arrow:
            drawLineOrArrow(stroke, in: context)
        case .text:
            drawText(stroke, in: context)
        }
    }

    private func drawFreehandStroke(_ stroke: DrawingStroke, in context: CGContext) {
        guard stroke.points.count > 1 else { return }
        let path = CGMutablePath()
        let first = stroke.points[0]
        path.move(to: CGPoint(x: first.x * bounds.width, y: first.y * bounds.height))
        for point in stroke.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * bounds.width, y: point.y * bounds.height))
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch stroke.tool {
        case .pen:
            let c = stroke.color
            context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
            context.setLineWidth(CGFloat(stroke.width))
            context.setBlendMode(.normal)
        case .eraser:
            context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
            context.setLineWidth(max(CGFloat(stroke.width), 8))
            context.setBlendMode(.clear)
        default:
            return
        }

        context.addPath(path)
        context.strokePath()
    }

    private func drawRectangle(_ stroke: DrawingStroke, in context: CGContext) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * bounds.width, y: stroke.points[0].y * bounds.height)
        let end = CGPoint(x: stroke.points[1].x * bounds.width, y: stroke.points[1].y * bounds.height)
        let rect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized
        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineJoin(.round)
        context.setBlendMode(.normal)
        context.stroke(rect)
    }

    private func drawEllipse(_ stroke: DrawingStroke, in context: CGContext) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * bounds.width, y: stroke.points[0].y * bounds.height)
        let end = CGPoint(x: stroke.points[1].x * bounds.width, y: stroke.points[1].y * bounds.height)
        let rect = CGRect(origin: start, size: CGSize(width: end.x - start.x, height: end.y - start.y)).standardized
        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setBlendMode(.normal)
        context.strokeEllipse(in: rect)
    }

    private func drawLineOrArrow(_ stroke: DrawingStroke, in context: CGContext) {
        guard stroke.points.count >= 2 else { return }
        let start = CGPoint(x: stroke.points[0].x * bounds.width, y: stroke.points[0].y * bounds.height)
        let end = CGPoint(x: stroke.points[1].x * bounds.width, y: stroke.points[1].y * bounds.height)

        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let c = stroke.color
        context.setStrokeColor(CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a))
        context.setLineWidth(CGFloat(stroke.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setBlendMode(.normal)
        context.addPath(path)
        context.strokePath()

        if stroke.tool == .arrow {
            drawArrowhead(at: end, from: start, in: context, color: c, width: stroke.width)
        }
    }

    private func drawArrowhead(at tip: CGPoint, from start: CGPoint, in context: CGContext, color: CGColorComponents, width: Double) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let headLength = CGFloat(max(width * 3, 12))
        let headAngle: CGFloat = .pi / 6

        let left = CGPoint(
            x: tip.x - headLength * cos(angle - headAngle),
            y: tip.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: tip.x - headLength * cos(angle + headAngle),
            y: tip.y - headLength * sin(angle + headAngle)
        )

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.move(to: tip)
        path.addLine(to: right)

        context.setStrokeColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: color.a))
        context.setLineWidth(CGFloat(width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }

    private func drawText(_ stroke: DrawingStroke, in context: CGContext) {
        guard stroke.points.count >= 1,
              let text = stroke.text, !text.isEmpty else { return }
        let point = stroke.points[0]
        let location = CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
        let c = stroke.color

        let fontSize = max(CGFloat(stroke.width), 12)
        let font = CTFontCreateWithName("SFPro-Regular" as CFString, fontSize, nil)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font as Any,
            .foregroundColor: NSColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(at: location)
    }
}
