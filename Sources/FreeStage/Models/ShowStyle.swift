//
//  ShowStyle.swift
//  FreeStage
//
//  A reusable set of global colors, type sizes, and layout defaults for
//  template graphics (lower thirds, bugs, tickers, etc.). Saved as presets
//  in AppSettings and referenced by each Show so new layers start on-brand.
//

import Foundation

struct ShowStyle: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String

    // MARK: - Global colors
    var primaryColor: CGColorComponents
    var accentColor: CGColorComponents
    var backgroundColor: CGColorComponents
    var textColor: CGColorComponents
    var subtitleTextColor: CGColorComponents
    var labelTextColor: CGColorComponents

    // MARK: - Typography
    var titleFontSize: Double
    var subtitleFontSize: Double
    var labelFontSize: Double

    // MARK: - Layout
    var alignment: TemplateTextAlignment
    var horizontalPadding: Double
    var verticalPadding: Double

    // MARK: - Fill & effects
    var fillStyle: TemplateFillStyle
    var gradientStartColor: CGColorComponents
    var gradientEndColor: CGColorComponents
    var cornerRadius: Double

    // MARK: - Animation
    var animation: TemplateAnimation

    init(
        id: UUID = UUID(),
        name: String = "Default",
        primaryColor: CGColorComponents = CGColorComponents(r: 0, g: 0.3, b: 0.6, a: 0.85),
        accentColor: CGColorComponents = .white,
        backgroundColor: CGColorComponents = CGColorComponents(r: 0, g: 0.3, b: 0.6, a: 0.85),
        textColor: CGColorComponents = .white,
        subtitleTextColor: CGColorComponents = .white,
        labelTextColor: CGColorComponents = .white,
        titleFontSize: Double = 48,
        subtitleFontSize: Double = 28,
        labelFontSize: Double = 18,
        alignment: TemplateTextAlignment = .left,
        horizontalPadding: Double = 40,
        verticalPadding: Double = 24,
        fillStyle: TemplateFillStyle = .solid,
        gradientStartColor: CGColorComponents = CGColorComponents(r: 0, g: 0.2, b: 0.5, a: 0.9),
        gradientEndColor: CGColorComponents = CGColorComponents(r: 0, g: 0.5, b: 0.7, a: 0.9),
        cornerRadius: Double = 0,
        animation: TemplateAnimation = TemplateAnimation()
    ) {
        self.id = id
        self.name = name
        self.primaryColor = primaryColor
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.subtitleTextColor = subtitleTextColor
        self.labelTextColor = labelTextColor
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.labelFontSize = labelFontSize
        self.alignment = alignment
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.fillStyle = fillStyle
        self.gradientStartColor = gradientStartColor
        self.gradientEndColor = gradientEndColor
        self.cornerRadius = cornerRadius
        self.animation = animation
    }
}

// MARK: - Built-in presets

extension ShowStyle {
    static var `default`: ShowStyle {
        ShowStyle(name: "FreeStage Default")
    }

    static var newsDark: ShowStyle {
        ShowStyle(
            name: "News Dark",
            primaryColor: CGColorComponents(r: 0.75, g: 0.05, b: 0.05, a: 0.9),
            accentColor: .white,
            backgroundColor: CGColorComponents(r: 0.75, g: 0.05, b: 0.05, a: 0.9),
            textColor: .white,
            subtitleTextColor: .white,
            labelTextColor: .white,
            titleFontSize: 52,
            subtitleFontSize: 28,
            labelFontSize: 18,
            alignment: .left,
            horizontalPadding: 40,
            verticalPadding: 24,
            fillStyle: .solid,
            gradientStartColor: CGColorComponents(r: 0.6, g: 0.05, b: 0.05, a: 0.95),
            gradientEndColor: CGColorComponents(r: 0.9, g: 0.05, b: 0.05, a: 0.95),
            cornerRadius: 0
        )
    }

    static var cyberBlue: ShowStyle {
        ShowStyle(
            name: "Cyber Blue",
            primaryColor: CGColorComponents(r: 0, g: 0.7, b: 1, a: 0.85),
            accentColor: .white,
            backgroundColor: CGColorComponents(r: 0, g: 0.15, b: 0.25, a: 0.9),
            textColor: .white,
            subtitleTextColor: .white,
            labelTextColor: CGColorComponents(r: 0, g: 0.7, b: 1, a: 1),
            titleFontSize: 48,
            subtitleFontSize: 26,
            labelFontSize: 16,
            alignment: .center,
            horizontalPadding: 48,
            verticalPadding: 28,
            fillStyle: .gradient,
            gradientStartColor: CGColorComponents(r: 0, g: 0.1, b: 0.2, a: 0.95),
            gradientEndColor: CGColorComponents(r: 0, g: 0.3, b: 0.5, a: 0.95),
            cornerRadius: 12
        )
    }

    static var minimalLight: ShowStyle {
        ShowStyle(
            name: "Minimal Light",
            primaryColor: CGColorComponents(r: 0.1, g: 0.1, b: 0.1, a: 0.85),
            accentColor: CGColorComponents(r: 0.1, g: 0.1, b: 0.1, a: 1),
            backgroundColor: CGColorComponents(r: 1, g: 1, b: 1, a: 0.9),
            textColor: CGColorComponents(r: 0.1, g: 0.1, b: 0.1, a: 1),
            subtitleTextColor: CGColorComponents(r: 0.2, g: 0.2, b: 0.2, a: 1),
            labelTextColor: CGColorComponents(r: 0.4, g: 0.4, b: 0.4, a: 1),
            titleFontSize: 46,
            subtitleFontSize: 26,
            labelFontSize: 16,
            alignment: .left,
            horizontalPadding: 36,
            verticalPadding: 22,
            fillStyle: .solid,
            gradientStartColor: CGColorComponents(r: 1, g: 1, b: 1, a: 0.95),
            gradientEndColor: CGColorComponents(r: 0.9, g: 0.9, b: 0.9, a: 0.95),
            cornerRadius: 8
        )
    }

    static var allBuiltIns: [ShowStyle] {
        [.default, .newsDark, .cyberBlue, .minimalLight]
    }
}
