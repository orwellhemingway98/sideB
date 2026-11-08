import Foundation

/// What the list window shows for whatever sideB is steering.
enum ListContent {
    case podcast(episodes: [Episode], current: Episode, chapters: [Chapter], currentChapter: Chapter?, description: String)
    case music(MusicContext, currentTrackID: String)
    case musicLoading(trackID: String)
    /// "Nothing to list for this song." or "Couldn't read the album from Music."
    case musicMessage(trackID: String, text: String)
    case spotify(MusicTrack)
    case nothing

    static let nothingToList = "Nothing to list for this song."
    static let couldNotRead = "Couldn't read the album from Music."
    static let couldNotReadSpotify = "Couldn't read the album from Spotify."
    static let noDescription = "No description."

    /// What the list is about. The window closes when this changes to something else; loading doesn't count.
    var identity: String? {
        switch self {
        case .podcast(_, let current, _, _, _):
            return current.show?.feedURL.absoluteString ?? "episode:" + current.guid
        case .music(let context, _): return context.id
        case .musicLoading(let trackID): return "loading:" + trackID
        case .musicMessage(let trackID, _): return "song:" + trackID
        case .spotify(let track): return "spotify:" + track.album
        case .nothing: return nil
        }
    }

    /// A read that failed, as opposed to an album with nothing in it: worth trying again.
    var canTryAgain: Bool {
        guard case .musicMessage(_, let text) = self else { return false }
        return text == Self.couldNotRead || text == Self.couldNotReadSpotify
    }

    /// What VoiceOver calls the back of the cover: what it lists.
    var spokenTitle: String {
        switch self {
        case .music(let context, _): return (context.kind == .playlist ? "Playlist: " : "Album: ") + context.title
        case .podcast(_, let current, _, _, _): return current.show.map { "Episodes of \($0.title)" } ?? "Episodes"
        default: return "List"
        }
    }

    var isLoading: Bool {
        if case .musicLoading = self { return true }
        return false
    }

    /// The count at the foot of a song list: "11 songs", or "500 of 812 songs" when only some could be read.
    static func countLine(shown: Int, total: Int) -> String {
        let songs = "\(total) song\(total == 1 ? "" : "s")"
        return shown < total ? "\(shown) of \(songs)" : songs
    }

    /// The podcast list's second tab: an episode without chapters only has its notes to show.
    static func secondTabTitle(hasChapters: Bool) -> String {
        hasChapters ? "Chapters" : "Notes"
    }

    /// The glass hint's word on the cover; the turn mark is drawn after it.
    static func hint(mode: PlaybackMode, source: MusicSourceID?, contextKind: MusicContext.Kind?) -> String {
        switch mode {
        case .podcast: return "Episodes"
        case .music:
            // Signed out of Spotify, there is no list, only the song's details. The line under the title already
            // says Spotify.
            if source == .spotify, contextKind == nil { return "Details" }
            return contextKind == .playlist ? "Playlist" : "Album"
        }
    }

    /// "31 Oct" this year, "30 Dec 2025" before it.
    static func episodeDate(_ date: Date, now: Date = Date(), locale: Locale = .current,
                            calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    /// What VoiceOver says for the cover: the hint without its arrow glyph, as an action.
    static func spokenHint(mode: PlaybackMode, source: MusicSourceID?, contextKind: MusicContext.Kind?) -> String {
        switch mode {
        case .podcast: return "Show episodes"
        case .music:
            if source == .spotify, contextKind == nil { return "Show song details" }
            return contextKind == .playlist ? "Show playlist" : "Show album"
        }
    }

    /// An episode description as plain text: tags stripped, common entities decoded, whitespace collapsed.
    static func plainText(fromHTML html: String?) -> String {
        guard var text = html else { return noDescription }
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&#39;", "'"), ("&apos;", "'"), ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
                                    ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&mdash;", "\u{2014}"),
                                    ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? noDescription : text
    }
}
