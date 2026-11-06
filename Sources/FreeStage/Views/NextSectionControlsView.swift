//
//  NextSectionControlsView.swift
//  FreeStage
//
//  Inspector controls for a next-section / coming-up template layer.
//

import SwiftUI

struct NextSectionControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Next Section") {
            VStack(alignment: .leading, spacing: 12) {
                textField("Label", binding: labelBinding)
                textField("Title", binding: titleBinding)
                textField("Subtitle", binding: subtitleBinding)

                HStack(spacing: 16) {
                    fontSizeControl("Label", value: labelFontSizeBinding)
                    fontSizeControl("Title", value: titleFontSizeBinding)
                    fontSizeControl("Subtitle", value: subtitleFontSizeBinding)
                }

                HStack(spacing: 16) {
                    colorRow("Label", binding: labelColorBinding)
                    colorRow("Title", binding: titleColorBinding)
                    colorRow("Subtitle", binding: subtitleColorBinding)
                }

                Picker("Fill Style", selection: fillStyleBinding) {
                    ForEach(TemplateFillStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if store.selectedLayerNextSection?.fillStyle == .solid {
                    colorRow("Background", binding: backgroundColorBinding)
                } else {
                    colorRow("Start", binding: gradientStartBinding)
                    colorRow("End", binding: gradientEndBinding)
                }
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

    private func fontSizeControl(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(Int(value.wrappedValue))")
                .font(.caption2)
            Slider(value: value, in: 8...120, step: 1)
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

    private var labelBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerNextSection?.label ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.label = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerNextSection?.title ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.title = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerNextSection?.subtitle ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.subtitle = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var labelFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerNextSection?.labelFontSize ?? 18 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.labelFontSize = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var titleFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerNextSection?.titleFontSize ?? 44 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.titleFontSize = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var subtitleFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerNextSection?.subtitleFontSize ?? 24 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.subtitleFontSize = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private var labelColorBinding: Binding<Color> {
        colorBinding(for: \.labelColor)
    }

    private var titleColorBinding: Binding<Color> {
        colorBinding(for: \.titleColor)
    }

    private var subtitleColorBinding: Binding<Color> {
        colorBinding(for: \.subtitleColor)
    }

    private var backgroundColorBinding: Binding<Color> {
        colorBinding(for: \.backgroundColor)
    }

    private var gradientStartBinding: Binding<Color> {
        colorBinding(for: \.gradientStartColor)
    }

    private var gradientEndBinding: Binding<Color> {
        colorBinding(for: \.gradientEndColor)
    }

    private var fillStyleBinding: Binding<TemplateFillStyle> {
        Binding(
            get: { store.selectedLayerNextSection?.fillStyle ?? .gradient },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    ns.fillStyle = newValue
                    layer.source = .nextSection(ns)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<NextSectionSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerNextSection else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .nextSection(var ns) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.labelColor: ns.labelColor = components
                    case \.titleColor: ns.titleColor = components
                    case \.subtitleColor: ns.subtitleColor = components
                    case \.backgroundColor: ns.backgroundColor = components
                    case \.gradientStartColor: ns.gradientStartColor = components
                    case \.gradientEndColor: ns.gradientEndColor = components
                    default: break
                    }
                    layer.source = .nextSection(ns)
                }
            }
        )
    }
}
