import Testing
@testable import PodlistKit

struct PlayedRulesTests {
    @Test(arguments: [
        (970.0, 1000.0, true), (971.0, 1000.0, true), (969.0, 1000.0, false),
        (1000.0, 1000.0, true), (1100.0, 1000.0, true), (0.0, 20.0, true),
    ])
    func nearEndWithDefaultThreshold(position: Double, duration: Double, expected: Bool) {
        #expect(PlayedRules.isNearEnd(position: position, duration: duration) == expected)
    }

    @Test(arguments: [(500.0, 600.0, 100.0, true), (500.0, 600.0, 99.0, false)])
    func customThreshold(position: Double, duration: Double, threshold: Double, expected: Bool) {
        #expect(PlayedRules.isNearEnd(position: position, duration: duration, threshold: threshold) == expected)
    }

    @Test(arguments: [nil, 0.0, -5.0])
    func unknownOrZeroDurationIsNeverNearEnd(duration: Double?) {
        #expect(!PlayedRules.isNearEnd(position: 100, duration: duration))
    }

    @Test(arguments: [
        (true, 0.0, nil as Double?, true), (false, 990.0, 1000.0, true),
        (false, 100.0, 1000.0, false), (false, 100.0, nil as Double?, false),
    ])
    func shouldMarkPlayed(finished: Bool, position: Double, duration: Double?, expected: Bool) {
        #expect(PlayedRules.shouldMarkPlayed(finished: finished, position: position, duration: duration) == expected)
    }

    @Test func removesOnlyFromRemovePlaylists() {
        let a = PlaylistID(), b = PlaylistID(), c = PlaylistID()
        let playlists = [
            PlaylistPolicy(playlistID: a, policy: .remove),
            PlaylistPolicy(playlistID: b, policy: .keep),
            PlaylistPolicy(playlistID: c, policy: .remove),
        ]
        #expect(PlayedRules.playlistsToRemoveFrom(playlists, isNowPlaying: false) == [a, c])
        #expect(PlayedRules.playlistsToRemoveFrom([], isNowPlaying: false).isEmpty)
    }

    @Test func runningEpisodeIsNeverRemoved() {
        let playlists = [PlaylistPolicy(playlistID: PlaylistID(), policy: .remove)]
        #expect(PlayedRules.playlistsToRemoveFrom(playlists, isNowPlaying: true).isEmpty)
    }

}
