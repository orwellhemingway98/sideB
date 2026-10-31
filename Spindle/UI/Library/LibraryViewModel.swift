import Foundation
import SwiftData

/// What the Library window shows on its right-hand side.
enum LibrarySection: Hashable {
    case upNext, newEpisodes, shows, downloaded
    case show(PersistentIdentifier)
}

/// What the Library window does: search the directory, follow by result, pasted link or OPML file,
/// and pick what to show.
@MainActor
final class LibraryViewModel: ObservableObject {
    static let searchFailed = "Search isn't available right now."
    static let notAFeed = "That link isn't a podcast feed."
    static let followFailed = "Couldn't follow that show."
    static let offline = "You're offline. Try again when you're connected."
    static let notOPML = "That file isn't an OPML list of podcasts."

    let library: LibraryStore
    let nowPlaying: NowPlaying
    let downloads: DownloadManager?
    let scheduler: RefreshScheduler?
    let artwork: ArtworkCache
    private let fetcher: HTTPFetching

    @Published var query = ""
    @Published private(set) var results: [DirectoryResult] = []
    /// Shown under the search field: search and follow-from-results failures.
    @Published private(set) var searchMessage: String?
    /// Shown under the Add by link field.
    @Published private(set) var linkMessage: String?
    /// Shown under Import OPML….
    @Published private(set) var importMessage: String?
    @Published var section: LibrarySection = .newEpisodes

    init(library: LibraryStore, fetcher: HTTPFetching, nowPlaying: NowPlaying,
         downloads: DownloadManager? = nil, scheduler: RefreshScheduler? = nil, artwork: ArtworkCache? = nil) {
        self.library = library
        self.fetcher = fetcher
        self.nowPlaying = nowPlaying
        self.downloads = downloads
        self.scheduler = scheduler
        self.artwork = artwork ?? ArtworkCache()
    }

    /// The show picked in the sidebar, if the section is one show.
    var selectedShow: Show? {
        get {
            guard case .show(let id) = section else { return nil }
            return library.shows.first { $0.persistentModelID == id }
        }
        set { section = newValue.map { .show($0.persistentModelID) } ?? .newEpisodes }
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
        searchMessage = await follow(feedURL: result.feedURL, otherwise: Self.followFailed)
    }

    func addByLink(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else {
            linkMessage = Self.notAFeed
            return
        }
        linkMessage = await follow(feedURL: url, otherwise: Self.notAFeed)
    }

    func importOPML(_ data: Data) async {
        do {
            let urls = try OPMLImporter.feedURLs(from: data)
            importMessage = Self.importSummaryText(await library.importFeeds(urls))
        } catch {
            importMessage = Self.notOPML
        }
    }

    /// "Followed 3 shows · 1 already followed · 1 couldn't be added", leaving out the zeros.
    static func importSummaryText(_ summary: ImportSummary) -> String {
        var parts: [String] = []
        if summary.followed > 0 {
            parts.append("Followed \(summary.followed) show\(summary.followed == 1 ? "" : "s")")
        }
        if summary.alreadyFollowed > 0 { parts.append("\(summary.alreadyFollowed) already followed") }
        if summary.failed > 0 { parts.append("\(summary.failed) couldn't be added") }
        return parts.isEmpty ? "No shows found in that file." : parts.joined(separator: " \u{00B7} ")
    }

    /// Follows and selects the show. Returns the message for the field that asked: nil on success,
    /// the offline note when there's no network, `otherwise` for any other failure.
    private func follow(feedURL: URL, otherwise failure: String) async -> String? {
        do {
            let show = try await library.follow(feedURL: feedURL)
            section = .show(show.persistentModelID)
            return nil
        } catch LibraryError.offline {
            return Self.offline
        } catch {
            return failure
        }
    }
}
