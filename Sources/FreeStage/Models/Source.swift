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
    case slideshow(SlideshowSource)
    case browser(url: URL, width: Int, height: Int)
    case color(CGColorComponents)
    case text(TextSource)
    case drawing(DrawingSource)
    case border(BorderSource)
    case lowerThird(LowerThirdSource)
    case chapterMarker(ChapterMarkerSource)
    case nextSection(NextSectionSource)
    case socialBug(SocialBugSource)
    case logoBug(LogoBugSource)
    case countdownTimer(CountdownTimerSource)
    case imageLogoBug(ImageLogoBugSource)
    case ticker(TickerSource)
    case playlist(PlaylistSource)

    var id: String {
        switch self {
        case .ndi(let name): return "ndi:\(name)"
        case .camera(let id): return "camera:\(id)"
        case .screen(let id): return "screen:\(id)"
        case .media(let url): return "media:\(url.path)"
        case .image(let url): return "image:\(url.path)"
        case .slideshow(let s): return "slideshow:\(s.id)"
        case .browser(let url, let w, let h): return "browser:\(url.absoluteString):\(w)x\(h)"
        case .color(let c): return "color:\(c)"
        case .text(let t): return "text:\(t.id)"
        case .drawing(let d): return "drawing:\(d.id)"
        case .border(let b): return "border:\(b.id)"
        case .lowerThird(let l): return "lowerThird:\(l.id)"
        case .chapterMarker(let c): return "chapterMarker:\(c.id)"
        case .nextSection(let n): return "nextSection:\(n.id)"
        case .socialBug(let s): return "socialBug:\(s.id)"
        case .logoBug(let l): return "logoBug:\(l.id)"
        case .countdownTimer(let c): return "countdownTimer:\(c.id)"
        case .imageLogoBug(let i): return "imageLogoBug:\(i.id)"
        case .ticker(let t): return "ticker:\(t.id)"
        case .playlist(let p): return "playlist:\(p.id)"
        }
    }

    var defaultName: String {
        switch self {
        case .ndi(let name): return name
        case .camera: return "Camera"
        case .screen: return "Screen"
        case .media(let url): return url.deletingPathExtension().lastPathComponent
        case .image(let url): return url.deletingPathExtension().lastPathComponent
        case .slideshow(let s): return "Slideshow (\(s.imageURLs.count))"
        case .browser(let url, _, _): return url.host ?? "Browser"
        case .color: return "Color"
        case .text(let t): return t.content.isEmpty ? "Text" : t.content
        case .drawing: return "Drawing"
        case .border: return "Border"
        case .lowerThird(let l): return l.title.isEmpty ? "Lower Third" : l.title
        case .chapterMarker(let c): return c.title.isEmpty ? "Chapter" : c.title
        case .nextSection(let n): return n.title.isEmpty ? "Next Section" : n.title
        case .socialBug(let s): return s.handle.isEmpty ? "Social Bug" : s.handle
        case .logoBug(let l): return l.text.isEmpty ? "Logo Bug" : l.text
        case .countdownTimer(let c): return c.label.isEmpty ? "Countdown" : c.label
        case .imageLogoBug(let i): return i.imageURL?.deletingPathExtension().lastPathComponent ?? "Logo Bug"
        case .ticker(let t): return t.items.first ?? "Ticker"
        case .playlist(let p): return p.items.first?.title ?? "Playlist"
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
    static let red = CGColorComponents(r: 1, g: 0, b: 0, a: 1)
    static let white = CGColorComponents(r: 1, g: 1, b: 1, a: 1)
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

/// Configuration for a drawing/annotation layer.
struct DrawingSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Canvas size in pixels. Strokes are stored in normalized 0...1 coordinates
    /// and scaled to this size when rendered.
    var canvasSize: CGSize
    /// Background fill. Alpha 0 makes the layer transparent except for strokes.
    var backgroundColor: CGColorComponents
    /// Ordered list of strokes. Each stroke is a complete mouse/tablet gesture.
    var strokes: [DrawingStroke]
    /// Current tool/color/width used for new strokes.
    var tool: DrawingTool
    var color: CGColorComponents
    var brushWidth: Double

    init(
        id: UUID = UUID(),
        canvasSize: CGSize = CGSize(width: 1920, height: 1080),
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0),
        strokes: [DrawingStroke] = [],
        tool: DrawingTool = .pen,
        color: CGColorComponents = CGColorComponents(r: 1, g: 0, b: 0, a: 1),
        brushWidth: Double = 4
    ) {
        self.id = id
        self.canvasSize = canvasSize
        self.backgroundColor = backgroundColor
        self.strokes = strokes
        self.tool = tool
        self.color = color
        self.brushWidth = brushWidth
    }
}

