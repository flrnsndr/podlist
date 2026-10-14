import Foundation
import Testing
@testable import PodlistKit

struct PlaylistSortingTests {
    private let podA = PodcastID()
    private let podB = PodcastID()

    private func entry(
        _ title: String, pod: PodcastID? = nil, podTitle: String = "P", published: Double = 0,
        duration: TimeInterval? = nil, position: Double = 0, added: Double = 0, id: EpisodeID = EpisodeID()
    ) -> PlaylistEntryInfo {
        PlaylistEntryInfo(
            episode: EpisodeInfo(
                id: id, podcastID: pod ?? podA, podcastTitle: podTitle, title: title,
                publishedAt: Date(timeIntervalSince1970: published), duration: duration),
            position: position, addedAt: Date(timeIntervalSince1970: added))
    }

    private func titles(_ e: [PlaylistEntryInfo]) -> [String] { e.map(\.episode.title) }

    @Test(arguments: [(true, ["a", "b", "c"]), (false, ["c", "b", "a"])])
    func publishedAndAdded(ascending: Bool, expected: [String]) {
        let items = [entry("b", published: 2, added: 2), entry("c", published: 3, added: 3), entry("a", published: 1, added: 1)]
        #expect(titles(PlaylistSorting.sorted(items, by: .published, ascending: ascending)) == expected)
        #expect(titles(PlaylistSorting.sorted(items, by: .added, ascending: ascending)) == expected)
    }

    @Test(arguments: [(true, ["short", "long", "none1", "none2"]), (false, ["long", "short", "none1", "none2"])])
    func durationPutsNilLast(ascending: Bool, expected: [String]) {
        let items = [
            entry("none2", position: 4), entry("long", duration: 300), entry("none1", position: 3),
            entry("short", duration: 60),
        ]
        #expect(titles(PlaylistSorting.sorted(items, by: .duration, ascending: ascending)) == expected)
    }

    @Test(arguments: [(true, ["Episode 2", "Episode 10"]), (false, ["Episode 10", "Episode 2"])])
    func titleUsesLocalizedStandardCompare(ascending: Bool, expected: [String]) {
        let items = [entry("Episode 10"), entry("Episode 2")]
        let result = titles(PlaylistSorting.sorted(items, by: .title, ascending: ascending))
        #expect(result == expected)
    }

    @Test(arguments: [true, false])
    func manualUsesPositionAndIgnoresDirection(ascending: Bool) {
        let items = [entry("c", position: 5), entry("a", position: -1), entry("b", position: 2)]
        #expect(titles(PlaylistSorting.sorted(items, by: .manual, ascending: ascending)) == ["a", "b", "c"])
    }

    @Test(arguments: PlaylistSort.allCases, [true, false])
    func equalKeysAreDeterministic(sort: PlaylistSort, ascending: Bool) {
        let ids = (0..<5).map { _ in EpisodeID() }
        let items = ids.enumerated().map { entry("same", published: 1, duration: 10, position: Double($0.offset % 2), added: 1, id: $0.element) }
        let first = PlaylistSorting.sorted(items, by: sort, ascending: ascending).map(\.episode.id)
        let second = PlaylistSorting.sorted(items.reversed(), by: sort, ascending: ascending).map(\.episode.id)
        #expect(first == second)
    }

    @Test func tieBreakIsPositionThenUUID() {
        let lo = EpisodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let hi = EpisodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let items = [entry("x", position: 1, id: hi), entry("x", position: 1, id: lo), entry("x", position: 0, id: hi)]
        let result = PlaylistSorting.sorted(items, by: .title, ascending: false)
        #expect(result.map(\.position) == [0, 1, 1])
        #expect(result.map(\.episode.id) == [hi, lo, hi])
    }

    @Test(arguments: [(true, ["a1", "a2", "b1", "b2"]), (false, ["a2", "a1", "b2", "b1"])])
    func groupedByPodcast(ascending: Bool, expected: [String]) {
        let items = [
            entry("b2", pod: podB, podTitle: "Beta", published: 2), entry("a2", pod: podA, podTitle: "alpha", published: 2),
            entry("b1", pod: podB, podTitle: "Beta", published: 1), entry("a1", pod: podA, podTitle: "alpha", published: 1),
        ]
        let sections = PlaylistSorting.grouped(items, ascending: ascending)
        #expect(sections.map(\.podcastTitle) == ["alpha", "Beta"])
        #expect(sections.map(\.podcastID) == [podA, podB])
        #expect(titles(sections.flatMap(\.entries)) == expected)
        #expect(titles(PlaylistSorting.sorted(items, by: .podcast, ascending: ascending)) == expected)
    }

    @Test func sameTitleSectionsTieBreakOnPodcastID() {
        let lo = PodcastID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let hi = PodcastID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let items = [entry("h", pod: hi, podTitle: "Same"), entry("l", pod: lo, podTitle: "Same")]
        #expect(PlaylistSorting.grouped(items, ascending: true).map(\.podcastID) == [lo, hi])
    }

    @Test func freezeToManualReproducesVisibleOrder() {
        let items = [entry("b", published: 2, position: 9), entry("a", published: 1, position: -3), entry("c", published: 3, position: 9)]
        let visible = PlaylistSorting.sorted(items, by: .published, ascending: false)
        let positions = PlaylistSorting.frozenPositions(visibleOrder: visible)
        let frozen = items.map { e -> PlaylistEntryInfo in
            var copy = e
            copy.position = positions[e.episode.id]!
            return copy
        }
        #expect(PlaylistSorting.sorted(frozen, by: .manual, ascending: true).map(\.episode.id) == visible.map(\.episode.id))
        #expect(positions.count == 3)
    }
}
