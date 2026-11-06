//
//  LowerThirdControlsView.swift
//  FreeStage
//
//  Inspector controls for a lower-third template layer.
//

import SwiftUI

struct LowerThirdControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Lower Third") {
            VStack(alignment: .leading, spacing: 12) {
                textField("Title", binding: titleBinding)
                textField("Subtitle", binding: subtitleBinding)

                HStack(spacing: 16) {
                    fontSizeControl("Title", value: titleFontSizeBinding)
                    fontSizeControl("Subtitle", value: subtitleFontSizeBinding)
                }

                HStack(spacing: 16) {
                    colorRow("Title", binding: titleColorBinding)
                    colorRow("Subtitle", binding: subtitleColorBinding)
                }

                Picker("Fill Style", selection: fillStyleBinding) {
                    ForEach(TemplateFillStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                if store.selectedLayerLowerThird?.fillStyle == .solid {
                    colorRow("Background", binding: backgroundColorBinding)
                } else {
                    colorRow("Start", binding: gradientStartBinding)
                    colorRow("End", binding: gradientEndBinding)
                }

                Picker("Alignment", selection: alignmentBinding) {
                    ForEach(TemplateTextAlignment.allCases) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
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

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerLowerThird?.title ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.title = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerLowerThird?.subtitle ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.subtitle = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }

    private var titleFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerLowerThird?.titleFontSize ?? 48 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.titleFontSize = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }

    private var subtitleFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerLowerThird?.subtitleFontSize ?? 28 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.subtitleFontSize = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
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
            get: { store.selectedLayerLowerThird?.fillStyle ?? .solid },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.fillStyle = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }

    private var alignmentBinding: Binding<TemplateTextAlignment> {
        Binding(
            get: { store.selectedLayerLowerThird?.alignment ?? .left },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    lt.alignment = newValue
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<LowerThirdSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerLowerThird else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .lowerThird(var lt) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.titleColor: lt.titleColor = components
                    case \.subtitleColor: lt.subtitleColor = components
                    case \.backgroundColor: lt.backgroundColor = components
                    case \.gradientStartColor: lt.gradientStartColor = components
                    case \.gradientEndColor: lt.gradientEndColor = components
                    default: break
                    }
                    layer.source = .lowerThird(lt)
                }
            }
        )
    }
}
