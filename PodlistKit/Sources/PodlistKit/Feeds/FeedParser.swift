import Foundation
import os

/// Podcast RSS parser on Foundation's `XMLParser` (ADR 0003).
///
/// Built for messy real-world feeds: namespaces are matched by URI (case-insensitive, prefix does not
/// matter), unknown elements are ignored, missing or broken values become `nil`, and items without a valid
/// enclosure URL are skipped. External entities are never resolved. Pure and `Sendable`-clean: callable from any actor.
public enum FeedParser {
    public static func parse(_ data: Data) throws -> ParsedFeed {
        let parser = XMLParser(data: prepare(data))
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        let delegate = FeedXMLDelegate()
        parser.delegate = delegate

        let succeeded = parser.parse()
        if delegate.rootIsNotRSS { throw FeedParserError.notAFeed }
        guard succeeded else {
            throw FeedParserError.malformed(parser.parserError?.localizedDescription ?? "Unknown XML error")
        }
        guard delegate.sawChannel else { throw FeedParserError.notAFeed }
        return delegate.makeFeed()
    }

    /// Cleans up byte-level junk that makes libxml2 reject otherwise usable feeds: a byte order mark and
    /// whitespace before the XML declaration, and control characters that are illegal in XML 1.0.
    /// UTF-16/32 input is left untouched.
    static func prepare(_ data: Data) -> Data {
        guard data.count >= 2, data[data.startIndex] != 0, data[data.startIndex + 1] != 0,
            !(data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xFE),
            !(data[data.startIndex] == 0xFE && data[data.startIndex + 1] == 0xFF)
        else { return data }

        func isIllegal(_ byte: UInt8) -> Bool { byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D }
        func isLeadingJunk(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }

        var start = data.startIndex
        if data.count >= 3, data[start] == 0xEF, data[start + 1] == 0xBB, data[start + 2] == 0xBF { start += 3 }
        while start < data.endIndex, isLeadingJunk(data[start]) { start += 1 }

        let body = data[start...]
        guard body.contains(where: isIllegal) else { return start == data.startIndex ? data : Data(body) }
        return Data(body.filter { !isIllegal($0) })
    }
}

// MARK: - Namespaces

enum FeedNamespace {
    case rss, itunes, podcast, psc, content, other

    /// Matches by URI, ignoring case, scheme and a trailing slash. Elements with an undeclared prefix
    /// (a common feed bug) fall back to the conventional prefix.
    init(uri: String?, qualifiedName: String) {
        guard let uri, !uri.isEmpty else {
            guard let colon = qualifiedName.firstIndex(of: ":") else {
                self = .rss
                return
            }
            switch qualifiedName[..<colon].lowercased() {
            case "itunes": self = .itunes
            case "podcast": self = .podcast
            case "psc": self = .psc
            case "content": self = .content
            default: self = .other
            }
            return
        }
        var normalized = uri.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where normalized.hasPrefix(scheme) {
            normalized.removeFirst(scheme.count)
        }
        if normalized.hasSuffix("/") { normalized.removeLast() }
        switch normalized {
        case "www.itunes.com/dtds/podcast-1.0.dtd": self = .itunes
        case "podcastindex.org/namespace/1.0": self = .podcast
        case "podlove.org/simple-chapters": self = .psc
        case "purl.org/rss/1.0/modules/content": self = .content
        case "backend.userland.com/rss2": self = .rss
        default: self = .other
        }
    }
}

// MARK: - XML delegate

