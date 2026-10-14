import os

extension Logger {
    private static let subsystem = "com.podlistapp.podlist"

    /// Model container, schema and seeding.
    public static let store = Logger(subsystem: subsystem, category: "store")
    /// Playlist changes.
    public static let playlists = Logger(subsystem: subsystem, category: "playlists")
    /// Feed loading, parsing, subscribing and refreshing.
    public static let feeds = Logger(subsystem: subsystem, category: "feeds")
    /// Library writes: played status, progress, unsubscribing.
    public static let library = Logger(subsystem: subsystem, category: "library")
    /// Up Next: queue operations, history.
    public static let upNext = Logger(subsystem: subsystem, category: "upNext")
    /// Chapter loading from JSON, audio files and show notes.
    public static let chapters = Logger(subsystem: subsystem, category: "chapters")
    /// AVPlayer, audio session, remote commands.
    public static let playback = Logger(subsystem: subsystem, category: "playback")
    /// Episode downloads and their files.
    public static let downloads = Logger(subsystem: subsystem, category: "downloads")
    /// New-episode notifications and background refresh.
    public static let notifications = Logger(subsystem: subsystem, category: "notifications")
    /// The listening log and its statistics.
    public static let statistics = Logger(subsystem: subsystem, category: "statistics")
}
