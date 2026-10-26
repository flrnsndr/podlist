import Foundation
import Testing

@testable import PodlistKit

/// One search over iTunes and ARD Sounds (concept §4.13).
struct PodcastDirectoryTests {
    private let routes = StubURLProtocol.Routes()

    private func directory(grace: Duration = .seconds(1)) -> PodcastDirectory {
        PodcastDirectory(session: StubURLProtocol.session(routes: routes), ardGrace: grace)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ARD"))
        return try Data(contentsOf: url)
    }

    private func stub(_ term: String, itunes: StubURLProtocol.Response, ard: StubURLProtocol.Response) {
        routes.set(ITunesSearch.searchURL(term: term, country: "DE"), itunes)
        routes.set(ARDSounds.searchQueryURL(term: term), ard)
    }

    @Test func findsARDOnlyShowsNextToITunes() async throws {
        stub("Kafka", itunes: .init(body: try fixture("itunes-kafka")), ard: .init(body: try fixture("search-kafka")))
        let results = try await directory().search("Kafka", country: "DE")
        #expect(results.contains { $0.feedURL == ARDSounds.showURL("urn:ard:show:2760782f4323167a") })
        #expect(results.contains { $0.title == "Kafkas letzte Tage" })
    }

    @Test func loriotOnce() async throws {
        stub("Loriot", itunes: .init(body: try fixture("itunes-loriot")), ard: .init(body: try fixture("search-loriot")))
        let results = try await directory().search("Loriot", country: "DE")
        #expect(results.filter { $0.title.hasPrefix("Loriot 100") }.map(\.feedURL.host) == ["www.radiobremen.de"])
    }

    @Test func aFailingARDLeavesTheITunesResults() async throws {
        stub("Kafka", itunes: .init(body: try fixture("itunes-kafka")), ard: .init(status: 500))
        let results = try await directory().search("Kafka", country: "DE")
        #expect(results == (try ITunesSearch.decode(fixture("itunes-kafka"))))
    }

    @Test func aSlowARDDoesNotHoldUpTheResults() async throws {
        stub("Kafka", itunes: .init(body: try fixture("itunes-kafka")), ard: .init(body: try fixture("search-kafka"), delay: .seconds(30)))
        let start = ContinuousClock.now
        let results = try await directory(grace: .milliseconds(100)).search("Kafka", country: "DE")
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(results == (try ITunesSearch.decode(fixture("itunes-kafka"))))
    }

    @Test func withoutITunesARDAloneAnswers() async throws {
        stub("Kafka", itunes: .init(status: 503), ard: .init(body: try fixture("search-kafka")))
        let results = try await directory().search("Kafka", country: "DE")
        #expect(results.first?.title == "Kafka – Das Schloss")
        stub("Kafka", itunes: .init(status: 503), ard: .init(status: 503))
        await #expect(throws: FeedLoadError.http(status: 503)) { try await directory().search("Kafka", country: "DE") }
    }

    /// ARD is searched in every region (A82).
    @Test func otherRegionsSearchARDToo() async throws {
        routes.set(ITunesSearch.searchURL(term: "Kafka", country: "US"), .init(body: try fixture("itunes-kafka")))
        routes.set(ARDSounds.searchQueryURL(term: "Kafka"), .init(body: try fixture("search-kafka")))
        let results = try await directory().search("Kafka", country: "US")
        #expect(results.contains { $0.feedURL == ARDSounds.showURL("urn:ard:show:2760782f4323167a") })
    }
}
