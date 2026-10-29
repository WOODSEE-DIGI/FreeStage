//
//  CueListView.swift
//  FreeStage
//
//  QLab-style ordered cue list table with status, number, name, target,
//  pre-wait, duration, post-wait, and continue columns.
//

import SwiftUI

struct CueListView: View {
    @Environment(ShowStore.self) private var store
    @Environment(\.appSettings) private var appSettings

    var body: some View {
        @Bindable var store = store

        Table(of: Cue.self, selection: $store.activeCueID) {
            TableColumn("") { cue in
                HStack(spacing: 4) {
                    statusIcon(for: cue)
                    if cue.id == store.activeCueID {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
            .width(48)

            TableColumn("Number") { cue in
                Text(cue.number)
                    .font(.system(.body, design: .monospaced))
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(min: 40, ideal: 60)

            TableColumn("Name") { cue in
                Text(cue.name)
                    .lineLimit(1)
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(min: 80, ideal: 140)

            TableColumn("Scene") { cue in
                Text(sceneName(for: cue))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(min: 60, ideal: 100)

            TableColumn("Pre Wait") { cue in
                Text(formatTime(cue.preWait))
                    .monospacedDigit()
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(60)

            TableColumn("Duration") { cue in
                Text(formatTime(cue.duration))
                    .monospacedDigit()
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(60)

            TableColumn("Post Wait") { cue in
                Text(formatTime(cue.postWait))
                    .monospacedDigit()
                    .cellBackground(cue.color?.swiftUIColor)
            }
            .width(60)

            TableColumn("") { cue in
                if cue.continueMode != .none {
                    Image(systemName: cue.continueMode.systemImage)
                        .foregroundStyle(.secondary)
                }
            }
            .width(40)

            TableColumn("") { cue in
                Button {
                    store.triggerCue(id: cue.id)
                } label: {
                    Image(systemName: "play.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Fire cue directly")
                .disabled(!cue.isArmed)
            }
            .width(32)
        } rows: {
            ForEach(store.show.cues) { cue in
                TableRow(cue)
                    .contextMenu {
                        Button("Fire Cue") {
                            store.triggerCue(id: cue.id)
                        }
                        .disabled(!cue.isArmed)
                        Divider()
                        Button("Select as Next") {
                            store.selectCue(id: cue.id)
                        }
                        Button("Duplicate Cue") {
                            store.duplicateCue(id: cue.id)
                        }
                        Divider()
                        Button("Copy HTTP Trigger URL") {
                            copyHTTPTriggerURL(for: cue)
                        }
                        Button("Copy OSC Trigger Address") {
                            copyOSCTriggerAddress(for: cue)
                        }
                    }
            }
        }

    }

    private func statusIcon(for cue: Cue) -> some View {
        let name: String
        let color: Color

        if !cue.isArmed {
            name = "slash.circle"
            color = .red
        } else if cue.id == store.activeCueID {
            name = "play.fill"
            color = .green
        } else if cue.isFlagged {
            name = "flag.fill"
            color = .yellow
        } else {
            name = "circle.fill"
            color = cue.color?.swiftUIColor ?? .clear
        }

        return Image(systemName: name)
            .foregroundStyle(color)
            .font(.caption)
    }

    private func sceneName(for cue: Cue) -> String {
        store.show.scene(withID: cue.sceneID)?.name ?? "Missing scene"
    }

    private func copyHTTPTriggerURL(for cue: Cue) {
        let port = appSettings?.cueTriggerServerPort ?? 17352
        let url = "http://localhost:\(port)/cue/\(cue.id.uuidString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    private func copyOSCTriggerAddress(for cue: Cue) {
        let address = "/freestage/cue/\(cue.id.uuidString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }
}

private func formatTime(_ interval: TimeInterval) -> String {
    guard interval > 0 else { return "" }
    return String(format: "%.2f", interval)
}

private extension View {
    /// Fill a table cell and tint it with the cue's list color so the whole
    /// row appears colored instead of just the status dot.
    func cellBackground(_ color: Color?) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color?.opacity(0.15) ?? Color.clear)
    }
}
