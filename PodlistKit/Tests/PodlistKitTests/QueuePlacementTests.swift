import Foundation
import Testing
@testable import PodlistKit

private func ids(_ names: String) -> [EpisodeID] {
    names.split(separator: " ").map { QueueWorld.episode(String($0)) }
}

private func names(_ ids: [EpisodeID]?) -> String? {
    ids?.map { QueueWorld.name($0.uuid) }.joined(separator: " ")
}

/// N94: an episode that got its place in the queue moves in its playlist next to its
/// neighbours from the queue; other episodes of the queue do not matter.
struct QueuePlacementTests {
    private func order(
        _ playlist: String, placing episode: String, queue: String, resume: String? = nil
    ) -> String? {
        let queue = ids(queue)
        let placed = QueueWorld.episode(episode)
        return names(QueuePlacement.order(
            of: ids(playlist), placing: placed, at: queue.firstIndex(of: placed)!, in: queue,
            resume: resume.map(QueueWorld.episode)))
    }

    /// Florian's example: A from X dragged past B (X) and C (Y) → in X, A comes after B.
    @Test func movesBehindTheNearestEpisodeOfThePlaylistInFrontOfIt() {
        #expect(order("A B D", placing: "A", queue: "B C A D") == "B A D")
    }

    @Test func withoutOneInFrontItMovesBeforeTheNearestBehindIt() {
        #expect(order("B D A", placing: "A", queue: "C A D B") == "B A D")
    }

    @Test func episodesOfOtherPlaylistsAreNoNeighbours() {
        #expect(order("B A", placing: "A", queue: "B Y1 Y2 A") == nil, "A already follows B")
    }

    /// No neighbour in the queue: right before the playlist's Wiedergabestand, without one
    /// at the top.
    @Test(arguments: [("C", "A B D C E"), (nil, "D A B C E")] as [(String?, String)])
    func withoutNeighboursItMovesBeforeTheResumePoint(resume: String?, expected: String) {
        #expect(order("A B C D E", placing: "D", queue: "Y1 D Y2", resume: resume) == expected)
    }

    @Test func aResumePointThatIsTheEpisodeItselfChangesNothing() {
        #expect(order("A B C", placing: "B", queue: "Y1 B", resume: "B") == nil)
    }

    @Test func aResumePointNoLongerInThePlaylistCountsAsNone() {
        #expect(order("A B C", placing: "C", queue: "C", resume: "Z") == "C A B")
    }

    /// The episode itself can appear a second time in the queue (in a block): that copy is
    /// no neighbour.
    @Test func anotherCopyOfTheEpisodeIsNoNeighbour() {
        #expect(order("A B C", placing: "C", queue: "C A B C") == "C A B")
    }

    @Test func anEpisodeNotInThePlaylistChangesNothing() {
        #expect(order("A B", placing: "Z", queue: "A Z B") == nil)
    }
}
