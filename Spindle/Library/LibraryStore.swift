import Foundation
import SwiftData
import SwiftUI  // Array.move(fromOffsets:toOffset:)

enum LibraryError: Error, Equatable {
    case invalidFeed
    case offline
}

@MainActor
final class LibraryStore: ObservableObject {
    private let container: ModelContainer
    private let fetcher: HTTPFetching
    private let defaults: UserDefaults
    private let now: () -> Date
    private let ephemeralSuite: String?
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, fetcher: HTTPFetching, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, ephemeralSuite: String? = nil) {
        self.ephemeralSuite = ephemeralSuite
        self.container = container
        self.fetcher = fetcher
        self.defaults = defaults
        self.now = now
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Show.self, Episode.self, UpNextEntry.self, configurations: configuration)
    }

    /// For tests and previews: nothing touches disk and settings go to a throwaway suite.
    static func inMemory(fetcher: HTTPFetching, now: @escaping () -> Date = Date.init) -> LibraryStore {
        let container = try! makeContainer(ModelConfiguration(isStoredInMemoryOnly: true))
        let suite = "spindle.tests.\(UUID().uuidString)"
        return LibraryStore(container: container, fetcher: fetcher,
                            defaults: UserDefaults(suiteName: suite)!, now: now, ephemeralSuite: suite)
    }

    deinit {
        if let suite = ephemeralSuite { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    /// The app's store: Application Support/Spindle/Library.store.
    static func onDisk(fetcher: HTTPFetching) throws -> LibraryStore {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Spindle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try makeContainer(ModelConfiguration(url: directory.appendingPathComponent("Library.store")))
        return LibraryStore(container: container, fetcher: fetcher)
    }

    // MARK: Shows

    var shows: [Show] {
        let all = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        return all.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func episodes(of show: Show) -> [Episode] {
        show.episodes.sorted(by: Self.newestFirst)
    }

    /// Newest first: dated before undated, then the feed's own order.
    private static func newestFirst(_ a: Episode, _ b: Episode) -> Bool {
        switch (a.published, b.published) {
        case let (x?, y?) where x != y: return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.feedOrder < b.feedOrder
        }
    }

    private var allEpisodes: [Episode] { (try? context.fetch(FetchDescriptor<Episode>())) ?? [] }

    /// Unplayed episodes from every show, newest first.
    func newEpisodes(limit: Int = 100) -> [Episode] {
        Array(allEpisodes.filter { !$0.played }.sorted(by: Self.newestFirst).prefix(limit))
    }

    /// Episodes whose downloaded file is on disk, newest first.
    var downloaded: [Episode] {
        allEpisodes.filter { episode in
            guard let file = episode.localFile else { return false }
            return FileManager.default.fileExists(atPath: file.path)
        }.sorted(by: Self.newestFirst)
    }

    /// Same show if scheme (treated as https), host case, and trailing slash are the only differences.
    private static func identity(of url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.scheme = "https"
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        while parts.path.count > 1, parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path == "/" { parts.path = "" }
        return parts.string ?? url.absoluteString
    }

    private func existingShow(for url: URL) -> Show? {
        let key = Self.identity(of: url)
        return shows.first { Self.identity(of: $0.feedURL) == key }
    }

    func follow(feedURL: URL) async throws -> Show {
        if let existing = existingShow(for: feedURL) { return existing }
        let parsed: ParsedFeed
        switch await Self.fetchAndParse(feedURL, with: fetcher) {
        case .success(let feed): parsed = feed
        case .failure(let error):
            throw Connectivity.isOffline(error) ? LibraryError.offline : LibraryError.invalidFeed
        }
        // Another follow of the same feed may have finished while we were fetching.
        if let existing = existingShow(for: feedURL) { return existing }
        objectWillChange.send()
        let show = Show(feedURL: feedURL, title: parsed.title)
        context.insert(show)
        apply(parsed, to: show)
        show.lastUpdated = now()
        save()
        return show
    }

    // MARK: Refresh

    func refresh(_ show: Show) async {
        let result = await Self.fetchAndParse(show.feedURL, with: fetcher)
        finish(show, with: result)
    }

    func refreshAll() async {
        let targets = shows.map { (show: $0, url: $0.feedURL) }
        let fetcher = self.fetcher
        await withTaskGroup(of: (Int, Result<ParsedFeed, Error>).self) { group in
            var next = 0
            func startNext() {
                guard next < targets.count else { return }
                let index = next, url = targets[next].url
                next += 1
                group.addTask { (index, await Self.fetchAndParse(url, with: fetcher)) }
            }
            for _ in 0..<2 { startNext() }
            while let (index, result) = await group.next() {
                finish(targets[index].show, with: result)
                startNext()
            }
        }
    }

    /// Fetches and parses away from the main actor, so a big feed never stalls the UI.
    private nonisolated static func fetchAndParse(_ url: URL, with fetcher: HTTPFetching) async -> Result<ParsedFeed, Error> {
        do { return .success(try FeedParser.parse(try await fetcher.data(from: url))) } catch { return .failure(error) }
    }

    /// Applies a refresh result on the main actor.
    private func finish(_ show: Show, with result: Result<ParsedFeed, Error>) {
        objectWillChange.send()
        do {
            let parsed = try result.get()
            apply(parsed, to: show)
            show.lastError = nil
            show.errorSince = nil
            show.lastUpdated = now()
        } catch {
            show.lastError = error.localizedDescription
            if show.errorSince == nil { show.errorSince = now() }
        }
        save()
    }

    /// Updates show metadata and upserts episodes by guid. Episodes missing from the feed are kept.
    private func apply(_ feed: ParsedFeed, to show: Show) {
        show.title = feed.title
        show.author = feed.author
        show.artworkURL = feed.artworkURL
        show.summary = feed.summary
        var byGUID: [String: Episode] = [:]
        for episode in show.episodes { byGUID[episode.guid] = episode }
        for (index, parsed) in feed.episodes.enumerated() {
            let episode: Episode
            if let existing = byGUID[parsed.guid] {
                episode = existing
            } else {
                episode = Episode(guid: parsed.guid, title: parsed.title, enclosureURL: parsed.enclosureURL)
                episode.show = show
                context.insert(episode)
                byGUID[parsed.guid] = episode
            }
            episode.title = parsed.title
            episode.published = parsed.published
            episode.feedOrder = index
            episode.duration = parsed.duration
            episode.enclosureURL = parsed.enclosureURL
            episode.enclosureType = parsed.enclosureType
            episode.chaptersURL = parsed.chaptersURL
            episode.inlineChaptersData = parsed.inlineChapters.isEmpty ? nil : try? JSONEncoder().encode(parsed.inlineChapters)
            episode.summary = parsed.summary
        }
    }

    // MARK: Up Next

    private var entries: [UpNextEntry] {
        let all = (try? context.fetch(FetchDescriptor<UpNextEntry>())) ?? []
        return all.sorted { $0.order < $1.order }
    }

    var upNext: [Episode] { entries.compactMap(\.episode) }

    func enqueue(_ episode: Episode) {
        let current = entries
        guard !current.contains(where: { $0.episode?.persistentModelID == episode.persistentModelID }) else { return }
        objectWillChange.send()
        context.insert(UpNextEntry(episode: episode, order: (current.last?.order ?? 0) + 1))
        save()
    }

    func remove(fromUpNext episode: Episode) {
        let matching = entries.filter { $0.episode?.persistentModelID == episode.persistentModelID }
        guard !matching.isEmpty else { return }
        objectWillChange.send()
        matching.forEach(context.delete)
        save()
    }

    /// Reorders Up Next the way a SwiftUI List's `onMove` describes it.
    func moveUpNext(from source: IndexSet, to destination: Int) {
        var current = entries
        current.move(fromOffsets: source, toOffset: destination)
        objectWillChange.send()
        for (index, entry) in current.enumerated() { entry.order = index + 1 }
        save()
    }

    func popNext() -> Episode? {
        guard let first = entries.first else { return nil }
        objectWillChange.send()
        let episode = first.episode
        context.delete(first)
        save()
        return episode
    }

    // MARK: Playback state

    func savePosition(_ position: TimeInterval, of episode: Episode) {
        objectWillChange.send()
        episode.position = position
        save()
    }

    func markPlayed(_ episode: Episode) {
        objectWillChange.send()
        episode.played = true
        episode.playedAt = now()
        episode.position = 0
        save()
    }

    /// Records where an episode's download lives (nil once it is removed).
    func setLocalFile(_ file: URL?, for episode: Episode) {
        objectWillChange.send()
        episode.localFile = file
        save()
    }

    /// Seeking back out of the last 30 s: the episode isn't finished after all.
    func markUnplayed(_ episode: Episode) {
        objectWillChange.send()
        episode.played = false
        episode.playedAt = nil
        save()
    }

    private static let lastFeedKey = "lastEpisodeFeedURL"
    private static let lastGUIDKey = "lastEpisodeGUID"

    /// Remembers the episode by its show's feed and its guid: guids are only unique within a feed.
    func rememberLastEpisode(_ episode: Episode) {
        defaults.set(episode.show?.feedURL.absoluteString, forKey: Self.lastFeedKey)
        defaults.set(episode.guid, forKey: Self.lastGUIDKey)
    }

    /// The episode last opened, if it is still in the library.
    var lastEpisode: Episode? {
        guard let feed = defaults.string(forKey: Self.lastFeedKey).flatMap(URL.init(string:)),
              let guid = defaults.string(forKey: Self.lastGUIDKey) else { return nil }
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.guid == guid })
        let candidates = (try? context.fetch(descriptor)) ?? []
        return candidates.first { $0.show?.feedURL == feed }
    }

    private func save() {
        try? context.save()
    }
}
