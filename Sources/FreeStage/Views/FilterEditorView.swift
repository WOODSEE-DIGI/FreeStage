//
//  FilterEditorView.swift
//  FreeStage
//
//  Inspector panel for adding, removing, and editing per-layer video filters.
//

import SwiftUI
import UniformTypeIdentifiers
import OSLog

private let filterLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "FilterEditor")

struct FilterEditorView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Video Filters") {
            VStack(alignment: .leading, spacing: 8) {
                filterList
                addFilterMenu
            }
        }
        .padding([.horizontal, .bottom])
    }

    private var filterList: some View {
        VStack(alignment: .leading, spacing: 10) {
            let visibleFilters = (store.selectedLayer?.filters ?? []).filter {
                if case .chromaKey = $0 { return false }
                return true
            }
            if !visibleFilters.isEmpty {
                ForEach(visibleFilters) { filter in
                    FilterRowView(filter: filter)
                }
            } else {
                Text("No filters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addFilterMenu: some View {
        Menu {
            Button("Color Correction") {
                store.addFilterToSelectedLayer(.colorCorrection(ColorCorrectionFilter()))
            }
            Button("Crop") {
                store.addFilterToSelectedLayer(.crop(CropFilter()))
            }
        } label: {
            Label("Add Filter", systemImage: "plus")
                .font(.caption)
        }
        .disabled(store.selectedLayer == nil)
    }
}

struct FilterRowView: View {
    @Environment(ShowStore.self) private var store
    @State private var isPickingBackground = false
    let filter: Filter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(filter.displayName)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    store.removeFilterFromSelectedLayer(id: filter.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            switch filter {
            case .chromaKey(let f):
                chromaKeyControls(filterID: filter.id, filter: f)
            case .colorCorrection(let f):
                colorCorrectionControls(filterID: filter.id, filter: f)
            case .crop(let f):
                cropControls(filterID: filter.id, filter: f)
            case .aiKeyer:
                Text("AI Keyer is not yet available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
        .fileImporter(
            isPresented: $isPickingBackground,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    filterLogger.warning("fileImporter returned empty URL list")
                    return
                }
                filterLogger.info("fileImporter picked: \(url.path)")
                let source: Source
                if let type = UTType(filenameExtension: url.pathExtension),
                   type.conforms(to: .image) {
                    source = .image(url: url)
                } else {
                    source = .media(url: url)
                }
                filterLogger.info("Updating chroma key filter id=\(filter.id) with backgroundSource=\(source.defaultName)")
                store.updateChromaKeyFilter(id: filter.id) { $0.backgroundSource = source }
                filterLogger.info("Done updating chroma key filter")
            case .failure(let error):
                filterLogger.error("fileImporter failed: \(error.localizedDescription)")
            }
        }
    }

    private func chromaKeyControls(filterID: String, filter: ChromaKeyFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Key Color")
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(rgb: filter.keyColor) },
                    set: { newColor in
                        let rgb = RGBColor(color: newColor)
                        store.updateChromaKeyFilter(id: filterID) { $0.keyColor = rgb }
                    }
                ))
                .labelsHidden()
                .frame(width: 60)
            }

            filterSlider("Threshold", value: filter.threshold, range: 0...1) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.threshold = newValue }
            }
            filterSlider("Smoothing", value: filter.smoothing, range: 0...0.5) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.smoothing = newValue }
            }
            filterSlider("Edge Feather", value: filter.edgeFeather, range: 0...0.5) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.edgeFeather = newValue }
            }
            filterSlider("Spill Supp.", value: filter.spillSuppression, range: 0...2) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.spillSuppression = newValue }
            }
            filterSlider("Spill Range", value: filter.spillRange, range: 0...1) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.spillRange = newValue }
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
                        store.updateChromaKeyFilter(id: filterID) { $0.backgroundSource = nil }
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
    }

    private func colorCorrectionControls(filterID: String, filter: ColorCorrectionFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            filterSlider("Exposure", value: filter.exposure, range: -3...3) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.exposure = newValue }
            }
            filterSlider("Brightness", value: filter.brightness, range: -1...1) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.brightness = newValue }
            }
            filterSlider("Contrast", value: filter.contrast, range: 0...2) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.contrast = newValue }
            }
            filterSlider("Saturation", value: filter.saturation, range: 0...2) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.saturation = newValue }
            }
            filterSlider("Hue", value: filter.hue, range: -Double.pi...Double.pi) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.hue = newValue }
            }
            filterSlider("Gamma", value: filter.gamma, range: 0.1...3) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.gamma = newValue }
            }
            filterSlider("Temperature", value: filter.temperature, range: -1...1) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.temperature = newValue }
            }
            filterSlider("Tint", value: filter.tint, range: -1...1) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.tint = newValue }
            }
        }
    }

    private func cropControls(filterID: String, filter: CropFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            filterSlider("X", value: filter.rect.x, range: 0...1) { _ in }
            filterSlider("Y", value: filter.rect.y, range: 0...1) { _ in }
            filterSlider("Width", value: filter.rect.width, range: 0...1) { _ in }
            filterSlider("Height", value: filter.rect.height, range: 0...1) { _ in }
        }
    }

    private func filterSlider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
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

// MARK: - Color helpers (shared; see ChromaKeyControlsView.swift)
