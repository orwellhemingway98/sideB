import AppKit
import SwiftUI

/// What the Library window does: search the directory, follow by result or pasted link, pick a show.
@MainActor
final class LibraryViewModel: ObservableObject {
    static let searchFailed = "Search isn't available right now."
    static let notAFeed = "That link isn't a podcast feed."
    static let followFailed = "Couldn't follow that show."

    let library: LibraryStore
    let nowPlaying: NowPlaying
    private let fetcher: HTTPFetching

    @Published var query = ""
    @Published private(set) var results: [DirectoryResult] = []
    /// Shown under the search field: search and follow-from-results failures.
    @Published private(set) var searchMessage: String?
    /// Shown under the Add by link field.
    @Published private(set) var linkMessage: String?
    @Published var selectedShow: Show?

    init(library: LibraryStore, fetcher: HTTPFetching, nowPlaying: NowPlaying) {
        self.library = library
        self.fetcher = fetcher
        self.nowPlaying = nowPlaying
    }

    func search() async {
        do {
            results = try await DirectorySearch.search(query, fetcher: fetcher)
            searchMessage = nil
        } catch {
            results = []
            searchMessage = Self.searchFailed
        }
    }

    func follow(_ result: DirectoryResult) async {
        searchMessage = await follow(feedURL: result.feedURL) ? nil : Self.followFailed
    }

    func addByLink(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            linkMessage = Self.notAFeed
            return
        }
        linkMessage = await follow(feedURL: url) ? nil : Self.notAFeed
    }

    /// Follows and selects the show; false if the feed couldn't be followed.
    private func follow(feedURL: URL) async -> Bool {
        do {
            selectedShow = try await library.follow(feedURL: feedURL)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Views

struct LibraryView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore

    init(model: LibraryViewModel) {
        self.model = model
        self.library = model.library
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model, library: library)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if let show = model.selectedShow {
                EpisodeList(show: show, library: library, nowPlaying: model.nowPlaying)
            } else {
                Text("Pick a show, or search for one to follow.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

private struct LibrarySidebar: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore
    @State private var link = ""
    @State private var refreshing = false

    var body: some View {
        List(selection: $model.selectedShow) {
            Section {
                TextField("Search podcasts", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.search() } }
                if let message = model.searchMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.results) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).lineLimit(1)
                            if !result.author.isEmpty {
                                Text(result.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Button("Follow") { Task { await model.follow(result) } }
                    }
                }
            }

            Section("Add by link") {
                HStack {
                    TextField("Feed link", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addLink)
                    Button("Add", action: addLink)
                }
                if let message = model.linkMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shows") {
                ForEach(library.shows) { show in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.title).lineLimit(1)
                        if show.lastError != nil {
                            Text(Self.brokenNote(for: show))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(show as Show?)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Refresh") {
                    refreshing = true
                    Task {
                        await library.refreshAll()
                        refreshing = false
                    }
                }
                .disabled(refreshing)
                Spacer()
            }
            .padding(10)
        }
    }

    private func addLink() {
        let text = link
        Task {
            await model.addByLink(text)
            if model.linkMessage == nil { link = "" }
        }
    }

    /// "Couldn't update · last worked 12 Oct 2026".
    static func brokenNote(for show: Show) -> String {
        guard let date = show.lastUpdated else { return "Couldn't update" }
        return "Couldn't update \u{00B7} last worked \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct EpisodeList: View {
    let show: Show
    @ObservedObject var library: LibraryStore
    let nowPlaying: NowPlaying

    var body: some View {
        List(library.episodes(of: show)) { episode in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title).lineLimit(2)
                    Text(Self.details(of: episode))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Play") { nowPlaying.play(episode) }
                Button("+ Up Next") { library.enqueue(episode) }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle(show.title)
    }

    /// Date · duration · time left when part-played.
    static func details(of episode: Episode) -> String {
        var parts: [String] = []
        if let published = episode.published {
            parts.append(published.formatted(date: .abbreviated, time: .omitted))
        }
        if let duration = episode.duration {
            parts.append(TimeFormat.clock(duration))
            if !episode.played, episode.position > 0 {
                parts.append("\(TimeFormat.clock(max(0, duration - episode.position))) left")
            }
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - Window

/// The Library window: a standard window and sidebar, which macOS 26 draws in Liquid Glass.
@MainActor
final class LibraryWindowController {
    private let window: NSWindow

    init(model: LibraryViewModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.title = "Spindle Library"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: LibraryView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
    }

    func show() {
        // The Library pill lives in a non-activating panel, so Spindle is never the active app here and the
        // cooperative `activate()` is refused: the window would open behind other apps with no keyboard.
        NSApp.forceActivate()
        window.makeKeyAndOrderFront(nil)
    }
}
