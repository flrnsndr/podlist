import PodlistKit
import SwiftUI

/// Folgendetails: the same sheet everywhere (concept §4.5): play, Up Next, "Playlist ab
/// hier" (only when opened from a playlist), playlists, chapters and show notes with
/// tappable timestamps (A30, A31). Played status and download live in the episode rows'
/// swipe actions and context menu (N103).
struct EpisodeDetailView: View {
    let episode: Episode
    /// The playlist the details were opened from.
    var playlist: Playlist?
    @Environment(PlayerController.self) private var player
    @Environment(UpNextService.self) private var upNext
    @Environment(InboxService.self) private var inbox
    @Environment(\.chapterService) private var chapterService
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingToPlaylist = false

    private var isPlayingThis: Bool { player.episode == episode && player.isPlaying }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        ArtworkView(url: episode.imageURL ?? episode.podcast?.artworkURL)
                            .frame(width: 88)
                        VStack(alignment: .leading, spacing: 4) {
                            if let podcast = episode.podcast {
                                NavigationLink(value: podcast) {
                                    HStack(spacing: 4) {
                                        Text(podcast.title)
                                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("episodePodcastLink")
                            }
                            Text(episode.title).font(.title3.bold())
                            Text(episode.publishedAt, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                            EpisodeStatusLine(episode: episode)
                        }
                    }
                    HStack {
                        Button {
                            isPlayingThis ? player.pause() : upNext.play(episode)
                        } label: {
                            Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        // Only an explicit "from the start" begins again; ▶ always goes on.
                        if episode.playbackPosition > 0 {
                            Button("Play from the Start", systemImage: "backward.end") { playFromStart() }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("episodeFromStart")
                        }
                    }
                    .controlSize(.large)
                    upNextActions
                    playlists
                    chapters
                    if let notes = episode.showNotes {
                        Text(HTMLText.attributedString(fromHTML: notes))
                            .font(.body)
                            .textSelection(.enabled)
                            .environment(\.openURL, OpenURLAction { url in
                                guard let time = ShowNotesTimestamps.time(from: url) else { return .systemAction }
                                play(at: time)
                                return .handled
                            })
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .task(id: episode.uuid) { await chapterService?.load(episode) }
            .sheet(isPresented: $isAddingToPlaylist) { AddToPlaylistView(episode: episode) }
            .undoBanner()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Three actions of one rank (N103), each adds the episode to its podcast's playlists
    /// ("+") with "Rückgängig": "Zu Playlists" only that, "Als Nächstes" and "Am Ende" also put
    /// it into the queue. Once the episode is in all of them, "Zu Playlists" turns grey with a
    /// checkmark ("In Playlists") and opens "Zu Playlist …", like a long press. Opened from a
    /// playlist, "Playlist ab hier" below (concept §4.5).
    private var upNextActions: some View {
        VStack(spacing: 8) {
            HStack {
                let isInPodcastPlaylists = isInAllPodcastPlaylists
                Menu {
                    Button("Choose Playlists…", systemImage: "checklist") { isAddingToPlaylist = true }
                } label: {
                    if isInPodcastPlaylists {
                        actionLabel("In Playlists", leading: "checkmark", symbols: ["music.note.list"])
                    } else {
                        actionLabel("To Playlists", symbols: ["music.note.list"])
                    }
                } primaryAction: {
                    if missingPodcastPlaylists.isEmpty {
                        isAddingToPlaylist = true
                    } else {
                        try? inbox.addToPodcastPlaylists(episode)
                    }
                }
                .tint(isInPodcastPlaylists ? Color.secondary : nil)
                .accessibilityIdentifier("addToPlaylist")
                Button {
                    try? inbox.addToPodcastPlaylistsAndQueue(episode, next: true)
                } label: {
                    actionLabel("Play Next", symbols: ["music.note.list", "text.line.first.and.arrowtriangle.forward"])
                }
                Button {
                    try? inbox.addToPodcastPlaylistsAndQueue(episode, next: false)
                } label: {
                    actionLabel("Play Last", symbols: ["music.note.list", "text.line.last.and.arrowtriangle.forward"])
                }
            }
            if let playlist {
                PlaylistStartButton(playlist: playlist, episode: episode) { _, _ in
                    Label("Play Playlist From Here", systemImage: "play.square.stack")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("playPlaylistFromHere")
            }
        }
        .buttonStyle(.bordered)
    }

    /// "+" (or ✓ once done) and where the episode goes (playlists, also the queue) over the
    /// action's name.
    private func actionLabel(_ title: LocalizedStringKey, leading: String = "plus", symbols: [String]) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: leading).font(.caption.weight(.bold))
                ForEach(symbols, id: \.self) { Image(systemName: $0) }
            }
            .font(.title3)
            .minimumScaleFactor(0.7)
            .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Chapters (concept §4.6); a tap plays the episode from there (A30).
    @ViewBuilder private var chapters: some View {
        let chapters = ChapterSelection.normalized(episode.chapters, duration: episode.duration)
        if ChapterSelection.visible(chapters).isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters").font(.headline)
                ChapterList(
                    chapters: chapters,
                    currentIndex: player.episode == episode ? player.chapterContext.index : nil
                ) { chapter in
                    play(at: chapter.start)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// Plays this episode from `time` (a chapter or a timestamp in the show notes, A30).
    private func play(at time: TimeInterval) {
        upNext.play(episode, at: time)
    }

    /// From the start, after the podcast's intro (A28), like in the listening history.
    private func playFromStart() {
        play(at: PlaybackRules.startPosition(
            stored: 0, isPlayed: false, duration: episode.duration,
            skipIntro: TimeInterval(episode.podcast?.skipIntroSeconds ?? 0)))
    }

    /// Playlist membership (concept §4.5); tapping a playlist opens "Zu Playlist …".
    @ViewBuilder private var playlists: some View {
        let playlists = (episode.playlistEntries ?? []).compactMap(\.playlist).sorted { $0.displayOrder < $1.displayOrder }
        if !playlists.isEmpty {
            FlowLayout {
                ForEach(playlists) { playlist in
                    PlaylistChip(playlist: playlist, isSelected: true) { isAddingToPlaylist = true }
                }
            }
        }
    }

    /// The episode is in every playlist its podcast is assigned to (and there is one).
    private var isInAllPodcastPlaylists: Bool {
        !(episode.podcast?.assignments ?? []).isEmpty && missingPodcastPlaylists.isEmpty
    }

    /// The playlists the episode's podcast is assigned to that do not have it yet.
    private var missingPodcastPlaylists: [Playlist] {
        let current = Set((episode.playlistEntries ?? []).compactMap(\.playlist))
        return (episode.podcast?.assignments ?? []).compactMap(\.playlist)
            .filter { !current.contains($0) }
            .sorted { $0.displayOrder < $1.displayOrder }
    }
}
