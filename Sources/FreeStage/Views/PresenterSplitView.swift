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

        // Keep the side panels stable when the window resizes; let the centre
        // monitors absorb the extra width.
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        context.coordinator.hostingControllers = [leftHC, centreHC, rightHC]
        context.coordinator.isSegmentEditorExpanded = isSegmentEditorExpanded
        context.coordinator.hasSetInitialPositions = false

        return splitView
    }

    func updateNSView(_ nsView: NSSplitView, context: Context) {
        let expandedChanged = context.coordinator.isSegmentEditorExpanded != isSegmentEditorExpanded
        context.coordinator.isSegmentEditorExpanded = isSegmentEditorExpanded
        context.coordinator.hostingControllers[0].rootView = leftContent
        context.coordinator.hostingControllers[1].rootView = centreContent
        context.coordinator.hostingControllers[2].rootView = rightContent

        // When the user toggles between the rundown list and the expanded
        // editor, snap the divider to the appropriate default width so the
        // editor tools are not jumbled on first open. Defer until after the
        // current SwiftUI/AppKit layout pass; setting positions while the
        // hosting controllers are still resizing can collapse the side panels.
        if expandedChanged {
            context.coordinator.hasSetInitialPositions = false
            let coordinator = context.coordinator
            Task { @MainActor in
                // One runloop turn of slack so the hosting controllers finish
                // their layout pass before the dividers move.
                await Task.yield()
                if coordinator.applyDefaultPositions(in: nsView, animated: true) {
                    coordinator.hasSetInitialPositions = true
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var hostingControllers: [NSHostingController<AnyView>] = []
        weak var splitView: NSSplitView?
        var isSegmentEditorExpanded = false
        var hasSetInitialPositions = false

        /// Guards against re-entrant position updates. `NSSplitView.setPosition(_:ofDividerAt:)`
        /// posts `splitViewDidResizeSubviews` synchronously, so applying the
        /// defaults from inside that notification re-enters this method before
        /// `hasSetInitialPositions` can be set, recursing until the stack
        /// overflows.
        private var isApplyingPositions = false

        private let leftExpandedMin: CGFloat = 580
        private let leftCollapsedMin: CGFloat = 220
        private let rightMin: CGFloat = 200
        private let centreMin: CGFloat = 240

        // MARK: - Divider position constraints

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let leftMin = isSegmentEditorExpanded ? leftExpandedMin : leftCollapsedMin
            // Divider 0: left panel minimum. Divider 1: left pane, the first
            // divider and the centre pane minimum.
            return dividerIndex == 0
                ? leftMin
                : leftMin + splitView.dividerThickness + centreMin
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

        // MARK: - Default divider positions

        /// Snap divider 0 and divider 1 to the widths that match the current
        /// editor/list mode. Called on first layout and whenever expand/collapse
        /// toggles, so the tools panel opens wide enough and the monitors stay
        /// usable. Returns false when the split view is still too small to
        /// honour the defaults, so the caller can retry on the next layout pass.
        @MainActor
        @discardableResult
        func applyDefaultPositions(in splitView: NSSplitView, animated: Bool) -> Bool {
            guard !isApplyingPositions, splitView.arrangedSubviews.count == 3 else { return false }
            let total = splitView.bounds.width
            let dividerThickness = splitView.dividerThickness
            let leftDefault: CGFloat = isSegmentEditorExpanded ? 640 : 240
            let rightDefault: CGFloat = 240

            // Never set positions that would push a divider off-screen. On the
            // very first layout pass the split view can still be 1 pt wide;
            // applying the defaults then collapses the side panels permanently.
            let minimumTotal = leftDefault + rightDefault + centreMin + dividerThickness * 2
            guard total >= minimumTotal else { return false }

            let leftPosition = min(leftDefault, total - rightDefault - centreMin - dividerThickness * 2)
            let rightPosition = max(
                leftPosition + centreMin + dividerThickness,
                total - rightDefault - dividerThickness
            )

            // Skip redundant updates: every `setPosition` call triggers a
            // synchronous did-resize notification and another layout pass.
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
            // AppKit delivers split-view notifications on the main thread.
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
