import AVFoundation
import Foundation
import Testing

/// Spike result (docs/adr/0006-chapter-spike-result.md): AVFoundation (iOS 26 simulator) does deliver
/// ID3v2 CHAP chapters from MP3, local and streamed. Pitfall: ID3 chapters carry no language, so
/// their only locale is "und". `bestMatchingPreferredLanguages: ["de", "en"]` therefore returns nothing;
/// the languages passed must come from `availableChapterLocales`.
/// Fixture: scripts/make-chapter-fixture.sh (3 CHAP + CTOC, ID3v2.3, 6 s).
///
/// Second spike (W3, Slice 4), iOS 26 simulator, fixtures from scripts/make-id3-chapter-fixtures.py:
/// - CHAP sub-frame `APIC` is exposed as a group item (key `APIC`, keySpace `org.id3`, identifier `id3/APIC`,
///   commonKey `artwork`, `dataValue` = raw image bytes, MIME in `extraAttributes[.dataType]`).
/// - `WXXX` is exposed (identifier `id3/WXXX`, `stringValue` = URL, description in `extraAttributes[.info]`),
///   other `W*` frames too (key `WOAR`, identifier `id3/WOAR`).
/// - ID3v2.4 CAVEAT: chapters are delivered only while every frame is < 128 bytes. A spec-compliant (synchsafe)
///   v2.4 tag with larger CHAP sub-frames (images, ~130+ byte titles) yields NO chapters, also for ffmpeg-made files;
///   the same content in v2.3, or in v2.4 with plain big-endian sizes, works. AVFoundation seems to read v2.4 sizes plainly.
/// - A tag appended at the end of the file (v2.4 footer "3DI") is found.
/// - MP4 chapters: locale `und`, items in keySpace `comn`, commonKey `title`; the asset formats are
///   iTunes/mp4ra, not `org.id3`.
struct ChapterSpikeTests {
    struct Chapter: Equatable {
        let title: String
        let start: Double
        let end: Double
    }

    static let expected = [
        Chapter(title: "Intro", start: 0, end: 2),
        Chapter(title: "Zweites Kapitel", start: 2, end: 4.5),
        Chapter(title: "Abschluss", start: 4.5, end: 6),
    ]

