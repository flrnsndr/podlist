import Foundation
import Observation
import SwiftData
import os

/// All playlist writes go through this service (concept §6.2): playlists, podcast
/// assignments with their auto-add rule, and entries (concept §4.1–4.3).
@MainActor @Observable
public final class PlaylistService {
    private let context: ModelContext
    private let downloads: DownloadService?
    private let now: @Sendable () -> Date

    /// `downloads` loads episodes that enter playlists with auto-download (N31).
    public init(context: ModelContext, downloads: DownloadService? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.downloads = downloads
        self.now = now
    }

    /// Inserts the default playlists whose `systemKey` is not present yet. The app calls
    /// this once per installation, so playlists the user deleted do not come back.
    public func insertDefaultPlaylists() throws {
        let existing = try context.fetch(FetchDescriptor<Playlist>())
        let existingKeys = Set(existing.compactMap(\.systemKey))
        var order = existing.map(\.displayOrder).max() ?? -1
        for playlist in DefaultPlaylist.allCases where !existingKeys.contains(playlist.systemKey) {
            order += 1
            let inserted = Playlist(
                systemKey: playlist.systemKey, colorKey: playlist.colorKey,
                symbolName: playlist.symbolName, displayOrder: order)
            inserted.autoDownload = true  // N89
            context.insert(inserted)
        }
        try context.save()
        Logger.store.info("Default playlists ensured (\(DefaultPlaylist.allCases.count - existingKeys.count) inserted)")
    }

    /// Creates the playlist "Alles" if it is missing (every launch, concept §4.1): first in
    /// the list, with its fixed sort (N97) and auto-download (N88, N89). Playlists already
    /// hidden are left out of it (N72, A65). An existing "Alles" gets the fixed sort (then it
    /// starts at its newest episode, A78) and always removes played episodes (N99).
    public func ensureEverything() throws {
        let existing = try context.fetch(FetchDescriptor<Playlist>())
        if let everything = existing.everything {
            if everything.sort != Everything.sort || everything.sortAscending != Everything.sortAscending {
                everything.sort = Everything.sort
                everything.sortAscending = Everything.sortAscending
                everything.resumeEpisode = nil
            }
            if everything.playedPolicy != .remove { everything.playedPolicy = .remove }
            if context.hasChanges { try context.save() }
            return
        }
        let everything = Playlist(
            systemKey: Playlist.everythingKey, colorKey: "purple", symbolName: "square.stack.3d.up",
            displayOrder: Position.top(above: existing.map(\.displayOrder)))
        everything.sort = Everything.sort
        everything.sortAscending = Everything.sortAscending
        everything.autoDownload = true
        context.insert(everything)
        for playlist in existing where playlist.isHidden { playlist.isExcludedFromEverything = true }
        try context.save()
        Logger.store.info("Playlist Everything created")
    }

    // MARK: Playlists

    /// A new playlist: manual sort (N10), played episodes are removed, auto-download (N89),
    /// at the end of the list.
    @discardableResult
    public func createPlaylist(name: String, colorKey: String, symbolName: String) throws -> Playlist {
        let orders = try context.fetch(FetchDescriptor<Playlist>()).map(\.displayOrder)
        let playlist = Playlist(
            customName: Self.cleaned(name), colorKey: colorKey, symbolName: symbolName,
            displayOrder: Position.bottom(below: orders))
        playlist.autoDownload = true
        context.insert(playlist)
        try context.save()
        return playlist
    }

    /// Name, color and symbol. An empty name gives a default playlist its translated
    /// name back (concept §4.8); a custom playlist keeps its old name.
    public func update(_ playlist: Playlist, customName: String?, colorKey: String, symbolName: String) throws {
        let name = customName.flatMap(Self.cleaned)
        if name != nil || playlist.systemKey != nil { playlist.customName = name }
        playlist.colorKey = colorKey
        playlist.symbolName = symbolName
        try context.save()
    }

    /// Changing to manual takes over the visible order, so nothing jumps (concept §4.2).
    public func setSort(_ sort: PlaylistSort, ascending: Bool, of playlist: Playlist) throws {
        guard !playlist.isEverything else { return }  // fixed sort (N97)
        if sort == .manual { playlist.switchToManual() }
        playlist.sort = sort
        playlist.sortAscending = ascending
        try context.save()
    }

    /// Switching to "remove" removes nothing at once: played episodes leave once they are
    /// played again or marked played (Florian, A15).
    public func setPlayedPolicy(_ policy: PlayedPolicy, of playlist: Playlist) throws {
        guard !playlist.isEverything else { return }  // always "remove" (N99)
        playlist.playedPolicy = policy
        try context.save()
        downloads?.evaluate()  // played downloads it kept may go (N32)
    }

