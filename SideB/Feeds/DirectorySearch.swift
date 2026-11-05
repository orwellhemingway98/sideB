import Foundation

struct DirectoryResult: Equatable, Identifiable {
    var id: URL { feedURL }
    let title: String
    let author: String
    let artworkURL: URL?
    let feedURL: URL
}

enum DirectorySearch {
    static func url(for term: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/#")
        let escaped = term.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "term", value: escaped),
        ]
        return components.url!
    }

    private struct Response: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let collectionName: String?
        let artistName: String?
        let artworkUrl600: String?
        let feedUrl: String?
    }

    static func decode(_ data: Data) throws -> [DirectoryResult] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.results.compactMap { item in
            guard let name = item.collectionName,
                  let feed = item.feedUrl.flatMap({ URL(string: $0) }) else { return nil }
            return DirectoryResult(title: name,
                                   author: item.artistName ?? "",
                                   artworkURL: item.artworkUrl600.flatMap { URL(string: $0) },
                                   feedURL: feed)
        }
    }

    static func search(_ term: String, fetcher: HTTPFetching) async throws -> [DirectoryResult] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try decode(try await fetcher.data(from: url(for: trimmed)))
    }
}
