import Foundation
import Testing
@testable import PodlistKit

private let sport = PlaylistID()
private let news = PlaylistID()
private let kids = PlaylistID()
private let empty = PlaylistID()

// Settings → Benachrichtigungen (N87): the podcasts nested under their playlists, visible ones
// in "Alle", hidden ones behind "Mehr ›"; a group's switch is on only when all its podcasts are.
struct NotificationGroupsTests {
    private let playlists: [(id: PlaylistID, isHidden: Bool)] = [(sport, false), (kids, true), (news, false), (empty, false)]

    private func podcast(_ title: String, _ playlists: Set<PlaylistID>, isOn: Bool = true) -> NotificationPodcast {
        NotificationPodcast(id: PodcastID(), title: title, isOn: isOn, playlists: playlists)
    }

    @Test func visiblePlaylistsInOrderThenWithoutPlaylistHiddenOnesApart() {
        let a = podcast("Anna", [sport])
        let b = podcast("Bert", [news])
        let c = podcast("Cleo", [kids])
        let d = podcast("Dora", [])
        let groups = NotificationGroups.groups(podcasts: [d, c, b, a], playlists: playlists)

        #expect(groups.shown.map(\.id) == [.playlist(sport), .playlist(news), .withoutPlaylist])
        #expect(groups.hidden.map(\.id) == [.playlist(kids)])
        #expect(groups.shown.map(\.podcasts) == [[a.id], [b.id], [d.id]])
        #expect(groups.hidden.map(\.podcasts) == [[c.id]])
    }

    @Test func playlistsWithoutPodcastsAreLeftOut() {
        let groups = NotificationGroups.groups(podcasts: [podcast("Anna", [sport])], playlists: playlists)
        #expect(groups.shown.map(\.id) == [.playlist(sport)], "no empty news, empty or without-playlist group")
        #expect(groups.hidden.isEmpty)
    }

    /// A podcast in several playlists shows under each, visible or hidden.
    @Test func podcastInSeveralPlaylistsShowsUnderEach() {
        let a = podcast("Anna", [sport, news, kids])
        let groups = NotificationGroups.groups(podcasts: [a], playlists: playlists)
        #expect(groups.shown.map(\.id) == [.playlist(sport), .playlist(news)])
        #expect(groups.hidden.map(\.id) == [.playlist(kids)])
        #expect((groups.shown + groups.hidden).allSatisfy { $0.podcasts == [a.id] })
    }

    @Test func podcastsAreSortedByTitle() {
        let b = podcast("bert", [sport])
        let a = podcast("Anna", [sport])
        let c = podcast("Cäsar 10", [sport])
        let c2 = podcast("Cäsar 9", [sport])
        let group = NotificationGroups.groups(podcasts: [c, b, c2, a], playlists: playlists).shown[0]
        #expect(group.podcasts == [a.id, b.id, c2.id, c.id])
    }

    @Test(arguments: [
        ([true, true, true], NotificationGroupState.on),
        ([false, false], .off),
        ([true, false, true], .mixed(on: 2, of: 3)),
        ([false, true], .mixed(on: 1, of: 2)),
    ] as [([Bool], NotificationGroupState)])
    func stateIsOnOnlyWhenAllPodcastsAreOn(values: [Bool], state: NotificationGroupState) {
        let podcasts = values.enumerated().map { podcast("P\($0.offset)", [sport], isOn: $0.element) }
        #expect(NotificationGroups.groups(podcasts: podcasts, playlists: playlists).shown[0].state == state)
    }

    @Test func membersOfAGroup() {
        let a = podcast("Anna", [sport, kids])
        let b = podcast("Bert", [])
        let c = podcast("Cleo", [news])
        #expect(NotificationGroups.members(of: .playlist(sport), among: [a, b, c]) == [a.id])
        #expect(NotificationGroups.members(of: .playlist(kids), among: [a, b, c]) == [a.id])
        #expect(NotificationGroups.members(of: .withoutPlaylist, among: [a, b, c]) == [b.id])
    }
}
