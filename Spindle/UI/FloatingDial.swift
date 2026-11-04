import AppKit
import SwiftUI

/// Whether the dial is popped out of the menu bar, remembered across launches.
final class DialPlacement: ObservableObject {
    private static let key = "dialPoppedOut"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPoppedOut = defaults.bool(forKey: Self.key)
    }

    /// Published so the panel's pill can read Pop out or Put back.
    @Published var isPoppedOut: Bool {
        didSet { defaults.set(isPoppedOut, forKey: Self.key) }
    }
}

/// The mini player: just the cover, floating in a thin glass frame above other windows. The pointer brings up the
/// controls, a click turns it over to its list, and a drag moves it. Its position is remembered; "Put Back" returns
/// it to the menu bar.
@MainActor
final class FloatingDialController {
    static let autosaveName = "SpindleMiniPlayer"
    /// Clear room round the glass inside the window, as the panel keeps, so the glass's own shadow fades out
    /// instead of being cut off square at the window's edges.
    static let shadowMargin = NSEdgeInsets(top: 16, left: 24, bottom: 28, right: 24)
    private static var windowSize: NSSize {
        let m = shadowMargin
        return NSSize(width: MiniPlayer.size.width + m.left + m.right, height: MiniPlayer.size.height + m.top + m.bottom)
    }

    private let panel: NSPanel
    private let placement: DialPlacement
    private let onPutBack: () -> Void
    /// The mini player's own list and flip, apart from the panel's.
    private let listController: ListController?

    init(nowPlaying: NowPlaying, placement: DialPlacement, onPutBack: @escaping () -> Void,
         onLibrary: @escaping () -> Void, artwork: ArtworkCache? = nil, list: ListModel? = nil) {
        self.placement = placement
        self.onPutBack = onPutBack
        let listController = list.map { ListController(model: $0, nowPlaying: nowPlaying, followsPanel: false) }
        self.listController = listController
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.windowSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The glass carries its own depth; a window shadow is drawn around the square frame, past the corners.
        panel.hasShadow = false
        // White ink on glass, like the panel: dark in Light mode too.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let root = FloatingDialView(nowPlaying: nowPlaying, artwork: artwork ?? ArtworkCache(), list: list,
                                    onFlip: { listController?.toggle() },
                                    onPutBack: { [weak self] in self?.putBack() },
                                    onLibrary: onLibrary)
        let m = Self.shadowMargin
        let hosting = FirstClickHostingView(rootView: root.padding(EdgeInsets(top: m.top, leading: m.left,
                                                                               bottom: m.bottom, trailing: m.right)))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.windowSize)
        panel.contentView = hosting
        if !panel.setFrameUsingName(Self.autosaveName), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - Self.windowSize.width / 2, y: screen.midY - Self.windowSize.height / 2))
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        // A saved frame from an earlier version keeps its place but takes the mini player's size.
        panel.setContentSize(Self.windowSize)
    }

    var isShown: Bool { panel.isVisible }

    /// The dial's window.
    var window: NSWindow { panel }

    func show() {
        placement.isPoppedOut = true
        panel.orderFrontRegardless()
    }

    func putBack() {
        listController?.close(animated: false)
        placement.isPoppedOut = false
        panel.orderOut(nil)
        onPutBack()
    }
}

private struct FloatingDialView: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache
    let list: ListModel?
    let onFlip: () -> Void
    let onPutBack: () -> Void
    let onLibrary: () -> Void

    /// The cover's picture: the frame's glass takes its colour, as the panel's does.
    private var coverImage: NSImage? {
        guard let display = nowPlaying.display else { return nil }
        return (display.kind == .music ? nowPlaying.musicArtwork : nil) ?? artwork.image(for: display.artworkURL)
    }

    var body: some View {
        MiniPlayer(nowPlaying: nowPlaying, artwork: artwork, list: list, coverImage: coverImage,
                   onFlip: onFlip, onPutBack: onPutBack, onLibrary: onLibrary)
            .background(ClickOrDragArea(onClick: nil, menu: menu))
            .background(WindowGlass(cornerRadius: MiniPlayer.cornerRadius, tint: CoverTint.glassTint(for: coverImage)))
            .frame(width: MiniPlayer.size.width, height: MiniPlayer.size.height)
    }

    private func menu() -> NSMenu { MiniPlayer.menu(onPutBack: onPutBack, onLibrary: onLibrary) }
}

/// The cover and nothing else, until the pointer comes over it: then Library, a turn-over hint and Put Back along
/// the top, and the progress line, times and buttons along the bottom over a soft dark fade.
struct MiniPlayer: View {
    /// The thin glass frame round the panel's 240 pt cover.
    static let frameWidth: CGFloat = 10
    static let size = CGSize(width: CoverButton.size + 2 * frameWidth, height: CoverButton.size + 2 * frameWidth)
    /// Parallel corners: the cover's radius plus the frame.
    static let cornerRadius = DialPanelView.coverCornerRadius + frameWidth
    /// How far the pointer moves before a press on the cover is a drag and not a click.
    static let dragThreshold: CGFloat = 3

    static func isDrag(from start: NSPoint, to now: NSPoint) -> Bool {
        hypot(now.x - start.x, now.y - start.y) >= dragThreshold
    }

