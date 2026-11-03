import AppKit
import SwiftUI

/// The progress line that replaced the dial: drag it to move through the song or episode, or scroll over it
/// (with haptic ticks, as the dial had). Playing, it glides on between the player's ticks rather than stepping.
struct ProgressLine: View {
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer
    var height: CGFloat = 6

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var scroll = ScrollMonitor(round: false)
    @State private var positionStamp = (position: 0.0, at: Date())

    init(nowPlaying: NowPlaying, height: CGFloat = 6) {
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
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
                        dragFraction = Transport.fraction(atX: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { value in
                        if let duration {
                            let fraction = Transport.fraction(atX: value.location.x, width: geometry.size.width)
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
            installScroll()
        }
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didClose)) { _ in
            scroll.remove()
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

/// Back, play/pause and forward under the line, in Apple's own symbols: skip back and forward for music,
/// 15 seconds back and 30 on for podcasts.
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
        let playing = nowPlaying.display?.isPlaying ?? false
        let symbols = Transport.Symbols(isMusic: isMusic, isPlaying: playing)
        HStack(spacing: 26 * scale) {
            button(isMusic ? "Previous track" : "Back 15 seconds", action: nowPlaying.back) {
                Image(systemName: symbols.back).font(.system(size: 20 * scale, weight: .regular))
            }
            Button { nowPlaying.toggle() } label: {
                // No glass circle: a plain symbol, a size up from back and forward.
                Image(systemName: symbols.playPause)
                    .font(.system(size: 30 * scale, weight: .regular))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: playSize, height: playSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Pause" : "Play")
            button(isMusic ? "Next track" : "Forward 30 seconds", action: nowPlaying.forward) {
                Image(systemName: symbols.forward).font(.system(size: 20 * scale, weight: .regular))
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
    /// Where along a line of `width` a pointer at `x` lands, held to the line's ends.
    static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }

    /// The SF Symbols the playback buttons use.
    struct Symbols: Equatable {
        let back: String
        let playPause: String
        let forward: String

        init(back: String, playPause: String, forward: String) {
            self.back = back
            self.playPause = playPause
            self.forward = forward
        }

        init(isMusic: Bool, isPlaying: Bool) {
            back = isMusic ? "backward.fill" : "gobackward.15"
            playPause = isPlaying ? "pause.fill" : "play.fill"
            forward = isMusic ? "forward.fill" : "goforward.30"
        }
    }

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
