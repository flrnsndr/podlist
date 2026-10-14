import Foundation
import Testing
@testable import PodlistKit

struct UpNextHistoryTests {
    private let state = UpNextState(
        nowPlaying: NowPlaying(episode: EpisodeID(), playlist: PlaylistID()),
        items: [.episode(EpisodeID()), .playlist(PlaylistID())])

    @Test func recordsNewestFirst() {
        var history = UpNextHistory()
        let other = UpNextState(items: [.episode(EpisodeID())])
        history.record(state, reason: .replaced, now: Date(timeIntervalSinceReferenceDate: 1))
        history.record(other, reason: .cleared, now: Date(timeIntervalSinceReferenceDate: 2))
        #expect(history.snapshots.map(\.state) == [other, state])
        #expect(history.snapshots.map(\.reason) == [.cleared, .replaced])
    }

    @Test func emptyStateIsNotRecorded() {
        var history = UpNextHistory()
        history.record(UpNextState(), reason: .cleared, now: .distantPast)
        #expect(history.isEmpty)
    }

    @Test func keepsOnlyTheLastTwentyStates() {
        var history = UpNextHistory()
        for second in 0..<25 {
            history.record(state, reason: .replaced, now: Date(timeIntervalSinceReferenceDate: Double(second)))
        }
        #expect(history.count == UpNextHistory.limit)
        #expect(history.snapshots.first?.createdAt == Date(timeIntervalSinceReferenceDate: 24))
        #expect(history.snapshots.last?.createdAt == Date(timeIntervalSinceReferenceDate: 5))
    }

    @Test func loadingPersistedSnapshotsSortsAndTrims() {
        let snapshots = (0..<22).map {
            UpNextSnapshotValue(createdAt: Date(timeIntervalSinceReferenceDate: Double($0)), reason: .replaced, state: state)
        }
        let history = UpNextHistory(snapshots: snapshots.shuffled())
        #expect(history.count == 20)
        #expect(history.snapshots.map(\.createdAt) == snapshots.reversed().prefix(20).map(\.createdAt))
    }

    @Test func undoAfterUndoReturnsToTheReplacingState() throws {
        let a = QueuePlaylist(id: PlaylistID(), playedPolicy: .remove, episodes: [EpisodeID()], resumeEpisode: nil)
        let b = QueuePlaylist(id: PlaylistID(), playedPolicy: .remove, episodes: [EpisodeID()], resumeEpisode: nil)
        var history = UpNextHistory()
        var resolver = QueueResolver(state: UpNextState(), playlists: [a, b], playedEpisodes: [])
        _ = resolver.playNow(playlist: a.id, history: &history, now: .distantPast)
        _ = resolver.playNow(playlist: b.id, history: &history, now: .distantPast)
        let withB = resolver.state
        _ = resolver.restore(try #require(history.snapshots.first), history: &history, now: .distantPast)
        #expect(resolver.state.items == [.playlist(a.id)])
        _ = resolver.restore(try #require(history.snapshots.first), history: &history, now: .distantPast)
        #expect(resolver.state == withB)
        #expect(history.snapshots.map(\.reason) == [.restored, .restored, .replaced])
    }

    @Test func snapshotPayloadRoundTripsThroughCodable() throws {
        let snapshot = UpNextSnapshotValue(createdAt: Date(timeIntervalSinceReferenceDate: 7), reason: .cleared, state: state)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UpNextSnapshotValue.self, from: data) == snapshot)
    }
}
