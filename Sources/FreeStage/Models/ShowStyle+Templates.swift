//
//  ShowStyle+Templates.swift
//  FreeStage
//
//  Applies a ShowStyle's colors, fonts, and layout defaults to the various
//  template source structs when they are created.
//

import Foundation

extension ShowStyle {
    func apply(to source: inout LowerThirdSource) {
        source.titleColor = textColor
        source.subtitleColor = subtitleTextColor
        source.titleFontSize = titleFontSize
        source.subtitleFontSize = subtitleFontSize
        source.backgroundColor = backgroundColor
        source.gradientStartColor = gradientStartColor
        source.gradientEndColor = gradientEndColor
        source.fillStyle = fillStyle
        source.alignment = alignment
        source.horizontalPadding = horizontalPadding
        source.verticalPadding = verticalPadding
        source.animation = animation
    }

    func apply(to source: inout NextSectionSource) {
        source.labelColor = labelTextColor
        source.titleColor = textColor
        source.subtitleColor = subtitleTextColor
        source.labelFontSize = labelFontSize
        source.titleFontSize = titleFontSize
        source.subtitleFontSize = subtitleFontSize
        source.backgroundColor = backgroundColor
        source.gradientStartColor = gradientStartColor
        source.gradientEndColor = gradientEndColor
        source.fillStyle = fillStyle
        source.animation = animation
    }

    func apply(to source: inout ChapterMarkerSource) {
        source.textColor = textColor
        source.accentColor = accentColor
        source.backgroundColor = backgroundColor
        source.fontSize = titleFontSize
        source.animation = animation
    }

    func apply(to source: inout SocialBugSource) {
        source.textColor = textColor
        source.backgroundColor = backgroundColor
        source.fontSize = titleFontSize
        source.animation = animation
    }

    func apply(to source: inout LogoBugSource) {
        source.textColor = textColor
        source.backgroundColor = backgroundColor
        source.fontSize = titleFontSize
        source.animation = animation
    }

    func apply(to source: inout CountdownTimerSource) {
        source.textColor = textColor
        source.backgroundColor = backgroundColor
        source.fontSize = titleFontSize
        source.labelFontSize = labelFontSize
        source.animation = animation
    }

    func apply(to source: inout BorderSource) {
        source.color = primaryColor
        source.gradientStartColor = gradientStartColor
        source.gradientEndColor = gradientEndColor
        source.fillColor = backgroundColor
        source.cornerRadius = cornerRadius
        source.animation = animation
    }

    func apply(to source: inout TickerSource) {
        source.textColor = textColor
        source.backgroundColor = backgroundColor
        source.fontSize = subtitleFontSize
        source.animation = animation
    }
}
