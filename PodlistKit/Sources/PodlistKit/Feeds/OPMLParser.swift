import Foundation

/// Reads podcast subscriptions from an OPML file (Pocket Casts, Overcast, Apple Podcasts, …).
///
/// Every `outline` with a usable `xmlUrl` counts, at any nesting depth. Overcast's
/// per-episode outlines (`podcastEpisode` / `podcast-episode`) are skipped.
public enum OPMLParser {
    public static func parse(_ data: Data) throws -> [OPMLOutline] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        let finished = parser.parse()

        if delegate.rootIsNotOPML { throw OPMLParserError.notOPML }
        if !finished {
            let message = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw OPMLParserError.malformed(message)
        }
        return delegate.outlines
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var outlines: [OPMLOutline] = []
        var rootIsNotOPML = false
        private var seenRoot = false
        private var seenURLs: Set<String> = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String]
        ) {
            if !seenRoot {
                seenRoot = true
                if elementName.lowercased() != "opml" {
                    rootIsNotOPML = true
                    parser.abortParsing()
                }
                return
            }
            guard elementName.lowercased() == "outline" else { return }
            let attributes = Dictionary(
                attributeDict.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })

            switch attributes["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" {
            case "", "rss", "link": break
            default: return
            }
            guard let feedURL = Self.absoluteWebURL(attributes["xmlurl"]) else { return }
            guard seenURLs.insert(feedURL.absoluteString).inserted else { return }
            outlines.append(OPMLOutline(title: Self.title(text: attributes["text"], title: attributes["title"]), feedURL: feedURL))
        }

        private static func title(text: String?, title: String?) -> String? {
            for candidate in [text, title] {
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty { return trimmed }
            }
            return nil
        }

        private static func absoluteWebURL(_ value: String?) -> URL? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                let url = URL(string: trimmed),
                let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                let host = url.host(percentEncoded: false), !host.isEmpty
            else { return nil }
            return url
        }
    }
}
