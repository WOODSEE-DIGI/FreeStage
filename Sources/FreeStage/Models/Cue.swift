//
//  Cue.swift
//  FreeStage
//
//  A cue advances the show to a specific scene, optionally with a transition
//  and a duration. Cues are ordered and fireable like a QLab cue list.
//

import Foundation
import SwiftUI

struct Cue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var number: String
    var name: String
    var sceneID: UUID
    var transition: Transition
    var duration: TimeInterval
    var preWait: TimeInterval
    var postWait: TimeInterval
    var continueMode: ContinueMode
    var isArmed: Bool
    var isFlagged: Bool
    var notes: String
    var targetID: UUID?
    var color: CueColor?
    var cameraMove: CameraMove?

    init(
        id: UUID = UUID(),
        number: String = "",
        name: String = "",
        sceneID: UUID,
        transition: Transition = .cut,
        duration: TimeInterval = 0,
        preWait: TimeInterval = 0,
        postWait: TimeInterval = 0,
        continueMode: ContinueMode = .none,
        isArmed: Bool = true,
        isFlagged: Bool = false,
        notes: String = "",
        targetID: UUID? = nil,
        color: CueColor? = nil,
        cameraMove: CameraMove? = nil
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.sceneID = sceneID
        self.transition = transition
        self.duration = duration
        self.preWait = preWait
        self.postWait = postWait
        self.continueMode = continueMode
        self.isArmed = isArmed
        self.isFlagged = isFlagged
        self.notes = notes
        self.targetID = targetID
        self.color = color
        self.cameraMove = cameraMove
    }

    /// The default keyboard shortcut labels map to single-letter editing.
    var continueModeDisplay: String {
        switch continueMode {
        case .none: return ""
        case .autoContinue: return "→"
        case .autoFollow: return "⇢"
        }
    }
}

enum Transition: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case cut
    case dissolve
    case wipeLeft
    case wipeRight
    case wipeUp
    case wipeDown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .dissolve: return "Dissolve"
        case .wipeLeft: return "Wipe Left"
        case .wipeRight: return "Wipe Right"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        }
    }
}

enum ContinueMode: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case autoContinue
    case autoFollow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Continue"
        case .autoContinue: return "Auto Continue"
        case .autoFollow: return "Auto Follow"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return ""
        case .autoContinue: return "arrow.forward.circle"
        case .autoFollow: return "arrowshape.right.circle"
        }
    }
}

enum CueColor: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}
