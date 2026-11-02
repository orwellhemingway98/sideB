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
    private let loadContext: (MusicTrack, Bool) async -> MusicContext?
    private var generation = 0
    private var lastKey: String?

    /// `loadContext(track, refresh)` defaults to the music remote's cached reader; tests pass their own.
    init(nowPlaying: NowPlaying, library: LibraryStore, loadContext: ((MusicTrack, Bool) async -> MusicContext?)? = nil) {
        self.nowPlaying = nowPlaying
        self.library = library
        self.loadContext = loadContext ?? { [weak nowPlaying] track, refresh in
            await nowPlaying?.music?.context(for: track, refresh: refresh)
        }
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
        ].joined(separator: "|")
    }

    /// True when something the list shows has changed since the last reload.
    var needsReload: Bool { key != lastKey }

    /// `force` reads a Music list again (opening the window), so playlist edits show.
    func reload(force: Bool = false) async {
        generation += 1
        let mine = generation
        lastKey = key
        switch nowPlaying.mode {
        case .podcast:
            guard let episode = nowPlaying.player.episode else {
                content = .nothing
                return
            }
            content = .podcast(episodes: episode.show.map { library.episodes(of: $0) } ?? [episode],
                               current: episode, chapters: nowPlaying.chapters,
                               currentChapter: nowPlaying.currentChapter,
                               description: ListContent.plainText(fromHTML: episode.summary))
        case .music:
            guard let track = nowPlaying.music?.track else {
                content = .nothing
                return
            }
            if track.source == .spotify {
                content = .spotify(track)
                return
            }
            // The next song on the list already shown: just move the highlight.
            if !force, case .music(let context, _) = content, context.id == nowPlaying.music?.contextKey,
               let row = context.row(for: track) {
                content = .music(context, currentTrackID: row.id)
                return
            }
            content = .musicLoading(trackID: track.trackID)
            let context = await loadContext(track, force)
            guard mine == generation else { return }
            if let context, !context.tracks.isEmpty {
                content = .music(context, currentTrackID: context.row(for: track)?.id ?? track.trackID)
            } else {
                let failed = nowPlaying.music?.contextFailed == true
                content = .musicMessage(trackID: track.trackID,
                                        text: failed ? ListContent.couldNotRead : ListContent.nothingToList)
            }
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

