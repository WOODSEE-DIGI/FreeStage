//
//  CameraControlsView.swift
//  FreeStage
//
//  Inspector panel for per-camera adjustments. Software framing (zoom/pan)
//  maps to the layer transform, exposure/temperature/tint to a Color
//  Correction filter, and gimbal pan/tilt drives the physical OBSBOT gimbal
//  (with an optional software limit zone) when connected.
//

import SwiftUI

struct CameraControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Camera Adjustments") {
            if let layer = store.selectedLayer, case .camera = layer.source {
                CameraAdjustmentsEditor()
            } else {
                Text("Select a camera layer to adjust its image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .bottom])
    }
}

struct CameraAdjustmentsEditor: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.cameraControlService) private var cameraControlService
    @State private var presetName = ""
    @State private var transportSelection: ObsbotPTZController.Transport = .usb
    /// Currently held jog-pad arrow (drives the pressed accent).
    @State private var pressedArrow: String? = nil

    private var layer: Layer? { store.selectedLayer }
    private var transform: ItemTransform { layer?.transform ?? .identity }
    private var colorCorrection: ColorCorrectionFilter? { store.selectedLayerColorCorrection }
    private var gimbal: (pan: Double, tilt: Double, active: Bool) {
        let settings = layer?.cameraSettings
        return (settings?.gimbalPan ?? 0, settings?.gimbalTilt ?? 0, settings?.gimbalActive ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zoom / Position")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            cameraSlider("Zoom", value: transform.scaleX, range: 0.1...5) { newValue in
                store.updateSelectedLayer {
                    $0.transform.scaleX = newValue
                    $0.transform.scaleY = newValue
                }
            }

            cameraSlider("Pan X", value: transform.x, range: 0...1) { newValue in
                store.updateSelectedLayer { $0.transform.x = newValue }
            }

            cameraSlider("Pan Y", value: transform.y, range: 0...1) { newValue in
                store.updateSelectedLayer { $0.transform.y = newValue }
            }

            gimbalSection

            Text("Color")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            cameraSlider("Exposure", value: colorCorrection?.exposure ?? 0, range: -3...3) { newValue in
                store.setSelectedLayerExposure(newValue)
            }

            cameraSlider("Temperature", value: colorCorrection?.temperature ?? 0, range: -1...1) { newValue in
                store.setSelectedLayerColorTemperature(newValue)
            }

            cameraSlider("Tint", value: colorCorrection?.tint ?? 0, range: -1...1) { newValue in
                store.setSelectedLayerColorTint(newValue)
            }

            Divider()

            Text("Presets")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack {
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    guard !presetName.isEmpty else { return }
                    store.addCameraPreset(name: presetName)
                    presetName = ""
                }
                .disabled(presetName.isEmpty)
            }

            if !store.show.cameraPresets.isEmpty {
                Picker("Recall", selection: Binding(
                    get: { UUID?.none },
                    set: { id in
                        guard let id,
                              let preset = store.show.cameraPresets.first(where: { $0.id == id })
                        else { return }
                        store.applyCameraPresetToSelectedLayer(preset)
                    }
                )) {
                    Text("Select preset…").tag(UUID?.none)
                    ForEach(store.show.cameraPresets) { preset in
                        Text(preset.name).tag(preset.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Gimbal

    @ViewBuilder
    private var gimbalSection: some View {
        if let service = cameraControlService {
            Divider().padding(.top, 4)

            HStack {
                Text("Gimbal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                gimbalConnectionBadge(service)
            }

            if service.ptz.isConnected {
                gimbalPad(service)
                gimbalSliders(service)

                HStack(spacing: 8) {
                    Button("Read Position") {
                        Task { await service.ptz.refreshPosition() }
                    }
                    .controlSize(.small)

                    Button("Recenter") {
                        service.ptz.recenter()
                        store.updateSelectedLayerGimbal(pan: 0, tilt: 0)
                    }
                    .controlSize(.small)

                    Spacer()

                    Text("Now: \(service.ptz.currentPan, specifier: "%.1f")° / \(service.ptz.currentTilt, specifier: "%.1f")°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                limitZoneEditor
            } else {
                gimbalConnectControls(service)
            }

            if let error = service.ptz.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func gimbalConnectionBadge(_ service: CameraControlService) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(service.ptz.isConnected ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text(service.ptz.deviceName ?? "Disconnected")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func gimbalConnectControls(_ service: CameraControlService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Path", selection: Binding(
                    get: { transportSelection },
                    set: { newValue in
                        transportSelection = newValue
                    }
                )) {
                    ForEach(ObsbotPTZController.Transport.allCases) { transport in
                        Text(transport.rawValue).tag(transport)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Button("Connect Gimbal") {
                    service.connectGimbal(transport: transportSelection, captureUniqueID: store.selectedCameraUniqueID)
                }
                .controlSize(.small)
            }

            Text(transportSelection == .usb
                 ? "Direct USB control; no companion app required."
                 : "Sends OSC to OBSBOT Center on this Mac (UDP 16284). Requires the app to be running.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Direction pad (manual jog; needs no position reads)

    /// Ecamm-style jog pad: press-and-hold an arrow to drive the head at the
    /// jog speed, release to stop. Speeds are wire frame (pitch + = down,
    /// pan + = left), converted here from the arrows.
    @ViewBuilder
    private func gimbalPad(_ service: CameraControlService) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Color.clear.frame(width: 44, height: 34)
                padButton("▲", id: "up", pitchWire: -1, panWire: 0, service: service)
                    .accessibilityLabel("Tilt up")
                Color.clear.frame(width: 44, height: 34)
            }
            HStack(spacing: 6) {
                padButton("◀", id: "left", pitchWire: 0, panWire: 1, service: service)
                    .accessibilityLabel("Pan left")
                Button("■") { service.ptz.nudgeStop() }
                    .frame(width: 44, height: 34)
                    .accessibilityLabel("Stop")
                padButton("▶", id: "right", pitchWire: 0, panWire: -1, service: service)
                    .accessibilityLabel("Pan right")
            }
            HStack(spacing: 6) {
                Color.clear.frame(width: 44, height: 34)
                padButton("▼", id: "down", pitchWire: 1, panWire: 0, service: service)
                    .accessibilityLabel("Tilt down")
                Color.clear.frame(width: 44, height: 34)
            }
            cameraSlider("Jog °/s", value: service.ptz.nudgeSpeed, range: 5...60) {
                service.ptz.nudgeSpeed = $0
            }
        }
        .padding(.vertical, 2)
    }

    private func padButton(_ title: String, id: String, pitchWire: Double, panWire: Double, service: CameraControlService) -> some View {
        Text(title)
            .font(.title2)
            .foregroundStyle(pressedArrow == id ? .white : .primary)
            .frame(width: 44, height: 34)
            .background(pressedArrow == id ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            .clipShape(.rect(cornerRadius: 8))
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                if pressing {
                    pressedArrow = id
                    service.ptz.nudgeStart(
                        pitchWire: pitchWire * service.ptz.nudgeSpeed,
                        panWire: panWire * service.ptz.nudgeSpeed
                    )
                } else {
                    if pressedArrow == id { pressedArrow = nil }
                    service.ptz.nudgeStop()
                }
            }, perform: {})
    }

    @ViewBuilder
    private func gimbalSliders(_ service: CameraControlService) -> some View {
        let panRange = service.ptz.panRange
        let tiltRange = service.ptz.tiltRange

        cameraSlider("Pan °", value: gimbal.pan, range: panRange) { newValue in
            store.updateSelectedLayerGimbal(pan: newValue)
        }
        cameraSlider("Tilt °", value: gimbal.tilt, range: tiltRange) { newValue in
            store.updateSelectedLayerGimbal(tilt: newValue)
        }
    }

    // MARK: - Limit zone

    @ViewBuilder
    private var limitZoneEditor: some View {
        if let zone = store.limitZoneForSelectedCamera() {
            Divider().padding(.top, 2)

            HStack {
                Text("Limit Zone")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { zone.isEnabled },
                    set: { updated in
                        var z = zone
                        z.isEnabled = updated
                        store.setLimitZoneForSelectedCamera(z)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("When on, gimbal moves are clamped into the zone so the camera cannot frame outside it.")
            }

            if zone.isEnabled {
                limitZoneRangeRow("Pan", lower: zone.panMin, upper: zone.panMax, range: -130...130) { newMin, newMax in
                    store.setLimitZoneForSelectedCamera(
                        CameraLimitZone(isEnabled: true, panMin: newMin, panMax: newMax, tiltMin: zone.tiltMin, tiltMax: zone.tiltMax)
                    )
                }
                limitZoneRangeRow("Tilt", lower: zone.tiltMin, upper: zone.tiltMax, range: -60...60) { newMin, newMax in
                    store.setLimitZoneForSelectedCamera(
                        CameraLimitZone(isEnabled: true, panMin: zone.panMin, panMax: zone.panMax, tiltMin: newMin, tiltMax: newMax)
                    )
                }
            }
        }
    }

    private func limitZoneRangeRow(
        _ label: String,
        lower: Double,
        upper: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double, Double) -> Void
    ) -> some View {
        // NOTE: parameters are lower/upper, not min/max, so the global
        // Swift min()/max() functions stay callable inside the bindings.
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label)  \(lower, specifier: "%.0f")° … \(upper, specifier: "%.0f")°")
                .font(.caption.monospacedDigit())
            HStack(spacing: 6) {
                Slider(value: Binding(
                    get: { lower },
                    set: { onChange(Swift.min($0, upper), upper) }
                ), in: range)
                Slider(value: Binding(
                    get: { upper },
                    set: { onChange(lower, Swift.max($0, lower)) }
                ), in: range)
            }
        }
    }

    // MARK: - Helpers

    private func cameraSlider(
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
