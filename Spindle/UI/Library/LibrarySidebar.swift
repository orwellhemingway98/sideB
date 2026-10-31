import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibrarySidebar: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore
    @State private var link = ""

    var body: some View {
        List(selection: $model.section) {
            Section {
                TextField("Search podcasts", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.search() } }
                if let message = model.searchMessage { Note(text: message) }
                ForEach(model.results) { result in
                    HStack(spacing: 8) {
                        ArtworkView(cache: model.artwork, url: result.artworkURL, seed: result.title,
                                    size: 28, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).lineLimit(1)
                            if !result.author.isEmpty {
                                Text(result.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Button("Follow") { Task { await model.follow(result) } }
                    }
                }
            }

            Section("Library") {
                Text("Up Next").tag(LibrarySection.upNext)
                Text("New Episodes").tag(LibrarySection.newEpisodes)
                Text("Shows").tag(LibrarySection.shows)
                Text("Downloaded").tag(LibrarySection.downloaded)
            }

            Section("Following") {
                ForEach(library.shows) { show in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.title).lineLimit(1)
                        if show.lastError != nil { Note(text: Self.brokenNote(for: show)) }
                    }
                    .tag(LibrarySection.show(show.persistentModelID))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Add by link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLink)
                Button("Add", action: addLink)
            }
            if let message = model.linkMessage { Note(text: message) }
            HStack {
                Button("Import OPML…", action: importOPML)
                Spacer()
                if let scheduler = model.scheduler { RefreshButton(scheduler: scheduler) }
            }
            if let message = model.importMessage { Note(text: message) }
        }
        .padding(10)
    }

    private func addLink() {
        let text = link
        Task {
            await model.addByLink(text)
            if model.linkMessage == nil { link = "" }
        }
    }

    private func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "opml") ?? .xml, .xml]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the OPML file your old podcast app exported."
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        Task { await model.importOPML(data) }
    }

    /// "Couldn't update · last worked 12 Oct 2026".
    static func brokenNote(for show: Show) -> String {
        guard let date = show.lastUpdated else { return "Couldn't update" }
        return "Couldn't update \u{00B7} last worked \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct RefreshButton: View {
    @ObservedObject var scheduler: RefreshScheduler

    var body: some View {
        Button(scheduler.isRefreshing ? "Refreshing…" : "Refresh") {
            Task { await scheduler.refreshNow() }
        }
        .disabled(scheduler.isRefreshing)
    }
}

/// A small secondary line under a field.
struct Note: View {
    let text: String

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
