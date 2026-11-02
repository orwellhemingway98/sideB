import AppKit
import SwiftUI

/// The 150 pt glass disc: a progress ring with chapter dots round a play/pause button.
/// Turn it (two-finger rotate, scroll, or drag round the ring) to scrub; press the centre to
/// play or pause; press the ring to jump there. With controls, it also carries back and forward at
/// 9 and 3 o'clock (⏮ ⏭ for music, −15 and +30 for podcasts) and the podcast speed under the centre.
struct DiscView: View {
    static let size: CGFloat = DialGeometry.discSize
    private static let buttonSize: CGFloat = 60

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer

    @State private var lastRotation: Angle?
    @State private var dragAngle: Double?
    @State private var dragIgnored = false
    @State private var scroll = ScrollMonitor()
    /// Where the glass's highlight sits; it turns as the wheel is turned.
    @State private var highlight: Double = -40
    /// The pointer is over the wheel: back and forward bud out of the glass.
    @State private var pointerNear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which window the disc is in; only the panel's disc follows the panel's notifications.
    let host: DiscHost
    /// Draws back, forward and speed on the disc.
    let showsControls: Bool

    init(nowPlaying: NowPlaying, host: DiscHost = .panel, showsControls: Bool = false) {
        self.host = host
        self.showsControls = showsControls
        self.nowPlaying = nowPlaying
        _player = ObservedObject(wrappedValue: nowPlaying.player)
    }

    private var center: CGPoint { CGPoint(x: Self.size / 2, y: Self.size / 2) }

    private var duration: TimeInterval? {
        guard let duration = nowPlaying.displayDuration, duration > 0 else { return nil }
        return duration
    }

