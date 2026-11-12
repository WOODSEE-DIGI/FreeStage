//
//  PresenterSplitView.swift
//  FreeStage
//
//  Native NSSplitView wrapper for the presenter workspace. Uses AppKit's
//  built-in split view and delegate methods for min/max constraints and
//  initial divider positions, so both dividers work reliably regardless of
//  the SwiftUI/Metal view hierarchy.
//

import SwiftUI
import AppKit

struct PresenterSplitView: NSViewRepresentable {
    let isSegmentEditorExpanded: Bool
    let leftContent: AnyView
    let centreContent: AnyView
    let rightContent: AnyView

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = context.coordinator

        let leftHC = NSHostingController(rootView: leftContent)
        let centreHC = NSHostingController(rootView: centreContent)
        let rightHC = NSHostingController(rootView: rightContent)

        for hc in [leftHC, centreHC, rightHC] {
            hc.view.translatesAutoresizingMaskIntoConstraints = true
            hc.view.autoresizingMask = [.width, .height]
        }

        splitView.addArrangedSubview(leftHC.view)
        splitView.addArrangedSubview(centreHC.view)
        splitView.addArrangedSubview(rightHC.view)

        context.coordinator.hostingControllers = [leftHC, centreHC, rightHC]
        context.coordinator.splitView = splitView
        context.coordinator.isSegmentEditorExpanded = isSegmentEditorExpanded
        context.coordinator.hasSetInitialPositions = false

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        context.coordinator.isSegmentEditorExpanded = isSegmentEditorExpanded
        context.coordinator.hostingControllers[0].rootView = leftContent
        context.coordinator.hostingControllers[1].rootView = centreContent
        context.coordinator.hostingControllers[2].rootView = rightContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var hostingControllers: [NSHostingController<AnyView>] = []
        weak var splitView: NSSplitView?
        var isSegmentEditorExpanded = false
        var hasSetInitialPositions = false

        private let leftExpandedMin: CGFloat = 400
        private let leftCollapsedMin: CGFloat = 180
        private let rightMin: CGFloat = 200
        private let centreMin: CGFloat = 240

        // MARK: - Divider position constraints

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let leftMin = isSegmentEditorExpanded ? leftExpandedMin : leftCollapsedMin
            // Divider 0: left panel minimum. Divider 1: left + centre minimum.
            return dividerIndex == 0 ? leftMin : leftMin + centreMin
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let total = splitView.bounds.width
            // Divider 0: centre + right minimum. Divider 1: right minimum.
            return dividerIndex == 0 ? total - centreMin - rightMin : total - rightMin
        }

        // MARK: - Initial layout

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count == 3,
                  !hasSetInitialPositions else { return }

            let total = splitView.bounds.width
            guard total > 0 else { return }

            hasSetInitialPositions = true
            let leftDefault: CGFloat = isSegmentEditorExpanded ? 460 : 220
            let rightDefault: CGFloat = 240
            let dividerThickness = splitView.dividerThickness
            splitView.setPosition(leftDefault, ofDividerAt: 0)
            splitView.setPosition(total - rightDefault - dividerThickness, ofDividerAt: 1)
        }
    }
}
