//
//  DrawingEditorView.swift
//  FreeStage
//
//  Modal editor for a DrawingSource: canvas, tool picker, color, width, undo.
//

import SwiftUI

struct DrawingEditorView: View {
    @Binding var source: DrawingSource
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding()
                .background(.ultraThinMaterial)

            GeometryReader { geometry in
                let aspect = source.canvasSize.width / source.canvasSize.height
                let container = geometry.size
                let width = min(container.width, container.height * aspect)
                let height = width / aspect

                DrawingCanvasView(source: $source)
                    .frame(width: width, height: height)
                    .background(Color(nsColor: .textBackgroundColor))
                    .border(Color.secondary.opacity(0.3), width: 1)
                    .position(x: container.width / 2, y: container.height / 2)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            toolMenu
                .frame(width: 140)

            HStack(spacing: 6) {
                Text("Color")
                ColorPicker("", selection: colorBinding)
                    .labelsHidden()
            }

            HStack(spacing: 6) {
                Text("Width")
                Slider(value: binding(\.brushWidth), in: 1...100, step: 1)
                    .frame(width: 120)
                Text("\(Int(source.brushWidth))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32)
            }

            Spacer()

            Button {
                if !source.strokes.isEmpty {
                    source.strokes.removeLast()
                }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(source.strokes.isEmpty)

            Button {
                source.strokes.removeAll()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(source.strokes.isEmpty)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var toolMenu: some View {
        Picker("Tool", selection: binding(\.tool)) {
            ForEach(DrawingTool.allCases) { tool in
                Label(tool.displayName, systemImage: tool.systemImage)
                    .tag(tool)
            }
        }
        .pickerStyle(.menu)
        .help("Select drawing tool")
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: RGBColor(r: source.color.r, g: source.color.g, b: source.color.b)) },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                source.color = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: 1.0)
            }
        )
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<DrawingSource, Value>
    ) -> Binding<Value> {
        Binding(
            get: { source[keyPath: keyPath] },
            set: { source[keyPath: keyPath] = $0 }
        )
    }
}
