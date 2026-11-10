//
//  StreamDestinationsSettingsView.swift
//  FreeStage
//
//  Settings panel for managing RTMP/RTMPS stream destinations.
//

import SwiftUI

struct StreamDestinationsSettingsView: View {
    @Environment(\.streamingService) private var streamingService
    @State private var selection: StreamDestination?
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stream Destinations")
                .font(.title2.bold())

            Text("Add RTMP destinations such as Twitch, YouTube, Facebook Live, or a custom ingest server.")
                .foregroundStyle(.secondary)

            HStack {
                List(streamingService?.destinations ?? [], selection: $selection) { destination in
                    DestinationRow(destination: destination)
                        .tag(destination)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Button("Add Destination") {
                        let newDestination = StreamDestination(
                            name: "New Destination",
                            platform: .custom,
                            serverURL: "",
                            streamKey: ""
                        )
                        streamingService?.addDestination(newDestination)
                        selection = newDestination
                        isEditing = true
                    }

                    Button("Edit") {
                        isEditing = true
                    }
                    .disabled(selection == nil)

                    Button("Delete") {
                        if let selection {
                            streamingService?.removeDestination(id: selection.id)
                        }
                    }
                    .disabled(selection == nil)

                    Spacer()
                }
                .frame(width: 140)
                .padding(.leading, 8)
            }

            if let service = streamingService {
                HStack(spacing: 16) {
                    Toggle("Auto-reconnect", isOn: .constant(service.autoReconnect))
                        .disabled(true)
                    Text("Max attempts: \(service.maxReconnectAttempts)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .sheet(item: $selection) { destination in
            StreamDestinationEditorView(
                destination: destination,
                onSave: { updated in
                    streamingService?.updateDestination(updated)
                    selection = updated
                }
            )
        }
    }
}

private struct DestinationRow: View {
    let destination: StreamDestination

    var body: some View {
        HStack {
            Image(systemName: destination.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(destination.isEnabled ? .green : .secondary)

            VStack(alignment: .leading) {
                Text(destination.name)
                    .font(.headline)
                Text("\(destination.platform.displayName) • \(destination.serverURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    StreamDestinationsSettingsView()
        .environment(\.streamingService, StreamingService())
}
