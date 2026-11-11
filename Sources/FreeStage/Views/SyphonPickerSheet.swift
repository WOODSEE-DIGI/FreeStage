//
//  SyphonPickerSheet.swift
//  FreeStage
//
//  Sheet for choosing an available Syphon server to add as a layer source.
//

import SwiftUI
import Syphon

/// Displayable summary of a discovered Syphon server.
struct SyphonServerInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let appName: String
}

struct SyphonPickerSheet: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var servers: [SyphonServerInfo] = []
    @State private var selectedID: String?

    let onSelect: (Source) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Syphon Server")
                .font(.headline)

            if servers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Syphon servers found")
                        .font(.body)
                    Text("Make sure another app on this Mac is publishing a Syphon feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(servers, selection: $selectedID) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.body)
                            Text(server.appName.isEmpty ? "Unknown app" : server.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(server.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedID = server.id
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Layer") {
                    if let server = servers.first(where: { $0.id == selectedID }) {
                        let source = Source.syphon(
                            name: server.name,
                            appName: server.appName.isEmpty ? nil : server.appName,
                            uuid: server.id
                        )
                        onSelect(source)
                    }
                    dismiss()
                }
                .disabled(selectedID == nil)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 320)
        .onAppear(perform: refreshServers)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshServers()
        }
    }

    private func refreshServers() {
        let directory = SyphonServerDirectory.shared()
        let rawServers = directory.servers as [[String: Any]]
        servers = rawServers.compactMap { dict in
            guard let uuid = dict[SyphonServerDescriptionUUIDKey] as? String else { return nil }
            let name = (dict[SyphonServerDescriptionNameKey] as? String)?
                .trimmingCharacters(in: .whitespaces) ?? "Unnamed"
            let appName = (dict[SyphonServerDescriptionAppNameKey] as? String) ?? ""
            return SyphonServerInfo(id: uuid, name: name, appName: appName)
        }
    }
}
