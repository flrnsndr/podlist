import Foundation

/// A playlist the subscribe sheet can suggest.
public struct PlaylistCandidate: Hashable, Sendable {
    public var id: PlaylistID
    public var systemKey: String?
    /// What the user sees: custom name or translated default name.
    public var name: String
    /// A default playlist the user renamed: suggested by its new name only (N68).
    public var isRenamed: Bool

    public init(id: PlaylistID, systemKey: String?, name: String, isRenamed: Bool = false) {
        self.id = id
        self.systemKey = systemKey
        self.name = name
        self.isRenamed = isRenamed
    }
}

/// Picks the playlists preselected in the subscribe sheet from the feed's Apple
/// categories (concept §4.5). Pure logic, no clock, no models.
public enum PlaylistSuggestions {
    private static let table: [String: Set<String>] = {
        var map: [String: Set<String>] = [:]
        func add(_ key: String, _ categories: [String]) {
            for category in categories { map[normalize(category), default: []].insert(key) }
        }
        add("news", ["News", "Daily News", "News Commentary", "Business News"])
        // Pre-2019 taxonomy: "News & Politics" covers both.
        add("news", ["News & Politics"])
        add("politics", ["News & Politics", "Politics", "Government"])
        add("sports", [
            "Sports", "Sports News", "Baseball", "Basketball", "Cricket", "Fantasy Sports",
            "Football", "Golf", "Hockey", "Rugby", "Running", "Soccer", "Swimming", "Tennis",
            "Volleyball", "Wilderness", "Wrestling",
        ])
        add("entertainment", [
            "Comedy", "Comedy Interviews", "Improv", "Stand-Up",
            "TV & Film", "After Shows", "Film History", "Film Interviews", "Film Reviews",
            "TV Reviews",
            "Fiction", "Comedy Fiction", "Drama", "Science Fiction",
            "Music", "Music Commentary", "Music History", "Music Interviews",
            "Entertainment News", "Games", "Video Games",
            // ASSUMPTION: the old "Games & Hobbies" and "Video Games" count as entertainment;
            // Hobbies alone is too broad and maps to nothing.
            "Games & Hobbies", "Arts & Entertainment",
        ])
        add("knowledge", [
            "Science", "Astronomy", "Chemistry", "Earth Sciences", "Life Sciences", "Mathematics",
            "Natural Sciences", "Nature", "Physics", "Social Sciences",
            "Education", "Courses", "How To", "Language Learning", "Self-Improvement",
            "History", "Documentary", "Philosophy",
            // Old taxonomy.
            "Science & Medicine", "Natural Sciences", "Social Sciences",
        ])
        // ASSUMPTION: "Self-Improvement" and "How To" are Education subcategories, so knowledge.
        add("technology", [
            "Technology", "Tech News", "Podcasting", "Gadgets", "Software How-To",
        ])
        return map
    }()

    /// Default-playlist system keys an Apple category maps to (case-insensitive; empty if none).
    public static func systemKeys(forCategory category: String) -> Set<String> {
        table[normalize(category)] ?? []
    }

    /// Preselected playlists, in the order of `playlists`. A playlist is suggested if its
    /// systemKey matches one of the categories (unless it was renamed, N68), or if its
    /// name equals a category (case- and diacritic-insensitive, trimmed), e.g. a custom
    /// playlist "True Crime".
    public static func suggested(forCategories categories: [String], playlists: [PlaylistCandidate]) -> [PlaylistID] {
        let keys = categories.reduce(into: Set<String>()) { $0.formUnion(systemKeys(forCategory: $1)) }
        let names = Set(categories.map(normalize).filter { !$0.isEmpty })
        var seen = Set<PlaylistID>()
        var result: [PlaylistID] = []
        for playlist in playlists {
            let byKey = !playlist.isRenamed && (playlist.systemKey.map(keys.contains) ?? false)
            let byName = names.contains(normalize(playlist.name))
            if (byKey || byName) && seen.insert(playlist.id).inserted {
                result.append(playlist.id)
            }
        }
        return result
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
