import AppKit
import SwiftUI

/// Whether the dial is popped out of the menu bar, remembered across launches.
final class DialPlacement {
    private static let key = "dialPoppedOut"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isPoppedOut: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

/// The disc on its own: a borderless glass dial above other windows, dragged by the bar beneath it
/// (dragging on the disc turns it). Its position is remembered; "Put Back" returns it to the menu bar.
@MainActor
final class FloatingDialController {
    static let autosaveName = "SpindleFloatingDial"
    private static let size = NSSize(width: 170, height: 196)

    private let panel: NSPanel
    private let placement: DialPlacement
    private let onPutBack: () -> Void

    init(nowPlaying: NowPlaying, placement: DialPlacement, onPutBack: @escaping () -> Void,
         onLibrary: @escaping () -> Void) {
        self.placement = placement
        self.onPutBack = onPutBack
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let root = FloatingDialView(nowPlaying: nowPlaying,
                                    onPutBack: { [weak self] in self?.putBack() },
                                    onLibrary: onLibrary)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
        if !panel.setFrameUsingName(Self.autosaveName), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - Self.size.width / 2, y: screen.midY - Self.size.height / 2))
        }
        panel.setFrameAutosaveName(Self.autosaveName)
    }

    var isShown: Bool { panel.isVisible }

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
    let nowPlaying: NowPlaying
    let onPutBack: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            DiscView(nowPlaying: nowPlaying)
                .padding(10)
                .glassEffect(.regular, in: Circle())
            GrabBar()
                .frame(width: 36, height: 6)
                .glassEffect(.regular, in: Capsule())
                .help("Drag to move")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Put Back", action: onPutBack)
            Button("Open Library\u{2026}", action: onLibrary)
            Divider()
            Button("Quit Spindle") { NSApp.terminate(nil) }
        }
    }
}

/// Dragging this moves the floating dial's window.
private struct GrabBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
