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

/// The mini player: the menu bar strip grown into a floating glass capsule above other windows, dragged by
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
            .background(WindowGlass(cornerRadius: MiniPlayer.size.height / 2, tint: CoverTint.glassTint(for: coverImage)))
            .frame(width: MiniPlayer.size.width, height: MiniPlayer.size.height)
            .contextMenu {
                Button("Put Back", action: onPutBack)
                Button("Open Library\u{2026}", action: onLibrary)
                Divider()
                Button("Quit Spindle") { NSApp.terminate(nil) }
            }
    }
}

/// The menu bar strip, grown: the cover, the title and artist with the source, and the progress line. With the
/// pointer over it, play/pause shows on the cover, back and forward at the right and the times under the line.
struct MiniPlayer: View {
    static let size = CGSize(width: 300, height: 56)
    private static let cover: CGFloat = 42

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject var artwork: ArtworkCache
    @State private var hovering = false

    /// Where along a line of `width` a pointer at `x` lands, held to the line's ends.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }

    var body: some View {
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
                ProgressLine(nowPlaying: nowPlaying, host: .floating, height: 3)
                    .padding(.top, -3)
                    .overlay(alignment: .bottom) { if hovering { times.offset(y: 9) } }
            }
            .allowsHitTesting(nowPlaying.display != nil)
            if hovering, nowPlaying.display != nil {
                HStack(spacing: 2) {
                    skip(forward: false)
                    skip(forward: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Capsule())
        .onHover { inside in withAnimation(.easeOut(duration: 0.2)) { hovering = inside } }
    }

    private var cover: some View {
        Group {
            if let display = nowPlaying.display {
                Button { nowPlaying.toggle() } label: {
                    ArtworkView(cache: artwork, url: display.artworkURL, seed: display.artworkSeed,
                                size: Self.cover, cornerRadius: 11,
                                image: display.kind == .music ? nowPlaying.musicArtwork : nil)
                        .overlay {
                            if hovering {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(.black.opacity(0.3))
                                    .overlay(PlayPauseGlyph(isPlaying: display.isPlaying)
                                        .fill(.white).frame(width: 12, height: 14))
                                    .transition(.opacity)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(display.isPlaying ? "Pause" : "Play")
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .frame(width: Self.cover, height: Self.cover)
            }
        }
    }

    private var times: some View {
        HStack {
            Text(TimeFormat.clock(nowPlaying.displayPosition))
            Spacer()
            if let duration = nowPlaying.displayDuration {
                Text(TimeFormat.remaining(max(0, duration - nowPlaying.displayPosition)))
            }
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
    }

    private func skip(forward: Bool) -> some View {
        let music = nowPlaying.mode == .music
        let label = forward ? (music ? "Next track" : "Forward 30 seconds") : (music ? "Previous track" : "Back 15 seconds")
        return Button { forward ? nowPlaying.forward() : nowPlaying.back() } label: {
            Group {
                if music {
                    TrackSkipGlyph(forward: forward).fill(Color(nsColor: .labelColor)).frame(width: 14, height: 10)
                } else {
                    Text(forward ? "+30" : "\u{2212}15").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color(nsColor: .labelColor))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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
