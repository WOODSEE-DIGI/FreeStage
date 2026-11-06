//
//  BorderControlsView.swift
//  FreeStage
//
//  Inspector controls for a border template layer: thickness, corner radius,
//  fill style, color/gradient, and center fill.
//

import SwiftUI

struct BorderControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Border") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    thicknessControl
                    cornerRadiusControl
                }

                Picker("Fill Style", selection: fillStyleBinding) {
                    ForEach(TemplateFillStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if store.selectedLayerBorder?.fillStyle == .solid {
                    colorRow("Color", binding: colorBinding)
                } else {
                    colorRow("Start", binding: gradientStartBinding)
                    colorRow("End", binding: gradientEndBinding)
                    gradientAngleControl
                }

                Toggle("Fill Center", isOn: fillCenterBinding)

                if store.selectedLayerBorder?.fillCenter == true {
                    colorRow("Fill Color", binding: fillColorBinding)
                }
            }
        }
        .padding([.horizontal, .top])
    }

    private var thicknessControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Thickness: \(Int(store.selectedLayerBorder?.thickness ?? 8))")
                .font(.caption2)
            Slider(value: thicknessBinding, in: 1...80, step: 1)
        }
    }

    private var cornerRadiusControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Radius: \(Int(store.selectedLayerBorder?.cornerRadius ?? 0))")
                .font(.caption2)
            Slider(value: cornerRadiusBinding, in: 0...200, step: 1)
        }
    }

    private var gradientAngleControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Angle: \(Int(store.selectedLayerBorder?.gradientAngle ?? 0))°")
                .font(.caption2)
            Slider(value: gradientAngleBinding, in: 0...360, step: 1)
        }
    }

    private func colorRow(_ label: String, binding: Binding<Color>) -> some View {
        HStack(spacing: 6) {
            Text(label)
            ColorPicker("", selection: binding)
                .labelsHidden()
            Spacer()
        }
    }

    private var thicknessBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerBorder?.thickness ?? 8 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    border.thickness = newValue
                    layer.source = .border(border)
                }
            }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerBorder?.cornerRadius ?? 0 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    border.cornerRadius = newValue
                    layer.source = .border(border)
                }
            }
        )
    }

    private var fillStyleBinding: Binding<TemplateFillStyle> {
        Binding(
            get: { store.selectedLayerBorder?.fillStyle ?? .solid },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    border.fillStyle = newValue
                    layer.source = .border(border)
                }
            }
        )
    }

    private var fillCenterBinding: Binding<Bool> {
        Binding(
            get: { store.selectedLayerBorder?.fillCenter ?? false },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    border.fillCenter = newValue
                    layer.source = .border(border)
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        colorBinding(for: \.color)
    }

    private var gradientStartBinding: Binding<Color> {
        colorBinding(for: \.gradientStartColor)
    }

    private var gradientEndBinding: Binding<Color> {
        colorBinding(for: \.gradientEndColor)
    }

    private var fillColorBinding: Binding<Color> {
        colorBinding(for: \.fillColor)
    }

    private var gradientAngleBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerBorder?.gradientAngle ?? 0 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    border.gradientAngle = newValue
                    layer.source = .border(border)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<BorderSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let border = store.selectedLayerBorder else { return .white }
                let components = border[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .border(var border) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.color: border.color = components
                    case \.gradientStartColor: border.gradientStartColor = components
                    case \.gradientEndColor: border.gradientEndColor = components
                    case \.fillColor: border.fillColor = components
                    default: break
                    }
                    layer.source = .border(border)
                }
            }
        )
    }
}
