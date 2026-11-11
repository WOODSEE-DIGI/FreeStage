//
//  SceneLibraryView.swift
//  FreeStage
//
//  Scene library: build scenes independently, then create cues that reference them.
//

import SwiftUI

struct SceneLibraryView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @State private var newSceneName = ""

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.vertical, 8)
                .foregroundStyle(theme.text)

            Divider()

            List(selection: $store.selectedSceneID) {
                ForEach(store.show.scenes) { scene in
                    sceneRow(scene)
                        .listRowBackground(theme.panelBackground)
                }
                .onDelete { indexSet in
                    deleteScenes(at: indexSet)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.panelBackground)
    }

    private var header: some View {
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
    }

    private func sceneRow(_ scene: Scene) -> some View {
        let cueCount = store.show.cues.filter { $0.sceneID == scene.id }.count

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.name)
                    .lineLimit(1)
                Text("\(cueCount) cue\(cueCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
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
        .environment(ThemeStore())
}
