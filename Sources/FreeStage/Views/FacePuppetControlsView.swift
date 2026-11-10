//
//  FacePuppetControlsView.swift
//  FreeStage
//
//  Inspector controls for a Face Puppet layer: change the driving camera,
//  swap the puppet image, pick a bundled sample wrap, generate a new texture
//  with ComfyUI or a local Stable Diffusion model, and reset anchor offsets.
//

import SwiftUI
import UniformTypeIdentifiers

/// Identifies which texture generator the user wants to use.
private enum TextureGeneratorSource: Identifiable, Hashable {
    case comfyUI
    case local(LocalDiffusionModel)

    var id: String {
        switch self {
        case .comfyUI: return "comfyui"
        case .local(let model): return model.id
        }
    }

    var displayName: String {
        switch self {
        case .comfyUI: return "ComfyUI (local server)"
        case .local(let model): return model.name
        }
    }

    var isLocal: Bool {
        switch self {
        case .comfyUI: return false
        case .local: return true
        }
    }
}

/// Either a textured puppet or a mesh-only preview layer.
private enum FacePuppetLayerInfo {
    case textured(cameraID: String, puppetURL: URL, anchorMap: FacePuppetAnchorMap?)
    case mesh(cameraID: String, anchorMap: FacePuppetAnchorMap?)
}

