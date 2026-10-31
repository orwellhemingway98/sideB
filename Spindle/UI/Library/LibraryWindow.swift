import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore

    init(model: LibraryViewModel) {
        self.model = model
        self.library = model.library
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(model: model, library: library)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            detail
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .upNext:
            UpNextList(model: model, library: library)
        case .newEpisodes:
            EpisodeList(title: "New Episodes", episodes: library.newEpisodes(), model: model, showsShow: true,
                        empty: "Nothing new. Follow a show to see its episodes here.")
        case .shows:
            ShowGrid(model: model, library: library)
        case .downloaded:
            EpisodeList(title: "Downloaded", episodes: library.downloaded, model: model, showsShow: true,
                        empty: "Download an episode to listen without a connection.")
        case .show:
            if let show = model.selectedShow {
                EpisodeList(title: show.title, episodes: library.episodes(of: show), model: model, showsShow: false,
                            empty: "No episodes yet.")
            } else {
                Placeholder(text: "That show isn't in your library any more.")
            }
        }
    }
}

/// A quiet centred note for empty sections.
struct Placeholder: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Library window: a standard window and sidebar, which macOS 26 draws in Liquid Glass.
@MainActor
final class LibraryWindowController {
    private let window: NSWindow

    init(model: LibraryViewModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
        window.title = "Spindle Library"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: LibraryView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
    }

    func show() {
        // The Library pill lives in a non-activating panel, so Spindle is never the active app here and the
        // cooperative `activate()` is refused: the window would open behind other apps with no keyboard.
        NSApp.forceActivate()
        window.makeKeyAndOrderFront(nil)
    }
}