/// A single continuous stroke, shape, or text element drawn by the user.
struct DrawingStroke: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Freehand points for pen/eraser; for shapes/lines, two points define start/end.
    var points: [DrawingPoint]
    var color: CGColorComponents
    var width: Double
    var tool: DrawingTool
    /// Text content when the tool is `.text`.
    var text: String?

    init(
        id: UUID = UUID(),
        points: [DrawingPoint] = [],
        color: CGColorComponents = .red,
        width: Double = 4,
        tool: DrawingTool = .pen,
        text: String? = nil
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.width = width
        self.tool = tool
        self.text = text
    }
}

/// Normalized point on the drawing canvas with optional tablet pressure.
struct DrawingPoint: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
    /// Tablet pressure in 0...1; nil or 0 means no pressure data.
    var pressure: Double?

    init(x: Double, y: Double, pressure: Double? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }
}

enum DrawingTool: String, CaseIterable, Identifiable, Codable, Sendable {
    case pen
    case eraser
    case rectangle
    case ellipse
    case line
    case arrow
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "minus"
        case .arrow: return "arrow.right"
        case .text: return "textformat"
        }
    }

    var isShape: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .arrow:
            return true
        default:
            return false
        }
    }
}

/// Configuration for a slideshow source.
struct SlideshowSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// Ordered list of image URLs to cycle through.
    var imageURLs: [URL]
    /// Seconds each slide is shown.
    var interval: TimeInterval
    /// Transition style between slides.
    var transition: SlideTransition
    /// Randomize slide order.
    var shuffle: Bool

    init(
        id: UUID = UUID(),
        imageURLs: [URL] = [],
        interval: TimeInterval = 5.0,
        transition: SlideTransition = .cut,
        shuffle: Bool = false
    ) {
        self.id = id
        self.imageURLs = imageURLs
        self.interval = max(interval, 0.5)
        self.transition = transition
        self.shuffle = shuffle
    }
}

enum SlideTransition: String, CaseIterable, Identifiable, Codable, Sendable {
    case cut
    case dissolve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .dissolve: return "Dissolve"
        }
    }
}

// MARK: - Template sources

/// Horizontal alignment for template text.
enum TemplateTextAlignment: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case center
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }
}

/// Fill style for template shapes: solid color or linear gradient.
enum TemplateFillStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case solid
    case gradient

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .gradient: return "Gradient"
        }
    }
}

/// Configuration for a border/frame template layer.
struct BorderSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var thickness: Double
    var cornerRadius: Double
    var fillStyle: TemplateFillStyle
    var color: CGColorComponents
    var gradientStartColor: CGColorComponents
    var gradientEndColor: CGColorComponents
    var gradientAngle: Double
    var fillCenter: Bool
    var fillColor: CGColorComponents
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        thickness: Double = 8,
        cornerRadius: Double = 0,
        fillStyle: TemplateFillStyle = .solid,
        color: CGColorComponents = .white,
        gradientStartColor: CGColorComponents = .white,
        gradientEndColor: CGColorComponents = .black,
        gradientAngle: Double = 0,
        fillCenter: Bool = false,
        fillColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0),
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.thickness = thickness
        self.cornerRadius = cornerRadius
        self.fillStyle = fillStyle
        self.color = color
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.gradientAngle = gradientAngle
        self.fillCenter = fillCenter
        self.fillColor = fillColor
        self.animation = animation
    }
}

