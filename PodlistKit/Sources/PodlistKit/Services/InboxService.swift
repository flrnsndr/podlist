import Foundation
import Observation
import SwiftData
import os

/// The inbox (Eingang, concept §4.10): reads what it shows and carries out its actions, each
/// with "Rückgängig" (N50). It also remembers which episodes were seen open in this session,
/// for "Gerade erledigt" (N74). The rules live in `InboxRules`; what makes an episode done
/// elsewhere in the app (playlists, Up Next, playing) goes through `Episode.inboxHandled()`.
@MainActor @Observable
public final class InboxService {
    /// The latest action of the inbox, for the "Rückgängig" banner (one at a time, N50).
    public struct UndoableAction: Identifiable {
        public enum Kind: Hashable {
            /// "Hinzufügen zu …": the playlists it went into.
            case added(playlists: [PlaylistID])
            /// "Alle hinzufügen": how many episodes.
            case addedAll(count: Int)
            case playNext
            case discarded
            /// "Rest aussortieren": how many episodes.
            case discardedAll(count: Int)
        }

        public let id = UUID()
        public let kind: Kind
        public let createdAt: Date
    }

    public private(set) var undoableAction: UndoableAction?
    /// The last visit of the inbox tab (N41, A60).
    public private(set) var lastVisit: Date?
    /// The episodes the inbox showed open since the app last went to the background (A67).
    public private(set) var seenOpen: Set<EpisodeID> = []

    private struct Undo {
        /// An episode as it was before the action.
        struct Before {
            let episode: Episode
            let state: InboxState
            /// The playlists it was in, e.g. by partial auto-add (N75).
            let playlists: Set<PersistentIdentifier>

            init(_ episode: Episode) {
                self.episode = episode
                state = episode.inboxState
                playlists = Set((episode.playlistEntries ?? []).compactMap { $0.playlist?.persistentModelID })
            }
        }

        /// The episodes before the action.
        var states: [Before] = []
        /// Entries the action added.
        var entries: [(Episode, Playlist)] = []
        /// Went to Up Next with "Als Nächstes".
        var queued: Episode?
    }

    @ObservationIgnored private var undoData: Undo?
    private let context: ModelContext
    private let playlists: PlaylistService
    private let upNext: UpNextService
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private static let lastVisitKey = "inboxLastVisit"

    public init(
        context: ModelContext, playlists: PlaylistService, upNext: UpNextService,
        defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.playlists = playlists
        self.upNext = upNext
        self.defaults = defaults
        self.now = now
        lastVisit = defaults.object(forKey: Self.lastVisitKey) as? Date
    }

    // MARK: Reading

