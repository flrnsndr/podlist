import Foundation
import Testing

@testable import PodlistKit

struct PlaylistSuggestionsTests {
    @Test(arguments: [
        ("News", ["news"]),
        ("news", ["news"]),
        ("  Daily News ", ["news"]),
        ("News Commentary", ["news"]),
        ("Business News", ["news"]),
        ("News & Politics", ["news", "politics"]),
        ("Politics", ["politics"]),
        ("Government", ["politics"]),
        ("Sports", ["sports"]),
        ("Sports News", ["sports"]),
        ("Soccer", ["sports"]),
        ("Football", ["sports"]),
        ("Basketball", ["sports"]),
        ("Comedy", ["entertainment"]),
        ("Stand-Up", ["entertainment"]),
        ("TV & Film", ["entertainment"]),
        ("Film Reviews", ["entertainment"]),
        ("Drama", ["entertainment"]),
        ("Music", ["entertainment"]),
        ("Music Interviews", ["entertainment"]),
        ("Entertainment News", ["entertainment"]),
        ("Video Games", ["entertainment"]),
        ("Science", ["knowledge"]),
        ("Astronomy", ["knowledge"]),
        ("Education", ["knowledge"]),
        ("Self-Improvement", ["knowledge"]),
        ("History", ["knowledge"]),
        ("Documentary", ["knowledge"]),
        ("Philosophy", ["knowledge"]),
        ("Science & Medicine", ["knowledge"]),
        ("Technology", ["technology"]),
        ("Tech News", ["technology"]),
        ("Podcasting", ["technology"]),
        ("Gadgets", ["technology"]),
        ("Software How-To", ["technology"]),
        ("Society & Culture", []),
        ("Business", []),
        ("Health & Fitness", []),
        ("Kids & Family", []),
        ("Religion & Spirituality", []),
        ("True Crime", []),
        ("Arts", []),
        ("Leisure", []),
        ("", []),
    ] as [(String, [String])])
    func categoryMapsToKeys(category: String, keys: [String]) {
        #expect(PlaylistSuggestions.systemKeys(forCategory: category) == Set(keys))
    }

    private func candidate(_ key: String?, _ name: String, isRenamed: Bool = false) -> PlaylistCandidate {
        PlaylistCandidate(id: PlaylistID(), systemKey: key, name: name, isRenamed: isRenamed)
    }

    @Test func suggestionsFollowPlaylistOrderWithoutDuplicates() {
        let tech = candidate("technology", "Technik")
        let news = candidate("news", "Nachrichten")
        let sports = candidate("sports", "Sport")
        let result = PlaylistSuggestions.suggested(
            forCategories: ["Technology", "Tech News", "News", "Daily News"],
            playlists: [tech, sports, news])
        #expect(result == [tech.id, news.id])
    }

    @Test func oldNewsAndPoliticsSuggestsBoth() {
        let news = candidate("news", "News")
        let politics = candidate("politics", "Politik")
        let other = candidate(nil, "Misc")
        #expect(
            PlaylistSuggestions.suggested(
                forCategories: ["News & Politics"], playlists: [other, news, politics])
                == [news.id, politics.id])
    }

    /// N68: a renamed default playlist is suggested by its new name only.
    @Test func renamedDefaultMatchesByItsNewNameOnly() {
        let renamed = candidate("technology", "Nerdkram", isRenamed: true)
        let crime = candidate("knowledge", "True Crime", isRenamed: true)
        #expect(PlaylistSuggestions.suggested(forCategories: ["Technology"], playlists: [renamed]).isEmpty)
        #expect(PlaylistSuggestions.suggested(forCategories: ["Science"], playlists: [crime]).isEmpty)
        #expect(PlaylistSuggestions.suggested(forCategories: ["True Crime"], playlists: [renamed, crime]) == [crime.id])
    }

    @Test func customPlaylistMatchesByNameIgnoringCaseDiacriticsAndWhitespace() {
        let crime = candidate(nil, "  true CRIME ")
        let cafe = candidate(nil, "Café")
        let none = candidate(nil, "Something")
        #expect(
            PlaylistSuggestions.suggested(
                forCategories: ["True Crime", "Cafe"], playlists: [none, crime, cafe])
                == [crime.id, cafe.id])
    }

    @Test func unknownAndEmptyInputSuggestNothing() {
        let news = candidate("news", "News")
        #expect(PlaylistSuggestions.suggested(forCategories: [], playlists: [news]).isEmpty)
        #expect(PlaylistSuggestions.suggested(forCategories: ["Business", "Arts"], playlists: [news]).isEmpty)
        #expect(PlaylistSuggestions.suggested(forCategories: ["News"], playlists: []).isEmpty)
    }
}
