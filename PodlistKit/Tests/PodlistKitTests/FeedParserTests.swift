import Foundation
import Testing

@testable import PodlistKit

// MARK: - Helpers

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures/Feeds"))
    return try Data(contentsOf: url)
}

/// UTC reference date without touching the device time zone or locale.
private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components)!
}

private func url(_ string: String) -> URL { URL(string: string)! }

/// A minimal feed around the given item XML.
private func feed(
    channel: String = "<title>T</title>", items: String = "", namespaces: String = "", rssAttributes: String = ""
) -> Data {
    Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" \(namespaces) \(rssAttributes)><channel>\(channel)\(items)</channel></rss>
        """.utf8)
}

private let itunesNS = #"xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd""#

private func item(_ body: String, enclosure: String = #"<enclosure url="https://example.com/a.mp3"/>"#) -> String {
    "<item><title>E</title>\(body)\(enclosure)</item>"
}

// MARK: - Date table

struct FeedDateParsingTests {
    static let cases: [(String, Date)] = [
        // RFC 822 / 1123 variants
        ("Tue, 05 Mar 2024 09:30:00 +0200", utc(2024, 3, 5, 7, 30)),
        ("Tue, 5 Mar 2024 09:30:00 GMT", utc(2024, 3, 5, 9, 30)),
        ("5 Mar 2024 09:30:00 GMT", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 24 09:30:00 GMT", utc(2024, 3, 5, 9, 30)),
        ("05 Mar 99 09:30:00 GMT", utc(1999, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30 GMT", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00 -05:00", utc(2024, 3, 5, 14, 30)),
        ("Tue, 05 Mar 2024 09:30:00 +05:30", utc(2024, 3, 5, 4, 0)),
        ("Tue, 05 Mar 2024 09:30:00 +02", utc(2024, 3, 5, 7, 30)),
        ("Tue, 05 Mar 2024 09:30:00 Z", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00 UT", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00 UTC", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00 GMT+0200", utc(2024, 3, 5, 7, 30)),
        ("Tue, 05 Mar 2024 09:30:00 +0000 (UTC)", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00 EST", utc(2024, 3, 5, 14, 30)),
        ("Tue, 05 Mar 2024 09:30:00 EDT", utc(2024, 3, 5, 13, 30)),
        ("Tue, 05 Mar 2024 09:30:00 CST", utc(2024, 3, 5, 15, 30)),
        ("Tue, 05 Mar 2024 09:30:00 CDT", utc(2024, 3, 5, 14, 30)),
        ("Tue, 05 Mar 2024 09:30:00 MST", utc(2024, 3, 5, 16, 30)),
        ("Tue, 05 Mar 2024 09:30:00 MDT", utc(2024, 3, 5, 15, 30)),
        ("Tue, 05 Mar 2024 09:30:00 PST", utc(2024, 3, 5, 17, 30)),
        ("Tue, 05 Mar 2024 09:30:00 PDT", utc(2024, 3, 5, 16, 30)),
        ("Tue, 05 Mar 2024 09:30:00 CET", utc(2024, 3, 5, 8, 30)),
        ("Tue, 05 Mar 2024 09:30:00 CEST", utc(2024, 3, 5, 7, 30)),
        ("Tue,   05   Mar   2024   09:30:00   +0000", utc(2024, 3, 5, 9, 30)),
        ("  Tue, 05 Mar 2024 09:30:00 GMT\n", utc(2024, 3, 5, 9, 30)),
        ("Tuesday, 05 March 2024 09:30:00 GMT", utc(2024, 3, 5, 9, 30)),
        ("tue, 05 mar 2024 09:30:00 gmt", utc(2024, 3, 5, 9, 30)),
        ("Tue,05 Mar 2024 09:30:00 GMT", utc(2024, 3, 5, 9, 30)),
        ("Tue, 05 Mar 2024 09:30:00", utc(2024, 3, 5, 9, 30)),  // no zone: UTC
        ("Sun, 31 Dec 2023 23:59:59 -1100", utc(2024, 1, 1, 10, 59, 59)),
        ("Thu, 29 Feb 2024 12:00:00 GMT", utc(2024, 2, 29, 12)),
        ("Mon, 01 Jan 1990 00:00:00 GMT", utc(1990, 1, 1)),
        // ISO 8601
        ("2024-03-05T09:30:00Z", utc(2024, 3, 5, 9, 30)),
        ("2024-03-05T09:30:00+02:00", utc(2024, 3, 5, 7, 30)),
        ("2024-03-05T09:30:00+0200", utc(2024, 3, 5, 7, 30)),
        ("2024-03-05T09:30:00-05:00", utc(2024, 3, 5, 14, 30)),
        ("2024-03-05T09:30Z", utc(2024, 3, 5, 9, 30)),
        ("2024-03-05 09:30:00", utc(2024, 3, 5, 9, 30)),
        ("2024-03-05", utc(2024, 3, 5)),
    ]

    @Test(arguments: cases)
    func parses(_ input: String, _ expected: Date) {
        #expect(FeedParser.parseDate(input) == expected)
    }

    @Test(arguments: [
        ("2024-03-05T09:30:00.250Z", 0.25),
        ("2024-03-05T09:30:00.5+00:00", 0.5),
        ("2024-03-05T09:30:00.123456Z", 0.123456),
    ])
    func parsesFractionalSeconds(_ input: String, _ fraction: Double) throws {
        let date = try #require(FeedParser.parseDate(input))
        let expected = utc(2024, 3, 5, 9, 30).timeIntervalSince1970 + fraction
        #expect(abs(date.timeIntervalSince1970 - expected) < 0.000_01)
    }

    @Test(arguments: [
        "", "   ", "yesterday", "Tue", "2024", "Tue, 31 Feb 2024 09:30:00 GMT", "Tue, 05 Foo 2024 09:30:00 GMT",
        "Tue, 05 Mar 2024 25:00:00 GMT", "Tue, 05 Mar 2024 09:61:00 GMT", "Tue, 05 Mar 2024 09:30:00 XYZ",
        "Tue, 00 Mar 2024 09:30:00 GMT", "Tue, 05 Mar 2024 09:30:00 +99999", "2024-13-05T09:30:00Z",
        "2024-03-05T09:30:00+", "Tue, 05 Mar 2024 09h30", "5.3.2024 09:30",
    ])
    func rejectsGarbage(_ input: String) {
        #expect(FeedParser.parseDate(input) == nil)
    }

    @Test func instantInsideACentralEuropeanDSTGapIsInterpretedWithTheGivenOffset() {
        // No Locale.current / TimeZone.current involved: 02:30 on the DST change day is just 01:30 UTC.
        #expect(FeedParser.parseDate("Sun, 31 Mar 2024 02:30:00 +0100") == utc(2024, 3, 31, 1, 30))
    }
}

// MARK: - Duration / clock table

struct FeedDurationParsingTests {
    static let durations: [(String, TimeInterval)] = [
        ("01:02:03", 3723), ("1:02:03", 3723), ("00:00:01", 1), ("10:00:00", 36000), ("45:30", 2730),
        ("0:30", 30), ("125:30", 7530), ("3600", 3600), ("3600.5", 3600.5), ("  90 ", 90), ("1:02:03.5", 3723.5),
        ("12", 12), ("7.25", 7.25),
    ]

    @Test(arguments: durations)
    func parses(_ input: String, _ expected: TimeInterval) {
        #expect(FeedParser.parseDuration(input) == expected)
    }

    @Test(arguments: [
        "", "   ", "0", "0.0", "00:00", "00:00:00", "abc", "about an hour", "1:2:3:4", "-5", "-1:00", "inf", "nan",
        "1e3", "1:xx", "12:", ":30", "1::30", "1,5", "0x10",
    ])
    func rejectsGarbageAndZero(_ input: String) {
        #expect(FeedParser.parseDuration(input) == nil)
    }

    @Test(arguments: [
        ("00:12:30.500", 750.5), ("12:30.5", 750.5), ("90", 90), ("0", 0), ("00:00:00", 0), ("npt:01:00", 60),
        ("NPT:1:01:00", 3660), ("1:00:00.000", 3600),
    ] as [(String, TimeInterval)])
    func parsesChapterClock(_ input: String, _ expected: TimeInterval) {
        #expect(FeedParser.parseClock(input) == expected)
    }

    @Test(arguments: ["", "x", "-1", "1:x", "inf"])
    func rejectsInvalidChapterClock(_ input: String) {
        #expect(FeedParser.parseClock(input) == nil)
    }
}

// MARK: - Fixtures

struct FeedParserFixtureTests {
    @Test func podloveGermanFeedChannel() throws {
        let feed = try FeedParser.parse(fixture("podlove-german"))
        #expect(feed.title == "Kaffeepause & Kosmos")
        #expect(feed.author == "Anna Beispiel & Ben Muster")
        #expect(feed.summary == "Wissenschaft, Weltraum und Kaffee – jeden zweiten Dienstag.")
        #expect(feed.artworkURL == url("https://kaffeepause.example.de/cover-3000.jpg"))
        #expect(feed.link == url("https://kaffeepause.example.de"))
        #expect(feed.categories == ["Science", "Astronomy", "Society & Culture"])
        #expect(feed.newFeedURL == nil)
        #expect(feed.episodes.count == 2)
    }

    @Test func podloveGermanFirstEpisode() throws {
        let episode = try #require(FeedParser.parse(fixture("podlove-german")).episodes.first)
        #expect(episode.guid == "kaffeepause-042")
        #expect(episode.title == "KK042 Der Mond ist nicht aus Käse")
        #expect(
            episode.showNotes
                == "<p>Wir sprechen über den <strong>Mond</strong> &amp; seine Entstehung.</p><ul><li>Shownotes</li></ul>")
        #expect(episode.publishedAt == utc(2024, 3, 5, 7, 30))
        #expect(episode.duration == 3723)
        #expect(episode.audioURL == url("https://media.kaffeepause.example.de/kk042.mp3"))
        #expect(episode.fileSize == 59_432_100)
        #expect(episode.mimeType == "audio/mpeg")
        #expect(episode.chaptersURL == nil)
        #expect(episode.imageURL == nil)
    }

    @Test func podloveChaptersAreSortedAndLinked() throws {
        let episode = try #require(FeedParser.parse(fixture("podlove-german")).episodes.first)
        #expect(
            episode.chapters == [
                Chapter(start: 0, end: 750.5, title: "Begrüßung"),
                Chapter(
                    start: 750.5, end: 2700, title: "Marsmissionen",
                    imageURL: url("https://kaffeepause.example.de/ch/mars.jpg"), linkURL: url("https://example.org/mars")),
                Chapter(start: 2700, end: nil, title: "Verabschiedung & Ausblick"),
            ])
    }

    @Test func podloveSecondEpisodeFallsBackToDescription() throws {
        let episode = try #require(FeedParser.parse(fixture("podlove-german")).episodes.last)
        #expect(episode.guid == "kaffeepause-041")
        #expect(episode.showNotes == "<p>Nur eine Beschreibung.</p>")
        #expect(episode.publishedAt == utc(2024, 2, 20, 7, 0))
        #expect(episode.duration == 2890)
        #expect(episode.chapters.isEmpty)
    }

    @Test func podcasting20FeedChannel() throws {
        let feed = try FeedParser.parse(fixture("podcasting20"))
        #expect(feed.title == "The Long Now Radio")
        #expect(feed.author == "editor@longnow.example.com (Dana Example)")  // managingEditor fallback
        #expect(feed.summary == "Conversations about long-term thinking.")  // description fallback
        #expect(feed.artworkURL == url("https://longnow.example.com/art.jpg"))
        #expect(feed.link == url("https://longnow.example.com/"))
        #expect(feed.categories == ["Technology", "Science", "Natural Sciences"])
        #expect(feed.newFeedURL == url("https://feeds.example.com/longnow-new"))
        #expect(feed.episodes.count == 2)
    }

    @Test func podcasting20Episodes() throws {
        let episodes = try FeedParser.parse(fixture("podcasting20")).episodes
        let first = episodes[0]
        #expect(first.guid == "c0ffee00-1111-2222-3333-444455556666")
        #expect(first.title == "Ep. 7: Clocks in Caves")
        #expect(first.showNotes == "Season 2, episode 7.")  // description wins over itunes:summary
        #expect(first.publishedAt == utc(2024, 8, 9, 6, 15))
        #expect(first.episodeNumber == 7)
        #expect(first.seasonNumber == 2)
        #expect(first.duration == 3725)
        #expect(first.imageURL == url("https://longnow.example.com/ep7.jpg"))
        #expect(first.audioURL == url("https://cdn.example.com/longnow/ep7.mp3?token=abc&x=1"))
        #expect(first.fileSize == nil)  // length="0"
        #expect(first.chaptersURL == url("https://longnow.example.com/chapters/ep7.json"))
        #expect(first.chapters.isEmpty)

        let second = episodes[1]
        #expect(second.episodeNumber == nil)  // "bonus"
        #expect(second.seasonNumber == 1)
        #expect(second.duration == 180)
        #expect(second.fileSize == nil)  // "n/a"
        #expect(second.showNotes == nil)
        let date = try #require(second.publishedAt)
        #expect(abs(date.timeIntervalSince1970 - (utc(2024, 7, 1, 10).timeIntervalSince1970 + 0.25)) < 0.001)
    }

    @Test func messyFeedChannel() throws {
        let feed = try FeedParser.parse(fixture("messy"))
        #expect(feed.title == "Chaos   FM")  // trimmed, inner whitespace kept
        #expect(feed.link == nil)  // not an absolute URL
        #expect(feed.summary == "<p>Feed with &amp; entities</p>")
        #expect(feed.author == "fallback@chaos.example (Chaos FM)")  // blank itunes:author ignored
        #expect(feed.artworkURL == url("https://chaos.example/logo.png"))  // image/url fallback
        #expect(feed.categories.isEmpty)
    }

    @Test func messyFeedKeepsOnlyItemsWithValidEnclosure() throws {
        let episodes = try FeedParser.parse(fixture("messy")).episodes
        #expect(episodes.map(\.title) == ["No guid, MM:SS duration", "Video enclosure", "", "ISO date, fractional duration"])
    }

    @Test func messyEpisodeWithoutGuid() throws {
        let episode = try FeedParser.parse(fixture("messy")).episodes[0]
        #expect(episode.guid == nil)  // whitespace only
        #expect(episode.publishedAt == utc(2024, 1, 1, 13, 5))  // "Mon,  1 Jan 2024   08:05 EST"
        #expect(episode.duration == 2730)
        #expect(episode.showNotes == "<p>Hello &amp; welcome</p>")  // entity-encoded HTML, decoded once
        #expect(episode.audioURL == url("http://chaos.example/audio/1.mp3"))
        #expect(episode.fileSize == nil)  // length=""
        #expect(episode.mimeType == "audio/mpeg")
    }

    @Test func messyVideoEnclosureWinsAsFirst() throws {
        let episode = try FeedParser.parse(fixture("messy")).episodes[1]
        #expect(episode.guid == "chaos-3")
        #expect(episode.audioURL == url("https://chaos.example/video/3.mp4"))
        #expect(episode.mimeType == "video/mp4")
        #expect(episode.fileSize == 1_048_576)
        #expect(episode.duration == nil)  // "0"
        #expect(episode.publishedAt == utc(2024, 1, 3, 12))  // "3 Jan 24 12:00 GMT"
    }

    @Test func messyEmptyTagsBecomeNil() throws {
        let episode = try FeedParser.parse(fixture("messy")).episodes[2]
        #expect(episode.title == "")
        #expect(episode.guid == nil)
        #expect(episode.publishedAt == nil)  // unparseable
        #expect(episode.duration == nil)  // garbage
        #expect(episode.showNotes == "Summary fallback")  // empty description falls through to itunes:summary
        #expect(episode.fileSize == nil)
        #expect(episode.mimeType == nil)
    }

    @Test func messyIsoDateAndFractionalDuration() throws {
        let episode = try FeedParser.parse(fixture("messy")).episodes[3]
        #expect(episode.publishedAt == utc(2024, 1, 6, 6, 30))
        #expect(episode.duration == 3600.5)
        #expect(episode.fileSize == 2048)
    }

    @Test func htmlPageIsNotAFeed() throws {
        #expect(throws: FeedParserError.notAFeed) { try FeedParser.parse(fixture("not-a-feed-html")) }
    }

    @Test func atomFeedIsNotAFeed() throws {
        #expect(throws: FeedParserError.notAFeed) { try FeedParser.parse(fixture("not-a-feed-atom")) }
    }

    @Test func truncatedXMLIsMalformed() throws {
        let data = try fixture("truncated")
        do {
            _ = try FeedParser.parse(data)
            Issue.record("expected FeedParserError.malformed")
        } catch let FeedParserError.malformed(message) {
            #expect(!message.isEmpty)
        }
    }
}

// MARK: - Structure and robustness

struct FeedParserRobustnessTests {
    @Test func rssWithoutChannelIsNotAFeed() {
        #expect(throws: FeedParserError.notAFeed) { try FeedParser.parse(Data(#"<rss version="2.0"></rss>"#.utf8)) }
    }

    @Test func emptyDataIsMalformed() {
        #expect(throws: FeedParserError.self) { try FeedParser.parse(Data()) }
        do {
            _ = try FeedParser.parse(Data())
            Issue.record("expected an error")
        } catch let error as FeedParserError {
            if case .malformed = error {} else { Issue.record("expected .malformed, got \(error)") }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func emptyChannelParses() throws {
        let parsed = try FeedParser.parse(feed(channel: ""))
        #expect(parsed.title == "")
        #expect(parsed.episodes.isEmpty)
    }

    @Test func namespacesAreMatchedByURINotPrefix() throws {
        let data = feed(
            channel: "<title>T</title><it:author>Alice</it:author><it:category text=\"News\"/>",
            items: item(
                "<it:duration>10:00</it:duration><it:episode>3</it:episode><ct:encoded>notes</ct:encoded>"),
            namespaces: #"xmlns:it="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:ct="http://purl.org/rss/1.0/modules/content/""#
        )
        let parsed = try FeedParser.parse(data)
        #expect(parsed.author == "Alice")
        #expect(parsed.categories == ["News"])
        #expect(parsed.episodes[0].duration == 600)
        #expect(parsed.episodes[0].episodeNumber == 3)
        #expect(parsed.episodes[0].showNotes == "notes")
    }

    @Test func undeclaredConventionalPrefixesStillWork() throws {
        // A frequent feed bug: `itunes:` used without `xmlns:itunes`.
        let data = feed(
            channel: "<title>T</title><itunes:author>Carol</itunes:author>",
            items: item("<itunes:duration>01:00</itunes:duration>"))
        let parsed = try FeedParser.parse(data)
        #expect(parsed.author == "Carol")
        #expect(parsed.episodes[0].duration == 60)
    }

    @Test func namespaceURIsAreCaseInsensitive() throws {
        let data = feed(
            channel: "<title>T</title><itunes:author>Bob</itunes:author>",
            namespaces: #"xmlns:itunes="HTTP://WWW.iTunes.COM/DTDS/Podcast-1.0.dtd""#)
        #expect(try FeedParser.parse(data).author == "Bob")
    }

    @Test func foreignNamespacesAreIgnored() throws {
        let data = feed(
            channel:
                #"<title>Real</title><atom:title>Atom</atom:title><atom:link href="https://x.example/feed" rel="self"/><atom:author>Nope</atom:author>"#,
            items: item("<media:title>Media title</media:title><media:description>Media</media:description>"),
            namespaces: #"xmlns:atom="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/""#)
        let parsed = try FeedParser.parse(data)
        #expect(parsed.title == "Real")
        #expect(parsed.link == nil)
        #expect(parsed.author == nil)
        #expect(parsed.episodes[0].title == "E")
        #expect(parsed.episodes[0].showNotes == nil)
    }

    @Test func defaultRSSNamespaceDeclarationIsAccepted() throws {
        let data = feed(channel: "<title>Userland</title>", rssAttributes: #"xmlns="http://backend.userland.com/rss2""#)
        #expect(try FeedParser.parse(data).title == "Userland")
    }

    @Test func titlesInsideImageAndItemsDoNotLeakIntoTheChannel() throws {
        let data = feed(
            channel: "<image><title>Image</title><url>https://x.example/i.png</url></image><title>Channel</title>",
            items: "<item><title>Item</title><enclosure url=\"https://x.example/a.mp3\"/></item>")
        let parsed = try FeedParser.parse(data)
        #expect(parsed.title == "Channel")
        #expect(parsed.artworkURL == url("https://x.example/i.png"))
        #expect(parsed.episodes.map(\.title) == ["Item"])
    }

    @Test func itemLevelCategoriesAreNotFeedCategories() throws {
        let data = feed(
            channel: "<title>T</title><itunes:category text=\"A\"/>",
            items: item(#"<itunes:category text="B"/>"#), namespaces: itunesNS)
        #expect(try FeedParser.parse(data).categories == ["A"])
    }

    @Test func categoriesAreDeduplicatedInDocumentOrder() throws {
        let data = feed(
            channel:
                #"<itunes:category text="B"><itunes:category text="A"/></itunes:category><itunes:category text="A"/><itunes:category text=" "/><itunes:category text="B"/>"#,
            namespaces: itunesNS)
        #expect(try FeedParser.parse(data).categories == ["B", "A"])
    }

    @Test func firstValidEnclosureWins() throws {
        let items = """
            <item><title>X</title>
            <enclosure url="ftp://x.example/a.mp3"/>
            <enclosure url="https://x.example/second.mp3" length="5"/>
            <enclosure url="https://x.example/third.mp3" length="6"/></item>
            """
        let episode = try FeedParser.parse(feed(items: items)).episodes[0]
        #expect(episode.audioURL == url("https://x.example/second.mp3"))
        #expect(episode.fileSize == 5)
    }

    @Test(arguments: [
        #"<enclosure/>"#, #"<enclosure url=""/>"#, #"<enclosure url="   "/>"#, #"<enclosure url="relative/a.mp3"/>"#,
        #"<enclosure url="//cdn.example.com/a.mp3"/>"#, #"<enclosure url="ftp://example.com/a.mp3"/>"#,
        #"<enclosure url="file:///etc/passwd"/>"#, #"<enclosure url="https:///a.mp3"/>"#,
        #"<enclosure url="javascript:alert(1)"/>"#,
    ])
    func skipsItemsWithoutValidEnclosure(_ enclosure: String) throws {
        let parsed = try FeedParser.parse(feed(items: "<item><title>X</title>\(enclosure)</item>"))
        #expect(parsed.episodes.isEmpty)
    }

    @Test func enclosureURLIsTrimmed() throws {
        let episode = try FeedParser.parse(feed(items: item("", enclosure: #"<enclosure url="  https://x.example/a.mp3 "/>"#))).episodes[0]
        #expect(episode.audioURL == url("https://x.example/a.mp3"))
    }

    @Test(arguments: [("12345", Int64(12345)), (" 7 ", 7), ("0", nil), ("-5", nil), ("1.5", nil), ("big", nil), ("", nil)] as [(String, Int64?)])
    func enclosureLength(_ raw: String, _ expected: Int64?) throws {
        let enclosure = "<enclosure url=\"https://x.example/a.mp3\" length=\"\(raw)\"/>"
        let episode = try FeedParser.parse(feed(items: item("", enclosure: enclosure))).episodes[0]
        #expect(episode.fileSize == expected)
    }

    @Test(arguments: [("5", 5), (" 12 ", 12), ("05", 5), ("0", 0), ("5.5", nil), ("one", nil), ("", nil), ("S1", nil)] as [(String, Int?)])
    func episodeAndSeasonNumbers(_ raw: String, _ expected: Int?) throws {
        let body = "<itunes:episode>\(raw)</itunes:episode><itunes:season>\(raw)</itunes:season>"
        let episode = try FeedParser.parse(feed(items: item(body), namespaces: itunesNS)).episodes[0]
        #expect(episode.episodeNumber == expected)
        #expect(episode.seasonNumber == expected)
    }

    @Test func showNotesFallbackOrder() throws {
        let both = item("<content:encoded>C</content:encoded><description>D</description><itunes:summary>S</itunes:summary>")
        let noContent = item("<description>D</description><itunes:summary>S</itunes:summary>")
        let onlySummary = item("<itunes:summary>S</itunes:summary>")
        let ns = itunesNS + #" xmlns:content="http://purl.org/rss/1.0/modules/content/""#
        let notes = try FeedParser.parse(feed(items: both + noContent + onlySummary, namespaces: ns)).episodes.map(\.showNotes)
        #expect(notes == ["C", "D", "S"])
    }

    /// The short description (concept §4.12, N83): plain text, tags and entities gone,
    /// whitespace collapsed; missing or empty → nil. Never the channel's subtitle.
    @Test func episodeSubtitleIsPlainText() throws {
        let plain = item("<itunes:subtitle>  Wir reden über den Mond.  </itunes:subtitle>")
        let html = item("<itunes:subtitle><![CDATA[<p>Der <b>Mond</b> &amp; die\n  Sterne</p>]]></itunes:subtitle>")
        let empty = item("<itunes:subtitle>  </itunes:subtitle>")
        let none = item("<description>D</description>")
        let channel = "<itunes:subtitle>Channel</itunes:subtitle>"
        let parsed = try FeedParser.parse(feed(items: channel + plain + html + empty + none, namespaces: itunesNS))
        #expect(parsed.episodes.map(\.subtitle) == ["Wir reden über den Mond.", "Der Mond & die Sterne", nil, nil])
    }

    @Test func episodeTitleFallsBackToItunesTitle() throws {
        let items = "<item><itunes:title>From iTunes</itunes:title><enclosure url=\"https://x.example/a.mp3\"/></item>"
        let episode = try FeedParser.parse(feed(items: items, namespaces: itunesNS)).episodes[0]
        #expect(episode.title == "From iTunes")
    }

    @Test func chaptersWithInvalidStartAreDropped() throws {
        let body = """
            <psc:chapters>
            <psc:chapter start="bogus" title="Bad"/>
            <psc:chapter title="No start"/>
            <psc:chapter start="90" title="Good" href="not a url" image="ftp://x.example/i.png"/>
            <psc:chapter start="30" title="First"/>
            </psc:chapters>
            """
        let data = feed(items: item(body), namespaces: #"xmlns:psc="http://podlove.org/simple-chapters""#)
        let chapters = try FeedParser.parse(data).episodes[0].chapters
        #expect(chapters == [Chapter(start: 30, end: 90, title: "First"), Chapter(start: 90, end: nil, title: "Good")])
    }

    @Test func chaptersOutsideAnItemAreIgnored() throws {
        let channel = #"<title>T</title><psc:chapters><psc:chapter start="1" title="X"/></psc:chapters>"#
        let data = feed(channel: channel, items: item(""), namespaces: #"xmlns:psc="http://podlove.org/simple-chapters""#)
        #expect(try FeedParser.parse(data).episodes[0].chapters.isEmpty)
    }

    @Test func podcastChaptersURLMustBeAbsolute() throws {
        let ns = #"xmlns:podcast="https://podcastindex.org/namespace/1.0""#
        let good = item(#"<podcast:chapters url="https://x.example/c.json" type="application/json+chapters"/>"#)
        let bad = item(#"<podcast:chapters url="c.json"/>"#)
        let episodes = try FeedParser.parse(feed(items: good + bad, namespaces: ns)).episodes
        #expect(episodes.map(\.chaptersURL) == [url("https://x.example/c.json"), nil])
    }

    @Test func itemImageIsOnlyTakenFromItunesImage() throws {
        let body = #"<image><url>https://x.example/wrong.png</url></image><itunes:image href="https://x.example/right.png"/>"#
        let episode = try FeedParser.parse(feed(items: item(body), namespaces: itunesNS)).episodes[0]
        #expect(episode.imageURL == url("https://x.example/right.png"))
    }

    @Test func feedOrderIsKept() throws {
        let items = (1...5).map { "<item><title>#\($0)</title><enclosure url=\"https://x.example/\($0).mp3\"/></item>" }
        let parsed = try FeedParser.parse(feed(items: items.joined()))
        #expect(parsed.episodes.map(\.title) == ["#1", "#2", "#3", "#4", "#5"])
    }

    // MARK: Messy bytes

    @Test func leadingWhitespaceBeforeXMLDeclarationIsTolerated() throws {
        var data = Data("\n\r\n  ".utf8)
        data.append(feed(channel: "<title>Padded</title>"))
        #expect(try FeedParser.parse(data).title == "Padded")
    }

    @Test func utf8ByteOrderMarkIsTolerated() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(feed(channel: "<title>Bom</title>"))
        #expect(try FeedParser.parse(data).title == "Bom")
    }

    @Test func illegalControlCharactersAreStripped() throws {
        var data = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss><channel><title>Bad".utf8)
        data.append(contentsOf: [0x0B, 0x0C, 0x01])
        data.append(Data("Chars</title></channel></rss>".utf8))
        #expect(try FeedParser.parse(data).title == "BadChars")
    }

    @Test func externalEntitiesAreNeverResolved() throws {
        let xml = """
            <?xml version="1.0"?>
            <!DOCTYPE rss [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
            <rss><channel><title>Safe&xxe;</title></channel></rss>
            """
        let title = (try? FeedParser.parse(Data(xml.utf8)))?.title ?? ""
        #expect(!title.contains("root:"))
    }

    @Test func latin1EncodedFeedIsDecodedByDeclaredEncoding() throws {
        var data = Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><rss><channel><title>Gr".utf8)
        data.append(0xFC)  // ü
        data.append(Data("n</title></channel></rss>".utf8))
        #expect(try FeedParser.parse(data).title == "Grün")
    }

    // MARK: Scale and concurrency

    @Test func parsesLargeFeedCompletely() throws {
        var xml = #"<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Big</title>"#
        for index in 0..<3000 {
            xml += """
                <item><title>Episode \(index)</title><guid>g-\(index)</guid>\
                <pubDate>Tue, 05 Mar 2024 09:30:00 +0200</pubDate><itunes:duration>12:34</itunes:duration>\
                <description>Notes for \(index)</description>\
                <enclosure url="https://cdn.example.com/\(index).mp3" length="\(1000 + index)" type="audio/mpeg"/></item>
                """
        }
        xml += "</channel></rss>"
        let parsed = try FeedParser.parse(Data(xml.utf8))
        #expect(parsed.episodes.count == 3000)
        #expect(parsed.episodes.first?.title == "Episode 0")
        #expect(parsed.episodes.last?.guid == "g-2999")
        #expect(parsed.episodes.last?.fileSize == 3999)
        #expect(parsed.episodes.allSatisfy { $0.duration == 754 && $0.publishedAt == utc(2024, 3, 5, 7, 30) })
    }

    @Test func parseIsCallableFromAnyActor() async throws {
        let data = try fixture("podlove-german")
        let parsed = try await Task.detached { try FeedParser.parse(data) }.value
        #expect(parsed.episodes.count == 2)
    }
}
