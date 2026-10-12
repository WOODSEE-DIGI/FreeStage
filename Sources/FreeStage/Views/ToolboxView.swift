//
//  ToolboxView.swift
//  FreeStage
//
//  QLab-style left toolbox: miniature cue-type buttons.
//

import SwiftUI

struct ToolboxView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            toolboxButton("Camera", systemImage: "video.fill")
            toolboxButton("Color", systemImage: "paintpalette.fill")
            toolboxButton("Text", systemImage: "textformat")
            toolboxButton("Image", systemImage: "photo")
            toolboxButton("Fade", systemImage: "light.max")
            toolboxButton("Wait", systemImage: "clock")
            toolboxButton("Memo", systemImage: "note.text")

            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 64)
        .background(.ultraThinMaterial)
    }

    private func toolboxButton(_ title: String, systemImage: String) -> some View {
        Button {
            // Toolbox mirrors the toolbar; for now it adds a generic cue.
            store.addCue(source: .color(.black))
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(width: 52, height: 44)
        }
        .buttonStyle(.borderless)
    }
}
