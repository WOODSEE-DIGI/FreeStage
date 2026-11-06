//
//  PlaylistControlsView.swift
//  FreeStage
//
//  Inspector controls for a playlist-rotation template layer.
//

import SwiftUI

struct PlaylistControlsView: View {
    @Environment(ShowStore.self) private var store

    var body: some View {
        GroupBox("Playlist") {
            VStack(alignment: .leading, spacing: 12) {
                itemsSection

                Divider()

                HStack(spacing: 16) {
                    durationControl
                    crossfadeControl
                }

                HStack(spacing: 16) {
                    fontSizeControl
                    subtitleFontSizeControl
                }

                HStack(spacing: 16) {
                    colorRow("Text", binding: textColorBinding)
                    colorRow("Accent", binding: accentColorBinding)
                }

                colorRow("Background", binding: backgroundColorBinding)

                Toggle("Loop", isOn: loopBinding)

                AnimationControlsView()
            }
        }
        .padding([.horizontal, .top])
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            ForEach(Array((store.selectedLayerPlaylist?.items ?? []).enumerated()), id: \.offset) { index, item in
                itemRow(item: item, index: index)
            }
        }
    }

    private func itemRow(item: PlaylistItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Title", text: Binding(
                    get: { item.title },
                    set: { newValue in updateItem(at: index) { $0.title = newValue } }
                ))
                .textFieldStyle(.roundedBorder)

                Picker("", selection: Binding(
                    get: { item.style },
                    set: { newValue in updateItem(at: index) { $0.style = newValue } }
                )) {
                    ForEach(PlaylistItemStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Button {
                    removeItem(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            TextField("Subtitle", text: Binding(
                get: { item.subtitle },
                set: { newValue in updateItem(at: index) { $0.subtitle = newValue } }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Text("Duration: \(String(format: "%.1f", item.duration))s")
                    .font(.caption2)
                Slider(value: Binding(
                    get: { item.duration },
                    set: { newValue in updateItem(at: index) { $0.duration = newValue } }
                ), in: 1...30, step: 0.5)
            }
        }
    }

    private var durationControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Duration: \(String(format: "%.1f", store.selectedLayerPlaylist?.displayDuration ?? 5))s")
                .font(.caption2)
            Slider(value: displayDurationBinding, in: 1...30, step: 0.5)
        }
    }

    private var crossfadeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Crossfade: \(String(format: "%.1f", store.selectedLayerPlaylist?.crossfadeDuration ?? 0.5))s")
                .font(.caption2)
            Slider(value: crossfadeDurationBinding, in: 0...2, step: 0.1)
        }
    }

    private var fontSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Title: \(Int(store.selectedLayerPlaylist?.fontSize ?? 42))")
                .font(.caption2)
            Slider(value: fontSizeBinding, in: 8...120, step: 1)
        }
    }

    private var subtitleFontSizeControl: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Subtitle: \(Int(store.selectedLayerPlaylist?.subtitleFontSize ?? 24))")
                .font(.caption2)
            Slider(value: subtitleFontSizeBinding, in: 8...80, step: 1)
        }
    }

    private func colorRow(_ label: String, binding: Binding<Color>) -> some View {
        HStack(spacing: 6) {
            Text(label)
            ColorPicker("", selection: binding)
                .labelsHidden()
            Spacer()
        }
    }

    private func addItem() {
        store.updateSelectedLayer { layer in
            guard case .playlist(var playlist) = layer.source else { return }
            playlist.items.append(PlaylistItem())
            layer.source = .playlist(playlist)
        }
    }

    private func removeItem(at index: Int) {
        store.updateSelectedLayer { layer in
            guard case .playlist(var playlist) = layer.source else { return }
            guard index < playlist.items.count else { return }
            playlist.items.remove(at: index)
            layer.source = .playlist(playlist)
        }
    }

    private func updateItem(at index: Int, mutation: (inout PlaylistItem) -> Void) {
        store.updateSelectedLayer { layer in
            guard case .playlist(var playlist) = layer.source else { return }
            guard index < playlist.items.count else { return }
            mutation(&playlist.items[index])
            layer.source = .playlist(playlist)
        }
    }

    private var displayDurationBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerPlaylist?.displayDuration ?? 5 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    playlist.displayDuration = newValue
                    layer.source = .playlist(playlist)
                }
            }
        )
    }

    private var crossfadeDurationBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerPlaylist?.crossfadeDuration ?? 0.5 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    playlist.crossfadeDuration = newValue
                    layer.source = .playlist(playlist)
                }
            }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerPlaylist?.fontSize ?? 42 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    playlist.fontSize = newValue
                    layer.source = .playlist(playlist)
                }
            }
        )
    }

    private var subtitleFontSizeBinding: Binding<Double> {
        Binding(
            get: { store.selectedLayerPlaylist?.subtitleFontSize ?? 24 },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    playlist.subtitleFontSize = newValue
                    layer.source = .playlist(playlist)
                }
            }
        )
    }

    private var textColorBinding: Binding<Color> {
        colorBinding(for: \.textColor)
    }

    private var accentColorBinding: Binding<Color> {
        colorBinding(for: \.accentColor)
    }

    private var backgroundColorBinding: Binding<Color> {
        colorBinding(for: \.backgroundColor)
    }

    private var loopBinding: Binding<Bool> {
        Binding(
            get: { store.selectedLayerPlaylist?.loop ?? true },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    playlist.loop = newValue
                    layer.source = .playlist(playlist)
                }
            }
        )
    }

    private func colorBinding(for keyPath: KeyPath<PlaylistSource, CGColorComponents>) -> Binding<Color> {
        Binding(
            get: {
                guard let source = store.selectedLayerPlaylist else { return .white }
                let components = source[keyPath: keyPath]
                return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
            },
            set: { newValue in
                let rgb = RGBColor(color: newValue)
                let opacity = newValue.cgColor?.alpha ?? 1.0
                store.updateSelectedLayer { layer in
                    guard case .playlist(var playlist) = layer.source else { return }
                    let components = CGColorComponents(r: rgb.r, g: rgb.g, b: rgb.b, a: Double(opacity))
                    switch keyPath {
                    case \.textColor: playlist.textColor = components
                    case \.accentColor: playlist.accentColor = components
                    case \.backgroundColor: playlist.backgroundColor = components
                    default: break
                    }
                    layer.source = .playlist(playlist)
                }
            }
        )
    }
}
