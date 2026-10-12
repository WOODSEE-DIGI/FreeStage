//
//  ChromaKeyControlsView.swift
//  FreeStage
//
//  Reusable chroma-key controls (key color, tuning sliders, background picker).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let filter = store.selectedLayerChromaKey {
                controls(for: filter)
            } else {
                Text("Chroma key is off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    }

    @ViewBuilder
    private func controls(for filter: ChromaKeyFilter) -> some View {
        HStack {
            Text("Key Color")
                .font(.caption)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(rgb: filter.keyColor) },
                set: { newColor in
                    let rgb = RGBColor(color: newColor)
                    store.updateSelectedLayerChromaKey { $0.keyColor = rgb }
                }
            ))
            .labelsHidden()
            .frame(width: 60)
        }

        slider("Threshold", value: filter.threshold, range: 0...1) { newValue in
            store.updateSelectedLayerChromaKey { $0.threshold = newValue }
        }
        slider("Smoothing", value: filter.smoothing, range: 0...0.5) { newValue in
            store.updateSelectedLayerChromaKey { $0.smoothing = newValue }
        }
        slider("Edge Feather", value: filter.edgeFeather, range: 0...0.5) { newValue in
            store.updateSelectedLayerChromaKey { $0.edgeFeather = newValue }
        }
        slider("Spill Supp.", value: filter.spillSuppression, range: 0...2) { newValue in
            store.updateSelectedLayerChromaKey { $0.spillSuppression = newValue }
        }
        slider("Spill Range", value: filter.spillRange, range: 0...1) { newValue in
            store.updateSelectedLayerChromaKey { $0.spillRange = newValue }
        }

        Divider()

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
            Button {
                isPickingBackground = true
            } label: {
                Label("Choose Image or Video…", systemImage: "photo")
            }
            .font(.caption)
        }

        Text("When no background is chosen, the keyed area is transparent.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func slider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 90, alignment: .leading)
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range)
            Text("\(value, specifier: "%.2f")")
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
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