/// Configuration for a lower-third graphic template layer.
struct LowerThirdSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var titleFontSize: Double
    var subtitleFontSize: Double
    var titleColor: CGColorComponents
    var subtitleColor: CGColorComponents
    var fillStyle: TemplateFillStyle
    var backgroundColor: CGColorComponents
    var gradientStartColor: CGColorComponents
    var gradientEndColor: CGColorComponents
    var alignment: TemplateTextAlignment
    var horizontalPadding: Double
    var verticalPadding: Double
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        title: String = "Name",
        subtitle: String = "Role / Detail",
        titleFontSize: Double = 48,
        subtitleFontSize: Double = 28,
        titleColor: CGColorComponents = .white,
        subtitleColor: CGColorComponents = .white,
        fillStyle: TemplateFillStyle = .solid,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0.3, b: 0.6, a: 0.85),
        gradientStartColor: CGColorComponents = CGColorComponents(r: 0, g: 0.2, b: 0.5, a: 0.9),
        gradientEndColor: CGColorComponents = CGColorComponents(r: 0, g: 0.5, b: 0.7, a: 0.9),
        alignment: TemplateTextAlignment = .left,
        horizontalPadding: Double = 40,
        verticalPadding: Double = 24,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.fillStyle = fillStyle
        self.backgroundColor = backgroundColor
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.alignment = alignment
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.animation = animation
    }
}

/// Configuration for a chapter-marker template layer.
struct ChapterMarkerSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var chapterNumber: String
    var title: String
    var fontSize: Double
    var textColor: CGColorComponents
    var accentColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var showProgressBar: Bool
    var progress: Double
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        chapterNumber: String = "01",
        title: String = "Chapter Title",
        fontSize: Double = 42,
        textColor: CGColorComponents = .white,
        accentColor: CGColorComponents = .red,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0.6),
        showProgressBar: Bool = true,
        progress: Double = 0,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.chapterNumber = chapterNumber
        self.title = title
        self.fontSize = fontSize
        self.textColor = textColor
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.showProgressBar = showProgressBar
        self.progress = progress
        self.animation = animation
    }
}

/// Configuration for a "next section / coming up" template layer.
struct NextSectionSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var label: String
    var title: String
    var subtitle: String
    var titleFontSize: Double
    var subtitleFontSize: Double
    var labelFontSize: Double
    var titleColor: CGColorComponents
    var subtitleColor: CGColorComponents
    var labelColor: CGColorComponents
    var fillStyle: TemplateFillStyle
    var backgroundColor: CGColorComponents
    var gradientStartColor: CGColorComponents
    var gradientEndColor: CGColorComponents
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        label: String = "UP NEXT",
        title: String = "Section Title",
        subtitle: String = "Brief description of what's coming up next.",
        titleFontSize: Double = 44,
        subtitleFontSize: Double = 24,
        labelFontSize: Double = 18,
        titleColor: CGColorComponents = .white,
        subtitleColor: CGColorComponents = .white,
        labelColor: CGColorComponents = .white,
        fillStyle: TemplateFillStyle = .gradient,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0.1, g: 0.1, b: 0.1, a: 0.8),
        gradientStartColor: CGColorComponents = CGColorComponents(r: 0.2, g: 0.2, b: 0.2, a: 0.9),
        gradientEndColor: CGColorComponents = CGColorComponents(r: 0.05, g: 0.05, b: 0.05, a: 0.9),
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.label = label
        self.title = title
        self.subtitle = subtitle
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.labelFontSize = labelFontSize
        self.titleColor = titleColor
        self.subtitleColor = subtitleColor
        self.labelColor = labelColor
        self.fillStyle = fillStyle
        self.backgroundColor = backgroundColor
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.animation = animation
    }
}

// MARK: - Animation

/// Animation preset for template layers.
enum TemplateAnimationPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case slideFromLeft
    case slideFromRight
    case slideFromBottom
    case fade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .slideFromLeft: return "Slide from Left"
        case .slideFromRight: return "Slide from Right"
        case .slideFromBottom: return "Slide from Bottom"
        case .fade: return "Fade"
        }
    }
}

/// Animation state for a template layer.
struct TemplateAnimation: Hashable, Codable, Sendable {
    var preset: TemplateAnimationPreset
    var progress: Double
    var duration: Double

