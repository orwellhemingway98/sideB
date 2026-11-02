import AppKit
import SwiftUI

/// AppKit's window glass behind a SwiftUI view. SwiftUI's own glass only refracts what's inside its window, and
/// Spindle's windows are clear, so it rendered as flat grey; this one sees the desktop and the windows behind,
/// like the list's popover.
struct WindowGlass: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = cornerRadius
    }
}
