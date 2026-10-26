import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Debug builds in the simulator play the made-up library from silent MP3s in the app's
/// container (`SimulatorLibrary`): one per episode length, long enough for the episode.
@MainActor
struct SampleDataSimulatorAudioTests {
    nonisolated private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
    }

    @Test(arguments: [1, 60, 16 * 60])
    func silentMP3LastsAsLongAsAsked(seconds: Int) async throws {
        let data = SampleData.silentMP3(seconds: seconds)
        let frames = Int((Double(seconds) / 0.036).rounded(.up))
        #expect(data.count == frames * 36)
        #expect(data.prefix(4) == Data([0xFF, 0xF3, 0x18, 0xC0]))

        let file = URL.temporaryDirectory.appending(path: "silent-\(UUID().uuidString).mp3")
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let asset = AVURLAsset(url: file, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - Double(seconds)) < 0.1)

        // It decodes: AVFoundation reads it as audio, not only as a length.
        let audio = try AVAudioFile(forReading: file)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4_096))
        try audio.read(into: buffer)
        #expect(buffer.frameLength > 0)
    }

    @Test func madeUpEpisodesPlayTheSilenceOfTheirLength() throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        try SampleData.insertScreenshots(into: context, german: true, artwork: { _ in nil }, now: Self.now)
        let own = Podcast(feedURL: URL(string: "https://feeds.example.org/own.xml")!, title: "Own", subscribedAt: Self.now)
        context.insert(own)
        let ownEpisode = Episode(
            guid: "own-1", title: "Own", publishedAt: Self.now, audioURL: URL(string: "https://feeds.example.org/1.mp3")!)
        ownEpisode.duration = 600
        ownEpisode.podcast = own
        context.insert(ownEpisode)
        try context.save()

        try SampleData.updateScreenshotAudio(in: context) { URL(string: "file:///old/\($0).mp3") }
        // A new build in the simulator moves the container; the measured duration of a played
        // episode is a few milliseconds off the stated one and keeps its file.
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        let played = try #require(episodes.first { $0.podcast?.feedURL.host() == "example.com" })
        let stated = try #require(played.duration)
        played.duration = stated + 0.012
        try SampleData.updateScreenshotAudio(in: context) { URL(string: "file:///new/\($0).mp3") }

        let madeUp = episodes.filter { $0 != ownEpisode }
        #expect(madeUp.count >= 20)
        for episode in madeUp {
            let seconds = try #require(episode.duration.map { Int($0.rounded()) })
            #expect(episode.audioURL == URL(string: "file:///new/\(seconds).mp3"))
        }
        #expect(played.audioURL == URL(string: "file:///new/\(Int(stated)).mp3"))
        #expect(ownEpisode.audioURL == URL(string: "https://feeds.example.org/1.mp3"))
    }
}
