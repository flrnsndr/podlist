import Foundation
import SwiftData

extension SampleData {
    /// `seconds` of silence as an MP3 (MPEG-2 Layer III, 16 kHz mono, 8 kbit/s, ~1 KB per
    /// second): the same empty frame over and over, so the made-up episodes of Debug builds in
    /// the simulator have something to play (`SimulatorLibrary`).
    public static func silentMP3(seconds: Int) -> Data {
        // Header (MPEG-2, Layer III, no CRC, 8 kbit/s, 16 kHz, mono), 9 bytes of side
        // information with no audio data in them, and zero padding: 36 bytes for 36 ms.
        var frame = Data([0xFF, 0xF3, 0x18, 0xC0])
        frame.append(Data(count: 32))
        let count = Int((Double(seconds) / 0.036).rounded(.up))
        var data = frame
        data.reserveCapacity(count * frame.count)
        while data.count < count * frame.count {
            data.append(data.prefix(count * frame.count - data.count))
        }
        return data
    }

    /// Points the made-up episodes (podcasts at `https://example.com/<slug>/feed.xml`) at the
    /// silent MP3 `audio` returns for their length in whole seconds; their files live in the
    /// app's container, whose path changes when the simulator installs a new build.
    public static func updateScreenshotAudio(in context: ModelContext, audio: (Int) -> URL?) throws {
        for podcast in try context.fetch(FetchDescriptor<Podcast>()) where podcast.feedURL.host() == "example.com" {
            for episode in podcast.episodes ?? [] {
                guard let duration = episode.duration, duration > 0,
                      let url = audio(Int(duration.rounded())), episode.audioURL != url else { continue }
                episode.audioURL = url
            }
        }
        if context.hasChanges { try context.save() }
    }
}
