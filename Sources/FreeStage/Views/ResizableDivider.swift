//
//  ResizableDivider.swift
//  FreeStage
//
//  Draggable vertical divider for resizable column layouts. Dragging updates
//  the bound width while clamping to the provided range. Gestures are read in
//  the workspace column coordinate space so the divider keeps tracking even as
//  its own frame moves.
//

import SwiftUI

struct ResizableDivider: View {
    static let coordinateSpaceName = "workspaceColumns"

    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named(Self.coordinateSpaceName))
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let delta = value.translation.width
                        width = min(max(dragStartWidth! + delta, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 2)
            )
            .help("Drag to resize")
    }
}
