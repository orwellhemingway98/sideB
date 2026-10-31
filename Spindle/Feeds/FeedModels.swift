import Foundation

struct Chapter: Codable, Equatable, Sendable {
    let start: TimeInterval
    let title: String
}

struct ParsedFeed: Equatable, Sendable {
    let title: String
    let author: String?
    let artworkURL: URL?
    let summary: String?
    let episodes: [ParsedEpisode]
}

struct ParsedEpisode: Equatable, Sendable {
    let guid: String
    let title: String
    let published: Date?
    let duration: TimeInterval?
    let enclosureURL: URL
    let enclosureType: String?
    let chaptersURL: URL?
    let inlineChapters: [Chapter]
    let summary: String?
}

enum FeedError: Error, Equatable {
    case notAFeed
}
