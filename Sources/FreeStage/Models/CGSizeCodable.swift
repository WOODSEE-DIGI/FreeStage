//
//  CGSizeCodable.swift
//  FreeStage
//
//  Codable wrapper for CGSize.
//

import Foundation

struct CGSizeCodable: Hashable, Codable, Sendable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}