    init(
        preset: TemplateAnimationPreset = .none,
        progress: Double = 1,
        duration: Double = 0.5
    ) {
        self.preset = preset
        self.progress = max(0, min(1, progress))
        self.duration = max(0.05, duration)
    }
}

/// Common protocol-ish helper for template sources that support animation.
protocol AnimatableTemplate {
    var animation: TemplateAnimation { get set }
}

extension BorderSource: AnimatableTemplate {}
extension LowerThirdSource: AnimatableTemplate {}
extension ChapterMarkerSource: AnimatableTemplate {}
extension NextSectionSource: AnimatableTemplate {}

// MARK: - Additional streaming templates

/// Social platform choices for the social bug template.
enum SocialPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case custom
    case twitter
    case instagram
    case youtube
    case twitch
    case tiktok
    case linkedin
    case facebook
    case threads
    case bluesky
    case mastodon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: return "Custom"
        case .twitter: return "X / Twitter"
        case .instagram: return "Instagram"
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .tiktok: return "TikTok"
        case .linkedin: return "LinkedIn"
        case .facebook: return "Facebook"
        case .threads: return "Threads"
        case .bluesky: return "Bluesky"
        case .mastodon: return "Mastodon"
        }
    }

    var systemImage: String {
        switch self {
        case .custom: return "at"
        case .twitter: return "bird.fill"
        case .instagram: return "camera.fill"
        case .youtube: return "play.rectangle.fill"
        case .twitch: return "play.tv.fill"
        case .tiktok: return "music.note"
        case .linkedin: return "briefcase.fill"
        case .facebook: return "f.circle.fill"
        case .threads: return "at.circle.fill"
        case .bluesky: return "cloud.fill"
        case .mastodon: return "bubble.left.fill"
        }
    }
}

/// Configuration for a social-handle bug template layer.
struct SocialBugSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var platform: SocialPlatform
    var handle: String
    var label: String
    var fontSize: Double
    var textColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var cornerRadius: Double
    var padding: Double
    var position: TemplateBugPosition
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        platform: SocialPlatform = .twitter,
        handle: String = "@handle",
        label: String = "",
        fontSize: Double = 24,
        textColor: CGColorComponents = .white,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0.7),
        cornerRadius: Double = 8,
        padding: Double = 12,
        position: TemplateBugPosition = .topRight,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.platform = platform
        self.handle = handle
        self.label = label
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.position = position
        self.animation = animation
    }
}

/// Configuration for a logo/brand bug template layer.
struct LogoBugSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var text: String
    var fontSize: Double
    var textColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var cornerRadius: Double
    var padding: Double
    var position: TemplateBugPosition
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        text: String = "BRAND",
        fontSize: Double = 28,
        textColor: CGColorComponents = .white,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0.6),
        cornerRadius: Double = 8,
        padding: Double = 14,
        position: TemplateBugPosition = .topLeft,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.position = position
        self.animation = animation
    }
}

/// Screen corner / edge position for bug-style templates.
enum TemplateBugPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

/// Configuration for a countdown timer template layer.
struct CountdownTimerSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var targetDate: Date
    var label: String
    var fontSize: Double
    var labelFontSize: Double
    var textColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var showSeconds: Bool
    var alignment: TemplateTextAlignment
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        targetDate: Date = Date().addingTimeInterval(300),
        label: String = "Starting in",
        fontSize: Double = 64,
        labelFontSize: Double = 24,
        textColor: CGColorComponents = .white,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0.6),
        showSeconds: Bool = true,
        alignment: TemplateTextAlignment = .center,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.targetDate = targetDate
        self.label = label
        self.fontSize = fontSize
        self.labelFontSize = labelFontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.showSeconds = showSeconds
        self.alignment = alignment
        self.animation = animation
    }

    /// Format the remaining time relative to now.
    func formattedRemaining(from now: Date) -> String {
        let remaining = targetDate.timeIntervalSince(now)
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if showSeconds {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Image logo bug

/// Configuration for an image-based logo/brand bug template layer.
struct ImageLogoBugSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var imageURL: URL?
    var position: TemplateBugPosition
    var width: Double
    var cornerRadius: Double
    var backgroundColor: CGColorComponents
    var padding: Double
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        imageURL: URL? = nil,
        position: TemplateBugPosition = .topRight,
        width: Double = 200,
        cornerRadius: Double = 8,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0, b: 0, a: 0),
        padding: Double = 0,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.imageURL = imageURL
        self.position = position
        self.width = width
        self.cornerRadius = cornerRadius
        self.backgroundColor = backgroundColor
        self.padding = padding
        self.animation = animation
    }
}

