#if DEBUG && targetEnvironment(simulator)
import Foundation
import PodlistKit
import SwiftData

/// Debug builds in the simulator start with the made-up library of `-screenshots`, so a
/// problem can be shown without subscribing first. Once per install, and only into a store
/// without podcasts; deleting the app starts over. Its episodes play silent MP3s of their
/// length from Caches. Release and device builds never get here.
enum SimulatorLibrary {
    private static let key = "didOfferSimulatorLibrary"

    @MainActor
    static func prepare(context: ModelContext) throws {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: key) {
            try SampleData.insertSimulatorLibraryIfEmpty(
                into: context, german: Bundle.main.preferredLocalizations.first == "de",
                artwork: ScreenshotArtwork.url(for:))
            defaults.set(true, forKey: key)
        }
        try SampleData.updateScreenshotArtwork(in: context, artwork: ScreenshotArtwork.url(for:))
        try SampleData.updateScreenshotAudio(in: context, audio: silence(seconds:))
    }

    /// Written once per length; ~1 KB per second, all lengths of the library together ~80 MB.
    private static func silence(seconds: Int) -> URL? {
        let directory = URL.cachesDirectory.appending(path: "SimulatorAudio", directoryHint: .isDirectory)
        let file = directory.appending(path: "\(seconds).mp3")
        if FileManager.default.fileExists(atPath: file.path()) { return file }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try SampleData.silentMP3(seconds: seconds).write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }
}
#endif
