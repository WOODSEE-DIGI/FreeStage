//
//  CameraPickerSheet.swift
//  FreeStage
//
//  Sheet for selecting a camera to add as a layer.
//

import SwiftUI
import AVFoundation

struct CameraPickerSheet: View {
    let onSelect: (CameraDevice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [CameraDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Camera Layer")
                .font(.title2.bold())

            if devices.isEmpty {
                Text("No cameras found.")
                    .foregroundStyle(.secondary)
            } else {
                List(devices) { device in
                    Button {
                        onSelect(device)
                        dismiss()
                    } label: {
                        HStack {
                            Text(device.name)
                            if device.isOBSBOT {
                                Text("OBSBOT")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(4)
                            }
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
        .frame(minWidth: 320, minHeight: 240)
        .task {
            requestAccessAndDiscover()
        }
    }

    private func requestAccessAndDiscover() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print("[FreeStage] Camera access granted: \(granted)")
            guard granted else { return }
            Task { @MainActor in
                self.devices = CameraDevice.discover()
                print("[FreeStage] Discovered \(self.devices.count) cameras: \(self.devices.map(\.name))")
            }
        }
    }
}
