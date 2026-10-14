import Foundation
import Testing
@testable import PodlistKit

private let sport = PlaylistID()
private let news = PlaylistID()
private let kids = PlaylistID()
private let secret = PlaylistID()

// Hidden playlists (concept §4.1, N65): a podcast is left out of "Alle" only when every one of
// its playlists is hidden; a visible playlist wins.
struct HiddenPlaylistsTests {
    @Test(arguments: [
        ([kids], true),
        ([kids, secret], true),
        ([kids, sport], false),
        ([sport], false),
        ([sport, news], false),
        ([], false),
    ] as [(Set<PlaylistID>, Bool)])
    func podcastIsHiddenOnlyWhenAllItsPlaylistsAreHidden(playlists: Set<PlaylistID>, hidden: Bool) {
        #expect(HiddenPlaylists.hidesPodcast(in: playlists, hidden: [kids, secret]) == hidden)
    }

    @Test func withoutHiddenPlaylistsNothingIsHidden() {
        #expect(!HiddenPlaylists.hidesPodcast(in: [sport], hidden: []))
    }
}

// "Mehr ›" (N66): hidden playlists wait behind the button, in their order; the ones pinned
// (already chosen when a sheet opened) always show where they are.
struct HiddenPlaylistsSplitTests {
    private let list: [(id: PlaylistID, isHidden: Bool)] = [
        (sport, false), (kids, true), (news, false), (secret, true),
    ]

    @Test func hiddenPlaylistsGoBehindTheButton() {
        let split = HiddenPlaylists.split(list)
        #expect(split.shown == [sport, news])
        #expect(split.behindMore == [kids, secret])
    }

    @Test func pinnedHiddenPlaylistsStayInPlace() {
        let split = HiddenPlaylists.split(list, pinned: [secret, sport])
        #expect(split.shown == [sport, news, secret])
        #expect(split.behindMore == [kids])
    }

    @Test func withoutHiddenPlaylistsNothingIsBehindTheButton() {
        let split = HiddenPlaylists.split([(sport, false), (news, false)])
        #expect(split.shown == [sport, news])
        #expect(split.behindMore.isEmpty)
    }
}
