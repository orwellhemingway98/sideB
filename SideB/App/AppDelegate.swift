import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var library: LibraryStore?
    private var player: PodcastPlayer?
    private var nowPlaying: NowPlaying?
    private var panel: PanelController?
    private var strip: StatusStripController?
    private var libraryWindow: LibraryWindowController?
    private var fetcher: HTTPFetching?
    private var artwork: ArtworkCache?
    private var downloads: DownloadManager?
    private var scheduler: RefreshScheduler?
    private var music: MusicRemote?
    private var miniPlayer: MiniPlayerController?
    private var list: ListController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests { return }

        let fetcher = URLSessionFetcher()
        let library: LibraryStore
        do {
            library = try LibraryStore.onDisk(fetcher: fetcher)
        } catch {
            let alert = NSAlert()
            alert.messageText = "sideB couldn't open its library."
            alert.informativeText = error.localizedDescription
            NSApp.forceActivate()  // A menu bar app is not active at launch; the alert would open behind.
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let engine = AVPlayerEngine()
        let player = PodcastPlayer(engine: engine, library: library)
        let media = MediaCenter()
        let haptics = Haptics()
        let spotify = SpotifyAccount()
        let music = MusicRemote(sources: [AppleMusicSource(), SpotifySource(api: spotify.api)])
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
            },
            music: music)
        let artwork = ArtworkCache()
        let placement = MiniPlacement()
        let miniPlayer = MiniPlayerController(nowPlaying: nowPlaying, placement: placement,
                                                  onPutBack: {}, onLibrary: { [weak self] in self?.showLibrary() },
                                                  artwork: artwork,
                                                  list: ListModel(nowPlaying: nowPlaying, library: library, spotify: spotify))
        let listModel = ListModel(nowPlaying: nowPlaying, library: library, spotify: spotify)
        let list = ListController(model: listModel, nowPlaying: nowPlaying)
        let panel = PanelController(nowPlaying: nowPlaying, library: library, artwork: artwork,
                                        onLibrary: { [weak self] in self?.showLibrary() },
                                        onPopOut: { [weak self] in self?.popOut() },
                                        placement: placement,
                                        onCover: { [weak self] in self?.toggleList() },
                                        list: listModel,
                                        lesson: ScrollLesson(turned: nowPlaying.turned))
        panel.escapeHandler = { [weak list] in list?.handleEscape() ?? false }
        self.list = list
        let strip = StatusStripController(nowPlaying: nowPlaying, artwork: artwork, panel: panel,
                                          onLibrary: { [weak self] in self?.showLibrary() },
                                          miniPlayer: miniPlayer, spotify: spotify)

        // Downloads live beside the library store, in Application Support/sideB/Episodes.
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sideB", isDirectory: true)
        let downloads = DownloadManager(library: library, session: URLSessionDownloads(), root: root)
        let cleanUp = { @MainActor [weak player] in
            DownloadCleaner.purge(library.downloaded, now: .now, excluding: player?.episode,
                                  remove: downloads.removeDownload)
        }
        let scheduler = RefreshScheduler(refresh: {
            await library.refreshAll()
            cleanUp()
        })

        self.music = music
        self.miniPlayer = miniPlayer
        self.fetcher = fetcher
        self.artwork = artwork
        self.downloads = downloads
        self.scheduler = scheduler
        self.library = library
        self.player = player
        self.nowPlaying = nowPlaying
        self.panel = panel
        self.strip = strip

        if let episode = library.lastEpisode {
            player.open(episode, autoplay: false)
        }
        cleanUp()
        scheduler.start()
        // The first poll of a running music app makes macOS ask for Automation permission, once.
        music.start()
        if placement.isPoppedOut { miniPlayer.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying?.flushScrub()
        player?.saveNow()
    }

    /// The cover opens (or closes) the list window under the panel.
    private func toggleList() {
        list?.toggle()
    }

    /// The panel's corner button: pops the mini player out, or puts it back when it is already out.
    private func popOut() {
        guard let miniPlayer else { return }
        if miniPlayer.isShown {
            miniPlayer.putBack()
        } else {
            panel?.close()
            miniPlayer.show()
        }
    }

    /// Opens (creating once) the Library window and brings sideB forward.
    private func showLibrary() {
        guard let library, let nowPlaying, let fetcher else { return }
        if libraryWindow == nil {
            let model = LibraryViewModel(library: library, fetcher: fetcher, nowPlaying: nowPlaying,
                                         downloads: downloads, scheduler: scheduler, artwork: artwork)
            libraryWindow = LibraryWindowController(model: model)
        }
        panel?.close()
        libraryWindow?.show()
    }
}

extension NSApplication {
    /// Brings sideB to the front even when the user acted in a non-activating panel or the menu bar,
    /// where the cooperative `activate()` is refused. The one call site of the deprecated API, on purpose.
    func forceActivate() {
        activate(ignoringOtherApps: true)
    }
}
