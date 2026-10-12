//
//  MastheadView.swift
//  FreeStage
//
//  QLab-style masthead: GO button, standby display, notes, and cue-type toolbar.
//

import SwiftUI

struct MastheadView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @State private var isAddingCamera = false

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 16) {
                goButton
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    activeCueDisplay
                    notesField
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Divider()

            HStack(spacing: 12) {
                toolbarButton("Camera", systemImage: "video.fill") {
                    isAddingCamera = true
                }
                toolbarButton("Color", systemImage: "paintpalette.fill") {
                    store.addCue(source: .color(.green))
                }
                toolbarButton("Text", systemImage: "textformat") {
                    store.addCue(source: .text(TextSource()))
                }
                toolbarButton("Image", systemImage: "photo") {
                    // Placeholder for file picker cue.
                    store.addCue(source: .color(.black))
                }
                toolbarButton("Group", systemImage: "folder.fill") {
                    store.addGroupCue()
                }
                toolbarButton("Wait", systemImage: "clock") {
                    store.addCue(source: .color(.black))
                }
                toolbarButton("Memo", systemImage: "note.text") {
                    store.addCue(source: .color(.black))
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isAddingCamera) {
            CameraPickerSheet { device in
                let cueID = store.addCue(source: .camera(deviceID: device.uniqueID), name: device.name)
                captureManager?.startCapture(uniqueID: device.uniqueID)
                store.selectCue(id: cueID)
            }
        }
    }

    private var goButton: some View {
        Button {
            store.go()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(goBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(goBorder, lineWidth: 3)
                    )
                Text("GO")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(store.activeCue?.isArmed != true)
    }

    private var activeCueDisplay: some View {
        HStack(spacing: 8) {
            if let cue = store.activeCue {
                if !cue.number.isEmpty {
                    Text(cue.number)
                        .font(.system(.title2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("•")
                    .foregroundStyle(.secondary)
                    .opacity(cue.number.isEmpty ? 0 : 1)
                Text(cue.name)
                    .font(.title2)
                    .lineLimit(1)
            } else {
                Text("No cue standing by")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var notesField: some View {
        TextField(
            "Notes for the standing-by cue…",
            text: Binding(
                get: { store.activeCue?.notes ?? "" },
                set: { newValue in store.updateActiveCue { $0.notes = newValue } }
            )
        )
        .textFieldStyle(.roundedBorder)
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(width: 56, height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(store.activeScene == nil)
    }

    private var goBackground: Color {
        store.activeCue?.isArmed == true ? Color.green.opacity(0.25) : Color.gray.opacity(0.15)
    }

    private var goBorder: Color {
        store.activeCue?.isArmed == true ? .green : .red
    }
}
