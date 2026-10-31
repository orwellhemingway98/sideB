import Foundation
import SwiftData

@Model
final class Episode {
    var guid: String
    var show: Show?
    var title: String
    var published: Date?
    /// Position of the episode in the feed it came from; breaks ties between equal dates.
    var feedOrder: Int = 0
    var duration: TimeInterval?
    var enclosureURL: URL
    var enclosureType: String?
    var chaptersURL: URL?
    var inlineChaptersData: Data?
    var summary: String?
    var position: TimeInterval = 0
    var played = false
    /// When it was marked played; downloads are cleaned up a week after.
    var playedAt: Date?
    var localFile: URL?

    init(guid: String, title: String, enclosureURL: URL) {
        self.guid = guid
        self.title = title
        self.enclosureURL = enclosureURL
    }

    var inlineChapters: [Chapter] {
        guard let data = inlineChaptersData else { return [] }
        return (try? JSONDecoder().decode([Chapter].self, from: data)) ?? []
    }

    var playableURL: URL {
        if let file = localFile, FileManager.default.fileExists(atPath: file.path) { return file }
        return enclosureURL
    }
}
