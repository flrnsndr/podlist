import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Integration tests for the SwiftData schema with an in-memory container (concept §5, §9 level 2).
@MainActor
struct SchemaTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
    }

    @Test(arguments: PodlistMigrationPlan.schemas.map { ObjectIdentifier($0) })
    func schemaIsCloudKitCompatible(_ version: ObjectIdentifier) throws {
        let versioned = try #require(PodlistMigrationPlan.schemas.first { ObjectIdentifier($0) == version })
        let schema = Schema(versionedSchema: versioned)
        for entity in schema.entities {
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) must be optional")
                #expect(relationship.inverseKeyPath != nil || relationship.inverseName != nil,
                        "\(entity.name).\(relationship.name) needs an inverse")
                #expect(relationship.deleteRule != .deny, "\(entity.name).\(relationship.name) must not deny")
            }
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) must not be unique")
            }
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) must not have #Unique")
        }
    }

    /// Florian's device has a SchemaV1 store (since Slice 1): it must open with the
    /// current schema and keep its data.
    @Test func storeFromSchemaV1OpensWithTheCurrentSchema() throws {
        let directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Podlist.store")
        do {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            let playlist = SchemaV1.Playlist(customName: "Krimi", colorKey: "red", symbolName: "star", displayOrder: 0)
            let episode = SchemaV1.Episode(guid: "g", title: "E", publishedAt: .distantPast, audioURL: URL(string: "https://example.com/e.mp3")!)
            context.insert(playlist)
            context.insert(episode)
            context.insert(SchemaV1.PlaylistEntry(playlist: playlist, episode: episode, position: 1, addedAt: .distantPast, origin: .manual))
            try context.save()
        }
        let container = try PodlistStore.makeContainer(url: url)
        let entries = try ModelContext(container).fetch(FetchDescriptor<PlaylistEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.playlist?.customName == "Krimi")
        #expect(entries.first?.episode?.title == "E")
        // A51: existing episodes were never in the inbox.
        #expect(entries.first?.episode?.inboxAddedAt == nil)
    }

    /// Slice 7 stores (SchemaV2) open with the listening log (SchemaV3) and keep their data;
    /// the log starts empty (N58).
    @Test func storeFromSchemaV2OpensWithTheCurrentSchema() throws {
        let directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Podlist.store")
        let addedAt = Date(timeIntervalSinceReferenceDate: 1000)
        do {
            let schema = Schema(versionedSchema: SchemaV2.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            let episode = SchemaV2.Episode(guid: "g", title: "E", publishedAt: .distantPast, audioURL: URL(string: "https://example.com/e.mp3")!)
            episode.inboxAddedAt = addedAt
            context.insert(episode)
            try context.save()
        }
        let container = try PodlistStore.makeContainer(url: url)
        let context = ModelContext(container)
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.map(\.title) == ["E"])
        #expect(episodes.first?.inboxAddedAt == addedAt)
        #expect(try context.fetchCount(FetchDescriptor<ListeningSession>()) == 0)
    }

    /// Slice 8 stores (SchemaV3) open with hidden playlists (SchemaV4) and keep their data;
    /// every playlist starts visible.
    @Test func storeFromSchemaV3OpensWithTheCurrentSchema() throws {
        let directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Podlist.store")
        do {
            let schema = Schema(versionedSchema: SchemaV3.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            context.insert(SchemaV3.Playlist(customName: "Krimi", colorKey: "red", symbolName: "star", displayOrder: 0))
            context.insert(SchemaV3.ListeningSession(episodeUUID: UUID(), startedAt: .distantPast))
            try context.save()
        }
        let container = try PodlistStore.makeContainer(url: url)
        let context = ModelContext(container)
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.customName) == ["Krimi"])
        #expect(playlists.first?.isHidden == false)
        #expect(try context.fetchCount(FetchDescriptor<ListeningSession>()) == 1)
    }

    /// Stores with hidden playlists (SchemaV4) open with "Alles" (SchemaV5) and keep their
    /// data; nothing is left out of "Alles" until the app creates it (A65).
    @Test func storeFromSchemaV4OpensWithTheCurrentSchema() throws {
        let directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Podlist.store")
        do {
            let schema = Schema(versionedSchema: SchemaV4.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            let playlist = SchemaV4.Playlist(customName: "Kinder", colorKey: "pink", symbolName: "star", displayOrder: 0)
            playlist.isHidden = true
            context.insert(playlist)
            context.insert(SchemaV4.Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "P", subscribedAt: .distantPast))
            try context.save()
        }
        let container = try PodlistStore.makeContainer(url: url)
        let context = ModelContext(container)
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.customName) == ["Kinder"])
        #expect(playlists.first?.isHidden == true)
        #expect(playlists.first?.isExcludedFromEverything == false)
        #expect(try context.fetch(FetchDescriptor<Podcast>()).map(\.isExcludedFromEverything) == [false])
    }

    /// Stores with "Alles" (SchemaV5) open with short descriptions and remembered playlists
    /// (SchemaV6, concept §4.12): both start empty (A74).
    @Test func storeFromSchemaV5OpensWithTheCurrentSchema() throws {
        let directory = URL.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Podlist.store")
        do {
            let schema = Schema(versionedSchema: SchemaV5.self)
            let old = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let context = ModelContext(old)
            let podcast = SchemaV5.Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "P", subscribedAt: .distantPast)
            podcast.isSubscribed = false
            context.insert(podcast)
            let episode = SchemaV5.Episode(guid: "1", title: "E", publishedAt: .distantPast, audioURL: URL(string: "https://example.com/1.mp3")!)
            episode.podcast = podcast
            context.insert(episode)
            try context.save()
        }
        let container = try PodlistStore.makeContainer(url: url)
        let context = ModelContext(container)
        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.map(\.isSubscribed) == [false])
        #expect(podcasts.map(\.playlistUUIDsBeforeUnsubscribing) == [[]])
        #expect(try context.fetch(FetchDescriptor<Episode>()).map(\.subtitle) == [nil])
    }

    @Test func listeningSessionsPersistAndFilterByDate() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let session = ListeningSession(episodeUUID: UUID(), startedAt: start)
        session.listenedSeconds = 60
        session.endReason = .sleepTimer
        context.insert(session)
        context.insert(ListeningSession(episodeUUID: UUID(), startedAt: start.addingTimeInterval(-86_400)))
        try context.save()
        let result = try context.fetch(FetchDescriptor<ListeningSession>(predicate: #Predicate { $0.startedAt >= start }))
        #expect(result.map(\.uuid) == [session.uuid])
        #expect(result.first?.endReason == .sleepTimer)
        #expect(result.first?.listenedSeconds == 60)
        #expect(ListeningSession(episodeUUID: UUID(), startedAt: start).endReason == .interrupted,
                "an open session counts as interrupted until it closes")
    }

    @Test func migrationPlanEndsWithTheCurrentSchema() {
        #expect(PodlistMigrationPlan.schemas.last.map(ObjectIdentifier.init) == ObjectIdentifier(SchemaV6.self))
        #expect(PodlistMigrationPlan.stages.count == PodlistMigrationPlan.schemas.count - 1)
    }

    @Test func inboxStatePersistsAndFiltersWithPredicates() throws {
        let (_, episode, _) = try insertGraph()
        let addedAt = Date(timeIntervalSinceReferenceDate: 1000)
        episode.inboxAddedAt = addedAt
        episode.inboxState = .done
        try context.save()
        let done = InboxState.done.rawValue
        let cutoff = Date(timeIntervalSinceReferenceDate: 500)
        let never = Date.distantPast
        let result = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate {
            $0.inboxStateRaw == done && ($0.inboxAddedAt ?? never) > cutoff
        }))
        #expect(result.map(\.uuid) == [episode.uuid])
        #expect(result.first?.inboxAddedAt == addedAt)
    }

    @Test func defaultPlaylistsAreInsertedOnceWithSystemKeys() throws {
        let service = PlaylistService(context: context)
        try service.insertDefaultPlaylists()
        try service.insertDefaultPlaylists()
        let playlists = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.displayOrder)]))
        #expect(playlists.map(\.systemKey) == DefaultPlaylist.allCases.map(\.systemKey))
        #expect(playlists.allSatisfy { $0.customName == nil && $0.playedPolicy == .remove && $0.sort == .manual })
        #expect(Set(playlists.map(\.uuid)).count == playlists.count)
    }

    @Test func modelGraphWithEntriesQueueAndCursorPersists() throws {
        let (podcast, episode, playlist) = try insertGraph()
        playlist.resumeEpisode = episode
        context.insert(QueueItem(position: 0, playlist: playlist))
        context.insert(QueueItem(position: 1, episode: episode))
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Playlist>()).first)
        #expect(fetched.resumeEpisode?.uuid == episode.uuid)
        #expect(fetched.entries?.count == 1)
        #expect(fetched.assignments?.first?.podcast?.uuid == podcast.uuid)
        #expect(fetched.assignments?.first?.autoAdd == .top)
        #expect(episode.resumingPlaylists?.map(\.uuid) == [playlist.uuid])
        #expect(try context.fetchCount(FetchDescriptor<QueueItem>()) == 2)
    }

    @Test func deletingAnEpisodeRemovesItsEntriesAndQueueItemsAndClearsCursors() throws {
        let (_, episode, playlist) = try insertGraph()
        playlist.resumeEpisode = episode
        context.insert(QueueItem(position: 0, episode: episode))
        try context.save()

        context.delete(episode)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PlaylistEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<QueueItem>()) == 0)
        #expect(playlist.resumeEpisode == nil)
        #expect(try context.fetchCount(FetchDescriptor<Playlist>()) == 1, "the playlist itself stays")
    }

    @Test func deletingAPlaylistKeepsItsEpisodes() throws {
        let (_, _, playlist) = try insertGraph()
        context.insert(QueueItem(position: 0, playlist: playlist))
        try context.save()
        context.delete(playlist)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistAssignment>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<QueueItem>()) == 0)
    }

    @Test func rawEnumsCanBeFilteredWithPredicates() throws {
        let (_, episode, _) = try insertGraph()
        episode.downloadState = .downloaded
        try context.save()
        let downloaded = DownloadState.downloaded.rawValue
        let result = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.downloadStateRaw == downloaded }))
        #expect(result.map(\.uuid) == [episode.uuid])
    }

    @Test func chaptersAreStoredInline() throws {
        let (_, episode, _) = try insertGraph()
        let chapters = [
            Chapter(start: 0, end: 60, title: "Intro"),
            Chapter(start: 60, title: "Hidden", imageURL: URL(string: "https://example.com/c.jpg"), isHidden: true),
        ]
        episode.chapters = chapters
        episode.chaptersSource = .json
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<Episode>()).first)
        #expect(fetched.chapters == chapters)
        #expect(fetched.chaptersSource == .json)
    }

    @Test func upNextSnapshotPayloadRoundTrips() throws {
        let value = UpNextSnapshotValue(
            createdAt: Date(timeIntervalSinceReferenceDate: 100), reason: .cleared,
            state: UpNextState(nowPlaying: EpisodeID(), items: [EpisodeID(), EpisodeID()]))
        context.insert(try UpNextSnapshot(value))
        try context.save()
        let fetched = try #require(try context.fetch(FetchDescriptor<UpNextSnapshot>()).first)
        #expect(try fetched.value() == value)
    }

    @Test func sampleDataFillsTheDefaultPlaylists() throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        try SampleData.insert(into: context)
        #expect(try context.fetchCount(FetchDescriptor<Podcast>()) == 4)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 11)
        let inbox = try context.fetch(FetchDescriptor<Episode>()).compactMap(\.inboxValue)
        #expect(InboxRules.shown(inbox, filter: .all, now: .now).count == 2)
        #expect(inbox.count { $0.state == .done } == 3)
        let news = try #require(try context.fetch(FetchDescriptor<Playlist>()).first { $0.systemKey == "news" })
        #expect(news.entries?.count == 3)
    }

    private func insertGraph() throws -> (Podcast, Episode, Playlist) {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "P", subscribedAt: date)
        let episode = Episode(guid: "1", title: "E", publishedAt: date, audioURL: URL(string: "https://example.com/1.mp3")!)
        let playlist = Playlist(colorKey: "blue", symbolName: "star", displayOrder: 0)
        context.insert(podcast)
        context.insert(playlist)
        episode.podcast = podcast
        context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: .top, createdAt: date))
        context.insert(PlaylistEntry(playlist: playlist, episode: episode, position: 0, addedAt: date, origin: .manual))
        try context.save()
        return (podcast, episode, playlist)
    }
}
