import AppKit
import SwiftUI

/// The 150 pt glass disc: a progress ring with chapter dots round a play/pause button.
/// Turn it (two-finger rotate, scroll, or drag round the ring) to scrub; press the centre to
/// play or pause; press the ring to jump there.
struct DiscView: View {
    static let size: CGFloat = 150
    /// Presses and drags count as on the ring between these radii.
    static let ringBand: ClosedRange<CGFloat> = 45...75
    /// A press inside this radius is on the centre button.
    static let centreRadius: CGFloat = 30
    private static let ringRadius: CGFloat = 63
    private static let ringWidth: CGFloat = 3
    private static let buttonSize: CGFloat = 60

    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var player: PodcastPlayer

    @State private var lastRotation: Angle?
    @State private var dragAngle: Double?
    @State private var dragIgnored = false
    @State private var scroll = ScrollMonitor()

    init(nowPlaying: NowPlaying) {
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
                .overlay(rim)
            ring
            centreButton
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(dragGesture.exclusively(before: tapGesture))
        .simultaneousGesture(rotateGesture)
        .background(ScrollAnchor(monitor: scroll))
        .onHover { inside in
            if inside { installScroll() } else { scroll.remove() }
        }
        // The monitor only acts on scrolls over the disc, so it can go in as soon as the panel shows.
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didShow)) { _ in installScroll() }
        // A disc that appears while its panel is already up (the panel swaps in a new one when the first
        // episode opens) gets no didShow. Its anchor joins the window after onAppear, so check on the next turn.
        .onAppear {
            DispatchQueue.main.async { if scroll.anchorIsOnScreen { installScroll() } }
        }
        .onDisappear { scroll.remove() }
        .onReceive(NotificationCenter.default.publisher(for: DialPanelController.didClose)) { _ in scroll.remove() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dial")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { nowPlaying.toggle() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nowPlaying.skip(by: 30)
            case .decrement: nowPlaying.skip(by: -15)
            @unknown default: break
            }
        }
    }

    private func installScroll() {
        scroll.install { [nowPlaying] degrees in nowPlaying.turn(degrees: degrees) }
    }

    // MARK: Drawing

    private var rim: some View {
        Circle().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.15), .white.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1)
    }

    private var ring: some View {
        let diameter = Self.ringRadius * 2
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.18), radius: 1.5)
            ForEach(Array(chapterAngles.enumerated()), id: \.offset) { _, degrees in
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .shadow(color: .black.opacity(0.25), radius: 1)
                    .offset(y: -Self.ringRadius)
                    .rotationEffect(.degrees(degrees))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var chapterAngles: [Double] {
        guard nowPlaying.mode == .podcast, player.episode != nil, let duration else { return [] }
        return nowPlaying.chapters.map { min(1, max(0, $0.start / duration)) * 360 }
    }

    private var centreButton: some View {
        PlayPauseGlyph(isPlaying: nowPlaying.display?.isPlaying ?? false)
            .fill(.primary)
            .frame(width: 18, height: 20)
            .opacity(nowPlaying.display == nil ? 0.35 : 1)
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
                nowPlaying.turn(degrees: Self.rotateSign * (value.rotation - previous).degrees)
            }
            .onEnded { _ in lastRotation = nil }
    }

    /// Dragging round the ring. Drags that start off the ring band (on the centre button, say) don't turn;
    /// one that starts and ends on the centre button is a press that drifted, so it still plays or pauses.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragAngle == nil, !dragIgnored {
                    guard Self.ringBand.contains(distance(of: value.startLocation)) else {
                        dragIgnored = true
                        return
                    }
                    dragAngle = DialGeometry.angle(of: value.startLocation, around: center)
                }
                guard let previous = dragAngle else { return }
                let current = DialGeometry.angle(of: value.location, around: center)
                dragAngle = current
                nowPlaying.turn(degrees: DialGeometry.delta(from: previous, to: current))
            }
            .onEnded { value in
                if dragAngle == nil, distance(of: value.startLocation) <= Self.centreRadius,
                   distance(of: value.location) <= Self.centreRadius {
                    nowPlaying.toggle()
                }
                dragAngle = nil
                dragIgnored = false
            }
    }

    /// A press on the centre plays or pauses; a press on the ring jumps to that point.
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let radius = distance(of: value.location)
                if radius <= Self.centreRadius {
                    nowPlaying.toggle()
                } else if Self.ringBand.contains(radius), let duration {
                    nowPlaying.jump(to: DialGeometry.time(atRingPoint: value.location, center: center,
                                                          duration: duration))
                }
            }
    }

    private func distance(of point: CGPoint) -> CGFloat {
        hypot(point.x - center.x, point.y - center.y)
    }
}

/// Pause bars, or a play triangle, drawn as a path.
struct PlayPauseGlyph: Shape {
    var isPlaying: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isPlaying {
            let bar = rect.width * 0.32
            path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.08, y: rect.minY, width: bar, height: rect.height),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            path.addRoundedRect(in: CGRect(x: rect.maxX - rect.width * 0.08 - bar, y: rect.minY, width: bar, height: rect.height),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
        } else {
            // Nudged right so the triangle looks centred.
            let inset = rect.width * 0.12
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX + inset, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// ⏮ / ⏭ drawn in code: two triangles and a bar.
struct TrackSkipGlyph: Shape {
    var forward: Bool

    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.14
        let half = (rect.width - bar) / 2
        var path = Path()
        func triangle(from x: CGFloat) {
            let tip = forward ? x + half : x
            let base = forward ? x : x + half
            path.move(to: CGPoint(x: base, y: rect.minY))
            path.addLine(to: CGPoint(x: tip, y: rect.midY))
            path.addLine(to: CGPoint(x: base, y: rect.maxY))
            path.closeSubpath()
        }
        if forward {
            triangle(from: rect.minX)
            triangle(from: rect.minX + half * 0.55)
            path.addRect(CGRect(x: rect.maxX - bar, y: rect.minY, width: bar, height: rect.height))
        } else {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: bar, height: rect.height))
            triangle(from: rect.minX + bar + half * 0.45)
            triangle(from: rect.minX + bar)
        }
        return path
    }
}

