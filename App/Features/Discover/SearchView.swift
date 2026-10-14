import PodlistKit
import SwiftUI

/// Suche: the iTunes directory; a pasted feed URL opens its preview directly.
struct SearchView: View {
    @State private var model = SearchModel()
    @Environment(\.podcastDirectory) private var directory

    var body: some View {
        NavigationStack {
            List {
                if let url = model.feedURL {
                    NavigationLink(value: PodcastPreviewRoute(feedURL: url, title: nil, artworkURL: nil)) {
                        Label("Open Feed URL", systemImage: "link")
                    }
                }
                ForEach(model.results) { result in
                    NavigationLink(value: PodcastPreviewRoute(result)) {
                        SearchResultRow(result: result)
                    }
                }
            }
            .overlay { overlay }
            .navigationTitle("Search")
            .navigationDestination(for: PodcastPreviewRoute.self) { PodcastPreviewView(route: $0) }
            .searchable(text: $model.query, prompt: Text("Podcasts or feed URL"))
            .task(id: model.query) { await model.search(using: directory) }
        }
    }

    @ViewBuilder private var overlay: some View {
        switch model.status {
        case .idle where model.results.isEmpty && model.feedURL == nil:
            ContentUnavailableView("Find Podcasts", systemImage: "magnifyingglass",
                                   description: Text("Search for podcasts or add a feed URL."))
        case .searching where model.results.isEmpty:
            ProgressView()
        case .failed:
            ContentUnavailableView("Search Failed", systemImage: "wifi.exclamationmark",
                                   description: Text("Check your connection and try again."))
        case .done where model.results.isEmpty && model.feedURL == nil:
            ContentUnavailableView.search(text: model.query)
        default:
            EmptyView()
        }
    }
}

/// Search with debounce (concept §6.2: a real screen-logic view model).
@MainActor @Observable
final class SearchModel {
    enum Status { case idle, searching, done, failed }

    var query = ""
    private(set) var results: [PodcastSearchResult] = []
    private(set) var status = Status.idle

    /// The query, if it is a feed URL.
    var feedURL: URL? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("://") || text.hasPrefix("feed:") else { return nil }
        return URL(string: text).flatMap(FeedLoader.normalizedFeedURL)
    }

    func search(using directory: PodcastDirectory) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, feedURL == nil else {
            results = []
            status = .idle
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(350))
            status = .searching
            let country = Locale.current.region?.identifier ?? "US"
            results = try await directory.search(term, country: country)
            status = .done
        } catch is CancellationError {
            // A newer query replaced this one.
        } catch {
            results = []
            status = .failed
        }
    }
}

struct SearchResultRow: View {
    let result: PodcastSearchResult

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: result.artworkURL, cornerRadius: 6)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.headline).lineLimit(2)
                if let author = result.author {
                    Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
