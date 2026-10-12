//
//  FooterView.swift
//  FreeStage
//
//  QLab-style footer: Edit/Show mode, workspace toggles, cue count, and panic.
//

import SwiftUI

struct FooterView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        HStack(spacing: 16) {
            modePicker

            HStack(spacing: 8) {
                Button {
                    withAnimation { store.mastheadVisible.toggle() }
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .foregroundStyle(store.mastheadVisible ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Masthead")
            }

            Spacer()

            Button(role: .destructive) {
                store.panic()
            } label: {
                Label("Panic", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)

            Spacer()

            Text("\(store.show.cues.count) cue(s)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation { store.sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(store.sidebarVisible ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")

                Button {
                    withAnimation { store.inspectorVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                        .foregroundStyle(store.inspectorVisible ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            Text("Mode")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: Binding(
                get: { store.isEditMode },
                set: { store.isEditMode = $0 }
            )) {
                Text("Edit").tag(true)
                Text("Show").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .labelsHidden()
        }
    }
}
