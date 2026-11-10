//
//  StreamingStatusView.swift
//  FreeStage
//
//  Compact stream status + start/stop controls for the mixer/masthead.
//

import SwiftUI

struct StreamingStatusView: View {
    @Environment(\.streamingService) private var streamingService

    var body: some View {
        HStack(spacing: 12) {
            streamingIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(streamingService?.statusMessage ?? "Unavailable")
                    .font(.caption.bold())
                    .foregroundStyle(streamingService?.isStreaming == true ? .red : .primary)

                if let service = streamingService, service.isStreaming {
                    Text(format(duration: service.streamDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            destinationMenu

            Button(action: toggleStreaming) {
                Image(systemName: streamingService?.isStreaming == true ? "stop.fill" : "dot.radiowaves.left.and.right")
                Text(streamingService?.isStreaming == true ? "Stop Stream" : "Go Live")
            }
            .buttonStyle(.borderedProminent)
            .tint(streamingService?.isStreaming == true ? .red : .blue)
            .disabled(streamingService == nil || (streamingService?.isStreaming == false && (streamingService?.destinations.isEmpty ?? true)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if streamingService?.isStreaming == true {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolEffect(.pulse)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var destinationMenu: some View {
        if let service = streamingService, !service.isStreaming {
            Menu {
                ForEach(service.destinations.filter(\.isEnabled)) { destination in
                    Button(destination.name) {
                        Task {
                            await service.startStreaming(to: destination.id)
                        }
                    }
                }
            } label: {
                Label("Destination", systemImage: "globe")
            }
            .disabled(service.destinations.filter(\.isEnabled).isEmpty)
        }
    }

    private func toggleStreaming() {
        guard let service = streamingService else { return }
        if service.isStreaming {
            service.stopStreaming()
        }
    }

    private func format(duration: TimeInterval) -> String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

#Preview {
    StreamingStatusView()
        .environment(\.streamingService, StreamingService())
        .padding()
}