// MARK: - Scrolling ticker

enum TickerDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Scroll Left"
        case .right: return "Scroll Right"
        }
    }
}

enum TickerVerticalPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

/// Configuration for a scrolling ticker / news banner template layer.
struct TickerSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var items: [String]
    var separator: String
    var speed: Double
    var direction: TickerDirection
    var fontSize: Double
    var textColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var verticalPosition: TickerVerticalPosition
    var height: Double
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        items: [String] = ["Breaking news", "Live stream in progress"],
        separator: String = "   •   ",
        speed: Double = 120,
        direction: TickerDirection = .left,
        fontSize: Double = 28,
        textColor: CGColorComponents = .white,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0.8, g: 0, b: 0, a: 0.9),
        verticalPosition: TickerVerticalPosition = .bottom,
        height: Double = 48,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.items = items
        self.separator = separator
        self.speed = speed
        self.direction = direction
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.verticalPosition = verticalPosition
        self.height = height
        self.animation = animation
    }

    var tickerText: String {
        items.filter { !$0.isEmpty }.joined(separator: separator)
    }
}

// MARK: - Playlist rotation

enum PlaylistItemStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case lowerThird
    case socialBug
    case simple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lowerThird: return "Lower Third"
        case .socialBug: return "Social Bug"
        case .simple: return "Simple"
        }
    }
}

/// A single item in a playlist rotation.
struct PlaylistItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var style: PlaylistItemStyle
    var duration: TimeInterval

    init(
        id: UUID = UUID(),
        title: String = "Title",
        subtitle: String = "Subtitle",
        style: PlaylistItemStyle = .lowerThird,
        duration: TimeInterval = 5
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.duration = max(1, duration)
    }
}

/// Configuration for a playlist-rotation template layer that cycles through
/// messages automatically.
struct PlaylistSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var items: [PlaylistItem]
    var loop: Bool
    var displayDuration: TimeInterval
    var crossfadeDuration: TimeInterval
    var backgroundColor: CGColorComponents
    var accentColor: CGColorComponents
    var textColor: CGColorComponents
    var fontSize: Double
    var subtitleFontSize: Double
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        items: [PlaylistItem] = [
            PlaylistItem(title: "Welcome", subtitle: "Thanks for joining"),
            PlaylistItem(title: "Follow us", subtitle: "@freestage")
        ],
        loop: Bool = true,
        displayDuration: TimeInterval = 5,
        crossfadeDuration: TimeInterval = 0.5,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0.3, b: 0.6, a: 0.85),
        accentColor: CGColorComponents = .white,
        textColor: CGColorComponents = .white,
        fontSize: Double = 42,
        subtitleFontSize: Double = 24,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.items = items
        self.loop = loop
        self.displayDuration = max(1, displayDuration)
        self.crossfadeDuration = max(0, crossfadeDuration)
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.textColor = textColor
        self.fontSize = fontSize
        self.subtitleFontSize = subtitleFontSize
        self.animation = animation
    }

    /// Index and local progress (0...1) for the current item based on elapsed time.
    func item(at elapsed: TimeInterval) -> (index: Int, progress: Double, isLast: Bool)? {
        guard !items.isEmpty else { return nil }
        let cycleDuration = displayDuration + crossfadeDuration
        let totalDuration = cycleDuration * Double(items.count)
        guard loop || elapsed < totalDuration else { return nil }

        let wrapped = loop ? elapsed.truncatingRemainder(dividingBy: totalDuration) : elapsed
        let rawIndex = Int(wrapped / cycleDuration)
        let index = min(rawIndex, items.count - 1)
        let local = wrapped - Double(index) * cycleDuration
        let progress = min(1, max(0, local / displayDuration))
        return (index: index, progress: progress, isLast: index == items.count - 1 && !loop)
    }
}
