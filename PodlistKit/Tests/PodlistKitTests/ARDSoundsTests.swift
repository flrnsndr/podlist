import Foundation
import Testing

@testable import PodlistKit

/// ARD Sounds as a podcast source (concept §4.13): links, queries, and the mapping of real
/// API responses (fixtures captured 2026-10-20) to the feed layer's values.
struct ARDSoundsTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ARD"))
        return try Data(contentsOf: url)
    }

    // MARK: Links

    @Test(arguments: [
        ("https://www.ardsounds.de/sendung/kafka-das-schloss/urn:ard:show:2760782f4323167a/", "2760782f4323167a"),
        ("https://www.ardsounds.de/sendung/urn:ard:show:2760782f4323167a", "2760782f4323167a"),
        ("http://ardsounds.de/sendung/kafka/urn:ard:show:2760782F4323167A/?utm=x", "2760782f4323167a"),
        ("https://www.ardaudiothek.de/sendung/kafka-das-schloss/urn:ard:show:2760782f4323167a/", "2760782f4323167a"),
        ("urn:ard:show:2760782f4323167a", "2760782f4323167a"),
        ("  urn:ard:show:2760782f4323167a\n", "2760782f4323167a"),
    ])
    func recognizesShows(_ text: String, _ id: String) {
        #expect(ARDSounds.reference(from: text) == .show("urn:ard:show:\(id)"))
    }

    @Test(arguments: [
        "https://www.ardsounds.de/episode/urn:ard:episode:1ba5b1490f6d5151/",
        "https://www.ardaudiothek.de/episode/oliver-kalkofe/urn:ard:episode:1ba5b1490f6d5151",
        "urn:ard:episode:1ba5b1490f6d5151",
    ])
    func recognizesEpisodes(_ text: String) {
        #expect(ARDSounds.reference(from: text) == .episode("urn:ard:episode:1ba5b1490f6d5151"))
    }

    @Test(arguments: [
        "https://example.com/sendung/urn:ard:show:2760782f4323167a/",
        "https://www.ardsounds.de/",
        "https://www.ardsounds.de/sendung/kafka/",
        "urn:ard:show:",
        "urn:ard:show:xyz",
        "Kafka Das Schloss",
        "https://feeds.br.de/das-schloss-das-hoerspiel/feed.xml",
    ])
    func ignoresEverythingElse(_ text: String) {
        #expect(ARDSounds.reference(from: text) == nil)
    }

    @Test func canonicalURLs() {
        #expect(ARDSounds.showURL("urn:ard:show:2760782f4323167a").absoluteString
            == "https://www.ardsounds.de/sendung/urn:ard:show:2760782f4323167a/")
        #expect(ARDSounds.Reference.episode("urn:ard:episode:1ba5b1490f6d5151").url.absoluteString
            == "https://www.ardsounds.de/episode/urn:ard:episode:1ba5b1490f6d5151/")
    }

    /// Pasted links and bare URNs pass the feed URL check of the search field and "Feed hinzufügen".
    @Test func feedURLNormalizingKeepsARDLinksCanonical() throws {
        let show = try #require(URL(string: "https://www.ardsounds.de/sendung/kafka-das-schloss/urn:ard:show:2760782f4323167a/"))
        #expect(FeedLoader.normalizedFeedURL(show) == ARDSounds.showURL("urn:ard:show:2760782f4323167a"))
        let urn = try #require(URL(string: "urn:ard:show:2760782f4323167a"))
        #expect(FeedLoader.normalizedFeedURL(urn) == ARDSounds.showURL("urn:ard:show:2760782f4323167a"))
        let episode = try #require(URL(string: "http://www.ardaudiothek.de/episode/x/urn:ard:episode:1ba5b1490f6d5151"))
        #expect(FeedLoader.normalizedFeedURL(episode)?.absoluteString
            == "https://www.ardsounds.de/episode/urn:ard:episode:1ba5b1490f6d5151/")
    }

    // MARK: Queries

    @Test func queriesAreGETRequestsWithTheShowID() throws {
        let url = ARDSounds.showQueryURL("urn:ard:show:2760782f4323167a")
        #expect(url.host == "api.ardaudiothek.de")
        #expect(url.path == "/graphql")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value)
        #expect(query.contains("programSet(id: \"urn:ard:show:2760782f4323167a\")"))
        #expect(query.contains("PUBLISH_DATE_DESC"))
        #expect(query.contains("audios"))
        let state = try #require(URLComponents(url: ARDSounds.stateQueryURL("urn:ard:show:2760782f4323167a"), resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        #expect(state.contains("lastItemModified"))
        #expect(!state.contains("items"))
    }

    @Test func searchQueryEscapesTheTerm() throws {
        let url = ARDSounds.searchQueryURL(term: "Kafka \"Das\" \\ Schloss", limit: 10)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
        #expect(query.contains(#"search(query: "Kafka \"Das\" \\ Schloss", limit: 10)"#))
    }

    // MARK: Shows

    @Test func mapsAShowLikeAFeed() throws {
        let show = try ARDSounds.decodeShow(fixture("show-kafka"))
        let feed = show.feed
        #expect(feed.title == "Kafka – Das Schloss")
        #expect(feed.author == "ARD")
        #expect(feed.summary?.isEmpty == false)
        #expect(feed.artworkURL?.absoluteString
            == "https://api.ardmediathek.de/image-service/images/urn:ard:image:134b83b0d36910f6?w=1400&ch=49e9bb5d2825d4de")
        #expect(feed.link?.absoluteString == "https://www.ardsounds.de/sendung/kafka-das-schloss/urn:ard:show:2760782f4323167a/")
        #expect(feed.categories.isEmpty)
        #expect(feed.newFeedURL == nil)
        #expect(feed.episodes.count == 30)
        #expect(show.validator == "2026-01-29T11:09:48.523177+01:00|2024-05-27T00:06:00+02:00|30")

        let first = try #require(feed.episodes.first)
        #expect(first.guid == "urn:ard:publication:8ca2b3eb8b6b0b51")
        #expect(first.title == "Franz Kafka: Das Schloss (29/29)")
        #expect(first.audioURL.absoluteString.hasPrefix("https://rbbmediapmdp-a.akamaihd.net/content/03/71/"))
        #expect(first.mimeType == "audio/mpeg")
        #expect(first.duration == 1721)
        #expect(first.publishedAt == ISO8601DateFormatter().date(from: "2024-03-24T23:29:00Z"))
        #expect(first.imageURL?.absoluteString.contains("w=1400") == true)
        // The summary is only the start of the description: no subtitle.
        #expect(first.subtitle == nil)
        let notes = try #require(first.showNotes)
        #expect(notes.contains("<p>Der Schauspieler Ulrich Matthes liest"))
        #expect(HTMLText.plainText(fromHTML: notes).contains("Pepi.\n\nDer Schauspieler"))
    }

    @Test func aSummaryOfItsOwnBecomesTheSubtitle() throws {
        let feed = try ARDSounds.decodeShow(fixture("show-loriot")).feed
        let first = try #require(feed.episodes.first)
        #expect(first.title == "Oliver Kalkofe: \"Weihnachten bei Hoppenstedts versuche ich jedes Jahr zu gucken\"")
        #expect(first.subtitle?.hasPrefix("Das große Finale") == true)
        #expect(first.showNotes?.contains("\r") == false)
    }

    @Test func aMissingShowIsNotFound() throws {
        #expect(throws: ARDSoundsError.notFound) { try ARDSounds.decodeShow(fixture("show-missing")) }
        #expect(FeedFailureReason(ARDSoundsError.notFound) == .notFound)
    }

    @Test(arguments: [
        #"{"errors":[{"message":"boom"}],"data":null}"#,
        "<html>",
        #"{"data":{"programSet":{"coreId":null}}}"#,
    ])
    func brokenResponsesThrow(_ body: String) {
        #expect(throws: (any Error).self) { try ARDSounds.decodeShow(Data(body.utf8)) }
    }

    /// Every field but the audio may be missing; items without an audio URL are dropped.
    @Test func handlesNulls() throws {
        let body = #"""
        {"data":{"programSet":{"coreId":"urn:ard:show:00000000000000aa","title":null,"synopsis":null,"sharingUrl":null,
        "numberOfElements":null,"lastItemAdded":null,"lastItemModified":null,"feedUrl":null,"image":null,"publicationService":null,
        "items":{"nodes":[
          {"coreId":null,"title":"  A  ","summary":null,"synopsis":null,"description":null,"sharingUrl":null,"publishDate":"junk",
           "duration":0,"image":{"url":null,"url1X1":null},"audios":[{"url":null,"mimeType":null},{"url":"https://x.de/a.mp3","mimeType":null}]},
          {"coreId":"urn:ard:publication:2","title":"B","audios":[]},
          {"coreId":"urn:ard:publication:3","title":"C","audios":null},
          null
        ]}}}}
        """#
        let show = try ARDSounds.decodeShow(Data(body.utf8))
        #expect(show.feed.title == "")
        #expect(show.feed.author == nil)
        #expect(show.feed.artworkURL == nil)
        #expect(show.feed.link?.absoluteString == "https://www.ardsounds.de/sendung/urn:ard:show:00000000000000aa/")
        #expect(show.validator == nil)
        let episode = try #require(show.feed.episodes.first)
        #expect(show.feed.episodes.count == 1)
        #expect(episode.guid == nil)
        #expect(episode.title == "A")
        #expect(episode.audioURL.absoluteString == "https://x.de/a.mp3")
        #expect(episode.publishedAt == nil)
        #expect(episode.duration == nil)
        #expect(episode.showNotes == nil)
    }

    @Test func decodesTheState() throws {
        #expect(try ARDSounds.decodeState(fixture("state-loriot")) == "2025-10-26T12:38:29.549281+01:00|-|8")
        #expect(throws: ARDSoundsError.notFound) { try ARDSounds.decodeState(fixture("show-missing")) }
    }

    @Test func decodesTheShowOfAnEpisode() throws {
        #expect(try ARDSounds.decodeShowURN(ofEpisode: fixture("item-episode")) == "urn:ard:show:2de1ca294641f598")
        #expect(throws: ARDSoundsError.notFound) { try ARDSounds.decodeShowURN(ofEpisode: Data(#"{"data":{"item":null}}"#.utf8)) }
    }

    // MARK: Search

    @Test func decodesSearchResults() throws {
        let shows = try ARDSounds.decodeSearch(fixture("search-kafka"))
        let first = try #require(shows.first)
        #expect(first.urn == "urn:ard:show:2760782f4323167a")
        #expect(first.title == "Kafka – Das Schloss")
        #expect(first.broadcaster == "ARD")
        #expect(first.feedURL == nil)
        #expect(first.artworkURL?.absoluteString.contains("w=600") == true)
        let br = try #require(shows.first { $0.title == "Das Schloss - Hörspiel nach Franz Kafka" })
        #expect(br.feedURL?.absoluteString == "https://feeds.br.de/das-schloss-das-hoerspiel/feed.xml")
    }

    @Test func crid_feedURLsAreNoFeeds() throws {
        let krimi = try ARDSounds.decodeSearch(fixture("search-krimi"))
        let knallhart = try #require(krimi.first { $0.title.hasPrefix("Knallhart") })
        #expect(knallhart.feedURL == nil)
    }

    private func merged(_ name: String, _ term: String) throws -> [PodcastSearchResult] {
        let itunes = try ITunesSearch.decode(fixture("itunes-\(name)"))
        let ard = try ARDSounds.decodeSearch(fixture("search-\(name)"))
        return ARDSounds.merge(iTunes: itunes, ard: ard, term: term)
    }

    /// The official Radio Bremen feed from iTunes, once; ARD's own entry is dropped.
    @Test func loriotShowsTheOfficialFeedOnce() throws {
        let results = try merged("loriot", "Loriot")
        let loriot = results.filter { $0.title.hasPrefix("Loriot 100") }
        #expect(loriot.count == 1)
        #expect(loriot.first?.feedURL.absoluteString == "https://www.radiobremen.de/feed/podcast/loriot-122.xml")
        #expect(results.count == 3)
    }

    /// "Hoyzer - Verrat am Fußball | rbb Sport" by ARD in iTunes is the same show.
    @Test func aLongerTitleOfTheSameBroadcasterIsADuplicate() throws {
        let results = try merged("hoyzer", "Hoyzer")
        #expect(results.filter { $0.title.lowercased().contains("hoyzer") }.count == 1)
        #expect(results.first?.feedURL.host() == "www.rbb-online.de")
    }

    @Test func ardOnlyShowsAreFoundAndBackedByARD() throws {
        let results = try merged("kafka", "Kafka")
        let schloss = try #require(results.first { $0.title == "Kafka – Das Schloss" })
        #expect(schloss.feedURL == ARDSounds.showURL("urn:ard:show:2760782f4323167a"))
        #expect(schloss.author == "ARD")
        #expect(schloss.id < 0)
        // An ARD show with its own feed and no iTunes entry becomes a normal feed result.
        let br = try #require(results.first { $0.title == "Das Schloss - Hörspiel nach Franz Kafka" })
        #expect(br.feedURL.absoluteString == "https://feeds.br.de/das-schloss-das-hoerspiel/feed.xml")
        // In iTunes too (NDR): only once.
        #expect(results.filter { $0.title == "Kehlmanns Helden: Kafka vs. Hiphop" }.count == 1)
        #expect(Set(results.map(\.id)).count == results.count)
        #expect(Set(results.map(\.feedURL)).count == results.count)
    }

    /// Merged by rank, iTunes first; a title that is exactly the search term comes first.
    @Test func ordering() {
        func result(_ id: Int, _ title: String) -> PodcastSearchResult {
            PodcastSearchResult(id: id, title: title, author: nil, feedURL: URL(string: "https://e.com/\(id)")!, artworkURL: nil, genres: [])
        }
        func show(_ id: Int, _ title: String) -> ARDSounds.Show {
            ARDSounds.Show(urn: "urn:ard:show:\(String(format: "%016x", id))", title: title, broadcaster: "ARD", feedURL: nil, artworkURL: nil)
        }
        let merged = ARDSounds.merge(
            iTunes: [result(1, "Alpha"), result(2, "Beta"), result(3, "Gamma")],
            ard: [show(10, "Delta"), show(11, "Das Schloss")], term: "das schloß")
        #expect(merged.map(\.title) == ["Das Schloss", "Alpha", "Delta", "Beta", "Gamma"])
    }

    @Test func withoutARDTheITunesResultsStayAsTheyAre() throws {
        let itunes = try ITunesSearch.decode(fixture("itunes-krimi"))
        #expect(ARDSounds.merge(iTunes: itunes, ard: [], term: "Krimi") == itunes)
    }
}
