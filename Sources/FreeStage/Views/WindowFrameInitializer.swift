//
//  WindowFrameInitializer.swift
//  FreeStage
//
//  Ensures the main window opens at least as large as the workspace minimum.
//

import SwiftUI
import AppKit

struct WindowFrameInitializer: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.enforceMinSize(for: view, minSize: minSize)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enforceMinSize(for: nsView, minSize: minSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private var task: Task<Void, Never>?

        func enforceMinSize(for view: NSView, minSize: NSSize) {
            task?.cancel()
            task = Task { [weak self] in
                await self?.attemptResize(view: view, minSize: minSize, retryCount: 0)
            }
        }

        private func attemptResize(view: NSView, minSize: NSSize, retryCount: Int) async {
            guard !Task.isCancelled else { return }

            guard let window = view.window else {
                if retryCount < 10 {
                    try? await Task.sleep(nanoseconds: UInt64(0.05 * Double(retryCount + 1) * 1_000_000_000))
                    await attemptResize(view: view, minSize: minSize, retryCount: retryCount + 1)
                }
                return
            }

            var frame = window.frame
            let needsResize = frame.size.width < minSize.width || frame.size.height < minSize.height

            if let screen = window.screen {
                let maxFrame = screen.visibleFrame
                let availableSize = maxFrame.size

                // Ensure the requested minimum fits on the current screen. If the
                // screen is too small, clamp to the visible area to avoid negative
                // view geometry warnings from AppKit.
                let clampedMinSize = NSSize(
                    width: min(minSize.width, availableSize.width),
                    height: min(minSize.height, availableSize.height)
                )
                window.minSize = clampedMinSize

                guard needsResize else { return }

                frame.size.width = max(frame.size.width, clampedMinSize.width)
                frame.size.height = max(frame.size.height, clampedMinSize.height)
                frame.size.width = min(frame.size.width, availableSize.width)
                frame.size.height = min(frame.size.height, availableSize.height)

                frame.origin.x = max(maxFrame.origin.x, min(frame.origin.x, maxFrame.maxX - frame.size.width))
                frame.origin.y = max(maxFrame.origin.y, min(frame.origin.y, maxFrame.maxY - frame.size.height))
            } else {
                window.minSize = minSize
                guard needsResize else { return }
                frame.size.width = max(frame.size.width, minSize.width)
                frame.size.height = max(frame.size.height, minSize.height)
            }

            window.setFrame(frame, display: true, animate: false)
        }
    }
}
