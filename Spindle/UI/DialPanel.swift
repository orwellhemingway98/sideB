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
    @State private var hovering = false
    /// What the header showed last time the cover was settled; kept while a new song's cover loads.
    @State private var settledDisplay: NowPlayingDisplay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Pops the disc out into the floating dial, or puts it back; nil hides the pill.
    let onPopOut: (() -> Void)?
    /// Whether the dial is out, so the pill reads Pop out or Put back.
    let placement: DialPlacement?
    /// Clicking the cover opens or closes the list window.
    let onCover: (() -> Void)?
    /// Tells the cover's hint whether a Music song plays from an album or a playlist.
    let list: ListModel?

    init(nowPlaying: NowPlaying, library: LibraryStore, artwork: ArtworkCache, onLibrary: @escaping () -> Void,
         onPopOut: (() -> Void)? = nil, placement: DialPlacement? = nil, onCover: (() -> Void)? = nil,
         list: ListModel? = nil) {
        self.onPopOut = onPopOut
        self.placement = placement
        self.onCover = onCover
        self.list = list
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
        self.library = library
        self.artwork = artwork
        self.onLibrary = onLibrary
    }

    /// Between the panel's rows, and the extra room round the disc so it doesn't crowd the text above and
    /// the pills below (22 pt from the halo's edge in all).
    static let rowSpacing: CGFloat = 14
    /// The times either side of the disc: each gets what's left of the row, less the halo and a hair's gap.
    static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    static let timeColumnWidth: CGFloat = (width - 32 - DialGeometry.discSize) / 2 - timeHaloClearance
    static let timeHaloClearance: CGFloat = (DialGeometry.haloSide - DialGeometry.discSize) / 2 + 1
    /// An hour-long time ("−1:13:32") shrinks this far to stay on one line.
    static let timeMinimumScale: CGFloat = 0.7
    static let discBreathing: CGFloat = 8

    var body: some View {
        // No GlassEffectContainer: it draws all its glass as one layer, which merged the disc's button into
        // the disc and drew the ring and the pill glyphs underneath.
        VStack(spacing: Self.rowSpacing) {
            if let display = nowPlaying.display {
                header(display)
                discRow(display)
                    .padding(.vertical, Self.discBreathing)
                if display.kind == .podcast, let failure = player.failure {
                    Text(failure).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
                }
                if display.kind == .podcast, !nowPlaying.chapters.isEmpty { chapterMenu }
                if display.kind == .music, let paused = nowPlaying.pausedEpisode { resumePill(paused) }
                upNext
            } else {
                DiscView(nowPlaying: nowPlaying)
                    .padding(.top, 6)
                Text("Find a show in Library")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                footer
            }
        }
        .padding(16)
        .padding(.bottom, 2)
        .onHover { hovering = $0 }
        .frame(width: Self.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    // MARK: Header

    /// The cover and title change together: a new song keeps the last one's until its cover is in, then both
    /// develop in at once.
    private func header(_ current: NowPlayingDisplay) -> some View {
        let settled = nowPlaying.coverSettled
        let display = settled ? current : (settledDisplay ?? current)
        let identity = settled ? nowPlaying.coverIdentity : nil
        return VStack(alignment: .leading, spacing: 10) {
            // While waiting, a podcast's cover mustn't borrow the last song's artwork.
            CoverButton(artwork: artwork, display: display,
                        image: display.kind == .music ? nowPlaying.musicArtwork : nil, identity: identity,
                        hint: coverHint, spokenHint: spokenCoverHint, action: onCover)
                .overlay(alignment: .top) { coverCorners }
            titles(display)
                .id(display.title + "\u{1F}" + display.subtitle)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
        }
        .animation(CoverButton.develop, value: display.title + "\u{1F}" + display.subtitle)
        .foregroundStyle(.primary)
        .onAppear { settledDisplay = current }
        .onChange(of: settled ? current : nil) { _, now in
            if let now { settledDisplay = now }
        }
    }

    private func titles(_ display: NowPlayingDisplay) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                if !display.subtitle.isEmpty || display.source != nil {
                    HStack(spacing: 5) {
                        if !display.subtitle.isEmpty {
                            Text(display.subtitle)
                                .font(.system(size: 11))
                                .opacity(0.8)
                                .lineLimit(1)
                        }
                        if let source = display.source {
                            SourceMark(source: source)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coverHint: String {
        ListContent.hint(mode: nowPlaying.mode, source: nowPlaying.music?.source,
                         contextKind: nowPlaying.music?.contextKind)
    }

    private var spokenCoverHint: String {
        ListContent.spokenHint(mode: nowPlaying.mode, source: nowPlaying.music?.source,
                               contextKind: nowPlaying.music?.contextKind)
    }

    /// Library and Pop out, in the cover's top corners while the pointer is over the panel.
    private var coverCorners: some View {
        HStack {
            CornerButton(label: "Library", action: onLibrary) {
                LibraryGlyph().fill(Color(nsColor: .labelColor)).frame(width: 13, height: 12)
            }
            Spacer(minLength: 0)
            if let onPopOut {
                if let placement {
                    PopOutCorner(placement: placement, action: onPopOut)
                } else {
                    CornerButton(label: "Pop out", action: onPopOut) { Text("\u{2197}") }
                }
            }
        }
        .padding(10)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: Disc and times

    /// The times sit either side of the disc, like the ends of a scrubber.
    private func discRow(_ display: NowPlayingDisplay) -> some View {
        HStack(spacing: 0) {
            Text(TimeFormat.clock(nowPlaying.displayPosition))
                .lineLimit(1)
                .minimumScaleFactor(Self.timeMinimumScale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Self.timeHaloClearance)
            DiscView(nowPlaying: nowPlaying, showsControls: true)
            Group {
                if let duration = display.duration {
                    Text(TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition)))
                } else {
                    Text("")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(Self.timeMinimumScale)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Self.timeHaloClearance)
        }
        // The halo reaches past the disc; reserve it, so the gaps above and below are real.
        .frame(height: DialGeometry.haloSide)
        .font(Font(Self.timeFont))
        .foregroundStyle(.secondary)
    }

    // MARK: Pills

    /// While music has the dial, the waiting podcast is one click away.
    private func resumePill(_ episode: Episode) -> some View {
        Button { nowPlaying.resumePodcast() } label: {
            HStack(spacing: 6) {
                PlayPauseGlyph(isPlaying: false).fill(Color(nsColor: .labelColor)).frame(width: 7, height: 8)
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

/// A small round glass button for the cover's corners.
private struct CornerButton<Glyph: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            glyph()
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Pop out while the dial lives in the panel, Put back while it floats.
private struct PopOutCorner: View {
    @ObservedObject var placement: DialPlacement
    let action: () -> Void

    var body: some View {
        CornerButton(label: placement.isPoppedOut ? "Put back" : "Pop out", action: action) {
            Text(placement.isPoppedOut ? "\u{2199}" : "\u{2197}")
        }
    }
}

/// Three spines on a shelf, the last leaning.
struct LibraryGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let spine = w * 0.24, gap = w * 0.1
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: spine, height: h),
                            cornerSize: CGSize(width: 1, height: 1))
        path.addRoundedRect(in: CGRect(x: rect.minX + spine + gap, y: rect.minY, width: spine, height: h),
                            cornerSize: CGSize(width: 1, height: 1))
        let leaning = Path(roundedRect: CGRect(x: rect.minX + 2 * (spine + gap), y: rect.minY + h * 0.08,
                                               width: spine, height: h * 0.92),
                           cornerSize: CGSize(width: 1, height: 1))
            .applying(CGAffineTransform(translationX: -rect.minX - 2 * (spine + gap), y: -rect.maxY)
                .concatenating(CGAffineTransform(rotationAngle: -0.28))
                .concatenating(CGAffineTransform(translationX: rect.minX + 2 * (spine + gap) + spine * 0.6, y: rect.maxY)))
        path.addPath(leaning)
        return path
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
         onPopOut: (() -> Void)? = nil, placement: DialPlacement? = nil, onCover: (() -> Void)? = nil,
         list: ListModel? = nil) {
        panel = DialPanelWindow(contentRect: NSRect(x: 0, y: 0, width: DialPanelView.width, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass carries its own depth; a window shadow is drawn around the square frame, past the corners.
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let root = DialPanelView(nowPlaying: nowPlaying, library: library, artwork: artwork, onLibrary: onLibrary,
                                 onPopOut: onPopOut, placement: placement, onCover: onCover, list: list)
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
    /// Whose cover this is; a new one develops in over the old. Nil keeps whatever is up.
    let identity: String?
    let hint: String
    let spokenHint: String
    let action: (() -> Void)?
    @State private var hovering = false
    @State private var shownIdentity: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A cover coming into focus behind glass.
    static let develop = Animation.spring(response: 0.45, dampingFraction: 0.9)

    /// Changes when the picture does: another song or episode, or its artwork arriving from the cache.
    private var pictureKey: String {
        let hasArtwork = image != nil || artwork.image(for: display.artworkURL) != nil
        return (shownIdentity ?? display.artworkSeed) + (hasArtwork ? "" : "~")
    }
    /// Resets itself if the press is interrupted (the panel closes mid-press).
    @GestureState private var pressed = false

    var body: some View {
        ZStack {
            ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                        size: Self.size, cornerRadius: 18, image: image)
                .id(pictureKey)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .modifier(active: Developing(amount: 0), identity: Developing(amount: 1)),
                    removal: .opacity))
        }
        .animation(Self.develop, value: pictureKey)
        .onAppear { shownIdentity = identity }
        .onChange(of: identity) { _, new in if let new { shownIdentity = new } }
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
            .accessibilityLabel("Cover")
            .accessibilityHint(spokenHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action?() }
    }
}

/// A small coloured dot for where a song plays; hovering names it, and VoiceOver reads the name.
struct SourceMark: View {
    let source: MusicSourceID

    var body: some View {
        Circle()
            .fill(Color(red: Double(source.markHex >> 16 & 0xFF) / 255, green: Double(source.markHex >> 8 & 0xFF) / 255,
                        blue: Double(source.markHex & 0xFF) / 255))
            .frame(width: 6, height: 6)
            .padding(3)                 // a larger target for the tooltip
            .contentShape(Rectangle())
            .help(source.displayName)
            .accessibilityElement()
            .accessibilityLabel(source.displayName)
    }
}

/// The develop-in: from slightly small, soft and clear to full size, sharp and solid.
private struct Developing: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 12 * (1 - amount))
            .scaleEffect(0.96 + 0.04 * amount)
            .opacity(amount)
    }
}
