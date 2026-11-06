//
//  ImageLogoBugControlsView.swift
//  FreeStage
//
//  Inspector controls for an image-based logo/brand bug template layer.
//

import SwiftUI

struct ImageLogoBugControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var showingImagePicker = false

    var body: some View {
        GroupBox("Image Logo Bug") {
            VStack(alignment: .leading, spacing: 12) {
                imagePreview

                HStack {
                    Button("Choose Image…") {
                        showingImagePicker = true
                    }
                    .controlSize(.small)

                    if store.selectedLayerImageLogoBug?.imageURL != nil {
                        Button("Clear") {
                            store.updateSelectedLayer { layer in
                                guard case .imageLogoBug(var bug) = layer.source else { return }
                                bug.imageURL = nil
                                layer.source = .imageLogoBug(bug)
                            }
                        }
                        .controlSize(.small)
                    }

                    Spacer()
                }

                widthControl

                Picker("Position", selection: positionBinding) {
                    ForEach(TemplateBugPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 16) {
                    cornerRadiusControl
                    paddingControl
                }

                colorRow("Background", binding: backgroundColorBinding)

                AnimationControlsView()
            }
        }
        .padding([.horizontal, .top])
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerSheet(selectedURL: imageURLBinding)
        }
    }

    private var imagePreview: some View {
        HStack {
            Spacer()
            if let url = store.selectedLayerImageLogoBug?.imageURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No image selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 60)
            }
            Spacer()
        }
    }

    private var widthControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Width: \(Int(store.selectedLayerImageLogoBug?.width ?? 200))")
                .font(.caption2)
            Slider(value: widthBinding, in: 50...600, step: 10)
        }
    }

    private var cornerRadiusControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Radius: \(Int(store.selectedLayerImageLogoBug?.cornerRadius ?? 8))")
                .font(.caption2)
            Slider(value: cornerRadiusBinding, in: 0...40, step: 1)
        }
    }

    private var paddingControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Padding: \(Int(store.selectedLayerImageLogoBug?.padding ?? 0))")
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

    private var imageURLBinding: Binding<URL?> {
        Binding(
            get: { store.selectedLayerImageLogoBug?.imageURL },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.imageURL = newValue
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerImageLogoBug?.width ?? 200 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.width = newValue
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }

    private var positionBinding: Binding<TemplateBugPosition> {
        Binding(
            get: { store.selectedLayerImageLogoBug?.position ?? .topRight },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.position = newValue
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerImageLogoBug?.cornerRadius ?? 8 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.cornerRadius = newValue
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }

    private var paddingBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerImageLogoBug?.padding ?? 0 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.padding = newValue
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerImageLogoBug else { return Color.clear }
                let bg = source.backgroundColor
                return Color(red: bg.r, green: bg.g, blue: bg.b, opacity: bg.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .imageLogoBug(var bug) = layer.source else { return }
                    bug.backgroundColor = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    layer.source = .imageLogoBug(bug)
                }
            }
        )
    }
}

/// Minimal image file picker sheet.
private struct ImagePickerSheet: View {
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Logo Image")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .image]
                    panel.begin { result in
                        guard result == .OK, let url = panel.url else { return }
                        selectedURL = url
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
