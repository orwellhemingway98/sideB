import SwiftUI

/// Every followed show as a cover; clicking one opens its episodes.
struct ShowGrid: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var library: LibraryStore

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 18)]

    var body: some View {
        Group {
            if library.shows.isEmpty {
                Placeholder(text: "Search for a show, paste a feed link, or import an OPML file.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(library.shows) { show in
                            Button { model.section = .show(show.persistentModelID) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(cache: model.artwork, url: show.artworkURL, seed: show.title,
                                                size: 120, cornerRadius: 10)
                                    Text(show.title)
                                        .font(.callout)
                                        .lineLimit(2)
                                        .frame(width: 120, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .navigationTitle("Shows")
    }
}