    /// The episodes the inbox may show at `now`, open and done (views use it with `@Query`);
    /// `shown` and `recentlyDone` do the rest.
    public static func candidates(now: Date) -> FetchDescriptor<Episode> {
        let cutoff = InboxRules.cutoff(now: now)
        let never = Date.distantPast
        let discarded = InboxState.discarded.rawValue
        return FetchDescriptor(
            predicate: #Predicate { ($0.inboxAddedAt ?? never) > cutoff && $0.inboxStateRaw != discarded },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
    }

    /// Only the open episodes of `candidates`: enough for the number on the tab (N47), and an
    /// episode that is playing (done, N46) never touches the root view with its saves.
    public static func openCandidates(now: Date) -> FetchDescriptor<Episode> {
        let cutoff = InboxRules.cutoff(now: now)
        let never = Date.distantPast
        let open = InboxState.open.rawValue
        return FetchDescriptor(predicate: #Predicate { ($0.inboxAddedAt ?? never) > cutoff && $0.inboxStateRaw == open })
    }

    /// The inbox as it shows: the open episodes (filter, newest first).
    public static func shown(_ episodes: [Episode], filter: PlaylistFilter, now: Date) -> [Episode] {
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        return InboxRules.shown(episodes.compactMap(\.inboxValue), filter: filter, now: now).compactMap { byID[$0.id] }
    }

    /// "Gerade erledigt" below the open episodes (N74, A67).
    public func recentlyDone(_ episodes: [Episode], filter: PlaylistFilter, now: Date) -> [Episode] {
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        return InboxRules.recentlyDone(episodes.compactMap(\.inboxValue), seenOpen: seenOpen, filter: filter, now: now)
            .compactMap { byID[$0.id] }
    }

    /// The number on the tab, from the episodes `candidates` fetched.
    public func newCount(of episodes: [Episode]) -> Int {
        InboxRules.newCount(episodes.compactMap(\.inboxValue), lastVisit: lastVisit, now: now())
    }

    public func shownEpisodes(filter: PlaylistFilter) throws -> [Episode] {
        let date = now()
        return Self.shown(try context.fetch(Self.candidates(now: date)), filter: filter, now: date)
    }

    public func recentlyDoneEpisodes(filter: PlaylistFilter) throws -> [Episode] {
        let date = now()
        return recentlyDone(try context.fetch(Self.candidates(now: date)), filter: filter, now: date)
    }

    public func newCount() throws -> Int {
        newCount(of: try context.fetch(Self.openCandidates(now: now())))
    }

    /// The inbox tab was opened or left (A60).
    public func didVisit(at date: Date? = nil) {
        let date = date ?? now()
        lastVisit = date
        defaults.set(date, forKey: Self.lastVisitKey)
    }

    /// The inbox showed these episodes open; once done, they stay below (A67).
    public func sawOpen(_ episodes: [Episode]) {
        let ids = Set(episodes.filter { $0.inboxState == .open }.map(\.episodeID))
        if !ids.isSubset(of: seenOpen) { seenOpen.formUnion(ids) }
    }

    /// The app went to the background: "Gerade erledigt" empties (N74, like N66).
    public func endSession() {
        if !seenOpen.isEmpty { seenOpen = [] }
    }

    // MARK: Actions

    /// "Hinzufügen zu ‹Playlists des Podcasts›": at the bottom of each assigned playlist
    /// that does not have it yet (A59, like N34).
    public func addToPodcastPlaylists(_ episode: Episode) throws {
        var undo = Undo()
        try add(episode, undo: &undo)
        let added = undo.entries.map { $0.1.playlistID }
        record(undo, kind: .added(playlists: added))
    }

    /// "Alle hinzufügen" for the shown episodes: the open ones with playlists, oldest first (A59).
    public func addAll(_ episodes: [Episode]) throws {
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = InboxRules.episodesToAddAll(episodes.compactMap(\.inboxValue)).compactMap { byID[$0] }
        guard !ordered.isEmpty else { return }
        var undo = Undo()
        for episode in ordered { try add(episode, undo: &undo) }
        record(undo, kind: .addedAll(count: ordered.count))
    }

    /// "Als Nächstes" (A50).
    public func playNext(_ episode: Episode) {
        let undo = Undo(states: [Undo.Before(episode)], queued: episode)
        upNext.playNext(episode)
        record(undo, kind: .playNext)
    }

    /// "Aussortieren" (N77): out of the inbox, still in the podcast.
    public func discard(_ episode: Episode) throws {
        let undo = Undo(states: [Undo.Before(episode)])
        episode.inboxState = InboxRules.state(episode.inboxState, after: .discarded)
        try context.save()
        record(undo, kind: .discarded)
    }

    /// "Rest aussortieren" for the shown episodes: every open one (N78, A69).
    public func discardAll(_ episodes: [Episode]) throws {
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        let discarding = InboxRules.episodesToDiscardAll(episodes.compactMap(\.inboxValue)).compactMap { byID[$0] }
        guard !discarding.isEmpty else { return }
        let undo = Undo(states: discarding.map(Undo.Before.init))
        for episode in discarding { episode.inboxState = InboxRules.state(episode.inboxState, after: .discarded) }
        try context.save()
        record(undo, kind: .discardedAll(count: discarding.count))
    }

    /// "Rückgängig": takes the latest action back and opens the episodes again. Entries leave
    /// the normal way (cursors move on); a started download stays (A40, A59). Done is a stored
    /// status: an episode that was started, played or put into a playlist or Up Next some
    /// other way since the action stays done.
    public func undo() throws {
        guard let undo = undoData else { return }
        undoData = nil
        undoableAction = nil
        if let queued = undo.queued { upNext.withdraw(queued) }
        for (episode, playlist) in undo.entries { try playlists.remove(episode, from: playlist) }
        for before in undo.states where !(before.state == .open && Self.isHandled(before)) {
            before.episode.inboxState = before.state
        }
        try context.save()
    }

    /// Whether something besides the undone action makes the episode done: it was played or
    /// started, is in Up Next, or is in a playlist it was not in before the action.
    private static func isHandled(_ before: Undo.Before) -> Bool {
        let episode = before.episode
        return episode.isPlayed || episode.playbackPosition > 0 || !(episode.queueItems ?? []).isEmpty
            || (episode.playlistEntries ?? []).contains { entry in
                entry.playlist.map { !before.playlists.contains($0.persistentModelID) } ?? false
            }
    }

    /// The banner went away.
    public func dismissUndo() {
        undoableAction = nil
        undoData = nil
    }

    // MARK: Plumbing

    private func add(_ episode: Episode, undo: inout Undo) throws {
        undo.states.append(Undo.Before(episode))
        let before = Set((episode.playlistEntries ?? []).compactMap(\.playlist))
        try playlists.addToAssignedPlaylists(episode)
        for playlist in (episode.playlistEntries ?? []).compactMap(\.playlist) where !before.contains(playlist) {
            undo.entries.append((episode, playlist))
        }
        episode.inboxHandled()
        try context.save()
    }

    private func record(_ undo: Undo, kind: UndoableAction.Kind) {
        undoData = undo
        undoableAction = UndoableAction(kind: kind, createdAt: now())
    }
}
