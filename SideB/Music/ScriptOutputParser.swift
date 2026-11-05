import Foundation

/// Parses the single line our AppleScripts return:
/// `state, volume[, trackID, title, artist, album, duration, position, index, count]`
/// joined by ASCII 31 (unit separator), which can't appear in track metadata.
enum ScriptOutputParser {
    static let separator: Character = "\u{1F}"

    static func parse(_ output: String, source: MusicSourceID, durationIsMilliseconds: Bool) -> MusicSnapshot? {
        // AppleScript renders absent values (ads, podcasts, streams) as "missing value".
        let fields = output.split(separator: separator, omittingEmptySubsequences: false)
            .map { $0 == "missing value" ? "" : String($0) }
        guard fields.count == 2 || fields.count == 10,
              let state = state(fields[0]),
              let volume = number(fields[1]).map({ Int($0.rounded()) }) else { return nil }
        guard fields.count == 10 else {
            return MusicSnapshot(state: state, track: nil, volume: volume)
        }
        let duration = number(fields[6]) ?? 0
        let track = MusicTrack(
            trackID: fields[2],
            title: fields[3],
            artist: fields[4],
            album: fields[5],
            duration: durationIsMilliseconds ? duration / 1000 : duration,
            position: number(fields[7]) ?? 0,
            index: Int(fields[8]),
            count: Int(fields[9]),
            source: source)
        return MusicSnapshot(state: state, track: track, volume: volume)
    }

    private static func state(_ raw: String) -> MusicPlayerState? {
        switch raw {
        case "playing", "fast forwarding", "rewinding": return .playing
        case "paused": return .paused
        case "stopped": return .stopped
        default: return nil
        }
    }

    /// AppleScript formats reals with the user's locale, so accept "," as the decimal mark.
    private static func number(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
