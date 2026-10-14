import Foundation
import os

/// Where downloaded episodes live (ADR 0007): Application Support/Downloads as
/// `<uuid>.<extension>`, excluded from the iCloud backup and never purged by iOS. Episodes
/// store only the file name; the container path changes with app updates.
public struct DownloadFiles: Sendable {
    public static let shared = DownloadFiles()

    public let directory: URL

    public init(directory: URL = URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    public func url(forFileNamed name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    public func exists(fileNamed name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forFileNamed: name).path(percentEncoded: false))
    }

    /// Free bytes for files the user asked for; nil if unknown.
    public func availableCapacity() -> Int64? {
        let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
        return try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    /// `<uuid>.<extension>`: the extension of the audio URL, else from the MIME type, else mp3.
    static func fileName(for episode: UUID, sourceURL: URL?, mimeType: String?) -> String {
        let fromURL = sourceURL?.pathExtension.lowercased() ?? ""
        let isPlausible = (1...4).contains(fromURL.count) && fromURL.allSatisfy { $0.isLetter || $0.isNumber }
        let fromMIME = switch mimeType?.lowercased() {
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac": "m4a"
        case "video/mp4": "mp4"
        case "audio/ogg": "ogg"
        case "audio/opus": "opus"
        default: "mp3"
        }
        return "\(episode.uuidString).\(isPlausible ? fromURL : fromMIME)"
    }

    /// Moves a finished download into place and returns its size. An older file of the same
    /// name is replaced atomically, so it never disappears while someone reads or plays it.
    func moveIntoPlace(_ temporary: URL, named name: String) throws -> Int64 {
        try prepareDirectory()
        // Staged in the directory first (the temporary file may be on another volume), under
        // a name `existingFileName` never takes for an episode's file.
        let staged = url(forFileNamed: ".\(UUID().uuidString).staged")
        try FileManager.default.moveItem(at: temporary, to: staged)
        guard rename(staged.path(percentEncoded: false), url(forFileNamed: name).path(percentEncoded: false)) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            remove(staged)
            throw error
        }
        return fileSize(ofFileNamed: name) ?? 0
    }

    /// The finished file of an episode, if one is there (a download that completed while
    /// the app was not running).
    func existingFileName(for episode: UUID) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.first { $0.hasPrefix("\(episode.uuidString).") && !$0.hasSuffix(".resume") }
    }

    func fileSize(ofFileNamed name: String) -> Int64? {
        (try? url(forFileNamed: name).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    func remove(fileNamed name: String) {
        remove(url(forFileNamed: name))
    }

    // MARK: Resume data (pause, A39)

    func saveResumeData(_ data: Data, for episode: UUID) {
        do {
            try prepareDirectory()
            try data.write(to: resumeDataURL(for: episode), options: .atomic)
        } catch {
            Logger.downloads.error("Saving resume data failed: \(String(describing: error), privacy: .public)")
        }
    }

    func resumeData(for episode: UUID) -> Data? {
        try? Data(contentsOf: resumeDataURL(for: episode))
    }

    func removeResumeData(for episode: UUID) {
        remove(resumeDataURL(for: episode))
    }

    // MARK: Helpers

    private func resumeDataURL(for episode: UUID) -> URL {
        url(forFileNamed: "\(episode.uuidString).resume")
    }

    private func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.downloads.error("Removing \(url.lastPathComponent, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(values)
    }
}
