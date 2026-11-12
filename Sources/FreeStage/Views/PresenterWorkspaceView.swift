//
//  PresenterWorkspaceView.swift
//  FreeStage
//
//  Streamlined workspace for presenter-to-camera shows. Replaces the theatre
//  cue/scene/layer UI with a segment rundown, live camera monitor, preview,
//  and placeholder panel.
//

import SwiftUI

struct PresenterWorkspaceView: View {
    @Environment(ShowStore.self) private var store
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Text(store.show.name)
                        .font(.title2.bold())
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("Presenter Mode")
                        .font(.caption.bold())
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.panelBackground)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    segmentRundown
                        .frame(minWidth: 240, idealWidth: 280)

                    VStack(spacing: 16) {
                        liveMonitor
                        previewMonitor
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    placeholderPanel
                        .frame(minWidth: 240, idealWidth: 280)
                }
                .padding(.horizontal)

                transportBar
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .padding(.vertical)
        }
    }

    // MARK: - Subviews (placeholders)

    private var segmentRundown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rundown")
                .font(.headline)
                .foregroundStyle(theme.text)
                .padding()

            if let segments = store.presenterRundown?.segments, !segments.isEmpty {
                List(selection: .constant(store.activeSegmentID)) {
                    ForEach(segments) { segment in
                        HStack {
                            Image(systemName: segment.type.iconName)
                                .foregroundStyle(theme.accent)
                            Text(segment.name)
                                .foregroundStyle(theme.text)
                            Spacer()
                            if segment.id == store.liveSegmentID {
                                Image(systemName: "record.circle.fill")
                                    .foregroundStyle(.red)
                            } else if segment.id == store.activeSegmentID {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(theme.selected)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectSegment(id: segment.id)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("No Segments", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var liveMonitor: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text("Live")
                    .font(.caption.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Text(store.liveSegment?.name ?? "—")
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 8)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .overlay(
                    Text("Live Output")
                        .foregroundStyle(theme.secondaryText)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var previewMonitor: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Preview")
                    .font(.caption.bold())
                    .foregroundStyle(theme.text)
                Spacer()
                Text(store.activeSegment?.name ?? "—")
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.horizontal, 8)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .overlay(
                    Text("Preview Output")
                        .foregroundStyle(theme.secondaryText)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholderPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Placeholders")
                .font(.headline)
                .foregroundStyle(theme.text)
                .padding()

            if let placeholders = store.presenterRundown?.placeholders, !placeholders.isEmpty {
                List {
                    ForEach(placeholders) { placeholder in
                        HStack {
                            Text(placeholder.name)
                                .foregroundStyle(theme.text)
                            Spacer()
                            if placeholder.source != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selectedPlaceholderID = placeholder.id
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("No Placeholders", systemImage: "square.dashed")
                    .foregroundStyle(theme.secondaryText)
            }

            Button("Add Placeholder") {
                store.addPresenterPlaceholder()
            }
            .padding()
        }
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var transportBar: some View {
        HStack(spacing: 16) {
            Button {
                store.selectPreviousSegment()
            } label: {
                Label("Previous", systemImage: "backward.frame")
            }

            Spacer()

            Button {
                store.presenterGo()
            } label: {
                Label("GO", systemImage: "play.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()

            Button {
                store.selectNextSegment()
            } label: {
                Label("Next", systemImage: "forward.frame")
            }
        }
        .padding()
        .background(theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
