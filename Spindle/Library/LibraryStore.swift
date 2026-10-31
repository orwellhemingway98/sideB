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

    /// Unplayed episodes from every show, newest first. The store filters, sorts and limits, so a big
    /// library costs one small query, not a pass over every episode on each redraw.
    func newEpisodes(limit: Int = 100) -> [Episode] {
        var descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { !$0.played },
            sortBy: [SortDescriptor(\.published, order: .reverse), SortDescriptor(\.feedOrder)])
        descriptor.fetchLimit = limit
        // The store sorts undated episodes by its own rule; re-sort the small page to keep them last.
        return ((try? context.fetch(descriptor)) ?? []).sorted(by: Self.newestFirst)
    }

    /// Episodes whose downloaded file is on disk, newest first.
    var downloaded: [Episode] {
        let descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.localFile != nil })
        return ((try? context.fetch(descriptor)) ?? []).filter { episode in
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
        // An http feed is tried as https first: macOS blocks plain http, and most such feeds serve both.
        let candidates = [feedURL.httpsUpgraded, feedURL].compactMap { $0 }
        var outcome: (url: URL, feed: ParsedFeed, validators: Validators)?
        var lastError: Error = LibraryError.invalidFeed
        for candidate in candidates {
            switch await Self.fetchAndParse(candidate, validators: Validators(), with: fetcher) {
            case .success(.fresh(let feed, let validators)):
                outcome = (candidate, feed, validators)
            case .success(.notModified):
                continue
            case .failure(let error):
                lastError = error
            }
            if outcome != nil { break }
        }
        guard let (workingURL, parsed, validators) = outcome else {
            throw Connectivity.isOffline(lastError) ? LibraryError.offline : LibraryError.invalidFeed
        }
        // Another follow of the same feed may have finished while we were fetching.
        if let existing = existingShow(for: feedURL) { return existing }
        objectWillChange.send()
        let show = Show(feedURL: workingURL, title: parsed.title)
        context.insert(show)
        apply(parsed, to: show)
        show.etag = validators.etag
        show.lastModified = validators.lastModified
        show.lastUpdated = now()
        save()
        return show
    }

    /// Follows every feed, two at a time; shows already followed are counted, not fetched again.
    func importFeeds(_ urls: [URL]) async -> ImportSummary {
        var summary = ImportSummary()
        let fresh = urls.filter { url in
            if existingShow(for: url) != nil { summary.alreadyFollowed += 1; return false }
            return true
        }
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            func startNext() {
                guard next < fresh.count else { return }
                let url = fresh[next]
                next += 1
                group.addTask { @MainActor in (try? await self.follow(feedURL: url)) != nil }
            }
            for _ in 0..<2 { startNext() }
            while let followed = await group.next() {
                if followed { summary.followed += 1 } else { summary.failed += 1 }
                startNext()
            }
        }
        return summary
    }

    // MARK: Refresh

    func refresh(_ show: Show) async {
        let result = await Self.fetchAndParse(show.feedURL, validators: Self.validators(of: show), with: fetcher)
        finish(show, with: result)
    }

    func refreshAll() async {
        let targets = shows.map { (show: $0, url: $0.feedURL, validators: Self.validators(of: $0)) }
        let fetcher = self.fetcher
        await withTaskGroup(of: (Int, Result<FeedUpdate, Error>).self) { group in
            var next = 0
            func startNext() {
                guard next < targets.count else { return }
                let index = next, url = targets[next].url, validators = targets[next].validators
                next += 1
                group.addTask { (index, await Self.fetchAndParse(url, validators: validators, with: fetcher)) }
            }
            for _ in 0..<2 { startNext() }
            while let (index, result) = await group.next() {
                finish(targets[index].show, with: result)
                startNext()
            }
        }
    }

    /// A refresh result: the parsed feed with its new validators, or "unchanged since last time".
    private enum FeedUpdate: Sendable {
        case fresh(ParsedFeed, Validators)
        case notModified
    }

    private static func validators(of show: Show) -> Validators {
        Validators(etag: show.etag, lastModified: show.lastModified)
    }

    /// Fetches (conditionally) and parses away from the main actor, so a big feed never stalls the UI.
    private nonisolated static func fetchAndParse(_ url: URL, validators: Validators,
                                                  with fetcher: HTTPFetching) async -> Result<FeedUpdate, Error> {
        do {
            switch try await fetcher.fetch(url, validators: validators) {
            case .notModified: return .success(.notModified)
            case .fresh(let data, let newValidators): return .success(.fresh(try FeedParser.parse(data), newValidators))
            }
        } catch {
            return .failure(error)
        }
    }

    /// Applies a refresh result on the main actor. Being offline isn't the feed's fault: it is
    /// left alone and tried again at the next check.
    private func finish(_ show: Show, with result: Result<FeedUpdate, Error>) {
        if case .failure(let error) = result, Connectivity.isOffline(error) { return }
        objectWillChange.send()
        switch result {
        case .success(.fresh(let parsed, let validators)):
            apply(parsed, to: show)
            show.etag = validators.etag
            show.lastModified = validators.lastModified
            markUpdated(show)
        case .success(.notModified):
            markUpdated(show)
        case .failure(let error):
            show.lastError = error.localizedDescription
            if show.errorSince == nil { show.errorSince = now() }
        }
        save()
    }

    private func markUpdated(_ show: Show) {
        show.lastError = nil
        show.errorSince = nil
        show.lastUpdated = now()
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

    func setUnavailable(_ value: Bool, for episode: Episode) {
        guard episode.unavailable != value else { return }
        objectWillChange.send()
        episode.unavailable = value
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
