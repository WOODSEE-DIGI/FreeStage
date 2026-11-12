//
//  DragDivider.swift
//  FreeStage
//
//  Draggable vertical divider rendered entirely in SwiftUI. Uses a DragGesture
//  in the global coordinate space so it tracks correctly even when the
//  surrounding layout relayouts during the drag.
//

import SwiftUI

struct DragDivider: View {
    let onDrag: (CGFloat) -> Void

    /// Cumulative translation at the previous onChanged callback, used to
    /// report true deltas instead of absolute offsets.
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            // Nearly-transparent fill so the full 14 pt strip is hit-testable,
            // not just the 1 pt visible line.
            .fill(Color.secondary.opacity(0.001))
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let current = value.translation.width
                        let delta = current - lastTranslation
                        lastTranslation = current
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                    }
            )
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}
