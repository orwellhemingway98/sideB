import AVFoundation
import Foundation

enum ChapterLoader {
    private struct Document: Decodable {
        struct Entry: Decodable {
            let startTime: TimeInterval?
            let title: String?
        }
        let chapters: [Entry]?
    }

    static func decodeJSON(_ data: Data) throws -> [Chapter] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        return (document.chapters ?? [])
            .compactMap { entry -> Chapter? in
                guard let start = entry.startTime, let title = entry.title, !title.isEmpty else { return nil }
                return Chapter(start: start, title: title)
            }
            .sorted { $0.start < $1.start }
    }

    /// Chapters JSON, then the feed's inline Podlove chapters, then the audio file.
    /// A source that fails or yields nothing falls through to the next.
    static func load(chaptersURL: URL?, inline: [Chapter], audioChapters: () async -> [Chapter],
                     fetcher: HTTPFetching) async -> [Chapter] {
        if let chaptersURL,
           let data = try? await fetcher.data(from: chaptersURL),
           let chapters = try? decodeJSON(data), !chapters.isEmpty {
            return chapters
        }
        if !inline.isEmpty { return inline }
        return await audioChapters()
    }
}

enum AudioFileChapters {
    static func read(from url: URL) async -> [Chapter] {
        do {
            let asset = AVURLAsset(url: url)
            let locales = try await asset.load(.availableChapterLocales)
            let languages = locales.map(\.identifier)
            let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: languages)
            var chapters: [Chapter] = []
            for group in groups {
                let items = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle)
                guard let item = items.first, let title = try await item.load(.stringValue), !title.isEmpty else { continue }
                chapters.append(Chapter(start: group.timeRange.start.seconds, title: title))
            }
            return chapters.sorted { $0.start < $1.start }
        } catch {
            return []
        }
    }
}
