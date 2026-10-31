import Foundation

enum FeedParser {
    static func parse(_ data: Data) throws -> ParsedFeed {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        let delegate = FeedXMLDelegate()
        parser.delegate = delegate
        guard parser.parse(), delegate.sawRSS else { throw FeedError.notAFeed }
        return delegate.feed()
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private static let itunes = "http://www.itunes.com/dtds/podcast-1.0.dtd"
    private static let podcast = "https://podcastindex.org/namespace/1.0"
    private static let psc = "http://podlove.org/simple-chapters"

    private struct ItemDraft {
        var title = ""
        var guid = ""
        var published: Date?
        var duration: TimeInterval?
        var enclosureURL: URL?
        var enclosureType: String?
        var chaptersURL: URL?
        var chapters: [Chapter] = []
        var description = ""
        var itunesSummary = ""
    }

    private(set) var sawRSS = false
    private var path: [String] = []
    private var text = ""

    private var title = ""
    private var author = ""
    private var itunesImage: URL?
    private var imageURL: URL?
    private var channelDescription = ""
    private var channelSummary = ""
    private var item: ItemDraft?
    private var episodes: [ParsedEpisode] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func feed() -> ParsedFeed {
        ParsedFeed(title: title, author: nonEmpty(author), artworkURL: itunesImage ?? imageURL,
                   summary: nonEmpty(channelDescription) ?? nonEmpty(channelSummary), episodes: episodes)
    }

    private func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if path.isEmpty { sawRSS = (name == "rss") && namespaceURI.map { $0.isEmpty } ?? true }
        path.append(name)
        text = ""
        let ns = namespaceURI ?? ""
        let inItem = item != nil
        switch (ns, name) {
        case ("", "item") where path.count == 3:
            item = ItemDraft()
        case ("", "enclosure") where inItem:
            if let url = attributes["url"].flatMap({ URL(string: $0) }) {
                item?.enclosureURL = url
                item?.enclosureType = attributes["type"]
            }
        case (Self.podcast, "chapters") where inItem:
            item?.chaptersURL = attributes["url"].flatMap { URL(string: $0) }
        case (Self.psc, "chapter") where inItem:
            if let start = attributes["start"].flatMap(DurationParser.seconds) {
                item?.chapters.append(Chapter(start: start, title: attributes["title"] ?? ""))
            }
        case (Self.itunes, "image") where !inItem && path.count == 3:
            itunesImage = attributes["href"].flatMap { URL(string: $0) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { path.removeLast() }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = namespaceURI ?? ""
        let parent = path.count >= 2 ? path[path.count - 2] : ""
        if item != nil {
            endItemChild(name: name, ns: ns, value: value)
        } else if path.count == 3 {   // rss > channel > child
            switch (ns, name) {
            case ("", "title"): title = value
            case ("", "description"): channelDescription = value
            case (Self.itunes, "summary"): channelSummary = value
            case (Self.itunes, "author"): author = value
            default: break
            }
        } else if path.count == 4, ns.isEmpty, name == "url", parent == "image" {
            imageURL = URL(string: value)
        }
        text = ""
    }

    private func endItemChild(name: String, ns: String, value: String) {
        if path.count == 3, ns.isEmpty, name == "item" {
            finishItem()
        } else if path.count == 4 {   // rss > channel > item > child
            switch (ns, name) {
            case ("", "title"): item?.title = value
            case ("", "guid"): item?.guid = value
            case ("", "pubDate"): item?.published = Self.dateFormatter.date(from: value)
            case ("", "description"): item?.description = value
            case (Self.itunes, "summary"): item?.itunesSummary = value
            case (Self.itunes, "duration"): item?.duration = DurationParser.seconds(value)
            default: break
            }
        }
    }

    private func finishItem() {
        defer { item = nil }
        guard let draft = item, let url = draft.enclosureURL else { return }
        episodes.append(ParsedEpisode(
            guid: draft.guid.isEmpty ? url.absoluteString : draft.guid,
            title: draft.title, published: draft.published, duration: draft.duration,
            enclosureURL: url, enclosureType: draft.enclosureType, chaptersURL: draft.chaptersURL,
            inlineChapters: draft.chapters,
            summary: nonEmpty(draft.description) ?? nonEmpty(draft.itunesSummary)))
    }
}
