import Foundation
import Testing
@testable import PodlistKit

// Concept §4.10 (Eingang) as tests: which episodes enter the inbox (A49, N48), how long they
// stay (A48), open → done → discarded (A50, N46, N49), only open ones show and the ones just
// done below them (N74, A67), auto-add (N75, A68), the filter (A56), the number on the tab
// (N41, N47), the sort (N53), "Alle hinzufügen" (A59) and "Rest aussortieren" (N78, A69).
struct InboxRulesTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
    private static let day: TimeInterval = 24 * 3600

    private static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * day) }

    private func candidate(
        _ id: EpisodeID = EpisodeID(), publishedDaysAgo: Double, wasInInbox: Bool = false, isInPlaylist: Bool = false
    ) -> InboxCandidate {
        InboxCandidate(
            id: id, publishedAt: Self.daysAgo(publishedDaysAgo), wasInInbox: wasInInbox, isInPlaylist: isInPlaylist)
    }

    private func episode(
        _ id: EpisodeID = EpisodeID(), publishedDaysAgo: Double = 1, addedDaysAgo: Double = 1,
        state: InboxState = .open, playlists: Set<PlaylistID> = [], subscribed: Bool = true, hidden: Bool = false
    ) -> InboxEpisode {
        InboxEpisode(
            id: id, publishedAt: Self.daysAgo(publishedDaysAgo), addedAt: Self.daysAgo(addedDaysAgo),
            state: state, podcastPlaylists: playlists, podcastIsSubscribed: subscribed, podcastIsHidden: hidden)
    }

    // MARK: Entering (A49, N48)

    /// A refresh brings the new episodes, but only those of the last 14 days: older ones are
    /// archive episodes the feed changed (new GUIDs), not news.
    @Test(arguments: [(0.0, true), (13.9, true), (14.0, true), (14.1, false), (400.0, false), (-1.0, true)])
    func refreshBringsNewEpisodesOfTheLastFourteenDays(publishedDaysAgo: Double, enters: Bool) {
        let id = EpisodeID()
        let ids = InboxRules.entering([candidate(id, publishedDaysAgo: publishedDaysAgo)], arrival: .refresh, now: Self.now)
        #expect(ids == (enters ? [id] : []))
    }

    @Test func refreshBringsEveryRecentNewEpisode() {
        let (a, b, old) = (EpisodeID(), EpisodeID(), EpisodeID())
        let ids = InboxRules.entering(
            [candidate(a, publishedDaysAgo: 0), candidate(old, publishedDaysAgo: 30), candidate(b, publishedDaysAgo: 2)],
            arrival: .refresh, now: Self.now)
        #expect(Set(ids) == [a, b])
    }

    /// Subscribing (also again, after unsubscribing) brings only the newest episode, however old.
    @Test func subscribingBringsOnlyTheNewestEpisodeHoweverOld() {
        let (newest, older, oldest) = (EpisodeID(), EpisodeID(), EpisodeID())
        let ids = InboxRules.entering(
            [candidate(older, publishedDaysAgo: 200), candidate(newest, publishedDaysAgo: 100), candidate(oldest, publishedDaysAgo: 300)],
            arrival: .subscribe, now: Self.now)
        #expect(ids == [newest])
    }

    /// Subscribing again: if the newest episode was in the inbox before (kept after
    /// unsubscribing), it is left as it is, and no older one comes instead.
    @Test func subscribingAgainLeavesANewestEpisodeThatWasInTheInbox() {
        let ids = InboxRules.entering(
            [candidate(publishedDaysAgo: 1, wasInInbox: true), candidate(publishedDaysAgo: 5)],
            arrival: .subscribe, now: Self.now)
        #expect(ids.isEmpty)
    }

    /// Feeds without dates: every episode gets the same date; the feed order decides (the
    /// first candidate is the newest).
    @Test func subscribingWithEqualDatesTakesTheFirstInFeedOrder() {
        let (first, second) = (EpisodeID(), EpisodeID())
        let ids = InboxRules.entering(
            [candidate(first, publishedDaysAgo: 0), candidate(second, publishedDaysAgo: 0)], arrival: .subscribe, now: Self.now)
        #expect(ids == [first])
    }

    /// Subscribing again: the candidates are all of the podcast's episodes, also those kept
    /// after unsubscribing (§4.9). A kept newest episode that is already in a playlist arrives done.
    @Test(arguments: [(false, InboxState.open), (true, .done)])
    func initialState(isInPlaylist: Bool, state: InboxState) {
        #expect(InboxRules.initialState(of: candidate(publishedDaysAgo: 0, isInPlaylist: isInPlaylist)) == state)
    }

    @Test func refreshNeverBringsAnEpisodeBackThatWasInTheInbox() {
        let ids = InboxRules.entering([candidate(publishedDaysAgo: 1, wasInInbox: true)], arrival: .refresh, now: Self.now)
        #expect(ids.isEmpty)
    }

    /// N75, A68: auto-add makes an episode done only if it is in a playlist and in every
    /// playlist of its podcast. Partial auto-add (Sport: Unten, Politik: Aus) leaves it open.
    /// Kept after unsubscribing (no assignments yet, §4.9) and in a playlist: done.
    @Test(arguments: [
        (["S"], ["S"], true),
        (["S", "P"], ["S", "P"], true),
        (["S"], ["S", "P"], false),
        ([], ["S"], false),
        ([], [], false),
        (["S"], [], true),
        (["S", "X"], ["S"], true),
    ])
    func autoAddSortsAnEpisodeCompletely(inPlaylists: [String], podcastPlaylists: [String], sorted: Bool) {
        let ids = Dictionary(uniqueKeysWithValues: ["S", "P", "X"].map { ($0, PlaylistID()) })
        #expect(InboxRules.isSortedByAutoAdd(
            inPlaylists: Set(inPlaylists.compactMap { ids[$0] }),
            podcastPlaylists: Set(podcastPlaylists.compactMap { ids[$0] })) == sorted)
    }

    @Test(arguments: [InboxArrival.refresh, .subscribe, .opmlImport])
    func noCandidatesNothingEnters(arrival: InboxArrival) {
        #expect(InboxRules.entering([], arrival: arrival, now: Self.now).isEmpty)
    }

    /// The OPML import fills the library, not the inbox.
    @Test func opmlImportBringsNothing() {
        let ids = InboxRules.entering([candidate(publishedDaysAgo: 0), candidate(publishedDaysAgo: 1)], arrival: .opmlImport, now: Self.now)
        #expect(ids.isEmpty)
    }

    // MARK: Open, done, discarded (A50, N46, N49)

    /// `handled`: landed in a playlist (auto-add, by hand, notification action), went to Up
    /// Next ("Als Nächstes" / "Am Ende"), started playing, or was marked played. Only an open
    /// episode can be discarded; done stays done (it is stored, N40) and discarded stays out.
    @Test(arguments: [
        (InboxState.open, InboxEvent.handled, InboxState.done),
        (.open, .discarded, .discarded),
        (.done, .handled, .done),
        (.done, .discarded, .done),
        (.discarded, .handled, .discarded),
        (.discarded, .discarded, .discarded),
    ])
    func stateAfterEvent(from: InboxState, event: InboxEvent, to: InboxState) {
        #expect(InboxRules.state(from, after: event) == to)
    }

    // MARK: Shown (A48, A58, N74)

    /// 14 days from arriving in the inbox, also under "Gerade erledigt"; afterwards only in the podcast.
    @Test(arguments: [(0.0, true), (13.9, true), (14.0, false), (20.0, false)])
    func episodeStaysFourteenDaysFromArriving(addedDaysAgo: Double, shown: Bool) {
        let id = EpisodeID()
        #expect(InboxRules.isShown(episode(publishedDaysAgo: 30, addedDaysAgo: addedDaysAgo), now: Self.now) == shown)
        let done = episode(id, publishedDaysAgo: 30, addedDaysAgo: addedDaysAgo, state: .done)
        #expect(InboxRules.recentlyDone([done], seenOpen: [id], filter: .all, now: Self.now).map(\.id) == (shown ? [id] : []))
    }

    /// N74: the inbox shows only open episodes; done ones leave it.
    @Test func doneEpisodeLeavesTheInbox() {
        #expect(!InboxRules.isShown(episode(state: .done), now: Self.now))
    }

    @Test func cutoffIsFourteenDaysAgo() {
        #expect(InboxRules.cutoff(now: Self.now) == Self.daysAgo(14))
    }

    @Test func discardedEpisodeLeavesAtOnce() {
        #expect(!InboxRules.isShown(episode(addedDaysAgo: 0, state: .discarded), now: Self.now))
    }

    @Test func episodesOfUnsubscribedPodcastsAreNotShown() {
        #expect(!InboxRules.isShown(episode(subscribed: false), now: Self.now))
    }

    /// Equal dates keep the order they come in (the service fetches them in feed order).
    @Test func equalDatesKeepTheirOrder() {
        let (a, b, c) = (EpisodeID(), EpisodeID(), EpisodeID())
        let shown = InboxRules.shown(
            [episode(a, publishedDaysAgo: 1), episode(b, publishedDaysAgo: 1), episode(c, publishedDaysAgo: 1)],
            filter: .all, now: Self.now)
        #expect(shown.map(\.id) == [a, b, c])
    }

    /// N53: newest first by publication date, not by arrival.
    @Test func newestEpisodeFirst() {
        let (a, b, c) = (EpisodeID(), EpisodeID(), EpisodeID())
        let shown = InboxRules.shown(
            [episode(a, publishedDaysAgo: 3, addedDaysAgo: 0), episode(b, publishedDaysAgo: 1),
             episode(c, publishedDaysAgo: 2, addedDaysAgo: 2)],
            filter: .all, now: Self.now)
        #expect(shown.map(\.id) == [b, c, a])
    }

    @Test func shownLeavesOutExpiredDoneDiscardedAndUnsubscribed() {
        let kept = EpisodeID()
        let shown = InboxRules.shown(
            [episode(kept), episode(addedDaysAgo: 15), episode(state: .done), episode(state: .discarded),
             episode(subscribed: false)],
            filter: .all, now: Self.now)
        #expect(shown.map(\.id) == [kept])
    }

    // MARK: "Gerade erledigt" (N74, A67)

    /// Done episodes that were seen open in this session, newest first; never discarded ones
    /// (N77), never done ones that were not seen open (e.g. sorted by auto-add), never open ones.
    @Test func recentlyDoneAreTheDoneOnesSeenOpen() {
        let (a, b, notSeen, discarded, open) = (EpisodeID(), EpisodeID(), EpisodeID(), EpisodeID(), EpisodeID())
        let all = [
            episode(a, publishedDaysAgo: 3, state: .done),
            episode(notSeen, publishedDaysAgo: 2, state: .done),
            episode(discarded, publishedDaysAgo: 2, state: .discarded),
            episode(open, publishedDaysAgo: 2),
            episode(b, publishedDaysAgo: 1, state: .done),
        ]
        let done = InboxRules.recentlyDone(all, seenOpen: [a, b, discarded, open], filter: .all, now: Self.now)
        #expect(done.map(\.id) == [b, a])
    }

    /// The filter works below as well (A67), also for hidden podcasts (N65).
    @Test func recentlyDoneRespectsTheFilter() {
        let (sport, kids) = (PlaylistID(), PlaylistID())
        let (s, k, none) = (EpisodeID(), EpisodeID(), EpisodeID())
        let all = [
            episode(s, publishedDaysAgo: 1, state: .done, playlists: [sport]),
            episode(k, publishedDaysAgo: 2, state: .done, playlists: [kids], hidden: true),
            episode(none, publishedDaysAgo: 3, state: .done),
        ]
        let seen: Set = [s, k, none]
        #expect(InboxRules.recentlyDone(all, seenOpen: seen, filter: .all, now: Self.now).map(\.id) == [s, none])
        #expect(InboxRules.recentlyDone(all, seenOpen: seen, filter: .playlist(sport), now: Self.now).map(\.id) == [s])
        #expect(InboxRules.recentlyDone(all, seenOpen: seen, filter: .playlist(kids), now: Self.now).map(\.id) == [k])
        #expect(InboxRules.recentlyDone(all, seenOpen: seen, filter: .withoutPlaylist, now: Self.now).map(\.id) == [none])
    }

    @Test func recentlyDoneLeavesOutUnsubscribedPodcasts() {
        let id = EpisodeID()
        #expect(InboxRules.recentlyDone(
            [episode(id, state: .done, subscribed: false)], seenOpen: [id], filter: .all, now: Self.now).isEmpty)
    }

    // MARK: Filter (A56)

    /// Like the library: "Sport" = episodes of podcasts assigned to Sport; "Ohne Playlist" =
    /// episodes of podcasts without an assignment.
    @Test func filterWorksThroughThePodcastsAssignments() {
        let (sport, politics) = (PlaylistID(), PlaylistID())
        let (s, sp, p, none) = (EpisodeID(), EpisodeID(), EpisodeID(), EpisodeID())
        let all = [
            episode(s, publishedDaysAgo: 1, playlists: [sport]),
            episode(sp, publishedDaysAgo: 2, playlists: [sport, politics]),
            episode(p, publishedDaysAgo: 3, playlists: [politics]),
            episode(none, publishedDaysAgo: 4),
        ]
        #expect(InboxRules.shown(all, filter: .all, now: Self.now).map(\.id) == [s, sp, p, none])
        #expect(InboxRules.shown(all, filter: .playlist(sport), now: Self.now).map(\.id) == [s, sp])
        #expect(InboxRules.shown(all, filter: .playlist(politics), now: Self.now).map(\.id) == [sp, p])
        #expect(InboxRules.shown(all, filter: .withoutPlaylist, now: Self.now).map(\.id) == [none])
    }

    /// N65: episodes of a podcast whose playlists are all hidden are left out of "Alle" and
    /// show only under the hidden playlist's chip.
    @Test func hiddenPodcastsShowOnlyUnderTheirPlaylist() {
        let kids = PlaylistID()
        let (visible, hidden) = (EpisodeID(), EpisodeID())
        let all = [
            episode(visible, publishedDaysAgo: 1),
            episode(hidden, publishedDaysAgo: 2, playlists: [kids], hidden: true),
        ]
        #expect(InboxRules.shown(all, filter: .all, now: Self.now).map(\.id) == [visible])
        #expect(InboxRules.shown(all, filter: .playlist(kids), now: Self.now).map(\.id) == [hidden])
    }

    // MARK: Number on the tab (N41, N47, A60)

    /// Only open episodes that arrived since the last visit of the tab; done ones (auto-add)
    /// never count.
    @Test func newCountCountsOpenEpisodesSinceTheLastVisit() {
        let lastVisit = Self.daysAgo(2)
        let all = [
            episode(addedDaysAgo: 1),
            episode(addedDaysAgo: 0.5),
            episode(addedDaysAgo: 1, state: .done),
            episode(addedDaysAgo: 1, state: .discarded),
            episode(addedDaysAgo: 3),
            episode(addedDaysAgo: 1, subscribed: false),
        ]
        #expect(InboxRules.newCount(all, lastVisit: lastVisit, now: Self.now) == 2)
    }

    @Test func newCountWithoutAVisitCountsAllShownOpenEpisodes() {
        let all = [episode(addedDaysAgo: 1), episode(addedDaysAgo: 10), episode(addedDaysAgo: 15), episode(state: .done)]
        #expect(InboxRules.newCount(all, lastVisit: nil, now: Self.now) == 2)
    }

    /// N65: the number counts what "Alle" shows, so hidden podcasts do not count.
    @Test func newCountLeavesOutHiddenPodcasts() {
        let all = [episode(), episode(playlists: [PlaylistID()], hidden: true)]
        #expect(InboxRules.newCount(all, lastVisit: nil, now: Self.now) == 1)
    }

    @Test func episodeArrivingAtTheMomentOfTheVisitDoesNotCount() {
        let lastVisit = Self.daysAgo(1)
        #expect(InboxRules.newCount([episode(addedDaysAgo: 1)], lastVisit: lastVisit, now: Self.now) == 0)
    }

    // MARK: "Alle hinzufügen" (A59)

    /// Every shown open episode whose podcast has playlists, oldest first, so the playlists
    /// stay chronological (each one goes to the bottom).
    @Test func addAllTakesOpenEpisodesWithPlaylistsOldestFirst() {
        let sport = PlaylistID()
        let (new, old, middle) = (EpisodeID(), EpisodeID(), EpisodeID())
        let shown = InboxRules.shown(
            [
                episode(new, publishedDaysAgo: 1, playlists: [sport]),
                episode(old, publishedDaysAgo: 5, playlists: [sport]),
                episode(publishedDaysAgo: 2, state: .done, playlists: [sport]),
                episode(publishedDaysAgo: 3),
                episode(middle, publishedDaysAgo: 3, playlists: [sport]),
            ],
            filter: .all, now: Self.now)
        #expect(InboxRules.episodesToAddAll(shown) == [old, middle, new])
    }

    /// With a filter, "Alle hinzufügen" means the episodes on screen.
    @Test func addAllRespectsTheFilter() {
        let (sport, politics) = (PlaylistID(), PlaylistID())
        let s = EpisodeID()
        let shown = InboxRules.shown(
            [episode(s, playlists: [sport]), episode(playlists: [politics])], filter: .playlist(sport), now: Self.now)
        #expect(InboxRules.episodesToAddAll(shown) == [s])
    }

    // MARK: "Rest aussortieren" (N78, A69)

    /// Every shown open episode, also those of podcasts without a playlist.
    @Test func discardAllTakesEveryShownOpenEpisode() {
        let (a, b) = (EpisodeID(), EpisodeID())
        let shown = InboxRules.shown(
            [episode(a, playlists: [PlaylistID()]), episode(b), episode(state: .done), episode(state: .discarded)],
            filter: .all, now: Self.now)
        #expect(InboxRules.episodesToDiscardAll(shown) == [a, b])
    }

    /// With a filter only the episodes on screen; under "Alle" not those of hidden podcasts (N65).
    @Test func discardAllRespectsTheFilter() {
        let (sport, kids) = (PlaylistID(), PlaylistID())
        let (s, none, k) = (EpisodeID(), EpisodeID(), EpisodeID())
        let all = [
            episode(s, publishedDaysAgo: 1, playlists: [sport]), episode(none, publishedDaysAgo: 2),
            episode(k, publishedDaysAgo: 3, playlists: [kids], hidden: true),
        ]
        #expect(InboxRules.episodesToDiscardAll(InboxRules.shown(all, filter: .playlist(sport), now: Self.now)) == [s])
        #expect(InboxRules.episodesToDiscardAll(InboxRules.shown(all, filter: .all, now: Self.now)) == [s, none])
    }
}
