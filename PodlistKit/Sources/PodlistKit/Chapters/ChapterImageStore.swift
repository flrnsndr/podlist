import Foundation

/// Chapter images embedded in audio files (N29), kept in the caches directory. A chapter
/// refers to its image with a stable `podlist-chapter-image:` URL (file paths of the app
/// container change with updates); iOS may purge the files, then the chapters are read again.
public struct ChapterImageStore: Sendable {
    public static let scheme = "podlist-chapter-image"
    public static let shared = ChapterImageStore()

    public let directory: URL
    private let session: URLSession

    public init(
        directory: URL = URL.cachesDirectory.appending(path: "ChapterImages", directoryHint: .isDirectory),
        session: URLSession = .shared
    ) {
        self.directory = directory
        self.session = session
    }

    public static func isChapterImage(_ url: URL) -> Bool {
        url.scheme == scheme
    }

    /// Stores the image of chapter `index` and returns the URL the chapter keeps.
    func save(_ data: Data, episode: UUID, index: Int) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(episode.uuidString)-\(index)"
        try data.write(to: directory.appending(path: name), options: .atomic)
        // The name is a UUID and a number, always a valid URL.
        return URL(string: "\(Self.scheme):\(name)")!
    }

    /// The cached image data for a `podlist-chapter-image:` URL; nil if missing.
    public func data(forCached url: URL) -> Data? {
        guard let file = file(for: url) else { return nil }
        return try? Data(contentsOf: file)
    }

    /// Deletes the cached images of these episodes (they are being deleted, A42).
    func removeImages(of episodes: Set<UUID>) {
        guard !episodes.isEmpty else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for name in names {
            // "<uuid>-<index>"
            guard let id = UUID(uuidString: String(name.prefix(36))), episodes.contains(id) else { continue }
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// Some chapter refers to a cached image that is gone.
    func isMissingImages(of chapters: [Chapter]) -> Bool {
        chapters.contains { chapter in
            guard let url = chapter.imageURL, let file = file(for: url) else { return false }
            return !FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        }
    }

    /// Image data for any artwork URL: cached chapter images from disk, everything else over
    /// the network (through `URLCache.shared`).
    public func imageData(for url: URL) async -> Data? {
        if Self.isChapterImage(url) { return data(forCached: url) }
        return try? await session.data(from: Self.secureURL(url)).0
    }

    /// Plain `http` artwork is loaded via `https`: App Transport Security blocks `http` outside
    /// AVFoundation (like feeds, `FeedLoader.normalizedFeedURL`). Other URLs stay as they are.
    static func secureURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    private func file(for url: URL) -> URL? {
        guard Self.isChapterImage(url) else { return nil }
        let name = String(url.absoluteString.dropFirst(Self.scheme.count + 1))
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return directory.appending(path: name)
    }
}
