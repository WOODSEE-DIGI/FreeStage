//
//  BlendMode.swift
//  FreeStage
//
//  Layer blending modes supported by the Metal compositor.
//

import Foundation

enum BlendMode: String, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case add
    case multiply
    case screen
    case overlay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .add: return "Add"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        }
    }
}
