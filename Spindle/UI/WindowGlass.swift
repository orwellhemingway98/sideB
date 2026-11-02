import AppKit
import SwiftUI

/// AppKit's window glass behind a SwiftUI view. SwiftUI's own glass only refracts what's inside its window, and
/// Spindle's windows are clear, so it rendered as flat grey; this one sees the desktop and the windows behind,
/// like the list's popover. A tint lets it take the cover's colour.
struct WindowGlass: NSViewRepresentable {
    let cornerRadius: CGFloat
    var tint: NSColor? = nil

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        glass.cornerRadius = cornerRadius
        guard glass.tintColor != tint else { return }
        // A new cover's colour eases in rather than snapping.
        NSAnimationContext.runAnimationGroup { group in
            group.duration = 0.45
            group.allowsImplicitAnimation = true
            glass.tintColor = tint
        }
    }
}
