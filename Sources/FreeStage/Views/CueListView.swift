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
            }
            .width(min: 40, ideal: 60)

            TableColumn("Name") { cue in
                Text(cue.name)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 140)

            TableColumn("Target") { cue in
                Text(targetDescription(for: cue))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 100)

            TableColumn("Pre Wait") { cue in
                Text(formatTime(cue.preWait))
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("Duration") { cue in
                Text(formatTime(cue.duration))
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("Post Wait") { cue in
                Text(formatTime(cue.postWait))
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("") { cue in
                if cue.continueMode != .none {
                    Image(systemName: cue.continueMode.systemImage)
                        .foregroundStyle(.secondary)
                }
            }
            .width(40)
        } rows: {
            ForEach(store.show.cues) { cue in
                TableRow(cue)
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

    private func targetDescription(for cue: Cue) -> String {
        if let targetID = cue.targetID,
           let target = store.show.cues.first(where: { $0.id == targetID }) {
            return target.number.isEmpty ? target.name : target.number
        }
        return ""
    }
}

private func formatTime(_ interval: TimeInterval) -> String {
    guard interval > 0 else { return "" }
    return String(format: "%.2f", interval)
}
