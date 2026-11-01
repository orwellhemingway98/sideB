import Foundation

/// A song in the album or playlist being listened to.
struct ContextTrack: Equatable, Identifiable {
    let id: String
    let disc: Int
    let number: Int
    let title: String
    let artist: String
    let duration: Double
}

/// What a Music song is playing from: one of your playlists, or its album.
struct MusicContext: Equatable {
    enum Kind: Equatable { case album, playlist }

    let kind: Kind
    /// "playlist:<persistent ID>" or "album:<album>|<album artist>".
    let id: String
    let title: String
    /// At most `MusicContextParser.cap`.
    let tracks: [ContextTrack]
    /// How many there are before the cap.
    let totalCount: Int
}

/// Parses the context script's output: a header record "kind␟id␟title␟totalCount", then one record per track
/// "id␟disc␟number␟title␟artist␟duration". Records are separated by ASCII 30 and fields by ASCII 31,
/// neither of which can appear in Music's metadata.
enum MusicContextParser {
    static let cap = 500
    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"

    static func parse(_ output: String) -> MusicContext? {
        let records = output.split(separator: recordSeparator, omittingEmptySubsequences: false)
        guard let header = records.first?.split(separator: fieldSeparator, omittingEmptySubsequences: false),
              header.count == 4 else { return nil }
        let kind: MusicContext.Kind
        switch header[0] {
        case "album": kind = .album
        case "playlist": kind = .playlist
        default: return nil
        }
        var tracks: [ContextTrack] = records.dropFirst().compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, !fields[0].isEmpty else { return nil }
            return ContextTrack(id: fields[0], disc: Int(fields[1]) ?? 0, number: Int(fields[2]) ?? 0,
                                title: fields[3], artist: fields[4], duration: number(fields[5]) ?? 0)
        }
        if kind == .album {
            tracks.sort { ($0.disc, $0.number) < ($1.disc, $1.number) }
        }
        let total = Int(header[3]) ?? tracks.count
        return MusicContext(kind: kind, id: String(header[1]), title: String(header[2]),
                            tracks: Array(tracks.prefix(cap)), totalCount: max(total, min(tracks.count, cap)))
    }

    /// AppleScript writes decimals in the system's locale ("200,5" in Portuguese).
    private static func number(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