struct FacePuppetControlsView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraCaptureManager) private var captureManager
    @Environment(\.cameraControlService) private var cameraControlService
    @State private var isImportingPuppetImage = false
    @State private var promptText = LocalDiffusionTextureGenerator.defaultPrompt
    @State private var isGenerating = false
    @State private var statusMessage: String?

    @State private var selectedSource: TextureGeneratorSource = .comfyUI
    @State private var isModelDownloaded = false
    @State private var isDownloading = false
    @State private var downloadProgress: Double?
    @State private var obsbotTransport: ObsbotPTZController.Transport = .usb

    private let downloader = DiffusionModelDownloader()
    private var layer: Layer? { store.selectedLayer }

    private var sourceOptions: [TextureGeneratorSource] {
        [.comfyUI] + LocalDiffusionModel.builtIn.map { .local($0) }
    }

    private var layerInfo: FacePuppetLayerInfo? {
        guard let layer else { return nil }
        switch layer.source {
        case .facePuppet(let cameraID, let puppetURL):
            return .textured(cameraID: cameraID, puppetURL: puppetURL, anchorMap: nil)
        case .facePuppetAnchored(let cameraID, let puppetURL, let anchorMap):
            return .textured(cameraID: cameraID, puppetURL: puppetURL, anchorMap: anchorMap)
        case .facePuppetMesh(let cameraID, let anchorMap):
            return .mesh(cameraID: cameraID, anchorMap: anchorMap)
        default:
            return nil
        }
    }

    var body: some View {
        GroupBox("Face Puppet") {
            if let info = layerInfo {
                VStack(alignment: .leading, spacing: 10) {
                    switch info {
                    case .textured(let cameraID, let puppetURL, _):
                        texturedControls(
                            cameraID: cameraID,
                            puppetURL: puppetURL
                        )
                    case .mesh(let cameraID, _):
                        meshControls(cameraID: cameraID)
                    }
                }
            } else {
                Text("Select a Face Puppet layer to change its camera or puppet image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .bottom])
        .fileImporter(
            isPresented: $isImportingPuppetImage,
            allowedContentTypes: [UTType.image],
            allowsMultipleSelection: false
        ) { result in
            replacePuppetImage(from: result)
        }
        .task {
            await refreshDownloadStatus()
        }
    }

    // MARK: - Textured puppet controls

    @ViewBuilder
    private func texturedControls(cameraID: String, puppetURL: URL) -> some View {
        cameraPicker(cameraID: cameraID)
        obsbotSection(cameraID: cameraID)
        puppetImagePreview(url: puppetURL)

        HStack(spacing: 8) {
            Button("Replace Puppet Image…") {
                isImportingPuppetImage = true
            }
            .controlSize(.small)

            Spacer()
        }

        sampleWrapPicker()

        Divider()

        Text("Texture Generator")
            .font(.caption.bold())
            .foregroundStyle(.secondary)

        Picker("Source", selection: $selectedSource) {
            ForEach(sourceOptions) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .onChange(of: selectedSource) { _, _ in
            isGenerating = false
            statusMessage = nil
            Task { await refreshDownloadStatus() }
        }

        if case .local(let model) = selectedSource {
            localModelControls(model: model)
        }

        TextEditor(text: $promptText)
            .font(.caption)
            .frame(height: 60)
            .border(.separator, width: 1)

        HStack {
            Button(isGenerating ? "Generating…" : "Generate…") {
                generateTexture(cameraID: cameraID)
            }
            .controlSize(.small)
            .disabled(isGenerating || !canGenerate)

            Spacer()
        }

        anchorResetButtons()

        if let downloadProgress, isDownloading {
            ProgressView(value: downloadProgress, total: 1.0)
                .controlSize(.small)
        }

        if let statusMessage {
            Text(statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    // MARK: - Mesh-only controls

    @ViewBuilder
    private func meshControls(cameraID: String) -> some View {
        cameraPicker(cameraID: cameraID)
        obsbotSection(cameraID: cameraID)

        Text("Mesh-only preview. Drag the green anchor handles on the preview to tune the wrap, then add a puppet texture.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        anchorResetButtons()

        HStack {
            Button("Wrap with Puppet…") {
                wrapMeshWithPuppet(cameraID: cameraID)
            }
            .controlSize(.small)

            Spacer()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func localModelControls(model: LocalDiffusionModel) -> some View {
        HStack(spacing: 8) {
            if isModelDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Model ready")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Button(isDownloading ? "Downloading…" : "Download Model") {
                    download(model: model)
                }
                .controlSize(.small)
                .disabled(isDownloading)
            }
            Spacer()
        }
    }

    private var canGenerate: Bool {
        switch selectedSource {
        case .comfyUI:
            return true
        case .local:
            return isModelDownloaded
        }
    }

    private func cameraPicker(cameraID: String) -> some View {
        let devices = CameraDevice.discover()
        return Picker("Camera", selection: Binding(
            get: { cameraID },
            set: { newID in
                guard newID != cameraID else { return }
                updateCameraID(newID)
            }
        )) {
            ForEach(devices) { device in
                Text(device.name).tag(device.uniqueID)
            }
        }
        .pickerStyle(.menu)
    }

    private func puppetImagePreview(url: URL) -> some View {
        HStack(spacing: 8) {
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func obsbotSection(cameraID: String) -> some View {
        if let service = cameraControlService,
           CameraDevice.discover().contains(where: { $0.uniqueID == cameraID && $0.isOBSBOT }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OBSBOT Camera")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(service.ptz.isConnected ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(service.ptz.isConnected ? (service.ptz.deviceName ?? "Connected") : "Disconnected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text("The OBSBOT's own AI tracking can move the head while the puppet mesh is running. Connect the gimbal to disable it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if service.ptz.isConnected {
                    HStack(spacing: 8) {
                        Button("Recenter Gimbal") {
                            service.ptz.recenter()
                            if layer != nil {
                                store.updateSelectedLayerGimbal(pan: 0, tilt: 0)
                            }
                        }
                        .controlSize(.small)

                        Spacer()
                    }
                } else {
                    HStack(spacing: 8) {
                        Picker("Path", selection: $obsbotTransport) {
                            ForEach(ObsbotPTZController.Transport.allCases) { transport in
                                Text(transport.rawValue).tag(transport)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)

                        Button("Connect Gimbal") {
                            service.connectGimbal(transport: obsbotTransport, captureUniqueID: cameraID)
                        }
                        .controlSize(.small)
                    }
                }

                if let error = service.ptz.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func sampleWrapPicker() -> some View {
        let wraps = sampleWraps
        if !wraps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sample Wraps")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(wraps) { wrap in
                        Button {
                            applySampleWrap(wrap)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo")
                                Text(wrap.name)
                            }
                            .font(.caption)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func anchorResetButtons() -> some View {
        HStack(spacing: 8) {
            Button("Reset Anchors") {
                resetAnchorOffsets()
            }
            .controlSize(.small)

            Spacer()
        }
    }

    // MARK: - Actions

    private func refreshDownloadStatus() async {
        guard case .local(let model) = selectedSource else {
            isModelDownloaded = false
            return
        }
        isModelDownloaded = await downloader.isDownloaded(model)
    }

    private func download(model: LocalDiffusionModel) {
        isDownloading = true
        statusMessage = "Downloading \(model.name)…"

        Task {
            do {
                _ = try await downloader.download(model: model) { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                await refreshDownloadStatus()
                statusMessage = "\(model.name) is ready."
            } catch {
                statusMessage = "Download failed: \(error.localizedDescription)"
            }
            isDownloading = false
        }
    }

    private func replacePuppetImage(from result: Result<[URL], any Error>) {
        guard case .textured(let cameraID, _, let anchorMap) = layerInfo,
              let layerID = store.selectedLayerID else { return }

        do {
            let urls = try result.get()
            guard let url = urls.first,
                  let localURL = copyPuppetImageToAppSupport(from: url) else { return }
            store.setLayerSource(
                id: layerID,
                source: .facePuppetAnchored(
                    cameraID: cameraID,
                    puppetImageURL: localURL,
                    anchorMap: anchorMap
                ),
                name: layer?.name
            )
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func applySampleWrap(_ wrap: SampleWrap) {
        guard case .textured(let cameraID, _, let anchorMap) = layerInfo,
              let localURL = copyPuppetImageToAppSupport(from: wrap.url) else { return }
        store.setLayerSource(
            id: store.selectedLayerID ?? UUID(),
            source: .facePuppetAnchored(
                cameraID: cameraID,
                puppetImageURL: localURL,
                anchorMap: anchorMap
            ),
            name: layer?.name
        )
    }

    private func generateTexture(cameraID: String) {
        guard let layer = layer else { return }
        isGenerating = true
        statusMessage = selectedSource.isLocal ? "Loading local model…" : "Queueing…"

        Task {
            do {
                let tempURL = try await generateWithSelectedSource()
                guard let localURL = copyPuppetImageToAppSupport(from: tempURL) else {
                    throw ComfyUITextureGeneratorError.invalidResponse
                }
                let anchorMap = layer.source.facePuppetAnchorMap
                store.setLayerSource(
                    id: layer.id,
                    source: .facePuppetAnchored(
                        cameraID: cameraID,
                        puppetImageURL: localURL,
                        anchorMap: anchorMap
                    ),
                    name: layer.name
                )
                statusMessage = "Generated and loaded new puppet texture."
            } catch {
                statusMessage = "Generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    private func generateWithSelectedSource() async throws -> URL {
        switch selectedSource {
        case .comfyUI:
            let generator = ComfyUITextureGenerator()
            return try await generator.generatePuppetTexture(promptOverride: promptText)
        case .local(let model):
            guard let directory = await downloader.localDirectory(for: model) else {
                throw LocalDiffusionTextureGeneratorError.modelNotDownloaded
            }
            let generator = LocalDiffusionTextureGenerator(
                model: model,
                resourceDirectory: directory
            )
            return try await generator.generatePuppetTexture(promptOverride: promptText)
        }
    }

    private func wrapMeshWithPuppet(cameraID: String) {
        guard let layer = layer,
              case .mesh(_, let anchorMap) = layerInfo,
              let defaultURL = Bundle.main.url(forResource: "default_puppet", withExtension: "png"),
              let localURL = copyPuppetImageToAppSupport(from: defaultURL) else { return }
        store.setLayerSource(
            id: layer.id,
            source: .facePuppetAnchored(
                cameraID: cameraID,
                puppetImageURL: localURL,
                anchorMap: anchorMap
            ),
            name: layer.name
        )
    }

    private func updateCameraID(_ newID: String) {
        guard let layer = layer else { return }
        let source: Source
        switch layer.source {
        case .facePuppet(_, let puppetURL):
            source = .facePuppet(cameraID: newID, puppetImageURL: puppetURL)
        case .facePuppetAnchored(_, let puppetURL, let anchorMap):
            source = .facePuppetAnchored(
                cameraID: newID,
                puppetImageURL: puppetURL,
                anchorMap: anchorMap
            )
        case .facePuppetMesh(_, let anchorMap):
            source = .facePuppetMesh(cameraID: newID, anchorMap: anchorMap)
        default:
            return
        }
        captureManager?.stopCapture(uniqueID: layer.source.cameraID ?? newID)
        store.setLayerSource(id: layer.id, source: source, name: layer.name)
        captureManager?.startCapture(uniqueID: newID)
    }

    private func resetAnchorOffsets() {
        guard let layer = layer else { return }
        let source: Source
        switch layer.source {
        case .facePuppet(let cameraID, let puppetURL):
            source = .facePuppet(cameraID: cameraID, puppetImageURL: puppetURL)
        case .facePuppetAnchored(let cameraID, let puppetURL, _):
            source = .facePuppetAnchored(
                cameraID: cameraID,
                puppetImageURL: puppetURL,
                anchorMap: nil
            )
        case .facePuppetMesh(let cameraID, _):
            source = .facePuppetMesh(cameraID: cameraID, anchorMap: nil)
        default:
            return
        }
        store.setLayerSource(id: layer.id, source: source, name: layer.name)
    }

    private func copyPuppetImageToAppSupport(from url: URL) -> URL? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let directory = support.appendingPathComponent("PuppetImages", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

// MARK: - Sample wraps

private struct SampleWrap: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
}

private var sampleWraps: [SampleWrap] {
    let names = [
        ("Panda", "wrap_panda"),
        ("Red Panda", "wrap_red_panda"),
        ("Fox", "wrap_fox"),
    ]
    return names.compactMap { name, resource in
        Bundle.main.url(forResource: resource, withExtension: "png")
            .map { SampleWrap(name: name, url: $0) }
    }
}

private extension Source {
    /// Camera ID for face-puppet sources, if any.
    var cameraID: String? {
        switch self {
        case .facePuppet(let id, _),
             .facePuppetAnchored(let id, _, _),
             .facePuppetMesh(let id, _):
            return id
        default:
            return nil
        }
    }
}
