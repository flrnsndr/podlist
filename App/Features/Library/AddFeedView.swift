import PodlistKit
import SwiftUI

/// Subscribe by entering a feed URL (private feeds, podcasts outside the directory).
struct AddFeedView: View {
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLoading = false
    @State private var failed = false
    @State private var subscribedPodcast: Podcast?

    private var url: URL? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(FeedLoader.normalizedFeedURL)
    }

    var body: some View {
        if let subscribedPodcast {
            AssignPlaylistsView(podcast: subscribedPodcast, isAfterSubscribing: true)
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed URL", text: $text, prompt: Text(verbatim: "https://example.com/feed.xml"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("feedURLField")
                        .onSubmit(subscribe)
                } footer: {
                    if failed {
                        Text("The feed could not be loaded. Check the URL and your connection.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Feed URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Subscribe", action: subscribe).disabled(url == nil)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func subscribe() {
        guard let url, !isLoading else { return }
        isLoading = true
        failed = false
        Task {
            defer { isLoading = false }
            do {
                if let podcast = try await library.subscribe(to: url) {
                    subscribedPodcast = podcast
                } else {
                    dismiss()
                }
            } catch {
                failed = true
            }
        }
    }
}
