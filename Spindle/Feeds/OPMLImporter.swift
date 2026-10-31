import Foundation

enum OPMLError: Error, Equatable {
    case notOPML
}

struct ImportSummary: Equatable {
    var followed = 0
    var alreadyFollowed = 0
    var failed = 0
}

/// Reads the list of shows another podcast app exported: every outline with a feed link, at any depth.
enum OPMLImporter {
    static func feedURLs(from data: Data) throws -> [URL] {
        let parser = XMLParser(data: strippingLeadingNoise(data))
        let delegate = OPMLDelegate()
        parser.delegate = delegate
        guard parser.parse(), delegate.sawOPML else { throw OPMLError.notOPML }
        return delegate.urls
    }
}

private final class OPMLDelegate: NSObject, XMLParserDelegate {
    private(set) var sawOPML = false
    private(set) var urls: [URL] = []
    private var seen: Set<String> = []
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if depth == 1 {
            sawOPML = name.lowercased() == "opml"
            if !sawOPML { parser.abortParsing() }
            return
        }
        guard name.lowercased() == "outline",
              let raw = attributes.first(where: { $0.key.lowercased() == "xmlurl" })?.value,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              seen.insert(url.absoluteString).inserted else { return }
        urls.append(url)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
    }
}
