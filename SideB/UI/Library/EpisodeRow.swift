import SwiftUI

/// A titled list of episode rows, or a note when there are none.
struct EpisodeList: View {
    let title: String
    let episodes: [Episode]
    @ObservedObject var model: LibraryViewModel
    /// Whether rows name their show (mixed lists) or not (one show's list).
    let showsShow: Bool
    let empty: String

    var body: some View {
        Group {
            if episodes.isEmpty {
                Placeholder(text: empty)
            } else {
                List(episodes) { episode in
                    EpisodeRow(episode: episode, model: model, showsShow: showsShow)
                }
            }
        }
        .navigationTitle(title)
    }
}

struct EpisodeRow: View {
    let episode: Episode
    @ObservedObject var model: LibraryViewModel
    let showsShow: Bool
    /// Up Next's own rows don't offer "+ Up Next".
    var offersEnqueue = true

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(cache: model.artwork, url: episode.show?.artworkURL, seed: episode.show?.title ?? episode.title,
                        size: 40, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title).lineLimit(2)
                Text(Self.details(of: episode, showsShow: showsShow))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { model.nowPlaying.play(episode) } label: {
                Image(systemName: "play.fill").font(.system(size: 11))
            }
            .help("Play")
            if offersEnqueue { Button("+ Up Next") { model.nowPlaying.player.enqueue(episode) } }
            if let downloads = model.downloads { DownloadButton(episode: episode, downloads: downloads) }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if episode.played {
                Button("Mark as Unplayed") { model.library.markUnplayed(episode) }
            } else {
                Button("Mark as Played") { model.library.markPlayed(episode) }
            }
            if let downloads = model.downloads, downloads.state(of: episode) == .downloaded {
                Button("Remove Download") { downloads.removeDownload(episode) }
            }
        }
    }

    /// Show · date · duration · time left when part-played · Downloaded / Unavailable.
    static func details(of episode: Episode, showsShow: Bool) -> String {
        var parts: [String] = []
        if showsShow, let show = episode.show?.title { parts.append(show) }
        if let published = episode.published {
            parts.append(published.formatted(date: .abbreviated, time: .omitted))
        }
        if let duration = episode.duration {
            parts.append(TimeFormat.clock(duration))
            if !episode.played, episode.position > 0 {
                parts.append("\(TimeFormat.clock(max(0, duration - episode.position))) left")
            }
        }
        if episode.unavailable { parts.append("Unavailable") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

private struct DownloadButton: View {
    let episode: Episode
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        switch downloads.state(of: episode) {
        case .none:
            Button("Download") { downloads.download(episode) }
        case .downloading(let fraction):
            Button("Downloading \(Int((fraction * 100).rounded()))%") { downloads.cancel(episode) }
                .help("Click to cancel")
        case .downloaded:
            Text("Downloaded").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Button("Retry download") { downloads.download(episode) }
                .help(message)
        }
    }
}
