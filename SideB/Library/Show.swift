import Foundation
import SwiftData

@Model
final class Show {
    @Attribute(.unique) var feedURL: URL
    var title: String
    var author: String?
    var artworkURL: URL?
    var summary: String?
    var lastUpdated: Date?
    var lastError: String?
    var errorSince: Date?
    /// The feed's ETag and Last-Modified from its last full download.
    var etag: String?
    var lastModified: String?
    @Relationship(deleteRule: .cascade, inverse: \Episode.show) var episodes: [Episode] = []

    init(feedURL: URL, title: String, author: String? = nil, artworkURL: URL? = nil, summary: String? = nil) {
        self.feedURL = feedURL
        self.title = title
        self.author = author
        self.artworkURL = artworkURL
        self.summary = summary
    }
}
