//
//  CountdownTimerControlsView.swift
//  FreeStage
//
//  Inspector controls for a countdown timer template layer.
//

import SwiftUI

struct CountdownTimerControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Countdown Timer") {
            VStack(alignment: .leading, spacing: 12) {
                targetDateControl

                textField("Label", binding: labelBinding)

                HStack(spacing: 16) {
                    fontSizeControl("Timer", value: fontSizeBinding)
                    fontSizeControl("Label", value: labelFontSizeBinding)
                }

                HStack(spacing: 16) {
                    colorRow("Text", binding: textColorBinding)
                    colorRow("Background", binding: backgroundColorBinding)
                }

                Toggle("Show Seconds", isOn: showSecondsBinding)

                Picker("Alignment", selection: alignmentBinding) {
                    ForEach(TemplateTextAlignment.allCases) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)

                AnimationControlsView()
            }
        }
        .padding([.horizontal, .top])
    }

    private var targetDateControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Target Time")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker(
                "",
                selection: targetDateBinding,
                displayedComponents: [.hourAndMinute, .date]
            )
            .labelsHidden()
        }
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

    private var targetDateBinding: Binding<Date> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.targetDate ?? Date().addingTimeInterval(300) },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.targetDate = newValue
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.label ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.label = newValue
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.fontSize ?? 64 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.fontSize = newValue
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }

    private var labelFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.labelFontSize ?? 24 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.labelFontSize = newValue
                    layer.source = .countdownTimer(timer)
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

    private var showSecondsBinding: Binding<Bool> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.showSeconds ?? true },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.showSeconds = newValue
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }

    private var alignmentBinding: Binding<TemplateTextAlignment> {
        Binding(
            get: { store.selectedLayerCountdownTimer?.alignment ?? .center },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    timer.alignment = newValue
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<CountdownTimerSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerCountdownTimer else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .countdownTimer(var timer) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: timer.textColor = components
                    case \.backgroundColor: timer.backgroundColor = components
                    default: break
                    }
                    layer.source = .countdownTimer(timer)
                }
            }
        )
    }
}
