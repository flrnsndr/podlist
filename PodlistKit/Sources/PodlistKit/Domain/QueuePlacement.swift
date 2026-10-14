import Foundation

/// N94: an episode that gets its place in the queue (dragged, "Als Nächstes", "Jetzt") moves
/// in each of its playlists next to its neighbours from the queue. Only its order changes,
/// never the content; episodes of other playlists stay where they are. Pure function.
public enum QueuePlacement {
    /// The playlist's new order, or `nil` if nothing changes.
    ///
    /// - Parameters:
    ///   - playlist: its episodes in their current order.
    ///   - index: where `episode` got its place in `queue`.
    ///   - queue: the queue as the episodes it will play: the running one, single episodes,
    ///     the episodes of the blocks. Another copy of `episode` in it is no neighbour.
    ///   - resume: the playlist's Wiedergabestand. Without a neighbour in the queue the
    ///     episode goes right before it, without one (or one no longer in it) to the top.
    public static func order(
        of playlist: [EpisodeID], placing episode: EpisodeID, at index: Int, in queue: [EpisodeID], resume: EpisodeID?
    ) -> [EpisodeID]? {
        guard playlist.contains(episode) else { return nil }
        let members = Set(playlist)
        let isNeighbour = { (other: EpisodeID) in other != episode && members.contains(other) }
        var result = playlist.filter { $0 != episode }
        if let before = queue[..<index].last(where: isNeighbour), let at = result.firstIndex(of: before) {
            result.insert(episode, at: at + 1)
        } else if let after = queue[(index + 1)...].first(where: isNeighbour), let at = result.firstIndex(of: after) {
            result.insert(episode, at: at)
        } else if let resume, resume != episode, let at = result.firstIndex(of: resume) {
            result.insert(episode, at: at)
        } else if resume == episode {
            return nil
        } else {
            result.insert(episode, at: 0)
        }
        return result == playlist ? nil : result
    }
}
