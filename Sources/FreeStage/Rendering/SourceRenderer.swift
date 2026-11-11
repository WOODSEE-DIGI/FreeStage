//
//  SourceRenderer.swift
//  FreeStage
//
//  Renders a Source into a Metal texture. Each concrete source type has its
//  own renderer implementation.
//

import Metal
import CoreGraphics

/// Renders a `Source` into a `MTLTexture`.
protocol SourceRenderer: Sendable {
    /// Render the source into a texture. The texture may be 1×1 for uniform
    /// sources (e.g. color) or the natural size of the source (e.g. image).
    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture?
}

/// Registry that selects the right renderer for a source.
@available(macOS 12.3, *)
struct SourceRendererRegistry: Sendable {
    private let colorRenderer = ColorSourceRenderer()
    private let imageRenderer = ImageSourceRenderer()
    private let slideshowRenderer = SlideshowSourceRenderer()
    private let drawingRenderer = DrawingSourceRenderer()
    private let textRenderer = TextSourceRenderer()
    private let templateRenderer = TemplateSourceRenderer()
    private let mediaRenderer = MediaSourceRenderer()
    private let cameraRenderer: CameraSourceRenderer
    private let screenRenderer: ScreenSourceRenderer
    private let facePuppetRenderer: FacePuppetSourceRenderer
    private let syphonRenderer = SyphonSourceRenderer()
    private let ndiRenderer = NDISourceRenderer()

    init(
        captureManager: CameraCaptureManager,
        screenCaptureManager: ScreenCaptureManager,
        trackingService: FacePuppetTrackingService? = nil
    ) {
        self.cameraRenderer = CameraSourceRenderer(captureManager: captureManager)
        self.screenRenderer = ScreenSourceRenderer(manager: screenCaptureManager)
        self.facePuppetRenderer = FacePuppetSourceRenderer(
            captureManager: captureManager,
            trackingService: trackingService
        )
    }

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        switch source {
        case .color:
            return try colorRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .image:
            return try imageRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .slideshow:
            return try slideshowRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .drawing:
            return try drawingRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .text:
            return try textRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .border, .lowerThird, .chapterMarker, .nextSection, .socialBug, .logoBug, .countdownTimer, .imageLogoBug, .ticker, .playlist:
            return try templateRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .media:
            return try mediaRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .camera:
            return try cameraRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .screen:
            return try screenRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .facePuppet, .facePuppetAnchored, .facePuppetMesh:
            return try facePuppetRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .syphon:
            return try syphonRenderer.render(source: source, device: device, commandQueue: commandQueue)
        case .ndi:
            return try ndiRenderer.render(source: source, device: device, commandQueue: commandQueue)
        default:
            return nil
        }
    }
}

extension Source {
    enum Kind: Hashable, Sendable {
        case ndi
        case syphon
        case camera
        case screen
        case media
        case image
        case slideshow
        case drawing
        case browser
        case color
        case text
        case border
        case lowerThird
        case chapterMarker
        case nextSection
        case socialBug
        case logoBug
        case countdownTimer
        case imageLogoBug
        case ticker
        case playlist
        case facePuppet
        case facePuppetAnchored
        case facePuppetMesh
    }

    var kind: Kind {
        switch self {
        case .ndi: return .ndi
        case .syphon: return .syphon
        case .camera: return .camera
        case .screen: return .screen
        case .media: return .media
        case .image: return .image
        case .slideshow: return .slideshow
        case .drawing: return .drawing
        case .browser: return .browser
        case .color: return .color
        case .text: return .text
        case .border: return .border
        case .lowerThird: return .lowerThird
        case .chapterMarker: return .chapterMarker
        case .nextSection: return .nextSection
        case .socialBug: return .socialBug
        case .logoBug: return .logoBug
        case .countdownTimer: return .countdownTimer
        case .imageLogoBug: return .imageLogoBug
        case .ticker: return .ticker
        case .playlist: return .playlist
        case .facePuppet: return .facePuppet
        case .facePuppetAnchored: return .facePuppetAnchored
        case .facePuppetMesh: return .facePuppetMesh
        }
    }
}
