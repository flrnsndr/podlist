import PodlistKit
import SwiftUI

struct PodcastPreviewRoute: Hashable {
    var feedURL: URL
    var title: String?
    var artworkURL: URL?

    init(feedURL: URL, title: String?, artworkURL: URL?) {
        self.feedURL = feedURL
        self.title = title
        self.artworkURL = artworkURL
    }

    init(_ result: PodcastSearchResult) {
        self.init(feedURL: result.feedURL, title: result.title, artworkURL: result.artworkURL)
    }
}

/// Vorschau des Podcasts → Abonnieren (concept §4.5). Nothing is stored before subscribing.
struct PodcastPreviewView: View {
    let route: PodcastPreviewRoute
    @Environment(LibraryService.self) private var library
    @State private var feed: ParsedFeed?
    @State private var loadFailed = false
    @State private var isSubscribed = false
    @State private var isSubscribing = false
    @State private var subscribeFailed = false
    @State private var subscribedPodcast: Podcast?

    var body: some View {
        List {
            Section {
                header
            }
            if let feed {
                Section("Episodes") {
                    ForEach(feed.episodes.prefix(30), id: \.self) { episode in
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = episode.publishedAt {
                                Text(date, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(episode.title).font(.headline).lineLimit(2)
                            if let duration = episode.duration {
                                Text(duration.durationText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if loadFailed {
                ContentUnavailableView("Feed Unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text("The feed could not be loaded. Check the URL and your connection."))
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle(feed?.title ?? route.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $subscribedPodcast) { AssignPlaylistsView(podcast: $0, isAfterSubscribing: true) }
        .alert("The feed could not be loaded. Check the URL and your connection.", isPresented: $subscribeFailed) {
            Button("OK") {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(url: feed?.artworkURL ?? route.artworkURL, cornerRadius: 12)
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed?.title ?? route.title ?? "").font(.title3.bold())
                    if let author = feed?.author {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if let summary = feed?.summary {
                Text(HTMLText.plainText(fromHTML: summary)).font(.callout).lineLimit(4)
            }
            subscribeButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var subscribeButton: some View {
        if isSubscribed {
            Label("Subscribed", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
                .foregroundStyle(.secondary)
        } else {
            Button {
                Task { await subscribe() }
            } label: {
                Group {
                    if isSubscribing { ProgressView() } else { Text("Subscribe") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubscribing)
        }
    }

    private func load() async {
        isSubscribed = (try? library.isSubscribed(feedURL: route.feedURL)) ?? false
        guard feed == nil else { return }
        do {
            feed = try await library.preview(route.feedURL)
        } catch {
            loadFailed = true
        }
    }

    private func subscribe() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            subscribedPodcast = try await library.subscribe(to: route.feedURL)
            isSubscribed = true
        } catch {
            subscribeFailed = true
        }
    }
}
