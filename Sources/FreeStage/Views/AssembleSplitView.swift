//
//  AssembleSplitView.swift
//  FreeStage
//
//  Native NSSplitView wrapper for the Assemble workspace. Gives the user
//  draggable dividers between the left (rundown + cue editor), centre
//  (canvas + layers), and right (tools/setup) columns while keeping sensible
//  minimum widths so the cue editor and tools remain usable.
//

import SwiftUI
import AppKit

struct AssembleSplitView: NSViewRepresentable {
    let leftContent: AnyView
    let centreContent: AnyView
    let rightContent: AnyView

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = context.coordinator
        context.coordinator.splitView = splitView

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

        // Side panels hold their width when the window resizes; centre canvas
        // absorbs any extra space.
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        context.coordinator.hostingControllers = [leftHC, centreHC, rightHC]
        context.coordinator.hasSetInitialPositions = false

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
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
        var hasSetInitialPositions = false

        private var isApplyingPositions = false

        private let leftMin: CGFloat = 360
        private let leftDefault: CGFloat = 420
        private let rightMin: CGFloat = 280
        private let rightDefault: CGFloat = 320
        private let centreMin: CGFloat = 240

        // MARK: - Divider position constraints

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            dividerIndex == 0
                ? leftMin
                : leftMin + splitView.dividerThickness + centreMin
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let total = splitView.bounds.width
            return dividerIndex == 0 ? total - centreMin - rightMin : total - rightMin
        }

        // MARK: - Default divider positions

        @MainActor
        @discardableResult
        func applyDefaultPositions(in splitView: NSSplitView, animated: Bool) -> Bool {
            guard !isApplyingPositions, splitView.arrangedSubviews.count == 3 else { return false }
            let total = splitView.bounds.width
            let dividerThickness = splitView.dividerThickness
            let minimumTotal = leftDefault + rightDefault + centreMin + dividerThickness * 2
            guard total >= minimumTotal else { return false }

            let leftPosition = min(leftDefault, total - rightDefault - centreMin - dividerThickness * 2)
            let rightPosition = max(
                leftPosition + centreMin + dividerThickness,
                total - rightDefault - dividerThickness
            )

            let leftIsSettled = abs(splitView.arrangedSubviews[0].frame.width - leftPosition) < 0.5
            let rightIsSettled = abs(splitView.arrangedSubviews[2].frame.width - rightDefault) < 0.5
            guard !(leftIsSettled && rightIsSettled) else { return true }

            isApplyingPositions = true
            defer { isApplyingPositions = false }

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    splitView.animator().setPosition(leftPosition, ofDividerAt: 0)
                    splitView.animator().setPosition(rightPosition, ofDividerAt: 1)
                }
            } else {
                splitView.setPosition(leftPosition, ofDividerAt: 0)
                splitView.setPosition(rightPosition, ofDividerAt: 1)
            }
            return true
        }

        // MARK: - NSSplitViewDelegate

        func splitViewDidResizeSubviews(_ notification: Notification) {
            MainActor.assumeIsolated {
                applyInitialPositionsIfNeeded(for: notification)
            }
        }

        @MainActor
        private func applyInitialPositionsIfNeeded(for notification: Notification) {
            guard !isApplyingPositions,
                  !hasSetInitialPositions,
                  let splitView = notification.object as? NSSplitView,
                  splitView === self.splitView,
                  splitView.arrangedSubviews.count == 3 else { return }

            if applyDefaultPositions(in: splitView, animated: false) {
                hasSetInitialPositions = true
            }
        }
    }
}
