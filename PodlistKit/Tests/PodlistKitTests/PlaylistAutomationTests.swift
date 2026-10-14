import Foundation
import Testing
@testable import PodlistKit

struct PlaylistAutomationTests {
    private let pod = PodcastID()
    private let playlist = PlaylistID()
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func episode(_ title: String, published: Double) -> EpisodeInfo {
        EpisodeInfo(podcastID: pod, podcastTitle: "P", title: title, publishedAt: Date(timeIntervalSince1970: published))
    }

    private func entry(_ e: EpisodeInfo, position: Double) -> PlaylistEntryInfo {
        PlaylistEntryInfo(episode: e, position: position, addedAt: .distantPast)
    }

    private func run(_ rule: AutoAddRule, new: [EpisodeInfo], existing: [PlaylistEntryInfo] = []) -> [PlaylistInsertion] {
        PlaylistAutomation.insertions(
            forNewEpisodes: new, assignments: [PlaylistAssignmentInfo(playlistID: playlist, rule: rule)],
            existingEntries: [playlist: existing], now: now)
    }

    @Test func offAddsNothing() {
        #expect(run(.off, new: [episode("n", published: 1)]).isEmpty)
    }

    @Test func topAndBottomSingleEpisode() {
        let existing = [entry(episode("x", published: 0), position: 3), entry(episode("y", published: 0), position: 7)]
        let new = episode("n", published: 5)
        let top = run(.top, new: [new], existing: existing)
        let bottom = run(.bottom, new: [new], existing: existing)
        #expect(top.map(\.entry.position) == [2])
        #expect(bottom.map(\.entry.position) == [8])
        #expect(top.first?.entry.addedAt == now)
        #expect(top.first?.playlistID == playlist)
    }

    @Test func multipleNewEpisodesTopNewestOnTop() {
        let old = episode("old", published: 1), mid = episode("mid", published: 2), new = episode("new", published: 3)
        let result = run(.top, new: [mid, new, old], existing: [entry(episode("x", published: 0), position: 0)])
        let ordered = result.sorted { $0.entry.position < $1.entry.position }.map(\.entry.episode.title)
        #expect(ordered == ["new", "mid", "old"])
        #expect(result.allSatisfy { $0.entry.position < 0 })
    }

    @Test func multipleNewEpisodesBottomOldestFirst() {
        let old = episode("old", published: 1), mid = episode("mid", published: 2), new = episode("new", published: 3)
        let result = run(.bottom, new: [new, old, mid], existing: [entry(episode("x", published: 0), position: 0)])
        let ordered = result.sorted { $0.entry.position < $1.entry.position }.map(\.entry.episode.title)
        #expect(ordered == ["old", "mid", "new"])
        #expect(result.allSatisfy { $0.entry.position > 0 })
    }

    @Test(arguments: [AutoAddRule.top, .bottom])
    func skipsEpisodesAlreadyInPlaylist(rule: AutoAddRule) {
        let have = episode("have", published: 1), fresh = episode("fresh", published: 2)
        let result = run(rule, new: [have, fresh], existing: [entry(have, position: 0)])
        #expect(result.map(\.entry.episode.title) == ["fresh"])
    }

    @Test func emptyPlaylistStartsAtZero() {
        #expect(run(.top, new: [episode("a", published: 1)]).map(\.entry.position) == [0])
        #expect(run(.bottom, new: [episode("a", published: 1)]).map(\.entry.position) == [0])
    }

    @Test func appliesEachAssignmentToItsOwnPlaylist() {
        let other = PlaylistID()
        let new = episode("n", published: 1)
        let result = PlaylistAutomation.insertions(
            forNewEpisodes: [new],
            assignments: [
                PlaylistAssignmentInfo(playlistID: playlist, rule: .top),
                PlaylistAssignmentInfo(playlistID: other, rule: .bottom),
                PlaylistAssignmentInfo(playlistID: PlaylistID(), rule: .off),
            ],
            existingEntries: [other: [entry(episode("x", published: 0), position: 4)]], now: now)
        #expect(result.map(\.playlistID) == [playlist, other])
        #expect(result.map(\.entry.position) == [0, 5])
    }
}
