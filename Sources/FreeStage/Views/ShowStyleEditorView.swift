//
//  ShowStyleEditorView.swift
//  FreeStage
//
//  Edits the current show's graphic style and manages saved presets.
//

import SwiftUI

struct ShowStyleEditorView: View {
    @Environment(ShowStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var presetName = ""
    @State private var showingSaveAlert = false

    var body: some View {
        @Bindable var store = store
        @Bindable var settings = settings

        Form {
            Section("Preset") {
                Picker("Default for New Shows", selection: $settings.selectedShowStyleID) {
                    Text("FreeStage Default").tag(String?.none)
                    ForEach(settings.showStyles) { style in
                        Text(style.name).tag(Optional(style.id.uuidString))
                    }
                }

                HStack {
                    TextField("Preset Name", text: $presetName)
                    Button("Save Current as Preset") {
                        saveCurrentAsPreset()
                    }
                    .disabled(presetName.isEmpty)
                }
            }

            Section("Current Show Style: \(store.show.style.name)") {
                StyleColorPicker("Background", color: styleBinding(for: \.backgroundColor))
                StyleColorPicker("Primary", color: styleBinding(for: \.primaryColor))
                StyleColorPicker("Accent", color: styleBinding(for: \.accentColor))
                StyleColorPicker("Title Text", color: styleBinding(for: \.textColor))
                StyleColorPicker("Subtitle Text", color: styleBinding(for: \.subtitleTextColor))
                StyleColorPicker("Label Text", color: styleBinding(for: \.labelTextColor))

                Picker("Fill Style", selection: styleBinding(for: \.fillStyle)) {
                    ForEach(TemplateFillStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                if store.show.style.fillStyle == .gradient {
                    StyleColorPicker("Gradient Start", color: styleBinding(for: \.gradientStartColor))
                    StyleColorPicker("Gradient End", color: styleBinding(for: \.gradientEndColor))
                }

                Picker("Alignment", selection: styleBinding(for: \.alignment)) {
                    ForEach(TemplateTextAlignment.allCases) { alignment in
                        Text(alignment.displayName).tag(alignment)
                    }
                }

                HStack {
                    Text("Title Size")
                    Slider(value: styleBinding(for: \.titleFontSize), in: 12...120, step: 1)
                    Text("\(Int(store.show.style.titleFontSize))")
                        .monospacedDigit()
                }

                HStack {
                    Text("Subtitle Size")
                    Slider(value: styleBinding(for: \.subtitleFontSize), in: 12...80, step: 1)
                    Text("\(Int(store.show.style.subtitleFontSize))")
                        .monospacedDigit()
                }

                HStack {
                    Text("Label Size")
                    Slider(value: styleBinding(for: \.labelFontSize), in: 10...60, step: 1)
                    Text("\(Int(store.show.style.labelFontSize))")
                        .monospacedDigit()
                }

                HStack {
                    Text("Horizontal Padding")
                    Slider(value: styleBinding(for: \.horizontalPadding), in: 0...120, step: 4)
                    Text("\(Int(store.show.style.horizontalPadding))")
                        .monospacedDigit()
                }

                HStack {
                    Text("Vertical Padding")
                    Slider(value: styleBinding(for: \.verticalPadding), in: 0...120, step: 4)
                    Text("\(Int(store.show.style.verticalPadding))")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 360, idealWidth: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Preset Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\"\(presetName)\" has been saved and is now available as a default style for new shows.")
        }
    }

    private func styleBinding<Value>(for keyPath: WritableKeyPath<ShowStyle, Value>) -> Binding<Value> {
        Binding(
            get: { store.show.style[keyPath: keyPath] },
            set: { newValue in
                store.show.style[keyPath: keyPath] = newValue
            }
        )
    }

    private func saveCurrentAsPreset() {
        var newStyle = store.show.style
        newStyle.id = UUID()
        newStyle.name = presetName
        var styles = settings.showStyles
        styles.append(newStyle)
        settings.showStyles = styles
        settings.selectedShowStyleID = newStyle.id.uuidString
        presetName = ""
        showingSaveAlert = true
    }
}

private struct StyleColorPicker: View {
    let title: String
    @Binding var color: CGColorComponents

    init(_ title: String, color: Binding<CGColorComponents>) {
        self.title = title
        self._color = color
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(red: color.r, green: color.g, blue: color.b, opacity: color.a) },
                set: { newColor in
                    if let components = newColor.cgColor?.components, components.count >= 4 {
                        color = CGColorComponents(
                            r: Double(components[0]),
                            g: Double(components[1]),
                            b: Double(components[2]),
                            a: Double(components[3])
                        )
                    }
                }
            ))
            .labelsHidden()
            .frame(width: 80)
        }
    }
}
