import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The inbox on service level (concept §4.10): what the feed refresher puts in, what makes an
/// episode done anywhere in the app, the actions of the inbox with "Rückgängig" and the
/// episodes just done (N74).
@MainActor
struct InboxServiceTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let library: LibraryService
    private let playlists: PlaylistService
    private let player: PlayerController
    private let upNext: UpNextService
    private let inbox: InboxService
    private let defaults: UserDefaults
    private var context: ModelContext { container.mainContext }
    /// 25 Sep 2026; the test feed's episodes are dated in October (after "now"), so they are recent.
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
    private let feedURL = URL(string: "https://example.com/feed.xml")!

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        library = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)),
            now: { InboxServiceTests.now })
        playlists = PlaylistService(context: container.mainContext, now: { InboxServiceTests.now })
        player = PlayerController(library: library)
        upNext = UpNextService(context: container.mainContext, library: library, player: player, now: { InboxServiceTests.now })
        defaults = try #require(UserDefaults(suiteName: "InboxServiceTests-\(UUID().uuidString)"))
        inbox = InboxService(
            context: container.mainContext, playlists: playlists, upNext: upNext, defaults: defaults,
            now: { InboxServiceTests.now })
    }

    // MARK: What comes in (A49, N48)

    @Test func subscribingPutsOnlyTheNewestEpisodeIntoTheInbox() async throws {
        serve(feed(items: [("g3", "Three", 3), ("g2", "Two", 2), ("g1", "One", 1)]))
        try await library.subscribe(to: feedURL)
        #expect(try inboxTitles() == ["Three"])
        #expect(try episode("Three").inboxState == .open)
        #expect(try episode("Three").inboxAddedAt == Self.now)
        #expect(try episode("Two").inboxAddedAt == nil, "the archive stays out")
    }

    /// The "In welche Playlists?" sheet adds no existing episode (N93): the newest one from
    /// subscribing stays open, whatever the rule.
    @Test(arguments: [AutoAddRule.off, .bottom])
    func assigningAfterSubscribingLeavesTheNewestEpisodeOpen(rule: AutoAddRule) async throws {
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let sport = try playlist("Sport")
        try playlists.setAssignments(of: podcast, to: [sport.uuid: rule])
        #expect(sport.entries?.isEmpty ?? true)
        #expect(try episode("Two").inboxState == .open)
        #expect(try inboxTitles() == ["Two"])
    }

    /// A68: after partial auto-add the podcast loses the playlist the episode is missing from
    /// (unassigned or deleted): nothing is left to add, so it is done.
    @Test(arguments: [false, true])
    func losingTheMissingPlaylistMakesItDone(deletePlaylist: Bool) async throws {
        let (podcast, _, politics) = try await partiallyAutoAddedEpisodeTwo()
        if deletePlaylist { try playlists.delete(politics) } else { try playlists.unassign(podcast, from: politics) }
        #expect(try episode("Two").inboxState == .done)
    }

    /// Losing the playlist it is in leaves it open: Politik is still missing.
    @Test func losingThePlaylistItIsInLeavesItOpen() async throws {
        let (podcast, sport, _) = try await partiallyAutoAddedEpisodeTwo()
        try playlists.unassign(podcast, from: sport)
        #expect(try episode("Two").inboxState == .open)
    }

    /// Sport (Unten) and Politik (Aus); a refresh brings "Two", which lands only in Sport and
    /// stays open (N75).
    private func partiallyAutoAddedEpisodeTwo() async throws -> (Podcast, Playlist, Playlist) {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let (sport, politics) = (try playlist("Sport"), try playlist("Politik"))
        try playlists.setAssignments(of: podcast, to: [sport.uuid: .bottom, politics.uuid: .off])
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.refresh(podcast)
        #expect(try episode("Two").inboxState == .open)
        // The refresher wrote in its own context: fetch again to see its episode and entries.
        func fresh(_ playlist: Playlist) throws -> Playlist {
            let id = playlist.uuid
            return try #require(try context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == id })).first)
        }
        let podcastID = podcast.uuid
        let freshPodcast = try #require(try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == podcastID })).first)
        let (freshSport, freshPolitics) = (try fresh(sport), try fresh(politics))
        #expect(freshSport.sortedEntries.compactMap { $0.episode?.title } == ["Two"])
        return (freshPodcast, freshSport, freshPolitics)
    }

    @Test func refreshPutsRecentNewEpisodesIntoTheInbox() async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        serve(feed(items: [("g3", "Three", 3, "Oct"), ("g2", "Two", 2, "Oct"), ("old", "Old", 1, "Aug"), ("g1", "One", 1, "Oct")]), etag: "\"v2\"")
        try await library.refresh(podcast)
        #expect(try inboxTitles() == ["Three", "Two", "One"])
        #expect(try episode("Old").inboxAddedAt == nil, "older than 14 days: an archive episode, not news (N48)")
        #expect(try episode("Three").inboxState == .open, "no playlist: open")
    }

    /// N75: auto-add into every playlist of the podcast makes it done; partial auto-add
    /// (Sport: Unten, Politik: Aus) leaves it open.
    @Test(arguments: [
        ([AutoAddRule.bottom], InboxState.done),
        ([.top], .done),
        ([.bottom, .top], .done),
        ([.bottom, .off], .open),
        ([.off], .open),
        ([], .open),
    ])
    func autoAddedEpisodesArriveDone(rules: [AutoAddRule], state: InboxState) async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        var assignments: [UUID: AutoAddRule] = [:]
        for (index, rule) in rules.enumerated() {
            assignments[try playlist("P\(index)").uuid] = rule
        }
        try playlists.setAssignments(of: podcast, to: assignments)
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.refresh(podcast)
        #expect(try episode("Two").inboxState == state)
        #expect(try inboxTitles().contains("Two") == (state == .open), "done episodes leave the inbox (N74)")
        if state == .done {
            // Only "One" from subscribing counts: assigning adds no existing episode (N93).
            #expect(try inbox.newCount() == 1, "auto-added episodes never count (N47)")
        }
    }

    @Test func opmlImportPutsNothingIntoTheInboxButLaterRefreshesDo() async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let opml = """
            <?xml version="1.0"?><opml version="2.0"><body>
            <outline type="rss" text="Test" xmlUrl="\(feedURL.absoluteString)"/></body></opml>
            """
        _ = try await library.importOPML(Data(opml.utf8))
        #expect(try inboxTitles().isEmpty)
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.refresh(try podcast())
        #expect(try inboxTitles() == ["Two"])
    }

    /// Subscribing again loads the whole archive again (unsubscribing deleted it); only the
    /// newest episode comes into the inbox, as on the first subscription.
    @Test func subscribingAgainPutsOnlyTheNewestEpisodeIntoTheInbox() async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        try inbox.discard(try episode("One"))
        try library.unsubscribe(podcast)
        serve(feed(items: [("g3", "Three", 3), ("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.subscribe(to: feedURL)
        #expect(try inboxTitles() == ["Three"])
        #expect(try episode("Two").inboxAddedAt == nil)
    }

    /// The newest episode was kept after unsubscribing (it is in a playlist) and was never in
    /// the inbox: subscribing again brings it in as done; no older one comes instead.
    @Test func subscribingAgainWithAKeptNewestEpisodeInAPlaylist() async throws {
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let two = try episode("Two")
        two.inboxAddedAt = nil  // e.g. from before Slice 7
        try context.save()
        try playlists.add(two, to: try playlist("Sport"))
        try library.unsubscribe(podcast)
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.subscribe(to: feedURL)
        #expect(try episode("Two").inboxAddedAt == Self.now)
        #expect(try episode("Two").inboxState == .done)
        #expect(try inboxTitles().isEmpty, "done episodes leave the inbox (N74)")
        #expect(try episode("One").inboxAddedAt == nil)
    }

    @Test func episodesOfUnsubscribedPodcastsLeaveTheInbox() async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let sport = try playlist("Sport")
        try playlists.add(try episode("One"), to: sport)  // kept after unsubscribing (§4.9)
        try library.unsubscribe(podcast)
        #expect(try inboxTitles().isEmpty)
    }

    // MARK: What makes an episode done anywhere (A50, N44, N46, N49)

    @Test func addingToAPlaylistByHandMakesItDone() throws {
        let e = try inboxEpisode("E")
        try playlists.add(e, to: try playlist("Sport"))
        #expect(e.inboxState == .done)
    }

    /// N44: the notification action "Zu Playlists hinzufügen".
    @Test func notificationActionAddToPlaylistsMakesItDone() throws {
        let e = try inboxEpisode("E")
        try assign(e, to: [try playlist("Sport")], rule: .off)
        try playlists.addToAssignedPlaylists(e)
        #expect(e.inboxState == .done)
    }

    @Test func playNextAndPlayLastMakeItDone() throws {
        let (a, b) = (try inboxEpisode("A"), try inboxEpisode("B"))
        upNext.playNext(a)
        upNext.playLast(b)
        #expect(a.inboxState == .done)
        #expect(b.inboxState == .done)
    }

    /// N46: starting is enough; it does not have to be heard to the end.
    @Test func startingToPlayMakesItDone() throws {
        let e = try inboxEpisode("E")
        upNext.play(e)
        #expect(e.inboxState == .done)
        #expect(!e.isPlayed)
    }

    /// A block starting an episode counts as playing it, too (it is in a playlist anyway).
    @Test func playingThroughAPlaylistMakesItDone() throws {
        let sport = try playlist("Sport")
        let e = try inboxEpisode("E")
        // Entered the playlist some other way without touching the inbox state (e.g. before Slice 7).
        context.insert(PlaylistEntry(playlist: sport, episode: e, position: 0, addedAt: Self.now, origin: .manual))
        e.inboxState = .open
        try context.save()
        upNext.playNow(sport)
        #expect(e.inboxState == .done)
    }

    @Test func markingPlayedMakesItDone() throws {
        let e = try inboxEpisode("E")
        try library.markPlayed(e)
        #expect(e.inboxState == .done)
    }

    /// Done is stored: leaving the playlist later (played policy) does not open it again.
    @Test func doneStaysDoneWhenTheEpisodeLeavesItsPlaylist() throws {
        let sport = try playlist("Sport")
        let e = try inboxEpisode("E")
        try playlists.add(e, to: sport)
        try playlists.remove(e, from: sport)
        #expect(e.inboxState == .done)
    }

    @Test func episodesThatWereNeverInTheInboxStayOut() throws {
        let e = try insertEpisode("E")
        try playlists.add(e, to: try playlist("Sport"))
        #expect(e.inboxAddedAt == nil)
        #expect(try inboxTitles().isEmpty)
    }

    // MARK: Actions in the inbox with "Rückgängig" (4.10, N50, A59)

    /// "Hinzufügen zu ‹Playlists des Podcasts›": at the bottom of every assigned playlist.
    @Test func addToThePodcastsPlaylistsAndUndo() throws {
        let (sport, politics) = (try playlist("Sport"), try playlist("Politik"))
        let existing = try insertEpisode("Existing")
        try playlists.add(existing, to: sport)
        let e = try inboxEpisode("E")
        try assign(e, to: [sport, politics], rule: .off)

        try inbox.addToPodcastPlaylists(e)
        #expect(e.inboxState == .done)
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["Existing", "E"])
        #expect(politics.sortedEntries.compactMap { $0.episode?.title } == ["E"])
        #expect(inbox.undoableAction != nil)

        try inbox.undo()
        #expect(e.inboxState == .open)
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["Existing"])
        #expect(politics.sortedEntries.isEmpty)
        #expect(inbox.undoableAction == nil)
    }

    /// Undo takes back only what the action added: a playlist that already had the episode keeps it.
    @Test func undoKeepsEntriesThatWereThereBefore() throws {
        let (sport, politics) = (try playlist("Sport"), try playlist("Politik"))
        let e = try inboxEpisode("E")
        try assign(e, to: [sport, politics], rule: .off)
        context.insert(PlaylistEntry(playlist: sport, episode: e, position: 0, addedAt: Self.now, origin: .manual))
        try context.save()

        try inbox.addToPodcastPlaylists(e)
        try inbox.undo()
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["E"])
        #expect(politics.sortedEntries.isEmpty)
    }

    /// Undo goes the normal way of removing (PlaylistEntryRemoval): a playlist whose cursor
    /// points at the episode moves on.
    @Test func undoAfterTheEpisodeStartedInItsPlaylistMovesTheCursorOn() throws {
        let sport = try playlist("Sport")
        let first = try insertEpisode("First")
        try playlists.add(first, to: sport)
        let e = try inboxEpisode("E")
        try assign(e, to: [sport], rule: .off)
        try inbox.addToPodcastPlaylists(e)
        upNext.playNow(sport, from: e)
        try inbox.undo()
        #expect(sport.resumeEpisode == first)
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["First"])
        #expect(e.inboxState == .done, "it was started meanwhile (N46): undo does not open it again")
    }

    /// Done is a stored status: whatever made the episode done since the action keeps it done.
    @Test func undoKeepsAnEpisodeDoneThatWasPlayedOrAddedElsewhereMeanwhile() throws {
        let (sport, other) = (try playlist("Sport"), try playlist("Other"))
        let played = try inboxEpisode("Played")
        let added = try inboxEpisode("Added")
        try assign(played, to: [sport], rule: .off)
        try assign(added, to: [sport], rule: .off)

        try inbox.addToPodcastPlaylists(played)
        try library.markPlayed(played)
        try inbox.undo()
        #expect(played.inboxState == .done, "marked played (N49)")

        try inbox.addToPodcastPlaylists(added)
        try playlists.add(added, to: other)
        try inbox.undo()
        #expect(added.inboxState == .done, "still in another playlist")
        #expect(other.sortedEntries.compactMap { $0.episode?.title } == ["Added"])
    }

    /// N75: after partial auto-add, "Hinzufügen zu …" adds only the playlists it is missing
    /// from; undo takes back only those, and the episode is open again.
    @Test func addAfterPartialAutoAddAndUndo() async throws {
        serve(feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let (sport, politics) = (try playlist("Sport"), try playlist("Politik"))
        try playlists.setAssignments(of: podcast, to: [sport.uuid: .bottom, politics.uuid: .off])
        serve(feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await library.refresh(podcast)
        let two = try episode("Two")
        #expect(two.inboxState == .open)

        try inbox.addToPodcastPlaylists(two)
        #expect(two.inboxState == .done)
        #expect(inbox.undoableAction?.kind == .added(playlists: [politics.playlistID]))
        #expect(politics.sortedEntries.compactMap { $0.episode?.title } == ["Two"])

        try inbox.undo()
        #expect(two.inboxState == .open)
        #expect(politics.sortedEntries.isEmpty)
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["Two"], "auto-add stays")
    }

    /// A59: the shown open episodes with playlists, oldest first, each at the bottom.
    @Test func addAllAndUndo() throws {
        let sport = try playlist("Sport")
        let new = try inboxEpisode("New", publishedDaysAgo: 1)
        let old = try inboxEpisode("Old", publishedDaysAgo: 3)
        let withoutPlaylist = try inboxEpisode("Alone", publishedDaysAgo: 2)
        let done = try inboxEpisode("Done", publishedDaysAgo: 2)
        try assign(new, to: [sport], rule: .off)
        try assign(old, to: [sport], rule: .off)
        try assign(done, to: [sport], rule: .off)
        done.inboxState = .done
        try context.save()

        try inbox.addAll([new, old, withoutPlaylist, done])
        #expect(sport.sortedEntries.compactMap { $0.episode?.title } == ["Old", "New"])
        #expect([new.inboxState, old.inboxState, withoutPlaylist.inboxState] == [.done, .done, .open])

        try inbox.undo()
        #expect(sport.sortedEntries.isEmpty)
        #expect([new.inboxState, old.inboxState, done.inboxState] == [.open, .open, .done])
    }

    @Test func discardAndUndo() throws {
        let e = try inboxEpisode("E")
        try inbox.discard(e)
        #expect(e.inboxState == .discarded)
        #expect(try inboxTitles().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 1, "it stays in the podcast")
        try inbox.undo()
        #expect(e.inboxState == .open)
        #expect(try inboxTitles() == ["E"])
    }

    /// N78, A69: "Rest aussortieren" takes every given open episode, also without a playlist;
    /// one undo brings them all back.
    @Test func discardAllAndUndo() throws {
        let sport = try playlist("Sport")
        let a = try inboxEpisode("A", publishedDaysAgo: 1)
        let alone = try inboxEpisode("Alone", publishedDaysAgo: 2)
        let done = try inboxEpisode("Done", publishedDaysAgo: 3)
        try assign(a, to: [sport], rule: .off)
        done.inboxState = .done
        try context.save()

        try inbox.discardAll([a, alone, done])
        #expect([a.inboxState, alone.inboxState, done.inboxState] == [.discarded, .discarded, .done])
        #expect(try inboxTitles().isEmpty)
        #expect(inbox.undoableAction?.kind == .discardedAll(count: 2))

        try inbox.undo()
        #expect([a.inboxState, alone.inboxState, done.inboxState] == [.open, .open, .done])
        #expect(try inboxTitles() == ["A", "Alone"])
    }

    @Test func discardAllWithoutOpenEpisodesDoesNothing() throws {
        let done = try inboxEpisode("Done")
        done.inboxState = .done
        try inbox.discardAll([done])
        #expect(inbox.undoableAction == nil)
    }

    // MARK: "Gerade erledigt" (N74, A67)

    /// Seen open, then done on any way: below the open ones until the app goes to the
    /// background. Discarded ones are gone (N77); undo brings an episode back to the open ones.
    @Test func episodesJustDoneStayBelowUntilTheSessionEnds() throws {
        let sport = try playlist("Sport")
        let added = try inboxEpisode("Added", publishedDaysAgo: 1)
        let byHand = try inboxEpisode("ByHand", publishedDaysAgo: 2)
        let discarded = try inboxEpisode("Discarded", publishedDaysAgo: 3)
        try assign(added, to: [sport], rule: .off)
        inbox.sawOpen(try inbox.shownEpisodes(filter: .all))

        try inbox.addToPodcastPlaylists(added)
        try playlists.add(byHand, to: sport)
        try inbox.discard(discarded)
        #expect(try inboxTitles().isEmpty)
        #expect(try inbox.recentlyDoneEpisodes(filter: .all).map(\.title) == ["Added", "ByHand"])

        try inbox.undo()
        #expect(try inboxTitles() == ["Discarded"], "undo of the latest action, the discard")

        inbox.endSession()
        #expect(try inbox.recentlyDoneEpisodes(filter: .all).isEmpty)
        #expect(try inboxTitles() == ["Discarded"])
    }

    /// An episode that was never seen open (sorted completely by auto-add, or done before the
    /// inbox showed it) does not appear below.
    @Test func episodesNotSeenOpenAreNotJustDone() throws {
        let e = try inboxEpisode("E")
        try playlists.add(e, to: try playlist("Sport"))
        #expect(try inbox.recentlyDoneEpisodes(filter: .all).isEmpty)
    }

    @Test func playNextFromTheInboxAndUndo() throws {
        let sport = try playlist("Sport")
        try playlists.add(try insertEpisode("S"), to: sport)
        upNext.playNow(sport)
        let e = try inboxEpisode("E")

        inbox.playNext(e)
        #expect(e.inboxState == .done)
        #expect(try render() == "▶ S · E · [Sport]")
        try inbox.undo()
        #expect(e.inboxState == .open)
        #expect(try render() == "▶ S · [Sport]")
    }

    /// On an empty Up Next "Als Nächstes" cues the episode (A22); undo empties the player again.
    @Test func playNextOnAnEmptyUpNextAndUndo() throws {
        let e = try inboxEpisode("E")
        inbox.playNext(e)
        #expect(player.episode == e)
        try inbox.undo()
        #expect(try render() == "–")
        #expect(player.episode == nil)
        #expect(e.inboxState == .open)
    }

    /// One action at a time (N50): a new action replaces the undo of the former one.
    @Test func onlyTheLatestActionCanBeUndone() throws {
        let (a, b) = (try inboxEpisode("A"), try inboxEpisode("B"))
        try inbox.discard(a)
        try inbox.discard(b)
        try inbox.undo()
        #expect(a.inboxState == .discarded)
        #expect(b.inboxState == .open)
        try inbox.undo()
        #expect(a.inboxState == .discarded, "nothing more to undo")
    }

    // MARK: Number on the tab (N41, N47, A60)

    @Test func newCountSinceTheLastVisit() throws {
        _ = try inboxEpisode("Before", addedDaysAgo: 2)
        inbox.didVisit(at: Self.now.addingTimeInterval(-24 * 3600))
        _ = try inboxEpisode("After", addedDaysAgo: 0.5)
        let done = try inboxEpisode("Done", addedDaysAgo: 0.5)
        done.inboxState = .done
        try context.save()
        #expect(try inbox.newCount() == 1)
        inbox.didVisit(at: Self.now)
        #expect(try inbox.newCount() == 0)
        #expect(inbox.lastVisit == Self.now)
    }

    /// N65: a podcast whose playlists are all hidden stays out of "Alle" and the number.
    @Test func hiddenPlaylistKeepsItsPodcastsOutOfAllAndTheNumber() throws {
        let kids = try playlist("Kids")
        let hidden = try inboxEpisode("Hidden")
        _ = try inboxEpisode("Visible")
        try assign(hidden, to: [kids], rule: .off)
        try playlists.setHidden(true, of: kids)
        #expect(try inboxTitles() == ["Visible"])
        #expect(try inbox.shownEpisodes(filter: .playlist(kids.playlistID)).map(\.title) == ["Hidden"])
        #expect(try inbox.newCount() == 1)
    }

    @Test func lastVisitSurvivesARestart() throws {
        inbox.didVisit(at: Self.now)
        let again = InboxService(context: context, playlists: playlists, upNext: upNext, defaults: defaults, now: { InboxServiceTests.now })
        #expect(again.lastVisit == Self.now)
    }

    // MARK: Helpers

    private func serve(_ body: String, etag: String = "\"v1\"") {
        routes.set(feedURL, .init(headers: ["ETag": etag], body: Data(body.utf8)))
    }

    /// Items: (guid, title, day[, month]); month defaults to Oct 2026 (after `now`).
    private func feed(items: [(String, String, Int, String)]) -> String {
        let entries = items.map { guid, title, day, month in
            """
            <item><guid>\(guid)</guid><title>\(title)</title>
            <pubDate>\(String(format: "%02d", day)) \(month) 2026 08:00:00 +0000</pubDate>
            <enclosure url="https://cdn.example.com/\(guid).mp3" length="1000" type="audio/mpeg"/></item>
            """
        }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Test Podcast</title>\(entries)</channel></rss>
            """
    }

    private func feed(items: [(String, String, Int)]) -> String {
        feed(items: items.map { ($0.0, $0.1, $0.2, "Oct") })
    }

    private func podcast() throws -> Podcast {
        try #require(try context.fetch(FetchDescriptor<Podcast>()).first)
    }

    private func episode(_ title: String) throws -> Episode {
        try #require(try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.title == title })).first)
    }

    private func playlist(_ name: String) throws -> Playlist {
        try playlists.createPlaylist(name: name, colorKey: "blue", symbolName: "star")
    }

    /// The inbox as the tab shows it (filter "Alle").
    private func inboxTitles() throws -> [String] {
        try inbox.shownEpisodes(filter: .all).map(\.title)
    }

    /// An episode of its own podcast "<title> Podcast" (subscribed, no assignment).
    private func insertEpisode(_ title: String, publishedDaysAgo: Double = 1) throws -> Episode {
        let podcast = Podcast(feedURL: URL(string: "https://example.invalid/\(title).xml")!, title: "\(title) Podcast", subscribedAt: Self.now)
        context.insert(podcast)
        let episode = Episode(
            guid: title, title: title, publishedAt: Self.now.addingTimeInterval(-publishedDaysAgo * 24 * 3600),
            audioURL: URL(string: "https://cdn.invalid/\(title).mp3")!)
        episode.duration = 3_600
        episode.podcast = podcast
        context.insert(episode)
        try context.save()
        return episode
    }

    /// Like `insertEpisode`, but open in the inbox.
    private func inboxEpisode(_ title: String, publishedDaysAgo: Double = 1, addedDaysAgo: Double = 0) throws -> Episode {
        let episode = try insertEpisode(title, publishedDaysAgo: publishedDaysAgo)
        episode.inboxAddedAt = Self.now.addingTimeInterval(-addedDaysAgo * 24 * 3600)
        episode.inboxState = .open
        try context.save()
        return episode
    }

    private func assign(_ episode: Episode, to targets: [Playlist], rule: AutoAddRule) throws {
        let podcast = try #require(episode.podcast)
        for playlist in targets {
            context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: rule, createdAt: Self.now))
        }
        try context.save()
    }

    /// "▶ S · E · [Sport]" as in `UpNextServiceTests`.
    private func render() throws -> String {
        let items = try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
        var parts: [String] = []
        if let now = items.first(where: \.isNowPlaying), let episode = now.episode { parts.append("▶ " + episode.title) }
        for item in items where !item.isNowPlaying {
            if let episode = item.episode { parts.append(episode.title) }
            if let playlist = item.playlist { parts.append("[\(playlist.customName ?? "")]") }
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}
