//
//  ShowKind.swift
//  FreeStage
//
//  Distinguishes the two show systems: theatre-style cue/scene workflows
//  versus presenter-to-camera segment workflows. The engine is shared, but
//  the UI and document model differ.
//

import Foundation

enum ShowKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case theatre
    case presenter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .theatre: return "Theatre / Projector"
        case .presenter: return "Presenter to Camera"
        }
    }

    var subtitle: String {
        switch self {
        case .theatre:
            return "Cue list, scenes, layers — for live shows, comedy, theatre, and projector-based events."
        case .presenter:
            return "Segment rundown with camera angles, graphic placeholders, and pre-prepared videos — for news, vlogs, and evidence presentations."
        }
    }
}
