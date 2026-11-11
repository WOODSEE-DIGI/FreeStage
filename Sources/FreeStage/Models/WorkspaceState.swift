//
//  WorkspaceState.swift
//  FreeStage
//
//  Persisted workspace UI state so a show reloads with the same cue, scene,
//  layer selection, panel visibility, and edit/show mode that the user left.
//

import Foundation

/// Snapshot of user-facing workspace state stored inside a show file.
struct WorkspaceState: Hashable, Codable, Sendable {
    var activeCueID: UUID?
    var liveCueID: UUID?
    var selectedLayerID: UUID?
    var selectedSceneID: UUID?
    var isEditMode: Bool
    var mastheadVisible: Bool
    var sidebarVisible: Bool
    var inspectorVisible: Bool
    var panicDuration: TimeInterval

    init(
        activeCueID: UUID? = nil,
        liveCueID: UUID? = nil,
        selectedLayerID: UUID? = nil,
        selectedSceneID: UUID? = nil,
        isEditMode: Bool = true,
        mastheadVisible: Bool = true,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = true,
        panicDuration: TimeInterval = 1.0
    ) {
        self.activeCueID = activeCueID
        self.liveCueID = liveCueID
        self.selectedLayerID = selectedLayerID
        self.selectedSceneID = selectedSceneID
        self.isEditMode = isEditMode
        self.mastheadVisible = mastheadVisible
        self.sidebarVisible = sidebarVisible
        self.inspectorVisible = inspectorVisible
        self.panicDuration = panicDuration
    }
}
