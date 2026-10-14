import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Integration tests for playlists, assignments and entries (concept §4.1–4.3).
@MainActor
struct PlaylistServiceTests {
    private let container: ModelContainer
    private let service: PlaylistService
    private let library: LibraryService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        service = PlaylistService(context: container.mainContext, now: { PlaylistServiceTests.now })
        library = LibraryService(container: container, now: { PlaylistServiceTests.now })
    }

    // MARK: Playlists

    @Test func newPlaylistIsManualRemovesPlayedAndGoesLast() throws {
        try service.insertDefaultPlaylists()
        let playlist = try service.createPlaylist(name: "  Krimi ", colorKey: "purple", symbolName: "magnifyingglass")
        #expect(playlist.customName == "Krimi")
        #expect(playlist.sort == .manual)
        #expect(playlist.playedPolicy == .remove)
        #expect(playlist.autoDownload, "auto-download is on by default (N89)")
        let last = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.displayOrder)])).last
        #expect(last == playlist)
    }

    /// N89: the default playlists and "Alles" download automatically from the start.
    @Test func defaultPlaylistsAndEverythingDownloadAutomatically() throws {
        try service.insertDefaultPlaylists()
        try service.ensureEverything()
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.everything != nil)
        #expect(playlists.allSatisfy { $0.autoDownload })
    }

    /// Once after the update (N89): every existing playlist, "Alles" too, downloads automatically.
    @Test func turningAutoDownloadOnForAllPlaylists() throws {
        try service.insertDefaultPlaylists()
        try service.ensureEverything()
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        for playlist in playlists { try service.setAutoDownload(false, of: playlist) }
        #expect(playlists.allSatisfy { !$0.autoDownload }, "\"Alles\" can turn it off too")

        try service.turnOnAutoDownloadForAllPlaylists()
        #expect(playlists.allSatisfy { $0.autoDownload })
    }

    @Test func updatingADefaultPlaylistWithoutNameKeepsTheTranslatedName() throws {
        try service.insertDefaultPlaylists()
        let news = try playlist(key: "news")
        try service.update(news, customName: "Aktuelles", colorKey: "pink", symbolName: "star")
        #expect(news.customName == "Aktuelles" && news.colorKey == "pink" && news.symbolName == "star")
        try service.update(news, customName: "   ", colorKey: "pink", symbolName: "star")
        #expect(news.customName == nil)
        #expect(news.systemKey == "news")
    }

    @Test func movingPlaylistsChangesTheirDisplayOrder() throws {
        try service.insertDefaultPlaylists()
        let ordered = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.displayOrder)]))
        try service.movePlaylists(ordered, fromOffsets: [0], toOffset: 3)
        let after = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.displayOrder)]))
        #expect(after.compactMap(\.systemKey).prefix(3) == ["politics", "sports", "news"])
    }

    /// N65: a podcast is hidden from "Alle" once all of its playlists are hidden; a visible
    /// playlist wins, and a podcast without playlists stays visible.
    @Test func hidingPlaylistsHidesPodcastsWhosePlaylistsAreAllHidden() throws {
        try service.insertDefaultPlaylists()
        let (news, sports) = (try playlist(key: "news"), try playlist(key: "sports"))
        let (onlyNews, _) = insertPodcast(episodes: 0)
        let (both, _) = insertPodcast(episodes: 0)
        let (none, _) = insertPodcast(episodes: 0)
        try service.assign(onlyNews, to: news, autoAdd: .off)
        try service.assign(both, to: news, autoAdd: .off)
        try service.assign(both, to: sports, autoAdd: .off)
        #expect(!news.isHidden, "playlists start visible")

        try service.setHidden(true, of: news)
        #expect(news.isHidden)
        #expect(onlyNews.isHiddenFromAll)
        #expect(!both.isHiddenFromAll)
        #expect(!none.isHiddenFromAll)

        try service.setHidden(true, of: sports)
        #expect(both.isHiddenFromAll)

        try service.setHidden(false, of: news)
        #expect(!onlyNews.isHiddenFromAll)
    }

    @Test func deletingAPlaylistKeepsEpisodesAndPodcasts() throws {
        let (podcast, episodes) = insertPodcast(episodes: 2)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try service.assign(podcast, to: list, autoAdd: .bottom)
        try service.add(episodes[0], to: list)
        try service.delete(list)
        #expect(try context.fetchCount(FetchDescriptor<Playlist>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistAssignment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 2)
    }

    // MARK: Assignments (concept §4.1)

    /// N93: assigning adds no existing episode, whatever the rule; only future episodes come
    /// in by auto-add, existing ones only by hand.
    @Test(arguments: [AutoAddRule.off, .top, .bottom])
    func assigningAddsNoExistingEpisode(rule: AutoAddRule) throws {
        let (podcast, _) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try service.assign(podcast, to: list, autoAdd: rule)
        #expect(list.assignments?.first?.autoAdd == rule)
        #expect(list.entries?.isEmpty ?? true)

        // Assigning again only changes the rule.
        try service.assign(podcast, to: list, autoAdd: .top)
        #expect(list.assignments?.count == 1)
        #expect(list.assignments?.first?.autoAdd == .top)
        #expect(list.entries?.isEmpty ?? true)
    }

    @Test func settingAssignmentsReplacesThemAndKeepsEntries() throws {
        let (podcast, episodes) = insertPodcast(episodes: 1)
        let a = try service.createPlaylist(name: "A", colorKey: "blue", symbolName: "star")
        let b = try service.createPlaylist(name: "B", colorKey: "blue", symbolName: "star")
        try service.setAssignments(of: podcast, to: [a.uuid: .bottom])
        #expect(a.entries?.isEmpty ?? true, "no existing episode comes in (N93)")
        try service.add(episodes[0], to: a)

        try service.setAssignments(of: podcast, to: [b.uuid: .top])
        #expect(a.assignments?.isEmpty ?? true)
        #expect(a.sortedEntries.compactMap(\.episode) == episodes, "unassigning keeps the entries")
        #expect(b.assignments?.first?.autoAdd == .top)
        #expect(b.entries?.isEmpty ?? true)
    }

    // MARK: Entries (concept §4.2, §4.5)

    @Test func addingByHandAppendsOnceAtTheBottom() throws {
        let (_, episodes) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try service.add(episodes[2], to: list)
        try service.add(episodes[0], to: list)
        try service.add(episodes[2], to: list)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[2], episodes[0]])
        #expect(list.sortedEntries.allSatisfy { $0.origin == .manual && $0.addedAt == Self.now })
    }

    /// N34: "Zu Playlists hinzufügen" in a notification.
    @Test func addingToAssignedPlaylistsAddsWhereTheEpisodeIsMissing() throws {
        let (podcast, episodes) = insertPodcast(episodes: 2)
        let off = try service.createPlaylist(name: "Off", colorKey: "blue", symbolName: "star")
        let auto = try service.createPlaylist(name: "Auto", colorKey: "blue", symbolName: "star")
        let other = try service.createPlaylist(name: "Other", colorKey: "blue", symbolName: "star")
        try service.add(episodes[0], to: off)
        try service.setAssignments(of: podcast, to: [off.uuid: .off, auto.uuid: .bottom])
        try service.add(episodes[1], to: auto)

        try service.addToAssignedPlaylists(episodes[1])
        #expect(off.sortedEntries.compactMap(\.episode) == [episodes[0], episodes[1]], "at the bottom")
        #expect(off.sortedEntries.last?.origin == .manual)
        #expect(auto.sortedEntries.compactMap(\.episode) == [episodes[1]], "once")
        #expect(other.entries?.isEmpty ?? true)
    }

    @Test func addingAPlayedEpisodeToARemovePlaylistMakesItUnplayed() throws {
        let (_, episodes) = insertPodcast(episodes: 1)
        try library.markPlayed(episodes[0])
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try service.add(episodes[0], to: list)
        #expect(!episodes[0].isPlayed, "A14: otherwise the played policy would hide it at once")
        #expect(list.entries?.count == 1)
    }

    @Test func removingByHandMovesTheCursorOn() throws {
        let (_, episodes) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        list.resumeEpisode = episodes[1]
        try service.remove(episodes[1], from: list)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[0], episodes[2]])
        #expect(list.resumeEpisode == episodes[2], "concept §4.4: the playlist keeps its place")
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 3)
    }

    @Test func movingEntriesByHand() throws {
        let (_, episodes) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        try service.moveEntries(of: list, fromOffsets: [2], toOffset: 0)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[2], episodes[0], episodes[1]])
    }

    /// N96: dragging in a sorted playlist switches it to manual, starting from what it showed.
    @Test func movingEntriesInASortedPlaylistSwitchesItToManual() throws {
        let (_, episodes) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        try service.setSort(.published, ascending: false, of: list)  // E2, E1, E0
        try service.moveEntries(of: list, fromOffsets: [2], toOffset: 1)
        #expect(list.sort == .manual)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[2], episodes[0], episodes[1]])
    }

    /// The list shows only part of the playlist ("Gespielte ausblenden", a podcast section):
    /// the offsets refer to what it shows, the others keep their place.
    @Test func movingEntriesAmongTheShownOnes() throws {
        let (_, episodes) = insertPodcast(episodes: 4)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        let shown = [episodes[0], episodes[2], episodes[3]]  // E1 is hidden
        try service.moveEntries(of: list, shown: shown, fromOffsets: [2], toOffset: 1)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[0], episodes[1], episodes[3], episodes[2]])
        try service.moveEntries(of: list, shown: [episodes[0], episodes[3], episodes[2]], fromOffsets: [0], toOffset: 3)
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[1], episodes[3], episodes[2], episodes[0]])
    }

    @Test func switchingToManualKeepsTheVisibleOrder() throws {
        let (_, episodes) = insertPodcast(episodes: 3)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        try service.setSort(.published, ascending: false, of: list)
        let visible = list.sortedEntries.compactMap(\.episode)
        #expect(visible == episodes.reversed())

        try service.setSort(.manual, ascending: true, of: list)
        #expect(list.sortedEntries.compactMap(\.episode) == visible, "nothing jumps (concept §4.2)")
    }

    // MARK: Played policy (concept §4.3)

    @Test func markingPlayedRemovesFromRemovePlaylistsOnly() throws {
        let (_, episodes) = insertPodcast(episodes: 2)
        let remove = try service.createPlaylist(name: "R", colorKey: "blue", symbolName: "star")
        let keep = try service.createPlaylist(name: "K", colorKey: "blue", symbolName: "star")
        try service.setPlayedPolicy(.keep, of: keep)
        for list in [remove, keep] { for episode in episodes { try service.add(episode, to: list) } }
        remove.resumeEpisode = episodes[0]

        try library.markPlayed(episodes[0])
        #expect(remove.sortedEntries.compactMap(\.episode) == [episodes[1]])
        #expect(remove.resumeEpisode == episodes[1], "the cursor moves on before the removal")
        #expect(keep.sortedEntries.compactMap(\.episode) == episodes)
    }

    @Test func theEpisodeInThePlayerStaysUntilItLeavesThePlayer() throws {
        let (_, episodes) = insertPodcast(episodes: 2)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        for episode in episodes { try service.add(episode, to: list) }
        let upNext = UpNextService(context: context, library: library, player: PlayerController(library: library))
        upNext.play(episodes[0])

        try library.markPlayed(episodes[0])
        #expect(list.entries?.count == 2, "the playing episode is never removed")

        upNext.play(episodes[1])
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[1]])
    }

    @Test func switchingToRemoveKeepsPlayedEntriesUntilTheyArePlayedAgain() throws {
        let (_, episodes) = insertPodcast(episodes: 2)
        let list = try service.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try service.setPlayedPolicy(.keep, of: list)
        for episode in episodes { try service.add(episode, to: list) }
        try library.markPlayed(episodes[0])
        #expect(list.entries?.count == 2)

        try service.setPlayedPolicy(.remove, of: list)
        #expect(list.sortedEntries.compactMap(\.episode) == episodes, "A15: nothing disappears at once")

        try library.markPlayed(episodes[0])
        #expect(list.sortedEntries.compactMap(\.episode) == [episodes[1]])
    }

    @Test func addingToAKeepPlaylistLeavesThePlayedStatus() throws {
        let (_, episodes) = insertPodcast(episodes: 1)
        try library.markPlayed(episodes[0])
        let list = try service.createPlaylist(name: "K", colorKey: "blue", symbolName: "star")
        try service.setPlayedPolicy(.keep, of: list)
        try service.add(episodes[0], to: list)
        #expect(episodes[0].isPlayed)
    }

    // MARK: Helpers

    private func playlist(key: String) throws -> Playlist {
        try #require(try context.fetch(FetchDescriptor<Playlist>()).first { $0.systemKey == key })
    }

    /// A podcast with episodes, oldest first.
    private func insertPodcast(episodes count: Int) -> (Podcast, [Episode]) {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "P", subscribedAt: Self.now)
        context.insert(podcast)
        let episodes = (0..<count).map { index in
            let episode = Episode(
                guid: "\(index)", title: "E\(index)", publishedAt: Self.now.addingTimeInterval(Double(index) * 86_400),
                audioURL: URL(string: "https://example.com/\(index).mp3")!)
            context.insert(episode)
            episode.podcast = podcast
            return episode
        }
        return (podcast, episodes)
    }
}
