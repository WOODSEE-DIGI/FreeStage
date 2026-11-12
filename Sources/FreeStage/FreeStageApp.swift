//
//  FreeStageApp.swift
//  FreeStage
//
//  App entry point for the live production switcher.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OSLog

private let appLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "FreeStageApp")

extension UTType {
    /// FreeStage show document type (registered in Info.plist).
    static var freeStageShow: UTType { UTType(exportedAs: "com.woodseedigi.freestage.show") }
}

@main
struct FreeStageApp: App {
    @State private var store: ShowStore
    @State private var captureManager: CameraCaptureManager
    @State private var screenCaptureManager: ScreenCaptureManager
    @State private var audioMixer: AudioMixer
    @State private var recordingService: RecordingService
    @State private var cameraControlService: CameraControlService
    @State private var goStreamController: GoStreamController
    @State private var appSettings: AppSettings
    @State private var cueTriggerServer: CueTriggerServer
    @State private var oscCueServer: OSCCueServer
    @State private var streamingService: StreamingService
    @State private var facePuppetTrackingService: FacePuppetTrackingService
    @StateObject private var virtualCamera: VirtualCameraOutputService
    @State private var themeStore: ThemeStore
    @State private var showProjectManager = true
    @State private var showLibrarySetup: Bool
    @State private var showScreenCapturePermissionAlert = false

    init() {
        // Clear any autosaved window frames from previous launches so the
        // default size and minimum size are honored on open.
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if key.contains("NSWindow Frame FreeStage") || key.contains("com.apple.swiftui.window") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let appSettings = AppSettings()
        let themeStore = ThemeStore(settings: appSettings)
        let audioMixer = AudioMixer()
        let recordingService = RecordingService()
        let cameraControlService = CameraControlService()
        let captureManager = CameraCaptureManager()
        let screenCaptureManager = ScreenCaptureManager()
        let store = ShowStore()
        let streamingService = StreamingService()
        let goStreamController = GoStreamController()
        let facePuppetTrackingService = FacePuppetTrackingService()
        let virtualCamera = VirtualCameraOutputService()

        captureManager.cameraControlService = cameraControlService
        store.cameraControlService = cameraControlService
        store.appSettings = appSettings
        screenCaptureManager.audioMixer = audioMixer
        screenCaptureManager.excludeDesktopIcons = appSettings.hideDesktopIconsDuringCapture
        recordingService.setAudioMixer(audioMixer)
        recordingService.configure(with: appSettings)
        streamingService.setAudioMixer(audioMixer)

        let cueTriggerServer = CueTriggerServer { [weak _store = store] in
            guard let store = _store else { return [] }
            return store.show.cues.map { CueSnapshot(cue: $0, sceneName: store.show.scene(withID: $0.sceneID)?.name ?? "") }
        }
        let oscCueServer = OSCCueServer()

        _store = State(wrappedValue: store)
        _captureManager = State(wrappedValue: captureManager)
        _screenCaptureManager = State(wrappedValue: screenCaptureManager)
        _audioMixer = State(wrappedValue: audioMixer)
        _recordingService = State(wrappedValue: recordingService)
        _cameraControlService = State(wrappedValue: cameraControlService)
        _goStreamController = State(wrappedValue: goStreamController)
        _appSettings = State(wrappedValue: appSettings)
        _cueTriggerServer = State(wrappedValue: cueTriggerServer)
        _oscCueServer = State(wrappedValue: oscCueServer)
        _streamingService = State(wrappedValue: streamingService)
        _facePuppetTrackingService = State(wrappedValue: facePuppetTrackingService)
        _virtualCamera = StateObject(wrappedValue: virtualCamera)
        _themeStore = State(wrappedValue: themeStore)
        _showLibrarySetup = State(initialValue: !appSettings.hasCompletedLibrarySetup)
    }

