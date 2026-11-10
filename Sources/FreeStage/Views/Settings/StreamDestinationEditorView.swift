//
//  StreamDestinationEditorView.swift
//  FreeStage
//
//  Sheet for adding or editing a stream destination.
//

import SwiftUI

struct StreamDestinationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var destination: StreamDestination
    let onSave: (StreamDestination) -> Void

    init(destination: StreamDestination, onSave: @escaping (StreamDestination) -> Void) {
        self._destination = State(initialValue: destination)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Destination")
                .font(.headline)

            Form {
                TextField("Name", text: $destination.name)

                Picker("Platform", selection: $destination.platform) {
                    ForEach(StreamingPlatform.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Server URL", text: $destination.serverURL)
                    .textContentType(.URL)

                SecureField("Stream Key", text: $destination.streamKey)

                Toggle("Enabled", isOn: $destination.isEnabled)

                HStack {
                    Text("Ingest URL preview:")
                        .font(.caption)
                    Text(destination.ingestURL?.absoluteString ?? "Invalid")
                        .font(.caption)
                        .foregroundStyle(destination.ingestURL == nil ? .red : .secondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button("Save") {
                    onSave(destination)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
}

#Preview {
    StreamDestinationEditorView(
        destination: StreamDestination(name: "Twitch", platform: .twitch, serverURL: "rtmp://live.twitch.tv/live", streamKey: "live_xxxx"),
        onSave: { _ in }
    )
}
