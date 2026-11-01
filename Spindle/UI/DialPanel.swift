import AppKit
import SwiftUI

/// The glass panel that drops from the menu bar strip.
struct DialPanelView: View {
    static let width: CGFloat = 272

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer
    @ObservedObject var library: LibraryStore
    @ObservedObject var artwork: ArtworkCache
    let onLibrary: () -> Void
    /// Pops the disc out into the floating dial; nil hides the pill.
    let onPopOut: (() -> Void)?
    /// Clicking the cover opens or closes the list window.
    let onCover: (() -> Void)?
    /// Tells the cover's hint whether a Music song plays from an album or a playlist.
    let list: ListModel?

    init(nowPlaying: NowPlaying, library: LibraryStore, artwork: ArtworkCache, onLibrary: @escaping () -> Void,
         onPopOut: (() -> Void)? = nil, onCover: (() -> Void)? = nil, list: ListModel? = nil) {
        self.onPopOut = onPopOut
        self.onCover = onCover
        self.list = list
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
        self.library = library
        self.artwork = artwork
        self.onLibrary = onLibrary
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 14) {
                if let display = nowPlaying.display {
                    header(display)
                    DiscView(nowPlaying: nowPlaying)
                    times(display)
                    if display.kind == .music {
                        musicPills
                        if let paused = nowPlaying.pausedEpisode { resumePill(paused) }
                    } else {
                        pills
                    }
                    upNext
                } else {
                    DiscView(nowPlaying: nowPlaying)
                        .padding(.top, 6)
                    Text("Find a show in Library")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                footer
            }
            .padding(16)
            .frame(width: Self.width)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    // MARK: Header

    private func header(_ display: NowPlayingDisplay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverButton(artwork: artwork, display: display, image: nowPlaying.musicArtwork,
                        hint: coverHint, action: onCover)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                let subtitle = [display.subtitle, display.sourceLabel ?? ""].filter { !$0.isEmpty }
                    .joined(separator: " \u{00B7} ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
    }

    private var coverHint: String {
        ListContent.hint(mode: nowPlaying.mode, source: nowPlaying.music?.source,
                         contextKind: nowPlaying.music?.contextKind)
    }

    // MARK: Times

    @ViewBuilder private func times(_ display: NowPlayingDisplay) -> some View {
        if display.kind == .podcast, let failure = player.failure {
            Text(failure)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                Text(TimeFormat.clock(nowPlaying.displayPosition))
                Spacer()
                if let duration = display.duration {
                    Text(TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition)))
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Pills

    private var pills: some View {
        HStack(spacing: 6) {
            pill("\u{2212}15") { nowPlaying.skip(by: -15) }
                .accessibilityLabel("Back 15 seconds")
            if !nowPlaying.chapters.isEmpty {
                chapterMenu
            } else {
                Spacer(minLength: 0)
            }
            pill(Self.rateLabel(player.rate)) { nowPlaying.cycleRate() }
                .accessibilityLabel("Speed \(Self.rateLabel(player.rate))")
            pill("+30") { nowPlaying.skip(by: 30) }
                .accessibilityLabel("Forward 30 seconds")
        }
    }

    /// While music has the dial, the waiting podcast is one click away.
    private func resumePill(_ episode: Episode) -> some View {
        Button { nowPlaying.resumePodcast() } label: {
            HStack(spacing: 6) {
                PlayPauseGlyph(isPlaying: false).fill(.primary).frame(width: 7, height: 8)
                Text("Resume \(episode.title)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resume podcast: \(episode.title)")
    }

    /// Music: just previous and next; the dial does the scrubbing.
    private var musicPills: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            glyphPill(TrackSkipGlyph(forward: false)) { nowPlaying.previous() }
                .accessibilityLabel("Previous track")
            glyphPill(TrackSkipGlyph(forward: true)) { nowPlaying.next() }
                .accessibilityLabel("Next track")
            Spacer(minLength: 0)
        }
    }

    private func glyphPill(_ glyph: TrackSkipGlyph, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyph.fill(.primary)
                .frame(width: 14, height: 10)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chapterMenu: some View {
        Menu {
            ForEach(Array(nowPlaying.chapters.enumerated()), id: \.offset) { _, chapter in
                Button("\(TimeFormat.clock(chapter.start))  \(chapter.title)") { nowPlaying.jump(to: chapter.start) }
            }
        } label: {
            Text(nowPlaying.currentChapter?.title ?? nowPlaying.chapters[0].title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Chapters")
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// "1×", "1.2×", "1.5×", "2×".
    static func rateLabel(_ rate: Float) -> String {
        String(format: "%g\u{00D7}", Double(rate))
    }

    // MARK: Up Next

    @ViewBuilder private var upNext: some View {
        let queue = Array(library.upNext.prefix(3))
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("UP NEXT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                ForEach(Array(queue.enumerated()), id: \.offset) { _, episode in
                    Button { nowPlaying.play(episode) } label: { row(episode) }
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ episode: Episode) -> some View {
        HStack(spacing: 8) {
            ArtworkView(cache: artwork, url: episode.show?.artworkURL, seed: episode.show?.title ?? episode.title,
                        size: 24, cornerRadius: 6)
            Text(episode.title)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let duration = episode.duration {
                Text(TimeFormat.clock(duration))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            pill("Library", action: onLibrary)
            Spacer(minLength: 0)
            if let onPopOut { pill("Pop out \u{2197}", action: onPopOut) }
        }
    }
}

/// A borderless panel that can take key status (for Escape) without activating the app, and keeps
/// its top edge in place when its content grows or shrinks.
private final class DialPanelWindow: NSPanel {
    var anchoredTop: CGFloat?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let top = anchoredTop { frame.origin.y = top - frame.height }
        super.setFrame(frame, display: flag)
    }
}

/// Owns the dial panel: shows it under the status button, closes it on an outside click or Escape.
@MainActor
final class DialPanelController {
    /// Posted when the panel closes, so the disc drops its scroll monitor even with the pointer still over it.
    static let didClose = Notification.Name("DialPanelController.didClose")
    /// Posted when the panel shows, so the disc can take scrolls from a pointer already over it.
    static let didShow = Notification.Name("DialPanelController.didShow")

    private let panel: DialPanelWindow
    private var outsideClickMonitor: Any?
    private var ownWindowClickMonitor: Any?
    /// The status bar window the panel hangs from: its clicks toggle through the button instead.
    private weak var anchorWindow: NSWindow?
    private var escapeMonitor: Any?

    var isShown: Bool { panel.isVisible }

    init(nowPlaying: NowPlaying, library: LibraryStore, artwork: ArtworkCache, onLibrary: @escaping () -> Void,
         onPopOut: (() -> Void)? = nil, onCover: (() -> Void)? = nil, list: ListModel? = nil) {
        panel = DialPanelWindow(contentRect: NSRect(x: 0, y: 0, width: DialPanelView.width, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = DialPanelView(nowPlaying: nowPlaying, library: library, artwork: artwork, onLibrary: onLibrary,
                                 onPopOut: onPopOut, onCover: onCover, list: list)
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
    }

    func toggle(below button: NSStatusBarButton) {
        if isShown { close() } else { show(below: button) }
    }

    /// Centres the panel under the button, kept inside the screen's visible frame.
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let visible = screen?.visibleFrame ?? .zero

        var x = buttonFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = min(buttonFrame.minY - 6, visible.maxY)

        anchorWindow = buttonWindow
        panel.anchoredTop = top
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        NotificationCenter.default.post(name: Self.didShow, object: self)
    }

    /// The panel's window, for windows that attach below it (the list).
    var window: NSWindow { panel }

    /// Asked first when Escape is pressed in the panel; returns true if it handled it.
    var escapeHandler: (() -> Bool)?

    func close() {
        removeMonitors()
        // Tell the list first: AppKit hides child windows with the panel, and the list must detach while
        // it can still see itself, or it would come back with the panel next time.
        NotificationCenter.default.post(name: Self.didClose, object: self)
        panel.orderOut(nil)
    }

    isolated deinit {
        removeMonitors()
    }

    private func installMonitors() {
        removeMonitors()
        // Global monitors only see clicks in other apps; clicks on the strip toggle through its button.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        // A local monitor catches clicks in Spindle's other windows, such as the Library.
        ownWindowClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let window = event.window
            MainActor.assumeIsolated {
                guard let self, PanelClickPolicy.closesPanel(clickWindow: window, panel: self.panel,
                                                             anchor: self.anchorWindow,
                                                             children: self.panel.childWindows ?? []) else { return }
                self.close()
            }
            return event
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let window = event.window
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, window === self.panel else { return false }
                // An open list window closes first; the panel stays.
                if self.escapeHandler?() == true { return true }
                self.close()
                return true
            }
            return closed ? nil : event
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let ownWindowClickMonitor { NSEvent.removeMonitor(ownWindowClickMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        outsideClickMonitor = nil
        ownWindowClickMonitor = nil
        escapeMonitor = nil
    }
}

/// The big cover: gives a little under the pointer and when pressed; clicking it opens the list window.
private struct CoverButton: View {
    static let size: CGFloat = 240

    @ObservedObject var artwork: ArtworkCache
    let display: NowPlayingDisplay
    let image: NSImage?
    let hint: String
    let action: (() -> Void)?
    @State private var hovering = false
    /// Resets itself if the press is interrupted (the panel closes mid-press).
    @GestureState private var pressed = false

    var body: some View {
        ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                    size: Self.size, cornerRadius: 18, image: image)
            .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
            .overlay(alignment: .bottomTrailing) {
                if action != nil {
                    Text(hint)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                        .padding(10)
                }
            }
            .scaleEffect(pressed ? 0.97 : (hovering ? 1.015 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
            .onHover { hovering = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onEnded { value in
                    let inside = CGRect(x: 0, y: 0, width: Self.size, height: Self.size).contains(value.location)
                    if inside { action?() }
                })
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cover. \(hint)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action?() }
    }
}