    /// N31: on loads every unplayed episode of the playlist, now and from then on; for
    /// "Alles" every unplayed episode it has (N88). Off keeps what is loaded (A40).
    public func setAutoDownload(_ isOn: Bool, of playlist: Playlist) throws {
        playlist.autoDownload = isOn
        try context.save()
        downloads?.evaluate()
    }

    /// N89: once after the update that made auto-download the default, every playlist
    /// ("Alles" too) downloads automatically. The app calls this once.
    public func turnOnAutoDownloadForAllPlaylists() throws {
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        for playlist in playlists { playlist.autoDownload = true }
        try context.save()
        downloads?.evaluate()
        Logger.store.info("Auto-download turned on for \(playlists.count) playlists")
    }

    /// N65: hidden playlists keep their podcasts out of "Alle" in the library and the inbox.
    /// Hiding also leaves the playlist out of "Alles", showing takes it back (N72, A65).
    public func setHidden(_ isHidden: Bool, of playlist: Playlist) throws {
        guard !playlist.isEverything else { return }
        playlist.isHidden = isHidden
        try setExcluded(isHidden, playlist: playlist)
    }

    /// Chooses a playlist for "Alles" or leaves it out (N71). Its episodes stay in "Alles" if
    /// another chosen playlist has them. Up Next is not touched (A88).
    public func setExcluded(_ isExcluded: Bool, playlist: Playlist) throws {
        guard !playlist.isEverything else { return }
        playlist.isExcludedFromEverything = isExcluded
        try context.save()
        downloads?.evaluate()  // what "Alles" loads may have changed (N88)
    }

    /// Chooses a podcast for "Alles" or leaves it out entirely (N71).
    public func setExcluded(_ isExcluded: Bool, podcast: Podcast) throws {
        podcast.isExcludedFromEverything = isExcluded
        try context.save()
        downloads?.evaluate()  // N88
    }

    /// Deletes the playlist with its entries and assignments; episodes stay, and so does
    /// Up Next (A88). "Alles" cannot be deleted (A64).
    public func delete(_ playlist: Playlist) throws {
        guard !playlist.isEverything else { return }
        let podcasts = (playlist.assignments ?? []).compactMap(\.podcast)
        context.delete(playlist)
        try context.save()
        try inboxAssignmentsChanged(podcasts)
        downloads?.evaluate()  // played downloads it kept may go (N32)
    }

    /// Reorders the playlist list (`ordered` as displayed, SwiftUI `onMove` semantics).
    public func movePlaylists(_ ordered: [Playlist], fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        let moved = Position.afterMove(ordered.map(\.displayOrder), fromOffsets: offsets, toOffset: destination)
        for (index, order) in moved { ordered[index].displayOrder = order }
        try context.save()
    }

    // MARK: Assignments (the podcast's "tags")

    /// Assigns a podcast or changes its rule. Only future episodes come in by auto-add; an
    /// assignment adds no existing episode (N93).
    public func assign(_ podcast: Podcast, to playlist: Playlist, autoAdd rule: AutoAddRule) throws {
        assignWithoutSaving(podcast, to: playlist, autoAdd: rule)
        try context.save()
    }

    public func unassign(_ podcast: Podcast, from playlist: Playlist) throws {
        (podcast.assignments ?? []).filter { $0.playlist == playlist }.forEach(context.delete)
        try context.save()
        try inboxAssignmentsChanged([podcast])
    }

    /// The result of the "In welche Playlists?" sheet: exactly these assignments
    /// (playlist `uuid` → rule). Unassigned playlists keep their entries (A16).
    public func setAssignments(of podcast: Podcast, to rules: [UUID: AutoAddRule]) throws {
        for assignment in podcast.assignments ?? [] where rules[assignment.playlist?.uuid ?? UUID()] == nil {
            context.delete(assignment)
        }
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        for playlist in playlists.tags {
            guard let rule = rules[playlist.uuid] else { continue }
            assignWithoutSaving(podcast, to: playlist, autoAdd: rule)
        }
        try context.save()
        // Once all assignments exist (and removed ones are gone): partial auto-add leaves an
        // episode open (N75).
        try inboxAssignmentsChanged([podcast])
        downloads?.evaluate()
    }

