import SwiftUI

/// Whether hidden playlists are shown (N66): one switch for the whole app, flipped by any
/// "Mehr ›" button. Not stored; the app collapses it when it goes to the background.
@MainActor @Observable
final class HiddenPlaylistsReveal {
    var isRevealed = false
}

/// "Mehr (2) ›" / "‹ Weniger" at the end of a chip row (library, inbox, assignment sheet).
struct HiddenPlaylistsChip: View {
    /// Playlists behind the button; without any there is no button.
    let count: Int
    @Environment(HiddenPlaylistsReveal.self) private var reveal

    var body: some View {
        if count > 0 {
            Button { reveal.isRevealed.toggle() } label: {
                HStack(spacing: 4) {
                    if reveal.isRevealed {
                        Image(systemName: "chevron.left").font(.caption.bold())
                        Text("Less")
                    } else {
                        Text("More (\(count))")
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(.primary)
                .background(Color.secondary.opacity(0.15), in: .capsule)
            }
            .buttonStyle(.plain)
            .hiddenPlaylistsAccessibility(count: count, isRevealed: reveal.isRevealed)
            .accessibilityIdentifier("hiddenPlaylistsButton")
        }
    }
}

/// The same as a list row (playlists tab, "Zu Playlist …").
struct HiddenPlaylistsRow: View {
    let count: Int
    @Environment(HiddenPlaylistsReveal.self) private var reveal

    var body: some View {
        if count > 0 {
            Button { reveal.isRevealed.toggle() } label: {
                HStack {
                    if reveal.isRevealed {
                        Label("Less", systemImage: "chevron.up")
                    } else {
                        Label("\(count) hidden playlists", systemImage: "eye.slash")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.tint)
            }
            .hiddenPlaylistsAccessibility(count: count, isRevealed: reveal.isRevealed)
            .accessibilityIdentifier("hiddenPlaylistsRow")
        }
    }
}

private extension View {
    func hiddenPlaylistsAccessibility(count: Int, isRevealed: Bool) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isRevealed ? Text("Hide Hidden Playlists") : Text("Show Hidden Playlists"))
            .accessibilityValue(isRevealed ? Text(verbatim: "") : Text(count, format: .number))
            .accessibilityAddTraits(.isButton)
    }
}
