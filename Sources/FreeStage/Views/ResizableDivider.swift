//
//  ResizableDivider.swift
//  FreeStage
//
//  Draggable vertical divider for resizable column layouts. Dragging updates
//  the bound width while clamping to the provided range.
//

import SwiftUI

struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = width
                        }
                        let delta = value.location.x - value.startLocation.x
                        width = min(max(dragStartWidth! + delta, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                    }
            )
            .overlay(
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
            )
            .help("Drag to resize")
    }
}
