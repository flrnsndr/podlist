import Foundation

/// What the store knows about an episode to recognize it in a refreshed feed.
public struct EpisodeKey: Hashable, Sendable {
    public var id: EpisodeID
    public var guid: String
    public var audioURL: URL
    public var title: String
    public var publishedAt: Date

    public init(id: EpisodeID, guid: String, audioURL: URL, title: String, publishedAt: Date) {
        self.id = id
        self.guid = guid
        self.audioURL = audioURL
        self.title = title
        self.publishedAt = publishedAt
    }
}

public enum FeedMergeAction: Hashable, Sendable {
    /// The feed item is a known episode; update its metadata.
    case update(EpisodeID, ParsedEpisode)
    /// A new episode.
    case insert(ParsedEpisode)
}

/// Matches the items of a refreshed feed against the stored episodes (ADR 0003):
/// GUID → audio URL → title + publication date. Every stored episode matches at most one
/// item, duplicates within the feed are dropped, and stored episodes that left the feed
/// are not touched.
public enum FeedMerge {
    /// The GUID stored for an item: its `guid`, or the audio URL when the feed has none.
    public static func storedGUID(for episode: ParsedEpisode) -> String {
        episode.guid ?? episode.audioURL.absoluteString
    }

    public static func actions(existing: [EpisodeKey], parsed: [ParsedEpisode]) -> [FeedMergeAction] {
        var byGUID: [String: EpisodeKey] = [:]
        var byURL: [URL: EpisodeKey] = [:]
        var byTitleAndDate: [TitleAndDate: EpisodeKey] = [:]
        for key in existing {
            byGUID[key.guid] = byGUID[key.guid] ?? key
            byURL[key.audioURL] = byURL[key.audioURL] ?? key
            let titleAndDate = TitleAndDate(title: key.title, date: key.publishedAt)
            byTitleAndDate[titleAndDate] = byTitleAndDate[titleAndDate] ?? key
        }

        var matched: Set<EpisodeID> = []
        var seenGUIDs: Set<String> = []
        var actions: [FeedMergeAction] = []
        for item in parsed {
            let guid = storedGUID(for: item)
            guard seenGUIDs.insert(guid).inserted else { continue }
            let candidates = [
                byGUID[guid],
                byURL[item.audioURL],
                item.publishedAt.flatMap { byTitleAndDate[TitleAndDate(title: item.title, date: $0)] },
            ]
            if let key = candidates.lazy.compactMap({ $0 }).first(where: { !matched.contains($0.id) }) {
                matched.insert(key.id)
                actions.append(.update(key.id, item))
            } else {
                actions.append(.insert(item))
            }
        }
        return actions
    }

    private struct TitleAndDate: Hashable {
        var title: String
        var date: Date
    }
}
