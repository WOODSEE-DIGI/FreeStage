//
//  VideoClipEditorView.swift
//  FreeStage
//
//  Clip editor for Presenter-mode Video Package segments. Lets the user
//  scrub a proxy video, set in/out points, and export a trimmed subclip
//  for instant final playback.
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoClipEditorView: View {
    @Environment(ThemeStore.self) private var theme
    @Binding var clip: VideoClip
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var isGeneratingProxy = false
    @State private var isGeneratingSubclip = false
    @State private var statusMessage: String?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            header

            videoPlayer
                .frame(minHeight: 280)

            timelineControls

            actionButtons

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .frame(minWidth: 800, minHeight: 560)
        .background(theme.background)
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: cleanup)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Clip Editor")
                    .font(.title2.bold())
                    .foregroundStyle(theme.text)
                Text(clip.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("In: \(formatTime(clip.inPoint))  Out: \(formatTime(clip.outPoint ?? duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.text)
                if let trimmed = clip.trimmedDuration {
                    Text("Trimmed duration: \(formatTime(trimmed))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
    }

    // MARK: - Video player

    private var videoPlayer: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9.0, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .aspectRatio(16 / 9.0, contentMode: .fit)
                    .overlay(
                        Text("Loading video…")
                            .foregroundStyle(theme.secondaryText)
                    )
            }
        }
    }

    // MARK: - Timeline controls

    private var timelineControls: some View {
        VStack(spacing: 8) {
            Slider(value: $currentTime, in: 0...max(duration, 0.01)) { editing in
                if editing {
                    pause()
                    seek(to: currentTime)
                } else {
                    seek(to: currentTime)
                }
            }
            .disabled(duration <= 0)

            HStack(spacing: 16) {
                Button {
                    seek(to: max(0, currentTime - 5))
                } label: {
                    Image(systemName: "gobackward.5")
                }

                Button {
                    isPlaying ? pause() : play()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .frame(width: 44)

                Button {
                    seek(to: min(duration, currentTime + 5))
                } label: {
                    Image(systemName: "goforward.5")
                }

                Spacer()

                Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.text)
            }
        }
    }

    // MARK: - In/Out and export buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Set In") {
                clip.inPoint = currentTime
            }
            .buttonStyle(.bordered)

            Button("Set Out") {
                clip.outPoint = currentTime
            }
            .buttonStyle(.bordered)

            Button("Reset") {
                clip.inPoint = 0
                clip.outPoint = nil
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                generateProxy()
            } label: {
                if isGeneratingProxy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(clip.proxyURL == nil ? "Generate Proxy" : "Regenerate Proxy")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isGeneratingProxy || isGeneratingSubclip)

            Button {
                generateSubclip()
            } label: {
                if isGeneratingSubclip {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(clip.subclipURL == nil ? "Export Subclip" : "Re-export Subclip")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingProxy || isGeneratingSubclip)
        }
    }

    // MARK: - Playback helpers

    private func setupPlayer() {
        let url = clip.proxyURL ?? clip.sourceURL
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer

        Task {
            let asset = AVURLAsset(url: clip.sourceURL)
            let loadedDuration = try? await asset.load(.duration).seconds
            let finalDuration = loadedDuration ?? 0
            await MainActor.run {
                duration = finalDuration
                if clip.sourceDuration == nil {
                    clip.sourceDuration = finalDuration
                }
                startTimer()
            }
        }
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        player?.pause()
        player = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                guard let player = self.player else { return }
                let time = player.currentTime().seconds
                if !time.isNaN {
                    self.currentTime = time
                }
            }
        }
    }

    private func play() {
        player?.play()
        isPlaying = true
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func seek(to time: Double) {
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Proxy / subclip generation

    private func generateProxy() {
        guard !isGeneratingProxy else { return }
        isGeneratingProxy = true
        statusMessage = "Generating proxy…"
        Task {
            do {
                let url = try await ProxyGenerator.shared.generateProxy(for: clip.sourceURL)
                await MainActor.run {
                    clip.proxyURL = url
                    statusMessage = "Proxy ready."
                    // Switch playback to proxy for smoother scrubbing.
                    if player != nil {
                        let wasPlaying = isPlaying
                        pause()
                        player?.replaceCurrentItem(with: AVPlayerItem(url: url))
                        seek(to: currentTime)
                        if wasPlaying { play() }
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Proxy failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isGeneratingProxy = false
            }
        }
    }

    private func generateSubclip() {
        guard !isGeneratingSubclip else { return }
        isGeneratingSubclip = true
        statusMessage = "Exporting subclip…"
        Task {
            do {
                let url = try await ProxyGenerator.shared.generateSubclip(
                    for: clip.sourceURL,
                    inPoint: clip.inPoint,
                    outPoint: clip.outPoint
                )
                await MainActor.run {
                    clip.subclipURL = url
                    statusMessage = "Subclip exported. Final playback will use the trimmed file."
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Subclip failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isGeneratingSubclip = false
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, time)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let centis = Int((total.truncatingRemainder(dividingBy: 1)) * 100)
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centis)
        } else {
            return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
        }
    }
}
