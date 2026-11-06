//
//  LogoBugControlsView.swift
//  FreeStage
//
//  Inspector controls for a logo/brand bug template layer.
//

import SwiftUI

struct LogoBugControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Logo Bug") {
            VStack(alignment: .leading, spacing: 12) {
                textField("Text", binding: textBinding)

                fontSizeControl

                HStack(spacing: 16) {
                    colorRow("Text", binding: textColorBinding)
                    colorRow("Background", binding: backgroundColorBinding)
                }

                HStack(spacing: 16) {
                    cornerRadiusControl
                    paddingControl
                }

                Picker("Position", selection: positionBinding) {
                    ForEach(TemplateBugPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                AnimationControlsView()
            }
        }
        .padding([.horizontal, .top])
    }

    private func textField(_ label: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var fontSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Size: \(Int(store.selectedLayerLogoBug?.fontSize ?? 28))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...80, step: 1)
        }
    }

    private var cornerRadiusControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Radius: \(Int(store.selectedLayerLogoBug?.cornerRadius ?? 8))")
                .font(.caption2)
            Slider(value: cornerRadiusBinding, in: 0...40, step: 1)
        }
    }

    private var paddingControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Padding: \(Int(store.selectedLayerLogoBug?.padding ?? 14))")
                .font(.caption2)
            Slider(value: paddingBinding, in: 0...40, step: 1)
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

    private var textBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerLogoBug?.text ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    bug.text = newValue
                    layer.source = .logoBug(bug)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerLogoBug?.fontSize ?? 28 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    bug.fontSize = newValue
                    layer.source = .logoBug(bug)
                }
            }
        )
    }

    private var textColorBinding: Binding<Color> {
        colorBinding(for: \.textColor)
    }

    private var backgroundColorBinding: Binding<Color> {
        colorBinding(for: \.backgroundColor)
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerLogoBug?.cornerRadius ?? 8 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    bug.cornerRadius = newValue
                    layer.source = .logoBug(bug)
                }
            }
        )
    }

    private var paddingBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerLogoBug?.padding ?? 14 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    bug.padding = newValue
                    layer.source = .logoBug(bug)
                }
            }
        )
    }

    private var positionBinding: Binding<TemplateBugPosition> {
        Binding(
            get: { store.selectedLayerLogoBug?.position ?? .topLeft },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    bug.position = newValue
                    layer.source = .logoBug(bug)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<LogoBugSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerLogoBug else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .logoBug(var bug) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: bug.textColor = components
                    case \.backgroundColor: bug.backgroundColor = components
                    default: break
                    }
                    layer.source = .logoBug(bug)
                }
            }
        )
    }
}
