import PodlistKit
import SwiftUI

extension DefaultPlaylist {
    var localizedName: LocalizedStringResource {
        switch self {
        case .news: "playlist.default.news"
        case .politics: "playlist.default.politics"
        case .sports: "playlist.default.sports"
        case .entertainment: "playlist.default.entertainment"
        case .knowledge: "playlist.default.knowledge"
        case .technology: "playlist.default.technology"
        }
    }
}

extension Playlist {
    /// The user's name, or the translated default name as long as it was not renamed
    /// (concept §4.8).
    var displayName: String {
        if let customName { return customName }
        return defaultName ?? ""
    }

    /// The translated name of a default playlist (`nil` for custom playlists).
    var defaultName: String? {
        if isEverything { return String(localized: "playlist.everything") }
        return systemKey.flatMap(DefaultPlaylist.init(rawValue:)).map { String(localized: $0.localizedName) }
    }

    var color: Color { PlaylistPalette.color(for: colorKey) }

    var candidate: PlaylistCandidate {
        PlaylistCandidate(id: playlistID, systemKey: systemKey, name: displayName, isRenamed: customName != nil)
    }
}

/// The fixed, accessible palette and symbols for playlists. Color is never the only
/// signal: every playlist also has a symbol.
enum PlaylistPalette {
    static let colorKeys = ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown"]

    static let symbols = [
        "music.note.list", "newspaper", "building.columns", "sportscourt", "theatermasks", "graduationcap",
        "cpu", "star", "heart", "bookmark", "flag", "bolt", "leaf", "globe.europe.africa", "briefcase",
        "car", "figure.run", "fork.knife", "gamecontroller", "film", "music.mic", "magnifyingglass",
        "moon.stars", "sun.max", "house", "person.2", "brain.head.profile", "lightbulb", "cross.case", "dollarsign.circle",
        "square.stack.3d.up",
    ]

    static func color(for key: String) -> Color {
        switch key {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        default: .accentColor
        }
    }
}

/// A playlist's symbol on its color, as used in lists, chips and pickers.
struct PlaylistIcon: View {
    let playlist: Playlist
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: playlist.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(playlist.color.gradient, in: .rect(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

/// Icon and name of a playlist.
struct PlaylistLabel: View {
    let playlist: Playlist

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(playlist.displayName)
                // A hidden playlist (N65), as on its chip.
                if playlist.isHidden {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("playlist.hidden"))
                }
            }
        } icon: {
            PlaylistIcon(playlist: playlist)
        }
    }
}
