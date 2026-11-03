import AppKit
import SwiftUI

/// The progress line that replaced the dial: drag it to move through the song or episode, or scroll over it
/// (with haptic ticks, as the dial had). Playing, it glides on between the player's ticks rather than stepping.
struct ProgressLine: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer
    /// Which window the line is in; only the panel's follows the panel's show and close notifications.
    let host: DiscHost
    var height: CGFloat = 6

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var scroll = ScrollMonitor(round: false)
    @State private var positionStamp = (position: 0.0, at: Date())

    init(nowPlaying: NowPlaying, host: DiscHost = .panel, height: CGFloat = 6) {
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
        self.host = host
        self.height = height
    }

    private var duration: TimeInterval? {
        guard let duration = nowPlaying.displayDuration, duration > 0 else { return nil }
        return duration
    }

    private var isTurning: Bool { nowPlaying.scrubPosition != nil || nowPlaying.volumeShown != nil }

    var body: some View {
        let flowing = dragFraction == nil && !isTurning && nowPlaying.display?.isPlaying == true && duration != nil
        let active = hovering || dragFraction != nil || isTurning
        let thickness = active ? height + 2 : height
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !flowing)) { timeline in
            let shown = shownFraction(at: timeline.date, flowing: flowing)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white)
                        .frame(width: max(thickness, geometry.size.width * shown))
                        .opacity(nowPlaying.display == nil ? 0 : 1)
                }
                .frame(height: thickness)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration != nil else { return }
                        dragFraction = MiniPlayer.fraction(atX: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { value in
                        if let duration {
                            let fraction = MiniPlayer.fraction(atX: value.location.x, width: geometry.size.width)
                            nowPlaying.jump(to: fraction * duration)
                        }
                        dragFraction = nil
                    })
            }
        }
        .frame(height: max(16, height + 10))
        .animation(.easeOut(duration: 0.15), value: active)
        .background(ScrollAnchor(monitor: scroll))
        .onHover { inside in
            hovering = inside
            if inside { installScroll() } else { scroll.remove() }
        }
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didShow)) { _ in
            if host.followsPanel { installScroll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didClose)) { _ in
            if host.followsPanel { scroll.remove() }
        }
        .onDisappear { scroll.remove() }
        .onChange(of: nowPlaying.displayPosition, initial: true) { _, position in
            positionStamp = (position, Date())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(Transport.spokenValue(isPlaying: nowPlaying.display?.isPlaying,
                                                  position: nowPlaying.displayPosition, duration: duration))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nowPlaying.skip(by: 30)
            case .decrement: nowPlaying.skip(by: -15)
            @unknown default: break
            }
        }
    }

    /// While dragging, where the pointer is; while playing, gliding on from the last tick; else where the player is.
    private func shownFraction(at now: Date, flowing: Bool) -> Double {
        if let dragFraction { return dragFraction }
        if let volume = nowPlaying.volumeShown { return Double(volume) / 100 }
        guard let duration else { return 0 }
        if flowing {
            return Transport.flowingProgress(position: positionStamp.position,
                                             elapsed: now.timeIntervalSince(positionStamp.at),
                                             rate: nowPlaying.mode == .music ? 1 : Double(player.rate),
                                             duration: duration, playing: true)
        }
        return min(1, max(0, nowPlaying.displayPosition / duration))
    }

    private func installScroll() {
        scroll.install { [nowPlaying] degrees in nowPlaying.turn(degrees: degrees) }
    }
}

