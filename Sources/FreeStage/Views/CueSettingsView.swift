//
//  CueSettingsView.swift
//  FreeStage
//
//  Left-side cue settings panel: number, name, timing, color tag, notes,
//  and camera A→B moves for the active cue.
//

import SwiftUI

struct CueSettingsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let cue = store.activeCue {
                    HStack {
                        TextField("Number", text: Binding(
                            get: { cue.number },
                            set: { newValue in store.updateActiveCue { $0.number = newValue } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                        TextField("Name", text: Binding(
                            get: { cue.name },
                            set: { newValue in store.updateActiveCue { $0.name = newValue } }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        Toggle("Armed", isOn: Binding(
                            get: { cue.isArmed },
                            set: { _ in store.toggleArmedForActiveCue() }
                        ))
                        .toggleStyle(.checkbox)

                        Toggle("Flagged", isOn: Binding(
                            get: { cue.isFlagged },
                            set: { _ in store.toggleFlaggedForActiveCue() }
                        ))
                        .toggleStyle(.checkbox)

                        Spacer()
                    }

                    Picker("Cue Color", selection: Binding(
                        get: { cue.color },
                        set: { newValue in store.updateActiveCue { $0.color = newValue } }
                    )) {
                        Text("None").tag(nil as CueColor?)
                        ForEach(CueColor.allCases) { color in
                            HStack {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 12, height: 12)
                                Text(color.rawValue.capitalized)
                            }
                            .tag(color as CueColor?)
                        }
                    }

                    Picker("Transition", selection: Binding(
                        get: { cue.transition },
                        set: { newValue in store.updateActiveCue { $0.transition = newValue } }
                    )) {
                        ForEach(Transition.allCases) { transition in
                            Text(transition.displayName).tag(transition)
                        }
                    }

                    Picker("Continue", selection: Binding(
                        get: { cue.continueMode },
                        set: { newValue in store.updateActiveCue { $0.continueMode = newValue } }
                    )) {
                        ForEach(ContinueMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    HStack {
                        timeField("Pre Wait", value: cue.preWait) { newValue in store.updateActiveCue { $0.preWait = newValue } }
                        timeField("Duration", value: cue.duration) { newValue in store.updateActiveCue { $0.duration = newValue } }
                        timeField("Post Wait", value: cue.postWait) { newValue in store.updateActiveCue { $0.postWait = newValue } }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: Binding(
                            get: { cue.notes },
                            set: { newValue in store.updateActiveCue { $0.notes = newValue } }
                        ))
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    }

                    cameraMoveSection(for: cue)
                } else {
                    Text("No cue selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
        }
    }

    private func cameraMoveSection(for cue: Cue) -> some View {
        GroupBox("Camera Move") {
            VStack(alignment: .leading, spacing: 10) {
                let move = cue.cameraMove ?? CameraMove()

                Toggle("Enable A→B Move", isOn: Binding(
                    get: { move.isEnabled },
                    set: { newValue in
                        store.updateActiveCue { cue in
                            var updated = cue.cameraMove ?? CameraMove()
                            updated.isEnabled = newValue
                            cue.cameraMove = updated
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                if move.isEnabled {
                    Picker("Start Preset", selection: Binding(
                        get: { move.startPresetID },
                        set: { newValue in
                            store.updateActiveCue { cue in
                                var updated = cue.cameraMove ?? CameraMove()
                                updated.startPresetID = newValue
                                cue.cameraMove = updated
                            }
                        }
                    )) {
                        Text("Current Position").tag(nil as UUID?)
                        ForEach(store.show.cameraPresets) { preset in
                            Text(preset.name).tag(preset.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("End Preset", selection: Binding(
                        get: { move.endPresetID },
                        set: { newValue in
                            store.updateActiveCue { cue in
                                var updated = cue.cameraMove ?? CameraMove()
                                updated.endPresetID = newValue
                                cue.cameraMove = updated
                            }
                        }
                    )) {
                        Text("Select preset…").tag(nil as UUID?)
                        ForEach(store.show.cameraPresets) { preset in
                            Text(preset.name).tag(preset.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Duration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Duration", value: Binding(
                            get: { move.duration },
                            set: { newValue in
                                store.updateActiveCue { cue in
                                    var updated = cue.cameraMove ?? CameraMove()
                                    updated.duration = newValue
                                    cue.cameraMove = updated
                                }
                            }
                        ), formatter: timeFormatter)
                        .textFieldStyle(.roundedBorder)
                    }
                }

                if store.show.cameraPresets.isEmpty {
                    Text("Save camera presets in the Scene Layers panel to use A→B moves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timeField(_ label: String, value: TimeInterval, onChange: @escaping (TimeInterval) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, value: Binding(
                get: { value },
                set: { onChange($0) }
            ), formatter: timeFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 80)
        }
    }

    private var timeFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
