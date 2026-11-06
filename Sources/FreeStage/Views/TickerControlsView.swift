//
//  TickerControlsView.swift
//  FreeStage
//
//  Inspector controls for a scrolling ticker template layer.
//

import SwiftUI

struct TickerControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var newItem = ""

    var body: some View {
        GroupBox("Ticker") {
            VStack(alignment: .leading, spacing: 12) {
                itemsList

                HStack {
                    TextField("New item", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        guard !newItem.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        store.updateSelectedLayer { layer in
                            guard case .ticker(var ticker) = layer.source else { return }
                            ticker.items.append(newItem.trimmingCharacters(in: .whitespaces))
                            layer.source = .ticker(ticker)
                        }
                        newItem = ""
                    }
                    .controlSize(.small)
                }

                textField("Separator", binding: separatorBinding)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed: \(Int(store.selectedLayerTicker?.speed ?? 120)) px/s")
                        .font(.caption2)
                    Slider(value: speedBinding, in: 20...600, step: 10)
                }

                HStack(spacing: 16) {
                    fontSizeControl
                    heightControl
                }

                HStack(spacing: 16) {
                    colorRow("Text", binding: textColorBinding)
                    colorRow("Background", binding: backgroundColorBinding)
                }

                Picker("Direction", selection: directionBinding) {
                    ForEach(TickerDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Position", selection: verticalPositionBinding) {
                    ForEach(TickerVerticalPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                AnimationControlsView()
            }
        }
        .padding([.horizontal, .top])
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Items")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array((store.selectedLayerTicker?.items ?? []).enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            store.updateSelectedLayer { layer in
                                guard case .ticker(var ticker) = layer.source else { return }
                                ticker.items.remove(at: index)
                                layer.source = .ticker(ticker)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 120)
            .environment(\.defaultMinListRowHeight, 22)
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

    private var fontSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Size: \(Int(store.selectedLayerTicker?.fontSize ?? 28))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...80, step: 1)
        }
    }

    private var heightControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Height: \(Int(store.selectedLayerTicker?.height ?? 48))")
                .font(.caption2)
            Slider(value: heightBinding, in: 20...120, step: 1)
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

    private var separatorBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerTicker?.separator ?? "   •   " },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.separator = newValue
                    layer.source = .ticker(ticker)
                }
            }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerTicker?.speed ?? 120 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.speed = newValue
                    layer.source = .ticker(ticker)
                }
            }
        )
    }

    private var directionBinding: Binding<TickerDirection> {
        Binding(
            get: { store.selectedLayerTicker?.direction ?? .left },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.direction = newValue
                    layer.source = .ticker(ticker)
                }
            }
        )
    }

    private var verticalPositionBinding: Binding<TickerVerticalPosition> {
        Binding(
            get: { store.selectedLayerTicker?.verticalPosition ?? .bottom },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.verticalPosition = newValue
                    layer.source = .ticker(ticker)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerTicker?.fontSize ?? 28 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.fontSize = newValue
                    layer.source = .ticker(ticker)
                }
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerTicker?.height ?? 48 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    ticker.height = newValue
                    layer.source = .ticker(ticker)
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

    private func colorBinding(for keyPath: KeyPath<TickerSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerTicker else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .ticker(var ticker) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: ticker.textColor = components
                    case \.backgroundColor: ticker.backgroundColor = components
                    default: break
                    }
                    layer.source = .ticker(ticker)
                }
            }
        )
    }
}