/// Back, play/pause and forward under the line: skip glyphs for music, −15 and +30 for podcasts.
struct TransportControls: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer
    var playSize: CGFloat = 52
    /// The skip glyphs scale with the play button.
    private var scale: CGFloat { playSize / 52 }

    init(nowPlaying: NowPlaying, playSize: CGFloat = 52) {
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
        self.playSize = playSize
    }

    private var isMusic: Bool { nowPlaying.mode == .music }

    var body: some View {
        let ink = Color(nsColor: .labelColor)
        let enabled = nowPlaying.display != nil
        HStack(spacing: 26 * scale) {
            button(isMusic ? "Previous track" : "Back 15 seconds", action: nowPlaying.back) {
                if isMusic {
                    TrackSkipGlyph(forward: false).fill(ink).frame(width: 21 * scale, height: 14 * scale)
                } else {
                    Text("\u{2212}15").font(.system(size: 14 * scale, weight: .semibold).monospacedDigit())
                }
            }
            Button { nowPlaying.toggle() } label: {
                PlayPauseGlyph(isPlaying: nowPlaying.display?.isPlaying ?? false)
                    .fill(ink)
                    .frame(width: playSize * 0.3, height: playSize * 0.34)
                    .animation(.spring(response: 0.3, dampingFraction: 0.78), value: nowPlaying.display?.isPlaying ?? false)
                    .frame(width: playSize, height: playSize)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlaying.display?.isPlaying == true ? "Pause" : "Play")
            button(isMusic ? "Next track" : "Forward 30 seconds", action: nowPlaying.forward) {
                if isMusic {
                    TrackSkipGlyph(forward: true).fill(ink).frame(width: 21 * scale, height: 14 * scale)
                } else {
                    Text("+30").font(.system(size: 14 * scale, weight: .semibold).monospacedDigit())
                }
            }
        }
        .foregroundStyle(ink)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func button<Label: View>(_ label: String, action: @escaping () -> Void,
                                     @ViewBuilder glyph: () -> Label) -> some View {
        Button(action: action) {
            glyph()
                .frame(width: 40 * scale, height: 40 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

enum Transport {
    /// What VoiceOver says the line is at: "Playing, 12:04 of 48:10".
    static func spokenValue(isPlaying: Bool?, position: TimeInterval, duration: TimeInterval?) -> String {
        guard let isPlaying else { return "Nothing playing" }
        let state = isPlaying ? "Playing" : "Paused"
        guard let duration, duration > 0 else { return state }
        return "\(state), \(TimeFormat.clock(position)) of \(TimeFormat.clock(duration))"
    }

    /// Between ticks of the player the line glides on at the playback speed, so it flows rather than steps;
    /// it never runs more than this many seconds past the last known place, in case the ticks stop.
    static let maxGlide: TimeInterval = 1.5

    static func flowingProgress(position: TimeInterval, elapsed: TimeInterval, rate: Double, duration: TimeInterval,
                                playing: Bool) -> Double {
        guard duration > 0 else { return 0 }
        let glide = playing ? min(max(0, elapsed) * rate, maxGlide) : 0
        return min(1, max(0, (position + glide) / duration))
    }
}

/// Pause bars, or a play triangle, that morph into each other: each is two four-sided pieces, so the
/// triangle's halves slide and square off into the bars. `morph` 0 is play, 1 is pause.
struct PlayPauseGlyph: Shape {
    var morph: Double

    init(morph: Double) { self.morph = morph }
    init(isPlaying: Bool) { morph = isPlaying ? 1 : 0 }

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    // In a unit box. The triangle is nudged right so it looks centred.
    private static let play: [CGPoint] = [
        CGPoint(x: 0.12, y: 0), CGPoint(x: 0.62, y: 0.25), CGPoint(x: 0.62, y: 0.75), CGPoint(x: 0.12, y: 1),
        CGPoint(x: 0.62, y: 0.25), CGPoint(x: 1.12, y: 0.5), CGPoint(x: 1.12, y: 0.5), CGPoint(x: 0.62, y: 0.75),
    ]
    private static let pause: [CGPoint] = [
        CGPoint(x: 0.08, y: 0), CGPoint(x: 0.40, y: 0), CGPoint(x: 0.40, y: 1), CGPoint(x: 0.08, y: 1),
        CGPoint(x: 0.60, y: 0), CGPoint(x: 0.92, y: 0), CGPoint(x: 0.92, y: 1), CGPoint(x: 0.60, y: 1),
    ]

    func path(in rect: CGRect) -> Path {
        let t = min(1, max(0, morph))
        let points = zip(Self.play, Self.pause).map { a, b in
            CGPoint(x: rect.minX + (a.x + (b.x - a.x) * t) * rect.width,
                    y: rect.minY + (a.y + (b.y - a.y) * t) * rect.height)
        }
        var path = Path()
        for piece in [points[0..<4], points[4..<8]] {
            path.addLines(Array(piece))
            path.closeSubpath()
        }
        return path
    }
}

/// ⏮ / ⏭ drawn in code: two triangles tip to base, then a bar; ⏮ is the mirror image of ⏭.
struct TrackSkipGlyph: Shape {
    var forward: Bool

    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.14
        let half = (rect.width - bar) / 2
        var path = Path()
        for start in [rect.minX, rect.minX + half] {
            path.move(to: CGPoint(x: start, y: rect.minY))
            path.addLine(to: CGPoint(x: start + half, y: rect.midY))
            path.addLine(to: CGPoint(x: start, y: rect.maxY))
            path.closeSubpath()
        }
        path.addRect(CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height))
        guard !forward else { return path }
        return path.applying(CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0).scaledBy(x: -1, y: 1))
    }
}
