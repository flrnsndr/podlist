import AVFoundation
import Foundation

/// Chapters read from an audio file by AVFoundation (concept §4.6 sources 3 and 4, ADR 0006).
public struct AudioChapterResult: Hashable, Sendable {
    public var source: ChapterSource      // .id3 or .mp4
    public var chapters: [Chapter]        // start, end, title, linkURL if available; imageURL stays nil
    /// Embedded chapter images by index into `chapters` (raw image data), if AVFoundation exposes them.
    public var images: [Int: Data]

    public init(source: ChapterSource, chapters: [Chapter], images: [Int: Data] = [:]) {
        self.source = source
        self.chapters = chapters
        self.images = images
    }
}

public enum AudioChapters {
    /// Chapters embedded in a local or streamed audio file; nil if it has none. Languages come from
    /// `availableChapterLocales` (ADR 0006), never from the UI language.
    ///
    /// Known AVFoundation limit (ChapterSpikeTests): spec-compliant ID3v2.4 tags whose CHAP sub-frames
    /// are 128 bytes or larger (images, long titles) deliver no chapters at all; ID3v2.3 is fine.
    public static func load(from url: URL) async throws -> AudioChapterResult? {
        let asset = AVURLAsset(url: url)
        let locales = try await asset.load(.availableChapterLocales)
        guard !locales.isEmpty else { return nil }
        // ASSUMPTION: with several chapter languages, take the one that matches the user's preferred
        // languages best; otherwise the first one the file lists. The list always comes from the file.
        let identifiers = orderedLocaleIdentifiers(available: locales.map(\.identifier), preferred: Locale.preferredLanguages)
        let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: identifiers)
        guard !groups.isEmpty else { return nil }

        var chapters: [Chapter] = []
        var images: [Int: Data] = [:]
        var sawID3Item = false
        for group in groups {
            var title = ""
            var link: URL?
            var otherLink: URL?
            var image: Data?
            for item in group.items {
                if item.keySpace == .id3 { sawID3Item = true }
                if item.commonKey == .commonKeyTitle, title.isEmpty {
                    title = try await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                } else if item.commonKey == .commonKeyArtwork, image == nil {
                    image = try await item.load(.dataValue)
                } else if item.identifier == .id3MetadataUserURL {
                    if link == nil { link = webURL(try await item.load(.stringValue)) }
                } else if let key = item.key as? String, item.keySpace == .id3, key.hasPrefix("W") {
                    // WOAR, WOAS, WORS, …: only a fallback when there is no WXXX.
                    if otherLink == nil { otherLink = webURL(try await item.load(.stringValue)) }
                }
            }
            let start = group.timeRange.start.seconds
            let end = group.timeRange.end.seconds
            guard start.isFinite else { continue }
            if let image, !image.isEmpty { images[chapters.count] = image }
            chapters.append(Chapter(start: start, end: end.isFinite ? end : nil, title: title, linkURL: link ?? otherLink))
        }
        guard !chapters.isEmpty else { return nil }

        // ID3 items live in the org.id3 key space; MP4 chapter titles come as common keys.
        let isID3: Bool
        if sawID3Item {
            isID3 = true
        } else {
            isID3 = try await asset.load(.availableMetadataFormats).contains(.id3Metadata)
        }
        return AudioChapterResult(source: isID3 ? .id3 : .mp4, chapters: chapters, images: images)
    }

    /// `available` reordered so the best match for the user's languages comes first; the rest keeps the file's order.
    static func orderedLocaleIdentifiers(available: [String], preferred: [String]) -> [String] {
        func language(_ identifier: String) -> String {
            Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
        }
        for wanted in preferred {
            if let match = available.first(where: { language($0) == language(wanted) }) {
                return [match] + available.filter { $0 != match }
            }
        }
        return available
    }

    /// Only http(s) links; an embedded `tel:`, `file:` or custom scheme is never offered to the user.
    static func webURL(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false
        else { return nil }
        return url
    }
}
