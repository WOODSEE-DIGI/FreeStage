//
//  SlideshowControlsView.swift
//  FreeStage
//
//  Inspector controls for a slideshow layer.
//

import SwiftUI

struct SlideshowControlsView: View {
    @Environment(ShowStore.self) private var store
    @State private var isReplacingImages = false

    var body: some View {
        GroupBox("Slideshow") {
            if let slideshow = store.selectedLayerSlideshow {
                controls(for: slideshow)
            } else {
                Text("Select a slideshow layer to edit its settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding([.horizontal, .top])
        .sheet(isPresented: $isReplacingImages) {
            SlideshowPickerSheet { slideshow in
                store.updateSelectedLayer { layer in
                    guard case .slideshow(var existing) = layer.source else { return }
                    existing.imageURLs = slideshow.imageURLs
                    existing.interval = slideshow.interval
                    existing.transition = slideshow.transition
                    existing.shuffle = slideshow.shuffle
                    layer.source = .slideshow(existing)
                }
            }
        }
    }

    private func controls(for slideshow: SlideshowSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(slideshow.imageURLs.count) image(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Replace Images…") {
                    isReplacingImages = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            Picker("Transition", selection: binding(\.transition)) {
                ForEach(SlideTransition.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Interval")
                Spacer()
                Picker("", selection: binding(\.interval)) {
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                    Text("15 s").tag(15.0)
                    Text("30 s").tag(30.0)
                    Text("60 s").tag(60.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            Toggle("Shuffle order", isOn: binding(\.shuffle))

            if slideshow.imageURLs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(slideshow.imageURLs.prefix(20), id: \.self) { url in
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Color.secondary.opacity(0.2)
                                }
                            }
                            .frame(width: 48, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<SlideshowSource, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                store.selectedLayerSlideshow?[keyPath: keyPath] ?? defaultValue(for: keyPath)
            },
            set: { newValue in
                store.updateSelectedLayer { layer in
                    guard case .slideshow(var slideshow) = layer.source else { return }
                    slideshow[keyPath: keyPath] = newValue
                    layer.source = .slideshow(slideshow)
                }
            }
        )
    }

    private func defaultValue<Value>(for keyPath: WritableKeyPath<SlideshowSource, Value>) -> Value {
        let defaultSource = SlideshowSource()
        return defaultSource[keyPath: keyPath]
    }
}
