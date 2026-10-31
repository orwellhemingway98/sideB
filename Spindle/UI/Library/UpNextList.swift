import SwiftUI

/// The Up Next queue: drag to reorder, Remove to take one out.
struct UpNextList: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore

    var body: some View {
        Group {
            if library.upNext.isEmpty {
                Placeholder(text: "Up Next is empty. Use \u{201C}+ Up Next\u{201D} on any episode.")
            } else {
                List {
                    ForEach(library.upNext) { episode in
                        HStack {
                            EpisodeRow(episode: episode, model: model, showsShow: true, offersEnqueue: false)
                            Button("Remove") { library.remove(fromUpNext: episode) }
                        }
                    }
                    .onMove { library.moveUpNext(from: $0, to: $1) }
                }
            }
        }
        .navigationTitle("Up Next")
    }
}