    var body: some SwiftUI.Scene {
        WindowGroup("FreeStage") {
            Group {
                if showProjectManager {
                    ProjectManagerView(isPresented: $showProjectManager)
                } else if store.show.kind == .presenter {
                    PresenterWorkspaceView()
                } else {
                    ContentView()
                }
            }
            .environment(store)
            .environment(themeStore)
            .environment(\.cameraCaptureManager, captureManager)
            .environment(\.screenCaptureManager, screenCaptureManager)
            .environment(\.audioMixer, audioMixer)
            .environment(\.recordingService, recordingService)
            .environment(\.cameraControlService, cameraControlService)
            .environment(\.goStreamController, goStreamController)
            .environment(\.virtualCameraOutputService, virtualCamera)
            .environment(appSettings)
            .environment(\.cueTriggerServer, cueTriggerServer)
            .environment(\.oscCueServer, oscCueServer)
            .environment(\.streamingService, streamingService)
            .environment(\.facePuppetTrackingService, facePuppetTrackingService)
            .alert("Screen Recording Permission Required", isPresented: $showScreenCapturePermissionAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(ScreenRecordingPermission.guidance)
                }
                .onReceive(NotificationCenter.default.publisher(for: .screenCapturePermissionDenied)) { _ in
                    showScreenCapturePermissionAlert = true
                }
                .task {
                    syncCueTriggerServer()
                    syncOSCCueServer()
                    themeStore.applyInitialAppearance()
                    // Repair the library template if folders were moved or deleted.
                    if appSettings.hasCompletedLibrarySetup {
                        appSettings.prepareLibrary()
                    }
                }
                .onChange(of: appSettings.cueTriggerServerEnabled) {
                    syncCueTriggerServer()
                }
                .onChange(of: appSettings.cueTriggerServerPort) {
                    syncCueTriggerServer()
                }
                .onChange(of: appSettings.cueTriggerServerLocalhostOnly) {
                    syncCueTriggerServer()
                }
                .onChange(of: appSettings.oscCueServerEnabled) {
                    syncOSCCueServer()
                }
                .onChange(of: appSettings.oscCueServerPort) {
                    syncOSCCueServer()
                }
                .onChange(of: appSettings.hideDesktopIconsDuringCapture) {
                    screenCaptureManager.setExcludeDesktopIcons(appSettings.hideDesktopIconsDuringCapture)
                }
                .sheet(isPresented: $showLibrarySetup) {
                    LibrarySetupView(initialRoot: appSettings.libraryRoot)
                        .environment(appSettings)
                        .environment(themeStore)
                }
        }
        .defaultSize(width: 1600, height: 1024)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Show") {
                    store.show = .default(style: appSettings.defaultShowStyle)
                    store.resetWorkspace()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open Show...") {
                    openShow()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save Show...") {
                    saveShow()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandMenu("Output") {
                Button(virtualCamera.isExtensionActive ? "Deactivate Virtual Camera" : "Activate Virtual Camera") {
                    if virtualCamera.isExtensionActive {
                        virtualCamera.deactivate()
                    } else {
                        virtualCamera.activate()
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button(virtualCamera.statusMessage) {}
                    .disabled(true)

                Divider()

                Button(recordingService.isRecording ? "Stop Recording" : "Start Recording") {
                    toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                if let url = recordingService.lastRecordingURL {
                    Button("Reveal Last Recording") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }

            CommandGroup(replacing: .help) {
                Button("FreeStage Help") {
                    openHelp()
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("GoStream Panel", id: "gostream-panel") {
            GoStreamPanelView()
                .environment(\.goStreamController, goStreamController)
        }
        // Surface frame is 1180×472; + margins/header for chrome.
        .defaultSize(width: 1220, height: 540)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(appSettings)
                .environment(store)
                .environment(themeStore)
        }
    }

    // MARK: - Show file I/O

    private func saveShow() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.freeStageShow]
        panel.nameFieldStringValue = "\(store.show.name).fst"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                var showToSave = store.show
                showToSave.workspace = WorkspaceState(
                    activeCueID: store.activeCueID,
                    liveCueID: store.liveCueID,
                    activeSegmentID: store.activeSegmentID,
                    liveSegmentID: store.liveSegmentID,
                    selectedLayerID: store.selectedLayerID,
                    selectedSceneID: store.selectedSceneID,
                    selectedPlaceholderID: store.selectedPlaceholderID,
                    isEditMode: store.isEditMode,
                    mastheadVisible: store.mastheadVisible,
                    sidebarVisible: store.sidebarVisible,
                    inspectorVisible: store.inspectorVisible,
                    panicDuration: store.panicDuration
                )

                let savedShow = try ShowPackage.write(showToSave, to: url)
                store.show = savedShow
                appSettings.addRecentShow(url: url)
                appLogger.info("Saved show package to \(url.path)")
            } catch {
                appLogger.error("Failed to save show: \(error.localizedDescription)")
                presentErrorAlert("Could not save show: \(error.localizedDescription)")
            }
        }
    }

    private func openShow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.freeStageShow]
        panel.allowsMultipleSelection = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                let show = try ShowPackage.read(from: url)
                DispatchQueue.main.async {
                    store.load(show: show)
                    appSettings.addRecentShow(url: url)
                    appLogger.info("Opened show package from \(url.path)")
                }
            } catch {
                appLogger.error("Failed to open show: \(error.localizedDescription)")
                presentErrorAlert("Could not open show: \(error.localizedDescription)")
            }
        }
    }

    private func presentErrorAlert(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "FreeStage"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func toggleRecording() {
        if recordingService.isRecording {
            Task {
                do {
                    if let url = try await recordingService.stopRecording() {
                        NSSound.beep()
                        print("[FreeStage] Recording saved to: \(url.path)")
                    }
                } catch {
                    print("[FreeStage] Failed to stop recording: \(error)")
                }
            }
        } else {
            do {
                let url = try recordingService.startRecording()
                print("[FreeStage] Recording started: \(url.path)")
            } catch {
                print("[FreeStage] Failed to start recording: \(error)")
            }
        }
    }

    private func syncCueTriggerServer() {
        guard appSettings.cueTriggerServerEnabled else {
            cueTriggerServer.stop()
            return
        }
        do {
            try cueTriggerServer.start(
                port: appSettings.cueTriggerServerPort,
                localhostOnly: appSettings.cueTriggerServerLocalhostOnly
            ) { cueID in
                store.triggerCue(id: cueID)
            } gimbal: { action in
                switch action {
                case .moveTo(let pan, let tilt):
                    store.updateSelectedLayerGimbal(pan: pan, tilt: tilt)
                case .recenter:
                    store.updateSelectedLayerGimbal(pan: 0, tilt: 0)
                case .nudge(let panDelta, let tiltDelta):
                    let settings = store.selectedLayer?.cameraSettings ?? CameraSettings()
                    store.updateSelectedLayerGimbal(
                        pan: settings.gimbalPan + panDelta,
                        tilt: settings.gimbalTilt + tiltDelta
                    )
                }
            }
        } catch {
            print("[FreeStage] Failed to start cue trigger server: \(error)")
        }
    }

    private func syncOSCCueServer() {
        guard appSettings.oscCueServerEnabled else {
            oscCueServer.stop()
            return
        }
        do {
            try oscCueServer.start(
                port: appSettings.oscCueServerPort,
                localhostOnly: appSettings.cueTriggerServerLocalhostOnly
            ) { action in
                switch action {
                case .trigger(let cueID):
                    store.triggerCue(id: cueID)
                case .triggerNumber(let number):
                    if let cue = store.show.cues.first(where: { $0.number == number }) {
                        store.triggerCue(id: cue.id)
                    }
                case .go:
                    store.go()
                case .next:
                    store.selectNext()
                case .previous:
                    store.selectPrevious()
                case .gimbalMoveTo(let pan, let tilt):
                    store.updateSelectedLayerGimbal(pan: pan, tilt: tilt)
                case .gimbalRecenter:
                    store.updateSelectedLayerGimbal(pan: 0, tilt: 0)
                case .gimbalNudge(let panDelta, let tiltDelta):
                    let settings = store.selectedLayer?.cameraSettings ?? CameraSettings()
                    store.updateSelectedLayerGimbal(
                        pan: settings.gimbalPan + panDelta,
                        tilt: settings.gimbalTilt + tiltDelta
                    )
                }
            }
        } catch {
            print("[FreeStage] Failed to start OSC cue server: \(error)")
        }
    }

    private func openHelp() {
        // Prefer the bundled HTML help; fall back to the project repository.
        if let url = Bundle.main.url(forResource: "Docs/index", withExtension: "html") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "https://github.com/woodseedigi/FreeStage") {
            NSWorkspace.shared.open(url)
        }
    }
}
