//
//  ChapterMarkerControlsView.swift
//  FreeStage
//
//  Inspector controls for a chapter-marker template layer.
//

import SwiftUI

struct ChapterMarkerControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Chapter Marker") {
            VStack(alignment: .leading, spacing: 12) {
                textField("Number", binding: numberBinding)
                textField("Title", binding: titleBinding)

                fontSizeControl

                HStack(spacing: 16) {
                    colorRow("Text", binding: textColorBinding)
                    colorRow("Accent", binding: accentColorBinding)
                }

                colorRow("Background", binding: backgroundColorBinding)

                Toggle("Show Progress Bar", isOn: showProgressBarBinding)

                if store.selectedLayerChapterMarker?.showProgressBar == true {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Progress: \(Int((store.selectedLayerChapterMarker?.progress ?? 0) * 100))%")
                            .font(.caption2)
                        Slider(value: progressBinding, in: 0...1, step: 0.01)
                    }
                }

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
            Text("Size: \(Int(store.selectedLayerChapterMarker?.fontSize ?? 42))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...120, step: 1)
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

    private var numberBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerChapterMarker?.chapterNumber ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    cm.chapterNumber = newValue
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.selectedLayerChapterMarker?.title ?? "" },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    cm.title = newValue
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerChapterMarker?.fontSize ?? 42 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    cm.fontSize = newValue
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }

    private var textColorBinding: Binding<Color> {
        colorBinding(for: \.textColor)
    }

    private var accentColorBinding: Binding<Color> {
        colorBinding(for: \.accentColor)
    }

    private var backgroundColorBinding: Binding<Color> {
        colorBinding(for: \.backgroundColor)
    }

    private var showProgressBarBinding: Binding<Bool> {
        Binding(
            get: { store.selectedLayerChapterMarker?.showProgressBar ?? true },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    cm.showProgressBar = newValue
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerChapterMarker?.progress ?? 0 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    cm.progress = newValue
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<ChapterMarkerSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerChapterMarker else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .chapterMarker(var cm) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: cm.textColor = components
                    case \.accentColor: cm.accentColor = components
                    case \.backgroundColor: cm.backgroundColor = components
                    default: break
                    }
                    layer.source = .chapterMarker(cm)
                }
            }
        )
    }
}
