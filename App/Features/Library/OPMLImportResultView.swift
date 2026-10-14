import PodlistKit
import SwiftUI

/// Result of an OPML import with failures (A34): what was subscribed, and every podcast
/// that could not be loaded with its reason.
struct OPMLImportResultView: View {
    let result: OPMLImportResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(result.subscribed) podcasts subscribed.")
                    if result.alreadySubscribed > 0 {
                        Text("\(result.alreadySubscribed) were already subscribed.")
                    }
                }
                Section("Could Not Be Loaded") {
                    ForEach(result.failed, id: \.outline) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.outline.title ?? failure.outline.feedURL.host() ?? failure.outline.feedURL.absoluteString)
                                .font(.headline)
                            Text(failure.reason.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(verbatim: failure.outline.feedURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Import finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension FeedFailureReason {
    /// Why the feed could not be loaded, for the user.
    var text: LocalizedStringResource {
        switch self {
        case .notFound: "Not found: there is no feed at this address any more."
        case .accessDenied: "Access denied: the feed needs a login."
        case .httpStatus(let status): "Server error (HTTP \(status))."
        case .notAFeed: "Not a feed: the address leads to a web page."
        case .malformedFeed: "The feed is damaged."
        case .invalidCertificate: "Invalid certificate: the server's secure connection cannot be trusted."
        case .insecureConnection: "Only reachable without encryption (http)."
        case .serverNotFound: "Server not found."
        case .offline: "No internet connection."
        case .timedOut: "The server did not answer in time."
        case .invalidURL: "Invalid feed address."
        case .other: "Unknown error."
        }
    }
}
