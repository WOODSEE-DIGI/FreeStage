//
//  NDIPickerSheet.swift
//  FreeStage
//
//  Sheet for choosing an available NDI source to add as a layer source.
//

import SwiftUI

struct NDIPickerSheet: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [NDISourceInfo] = []
    @State private var selectedID: String?

    let onSelect: (Source) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Select NDI Source")
                .font(.headline)

            if sources.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No NDI sources found")
                        .font(.body)
                    Text("Make sure an NDI sender is running on this Mac or the local network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sources, selection: $selectedID) { source in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.body)
                        }
                        Spacer()
                    }
                    .tag(source.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedID = source.id
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Add Layer") {
                    if let source = sources.first(where: { $0.id == selectedID }) {
                        onSelect(.ndi(name: source.name))
                    }
                    dismiss()
                }
                .disabled(selectedID == nil)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 320)
        .onAppear(perform: refreshSources)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshSources()
        }
    }

    private func refreshSources() {
        sources = NDISourceRenderer.discoverSources()
    }
}
