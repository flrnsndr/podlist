import PodlistKit
import SwiftData
import SwiftUI

struct RootView: View {
    enum Section: Hashable { case library, inbox, playlists, queue, search }

    @Environment(PlayerController.self) private var player
    @Environment(NotificationHandler.self) private var notificationHandler
    @Environment(InboxService.self) private var inbox
    /// For the number on the inbox tab (N41, N47).
    @Query(InboxService.openCandidates(now: .now)) private var inboxEpisodes: [Episode]
    @State private var section = Section.library
    @State private var isShowingPlayer = false

    var body: some View {
        @Bindable var notificationHandler = notificationHandler
        // Concept §6.6, N38, N92: Bibliothek · Eingang · Playlists · Warteschlange · Suche.
        TabView(selection: $section) {
            Tab("Library", systemImage: "books.vertical", value: .library) {
                LibraryView()
            }
            Tab("Inbox", systemImage: "tray", value: .inbox) {
                InboxView()
            }
            .badge(inbox.newCount(of: inboxEpisodes))
            Tab("Playlists", systemImage: "music.note.list", value: .playlists) {
                PlaylistsView()
                    .environment(\.isTabSelected, section == .playlists)
            }
            Tab("Queue", systemImage: "text.line.first.and.arrowtriangle.forward", value: .queue) {
                NavigationStack { UpNextView() }
                    .environment(\.isTabSelected, section == .queue)
            }
            Tab(value: .search, role: .search) {
                SearchView()
            }
        }
        .onChange(of: section) { old, new in
            // A60: opening and leaving the inbox count as a visit.
            if old == .inbox || new == .inbox { inbox.didVisit() }
        }
        .miniPlayer(isVisible: player.episode != nil) { isShowingPlayer = true }
        .sheet(isPresented: $isShowingPlayer) { PlayerView() }
        .onChange(of: player.episode == nil) { _, isEmpty in
            if isEmpty { isShowingPlayer = false }
        }
        .undoBanner(registersUndo: true)
        .sheet(item: $notificationHandler.shownEpisode) { NotifiedEpisodeView(id: $0.id) }
    }
}

private extension View {
    /// The mini player shows only while an episode is loaded (iOS 26.1+); on 26.0 the
    /// accessory always shows and says "Not Playing".
    @ViewBuilder func miniPlayer(isVisible: Bool, openPlayer: @escaping () -> Void) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isVisible) { MiniPlayer(openPlayer: openPlayer) }
        } else {
            tabViewBottomAccessory { MiniPlayer(openPlayer: openPlayer) }
        }
    }
}
