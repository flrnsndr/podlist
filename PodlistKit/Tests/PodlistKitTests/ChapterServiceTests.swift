import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PodlistKit

/// Loading chapters from every source (concept §4.6, ADR 0005, A29, N29) with an in-memory
/// store, a stubbed network and a stubbed audio reader.
@MainActor
struct ChapterServiceTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let audio = AudioStub()
    private let images: ChapterImageStore
    private let episode: Episode
    private var context: ModelContext { container.mainContext }
    private let chaptersURL = URL(string: "https://example.com/chapters/42.json")!

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        images = ChapterImageStore(directory: URL.temporaryDirectory.appending(path: "ChapterServiceTests-\(UUID().uuidString)"))
        episode = Episode(guid: "42", title: "E", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.example.com/42.mp3")!)
        episode.duration = 3_600
        container.mainContext.insert(episode)
        try container.mainContext.save()
    }

    private func makeService() -> ChapterService {
        let audio = audio
        return ChapterService(
            context: context, session: StubURLProtocol.session(routes: routes), images: images,
            loadAudio: { url in try audio.load(url) })
    }

    // MARK: Priority (ADR 0005)

    @Test func jsonChaptersWinOverPodloveAndSkipTheAudio() async throws {
        episode.chapters = [Chapter(start: 0, title: "Podlove")]
        episode.chaptersSource = .podlove
        episode.chaptersURL = chaptersURL
        routes.set(chaptersURL, .init(body: try fixture("spec-example")))

        await makeService().load(episode)
        #expect(episode.chaptersSource == .json)
        #expect(episode.chapters.map(\.title) == ["Intro", "Begrüßung und Neuigkeiten", "Werbung", "Interview mit Anna", "Abschied"])
        #expect(episode.chapters[1].end == 660, "normalized: visible chapters end where the next visible one starts")
        #expect(episode.chapters[2].isHidden)
        #expect(audio.calls == 0)
    }

    @Test func jsonIsLoadedOncePerLaunch() async throws {
        episode.chaptersURL = chaptersURL
        routes.set(chaptersURL, .init(body: try fixture("spec-example")))
        let service = makeService()
        await service.load(episode)
        await service.load(episode)
        #expect(routes.requests.count == 1)

        await makeService().load(episode)
        #expect(routes.requests.count == 2, "the next launch looks again (the podcaster may have changed it)")
    }

    @Test func failingJSONFallsBackToTheAudioFile() async throws {
        episode.chaptersURL = chaptersURL
        routes.set(chaptersURL, .init(status: 404))
        audio.result = AudioChapterResult(source: .id3, chapters: [Chapter(start: 0, title: "A"), Chapter(start: 60, title: "B")])

        await makeService().load(episode)
        #expect(episode.chaptersSource == .id3)
        #expect(episode.chapters.map(\.title) == ["A", "B"])
        #expect(episode.chapters.last?.end == 3_600)
    }

    @Test func podloveChaptersAreKeptWithoutReadingTheAudio() async {
        episode.chapters = [Chapter(start: 0, end: 3_600, title: "Podlove")]
        episode.chaptersSource = .podlove
        await makeService().load(episode)
        #expect(episode.chaptersSource == .podlove)
        #expect(audio.calls == 0)
    }

    @Test func showNotesTimestampsWhenNothingElseHasChapters() async {
        episode.showNotes = "<p>00:00 Intro<br>12:30 Thema eins<br>45:10 Thema zwei</p>"
        await makeService().load(episode)
        #expect(episode.chaptersSource == .shownotes)
        #expect(episode.chapters.map(\.start) == [0, 750, 2_710])
        #expect(audio.calls == 1, "the audio file was checked first")
    }

    @Test func audioChaptersWinOverShowNotes() async {
        episode.showNotes = "<p>00:00 Intro<br>12:30 Thema eins<br>45:10 Thema zwei</p>"
        audio.result = AudioChapterResult(source: .mp4, chapters: [Chapter(start: 0, title: "A"), Chapter(start: 60, title: "B")])
        await makeService().load(episode)
        #expect(episode.chaptersSource == .mp4)
    }

    @Test func theAudioIsReadOncePerLaunch() async {
        let service = makeService()
        await service.load(episode)
        await service.load(episode)
        #expect(audio.calls == 1)
        #expect(episode.chaptersSource == nil)
    }

    @Test func audioErrorsLeaveTheChaptersAlone() async {
        audio.fails = true
        episode.showNotes = "<p>00:00 Intro<br>12:30 Thema eins<br>45:10 Thema zwei</p>"
        await makeService().load(episode)
        #expect(episode.chaptersSource == .shownotes)
    }

    /// The episode can be deleted while its audio file is read (unsubscribing).
    @Test func anEpisodeDeletedDuringLoadingIsLeftAlone() async throws {
        nonisolated(unsafe) let context = context
        nonisolated(unsafe) let episode = episode
        let service = ChapterService(
            context: context, session: StubURLProtocol.session(routes: routes), images: images,
            loadAudio: { _ in
                await MainActor.run {
                    context.delete(episode)
                    try? context.save()
                }
                return AudioChapterResult(source: .id3, chapters: [Chapter(start: 0, title: "A")], images: [0: Data([1])])
            })
        await service.load(episode)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 0)
    }

    // MARK: Embedded images (N29)

    @Test func embeddedImagesAreCachedAndReadAgainWhenTheCacheIsGone() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        audio.result = AudioChapterResult(
            source: .id3, chapters: [Chapter(start: 60, title: "B"), Chapter(start: 0, title: "A")], images: [0: png])

        await makeService().load(episode)
        #expect(episode.chapters.map(\.title) == ["A", "B"])
        let url = try #require(episode.chapters[1].imageURL, "the image belongs to chapter B after sorting")
        #expect(ChapterImageStore.isChapterImage(url))
        #expect(images.data(forCached: url) == png)
        #expect(episode.chapters[0].imageURL == nil)

        // iOS purged the cache: the next launch reads the audio file again.
        try FileManager.default.removeItem(at: images.directory)
        await makeService().load(episode)
        #expect(audio.calls == 2)
        #expect(images.data(forCached: try #require(episode.chapters[1].imageURL)) == png)
    }

    // MARK: Helpers

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Chapters"))
        return try Data(contentsOf: url)
    }

    final class AudioStub: Sendable {
        private let state = Mutex((result: AudioChapterResult?.none, fails: false, calls: 0))
        var result: AudioChapterResult? {
            get { state.withLock { $0.result } }
            set { state.withLock { $0.result = newValue } }
        }
        var fails: Bool {
            get { state.withLock { $0.fails } }
            set { state.withLock { $0.fails = newValue } }
        }
        var calls: Int { state.withLock { $0.calls } }

        func load(_ url: URL) throws -> AudioChapterResult? {
            try state.withLock {
                $0.calls += 1
                if $0.fails { throw URLError(.timedOut) }
                return $0.result
            }
        }
    }
}
