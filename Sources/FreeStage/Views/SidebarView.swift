//
//  SidebarView.swift
//  FreeStage
//
//  QLab-style right sidebar: playback controls, lists/carts, and active cues.
//

import SwiftUI

struct SidebarView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sidebarButton("Reset", systemImage: "backward.end.fill", color: .secondary) {
                    store.resetWorkspace()
                }
                sidebarButton("Pause", systemImage: "pause.fill", color: .yellow) {
                    store.pauseAll()
                }
                sidebarButton("Resume", systemImage: "play.fill", color: .green) {
                    store.resumeAll()
                }
                sidebarButton("Panic", systemImage: "exclamationmark.triangle.fill", color: .red) {
                    store.panic()
                }
            }
            .padding()

            Divider()

            TabView {
                listsTab
                    .tabItem { Label("Lists", systemImage: "list.bullet") }

                activeCuesTab
                    .tabItem { Label("Active", systemImage: "play.rectangle") }
            }
        }
        .frame(minWidth: 220, idealWidth: 260)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
    }

    private var listsTab: some View {
        List {
            Section("Cue Lists") {
                Text("Main Cue List")
                    .font(.headline)
            }
        }
        .listStyle(.sidebar)
    }

    private var activeCuesTab: some View {
        List {
            if let cue = store.liveCue {
                Label(cue.name, systemImage: "play.fill")
                    .foregroundStyle(.green)
            } else {
                Text("No active cues")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }
}
