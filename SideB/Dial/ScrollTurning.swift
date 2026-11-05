import AppKit
import SwiftUI

/// Scrolls as turns: how far to scrub.
enum ScrollTurning {
    /// Degrees of turn for a scroll: scrolling down turns clockwise. Line-based mice step 10 points a line.
    static func degrees(for event: NSEvent) -> Double {
        let points = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        return -Double(points) * ScrollGeometry.scrollDegreesPerPoint
    }

    /// A scroll scrubs only when it lands on the line, in the line's own window, while that window is on screen.
    static func shouldTurn(eventWindow: NSWindow?, lineWindow: NSWindow?, windowVisible: Bool,
                           pointInLine: CGPoint, lineBounds: CGRect) -> Bool {
        guard let eventWindow, eventWindow === lineWindow, windowVisible else { return false }
        return lineBounds.contains(pointInLine)
    }
}

/// A local scroll-wheel monitor that runs while the pointer is over the line. It swallows only the
/// scrolls that land on the line (so the panel doesn't scroll instead) and passes every other one on.
@MainActor
final class ScrollMonitor {
    /// The line's own view, which gives its window and its frame.
    weak var anchor: NSView?
    private var monitor: Any?

    /// True when the line is in a window that is showing.
    var anchorIsOnScreen: Bool { anchor?.window?.isVisible == true }

    func install(_ turn: @escaping @MainActor (Double) -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let window = event.window
            let location = event.locationInWindow
            let degrees = ScrollTurning.degrees(for: event)
            let used = MainActor.assumeIsolated { () -> Bool in
                guard let anchor = self?.anchor, let lineWindow = anchor.window else { return false }
                guard ScrollTurning.shouldTurn(eventWindow: window, lineWindow: lineWindow,
                                               windowVisible: lineWindow.isVisible,
                                               pointInLine: anchor.convert(location, from: nil),
                                               lineBounds: anchor.bounds) else { return false }
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

/// An invisible view behind the line that tells the scroll monitor where the line is.
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

/// Which window a progress line lives in: the panel, or the mini player.
enum LineHost {
    case panel, floating

    /// Only the panel's line follows the panel's show and close notifications.
    var followsPanel: Bool { self == .panel }
}