    private func assignWithoutSaving(_ podcast: Podcast, to playlist: Playlist, autoAdd rule: AutoAddRule) {
        guard !playlist.isEverything else { return }  // "Alles" is no tag
        if let existing = (podcast.assignments ?? []).first(where: { $0.playlist == playlist }) {
            existing.autoAdd = rule
        } else {
            context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: rule, createdAt: now()))
        }
    }

    // MARK: Entries

    /// "Zu Playlist …": adds an episode at the bottom (N10), once.
    ///
    /// ASSUMPTION (A14): a played episode added by hand to a "remove" playlist counts as
    /// unplayed again; otherwise the played policy would hide it right away.
    public func add(_ episode: Episode, to playlist: Playlist) throws {
        guard !playlist.isEverything, !(playlist.entries ?? []).contains(where: { $0.episode == episode }) else { return }
        if episode.isPlayed, playlist.playedPolicy == .remove { episode.playedAt = nil }
        let position = Position.bottom(below: (playlist.entries ?? []).map(\.position))
        let addedAt = now()
        context.insert(PlaylistEntry(playlist: playlist, episode: episode, position: position, addedAt: addedAt, origin: .manual))
        episode.inboxHandled()
        try context.save()
        downloads?.evaluate()
    }

    /// "Zu Playlists hinzufügen" in a notification (N34): adds the episode at the bottom of
    /// every playlist its podcast is assigned to that does not contain it yet.
    public func addToAssignedPlaylists(_ episode: Episode) throws {
        let assigned = (episode.podcast?.assignments ?? []).compactMap(\.playlist)
        let missing = Set(NewEpisodeNotifications.playlistsToAdd(
            assigned: assigned.map(\.playlistID),
            containing: Set((episode.playlistEntries ?? []).compactMap { $0.playlist?.playlistID })))
        for playlist in assigned where missing.contains(playlist.playlistID) {
            try add(episode, to: playlist)
        }
    }

    public func remove(_ episode: Episode, from playlist: Playlist) throws {
        try PlaylistEntryRemoval.remove(episode, from: playlist, context: context)
        try context.save()
        downloads?.evaluate()  // a played download the playlist kept may go (N32)
    }

    /// Reorders entries by hand; a sorted playlist becomes manual first (N96). The offsets
    /// refer to `shown`, the episodes the list shows in order (all of them, or only the
    /// unplayed ones or one podcast section); the others keep their place.
    public func moveEntries(
        of playlist: Playlist, shown: [Episode]? = nil, fromOffsets offsets: IndexSet, toOffset destination: Int
    ) throws {
        guard !playlist.isEverything else { return }
        playlist.switchToManual()
        let entries = playlist.sortedEntries
        let shown = shown ?? entries.compactMap(\.episode)
        let index = { (episode: Episode) in entries.firstIndex { $0.episode == episode } }
        let fullOffsets = IndexSet(offsets.compactMap { shown.indices.contains($0) ? index(shown[$0]) : nil })
        let target = shown.indices.contains(destination) ? index(shown[destination]) : shown.last.flatMap(index).map { $0 + 1 }
        guard let target else { return }
        let moved = Position.afterMove(entries.map(\.position), fromOffsets: fullOffsets, toOffset: target)
        for (index, position) in moved { entries[index].position = position }
        try context.save()
    }

    // MARK: Helpers

    /// The podcasts' assignments changed (saved): an open inbox episode that is now in every
    /// playlist of its podcast is done, so none stays open with nothing to add (N75, A68).
    private func inboxAssignmentsChanged(_ podcasts: [Podcast]) throws {
        for podcast in podcasts {
            for episode in podcast.episodes ?? [] where episode.inboxAddedAt != nil && episode.inboxState == .open {
                episode.inboxAutoAdded()
            }
        }
        if context.hasChanges { try context.save() }
    }

    /// Inserts automatic entries computed by `PlaylistAutomation` (also used by the `FeedRefresher`)
    /// and returns the episodes it added. The caller decides about the inbox once all playlists
    /// are done (`Episode.inboxAutoAdded`, N75).
    @discardableResult
    nonisolated static func insert(
        _ insertions: [PlaylistInsertion], into playlist: Playlist, episodes: [Episode], context: ModelContext
    ) -> [Episode] {
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        var added: [Episode] = []
        for insertion in insertions {
            guard let episode = byID[insertion.entry.episode.id] else { continue }
            context.insert(PlaylistEntry(
                playlist: playlist, episode: episode, position: insertion.entry.position,
                addedAt: insertion.entry.addedAt, origin: .automatic))
            added.append(episode)
        }
        return added
    }

    private nonisolated static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Playlist {
    /// "Manuell" from what the playlist shows now, so nothing jumps (concept §4.2, N96).
    func switchToManual() {
        guard sort != .manual else { return }
        for (index, entry) in sortedEntries.enumerated() { entry.position = Double(index) }
        sort = .manual
    }
}
