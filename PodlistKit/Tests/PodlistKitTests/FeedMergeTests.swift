import Foundation
import Testing
@testable import PodlistKit

struct FeedMergeTests {
    private let date = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func url(_ name: String) -> URL { URL(string: "https://cdn.example.com/\(name).mp3")! }

    private func key(_ guid: String, url name: String, title: String = "T", date: Date? = nil) -> EpisodeKey {
        EpisodeKey(id: EpisodeID(), guid: guid, audioURL: url(name), title: title, publishedAt: date ?? self.date)
    }

    private func item(_ guid: String?, url name: String, title: String = "T", date: Date? = nil) -> ParsedEpisode {
        ParsedEpisode(guid: guid, title: title, publishedAt: date, audioURL: url(name))
    }

    @Test func matchesByGUIDEvenWhenTheAudioURLChanges() {
        let stored = key("g1", url: "a")
        let actions = FeedMerge.actions(existing: [stored], parsed: [item("g1", url: "a-new")])
        #expect(actions == [.update(stored.id, item("g1", url: "a-new"))])
    }

    @Test func fallsBackToTheAudioURLWhenTheGUIDChanged() {
        let stored = key("old-guid", url: "a")
        let actions = FeedMerge.actions(existing: [stored], parsed: [item("new-guid", url: "a")])
        #expect(actions == [.update(stored.id, item("new-guid", url: "a"))])
    }

    @Test func fallsBackToTitleAndDate() {
        let stored = key("old-guid", url: "a", title: "Folge 1", date: date)
        let changed = item("new-guid", url: "b", title: "Folge 1", date: date)
        #expect(FeedMerge.actions(existing: [stored], parsed: [changed]) == [.update(stored.id, changed)])
    }

    @Test func titleWithoutDateDoesNotMatch() {
        let stored = key("old-guid", url: "a", title: "Folge 1")
        let changed = item("new-guid", url: "b", title: "Folge 1", date: nil)
        #expect(FeedMerge.actions(existing: [stored], parsed: [changed]) == [.insert(changed)])
    }

    @Test func itemsWithoutGUIDAreStoredAndRecognizedByTheirAudioURL() {
        let first = item(nil, url: "a")
        #expect(FeedMerge.storedGUID(for: first) == url("a").absoluteString)
        let stored = key(FeedMerge.storedGUID(for: first), url: "a")
        #expect(FeedMerge.actions(existing: [stored], parsed: [first]) == [.update(stored.id, first)])
    }

    @Test func newItemsAreInsertedInFeedOrder() {
        let stored = key("g1", url: "a")
        let parsed = [item("g3", url: "c"), item("g1", url: "a"), item("g2", url: "b")]
        #expect(FeedMerge.actions(existing: [stored], parsed: parsed) == [
            .insert(parsed[0]), .update(stored.id, parsed[1]), .insert(parsed[2]),
        ])
    }

    @Test func duplicateItemsInTheFeedAreDropped() {
        let parsed = [item("g1", url: "a"), item("g1", url: "a-copy")]
        #expect(FeedMerge.actions(existing: [], parsed: parsed) == [.insert(parsed[0])])
    }

    @Test func aStoredEpisodeMatchesOnlyOnce() {
        // Two items share the stored audio URL (re-uploaded episode with a new GUID).
        let stored = key("g1", url: "a")
        let parsed = [item("g1", url: "a"), item("g2", url: "a")]
        #expect(FeedMerge.actions(existing: [stored], parsed: parsed) == [
            .update(stored.id, parsed[0]), .insert(parsed[1]),
        ])
    }

    @Test func episodesThatLeftTheFeedAreNotTouched() {
        let actions = FeedMerge.actions(existing: [key("gone", url: "x")], parsed: [item("g1", url: "a")])
        #expect(actions == [.insert(item("g1", url: "a"))])
    }
}
