//
//  Source.swift
//  FreeStage
//
//  A source produces pixels for a layer. Concrete sources are defined as
//  enum cases so the model stays serializable and SwiftUI-friendly.
//

import Foundation
import CoreGraphics

/// A concrete source of pixels for a layer.
enum Source: Identifiable, Hashable, Codable, Sendable {
    case ndi(name: String)
    case camera(deviceID: String)
    case screen(displayID: CGDirectDisplayID)
    case media(url: URL)
    case image(url: URL)
    case browser(url: URL, width: Int, height: Int)
    case color(CGColorComponents)
    case text(TextSource)

    var id: String {
        switch self {
        case .ndi(let name): return "ndi:\(name)"
        case .camera(let id): return "camera:\(id)"
        case .screen(let id): return "screen:\(id)"
        case .media(let url): return "media:\(url.path)"
        case .image(let url): return "image:\(url.path)"
        case .browser(let url, let w, let h): return "browser:\(url.absoluteString):\(w)x\(h)"
        case .color(let c): return "color:\(c)"
        case .text(let t): return "text:\(t.id)"
        }
    }

    var defaultName: String {
        switch self {
        case .ndi(let name): return name
        case .camera: return "Camera"
        case .screen: return "Screen"
        case .media(let url): return url.deletingPathExtension().lastPathComponent
        case .image(let url): return url.deletingPathExtension().lastPathComponent
        case .browser(let url, _, _): return url.host ?? "Browser"
        case .color: return "Color"
        case .text(let t): return t.content.isEmpty ? "Text" : t.content
        }
    }
}

/// RGBA color components for the color source.
struct CGColorComponents: Hashable, Codable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    static let black = CGColorComponents(r: 0, g: 0, b: 0, a: 1)
    static let green = CGColorComponents(r: 0, g: 1, b: 0, a: 1)
}

/// Configuration for a text source.
struct TextSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var content: String
    var fontName: String?
    var fontSize: Double
    var color: CGColorComponents
    var backgroundColor: CGColorComponents?

    init(
        id: UUID = UUID(),
        content: String = "Text",
        fontName: String? = nil,
        fontSize: Double = 48,
        color: CGColorComponents = .black,
        backgroundColor: CGColorComponents? = nil
    ) {
        self.id = id
        self.content = content
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.backgroundColor = backgroundColor
    }
}
