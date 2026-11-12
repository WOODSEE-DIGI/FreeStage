//
//  LibrarySetupView.swift
//  FreeStage
//
//  First-run setup sheet: choose where the show library lives and create the
//  folder template (GlobalAssets, Shows, Output).
//

import SwiftUI
import AppKit

struct LibrarySetupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoot: URL
    @State private var failureMessage: String?

    private let folders = ShowLibrary.templateFolders

    init(initialRoot: URL) {
        _selectedRoot = State(initialValue: initialRoot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    locationSection
                    previewSection
                }
                .padding(24)
            }
            .frame(maxHeight: 320)

            Divider()

            footer
        }
        .frame(width: 620)
        .background(theme.background)
        .interactiveDismissDisabled()
        .onAppear {
            // Start from whatever root the app already resolved (default or stored).
            selectedRoot = settings.libraryRoot
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Set Up Your Show Library")
                    .font(.title2.bold())
                    .foregroundStyle(theme.text)
                Text("FreeStage keeps shared assets, saved shows and output in one library folder. Choose where it should live — you can move it later in Settings.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(theme.panelBackground)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library Location")
                .font(.headline)
                .foregroundStyle(theme.text)

            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .foregroundStyle(theme.secondaryText)
                Text(selectedRoot.path)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(theme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.border, lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button("Choose Folder…") { chooseFolder() }
                Button("Use Default Location") { selectedRoot = ShowLibrary.defaultRoot() }
                    .disabled(selectedRoot.path == ShowLibrary.defaultRoot().path)
                Spacer()
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders to Create")
                .font(.headline)
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(folders) { folder in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: folder.symbolName)
                            .frame(width: 18)
                            .foregroundStyle(folder.depth == 0 ? theme.accent : theme.secondaryText)
                        Text(folder.name)
                            .font(folder.depth == 0 ? .callout.bold() : .callout)
                            .foregroundStyle(theme.text)
                        Text(folder.summary)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(folder.depth) * 20)
                }
            }

            Text("Existing files are never touched — missing folders are simply recreated.")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            Button("Skip for Now") {
                // Remember the skip so the sheet does not nag on every launch;
                // the template is created by the launch repair pass instead.
                settings.hasCompletedLibrarySetup = true
                dismiss()
            }
            .help("Keep the default location. Folders are created the next time FreeStage starts.")

            Button("Create Library") { createLibrary() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = selectedRoot
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder that will hold your FreeStage library."

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            selectedRoot = url
            failureMessage = nil
        }
    }

    private func createLibrary() {
        failureMessage = nil

        let result = settings.completeLibrarySetup(root: selectedRoot)

        if let failure = result.failures.first {
            failureMessage = "Could not create \(failure.path): \(failure.reason)"
            return
        }
        dismiss()
    }
}

#Preview {
    LibrarySetupView(initialRoot: ShowLibrary.defaultRoot())
        .environment(AppSettings())
        .environment(ThemeStore())
}
