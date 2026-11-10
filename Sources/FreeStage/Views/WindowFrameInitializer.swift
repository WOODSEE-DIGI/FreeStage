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

            window.minSize = minSize

            var frame = window.frame
            let needsResize = frame.size.width < minSize.width || frame.size.height < minSize.height
            guard needsResize else { return }

            frame.size.width = max(frame.size.width, minSize.width)
            frame.size.height = max(frame.size.height, minSize.height)

            if let screen = window.screen {
                let maxFrame = screen.visibleFrame
                if frame.maxX > maxFrame.maxX {
                    frame.origin.x = maxFrame.maxX - frame.size.width
                }
                if frame.maxY > maxFrame.maxY {
                    frame.origin.y = maxFrame.maxY - frame.size.height
                }
                if frame.origin.y < maxFrame.origin.y {
                    frame.origin.y = maxFrame.origin.y
                }
            }

            window.setFrame(frame, display: true, animate: false)
        }
    }
}
