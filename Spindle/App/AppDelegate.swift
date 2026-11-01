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
    private var fetcher: HTTPFetching?
    private var artwork: ArtworkCache?
    private var downloads: DownloadManager?
    private var scheduler: RefreshScheduler?
    private var music: MusicRemote?
    private var floatingDial: FloatingDialController?
    private var listWindow: ListWindowController?

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
            NSApp.forceActivate()  // A menu bar app is not active at launch; the alert would open behind.
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let engine = AVPlayerEngine()
        let player = PodcastPlayer(engine: engine, library: library)
        let media = MediaCenter()
        let haptics = Haptics()
        let music = MusicRemote(sources: [AppleMusicSource(), SpotifySource()])
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
        let placement = DialPlacement()
        let floatingDial = FloatingDialController(nowPlaying: nowPlaying, placement: placement,
                                                  onPutBack: {}, onLibrary: { [weak self] in self?.showLibrary() })
        let listModel = ListModel(nowPlaying: nowPlaying, library: library)
        let listWindow = ListWindowController(model: listModel, nowPlaying: nowPlaying)
        let panel = DialPanelController(nowPlaying: nowPlaying, library: library, artwork: artwork,
                                        onLibrary: { [weak self] in self?.showLibrary() },
                                        onPopOut: { [weak self] in self?.popOutDial() },
                                        onCover: { [weak self] in self?.toggleList() },
                                        list: listModel)
        panel.escapeHandler = { [weak listWindow] in listWindow?.handleEscape() ?? false }
        self.listWindow = listWindow
        let strip = StatusStripController(nowPlaying: nowPlaying, artwork: artwork, panel: panel,
                                          onLibrary: { [weak self] in self?.showLibrary() },
                                          floatingDial: floatingDial)

        // Downloads live beside the library store, in Application Support/Spindle/Episodes.
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spindle", isDirectory: true)
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
        self.floatingDial = floatingDial
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
        if placement.isPoppedOut { floatingDial.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying?.flushScrub()
        player?.saveNow()
    }

    /// The cover opens (or closes) the list window under the panel.
    private func toggleList() {
        guard let panel, let listWindow else { return }
        listWindow.toggle(below: panel.window)
    }

    private func popOutDial() {
        panel?.close()
        floatingDial?.show()
    }

    /// Opens (creating once) the Library window and brings Spindle forward.
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
    /// Brings Spindle to the front even when the user acted in a non-activating panel or the menu bar,
    /// where the cooperative `activate()` is refused. The one call site of the deprecated API, on purpose.
    func forceActivate() {
        activate(ignoringOtherApps: true)
    }
}
