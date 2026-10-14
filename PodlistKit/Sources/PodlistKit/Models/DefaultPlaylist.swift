import Foundation

/// The default playlists created on first launch (concept §4.1). They are ordinary
/// playlists: renamable and deletable. Their name is translated via `systemKey` as long
/// as the user has not renamed them (concept §4.8); the app owns the translations.
public enum DefaultPlaylist: String, CaseIterable, Sendable {
    case news
    case politics
    case sports
    case entertainment
    case knowledge
    case technology

    public var systemKey: String { rawValue }

    public var colorKey: String {
        switch self {
        case .news: "red"
        case .politics: "indigo"
        case .sports: "green"
        case .entertainment: "orange"
        case .knowledge: "teal"
        case .technology: "blue"
        }
    }

    public var symbolName: String {
        switch self {
        case .news: "newspaper"
        case .politics: "building.columns"
        case .sports: "sportscourt"
        case .entertainment: "theatermasks"
        case .knowledge: "graduationcap"
        case .technology: "cpu"
        }
    }
}
