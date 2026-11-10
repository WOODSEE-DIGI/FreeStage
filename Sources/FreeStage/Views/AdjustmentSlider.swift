//
//  AdjustmentSlider.swift
//  FreeStage
//
//  Reusable slider row with value label and a reset-to-default button.
//

import SwiftUI

/// A slider row for numeric adjustments. Shows the current value and a small
/// reset button that snaps the value back to its default.
struct AdjustmentSlider: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    let onChange: (Double) -> Void

    init(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        defaultValue: Double,
        onChange: @escaping (Double) -> Void
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.defaultValue = defaultValue
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: range)

            Text(String(format: "%.2f", value))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)

            Button {
                onChange(defaultValue)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .disabled(abs(value - defaultValue) < 0.0001)
            .help("Reset \(label) to default")
        }
    }
}

#Preview {
    @Previewable @State var value: Double = 0.5
    AdjustmentSlider(
        "Example",
        value: value,
        range: 0...1,
        defaultValue: 0.35,
        onChange: { value = $0 }
    )
    .padding()
}
