//
//  AudioDynamicsProcessor.swift
//  FreeStage
//
//  Per-channel auto-gain and peak limiting. Keeps microphones and system
//  audio at a consistent, YouTube-friendly level without manual fader riding.
//

import Foundation

/// Simple live dynamics processor: auto-gain plus a fast peak limiter.
///
/// The auto-gain measures RMS over a short sliding window and slowly adjusts
/// a gain multiplier so the signal sits near `targetRMS`. A noise gate prevents
/// the gain from running away during silence, and a peak limiter clamps the
/// output so boosted signals never clip.
final class AudioDynamicsProcessor: @unchecked Sendable {
    private let lock = NSLock()

    /// Whether the processor is active.
    var isEnabled = false {
        didSet { resetIfDisabled() }
    }

    /// Target RMS level (0...1). -20 dBFS ≈ 0.1, which is a comfortable
    /// YouTube/voice level with headroom for peaks.
    var targetRMS: Float = 0.1

    /// Maximum allowed gain (linear). 10.0 ≈ +20 dB.
    var maxGain: Float = 10.0

    /// Noise-floor gate. When input RMS is below this, gain is frozen so
    /// background noise is not amplified.
    var gateThreshold: Float = 0.0005

    /// Current applied gain (linear). Read-only for UI metering.
    private(set) var currentGain: Float = 1.0

    /// Smoothing factor for gain changes per buffer. Lower = slower/smoother.
    var smoothing: Float = 0.02

    /// Peak limiter threshold (linear). -3 dBFS ≈ 0.708.
    var limiterThreshold: Float = 0.708

    private var rmsWindow: [Float] = []
    private let rmsWindowSize = 48  // ~1 ms at 48 kHz stereo = 48 samples

    func process(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }

        lock.lock()
        let enabled = isEnabled
        let target = targetRMS
        let maxAllowedGain = maxGain
        let gate = gateThreshold
        let smoothing = self.smoothing
        let limiter = limiterThreshold
        var gain = currentGain
        lock.unlock()

        guard enabled else { return }

        // Compute short-term RMS for this buffer.
        let rms = bufferRMS(samples)

        if rms > gate {
            let desired = target / max(rms, 1e-8)
            let clampedDesired = min(desired, maxAllowedGain)
            // Faster reduction than increase (compressor-like behaviour).
            let attackSmoothing = clampedDesired < gain ? smoothing * 4 : smoothing
            gain = gain * (1 - attackSmoothing) + clampedDesired * attackSmoothing
        }
        // If below gate, leave gain where it is — don't boost silence.

        // Apply gain and limiter in one pass.
        for i in samples.indices {
            let amplified = samples[i] * gain
            samples[i] = softLimit(amplified, threshold: limiter)
        }

        lock.lock()
        currentGain = gain
        lock.unlock()
    }

    private func bufferRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }

    private func softLimit(_ sample: Float, threshold: Float) -> Float {
        // Hard-limit above threshold with a tiny soft-knee transition.
        let absSample = abs(sample)
        guard absSample > threshold else { return sample }
        let sign: Float = sample >= 0 ? 1 : -1
        let overshoot = absSample - threshold
        let knee: Float = 0.01
        let limited = threshold + overshoot / (1 + overshoot / knee)
        return sign * limited
    }

    private func resetIfDisabled() {
        lock.withLock {
            if !isEnabled {
                currentGain = 1.0
            }
        }
    }
}
