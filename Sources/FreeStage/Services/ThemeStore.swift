//
//  ThemeStore.swift
//  FreeStage
//
//  User-selectable UI theme for the FreeStage application chrome. The store
//  is injected into the SwiftUI environment so every panel reads from the
//  same source of truth.
//

import SwiftUI
import AppKit

/// Central colour palette for the FreeStage application chrome.
///
/// The store reads the user's chosen theme from `AppSettings.appThemeID` and
/// exposes semantic colours that views use instead of hard-coded system
/// colours. Presets are sourced from the shared ThemeSwatches library so
/// FreeStage stays consistent with the rest of the app suite.
@Observable
@MainActor
final class ThemeStore {
    static let defaultThemeID = AppTheme.default.id

    /// All available themes. Built-ins come from the shared swatch collection;
    /// user themes can be appended here in the future.
    let themes: [AppTheme] = AppTheme.allBuiltIns

    /// The currently selected theme identifier. Changes are persisted through
    /// `AppSettings` and the macOS appearance is updated immediately.
    var selectedThemeID: String {
        didSet {
            settings?.appThemeID = selectedThemeID
            applyAppAppearance()
        }
    }

    private weak var settings: AppSettings?

    /// Returns the selected theme, falling back to the default if the saved
    /// identifier no longer matches any theme.
    var currentTheme: AppTheme {
        themes.first { $0.id == selectedThemeID } ?? AppTheme.default
    }

    /// Create a store bound to the supplied settings object.
    init(settings: AppSettings? = nil) {
        self.settings = settings
        self.selectedThemeID = settings?.appThemeID ?? Self.defaultThemeID
    }

    /// Apply the current theme's appearance to `NSApp`. Call once the app
    /// lifecycle has started (e.g. from a view `.task`).
    func applyInitialAppearance() {
        applyAppAppearance()
    }

    private func applyAppAppearance() {
        NSApp.appearance = currentTheme.appearance.nsAppearance
    }

    // MARK: - Semantic colours

    var background:      Color { Color(hex: currentTheme.backgroundHex) }
    var panelBackground: Color { Color(hex: currentTheme.panelBackgroundHex) }
    var text:            Color { Color(hex: currentTheme.textHex) }
    var secondaryText:   Color { Color(hex: currentTheme.secondaryTextHex) }
    var accent:          Color { Color(hex: currentTheme.accentHex) }
    var selected:        Color { Color(hex: currentTheme.selectedHex) }
    var danger:          Color { Color(hex: currentTheme.dangerHex) }
    var monitorBackground: Color { Color(hex: currentTheme.monitorBackgroundHex) }
    var border:          Color { Color(hex: currentTheme.borderHex) }

    // MARK: - Bindings

    var selectedThemeIDBinding: Binding<String> {
        Binding(
            get: { self.selectedThemeID },
            set: { self.selectedThemeID = $0 }
        )
    }
}
