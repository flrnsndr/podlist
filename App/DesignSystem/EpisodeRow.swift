import PodlistKit
import SwiftUI

/// One episode in a list: date, title, listening state and a quick play button (concept §4.5).
/// The one row for episodes everywhere (podcast, playlist, inbox, Up Next), so an episode
/// looks the same wherever it shows up.
struct EpisodeRow: View {
    let episode: Episode
    /// In lists that mix podcasts: artwork and podcast title.
    var showsPodcast = false
    /// The playlist the row is shown in: its ▶ jumps inside it while it runs (scenario 12).
    var playlist: Playlist?
    /// In the podcast's episode list: a button that adds the episode to the podcast's playlists.
    var addsToPodcastPlaylists = false
    /// Off where a tap on the row or other actions start playback (inbox, Up Next).
    var showsPlayButton = true
    /// Playlists shown as pills under the status line, e.g. the one a queued episode plays in.
    var tags: [Playlist] = []

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsPodcast {
                ArtworkView(url: episode.imageURL ?? episode.podcast?.artworkURL, cornerRadius: 6)
                    .frame(width: 52)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                // The podcast matters more than the date: first and stronger.
                HStack(spacing: 4) {
                    if showsPodcast, let podcast = episode.podcast {
                        Text(podcast.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    Text(episode.publishedAt, format: .dateTime.day().month().year())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .font(.caption)
                Text(episode.title)
                    .font(.headline)
                    .lineLimit(2)
                EpisodeStatusLine(episode: episode)
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags) { PlaylistTag(playlist: $0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if addsToPodcastPlaylists {
                AddToPodcastPlaylistsButton(episode: episode)
            }
            if showsPlayButton {
                PlayButton(episode: episode, playlist: playlist)
            }
        }
        .opacity(episode.isPlayed ? 0.6 : 1)
    }
}

/// Adds the episode to every playlist its podcast is assigned to, like "Hinzufügen" in the
/// inbox (A59), with the same "Rückgängig" banner. A checkmark once it is in all of them;
/// nothing for a podcast without playlists.
struct AddToPodcastPlaylistsButton: View {
    let episode: Episode
    @Environment(InboxService.self) private var inbox

    var body: some View {
        let assigned = (episode.podcast?.assignments ?? []).compactMap(\.playlist).sorted { $0.displayOrder < $1.displayOrder }
        let containing = Set((episode.playlistEntries ?? []).compactMap(\.playlist))
        let missing = assigned.filter { !containing.contains($0) }
        let names = assigned.map(\.displayName).formatted(.list(type: .and))
        if !assigned.isEmpty {
            Button {
                try? inbox.addToPodcastPlaylists(episode)
            } label: {
                Image(systemName: missing.isEmpty ? "text.badge.checkmark" : "text.badge.plus")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .disabled(missing.isEmpty)
            .accessibilityLabel(missing.isEmpty ? Text("Already in \(names)") : Text("Add to \(names)"))
            .accessibilityIdentifier("addToPodcastPlaylists")
        }
    }
}

/// The download state (concept §4.7), then played ✓, remaining time with progress, or the duration.
struct EpisodeStatusLine: View {
    let episode: Episode
    /// Off where the row draws its own bar (listening history).
    var showsProgress = true

    var body: some View {
        HStack(spacing: 6) {
            DownloadStatusIcon(episode: episode)
            if episode.isPlayed {
                Label("Played", systemImage: "checkmark.circle")
            } else if episode.playbackPosition > 0, let duration = episode.duration, duration > 0 {
                HStack(spacing: 6) {
                    if showsProgress {
                        ProgressView(value: min(episode.playbackPosition, duration), total: duration)
                            .frame(width: 48)
                            .accessibilityHidden(true)
                    }
                    Text("\(max(0, duration - episode.playbackPosition).durationText) left")
                }
            } else if let duration = episode.duration {
                Text(duration.durationText)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// ▶ / ❚❚ for one episode: "▶ Abspielen" (scenario 10), in the running playlist a jump
/// inside it (scenario 12).
struct PlayButton: View {
    let episode: Episode
    var playlist: Playlist?
    @Environment(PlayerController.self) private var player
    @Environment(UpNextService.self) private var upNext

    private var isPlayingThis: Bool { player.episode == episode && player.isPlaying }

    var body: some View {
        Button {
            isPlayingThis ? player.pause() : upNext.play(episode, in: playlist)
        } label: {
            Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isPlayingThis ? Text("Pause") : Text("Play"))
    }
}
