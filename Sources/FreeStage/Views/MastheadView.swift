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
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @Environment(\.recordingService) private var recordingService
    @Environment(\.virtualCameraOutputService) private var virtualCamera
    @Environment(\.appSettings) private var appSettings
    @State private var isAddingCamera = false
    @State private var isAddingScreen = false
    @State private var isAddingSlideshow = false

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        activeCueDisplay
                        if isRecording {
                            recordingIndicator
                        }
                    }
                    notesField
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRecording {
                    stopShowButton
                        .frame(width: 80, height: 80)
                }

                goButton
                    .frame(width: 80, height: 80)
            }
            .padding()

            Divider()

            HStack {
                addCueMenu
                    .padding(.leading, 4)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isAddingCamera) {
            CameraPickerSheet { device in
                let cueID = store.addCue(source: .camera(deviceID: device.uniqueID), name: device.name)
                store.selectCue(id: cueID)
                captureManager?.startCapture(uniqueID: device.uniqueID)
            }
        }
        .sheet(isPresented: $isAddingScreen) {
            if let screenCaptureManager {
                ScreenPickerSheet { display in
                    let cueID = store.addCue(source: .screen(displayID: display.displayID), name: "Screen \(display.displayID)")
                    store.selectCue(id: cueID)
                    screenCaptureManager.startCapture(displayID: display.displayID)
                }
            }
        }
        .sheet(isPresented: $isAddingSlideshow) {
            SlideshowPickerSheet { slideshow in
                let cueID = store.addCue(source: .slideshow(slideshow), name: "Slideshow")
                store.selectCue(id: cueID)
            }
        }
    }

    private var addCueMenu: some View {
        Menu {
            Button("Camera…") { isAddingCamera = true }
            Button("Screen…") { isAddingScreen = true }
            Button("Color") { addCue(source: .color(.green), name: "Color") }
            Button("Text") { addCue(source: .text(TextSource()), name: "Text") }
            Button("Image") { addCue(source: .color(.black), name: "Image") }
            Button("Slideshow…") { isAddingSlideshow = true }
            Button("Draw") { addDrawingCue() }
            Divider()
            Button("Border") { addCue(source: .border(BorderSource()), name: "Border") }
            Button("Lower Third") { addCue(source: .lowerThird(LowerThirdSource()), name: "Lower Third") }
            Button("Chapter Marker") { addCue(source: .chapterMarker(ChapterMarkerSource()), name: "Chapter Marker") }
            Button("Next Section") { addCue(source: .nextSection(NextSectionSource()), name: "Next Section") }
            Button("Social Bug") { addCue(source: .socialBug(SocialBugSource()), name: "Social Bug") }
            Button("Logo Bug") { addCue(source: .logoBug(LogoBugSource()), name: "Logo Bug") }
            Button("Countdown") { addCue(source: .countdownTimer(CountdownTimerSource()), name: "Countdown") }
            Divider()
            Button("Group") {
                let cueID = store.addGroupCue()
                store.selectCue(id: cueID)
            }
            Button("Wait") { addCue(source: .color(.black), name: "Wait") }
            Button("Memo") { addCue(source: .color(.black), name: "Memo") }
        } label: {
            Label("Add Cue", systemImage: "plus")
        }
        .menuStyle(.borderedButton)
    }

    private var goButton: some View {
        Button {
            performGo()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(goBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(goBorder, lineWidth: 3)
                    )
                VStack(spacing: 2) {
                    Text("GO")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    if isRecordingInShowMode {
                        Text("REC")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(store.activeCue?.isArmed != true)
        .contextMenu {
            if let activeCue = store.activeCue {
                Button("Fire Cue Directly") {
                    store.triggerCue(id: activeCue.id)
                }
            }
        }
    }

    private func performGo() {
        if !store.isEditMode {
            // Show mode: arm outputs before the cue fires.
            if appSettings?.startVirtualCameraOnShowMode == true,
               let virtualCamera, !virtualCamera.isExtensionActive {
                virtualCamera.activate()
            }
            if appSettings?.recordOnGo == true,
               let recordingService, !recordingService.isRecording {
                do {
                    let url = try recordingService.startRecording()
                    print("[FreeStage] Show mode recording started: \(url.path)")
                } catch {
                    print("[FreeStage] Failed to start show recording: \(error)")
                }
            }
        }

        let result = store.go()

        if !store.isEditMode,
           case .atEnd = result,
           appSettings?.autoStopRecordingOnShowEnd == true,
           let recordingService, recordingService.isRecording {
            Task {
                do {
                    if let url = try await recordingService.stopRecording() {
                        NSSound.beep()
                        print("[FreeStage] Show ended; recording saved: \(url.path)")
                    }
                } catch {
                    print("[FreeStage] Failed to stop show recording: \(error)")
                }
            }
        }
    }

    private var isRecordingInShowMode: Bool {
        !store.isEditMode && recordingService?.isRecording == true
    }

    private var isRecording: Bool {
        recordingService?.isRecording == true
    }

    private var stopShowButton: some View {
        Button {
            stopShow()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red, lineWidth: 3)
                    )
                VStack(spacing: 2) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("STOP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Stop recording and end the show")
    }

    private var recordingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("REC")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.15))
        .clipShape(Capsule())
    }

    private func stopShow() {
        store.stopShow()
        if let recordingService, recordingService.isRecording {
            Task {
                do {
                    if let url = try await recordingService.stopRecording() {
                        NSSound.beep()
                        print("[FreeStage] Show stopped; recording saved: \(url.path)")
                    }
                } catch {
                    print("[FreeStage] Failed to stop recording: \(error)")
                }
            }
        }
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

    private var goBackground: Color {
        if store.isEditMode {
            return store.activeCue?.isArmed == true ? Color.green.opacity(0.25) : Color.gray.opacity(0.15)
        }
        return recordingService?.isRecording == true ? Color.red.opacity(0.35) : Color.orange.opacity(0.25)
    }

    private var goBorder: Color {
        if store.isEditMode {
            return store.activeCue?.isArmed == true ? .green : .red
        }
        return recordingService?.isRecording == true ? .red : .orange
    }

    private func addCue(source: Source, name: String) {
        let cueID = store.addCue(source: source, name: name)
        store.selectCue(id: cueID)
    }

    private func addDrawingCue() {
        let cueID = store.addCue(source: .drawing(DrawingSource()), name: "Drawing")
        store.selectCue(id: cueID)
    }
}
