import Foundation
import Testing
@testable import PodlistKit

private let sport = PlaylistID()
private let politics = PlaylistID()
private let kids = PlaylistID()
private let lage = PodcastID()
private let matze = PodcastID()

private func episode(_ title: String, of podcast: PodcastID = lage, played: Bool = false) -> EpisodeInfo {
    EpisodeInfo(
        podcastID: podcast, podcastTitle: podcast == lage ? "Lage der Nation" : "Hotel Matze", title: title,
        publishedAt: Date(timeIntervalSinceReferenceDate: 0),
        playedAt: played ? Date(timeIntervalSinceReferenceDate: 1) : nil)
}

private func source(_ episode: EpisodeInfo, in playlist: PlaylistID, addedAt seconds: TimeInterval = 0) -> Everything.Source {
    Everything.Source(
        entry: PlaylistEntryInfo(episode: episode, position: 7, addedAt: Date(timeIntervalSinceReferenceDate: seconds)),
        playlist: playlist)
}

// The playlist "Alles" (concept §4.1, N70–N73): every episode of the other playlists, once,
// without the playlists and podcasts left out.
struct EverythingTests {
    // N71: left out only when none of its playlists is still chosen (sichtbar gewinnt);
    // a podcast left out is always out.
    @Test(arguments: [
        ([sport], false, true),
        ([sport, politics], false, true),
        ([politics], false, false),
        ([politics, kids], false, false),
        ([sport], true, false),
        ([], false, false),
    ] as [(Set<PlaylistID>, Bool, Bool)])
    func episodeBelongsToEverythingWhileOneOfItsPlaylistsIsChosen(playlists: Set<PlaylistID>, podcastIsExcluded: Bool, includes: Bool) {
        #expect(Everything.includes(
            inPlaylists: playlists, excludedPlaylists: [politics, kids], podcastIsExcluded: podcastIsExcluded) == includes)
    }

    // N97: "Hinzugefügt" is the latest of its entries in a chosen playlist.
    @Test func eachEpisodeOnceWithTheLatestAddedOfItsChosenPlaylists() {
        let a = episode("A")
        let b = episode("B", of: matze)
        let entries = Everything.entries(
            [source(a, in: sport, addedAt: 10), source(a, in: politics, addedAt: 30), source(a, in: kids, addedAt: 20),
             source(b, in: kids, addedAt: 5)],
            excludedPlaylists: [politics], excludedPodcasts: [])
        #expect(entries.map(\.episode.id) == [a.id, b.id])
        #expect(entries.first?.addedAt == Date(timeIntervalSinceReferenceDate: 20), "politics is left out, kids is the latest chosen")
    }

    @Test func playlistsAndPodcastsLeftOutAreMissing() {
        let a = episode("A")
        let b = episode("B", of: matze)
        let c = episode("C")
        let entries = Everything.entries(
            [source(a, in: politics), source(b, in: sport), source(c, in: sport), source(c, in: politics)],
            excludedPlaylists: [politics], excludedPodcasts: [matze])
        #expect(entries.map(\.episode.id) == [c.id])
    }

    @Test func entriesHaveNoOwnPosition() {
        let entries = Everything.entries([source(episode("A"), in: sport)], excludedPlaylists: [], excludedPodcasts: [])
        #expect(entries.first?.position == 0, "no manual sort in Alles (A64)")
    }

    // N99: Alles always removes played episodes.
    @Test func onlyUnplayedEpisodesShow() {
        let entries = Everything.entries(
            [source(episode("A"), in: sport), source(episode("B", played: true), in: sport)],
            excludedPlaylists: [], excludedPodcasts: [])
        #expect(Everything.shown(entries).map(\.episode.title) == ["A"])
    }

    // N97: one fixed sort, newest added first.
    @Test func sortIsFixedToNewestAddedFirst() {
        #expect(Everything.sort == .added)
        #expect(!Everything.sortAscending)
    }
}
