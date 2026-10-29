//
//  ScreenPickerSheet.swift
//  FreeStage
//
//  Sheet for selecting a display to add as a screen-capture cue.
//

import SwiftUI
import ScreenCaptureKit

@available(macOS 12.3, *)
struct ScreenPickerSheet: View {
    let onSelect: (ScreenCaptureDisplay) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displays: [ScreenCaptureDisplay] = []
    @State private var isLoading = true
    @State private var usedFallback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Screen Cue")
                .font(.title2.bold())

            if isLoading {
                ProgressView("Discovering displays…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if displays.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No displays found.")
                        .foregroundStyle(.secondary)
                    Text("Make sure FreeStage has permission to record your screen in System Settings → Privacy & Security → Screen Recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Screen Recording Settings…") {
                        openScreenRecordingSettings()
                    }
                    .font(.caption)
                }
            } else {
                if usedFallback {
                    Text("Screen Recording permission may be required before capture begins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List(displays) { display in
                    Button {
                        onSelect(display)
                        dismiss()
                    } label: {
                        HStack {
                            Text(display.name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 260)
        .task {
            await discover()
        }
    }

    private func discover() async {
        displays = await ScreenCaptureDisplay.discover()
        let screenCaptureKitHasDisplays = await usesScreenCaptureKit()
        usedFallback = !displays.isEmpty && !screenCaptureKitHasDisplays
        isLoading = false
    }

    /// Returns true if SCShareableContent returned displays (permission granted).
    private func usesScreenCaptureKit() async -> Bool {
        do {
            let content = try await SCShareableContent.current
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording") {
            NSWorkspace.shared.open(url)
        }
    }
}
