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
    @State private var permissionGranted = ScreenRecordingPermission.isGranted

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
                if !permissionGranted || usedFallback {
                    permissionWarning
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
        .frame(minWidth: 380, minHeight: 280)
        .task {
            await discover()
        }
    }

    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Screen Recording permission is not active", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.bold())
                .foregroundStyle(.orange)
            Text("Cueing a display now will create the layer, but it will stay black until FreeStage is granted Screen Recording. If FreeStage already looks enabled in System Settings, remove it with the − button, add it back, then relaunch FreeStage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Grant Permission…") {
                    permissionGranted = ScreenRecordingPermission.request()
                    usedFallback = usedFallback || !permissionGranted
                }
                Button("Open Settings…") {
                    ScreenRecordingPermission.openSettings()
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func discover() async {
        permissionGranted = ScreenRecordingPermission.isGranted
        displays = await ScreenCaptureDisplay.discover()
        let screenCaptureKitHasDisplays = await usesScreenCaptureKit()
        usedFallback = !displays.isEmpty && !screenCaptureKitHasDisplays
        isLoading = false
    }

    /// Returns true when ScreenCaptureKit itself could enumerate displays,
    /// which only happens with an active Screen Recording grant.
    private func usesScreenCaptureKit() async -> Bool {
        do {
            let content = try await SCShareableContent.current
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    private func openScreenRecordingSettings() {
        ScreenRecordingPermission.openSettings()
    }
}
