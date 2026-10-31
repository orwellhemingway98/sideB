import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var library: LibraryStore?
    private var player: PodcastPlayer?
    private var nowPlaying: NowPlaying?
    private var panel: DialPanelController?
    private var strip: StatusStripController?
    private var libraryWindow: LibraryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests { return }

        let fetcher = URLSessionFetcher()
        let library: LibraryStore
        do {
            library = try LibraryStore.onDisk(fetcher: fetcher)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Spindle couldn't open its library."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let engine = AVPlayerEngine()
        let player = PodcastPlayer(engine: engine, library: library)
        let media = MediaCenter()
        let haptics = Haptics()
        let nowPlaying = NowPlaying(
            player: player, media: media, haptics: haptics,
            schedule: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
            },
            now: { ProcessInfo.processInfo.systemUptime },
            loadChapters: { @MainActor episode in
                // Read the model on the main actor; only plain values travel to the loaders.
                let chaptersURL = episode.chaptersURL
                let inline = episode.inlineChapters
                let audioURL = episode.playableURL
                return await ChapterLoader.load(chaptersURL: chaptersURL, inline: inline,
                                                audioChapters: { await AudioFileChapters.read(from: audioURL) },
                                                fetcher: fetcher)
            })
        let artwork = ArtworkCache()
        let panel = DialPanelController(nowPlaying: nowPlaying, library: library, artwork: artwork,
                                        onLibrary: { [weak self] in self?.showLibrary() })
        let strip = StatusStripController(nowPlaying: nowPlaying, artwork: artwork, panel: panel)

        self.library = library
        self.player = player
        self.nowPlaying = nowPlaying
        self.panel = panel
        self.strip = strip

        if let guid = library.lastEpisodeGUID,
           let episode = library.shows.lazy.flatMap(\.episodes).first(where: { $0.guid == guid }) {
            player.open(episode, autoplay: false)
        }
        Task { await library.refreshAll() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        player?.saveNow()
    }

    /// Opens (creating once) the Library window and brings Spindle forward.
    private func showLibrary() {
        guard let library, let nowPlaying else { return }
        if libraryWindow == nil {
            let model = LibraryViewModel(library: library, fetcher: URLSessionFetcher(), nowPlaying: nowPlaying)
            libraryWindow = LibraryWindowController(model: model)
        }
        panel?.close()
        libraryWindow?.show()
    }
}
