import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Settings → Benachrichtigungen (N87): the switch of a playlist (or of the podcasts without
/// one) sets all its podcasts and can be undone, one step; the main switch pauses every
/// notification and keeps each podcast's value.
@MainActor
struct NotificationSettingsTests {
    private let container: ModelContainer
    private let settings: UserDefaults
    private let center: FakeNotificationCenter
    private let scheduler: NotificationScheduler
    private let playlists: PlaylistService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        try self.init(center: FakeNotificationCenter())
    }

    private init(center: FakeNotificationCenter) throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        settings = try #require(UserDefaults(suiteName: "NotificationSettingsTests-\(UUID().uuidString)"))
        self.center = center
        scheduler = NotificationScheduler(context: container.mainContext, center: center, settings: settings, now: { Self.now })
        playlists = PlaylistService(context: container.mainContext, now: { Self.now })
    }

    // MARK: Groups

    /// A podcast has one switch: a playlist's switch changes it under its other playlists too.
    @Test func playlistSwitchSetsAllItsPodcastsAlsoInOtherPlaylists() throws {
        let sport = try playlist("Sport")
        let news = try playlist("News")
        let a = try podcast("A", in: [sport, news])
        let b = try podcast("B", in: [sport])
        let c = try podcast("C", in: [news])
        let outside = try podcast("D", in: [])

        try scheduler.setNotificationsEnabled(false, for: .playlist(sport.playlistID))
        #expect(!a.notificationsEnabled && !b.notificationsEnabled)
        #expect(c.notificationsEnabled && outside.notificationsEnabled)

        try scheduler.setNotificationsEnabled(true, for: .playlist(news.playlistID))
        #expect(a.notificationsEnabled && c.notificationsEnabled)
        #expect(!b.notificationsEnabled)
    }

    @Test func withoutPlaylistSetsOnlyPodcastsWithoutAPlaylist() throws {
        let sport = try playlist("Sport")
        let tagged = try podcast("A", in: [sport])
        let loose = try podcast("B", in: [])
        let unsubscribed = try podcast("C", in: [])
        unsubscribed.isSubscribed = false

        try scheduler.setNotificationsEnabled(false, for: .withoutPlaylist)
        #expect(tagged.notificationsEnabled)
        #expect(!loose.notificationsEnabled)
        #expect(unsubscribed.notificationsEnabled, "only subscribed podcasts are in the settings")
    }

    // MARK: Undo

    /// Undo restores each podcast's own value, not the opposite of the switch.
    @Test(arguments: [true, false])
    func undoRestoresEachPodcastsFormerValue(isOn: Bool) throws {
        let sport = try playlist("Sport")
        let a = try podcast("A", in: [sport])
        let b = try podcast("B", in: [sport], isOn: false)
        let c = try podcast("C", in: [sport])

        try scheduler.setNotificationsEnabled(isOn, for: .playlist(sport.playlistID))
        let change = try #require(scheduler.undoableChange)
        #expect(change.kind == .group(.playlist(sport.playlistID)))
        #expect(change.isOn == isOn)

        try scheduler.undo()
        #expect(a.notificationsEnabled && !b.notificationsEnabled && c.notificationsEnabled)
        #expect(scheduler.undoableChange == nil)
    }

    /// One step: a newer change replaces the former, and undo works once.
    @Test func onlyTheLastChangeCanBeUndone() throws {
        let sport = try playlist("Sport")
        let news = try playlist("News")
        let a = try podcast("A", in: [sport])
        let b = try podcast("B", in: [news])

        try scheduler.setNotificationsEnabled(false, for: .playlist(sport.playlistID))
        try scheduler.setNotificationsEnabled(false, for: .playlist(news.playlistID))
        try scheduler.undo()
        try scheduler.undo()
        #expect(!a.notificationsEnabled, "the former change stays")
        #expect(b.notificationsEnabled)
    }

    /// A podcast's own switch is no group change: it shows no undo and ends the one showing,
    /// so undo never overwrites it.
    @Test func podcastSwitchEndsTheUndo() throws {
        let sport = try playlist("Sport")
        let a = try podcast("A", in: [sport])
        let b = try podcast("B", in: [sport])

        try scheduler.setNotificationsEnabled(false, for: .playlist(sport.playlistID))
        try scheduler.setNotificationsEnabled(true, for: b)
        #expect(scheduler.undoableChange == nil)
        try scheduler.undo()
        #expect(!a.notificationsEnabled)
        #expect(b.notificationsEnabled)
    }

    // MARK: Main switch

    @Test func mainSwitchKeepsEachPodcastsValueAndIsStored() throws {
        let a = try podcast("A", in: [])
        let b = try podcast("B", in: [], isOn: false)
        #expect(scheduler.isEnabled, "on by default")

        scheduler.setEnabled(false)
        #expect(!scheduler.isEnabled)
        #expect(a.notificationsEnabled && !b.notificationsEnabled)
        let relaunched = NotificationScheduler(context: context, center: center, settings: settings)
        #expect(!relaunched.isEnabled)

        scheduler.setEnabled(true)
        #expect(a.notificationsEnabled && !b.notificationsEnabled)
    }

    @Test func mainSwitchCanBeUndone() throws {
        scheduler.setEnabled(false)
        #expect(scheduler.undoableChange?.kind == .all)
        #expect(scheduler.undoableChange?.isOn == false)
        try scheduler.undo()
        #expect(scheduler.isEnabled)
    }

    @Test func mainSwitchOffPostsNothing() async throws {
        let a = try podcast("A", in: [])
        let episode = Episode(guid: "g", title: "New", publishedAt: Self.now, audioURL: URL(string: "https://cdn.invalid/g.mp3")!)
        episode.podcast = a
        context.insert(episode)
        try context.save()

        scheduler.setEnabled(false)
        await scheduler.notifyNewEpisodes([episode.uuid])
        #expect(center.posted.isEmpty)

        scheduler.setEnabled(true)
        await scheduler.notifyNewEpisodes([episode.uuid])
        #expect(center.posted.map(\.body) == ["New"])
    }

    /// A47: no prompt while everything is off; turning on asks.
    @Test func permissionIsAskedOnlyWhileTheMainSwitchIsOn() async throws {
        let test = try NotificationSettingsTests(center: FakeNotificationCenter(authorization: .notDetermined))
        try test.podcast("A", in: [])
        test.scheduler.setEnabled(false)
        await test.scheduler.requestAuthorizationIfNeeded()
        #expect(test.center.authorizationRequests == 0)

        test.scheduler.setEnabled(true)
        let clock = ContinuousClock()
        let giveUp = clock.now + .seconds(2)
        while test.center.authorizationRequests == 0, clock.now < giveUp { try await Task.sleep(for: .milliseconds(20)) }
        #expect(test.center.authorizationRequests == 1)
    }

    // MARK: Helpers

    private func playlist(_ name: String) throws -> Playlist {
        try playlists.createPlaylist(name: name, colorKey: "blue", symbolName: "star")
    }

    @discardableResult
    private func podcast(_ title: String, in playlists: [Playlist], isOn: Bool = true) throws -> Podcast {
        let podcast = Podcast(feedURL: URL(string: "https://example.invalid/\(title).xml")!, title: title, subscribedAt: Self.now)
        podcast.notificationsEnabled = isOn
        context.insert(podcast)
        for playlist in playlists { try self.playlists.assign(podcast, to: playlist, autoAdd: .off) }
        try context.save()
        return podcast
    }
}
