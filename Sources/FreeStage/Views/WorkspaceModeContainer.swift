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
