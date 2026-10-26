//
//  DrawingControlsView.swift
//  FreeStage
//
//  Inspector controls for a drawing layer: edit, tool, color, width, undo/clear.
//

import SwiftUI

struct DrawingControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var isEditing = false

    var body: some View {
        GroupBox("Drawing") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(store.selectedLayerDrawing?.strokes.count ?? 0) stroke(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit Drawing…") {
                        isEditing = true
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                }

                if store.selectedLayerDrawing != nil {
                    toolMenu

                    HStack(spacing: 16) {
                        ColorPicker("Color", selection: colorBinding)
                            .labelsHidden()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Width: \(Int(store.selectedLayerDrawing?.brushWidth ?? 4))")
                                .font(.caption2)
                            Slider(value: widthBinding, in: 1...100, step: 1)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            store.updateSelectedLayer { layer in
                                guard case .drawing(var drawing) = layer.source else { return }
                                if !drawing.strokes.isEmpty {
                                    drawing.strokes.removeLast()
                                    layer.source = .drawing(drawing)
                                }
                            }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .font(.caption)
                        .disabled((store.selectedLayerDrawing?.strokes.isEmpty) ?? true)

                        Button {
                            store.updateSelectedLayer { layer in
                                guard case .drawing(var drawing) = layer.source else { return }
                                drawing.strokes.removeAll()
                                layer.source = .drawing(drawing)
                            }
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .font(.caption)
                        .disabled((store.selectedLayerDrawing?.strokes.isEmpty) ?? true)
                    }
                }
            }
        }
        .padding([.horizontal, .top])
        .sheet(isPresented: $isEditing) {
            if var source = store.selectedLayerDrawing {
                DrawingEditorView(source: Binding(
                    get: { source },
                    set: { newValue in
                        store.updateSelectedLayer { layer in
                            layer.source = .drawing(newValue)
                        }
                        source = newValue
                    }
                ))
                .frame(minWidth: 900, minHeight: 600)
            }
        }
    }

    private var toolMenu: some View {
        Picker("Tool", selection: toolBinding) {
            ForEach(DrawingTool.allCases) { tool in
                Label(tool.displayName, systemImage: tool.systemImage)
                    .tag(tool)
            }
        }
        .pickerStyle(.menu)
    }

    private var toolBinding: Binding<DrawingTool> {
        Binding(
            get: { store.selectedLayerDrawing?.tool ?? .pen },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .drawing(var drawing) = layer.source else { return }
                    drawing.tool = newValue
                    layer.source = .drawing(drawing)
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerDrawing else { return .red }
                return Color(rgb: RGBColor(r: source.color.r, g: source.color.g, b: source.color.b))
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                store.updateSelectedLayer { layer in
                    guard case .drawing(var drawing) = layer.source else { return }
                    drawing.color = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: 1.0)
                    layer.source = .drawing(drawing)
                }
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerDrawing?.brushWidth ?? 4 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .drawing(var drawing) = layer.source else { return }
                    drawing.brushWidth = newValue
                    layer.source = .drawing(drawing)
                }
            }
        )
    }
}
