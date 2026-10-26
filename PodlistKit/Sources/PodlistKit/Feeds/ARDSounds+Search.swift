import Foundation

extension ARDSounds {
    /// One result list from both directories (concept §4.13).
    ///
    /// An ARD show that iTunes lists too is dropped in favour of the iTunes result (the
    /// broadcaster's official feed, with categories): same feed URL, same title, or a title
    /// that starts like the other one when the iTunes author names the same broadcaster
    /// ("Hoyzer - Verrat am Fußball | rbb Sport" by ARD). An ARD show with its own feed becomes
    /// a normal feed result; only shows without one are backed by ARD.
    ///
    /// Order: by rank, taking turns, iTunes first; titles that are exactly the search term move
    /// to the front.
    public static func merge(iTunes: [PodcastSearchResult], ard: [Show], term: String) -> [PodcastSearchResult] {
        let feeds = Set(iTunes.map { feedKey($0.feedURL) })
        let fromARD = ard.filter { show in
            !(show.feedURL.map { feeds.contains(feedKey($0)) } ?? false)
                && !iTunes.contains { isSameShow(show, as: $0) }
        }
        .map { show in
            PodcastSearchResult(
                id: id(of: show.urn), title: show.title, author: show.broadcaster,
                feedURL: show.feedURL ?? showURL(show.urn), artworkURL: show.artworkURL, genres: [])
        }

        var merged: [PodcastSearchResult] = []
        var seenFeeds: Set<String> = []
        for index in 0..<max(iTunes.count, fromARD.count) {
            for list in [iTunes, fromARD] where index < list.count {
                if seenFeeds.insert(feedKey(list[index].feedURL)).inserted { merged.append(list[index]) }
            }
        }
        let wanted = normalizedTitle(term)
        let exact = merged.filter { normalizedTitle($0.title) == wanted }
        return exact + merged.filter { normalizedTitle($0.title) != wanted }
    }

    private static func isSameShow(_ show: Show, as result: PodcastSearchResult) -> Bool {
        let ard = normalizedTitle(show.title)
        let itunes = normalizedTitle(result.title)
        guard !ard.isEmpty else { return false }
        if ard == itunes { return true }
        guard itunes.hasPrefix(ard + " ") || ard.hasPrefix(itunes + " "),
              let broadcaster = show.broadcaster.map(normalizedTitle), !broadcaster.isEmpty,
              let author = result.author.map(normalizedTitle)
        else { return false }
        return (" " + author + " ").contains(" " + broadcaster + " ")
    }

    /// Lowercased, without diacritics and punctuation: "Hoyzer – Verrat am Fußball" → "hoyzer verrat am fussball".
    static func normalizedTitle(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Feed URLs compared without scheme and trailing slash.
    private static func feedKey(_ url: URL) -> String {
        var text = (FeedLoader.normalizedFeedURL(url) ?? url).absoluteString.lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// Negative, so it never meets an iTunes `collectionId`.
    private static func id(of urn: String) -> Int {
        let hex = urn.split(separator: ":").last.map(String.init) ?? ""
        let value = UInt64(hex.suffix(15), radix: 16) ?? UInt64(truncatingIfNeeded: urn.hashValue)
        return -Int(value & UInt64(Int.max)) - 1
    }
}
