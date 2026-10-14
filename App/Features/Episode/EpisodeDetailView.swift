import PodlistKit
import SwiftUI

/// Folgendetails: the same sheet everywhere (concept §4.5): play, Up Next, "Playlist ab
/// hier" (only when opened from a playlist), played status, playlists, chapters and show
/// notes with tappable timestamps (A30, A31), the download (concept §4.7).
struct EpisodeDetailView: View {
    let episode: Episode
    /// The playlist the details were opened from.
    var playlist: Playlist?
    @Environment(PlayerController.self) private var player
    @Environment(UpNextService.self) private var upNext
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
                                Text(podcast.title).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(episode.title).font(.title3.bold())
                            Text(episode.publishedAt, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                            EpisodeStatusLine(episode: episode)
                        }
                    }
                    HStack {
                        Button {
                            isPlayingThis ? player.pause() : upNext.play(episode, in: playlist)
                        } label: {
                            Label(isPlayingThis ? "Pause" : "Play", systemImage: isPlayingThis ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        PlayedToggle(episode: episode)
                            .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                    upNextActions
                    download
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
            .task(id: episode.uuid) { await chapterService?.load(episode) }
            .sheet(isPresented: $isAddingToPlaylist) { AddToPlaylistView(episode: episode) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "Als Nächstes", "Am Ende" and, opened from a playlist, "Playlist ab hier" (concept §4.5).
    private var upNextActions: some View {
        VStack(spacing: 8) {
            HStack {
                Button { upNext.playNext(episode) } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .frame(maxWidth: .infinity)
                }
                Button { upNext.playLast(episode) } label: {
                    Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward")
                        .frame(maxWidth: .infinity)
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

    /// Download state and action (concept §4.7).
    private var download: some View {
        HStack {
            DownloadButton(episode: episode)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("downloadButton")
            DownloadDetailText(episode: episode)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        upNext.play(episode, in: playlist, at: time)
    }

    /// Playlist membership (concept §4.5); tapping opens "Zu Playlist …".
    private var playlists: some View {
        let playlists = (episode.playlistEntries ?? []).compactMap(\.playlist).sorted { $0.displayOrder < $1.displayOrder }
        return FlowLayout {
            ForEach(playlists) { playlist in
                PlaylistChip(playlist: playlist, isSelected: true) { isAddingToPlaylist = true }
            }
            PlaylistChip(title: String(localized: "Add to Playlist…"), symbolName: "music.note.list", isSelected: false) {
                isAddingToPlaylist = true
            }
            .accessibilityIdentifier("addToPlaylist")
        }
    }
}
