import Foundation

/// Display sorting of playlist entries (concept §4.2). Pure functions, no state.
public enum PlaylistSorting {
    /// One podcast section of the "by podcast" view.
    public struct Section: Hashable, Sendable {
        public var podcastID: PodcastID
        public var podcastTitle: String
        public var entries: [PlaylistEntryInfo]
    }

    /// Sorted entries. `ascending` is ignored for `manual`. For `podcast` the result is the
    /// flat order (sections concatenated), which is what the queue plays.
    public static func sorted(
        _ entries: [PlaylistEntryInfo], by sort: PlaylistSort, ascending: Bool
    ) -> [PlaylistEntryInfo] {
        switch sort {
        case .podcast:
            return grouped(entries, ascending: ascending).flatMap(\.entries)
        case .manual:
            return entries.sorted { compare($0, $1) < 0 }
        case .published:
            return entries.sorted { order($0, $1, ascending) { cmp($0.episode.publishedAt, $1.episode.publishedAt) } }
        case .added:
            return entries.sorted { order($0, $1, ascending) { cmp($0.addedAt, $1.addedAt) } }
        case .title:
            return entries.sorted {
                order($0, $1, ascending) { $0.episode.title.localizedStandardCompare($1.episode.title).rawValue }
            }
        case .duration:
            return entries.sorted { a, b in
                switch (a.episode.duration, b.episode.duration) {
                case let (x?, y?):
                    let c = cmp(x, y)
                    if c != 0 { return ascending ? c < 0 : c > 0 }
                case (nil, _?): return false  // nil durations last in both directions
                case (_?, nil): return true
                case (nil, nil): break
                }
                return compare(a, b) < 0
            }
        }
    }

    /// Sections alphabetical by podcast title (tie-break podcastID), inside a section by
    /// publishedAt in the given direction (assumption A2).
    public static func grouped(_ entries: [PlaylistEntryInfo], ascending: Bool) -> [Section] {
        let byPodcast = Dictionary(grouping: entries, by: { $0.episode.podcastID })
        return byPodcast.map { id, items in
            Section(
                podcastID: id,
                podcastTitle: items[0].episode.podcastTitle,
                entries: sorted(items, by: .published, ascending: ascending))
        }
        .sorted {
            let c = $0.podcastTitle.localizedStandardCompare($1.podcastTitle).rawValue
            return c != 0 ? c < 0 : $0.podcastID.uuid.uuidString < $1.podcastID.uuid.uuidString
        }
    }

    /// "Freeze to manual" (concept §4.2): positions so that manual order equals `visibleOrder`.
    public static func frozenPositions(visibleOrder: [PlaylistEntryInfo]) -> [EpisodeID: Double] {
        var result: [EpisodeID: Double] = [:]
        for (index, entry) in visibleOrder.enumerated() { result[entry.episode.id] = Double(index) }
        return result
    }

    // MARK: Helpers

    private static func cmp<T: Comparable>(_ a: T, _ b: T) -> Int { a < b ? -1 : (a > b ? 1 : 0) }

    /// Fixed tie-break: position, then episode uuid (always ascending, so ties never flicker).
    private static func compare(_ a: PlaylistEntryInfo, _ b: PlaylistEntryInfo) -> Int {
        let p = cmp(a.position, b.position)
        if p != 0 { return p }
        return cmp(a.episode.id.uuid.uuidString, b.episode.id.uuid.uuidString)
    }

    private static func order(
        _ a: PlaylistEntryInfo, _ b: PlaylistEntryInfo, _ ascending: Bool,
        key: (PlaylistEntryInfo, PlaylistEntryInfo) -> Int
    ) -> Bool {
        let c = key(a, b)
        if c != 0 { return ascending ? c < 0 : c > 0 }
        return compare(a, b) < 0
    }
}
