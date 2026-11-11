//
//  AppTheme.swift
//  FreeStage
//
//  A named UI theme ("skin") for the FreeStage application chrome. Themes are
//  sourced from the shared ThemeSwatches palette collection so FreeStage stays
//  in sync with the rest of the WOODSEE-DIGI app suite.
//

import Foundation
import AppKit

struct AppTheme: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var appearance: AppThemeAppearance

    // MARK: - Chrome palette
    var backgroundHex: String
    var panelBackgroundHex: String
    var textHex: String
    var secondaryTextHex: String
    var accentHex: String
    var selectedHex: String
    var dangerHex: String
    var monitorBackgroundHex: String
    var borderHex: String

    init(
        id: String,
        name: String,
        appearance: AppThemeAppearance,
        backgroundHex: String,
        panelBackgroundHex: String,
        textHex: String,
        secondaryTextHex: String,
        accentHex: String,
        selectedHex: String,
        dangerHex: String,
        monitorBackgroundHex: String,
        borderHex: String
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.backgroundHex = backgroundHex
        self.panelBackgroundHex = panelBackgroundHex
        self.textHex = textHex
        self.secondaryTextHex = secondaryTextHex
        self.accentHex = accentHex
        self.selectedHex = selectedHex
        self.dangerHex = dangerHex
        self.monitorBackgroundHex = monitorBackgroundHex
        self.borderHex = borderHex
    }

    /// Build an AppTheme from a shared ThemeSwatches palette. Returns nil if
    /// the palette is missing the absolute minimum colours (Accent, Text).
    init?(palette: ThemeSwatches.Palette) {
        guard let accentHex = palette.hex(for: "Accent"),
              let textHex = palette.hex(for: "Text") else {
            return nil
        }

        let backgroundHex = palette.hex(for: "Background")
            ?? palette.hex(for: "Base")
            ?? "1E1E2EFF"

        let panelBackgroundHex = palette.hex(for: "Surface")
            ?? palette.hex(for: "Surface 0")
            ?? palette.hex(for: "Mantle")
            ?? backgroundHex

        let secondaryTextHex = palette.hex(for: "Subtext")
            ?? palette.hex(for: "Subtext 0")
            ?? palette.hex(for: "Subtext 1")
            ?? textHex

        let selectedHex = palette.hex(for: "Lavender")
            ?? palette.hex(for: "Blue")
            ?? accentHex

        let dangerHex = palette.hex(for: "Red")
            ?? palette.hex(for: "Pink")
            ?? accentHex

        let monitorBackgroundHex = palette.hex(for: "Crust")
            ?? palette.hex(for: "Background")
            ?? backgroundHex

        let borderHex = palette.hex(for: "Surface 2")
            ?? palette.hex(for: "Overlay 0")
            ?? panelBackgroundHex

        self.init(
            id: palette.id,
            name: palette.name,
            appearance: AppThemeAppearance(palette.appearance),
            backgroundHex: backgroundHex,
            panelBackgroundHex: panelBackgroundHex,
            textHex: textHex,
            secondaryTextHex: secondaryTextHex,
            accentHex: accentHex,
            selectedHex: selectedHex,
            dangerHex: dangerHex,
            monitorBackgroundHex: monitorBackgroundHex,
            borderHex: borderHex
        )
    }
}

enum AppThemeAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    init(_ appearance: ThemeSwatches.Appearance) {
        switch appearance {
        case .system: self = .system
        case .light: self = .light
        case .dark: self = .dark
        }
    }
}

// MARK: - Built-in presets (sourced from shared swatches)

extension AppTheme {
    static var allBuiltIns: [AppTheme] {
        ThemeSwatches.allPalettes.compactMap(AppTheme.init(palette:))
    }

    static var `default`: AppTheme {
        allBuiltIns.first { $0.id == "system-default" }
            ?? allBuiltIns.first
            ?? AppTheme(
                id: "fallback",
                name: "Fallback",
                appearance: .dark,
                backgroundHex: "1E1E2EFF",
                panelBackgroundHex: "313244FF",
                textHex: "CDD6F4FF",
                secondaryTextHex: "A6ADC8FF",
                accentHex: "89B4FAFF",
                selectedHex: "B4BEFEFF",
                dangerHex: "F38BA8FF",
                monitorBackgroundHex: "11111BFF",
                borderHex: "45475AFF"
            )
    }
}

// MARK: - ThemeSwatches helpers

private extension ThemeSwatches.Palette {
    /// Return the hex value of the first swatch whose name matches exactly,
    /// case-insensitively.
    func hex(for name: String) -> String? {
        swatches.first { swatch in
            swatch.names.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
        }?.hex
    }
}
