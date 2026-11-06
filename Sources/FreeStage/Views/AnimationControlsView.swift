//
//  AnimationControlsView.swift
//  FreeStage
//
//  Reusable animation controls for template layers: preset picker, duration,
//  progress slider, and animate in/out buttons.
//

import SwiftUI

struct AnimationControlsView: View {
    @Environment(ShowStore.self) private var store

    @State private var animationTimer: Timer? = nil

    var body: some View {
        GroupBox("Animation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Preset", selection: presetBinding) {
                    ForEach(TemplateAnimationPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                if animation.preset != .none {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration: \(String(format: "%.2f", animation.duration))s")
                            .font(.caption2)
                        Slider(value: durationBinding, in: 0.05...3, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Progress: \(Int(animation.progress * 100))%")
                            .font(.caption2)
                        Slider(value: progressBinding, in: 0...1, step: 0.01)
                    }

                    HStack(spacing: 8) {
                        Button("Animate In") {
                            runAnimation(to: 1)
                        }
                        .controlSize(.small)

                        Button("Animate Out") {
                            runAnimation(to: 0)
                        }
                        .controlSize(.small)

                        Spacer()
                    }
                }
            }
        }
        .padding([.horizontal, .top])
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private var animation: TemplateAnimation {
        selectedAnimation() ?? TemplateAnimation()
    }

    private func selectedAnimation() -> TemplateAnimation? {
        guard let layer = store.selectedLayer else { return nil }
        switch layer.source {
        case .border(let s): return s.animation
        case .lowerThird(let s): return s.animation
        case .chapterMarker(let s): return s.animation
        case .nextSection(let s): return s.animation
        case .socialBug(let s): return s.animation
        case .logoBug(let s): return s.animation
        case .countdownTimer(let s): return s.animation
        default: return nil
        }
    }

    private var presetBinding: Binding<TemplateAnimationPreset> {
        Binding(
            get: { animation.preset },
            set: { newValue in
                store.updateSelectedLayerAnimation { $0.preset = newValue }
            }
        )
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { animation.duration },
            set: { newValue in
                store.updateSelectedLayerAnimation { $0.duration = newValue }
            }
        )
    }

    private var progressBinding: Binding<Double> {
        Binding(
            get: { animation.progress },
            set: { newValue in
                store.updateSelectedLayerAnimation { $0.progress = newValue }
            }
        )
    }

    private func runAnimation(to target: Double) {
        animationTimer?.invalidate()
        let duration = animation.duration
        let start = animation.progress
        let startTime = Date()

        let timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let t = min(1, elapsed / duration)
            let newProgress = start + (target - start) * t
            Task { @MainActor in
                store.updateSelectedLayerAnimation { $0.progress = newProgress }
            }
            if t >= 1 {
                timer.invalidate()
                Task { @MainActor in
                    animationTimer = nil
                }
            }
        }
        animationTimer = timer
    }
}
