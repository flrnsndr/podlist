import Foundation
import os

/// Podcast search in the iTunes directory (concept §7: free, no key) and in ARD Sounds
/// (concept §4.13, every region, A82): one list, see `ARDSounds.merge`.
public struct PodcastDirectory: Sendable {
    private let session: URLSession
    /// How long the results wait for ARD once iTunes has answered.
    private let ardGrace: Duration

    public init(session: URLSession = .shared, ardGrace: Duration = .seconds(1)) {
        self.session = session
        self.ardGrace = ardGrace
    }

    /// `country`: ISO region code, e.g. "DE"; results follow the store of that country.
    /// ARD failing or being slow never fails or holds up the iTunes results.
    public func search(_ term: String, country: String) async throws -> [PodcastSearchResult] {
        let ard = Task { [session] in
            do {
                return try await ARDSoundsClient(session: session).search(term)
            } catch {
                Logger.feeds.error("ARD search failed: \(String(describing: error), privacy: .public)")
                return [ARDSounds.Show]()
            }
        }
        return try await withTaskCancellationHandler {
            try await search(term, country: country, ard: ard)
        } onCancel: {
            ard.cancel()
        }
    }

    private func search(
        _ term: String, country: String, ard: Task<[ARDSounds.Show], Never>
    ) async throws -> [PodcastSearchResult] {
        let itunes: [PodcastSearchResult]
        do {
            itunes = try await searchITunes(term, country: country)
        } catch {
            // Without iTunes, ARD alone is better than nothing.
            let shows = await ard.value
            if shows.isEmpty { throw error }
            return ARDSounds.merge(iTunes: [], ard: shows, term: term)
        }
        return ARDSounds.merge(iTunes: itunes, ard: await Self.value(of: ard, waitingAtMost: ardGrace) ?? [], term: term)
    }

    private func searchITunes(_ term: String, country: String) async throws -> [PodcastSearchResult] {
        let request = URLRequest(url: ITunesSearch.searchURL(term: term, country: country), timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedLoadError.http(status: http.statusCode)
        }
        return try ITunesSearch.decode(data)
    }

    /// The task's value, or `nil` (and the task cancelled) if it takes longer than `limit`.
    private static func value<Value: Sendable>(of task: Task<Value, Never>, waitingAtMost limit: Duration) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            if first == nil { task.cancel() }
            group.cancelAll()
            return first
        }
    }
}
