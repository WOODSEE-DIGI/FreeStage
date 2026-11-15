//
//  WorkspaceModeContainer.swift
//  FreeStage
//
//  Routes the main window between the three top-level workspace modes:
//  Assemble (builder), Edit (rundown), and Show (run mode).
//

import SwiftUI

struct WorkspaceModeContainer: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        Group {
            switch store.workspaceMode {
            case .assemble:
                AssembleShowView()
            case .edit:
                editWorkspace
            case .show:
                showWorkspace
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                workspaceModePicker
            }
        }
    }

    private var workspaceModePicker: some View {
        Picker("Mode", selection: Binding(
            get: { store.workspaceMode },
            set: { store.workspaceMode = $0 }
        )) {
            ForEach(WorkspaceMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
    }

    @ViewBuilder
    private var editWorkspace: some View {
        if store.show.kind == .presenter {
            PresenterWorkspaceView()
        } else {
            ContentView()
        }
    }

    @ViewBuilder
    private var showWorkspace: some View {
        // Placeholder for a future dedicated run mode. For now mirror Edit so
        // the user isn't dropped into an empty workspace.
        editWorkspace
    }
}
