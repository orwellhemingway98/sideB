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

    private let panel: NSPanel
    private let placement: DialPlacement
    private let onPutBack: () -> Void

    init(nowPlaying: NowPlaying, placement: DialPlacement, onPutBack: @escaping () -> Void,
         onLibrary: @escaping () -> Void, artwork: ArtworkCache? = nil) {
        self.placement = placement
        self.onPutBack = onPutBack
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: MiniPlayer.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // White ink on glass, like the panel: dark in Light mode too.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let root = FloatingDialView(nowPlaying: nowPlaying, artwork: artwork ?? ArtworkCache(),
                                    onPutBack: { [weak self] in self?.putBack() },
                                    onLibrary: onLibrary)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: MiniPlayer.size)
        panel.contentView = hosting
        if !panel.setFrameUsingName(Self.autosaveName), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - MiniPlayer.size.width / 2, y: screen.midY - MiniPlayer.size.height / 2))
        }
        panel.setFrameAutosaveName(Self.autosaveName)
        // A saved frame from the round dial keeps its place but takes the mini player's size.
        panel.setContentSize(MiniPlayer.size)
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
            .background(GrabArea())
            .background(WindowGlass(cornerRadius: MiniPlayer.cornerRadius, tint: CoverTint.glassTint(for: coverImage)))
            .frame(width: MiniPlayer.size.width, height: MiniPlayer.size.height)
            .contextMenu {
                Button("Put Back", action: onPutBack)
                Button("Open Library\u{2026}", action: onLibrary)
                Divider()
                Button("Quit Spindle") { NSApp.terminate(nil) }
            }
    }
}

/// The menu bar strip, grown into two rows: the cover with the title and the artist and its source, then the
/// progress line with the times, and back, play/pause and forward under it.
struct MiniPlayer: View {
    static let size = CGSize(width: 300, height: 120)
    private static let padding: CGFloat = 12
    private static let coverSide: CGFloat = 40
    private static let coverRadius: CGFloat = 10
    /// Parallel corners: the window's radius is the cover's plus the padding round it.
    static let cornerRadius = coverRadius + padding

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache

    /// Where along a line of `width` a pointer at `x` lands, held to the line's ends.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                cover
                VStack(alignment: .leading, spacing: 1) {
                    if let display = nowPlaying.display {
                        Text(display.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(display.subtitle).lineLimit(1)
                            if let source = display.source { SourceMark(source: source, size: 11) }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(DialPanelView.emptyTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)   // the window drags from here
            }
            VStack(spacing: 0) {
                ProgressLine(nowPlaying: nowPlaying, host: .floating, height: 4)
                ZStack {
                    times
                    TransportControls(nowPlaying: nowPlaying, playSize: 34)
                }
            }
        }
        .padding(Self.padding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }

    private var cover: some View {
        Group {
            if let display = nowPlaying.display {
                ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                            size: Self.coverSide, cornerRadius: Self.coverRadius,
                            image: display.kind == .music ? nowPlaying.musicArtwork : nil)
            } else {
                RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: Self.coverSide, height: Self.coverSide)
            }
        }
        .allowsHitTesting(false)
    }

    private var times: some View {
        HStack {
            if let volume = nowPlaying.volumeShown {
                Text("\(volume)%")
            } else {
                Text(TimeFormat.clock(nowPlaying.displayPosition))
            }
            Spacer()
            if let duration = nowPlaying.displayDuration, nowPlaying.volumeShown == nil {
                Text(TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition)))
            }
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
        .opacity(nowPlaying.display == nil ? 0 : 1)
        .allowsHitTesting(false)
    }
}

/// Behind the mini player: dragging anywhere that isn't a control moves the window.
private struct GrabArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
