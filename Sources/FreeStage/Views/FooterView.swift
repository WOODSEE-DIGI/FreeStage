//
//  FooterView.swift
//  FreeStage
//
//  QLab-style footer: Edit/Show mode, workspace toggles, cue count, and panic.
//

import SwiftUI

struct FooterView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.recordingService) private var recordingService
    @Environment(\.virtualCameraOutputService) private var virtualCamera

    var body: some View {
        HStack(spacing: 16) {
            modePicker

            HStack(spacing: 8) {
                Button {
                    withAnimation { store.inspectorVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(store.inspectorVisible ? theme.accent : theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("Toggle Cue Settings")

                Button {
                    withAnimation { store.mastheadVisible.toggle() }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .foregroundStyle(store.mastheadVisible ? theme.accent : theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("Toggle Masthead")

                Button {
                    openWindow(id: "gostream-panel")
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.borderless)
                .help("GoStream Panel")
            }

            Spacer()

            Button(role: .destructive) {
                panicAndStopOutputs()
            } label: {
                Label("Panic", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)

            Spacer()

            Text("\(store.show.cues.count) cue(s)")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            Spacer()

                Button {
                    withAnimation { store.sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(store.sidebarVisible ? theme.accent : theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .help("Toggle Layer Tools")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.panelBackground)
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            Text("Mode")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: Binding(
                get: { store.isEditMode },
                set: { newValue in
                    store.isEditMode = newValue
                    if !newValue {
                        enterShowMode()
                    }
                }
            )) {
                Text("Edit").tag(true)
                Text("Show").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .labelsHidden()
        }
    }

    private func enterShowMode() {
        if appSettings.startVirtualCameraOnShowMode,
           let virtualCamera, !virtualCamera.isExtensionActive {
            virtualCamera.activate()
        }
    }

    private func panicAndStopOutputs() {
        store.panic()
        if let recordingService, recordingService.isRecording {
            Task {
                do {
                    _ = try await recordingService.stopRecording()
                } catch {
                    print("[FreeStage] Failed to stop recording on panic: \(error)")
                }
            }
        }
    }
}
