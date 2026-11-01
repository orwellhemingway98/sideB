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
    private let loadContext: (MusicTrack) async -> MusicContext?
    private var generation = 0

    /// `loadContext` defaults to the music remote's cached reader; tests pass their own.
    init(nowPlaying: NowPlaying, library: LibraryStore, loadContext: ((MusicTrack) async -> MusicContext?)? = nil) {
        self.nowPlaying = nowPlaying
        self.library = library
        self.loadContext = loadContext ?? { [weak nowPlaying] track in await nowPlaying?.music?.context(for: track) }
    }

    func reload() async {
        generation += 1
        let mine = generation
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
            // The next song on an album already shown: just move the highlight.
            if case .music(let context, _) = content, context.tracks.contains(where: { $0.id == track.trackID }) {
                content = .music(context, currentTrackID: track.trackID)
                return
            }
            content = .musicLoading(trackID: track.trackID)
            let context = await loadContext(track)
            guard mine == generation else { return }
            if let context, !context.tracks.isEmpty {
                content = .music(context, currentTrackID: track.trackID)
            } else {
                let failed = nowPlaying.music?.contextFailed == true
                content = .musicMessage(trackID: track.trackID,
                                        text: failed ? ListContent.couldNotRead : ListContent.nothingToList)
            }
        }
    }
}
