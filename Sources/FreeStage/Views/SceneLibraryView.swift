//
//  SceneLibraryView.swift
//  FreeStage
//
//  Scene library: build scenes independently, then create cues that reference them.
//

import SwiftUI

struct SceneLibraryView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.screenCaptureManager) private var screenCaptureManager
    @State private var newSceneName = ""
    @State private var isAddingCamera = false
    @State private var isAddingScreen = false
    @State private var isAddingSlideshow = false

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            List(selection: $store.selectedSceneID) {
                ForEach(store.show.scenes) { scene in
                    sceneRow(scene)
                }
                .onDelete { indexSet in
                    deleteScenes(at: indexSet)
                }
            }
            .listStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $isAddingCamera) {
            CameraPickerSheet { device in
                addSourceToActiveScene(.camera(deviceID: device.uniqueID), name: device.name)
                captureManager?.startCapture(uniqueID: device.uniqueID)
            }
        }
        .sheet(isPresented: $isAddingScreen) {
            if let screenCaptureManager {
                ScreenPickerSheet { display in
                    addSourceToActiveScene(.screen(displayID: display.displayID), name: "Screen \(display.displayID)")
                    screenCaptureManager.startCapture(displayID: display.displayID)
                }
            }
        }
        .sheet(isPresented: $isAddingSlideshow) {
            SlideshowPickerSheet { slideshow in
                addSourceToActiveScene(.slideshow(slideshow), name: "Slideshow")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scenes")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    TextField("New scene", text: $newSceneName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button("Add") {
                        addScene()
                    }
                    .disabled(newSceneName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                sourceButton("Camera", systemImage: "video.fill") { isAddingCamera = true }
                sourceButton("Screen", systemImage: "display") { isAddingScreen = true }
                sourceButton("Color", systemImage: "paintpalette.fill") {
                    addSourceToActiveScene(.color(.green), name: "Color")
                }
                sourceButton("Text", systemImage: "textformat") {
                    addSourceToActiveScene(.text(TextSource()), name: "Text")
                }
                sourceButton("Slideshow", systemImage: "photo.stack") { isAddingSlideshow = true }
                sourceButton("Draw", systemImage: "pencil.tip") { addDrawingLayer() }
            }
        }
    }

    private func sourceButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(store.activeScene == nil)
    }

    private func sceneRow(_ scene: Scene) -> some View {
        let cueCount = store.show.cues.filter { $0.sceneID == scene.id }.count

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name)
                    .lineLimit(1)
                Text("\(cueCount) cue\(cueCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                let cueID = store.addCue(for: scene.id)
                store.selectCue(id: cueID)
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Add cue for this scene")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Add Cue for Scene") {
                let cueID = store.addCue(for: scene.id)
                store.selectCue(id: cueID)
            }
            Button("Duplicate Scene") {
                duplicateScene(scene)
            }
            Divider()
            Button("Delete Scene", role: .destructive) {
                store.deleteScene(id: scene.id)
            }
        }
    }

    private func addScene() {
        let name = newSceneName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let sceneID = store.createScene(name: name)
        newSceneName = ""
        // Pre-select the new scene so the user can add sources immediately.
        if let firstCueID = store.show.cues.first?.id {
            store.selectCue(id: firstCueID)
        }
        store.selectedSceneID = sceneID
    }

    private func addSourceToActiveScene(_ source: Source, name: String) {
        guard let scene = store.activeScene,
              let sceneIndex = store.show.scenes.firstIndex(where: { $0.id == scene.id }) else {
            // If no active scene, create one.
            let sceneID = store.createScene(name: name, layers: [Layer(name: name, source: source)])
            store.addCue(for: sceneID, name: name)
            return
        }
        let layer = Layer(name: name, source: source)
        store.show.scenes[sceneIndex].layers.append(layer)
        store.selectLayer(id: layer.id)
    }

    private func addDrawingLayer() {
        addSourceToActiveScene(.drawing(DrawingSource()), name: "Drawing")
    }

    private func duplicateScene(_ scene: Scene) {
        let copy = Scene(name: scene.name + " Copy", layers: scene.layers)
        store.show.scenes.append(copy)
    }

    private func deleteScenes(at indexSet: IndexSet) {
        for index in indexSet {
            let scene = store.show.scenes[index]
            store.deleteScene(id: scene.id)
        }
    }
}

#Preview {
    SceneLibraryView()
        .environment(ShowStore())
}
