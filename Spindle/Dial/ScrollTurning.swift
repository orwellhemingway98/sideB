import AppKit
import SwiftUI

/// Scrolls as turns of the dial.
enum ScrollTurning {
    /// Degrees of turn for a scroll: scrolling down turns clockwise. Line-based mice step 10 points a line.
    static func degrees(for event: NSEvent) -> Double {
        let points = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        return -Double(points) * DialGeometry.scrollDegreesPerPoint
    }

    /// A scroll turns the disc only when it lands inside the disc's circle, in the disc's own window,
    /// while that window is on screen. `pointInDisc` is in the disc's bounds (0...discSize on each axis).
    static func shouldTurn(eventWindow: NSWindow?, discWindow: NSWindow?, windowVisible: Bool,
                           pointInDisc: CGPoint, discSize: CGFloat) -> Bool {
        guard let eventWindow, eventWindow === discWindow, windowVisible else { return false }
        let radius = discSize / 2
        return hypot(pointInDisc.x - radius, pointInDisc.y - radius) <= radius
    }
}

/// A local scroll-wheel monitor that runs while the pointer is over the disc. It swallows only the
/// scrolls that land on the disc (so the panel doesn't scroll instead) and passes every other one on.
@MainActor
final class ScrollMonitor {
    /// The disc's own view, which gives its window and its frame.
    weak var anchor: NSView?
    private var monitor: Any?

    /// True when the disc is in a window that is showing.
    var anchorIsOnScreen: Bool { anchor?.window?.isVisible == true }

    func install(_ turn: @escaping @MainActor (Double) -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let window = event.window
            let location = event.locationInWindow
            let degrees = ScrollTurning.degrees(for: event)
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let anchor = self?.anchor, let discWindow = anchor.window else { return false }
                guard ScrollTurning.shouldTurn(eventWindow: window, discWindow: discWindow,
                                               windowVisible: discWindow.isVisible,
                                               pointInDisc: anchor.convert(location, from: nil),
                                               discSize: anchor.bounds.width) else { return false }
                turn(degrees)
                return true
            }
            return used ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit {
        remove()
    }
}

/// An invisible view behind the disc that tells the scroll monitor where the disc is.
struct ScrollAnchor: NSViewRepresentable {
    let monitor: ScrollMonitor

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        monitor.anchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        monitor.anchor = nsView
    }

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Where a disc lives: the menu bar panel, or the floating dial.
enum DiscHost {
    case panel, floating

    /// Only the panel's disc follows the panel's show and close notifications.
    var followsPanel: Bool { self == .panel }
}

