//
//  FacePuppetAnchorOverlayView.swift
//  FreeStage
//
//  Draggable anchor handles for face-puppet sources. Each handle follows the
//  tracked MediaPipe landmark plus the per-source offset, and dragging updates
//  that offset in the layer's source.
//

import SwiftUI

struct FacePuppetAnchorOverlayView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.facePuppetTrackingService) private var trackingService

    private let anchorNames = FacePuppetAnchorName.allCases
    private let handleSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            if let layer = store.selectedLayer,
               layer.source.facePuppetAnchorMap != nil || isPuppetSource(layer.source) {
                let frame = frame(for: layer, in: geometry.size)
                ZStack {
                    ForEach(anchorNames) { name in
                        anchorHandle(name: name, layer: layer, frame: frame)
                    }
                }
            }
        }
    }

    private func isPuppetSource(_ source: Source) -> Bool {
        switch source {
        case .facePuppet, .facePuppetAnchored, .facePuppetMesh:
            return true
        default:
            return false
        }
    }

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

    private func anchorHandle(name: FacePuppetAnchorName, layer: Layer, frame: CGRect) -> some View {
        let position = anchorPosition(
            index: name.landmarkIndex,
            frame: frame,
            offset: layer.source.facePuppetAnchorMap?.offsets[name.landmarkIndex]
        )
        return Circle()
            .fill(Color.green)
            .frame(width: handleSize, height: handleSize)
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        updateOffset(
                            layer: layer,
                            index: name.landmarkIndex,
                            frame: frame,
                            location: value.location
                        )
                    }
            )
            .overlay(
                Text(name.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .offset(y: -handleSize)
            )
    }

    private func anchorPosition(index: Int, frame: CGRect, offset: CGPoint?) -> CGPoint {
        guard let landmark = trackingService?.latestFrame?.landmarks[safe: index] else {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        let offsetX = CGFloat(offset?.x ?? 0)
        let offsetY = CGFloat(offset?.y ?? 0)
        return CGPoint(
            x: frame.minX + (CGFloat(landmark.x) + offsetX) * frame.width,
            y: frame.minY + (CGFloat(landmark.y) + offsetY) * frame.height
        )
    }

    private func updateOffset(layer: Layer, index: Int, frame: CGRect, location: CGPoint) {
        guard let landmark = trackingService?.latestFrame?.landmarks[safe: index] else { return }
        let normalizedX = (location.x - frame.minX) / frame.width
        let normalizedY = (location.y - frame.minY) / frame.height
        let offsetX = Double(normalizedX) - Double(landmark.x)
        let offsetY = Double(normalizedY) - Double(landmark.y)
        let newSource = layer.source.updatingAnchorOffset(
            index: index,
            offset: CGPoint(x: offsetX, y: offsetY)
        )
        store.setLayerSource(id: layer.id, source: newSource, name: layer.name)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
