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

/// The mini player: the menu bar strip grown into a small floating glass player above other windows, dragged by
/// anywhere that isn't a control. Its position is remembered; "Put Back" returns it to the menu bar.
@MainActor
final class FloatingDialController {
    static let autosaveName = "SpindleFloatingDial"
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

    init(nowPlaying: NowPlaying, placement: DialPlacement, onPutBack: @escaping () -> Void,
         onLibrary: @escaping () -> Void, artwork: ArtworkCache? = nil) {
        self.placement = placement
        self.onPutBack = onPutBack
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
        let root = FloatingDialView(nowPlaying: nowPlaying, artwork: artwork ?? ArtworkCache(),
                                    onPutBack: { [weak self] in self?.putBack() },
                                    onLibrary: onLibrary)
        let m = Self.shadowMargin
        let hosting = NSHostingView(rootView: root.padding(EdgeInsets(top: m.top, leading: m.left,
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
        placement.isPoppedOut = false
        panel.orderOut(nil)
        onPutBack()
    }
}

private struct FloatingDialView: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache
    let onPutBack: () -> Void
    let onLibrary: () -> Void

    /// The cover's picture: the capsule's glass takes its colour, as the panel's does.
    private var coverImage: NSImage? {
        guard let display = nowPlaying.display else { return nil }
        return (display.kind == .music ? nowPlaying.musicArtwork : nil) ?? artwork.image(for: display.artworkURL)
    }

    var body: some View {
        MiniPlayer(nowPlaying: nowPlaying, artwork: artwork)
            .background(GrabArea(menu: { MiniPlayer.menu(onPutBack: onPutBack, onLibrary: onLibrary) }))
            .background(WindowGlass(cornerRadius: MiniPlayer.cornerRadius, tint: CoverTint.glassTint(for: coverImage)))
            .frame(width: MiniPlayer.size.width, height: MiniPlayer.size.height)
    }
}

/// A small Now Playing card in the panel's glass language: the cover, lifted, with the title and the artist and
/// its source; the times either side of the progress line; then back, the glass play/pause and forward.
struct MiniPlayer: View {
    static let size = CGSize(width: 340, height: 164)
    private static let padding: CGFloat = 14
    private static let coverSide: CGFloat = 56
    private static let coverRadius: CGFloat = 12
    /// Parallel corners: the window's radius is the cover's plus the padding round it.
    static let cornerRadius = coverRadius + padding

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache

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

    /// Where along a line of `width` a pointer at `x` lands, held to the line's ends.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    if let display = nowPlaying.display {
                        Text(display.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(display.subtitle).lineLimit(1)
                            if let source = display.source { SourceMark(source: source, size: 13) }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(DialPanelView.emptyTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)   // the window drags from here
            HStack(spacing: 10) {
                Text(elapsed).frame(width: 40, alignment: .leading)
                ProgressLine(nowPlaying: nowPlaying, host: .floating, height: 6)
                Text(remaining).frame(width: 44, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            TransportControls(nowPlaying: nowPlaying, playSize: 44)
        }
        .padding(Self.padding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }

    private var elapsed: String {
        guard nowPlaying.display != nil else { return "" }
        if let volume = nowPlaying.volumeShown { return "\(volume)%" }
        return TimeFormat.clock(nowPlaying.displayPosition)
    }

    private var remaining: String {
        guard nowPlaying.volumeShown == nil, let duration = nowPlaying.displayDuration else { return "" }
        return TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition))
    }

    private var cover: some View {
        Group {
            if let display = nowPlaying.display {
                ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                            size: Self.coverSide, cornerRadius: Self.coverRadius,
                            image: display.kind == .music ? nowPlaying.musicArtwork : nil)
                    .overlay(RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    // The panel's cover lift, scaled down: only the cover sits above the glass.
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            } else {
                RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: Self.coverSide, height: Self.coverSide)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Behind the mini player: dragging anywhere that isn't a control moves the window.
/// Right-clicking it gives the mini player's menu, wherever the click lands.
private struct GrabArea: NSViewRepresentable {
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> NSView { DragView(menu: menu) }
    func updateNSView(_ view: NSView, context: Context) { (view as? DragView)?.makeMenu = menu }

    private final class DragView: NSView {
        var makeMenu: () -> NSMenu

        init(menu: @escaping () -> NSMenu) {
            makeMenu = menu
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }
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
