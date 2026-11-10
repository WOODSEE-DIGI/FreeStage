//
//  ChromaKeyControlsView.swift
//  FreeStage
//
//  Reusable chroma-key controls (key colors, tuning sliders, background picker).
//  Embedded directly in the layer inspector as a first-class toggle so users
//  don't have to dig through the Add Filter sub-menu.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let chromaKeyLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "ChromaKey")

/// Full chroma-key editor bound to the selected layer's chroma-key filter.
/// Assumes the filter already exists on the layer (call
/// `store.setSelectedLayerChromaKeyEnabled(true)` first).
struct ChromaKeyControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var isPickingBackground = false
    @State private var isPickingSlideshow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let filter = store.selectedLayerChromaKey {
                controls(for: filter)
            } else {
                Text("Enable Chroma Key above to adjust settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Keep the controls visible and editable for camera layers even
            // when chroma key has never been turned on.
            store.ensureSelectedLayerChromaKeyFilter()
        }
        .fileImporter(
            isPresented: $isPickingBackground,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    chromaKeyLogger.warning("fileImporter returned empty URL list")
                    return
                }
                chromaKeyLogger.info("fileImporter picked: \(url.path)")
                let source: Source
                if let type = UTType(filenameExtension: url.pathExtension),
                   type.conforms(to: .image) {
                    source = .image(url: url)
                } else {
                    source = .media(url: url)
                }
                store.updateSelectedLayerChromaKey { $0.backgroundSource = source }
                chromaKeyLogger.info("Background set to \(source.defaultName)")
            case .failure(let error):
                chromaKeyLogger.error("fileImporter failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $isPickingSlideshow) {
            SlideshowPickerSheet { slideshow in
                store.updateSelectedLayerChromaKey { $0.backgroundSource = .slideshow(slideshow) }
            }
        }
    }

    @ViewBuilder
    private func controls(for filter: ChromaKeyFilter) -> some View {
        if !filter.isEnabled {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Chroma Key is disabled. Enable it above to see the effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }

        HStack {
            Text("A / B")
                .font(.caption)
            Toggle("Bypass key for comparison", isOn: Binding(
                get: { filter.bypass },
                set: { newValue in store.updateSelectedLayerChromaKey { $0.bypass = newValue } }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Temporarily disable the key to compare against the original source.")

            Spacer()
        }

        keyColorSection(filter: filter)

        AdjustmentSlider("Threshold", value: filter.threshold, range: 0...1, defaultValue: 0.35) { newValue in
            store.updateSelectedLayerChromaKey { $0.threshold = newValue }
        }
        AdjustmentSlider("Smoothing", value: filter.smoothing, range: 0...0.5, defaultValue: 0.08) { newValue in
            store.updateSelectedLayerChromaKey { $0.smoothing = newValue }
        }
        AdjustmentSlider("Edge Feather", value: filter.edgeFeather, range: 0...0.5, defaultValue: 0.0) { newValue in
            store.updateSelectedLayerChromaKey { $0.edgeFeather = newValue }
        }
        AdjustmentSlider("Edge Despill", value: filter.edgeDespill, range: 0...2, defaultValue: 0.5) { newValue in
            store.updateSelectedLayerChromaKey { $0.edgeDespill = newValue }
        }
        AdjustmentSlider("Spill Supp.", value: filter.spillSuppression, range: 0...2, defaultValue: 0.5) { newValue in
            store.updateSelectedLayerChromaKey { $0.spillSuppression = newValue }
        }
        AdjustmentSlider("Spill Range", value: filter.spillRange, range: 0...1, defaultValue: 0.25) { newValue in
            store.updateSelectedLayerChromaKey { $0.spillRange = newValue }
        }
        AdjustmentSlider("Skin Protect", value: filter.skinToneProtection, range: 0...1, defaultValue: 0.3) { newValue in
            store.updateSelectedLayerChromaKey { $0.skinToneProtection = newValue }
        }

        Divider()

        backgroundSection(filter: filter)
    }

    @ViewBuilder
    private func keyColorSection(filter: ChromaKeyFilter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Key Colors")
                    .font(.caption)
                Spacer()
                Text("\(filter.keyColors.count)/4")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(0..<filter.keyColors.count, id: \.self) { index in
                HStack {
                    Text("Color \(index + 1)")
                        .font(.caption2)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(rgb: filter.keyColors[index]) },
                        set: { newColor in
                            let rgb = RGBColor(color: newColor)
                            store.updateSelectedLayerChromaKey { filter in
                                guard index < filter.keyColors.count else { return }
                                filter.keyColors[index] = rgb
                            }
                        }
                    ))
                    .labelsHidden()
                    .frame(width: 44)

                    if filter.keyColors.count > 1 {
                        Button {
                            store.updateSelectedLayerChromaKey { filter in
                                guard index < filter.keyColors.count else { return }
                                filter.keyColors.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this key color")
                    }
                }
            }

            if filter.keyColors.count < 4 {
                Button {
                    store.updateSelectedLayerChromaKey { filter in
                        let base = filter.keyColors.first ?? RGBColor(r: 0, g: 1, b: 0)
                        filter.keyColors.append(base)
                    }
                } label: {
                    Label("Add Key Color", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }

            Text("Add extra colors to sample green-screen highlights and shadows.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func backgroundSection(filter: ChromaKeyFilter) -> some View {
        HStack {
            Text("Background")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)

        if let source = filter.backgroundSource {
            HStack {
                Text(source.defaultName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Clear") {
                    store.updateSelectedLayerChromaKey { $0.backgroundSource = nil }
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        } else {
            HStack(spacing: 8) {
                Button {
                    isPickingBackground = true
                } label: {
                    Label("Image/Video…", systemImage: "photo")
                }
                .font(.caption)

                Button {
                    isPickingSlideshow = true
                } label: {
                    Label("Slideshow…", systemImage: "photo.stack")
                }
                .font(.caption)
            }
        }

        Text("When no background is chosen, the keyed area is transparent.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Color helpers

extension Color {
    init(rgb: RGBColor) {
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension RGBColor {
    init(color: Color) {
        let cg = color.cgColor ?? CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let components = cg.components ?? [0, 1, 0, 1]
        self.r = Double(components[0])
        self.g = Double(components[1])
        self.b = Double(components[2])
    }
}