/// Only used inside `FeedParser.parse`; never leaves the call.
final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private struct Element {
        let namespace: FeedNamespace
        let name: String  // local name, lowercased

        func isElement(_ namespace: FeedNamespace, _ name: String) -> Bool {
            self.namespace == namespace && self.name == name
        }
    }

    private enum Field {
        case title, link, description, author, managingEditor, guid, pubDate, contentEncoded
        case itunesTitle, itunesAuthor, itunesSummary, itunesSubtitle, newFeedURL, imageURL, duration, episode, season
    }

    private struct ChannelDraft {
        var title: String?
        var link: String?
        var description: String?
        var author: String?
        var managingEditor: String?
        var itunesAuthor: String?
        var itunesSummary: String?
        var newFeedURL: String?
        var imageURL: String?
        var artworkHref: String?
        var categories: [String] = []
    }

    private struct ItemDraft {
        var title: String?
        var itunesTitle: String?
        var guid: String?
        var pubDate: String?
        var description: String?
        var contentEncoded: String?
        var itunesSummary: String?
        var itunesSubtitle: String?
        var duration: String?
        var episode: String?
        var season: String?
        var enclosureURL: URL?
        var enclosureLength: String?
        var enclosureType: String?
        var imageHref: String?
        var chaptersURL: String?
        var chapters: [Chapter] = []
    }

    private(set) var rootIsNotRSS = false
    private(set) var sawChannel = false

    private var path: [Element] = []
    private var channel = ChannelDraft()
    private var item: ItemDraft?
    private var episodes: [ParsedEpisode] = []

    private var captureField: Field?
    private var captureDepth = 0
    private var captureInItem = false
    private var buffer = ""

    func makeFeed() -> ParsedFeed {
        ParsedFeed(
            title: channel.title ?? "",
            author: channel.itunesAuthor ?? channel.author ?? channel.managingEditor,
            summary: channel.itunesSummary ?? channel.description,
            artworkURL: FeedParser.parseWebURL(channel.artworkHref) ?? FeedParser.parseWebURL(channel.imageURL),
            link: FeedParser.parseWebURL(channel.link),
            categories: channel.categories,
            newFeedURL: FeedParser.parseWebURL(channel.newFeedURL),
            episodes: episodes)
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let qualified = qName ?? elementName
        let localName = qualified.split(separator: ":").last.map(String.init) ?? qualified
        let element = Element(
            namespace: FeedNamespace(uri: namespaceURI, qualifiedName: qualified), name: localName.lowercased())
        path.append(element)
        let depth = path.count

        if depth == 1 {
            if !element.isElement(.rss, "rss") {
                rootIsNotRSS = true
                parser.abortParsing()
            }
            return
        }
        if depth == 2 {
            if element.isElement(.rss, "channel") { sawChannel = true }
            return
        }
        guard path[1].isElement(.rss, "channel") else { return }

        if depth == 3, element.isElement(.rss, "item") {
            item = ItemDraft()
            return
        }
        if path[2].isElement(.rss, "item") {
            guard item != nil else { return }
            startItemChild(element, depth: depth, attributes: attributeDict)
        } else {
            startChannelChild(element, depth: depth, attributes: attributeDict)
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        let depth = path.count
        if captureField != nil, captureDepth == depth { finishCapture() }
        if depth == 3, path[2].isElement(.rss, "item"), path[1].isElement(.rss, "channel") { finishItem() }
        path.removeLast()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureField != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if captureField != nil { buffer += String(decoding: CDATABlock, as: UTF8.self) }
    }

    // MARK: Channel

    private func startChannelChild(_ element: Element, depth: Int, attributes: [String: String]) {
        if element.isElement(.itunes, "category") {
            if let text = Self.trimmed(Self.attribute("text", in: attributes)), !channel.categories.contains(text) {
                channel.categories.append(text)
            }
            return
        }
        switch depth {
        case 3:
            if element.isElement(.itunes, "image") {
                setChannel(\.artworkHref, Self.trimmed(Self.attribute("href", in: attributes)))
                return
            }
            let field: Field? =
                switch (element.namespace, element.name) {
                case (.rss, "title"): .title
                case (.rss, "link"): .link
                case (.rss, "description"): .description
                case (.rss, "author"): .author
                case (.rss, "managingeditor"): .managingEditor
                case (.itunes, "author"): .itunesAuthor
                case (.itunes, "summary"): .itunesSummary
                case (.itunes, "new-feed-url"): .newFeedURL
                default: nil
                }
            if let field { beginCapture(field, depth: depth, inItem: false) }
        case 4:
            if path[2].isElement(.rss, "image"), element.isElement(.rss, "url") {
                beginCapture(.imageURL, depth: depth, inItem: false)
            }
        default:
            break
        }
    }

    // MARK: Items

    private func startItemChild(_ element: Element, depth: Int, attributes: [String: String]) {
        switch depth {
        case 4:
            switch (element.namespace, element.name) {
            case (.rss, "enclosure"):
                guard item?.enclosureURL == nil, let url = FeedParser.parseWebURL(Self.attribute("url", in: attributes)) else { return }
                item?.enclosureURL = url
                item?.enclosureLength = Self.attribute("length", in: attributes)
                item?.enclosureType = Self.attribute("type", in: attributes)
            case (.itunes, "image"):
                setItem(\.imageHref, Self.trimmed(Self.attribute("href", in: attributes)))
            case (.podcast, "chapters"):
                setItem(\.chaptersURL, Self.trimmed(Self.attribute("url", in: attributes)))
            default:
                let field: Field? =
                    switch (element.namespace, element.name) {
                    case (.rss, "title"): .title
                    case (.rss, "guid"): .guid
                    case (.rss, "pubdate"): .pubDate
                    case (.rss, "description"): .description
                    case (.content, "encoded"): .contentEncoded
                    case (.itunes, "title"): .itunesTitle
                    case (.itunes, "summary"): .itunesSummary
                    case (.itunes, "subtitle"): .itunesSubtitle
                    case (.itunes, "duration"): .duration
                    case (.itunes, "episode"): .episode
                    case (.itunes, "season"): .season
                    default: nil
                    }
                if let field { beginCapture(field, depth: depth, inItem: true) }
            }
        case 5:
            guard path[3].isElement(.psc, "chapters"), element.isElement(.psc, "chapter"),
                let start = Self.attribute("start", in: attributes).flatMap(FeedParser.parseClock)
            else { return }
            item?.chapters.append(
                Chapter(
                    start: start, end: nil, title: Self.trimmed(Self.attribute("title", in: attributes)) ?? "",
                    imageURL: FeedParser.parseWebURL(Self.attribute("image", in: attributes)),
                    linkURL: FeedParser.parseWebURL(Self.attribute("href", in: attributes))))
        default:
            break
        }
    }

    private func finishItem() {
        defer { item = nil }
        guard let draft = item, let audioURL = draft.enclosureURL else { return }

        // Sorted by start (stable for equal starts); each chapter ends where the next begins.
        var chapters = draft.chapters.enumerated().sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }.map(\.element)
        for index in chapters.indices.dropLast() { chapters[index].end = chapters[index + 1].start }

        let fileSize = draft.enclosureLength.flatMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        episodes.append(
            ParsedEpisode(
                guid: draft.guid,
                // ASSUMPTION: `title` is non-optional; fall back to `itunes:title`, then to an empty string.
                title: draft.title ?? draft.itunesTitle ?? "",
                showNotes: draft.contentEncoded ?? draft.description ?? draft.itunesSummary,
                subtitle: draft.itunesSubtitle.map(HTMLText.plainText(fromHTML:)).flatMap(Self.trimmed),
                publishedAt: draft.pubDate.flatMap(FeedParser.parseDate),
                duration: draft.duration.flatMap(FeedParser.parseDuration),
                audioURL: audioURL,
                fileSize: fileSize.flatMap { $0 > 0 ? $0 : nil },
                mimeType: Self.trimmed(draft.enclosureType),
                imageURL: FeedParser.parseWebURL(draft.imageHref),
                episodeNumber: FeedParser.parseInt(draft.episode),
                seasonNumber: FeedParser.parseInt(draft.season),
                chaptersURL: FeedParser.parseWebURL(draft.chaptersURL),
                chapters: chapters))
    }

    // MARK: Text capture

    private func beginCapture(_ field: Field, depth: Int, inItem: Bool) {
        guard captureField == nil else { return }
        captureField = field
        captureDepth = depth
        captureInItem = inItem
        buffer = ""
    }

    /// Stores the trimmed text in the current scope.
    private func finishCapture() {
        defer {
            captureField = nil
            buffer = ""
        }
        guard let field = captureField, let text = Self.trimmed(buffer) else { return }
        if captureInItem {
            switch field {
            case .title: setItem(\.title, text)
            case .guid: setItem(\.guid, text)
            case .pubDate: setItem(\.pubDate, text)
            case .description: setItem(\.description, text)
            case .contentEncoded: setItem(\.contentEncoded, text)
            case .itunesTitle: setItem(\.itunesTitle, text)
            case .itunesSummary: setItem(\.itunesSummary, text)
            case .itunesSubtitle: setItem(\.itunesSubtitle, text)
            case .duration: setItem(\.duration, text)
            case .episode: setItem(\.episode, text)
            case .season: setItem(\.season, text)
            default: break
            }
        } else {
            switch field {
            case .title: setChannel(\.title, text)
            case .link: setChannel(\.link, text)
            case .description: setChannel(\.description, text)
            case .author: setChannel(\.author, text)
            case .managingEditor: setChannel(\.managingEditor, text)
            case .itunesAuthor: setChannel(\.itunesAuthor, text)
            case .itunesSummary: setChannel(\.itunesSummary, text)
            case .newFeedURL: setChannel(\.newFeedURL, text)
            case .imageURL: setChannel(\.imageURL, text)
            default: break
            }
        }
    }

    /// The first non-empty value of a field wins.
    private func setItem(_ keyPath: WritableKeyPath<ItemDraft, String?>, _ value: String?) {
        guard let value, item != nil, item?[keyPath: keyPath] == nil else { return }
        item?[keyPath: keyPath] = value
    }

    private func setChannel(_ keyPath: WritableKeyPath<ChannelDraft, String?>, _ value: String?) {
        guard let value, channel[keyPath: keyPath] == nil else { return }
        channel[keyPath: keyPath] = value
    }

    // MARK: Helpers

    private static func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Attribute lookup that tolerates odd casing (`URL=`, `Href=`).
    private static func attribute(_ name: String, in attributes: [String: String]) -> String? {
        if let value = attributes[name] { return value }
        return attributes.first { $0.key.lowercased() == name }?.value
    }
}
