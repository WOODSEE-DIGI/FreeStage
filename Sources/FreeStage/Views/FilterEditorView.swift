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
    @State private var isPickingSlideshow = false
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
        .sheet(isPresented: $isPickingSlideshow) {
            SlideshowPickerSheet { slideshow in
                store.updateChromaKeyFilter(id: filter.id) { $0.backgroundSource = .slideshow(slideshow) }
            }
        }
    }

    private func chromaKeyControls(filterID: String, filter: ChromaKeyFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("A / B")
                    .font(.caption)
                Toggle("Bypass key for comparison", isOn: Binding(
                    get: { filter.bypass },
                    set: { newValue in store.updateChromaKeyFilter(id: filterID) { $0.bypass = newValue } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Temporarily disable the key to compare against the original source.")

                Spacer()
            }

            keyColorControls(filterID: filterID, filter: filter)

            AdjustmentSlider("Threshold", value: filter.threshold, range: 0...1, defaultValue: 0.35) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.threshold = newValue }
            }
            AdjustmentSlider("Smoothing", value: filter.smoothing, range: 0...0.5, defaultValue: 0.08) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.smoothing = newValue }
            }
            AdjustmentSlider("Edge Feather", value: filter.edgeFeather, range: 0...0.5, defaultValue: 0.0) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.edgeFeather = newValue }
            }
            AdjustmentSlider("Edge Despill", value: filter.edgeDespill, range: 0...2, defaultValue: 0.5) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.edgeDespill = newValue }
            }
            AdjustmentSlider("Spill Supp.", value: filter.spillSuppression, range: 0...2, defaultValue: 0.5) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.spillSuppression = newValue }
            }
            AdjustmentSlider("Spill Range", value: filter.spillRange, range: 0...1, defaultValue: 0.25) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.spillRange = newValue }
            }
            AdjustmentSlider("Skin Protect", value: filter.skinToneProtection, range: 0...1, defaultValue: 0.3) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.skinToneProtection = newValue }
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
                VStack(alignment: .leading, spacing: 6) {
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

                    HStack {
                        Text("Position")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        AdjustmentSlider("X", value: filter.backgroundTransform.x, range: 0...1, defaultValue: 0.5) { newValue in
                            store.updateChromaKeyFilter(id: filterID) { $0.backgroundTransform.x = newValue }
                        }
                        AdjustmentSlider("Y", value: filter.backgroundTransform.y, range: 0...1, defaultValue: 0.5) { newValue in
                            store.updateChromaKeyFilter(id: filterID) { $0.backgroundTransform.y = newValue }
                        }
                    }

                    AdjustmentSlider("Zoom", value: filter.backgroundTransform.scaleX, range: 0.1...5, defaultValue: 1.0) { newValue in
                        store.updateChromaKeyFilter(id: filterID) {
                            $0.backgroundTransform.scaleX = newValue
                            $0.backgroundTransform.scaleY = newValue
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Reset Background") {
                            store.updateChromaKeyFilter(id: filterID) { $0.backgroundTransform = .identity }
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
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

    private func keyColorControls(filterID: String, filter: ChromaKeyFilter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Key Color")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(ChromaKeyColorPreset.allCases) { preset in
                    Button {
                        store.updateChromaKeyFilter(id: filterID) { $0.applyPreset(preset) }
                    } label: {
                        Text(preset.displayName)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(filter.keyColorPreset == preset ? Color.accentColor : Color.gray.opacity(0.25))
                            .foregroundStyle(filter.keyColorPreset == preset ? .white : .primary)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            AdjustmentSlider("Hue Shift", value: filter.hueShift, range: (-Double.pi / 2)...(Double.pi / 2), defaultValue: 0) { newValue in
                store.updateChromaKeyFilter(id: filterID) { $0.hueShift = newValue }
            }

            if filter.keyColorPreset == .custom {
                HStack {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
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
                                store.updateChromaKeyFilter(id: filterID) { filter in
                                    guard index < filter.keyColors.count else { return }
                                    filter.keyColors[index] = rgb
                                }
                            }
                        ))
                        .labelsHidden()
                        .frame(width: 44)

                        if filter.keyColors.count > 1 {
                            Button {
                                store.updateChromaKeyFilter(id: filterID) { filter in
                                    guard index < filter.keyColors.count else { return }
                                    filter.keyColors.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if filter.keyColors.count < 4 {
                    Button {
                        store.updateChromaKeyFilter(id: filterID) { filter in
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
            }
        }
        .padding(.vertical, 4)
    }

    private func colorCorrectionControls(filterID: String, filter: ColorCorrectionFilter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AdjustmentSlider("Exposure", value: filter.exposure, range: -3...3, defaultValue: 0.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.exposure = newValue }
            }
            AdjustmentSlider("Brightness", value: filter.brightness, range: -1...1, defaultValue: 0.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.brightness = newValue }
            }
            AdjustmentSlider("Contrast", value: filter.contrast, range: 0...2, defaultValue: 1.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.contrast = newValue }
            }
            AdjustmentSlider("Saturation", value: filter.saturation, range: 0...2, defaultValue: 1.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.saturation = newValue }
            }
            AdjustmentSlider("Hue", value: filter.hue, range: -Double.pi...Double.pi, defaultValue: 0.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.hue = newValue }
            }
            AdjustmentSlider("Gamma", value: filter.gamma, range: 0.1...3, defaultValue: 1.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.gamma = newValue }
            }
            AdjustmentSlider("Temperature", value: filter.temperature, range: -1...1, defaultValue: 0.0) { newValue in
                store.updateColorCorrectionFilter(id: filterID) { $0.temperature = newValue }
            }
            AdjustmentSlider("Tint", value: filter.tint, range: -1...1, defaultValue: 0.0) { newValue in
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
