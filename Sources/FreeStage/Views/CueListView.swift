//
//  CueListView.swift
//  FreeStage
//
//  QLab-style ordered cue list with status, number, name, target,
//  pre-wait, duration, post-wait, and continue columns.
//
//  Implemented as a custom list so each cue row can be tinted with one
//  continuous background color instead of the chopped-up cell tint that
//  SwiftUI's Table renders.
//

import SwiftUI

struct CueListView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    @Environment(AppSettings.self) private var appSettings

    // Column widths must match between header and rows.
    private let statusWidth: CGFloat = 56
    private let numberWidth: CGFloat = 60
    private let nameWidth: CGFloat = 140
    private let sceneWidth: CGFloat = 100
    private let timeWidth: CGFloat = 60
    private let continueWidth: CGFloat = 40
    private let fireWidth: CGFloat = 32

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(theme.panelBackground.opacity(0.8))

            Divider()

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.show.cues) { cue in
                            cueRow(cue)
                                .id(cue.id)
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
                    .padding(.vertical, 2)
                }
                .onChange(of: store.activeCueID) { _, newID in
                    if let newID {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(theme.panelBackground)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: statusWidth, alignment: .leading)

            Text("Number")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: numberWidth, alignment: .leading)

            Text("Name")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: nameWidth, alignment: .leading)

            Text("Scene")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: sceneWidth, alignment: .leading)

            Text("Pre Wait")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: timeWidth, alignment: .leading)

            Text("Duration")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: timeWidth, alignment: .leading)

            Text("Post Wait")
                .font(.caption.bold())
                .foregroundStyle(theme.secondaryText)
                .frame(width: timeWidth, alignment: .leading)

            Text("")
                .frame(width: continueWidth, alignment: .center)

            Text("")
                .frame(width: fireWidth, alignment: .center)

            Spacer()
        }
    }

    // MARK: - Row

    private func cueRow(_ cue: Cue) -> some View {
        let isActive = cue.id == store.activeCueID
        let rowColor = cue.color?.swiftUIColor

        return HStack(spacing: 0) {
            statusCell(for: cue)
                .frame(width: statusWidth, alignment: .leading)

            Text(cue.number)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(theme.text)
                .frame(width: numberWidth, alignment: .leading)

            Text(cue.name)
                .lineLimit(1)
                .foregroundStyle(theme.text)
                .frame(width: nameWidth, alignment: .leading)

            Text(sceneName(for: cue))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .frame(width: sceneWidth, alignment: .leading)

            Text(formatTime(cue.preWait))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: timeWidth, alignment: .leading)

            Text(formatTime(cue.duration))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: timeWidth, alignment: .leading)

            Text(formatTime(cue.postWait))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: timeWidth, alignment: .leading)

            HStack {
                Spacer()
                if cue.continueMode != .none {
                    Image(systemName: cue.continueMode.systemImage)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
            }
            .frame(width: continueWidth)

            HStack {
                Spacer()
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
                Spacer()
            }
            .frame(width: fireWidth)

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .background(
            rowColor?.opacity(0.28)
                ?? (isActive ? theme.selected.opacity(0.12) : Color.clear)
        )
        .overlay(
            Rectangle()
                .stroke(theme.selected, lineWidth: isActive ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectCue(id: cue.id)
        }
    }

    private func statusCell(for cue: Cue) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(cue.color?.swiftUIColor ?? .clear)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))

            statusIcon(for: cue)

            if cue.id == store.activeCueID {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
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
        let port = appSettings.cueTriggerServerPort
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
