//
//  DragDivider.swift
//  FreeStage
//
//  Draggable vertical divider. Uses a SwiftUI DragGesture in the global
//  coordinate space so it keeps tracking reliably even when the surrounding
//  HStack relayouts while dragging. Deltas are computed from the cumulative
//  gesture translation so the divider never drifts from the cursor.
//

import SwiftUI

struct DragDivider: View {
    let onDrag: (CGFloat) -> Void

    /// Tracks the previous gesture translation so each onChanged event reports
    /// a true delta rather than the cumulative offset from the drag start.
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(.clear)
            // The full width given by the parent (14 pt) is tappable; only a
            // 1 pt line is drawn in the centre as the visual divider.
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(
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
