//
//  SocialBugControlsView.swift
//  FreeStage
//
//  Inspector controls for a social-handle bug template layer.
//

import SwiftUI

struct SocialBugControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Social Bug") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Platform", selection: platformBinding) {
                    ForEach(SocialPlatform.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                .pickerStyle(.menu)

                textField("Handle", binding: handleBinding)
                textField("Label", binding: labelBinding)

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
            Text("Size: \(Int(store.selectedLayerSocialBug?.fontSize ?? 24))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...80, step: 1)
        }
    }

    private var cornerRadiusControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Radius: \(Int(store.selectedLayerSocialBug?.cornerRadius ?? 8))")
                .font(.caption2)
            Slider(value: cornerRadiusBinding, in: 0...40, step: 1)
        }
    }

    private var paddingControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Padding: \(Int(store.selectedLayerSocialBug?.padding ?? 12))")
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

    private var platformBinding: Binding<SocialPlatform> {
        Binding(
            get: { store.selectedLayerSocialBug?.platform ?? .twitter },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.platform = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private var handleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerSocialBug?.handle ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.handle = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerSocialBug?.label ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.label = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerSocialBug?.fontSize ?? 24 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.fontSize = newValue
                    layer.source = .socialBug(bug)
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
            get: { store.selectedLayerSocialBug?.cornerRadius ?? 8 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.cornerRadius = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private var paddingBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerSocialBug?.padding ?? 12 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.padding = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private var positionBinding: Binding<TemplateBugPosition> {
        Binding(
            get: { store.selectedLayerSocialBug?.position ?? .topRight },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    bug.position = newValue
                    layer.source = .socialBug(bug)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<SocialBugSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerSocialBug else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .socialBug(var bug) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: bug.textColor = components
                    case \.backgroundColor: bug.backgroundColor = components
                    default: break
                    }
                    layer.source = .socialBug(bug)
                }
            }
        )
    }
}
