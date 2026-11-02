import Foundation

/// What the list window shows for whatever the dial is steering.
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

    var isLoading: Bool {
        if case .musicLoading = self { return true }
        return false
    }

    /// The glass hint on the cover.
    static func hint(mode: PlaybackMode, source: MusicSourceID?, contextKind: MusicContext.Kind?) -> String {
        switch mode {
        case .podcast: return "Episodes \u{2304}"
        case .music:
            if source == .spotify { return "Spotify \u{2304}" }
            return contextKind == .playlist ? "Playlist \u{2304}" : "Album \u{2304}"
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
            if source == .spotify { return "Show song details" }
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