    /// The right-click menu: Put Back, the Library and Quit.
    @MainActor
    static func menu(onPutBack: @escaping () -> Void, onLibrary: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ActionItem("Put Back", run: onPutBack))
        menu.addItem(ActionItem("Open Library\u{2026}", run: onLibrary))
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit Spindle") { NSApp.terminate(nil) })
        return menu
    }

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache
    let list: ListModel?
    let coverImage: NSImage?
    let onFlip: () -> Void
    let onPutBack: () -> Void
    let onLibrary: () -> Void

    @State private var hovering = false
    /// What the cover showed last time it was settled; kept while a new song's cover loads.
    @State private var settledDisplay: NowPlayingDisplay?

    var body: some View {
        Group {
            if let current = nowPlaying.display {
                if let list {
                    CoverFlip(list: list, nowPlaying: nowPlaying, tint: coverImage.flatMap(CoverTint.backColour(for:)),
                              turnBack: onFlip) { front(current) }
                } else {
                    front(current)
                }
            } else {
                empty
            }
        }
        .frame(width: CoverButton.size, height: CoverButton.size)
        .frame(width: Self.size.width, height: Self.size.height)
        .onHover { inside in withAnimation(.easeOut(duration: 0.2)) { hovering = inside } }
        .onChange(of: nowPlaying.coverSettled ? nowPlaying.display : nil) { _, now in
            if let now { settledDisplay = now }
        }
    }

    private func front(_ current: NowPlayingDisplay) -> some View {
        // A new song keeps the last one's cover until its own is in, then it develops in.
        let settled = nowPlaying.coverSettled
        let display = settled ? current : (settledDisplay ?? current)
        return ZStack {
            CoverButton(artwork: artwork, display: display,
                        image: display.kind == .music ? nowPlaying.musicArtwork : nil,
                        identity: settled ? nowPlaying.coverIdentity : nil,
                        hint: hintWord, spokenHint: spokenHint, action: onFlip, showsHint: false)
            ClickOrDragArea(onClick: onFlip, menu: { MiniPlayer.menu(onPutBack: onPutBack, onLibrary: onLibrary) })
            if hovering {
                controls.transition(.opacity)
            }
        }
    }

    private var hintWord: String {
        ListContent.hint(mode: nowPlaying.mode, source: nowPlaying.music?.source,
                         contextKind: nowPlaying.music?.contextKind)
    }

    private var spokenHint: String {
        ListContent.spokenHint(mode: nowPlaying.mode, source: nowPlaying.music?.source,
                               contextKind: nowPlaying.music?.contextKind)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                ProgressLine(nowPlaying: nowPlaying, host: .floating, height: 4)
                times
                TransportControls(nowPlaying: nowPlaying, playSize: 40)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            // A near miss between the buttons does nothing, rather than turning the cover over.
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .background(alignment: .bottom) {
            // Keeps the white controls readable over any artwork.
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: DialPanelView.coverCornerRadius, style: .continuous))
        .frame(width: CoverButton.size, height: CoverButton.size)
    }

    private var topRow: some View {
        HStack {
            libraryButton
            Spacer(minLength: 0)
            if list != nil {
                Button(action: onFlip) {
                    TurnHint(word: hintWord)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenHint)
                Spacer(minLength: 0)
            }
            putBackButton
        }
        .padding(10)
    }

    private var libraryButton: some View {
        CornerButton(label: "Library", action: onLibrary) {
            LibraryGlyph().fill(Color(nsColor: .labelColor)).frame(width: 13, height: 12)
        }
    }

    private var putBackButton: some View {
        CornerButton(label: "Put back", action: onPutBack) { PopOutArrow(back: true) }
    }

    private var times: some View {
        HStack {
            if let volume = nowPlaying.volumeShown {
                Text("Volume \(volume)%")
            } else {
                Text(TimeFormat.clock(nowPlaying.displayPosition))
            }
            Spacer(minLength: 8)
            if let duration = nowPlaying.displayDuration, nowPlaying.volumeShown == nil {
                Text(TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition)))
            }
        }
        .lineLimit(1)
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.8))
        .allowsHitTesting(false)
    }

    /// Nothing to show: a plain tile that still moves, opens the Library and goes back.
    private var empty: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DialPanelView.coverCornerRadius, style: .continuous)
                .fill(.white.opacity(0.08))
            Text(DialPanelView.emptyTitle)
                .font(.system(size: DialPanelView.titleSize, weight: .semibold))
                .foregroundStyle(.secondary)
            ClickOrDragArea(onClick: nil, menu: { MiniPlayer.menu(onPutBack: onPutBack, onLibrary: onLibrary) })
            if hovering {
                VStack {
                    HStack {
                        libraryButton
                        Spacer(minLength: 0)
                        putBackButton
                    }
                    .padding(10)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
    }
}

/// The hosting view takes the first click, so a button works without the window being brought forward first.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Where a press moves the window if it drags and clicks if it doesn't. Right-clicking gives the mini player's menu.
private struct ClickOrDragArea: NSViewRepresentable {
    let onClick: (() -> Void)?
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> AreaView { AreaView() }

    func updateNSView(_ view: AreaView, context: Context) {
        view.onClick = onClick
        view.makeMenu = menu
    }

    final class AreaView: NSView {
        var onClick: (() -> Void)?
        var makeMenu: (() -> NSMenu)?
        private var pressedAt: NSPoint?
        private var windowOrigin: NSPoint?
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // The mouse location in screen terms, because the view moves with the window while dragging.
        override func mouseDown(with event: NSEvent) {
            pressedAt = NSEvent.mouseLocation
            windowOrigin = window?.frame.origin
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let pressedAt, let windowOrigin else { return }
            let now = NSEvent.mouseLocation
            if !dragging, !MiniPlayer.isDrag(from: pressedAt, to: now) { return }
            dragging = true
            window?.setFrameOrigin(NSPoint(x: windowOrigin.x + now.x - pressedAt.x, y: windowOrigin.y + now.y - pressedAt.y))
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging { onClick?() }
            pressedAt = nil
            windowOrigin = nil
            dragging = false
        }

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
