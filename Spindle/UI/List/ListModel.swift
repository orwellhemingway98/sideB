import Foundation

enum PodcastTab: Hashable {
    case episodes, chapters
}

/// Builds the list window's content from what's playing, reading a Music album or playlist when needed.
/// A read that finishes after the song has moved on is dropped.
@MainActor
final class ListModel: ObservableObject {
    @Published private(set) var content: ListContent = .nothing
    @Published var tab: PodcastTab = .episodes

    private let nowPlaying: NowPlaying
    private let library: LibraryStore
    /// Signed in, Spotify songs list their album or playlist; signed out, they show their details.
    let spotify: SpotifyAccount?
    private let loadContext: (MusicTrack, Bool) async -> MusicContext?
    private let cachedContext: (MusicTrack) -> MusicContext?
    private var generation = 0
    private var lastKey: String?

    /// `loadContext(track, refresh)` defaults to the music remote's cached reader; tests pass their own.
    init(nowPlaying: NowPlaying, library: LibraryStore, spotify: SpotifyAccount? = nil,
         loadContext: ((MusicTrack, Bool) async -> MusicContext?)? = nil) {
        self.nowPlaying = nowPlaying
        self.library = library
        self.spotify = spotify
        self.loadContext = loadContext ?? { [weak nowPlaying] track, refresh in
            await nowPlaying?.music?.context(for: track, refresh: refresh)
        }
        cachedContext = { [weak nowPlaying] track in nowPlaying?.music?.cachedContext(for: track) }
    }

    /// What the list depends on: not the playing position, so ticks don't rebuild it.
    private var key: String {
        let episode = nowPlaying.player.episode
        return [
            nowPlaying.mode == .music ? "music" : "podcast",
            episode?.guid ?? "",
            String(nowPlaying.chapters.count),
            nowPlaying.currentChapter.map { String($0.start) } ?? "",
            nowPlaying.music?.track?.trackID ?? "",
            nowPlaying.music?.contextKey ?? "",
            String(nowPlaying.music?.contextFailed ?? false),
            String(spotify?.isSignedIn ?? false),
        ].joined(separator: "|")
    }

    /// True when something the list shows has changed since the last reload.
    var needsReload: Bool { key != lastKey }

    /// `force` reads a Music list again (opening the window), so playlist edits show. What can be shown at
    /// once is (`showNow`); the read happens after, and replaces it when it arrives.
    func reload(force: Bool = false) async {
        generation += 1
        let mine = generation
        lastKey = key
        guard let track = showNow(force: force) else { return }
        let context = await loadContext(track, force)
        guard mine == generation else { return }
        if let context, !context.tracks.isEmpty {
            content = .music(context, currentTrackID: context.row(for: track)?.id ?? track.trackID)
        } else if case .music = content {
            // The re-read failed or came back empty: the list already up is still right.
            return
        } else {
            let failed = nowPlaying.music?.contextFailed == true
            let couldNotRead = track.source == .spotify ? ListContent.couldNotReadSpotify : ListContent.couldNotRead
            content = .musicMessage(trackID: track.trackID, text: failed ? couldNotRead : ListContent.nothingToList)
        }
    }

    /// Shows what needs no reading: a podcast's episodes, Spotify's details while signed out, or the album or
    /// playlist already read for this song. Returns the song whose list still has to be read from the app.
    @discardableResult
    func showNow(force: Bool = false) -> MusicTrack? {
        switch nowPlaying.mode {
        case .podcast:
            guard let episode = nowPlaying.player.episode else {
                content = .nothing
                return nil
            }
            content = .podcast(episodes: episode.show.map { library.episodes(of: $0) } ?? [episode],
                               current: episode, chapters: nowPlaying.chapters,
                               currentChapter: nowPlaying.currentChapter,
                               description: ListContent.plainText(fromHTML: episode.summary))
            return nil
        case .music:
            guard let track = nowPlaying.music?.track else {
                content = .nothing
                return nil
            }
            if track.source == .spotify, spotify?.isSignedIn != true {
                content = .spotify(track)
                return nil
            }
            // The next song on the list already shown: just move the highlight.
            if !force, case .music(let context, _) = content, context.id == nowPlaying.music?.contextKey,
               let row = context.row(for: track) {
                content = .music(context, currentTrackID: row.id)
                return nil
            }
            if let cached = cachedContext(track), !cached.tracks.isEmpty {
                content = .music(cached, currentTrackID: cached.row(for: track)?.id ?? track.trackID)
            } else {
                content = .musicLoading(trackID: track.trackID)
            }
            return track
        }
    }
}

/// Whether a content change closes the list window: a different show, album or playlist does; loading
/// never does, and the first real identity after opening is adopted.
enum ListCloseRule: Equatable {
    case keep(String?)
    case close

    static func decide(last: String?, identity: String?, isLoading: Bool) -> ListCloseRule {
        if isLoading { return .keep(last) }
        guard let identity else { return .close }
        guard let last else { return .keep(identity) }
        return last == identity ? .keep(last) : .close
    }
}

