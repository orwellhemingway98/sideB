import AppKit
import Combine
import SwiftUI

/// What the menu bar shows: the artwork and a progress hairline in a small glass capsule,
/// or a small empty glass disc when nothing is open.
struct StatusStripView: View {
    static let height: CGFloat = 20
    static let stripWidth: CGFloat = 13 + 5 + 44 + 2 * 6
    static let emptyWidth: CGFloat = 20
    private static let barWidth: CGFloat = 44

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer
    @ObservedObject var artwork: ArtworkCache

    init(nowPlaying: NowPlaying, artwork: ArtworkCache) {
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
        self.artwork = artwork
    }

    private var progress: Double {
        guard let duration = nowPlaying.displayDuration, duration > 0 else { return 0 }
        return min(1, max(0, nowPlaying.displayPosition / duration))
    }

    var body: some View {
        Group {
            if let display = nowPlaying.display {
                HStack(spacing: 5) {
                    ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                                size: 13, cornerRadius: 3.5, image: nowPlaying.musicArtwork)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.25))
                        Capsule().fill(Color(nsColor: .labelColor))
                            .frame(width: max(3, Self.barWidth * progress))
                    }
                    .frame(width: Self.barWidth, height: 3)
                }
                .padding(.horizontal, 6)
                .frame(width: Self.stripWidth, height: Self.height - 2)
                .glassEffect(.regular, in: Capsule())
            } else {
                Circle()
                    .strokeBorder(.primary.opacity(0.45), lineWidth: 1.5)
                    .padding(3.5)
                    .frame(width: Self.height - 4, height: Self.height - 4)
                    .glassEffect(.regular, in: Circle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The menu bar item. A click toggles the dial panel; a right-click shows the `StatusMenu`;
/// scrolling over it scrubs without opening anything.
@MainActor
final class StatusStripController: NSObject {
    private let statusItem: NSStatusItem
    private let nowPlaying: NowPlaying
    private let panel: DialPanelController
    private let onLibrary: () -> Void
    private let floatingDial: FloatingDialController?
    private let loginItem: LoginItem
    private let spotify: SpotifyAccount?
    private var cancellables: Set<AnyCancellable> = []

    init(nowPlaying: NowPlaying, artwork: ArtworkCache, panel: DialPanelController, onLibrary: @escaping () -> Void,
         floatingDial: FloatingDialController? = nil, loginItem: LoginItem = MainAppLoginItem(),
         spotify: SpotifyAccount? = nil) {
        self.spotify = spotify
        self.floatingDial = floatingDial
        self.loginItem = loginItem
        self.nowPlaying = nowPlaying
        self.panel = panel
        self.onLibrary = onLibrary
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.setAccessibilityLabel("Spindle")

        let hosting = PassThroughHostingView(rootView: StatusStripView(nowPlaying: nowPlaying, artwork: artwork))
        hosting.sizingOptions = []
        hosting.frame = button.bounds
        hosting.autoresizingMask = [.width, .height]
        button.addSubview(hosting)

        let scrollCatcher = StripScrollView(frame: button.bounds)
        scrollCatcher.autoresizingMask = [.width, .height]
        scrollCatcher.onScroll = { [weak nowPlaying] event in
            nowPlaying?.turn(degrees: ScrollTurning.degrees(for: event))
        }
        scrollCatcher.onRightClick = { [weak self] in self?.showMenu() }
        button.addSubview(scrollCatcher)

        // The hosted view has no intrinsic width, so a blank image of the right size sizes the item.
        // objectWillChange fires before the change lands, so read the result on the next turn.
        nowPlaying.objectWillChange
            .receive(on: DispatchQueue.main)
            .map { [weak nowPlaying] in nowPlaying?.display != nil }
            .prepend(nowPlaying.display != nil)
            .removeDuplicates()
            .sink { [weak button] open in
                let width = open ? StatusStripView.stripWidth : StatusStripView.emptyWidth
                button?.image = NSImage(size: NSSize(width: width, height: StatusStripView.height))
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    /// The menu is attached only for this click, so a left click keeps toggling the panel.
    private func showMenu() {
        guard let button = statusItem.button else { return }
        panel.close()
        let menu = StatusMenu.menu(floatingDial: floatingDial?.isShown, launchAtLogin: loginItem.isEnabled,
                                   spotifySignedIn: spotify?.isSignedIn) { [weak self] in
            self?.perform($0)
        }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func perform(_ command: StatusMenu.Command) {
        switch command {
        case .library: openLibrary()
        case .floatingDial: toggleFloatingDial()
        case .launchAtLogin:
            StatusMenu.toggle(loginItem) { error in
                let alert = NSAlert()
                alert.messageText = "Spindle couldn't change Launch at Login."
                alert.informativeText = error.localizedDescription
                NSApp.forceActivate()
                alert.runModal()
            }
        case .signOutOfSpotify: spotify?.signOut()
        case .signInToSpotify:
            guard let spotify, let id = spotify.clientID ?? SpotifyClientIDPrompt.ask(current: nil) else { return }
            Task { await spotify.signIn(clientID: id) }
        case .quit: NSApp.terminate(nil)
        }
    }

    private func openLibrary() { onLibrary() }

    private func toggleFloatingDial() {
        guard let floatingDial else { return }
        if floatingDial.isShown { floatingDial.putBack() } else { floatingDial.show() }
    }
}

/// Draws, but never takes the mouse: clicks fall through to the status button.
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Sits over the status button to catch scrolls; every click goes on to the button.
private final class StripScrollView: NSView {
    var onScroll: ((NSEvent) -> Void)?
    var onRightClick: (() -> Void)?

    override func scrollWheel(with event: NSEvent) { onScroll?(event) }
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}
