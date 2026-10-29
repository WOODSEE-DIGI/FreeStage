//
//  TextControlsView.swift
//  FreeStage
//
//  Inspector controls for a text layer: content, font size, color, and
//  background color.
//

import SwiftUI

struct TextControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Text") {
            VStack(alignment: .leading, spacing: 12) {
                textField

                HStack(spacing: 16) {
                    fontSizeControl
                    colorPicker
                    backgroundColorPicker
                }
            }
        }
        .padding([.horizontal, .top])
    }

    private var textField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Content")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: contentBinding)
                .font(.body)
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var fontSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Size: \(Int(store.selectedLayerText?.fontSize ?? 48))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...200, step: 1)
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 6) {
            Text("Color")
            ColorPicker("", selection: colorBinding)
                .labelsHidden()
        }
    }

    private var backgroundColorPicker: some View {
        HStack(spacing: 6) {
            Text("Background")
            ColorPicker("", selection: backgroundColorBinding)
                .labelsHidden()
        }
    }

    private var contentBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerText?.content ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .text(var textSource) = layer.source else { return }
                    textSource.content = newValue
                    layer.source = .text(textSource)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerText?.fontSize ?? 48 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .text(var textSource) = layer.source else { return }
                    textSource.fontSize = newValue
                    layer.source = .text(textSource)
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerText else { return .black }
                return Color(rgb: RGBColor(r: source.color.r, g: source.color.g, b: source.color.b))
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                store.updateSelectedLayer { layer in
                    guard case .text(var textSource) = layer.source else { return }
                    textSource.color = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: 1.0)
                    layer.source = .text(textSource)
                }
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerText,
                      let bg = source.backgroundColor else { return Color.clear }
                return Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .text(var textSource) = layer.source else { return }
                    textSource.backgroundColor = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    layer.source = .text(textSource)
                }
            }
        )
    }
}
