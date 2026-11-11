//
//  VideoControlsView.swift
//  FreeStage
//
//  Inspector controls for a video/media layer source.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var isPicking = false

    var body: some View {
        GroupBox("Video") {
            VStack(alignment: .leading, spacing: 12) {
                if let url = store.selectedLayerMedia {
                    HStack {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Change…") {
                            isPicking = true
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Text("No video selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose Video…") {
                            isPicking = true
                        }
                        .font(.caption)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding([.horizontal, .top])
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                store.updateSelectedLayer { layer in
                    guard case .media = layer.source else { return }
                    layer.source = .media(url: url)
                }
            case .failure:
                break
            }
        }
    }
}
