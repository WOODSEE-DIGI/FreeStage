//
//  LayerOverlayView.swift
//  FreeStage
//
//  On-canvas overlay for the selected layer: bounding box, move, and resize.
//

import SwiftUI

struct LayerOverlayView: View {
    @Environment(ShowStore.self) private var store
    @State private var lastMoveTranslation: CGSize = .zero
    @State private var lastResizeTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            if let layer = store.selectedLayer {
                let frame = frame(for: layer, in: geometry.size)
                ZStack {
                    boundingBox(frame: frame, layer: layer, size: geometry.size)
                    resizeHandle(frame: frame, layer: layer, size: geometry.size)
                }
            }
        }
    }

    // MARK: - Frame math

    private func frame(for layer: Layer, in size: CGSize) -> CGRect {
        let width = size.width
        let height = size.height
        let origin = CGPoint(
            x: (layer.transform.x - layer.transform.scaleX / 2) * width,
            y: (layer.transform.y - layer.transform.scaleY / 2) * height
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: layer.transform.scaleX * width,
            height: layer.transform.scaleY * height
        )
    }

    // MARK: - Bounding box

    private func boundingBox(frame: CGRect, layer: Layer, size: CGSize) -> some View {
        Rectangle()
            .strokeBorder(Color.yellow, lineWidth: 2)
            .frame(width: max(0, frame.width), height: max(0, frame.height))
            .position(x: frame.midX, y: frame.midY)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastMoveTranslation.width,
                            height: value.translation.height - lastMoveTranslation.height
                        )
                        move(layer: layer, by: delta, in: size)
                        lastMoveTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastMoveTranslation = .zero
                    }
            )
            .onTapGesture(count: 2) {
                // Double-tap resets to fill the canvas.
                store.updateSelectedLayer(
                    ItemTransform(x: 0.5, y: 0.5, scaleX: 1.0, scaleY: 1.0, rotation: 0, crop: .zero)
                )
            }
    }

    private func move(layer: Layer, by translation: CGSize, in size: CGSize) {
        let dx = Double(translation.width / size.width)
        let dy = Double(translation.height / size.height)
        var transform = layer.transform
        transform.x = (layer.transform.x + dx).clamped(to: 0...1)
        transform.y = (layer.transform.y + dy).clamped(to: 0...1)
        store.updateSelectedLayer(transform)
    }

    // MARK: - Resize handle

    private func resizeHandle(frame: CGRect, layer: Layer, size: CGSize) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 14, height: 14)
            .position(x: frame.maxX, y: frame.maxY)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - lastResizeTranslation.width,
                            height: value.translation.height - lastResizeTranslation.height
                        )
                        resize(layer: layer, from: frame, by: delta, in: size)
                        lastResizeTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastResizeTranslation = .zero
                    }
            )
    }

    private func resize(layer: Layer, from frame: CGRect, by translation: CGSize, in size: CGSize) {
        let newMaxX = frame.maxX + translation.width
        let newMaxY = frame.maxY + translation.height
        let newWidth = max(20, newMaxX - frame.minX)
        let newHeight = max(20, newMaxY - frame.minY)

        let scaleX = Double(newWidth / size.width)
        let scaleY = Double(newHeight / size.height)

        // Keep the opposite (top-left) corner anchored.
        let newCenterX = frame.minX / size.width + scaleX / 2
        let newCenterY = frame.minY / size.height + scaleY / 2

        var transform = layer.transform
        transform.scaleX = scaleX.clamped(to: 0.01...2.0)
        transform.scaleY = scaleY.clamped(to: 0.01...2.0)
        transform.x = newCenterX.clamped(to: 0...1)
        transform.y = newCenterY.clamped(to: 0...1)
        store.updateSelectedLayer(transform)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
