//
//  SlideshowPickerSheet.swift
//  FreeStage
//
//  Sheet for choosing a folder or multiple images to create a slideshow source.
//

import SwiftUI
import UniformTypeIdentifiers

struct SlideshowPickerSheet: View {
    let onSelect: (SlideshowSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var interval: TimeInterval = 5.0
    @State private var transition: SlideTransition = .cut
    @State private var shuffle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Slideshow")
                .font(.headline)

            Text("Choose a folder of images. FreeStage will cycle through them in layer order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Form {
                Picker("Transition", selection: $transition) {
                    ForEach(SlideTransition.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Interval")
                    Spacer()
                    Picker("", selection: $interval) {
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

                Toggle("Shuffle order", isOn: $shuffle)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button("Choose Folder…") {
                    pickFolder()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Slideshow Folder"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let urls = imageURLs(in: url)
            guard !urls.isEmpty else { return }
            let slideshow = SlideshowSource(
                imageURLs: urls,
                interval: interval,
                transition: transition,
                shuffle: shuffle
            )
            onSelect(slideshow)
            dismiss()
        }
    }

    private func imageURLs(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        let allowed = Set(["jpg", "jpeg", "png", "heic", "tif", "tiff", "bmp"])
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if allowed.contains(ext) {
                urls.append(fileURL)
            }
        }
        return urls.sorted { $0.path < $1.path }
    }
}
