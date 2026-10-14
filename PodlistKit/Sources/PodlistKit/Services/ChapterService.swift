import Foundation
import SwiftData
import os

/// Loads an episode's chapters from the best source (concept §4.6, ADR 0005) and stores
/// them in `Episode.chapters`: Podcasting 2.0 JSON, Podlove (already stored by the feed
/// refresher), the audio file (ID3 / MP4, with embedded images N29) and show-notes
/// timestamps. Called when an episode is opened or loaded into the player (A29); network
/// and AVFoundation work runs off the main actor, only value types come back.
@MainActor
public final class ChapterService {
    public typealias AudioLoader = @Sendable (URL) async throws -> AudioChapterResult?

    private let context: ModelContext
    private let session: URLSession
    private let images: ChapterImageStore
    private let loadAudio: AudioLoader
    /// Episodes whose JSON chapters / audio file were looked at since launch (A29).
    private var checkedJSON: Set<UUID> = []
    private var checkedAudio: Set<UUID> = []
    private var running: [UUID: Task<Void, Never>] = [:]

    public init(
        context: ModelContext, session: URLSession = .shared, images: ChapterImageStore = .shared,
        loadAudio: @escaping AudioLoader = { try await AudioChapters.load(from: $0) }
    ) {
        self.context = context
        self.session = session
        self.images = images
        self.loadAudio = loadAudio
    }

    /// Looks for better chapters; returns when done. Parallel calls for the same episode
    /// wait for the running one.
    public func load(_ episode: Episode) async {
        let id = episode.uuid
        if let task = running[id] {
            await task.value
            return
        }
        let task = Task { await self.run(episode) }
        running[id] = task
        await task.value
        running[id] = nil
    }

    private func run(_ episode: Episode) async {
        storeShowNotesChapters(of: episode)
        await loadJSONChapters(of: episode)
        await loadAudioChapters(of: episode)
    }

    // MARK: Sources

    private func storeShowNotesChapters(of episode: Episode) {
        guard ChapterSelection.shouldReplace(episode.chaptersSource, with: .shownotes),
              let notes = episode.showNotes else { return }
        let chapters = ShowNotesTimestamps.chapters(inPlainText: HTMLText.plainText(fromHTML: notes), duration: episode.duration)
        store(chapters, from: .shownotes, in: episode)
    }

    private func loadJSONChapters(of episode: Episode) async {
        guard let url = episode.chaptersURL, checkedJSON.insert(episode.uuid).inserted else { return }
        do {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("Podlist/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FeedLoadError.http(status: http.statusCode)
            }
            let chapters = try JSONChapters.parse(data, baseURL: url)
            store(chapters, from: .json, in: episode)
        } catch {
            Logger.chapters.error("JSON chapters failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// The audio file is read when nothing better than show notes is stored, or when the
    /// cached images of its chapters are gone.
    private func loadAudioChapters(of episode: Episode) async {
        let needsAudio = switch episode.chaptersSource {
        case nil, .shownotes: true
        case .id3, .mp4: images.isMissingImages(of: episode.chapters)
        case .json, .podlove: false
        }
        guard needsAudio, checkedAudio.insert(episode.uuid).inserted else { return }
        do {
            guard let result = try await loadAudio(episode.audioURL), Self.exists(episode) else { return }
            guard ChapterSelection.shouldReplace(episode.chaptersSource, with: result.source) else { return }
            var chapters = result.chapters
            for (index, data) in result.images where chapters.indices.contains(index) {
                chapters[index].imageURL = try images.save(data, episode: episode.uuid, index: index)
            }
            store(chapters, from: result.source, in: episode)
        } catch {
            Logger.chapters.error("Audio chapters failed for \(episode.audioURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Writing

    private static func exists(_ episode: Episode) -> Bool {
        episode.modelContext != nil && !episode.isDeleted
    }

    /// Stores normalized chapters if they are not empty and the source may replace the stored one.
    private func store(_ chapters: [Chapter], from source: ChapterSource, in episode: Episode) {
        // The episode may have been deleted while loading (unsubscribing).
        guard Self.exists(episode), ChapterSelection.shouldReplace(episode.chaptersSource, with: source) else { return }
        let normalized = ChapterSelection.normalized(chapters, duration: episode.duration)
        guard !normalized.isEmpty else { return }
        episode.setIfChanged(\.chapters, normalized)
        episode.chaptersSource = source
        do {
            try context.save()
        } catch {
            Logger.chapters.error("Saving chapters failed: \(String(describing: error), privacy: .public)")
        }
    }
}
