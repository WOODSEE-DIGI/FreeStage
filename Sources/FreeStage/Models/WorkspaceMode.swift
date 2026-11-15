//
//  WorkspaceMode.swift
//  FreeStage
//
//  Top-level workspace mode: assemble content, edit the rundown, or run the show.
//

import Foundation

/// The three primary ways to interact with a show.
/// - `assemble`: Photoshop-style cue/scene builder (grid, canvas, layers, tools).
/// - `edit`: Rundown-focused workspace (cues, live/preview, inspector).
/// - `show`: Stripped-back run mode for performance.
enum WorkspaceMode: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case assemble
    case edit
    case show

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .assemble: return "Assemble"
        case .edit: return "Edit"
        case .show: return "Show"
        }
    }

    var systemImage: String {
        switch self {
        case .assemble: return "wand.and.rays"
        case .edit: return "list.bullet.rectangle"
        case .show: return "play.rectangle"
        }
    }
}
