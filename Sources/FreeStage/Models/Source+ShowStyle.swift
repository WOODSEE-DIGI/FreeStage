//
//  Source+ShowStyle.swift
//  FreeStage
//
//  Applies a ShowStyle to template sources when they are created.
//

import Foundation

extension Source {
    /// Apply the current show's graphic style to any template source. Non-
    /// template sources are returned unchanged.
    func applying(_ style: ShowStyle) -> Source {
        switch self {
        case .border(var source):
            style.apply(to: &source)
            return .border(source)
        case .lowerThird(var source):
            style.apply(to: &source)
            return .lowerThird(source)
        case .chapterMarker(var source):
            style.apply(to: &source)
            return .chapterMarker(source)
        case .nextSection(var source):
            style.apply(to: &source)
            return .nextSection(source)
        case .socialBug(var source):
            style.apply(to: &source)
            return .socialBug(source)
        case .logoBug(var source):
            style.apply(to: &source)
            return .logoBug(source)
        case .countdownTimer(var source):
            style.apply(to: &source)
            return .countdownTimer(source)
        case .ticker(var source):
            style.apply(to: &source)
            return .ticker(source)
        default:
            return self
        }
    }
}
