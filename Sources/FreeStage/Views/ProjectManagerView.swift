//
//  ProjectManagerView.swift
//  FreeStage
//
//  Project manager dashboard: create a new show, open an existing one, or pick
//  from recently opened shows. Inspired by DaVinci Resolve's project manager.
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectManagerView: View {
    @Environment(ShowStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ThemeStore.self) private var theme
    @Binding var isPresented: Bool
    @State private var errorMessage: String?
    @State private var showingError = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 16)
    ]

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        actionCards

                        if !settings.recentShows.isEmpty {
                            recentShowsSection
                        }
                    }
                    .padding(40)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert("Could not open show", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("FreeStage")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(theme.text)
                Text("Project Manager")
                    .font(.title2)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .background(theme.panelBackground)
    }

    private var actionCards: some View {
        HStack(spacing: 16) {
            ActionCard(
                title: "New Theatre Show",
                subtitle: ShowKind.theatre.subtitle,
                icon: "theatermasks",
                color: theme.accent
            ) {
                createNewShow(kind: .theatre)
            }

            ActionCard(
                title: "New Presenter Show",
                subtitle: ShowKind.presenter.subtitle,
                icon: "video.bubble.left",
                color: theme.selected
            ) {
                createNewShow(kind: .presenter)
            }

            ActionCard(
                title: "Open Show…",
                subtitle: "Browse for a saved .fst show package.",
                icon: "folder",
                color: theme.secondaryText
            ) {
                openShowFromPanel()
            }
        }
    }

    private var recentShowsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Shows")
                    .font(.title2.bold())
                    .foregroundStyle(theme.text)

                Spacer()

                Text("\(settings.recentShows.count) show(s)")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(settings.recentShows) { recent in
                    RecentShowCard(recent: recent, theme: theme) {
                        openRecentShow(recent)
                    } onRemove: {
                        settings.removeRecentShow(id: recent.id)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func createNewShow(kind: ShowKind) {
        switch kind {
        case .theatre:
            store.show = .theatreDefault(style: settings.defaultShowStyle)
            store.resetWorkspace()
        case .presenter:
            store.show = .presenterDefault(style: settings.defaultShowStyle)
            store.resetWorkspace()
        }
        isPresented = false
    }

    private func openShowFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.freeStageShow]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            loadShow(from: url)
        }
    }

    private func openRecentShow(_ recent: RecentShow) {
        guard let url = recent.resolvedURL else {
            presentError("The saved show could not be found.")
            settings.removeRecentShow(id: recent.id)
            return
        }
        loadShow(from: url)
    }

    private func loadShow(from url: URL) {
        do {
            let (show, bookmark) = try accessSecurityScopedResource(url: url) {
                let bookmark = SecurityScopedBookmark.create(for: url)
                let show = try ShowPackage.read(from: url)
                return (show, bookmark)
            }
            store.load(show: show)
            settings.addRecentShow(url: url, bookmarkData: bookmark)
            isPresented = false
        } catch {
            presentError(error.localizedDescription)
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Action card

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent show card

private struct RecentShowCard: View {
    let recent: RecentShow
    let theme: ThemeStore
    let action: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "film.stack")
                        .font(.title2)
                        .foregroundStyle(theme.accent)
                    Spacer()
                }

                Text(recent.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(theme.text)

                Text(recent.path)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)

                Spacer()

                Text(recent.dateAdded, style: .date)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .padding()
            .background(theme.panelBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recent", role: .destructive) {
                onRemove()
            }
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true
    ProjectManagerView(isPresented: $isPresented)
        .environment(ShowStore())
        .environment(AppSettings())
        .environment(ThemeStore())
}
