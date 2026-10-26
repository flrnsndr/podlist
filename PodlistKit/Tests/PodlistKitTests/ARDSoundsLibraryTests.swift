import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// ARD-backed podcasts behave like any other (concept §4.13): preview, subscribe and refresh
/// through ARD's API, with a stubbed network and real responses.
@MainActor
struct ARDSoundsLibraryTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let service: LibraryService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
    private let urn = "urn:ard:show:2de1ca294641f598"
    private let showPage = URL(string: "https://www.ardsounds.de/sendung/loriot-100-mehr-lametta-mit-ariana-baborie/urn:ard:show:2de1ca294641f598/")!

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        service = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)),
            now: { ARDSoundsLibraryTests.now })
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ARD"))
        return try Data(contentsOf: url)
    }

    private func serveShow(_ body: Data) throws {
        routes.set(ARDSounds.showQueryURL(urn), .init(body: body))
        routes.set(ARDSounds.stateQueryURL(urn), .init(body: try stateBody(of: body)))
    }

    /// The state answer that belongs to a show answer.
    private func stateBody(of show: Data) throws -> Data {
        let json = try #require(try JSONSerialization.jsonObject(with: show) as? [String: Any])
        let set = try #require((json["data"] as? [String: Any])?["programSet"] as? [String: Any])
        let state = ["lastItemModified", "lastItemAdded", "numberOfElements"].reduce(into: [String: Any]()) { $0[$1] = set[$1] }
        return try JSONSerialization.data(withJSONObject: ["data": ["programSet": state]])
    }

    /// The Loriot show with one more episode on top and a newer modification date.
    private func showWithNewEpisode() throws -> Data {
        var json = try #require(try JSONSerialization.jsonObject(with: fixture("show-loriot")) as? [String: Any])
        var data = try #require(json["data"] as? [String: Any])
        var set = try #require(data["programSet"] as? [String: Any])
        var items = try #require(set["items"] as? [String: Any])
        let nodes = try #require(items["nodes"] as? [Any])
        let new: [String: Any] = [
            "coreId": "urn:ard:publication:0000000000000new", "title": "Bonusfolge", "publishDate": "2026-10-19T06:00:00+02:00",
            "duration": 600, "audios": [["url": "https://cdn.example.com/bonus.mp3", "mimeType": "audio/mp3"]],
        ]
        items["nodes"] = [new] + nodes
        set["items"] = items
        set["lastItemModified"] = "2026-10-19T06:00:01+02:00"
        set["numberOfElements"] = nodes.count + 1
        data["programSet"] = set
        json["data"] = data
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func previewOfAShowPage() async throws {
        try serveShow(fixture("show-loriot"))
        let feed = try await service.preview(showPage)
        #expect(feed.title == "Loriot 100 – mehr Lametta mit Ariana Baborie")
        #expect(feed.episodes.count == 8)
    }

    @Test func subscribingThroughAnEpisodeLinkStoresTheShow() async throws {
        try serveShow(fixture("show-loriot"))
        routes.set(ARDSounds.episodeQueryURL("urn:ard:episode:1ba5b1490f6d5151"), .init(body: try fixture("item-episode")))
        let podcast = try #require(try await service.subscribe(to: URL(string: "https://www.ardsounds.de/episode/urn:ard:episode:1ba5b1490f6d5151/")!))
        #expect(podcast.feedURL == ARDSounds.showURL(urn))
        #expect(podcast.title == "Loriot 100 – mehr Lametta mit Ariana Baborie")
        #expect(podcast.author == "ARD")
        #expect(podcast.lastModified == "2025-10-26T12:38:29.549281+01:00|-|8")
        #expect(podcast.episodes?.count == 8)
        #expect(try service.isSubscribed(feedURL: showPage))
        #expect(try service.isSubscribed(feedURL: URL(string: urn)!))

        // The same show by its URN: still one podcast.
        let again = try await service.subscribe(to: URL(string: urn)!)
        #expect(again?.uuid == podcast.uuid)
        #expect(try context.fetchCount(FetchDescriptor<Podcast>()) == 1)
    }

    @Test func refreshLoadsTheShowOnlyWhenItChanged() async throws {
        try serveShow(fixture("show-loriot"))
        let podcast = try #require(try await service.subscribe(to: showPage))
        let showRequests = { self.routes.requests.filter { $0.url == ARDSounds.showQueryURL(self.urn) }.count }
        #expect(showRequests() == 1)

        try await service.refresh(podcast)
        #expect(showRequests() == 1)
        #expect(routes.requests.last?.url == ARDSounds.stateQueryURL(urn))

        try serveShow(showWithNewEpisode())
        try await service.refresh(podcast)
        #expect(showRequests() == 2)
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.count == 9)
        let bonus = try #require(episodes.first { $0.guid == "urn:ard:publication:0000000000000new" })
        #expect(bonus.title == "Bonusfolge")
        #expect(bonus.duration == 600)
        #expect(bonus.inboxState == .open)
        let id = podcast.uuid
        let stored = try #require(try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == id })).first)
        #expect(stored.lastModified == "2026-10-19T06:00:01+02:00|-|9")
    }

    @Test func aShowThatIsGoneFailsLikeADeadFeed() async throws {
        routes.set(ARDSounds.showQueryURL(urn), .init(body: try fixture("show-missing")))
        await #expect(throws: ARDSoundsError.notFound) { _ = try await service.subscribe(to: showPage) }
    }
}