    static func fixtureURL(_ name: String = "chapters-id3", _ ext: String = "mp3") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    static func chapters(
        of url: URL, preferredLanguages: [String]?
    ) async throws -> (locales: [String], chapters: [Chapter]) {
        let asset = AVURLAsset(url: url)
        let locales = try await asset.load(.availableChapterLocales).map(\.identifier)
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: preferredLanguages ?? locales)
        var chapters: [Chapter] = []
        for group in groups {
            let titleItem = group.items.first { $0.commonKey == .commonKeyTitle }
            let title = try await titleItem?.load(.stringValue) ?? "<no title>"
            chapters.append(Chapter(title: title, start: group.timeRange.start.seconds, end: group.timeRange.end.seconds))
        }
        return (locales, chapters)
    }

    @Test func localMP3DeliversID3ChaptersUnderLocaleUnd() async throws {
        let result = try await Self.chapters(of: try Self.fixtureURL(), preferredLanguages: nil)
        #expect(result.locales == ["und"])
        #expect(result.chapters.count == 3)
        for (actual, wanted) in zip(result.chapters, Self.expected) {
            #expect(actual.title == wanted.title)
            #expect(abs(actual.start - wanted.start) < 0.01)
            #expect(abs(actual.end - wanted.end) < 0.01)
        }
    }

    /// Pins the pitfall: asking with the user's UI languages finds nothing, "und" finds everything.
    @Test(arguments: [
        (["de", "en"], 0),
        ([], 0),
        (["und"], 3),
    ] as [([String], Int)])
    func localMP3ChapterCountDependsOnPreferredLanguages(languages: [String], count: Int) async throws {
        let result = try await Self.chapters(of: try Self.fixtureURL(), preferredLanguages: languages)
        #expect(result.chapters.count == count)
    }

    // MARK: Second spike (W3)

    struct Item {
        let key: String?
        let keySpace: String?
        let identifier: String?
        let commonKey: String?
        let string: String?
        let data: Data?
        let extra: [String: String]
    }

    static func items(of url: URL) async throws -> [[Item]] {
        let asset = AVURLAsset(url: url)
        let locales = try await asset.load(.availableChapterLocales).map(\.identifier)
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: locales)
        var result: [[Item]] = []
        for group in groups {
            var items: [Item] = []
            for item in group.items {
                let extra = try await item.load(.extraAttributes) ?? [:]
                items.append(Item(
                    key: item.key as? String, keySpace: item.keySpace?.rawValue, identifier: item.identifier?.rawValue,
                    commonKey: item.commonKey?.rawValue, string: try await item.load(.stringValue),
                    data: try await item.load(.dataValue),
                    extra: Dictionary(uniqueKeysWithValues: extra.map { ($0.key.rawValue, String(describing: $0.value)) })))
            }
            result.append(items)
        }
        return result
    }

    @Test func id3ChapterImageIsExposedAsArtworkItem() async throws {
        let groups = try await Self.items(of: try Self.fixtureURL("chapters-id3-rich-v23"))
        #expect(groups.count == 3)
        for group in groups {
            let apic = try #require(group.first { $0.key == "APIC" })
            #expect(apic.keySpace == "org.id3")
            #expect(apic.identifier == "id3/APIC")
            #expect(apic.commonKey == "artwork")
            #expect(apic.extra["dataType"] == "image/png")
            let data = try #require(apic.data)
            #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }
    }

    @Test func id3ChapterLinksAreExposedAsStringItems() async throws {
        let groups = try await Self.items(of: try Self.fixtureURL("chapters-id3-rich-v23"))
        let wxxx = try #require(groups[0].first { $0.identifier == "id3/WXXX" })
        #expect(wxxx.string == "https://example.com/intro")
        #expect(wxxx.extra["info"] == "Link") // the WXXX description
        let woar = try #require(groups[0].first { $0.identifier == "id3/WOAR" })
        #expect(woar.string == "https://example.com/artist")
        #expect(groups[1].contains { $0.identifier == "id3/WOAR" } == false)
    }

    /// Pins the v2.4 caveat (see type comment). If this starts delivering chapters, AVFoundation was fixed.
    @Test(arguments: [
        ("chapters-id3-rich-v23", 3),
        ("chapters-id3-small-v24", 3),
        ("chapters-id3-trailing", 3),
        ("chapters-id3-rich-v24", 0),
    ] as [(String, Int)])
    func id3VersionsAndTagPositions(fixture: String, count: Int) async throws {
        let result = try await Self.chapters(of: try Self.fixtureURL(fixture), preferredLanguages: nil)
        #expect(result.chapters.count == count)
    }

    @Test func mp4ChaptersUseCommonKeysUnderLocaleUnd() async throws {
        let url = try Self.fixtureURL("chapters-mp4", "m4a")
        let asset = AVURLAsset(url: url)
        #expect(try await asset.load(.availableChapterLocales).map(\.identifier) == ["und"])
        let formats = try await asset.load(.availableMetadataFormats)
        #expect(!formats.contains(.id3Metadata))
        let groups = try await Self.items(of: url)
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.first?.keySpace == "comn" && $0.first?.commonKey == "title" })
        let id3Formats = try await AVURLAsset(url: try Self.fixtureURL()).load(.availableMetadataFormats)
        #expect(id3Formats.contains(.id3Metadata))
    }

    /// Spike only, left disabled. Re-run by serving the fixture with a Range-capable server on
    /// 127.0.0.1:8765 (python3 -m http.server does NOT support Range) and removing `.disabled`.
    /// Result at spike time: identical to the local file (see ADR 0006). A server WITHOUT Range support
    /// (plain `python3 -m http.server`, port 8766) was measured in the W3 spike, see the ADR.
    @Test(.disabled("spike: needs local range server"))
    func streamedMP3DeliversSameChapters() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:8765/chapters-id3.mp3"))
        let result = try await Self.chapters(of: url, preferredLanguages: nil)
        #expect(result.chapters.map(\.title) == Self.expected.map(\.title))
    }
}