    private var progress: Double {
        guard nowPlaying.display != nil, let duration else { return 0 }
        return min(1, max(0, nowPlaying.displayPosition / duration))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .glassEffect(.regular, in: Circle())
                .overlay(specular)
            ring
            centreButton
            if showsControls { controls.allowsHitTesting(false) }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(dragGesture.exclusively(before: tapGesture))
        .simultaneousGesture(rotateGesture)
        .background(ScrollAnchor(monitor: scroll))
        .onHover { inside in
            pointerNear = inside
            if inside { installScroll() } else { scroll.remove() }
        }
        // The monitor only acts on scrolls over the disc, so it can go in as soon as the panel shows.
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didShow)) { _ in
            if host.followsPanel { installScroll() }
        }
        // A disc that appears while its panel is already up (the panel swaps in a new one when the first
        // episode opens) gets no didShow. Its anchor joins the window after onAppear, so check on the next turn.
        .onAppear {
            DispatchQueue.main.async { if scroll.anchorIsOnScreen { installScroll() } }
        }
        .onDisappear { scroll.remove() }
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didClose)) { _ in
            if host.followsPanel { scroll.remove() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dial")
        .accessibilityValue(Self.spokenValue(isPlaying: nowPlaying.display?.isPlaying,
                                             position: nowPlaying.displayPosition, duration: duration))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { nowPlaying.toggle() }
        .accessibilityActions {
            if showsControls {
                Button(isMusic ? "Previous track" : "Back 15 seconds") { perform(.back) }
                Button(isMusic ? "Next track" : "Forward 30 seconds") { perform(.forward) }
                if speedShown { Button("Speed \(DialPanelView.rateLabel(player.rate))") { perform(.speed) } }
            }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nowPlaying.skip(by: 30)
            case .decrement: nowPlaying.skip(by: -15)
            @unknown default: break
            }
        }
    }

    /// What VoiceOver says the dial is at: "Playing, 12:04 of 48:10".
    static func spokenValue(isPlaying: Bool?, position: TimeInterval, duration: TimeInterval?) -> String {
        guard let isPlaying else { return "Nothing playing" }
        let state = isPlaying ? "Playing" : "Paused"
        guard let duration, duration > 0 else { return state }
        return "\(state), \(TimeFormat.clock(position)) of \(TimeFormat.clock(duration))"
    }

    private func installScroll() {
        scroll.install { degrees in turn(by: degrees) }
    }

    // MARK: Drawing

    /// The wheel is turned (scrubbing, or Option + turn for the volume) until the scrub is committed.
    private var isTurning: Bool { nowPlaying.scrubPosition != nil || nowPlaying.volumeShown != nil }

    /// Every turn goes through here, so the glass's highlight turns with the hand.
    private func turn(by degrees: Double) {
        nowPlaying.turn(degrees: degrees)
        guard nowPlaying.display != nil else { return }
        highlight += degrees
    }

    /// The glass's edge, caught by light: a bright highlight and a fainter one opposite, turning with the wheel.
    private var specular: some View {
        Circle()
            .strokeBorder(AngularGradient(stops: [
                .init(color: .white.opacity(0.7), location: 0), .init(color: .clear, location: 0.08),
                .init(color: .clear, location: 0.44), .init(color: .white.opacity(0.25), location: 0.5),
                .init(color: .clear, location: 0.56), .init(color: .clear, location: 0.92),
                .init(color: .white.opacity(0.7), location: 1),
            ], center: .center, angle: .degrees(highlight)), lineWidth: 1)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: highlight)
            .allowsHitTesting(false)
    }

    /// The time, as light caught inside the glass rim: it fades in from 12 o'clock and runs to now, with a
    /// small break where each chapter starts. While Option + turn sets the volume, it shows that. No track.
    private var ring: some View {
        let volume = nowPlaying.volumeShown
        let progress = volume.map { Double($0) / 100 } ?? progress
        let chapters = volume == nil ? chapterFractions : []
        let r = WheelLight.radius, w = WheelLight.width + (isTurning ? 1 : 0)
        let brightness = isTurning ? 1.0 : 0.85
        let side = DialGeometry.haloSide
        return Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func arc(_ from: Double, _ to: Double) -> Path {
                Path { p in
                    p.addArc(center: c, radius: r, startAngle: .degrees(from * 360 - 90),
                             endAngle: .degrees(to * 360 - 90), clockwise: false)
                }
            }
            guard progress > 0 else { return }
            // The fade-in, in short steps, then the rest at full strength with a round end at now.
            let fadeEnd = min(progress, WheelLight.fadeLength)
            let steps = 14
            for i in 0..<steps {
                let a = fadeEnd * Double(i) / Double(steps), b = fadeEnd * Double(i + 1) / Double(steps)
                context.stroke(arc(a, b + 0.001), with: .color(.white.opacity(brightness * WheelLight.opacity(atFraction: b))),
                               lineWidth: w)
            }
            if progress > fadeEnd {
                context.stroke(arc(fadeEnd, progress), with: .color(.white.opacity(brightness)),
                               style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            context.blendMode = .destinationOut
            for f in chapters where f > 0 && f < progress {
                context.stroke(arc(f - 0.004, f + 0.004), with: .color(.black), lineWidth: w + 2)
            }
        }
        .frame(width: side, height: side)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isTurning)
        .allowsHitTesting(false)
        .opacity(nowPlaying.display == nil ? 0.5 : 1)
    }

    /// Where the chapters start, as shares of the episode (podcasts only).
    private var chapterFractions: [Double] {
        guard nowPlaying.mode == .podcast, player.episode != nil, let duration else { return [] }
        return nowPlaying.chapters.map { min(1, max(0, $0.start / duration)) }
    }

    private var isMusic: Bool { nowPlaying.mode == .music }

    private var speedShown: Bool { showsControls && !isMusic && player.episode != nil }

    /// Back and forward fade in while the pointer is over the wheel and out when it leaves; at rest the wheel
    /// is just the wheel. Their spots work either way.
    private var controls: some View {
        let ink = Color(nsColor: .labelColor)
        let shown = pointerNear && nowPlaying.display != nil
        return ZStack {
            Group {
                if isMusic {
                    TrackSkipGlyph(forward: false).fill(ink).frame(width: 13, height: 9)
                } else {
                    Text("\u{2212}15").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(ink)
                }
            }
            .modifier(Bud(shown: shown, reduceMotion: reduceMotion))
            .offset(x: -DialGeometry.controlOffset)
            Group {
                if isMusic {
                    TrackSkipGlyph(forward: true).fill(ink).frame(width: 13, height: 9)
                } else {
                    Text("+30").font(.system(size: 10, weight: .semibold).monospacedDigit()).foregroundStyle(ink)
                }
            }
            .modifier(Bud(shown: shown, reduceMotion: reduceMotion))
            .offset(x: DialGeometry.controlOffset)
            if speedShown {
                Text(DialPanelView.rateLabel(player.rate))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .offset(y: DialGeometry.speedOffset)
            }
        }
        .opacity(nowPlaying.display == nil ? 0.35 : 1)
    }

    private func zone(of point: CGPoint) -> DialGeometry.Zone {
        let zone = DialGeometry.zone(of: point, speedShown: speedShown)
        if !showsControls, zone == .back || zone == .forward {
            // Without controls those spots are plain ring, as they always were.
            return DialGeometry.ringBand.contains(distance(of: point)) ? .ring : .outside
        }
        return zone
    }

    private func perform(_ zone: DialGeometry.Zone) {
        switch zone {
        case .centre: nowPlaying.toggle()
        case .back: nowPlaying.back()
        case .forward: nowPlaying.forward()
        case .speed: nowPlaying.cycleRate()
        case .ring, .outside: break
        }
    }

    /// Play/pause, or the volume while Option + turn sets it.
    private var centreButton: some View {
        Group {
            if let volume = nowPlaying.volumeShown {
                Text("\(volume)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .contentTransition(.numericText(value: Double(volume)))
                    .accessibilityLabel("Volume \(volume) percent")
            } else {
                PlayPauseGlyph(isPlaying: nowPlaying.display?.isPlaying ?? false)
                    .fill(Color(nsColor: .labelColor))
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78),
                               value: nowPlaying.display?.isPlaying ?? false)
                    .frame(width: 18, height: 20)
                    .opacity(nowPlaying.display == nil ? 0.35 : 1)
            }
        }
        .frame(width: Self.buttonSize, height: Self.buttonSize)
        .glassEffect(.regular.interactive(), in: Circle())
    }

    // MARK: Gestures

    /// The sign that makes a clockwise twist turn clockwise. A positive SwiftUI `Angle` is clockwise on screen
    /// (Apple's example feeds `RotateGesture`'s rotation straight into `rotationEffect`), so it should be 1;
    /// the Task 11 hand check confirms it.
    static let rotateSign: Double = 1

    /// Two fingers turning on the trackpad. Only the change since the last event is fed in.
    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                let previous = lastRotation ?? .zero
                lastRotation = value.rotation
                turn(by: Self.rotateSign * (value.rotation - previous).degrees)
            }
            .onEnded { _ in lastRotation = nil }
    }

    /// Dragging round the ring. Drags that start off the ring (on the centre button or a control, say) don't
    /// turn; one that starts and ends on the same button is a press that drifted, so it still counts.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragAngle == nil, !dragIgnored {
                    guard zone(of: value.startLocation) == .ring else {
                        dragIgnored = true
                        return
                    }
                    dragAngle = DialGeometry.angle(of: value.startLocation, around: center)
                }
                guard let previous = dragAngle else { return }
                let current = DialGeometry.angle(of: value.location, around: center)
                dragAngle = current
                turn(by: DialGeometry.delta(from: previous, to: current))
            }
            .onEnded { value in
                let start = zone(of: value.startLocation)
                if dragAngle == nil, start != .ring, start == zone(of: value.location) {
                    perform(start)
                }
                dragAngle = nil
                dragIgnored = false
            }
    }

    /// A press on the centre plays or pauses, one on a control acts, one on the ring jumps to that point.
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let zone = zone(of: value.location)
                if zone == .ring {
                    if let duration {
                        nowPlaying.jump(to: DialGeometry.time(atRingPoint: value.location, center: center,
                                                              duration: duration))
                    }
                } else {
                    perform(zone)
                }
            }
    }

    private func distance(of point: CGPoint) -> CGFloat {
        hypot(point.x - center.x, point.y - center.y)
    }
}

/// A play triangle that morphs into pause bars: each is two four-sided pieces, so the triangle's halves slide
/// and square off into the bars. `morph` 0 is play, 1 is pause.
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

/// A control fading in while the pointer is over the wheel.
private struct Bud: ViewModifier {
    let shown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.2), value: shown)
    }
}
