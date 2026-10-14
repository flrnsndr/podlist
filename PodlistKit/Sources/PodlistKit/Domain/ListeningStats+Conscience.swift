import Foundation

// G. Library and bad conscience (I26–I28).

extension ListeningStats.Context {
    func neglected() -> Insight? {
        let heard = Set(pieces.compactMap { records[$0.record].podcast })
        let entries = library.podcasts.compactMap { podcast -> NeglectedPodcast? in
            guard podcast.isSubscribed, podcast.subscribedAt < interval.start, !heard.contains(podcast.id) else { return nil }
            let count = podcast.episodesPublishedAt.filter { interval.holds($0) }.count
            guard count >= 1 else { return nil }
            return NeglectedPodcast(podcast: PodcastRef(id: podcast.id, title: podcast.title), newEpisodes: count)
        }.sorted {
            $0.newEpisodes != $1.newEpisodes ? $0.newEpisodes > $1.newEpisodes : $0.podcast.title < $1.podcast.title
        }
        return entries.isEmpty ? nil : .neglected(Array(entries.prefix(3)))
    }

    func backlog() -> Insight? {
        guard period.kind == .month, containsNow, atLeast(library.backlogSeconds, 3_600), total > 0, !periodDays.isEmpty
        else { return nil }
        let pace = total / Double(periodDays.count)
        let speed = content / total
        return .backlog(Backlog(
            seconds: library.backlogSeconds,
            days: Int((library.backlogSeconds / speed / pace).rounded(.up)),
            nonstopDays: Int((library.backlogSeconds / speed / 86_400).rounded(.up))))
    }

    func unheardSubscriptions() -> Insight? {
        guard period.kind == .year else { return nil }
        let limit = calendar.date(byAdding: .day, value: -30, to: min(interval.end, now))!
        let heard = Set(pieces.compactMap { records[$0.record].podcast })
        let count = library.podcasts.filter {
            $0.isSubscribed && $0.subscribedAt <= limit && !heard.contains($0.id)
        }.count
        return count >= 1 ? .unheardSubscriptions(count: count) : nil
    }
}
