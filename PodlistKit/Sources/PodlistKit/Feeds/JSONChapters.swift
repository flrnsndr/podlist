import Foundation

public enum JSONChaptersError: Error, Hashable, Sendable { case invalid }

/// Podcasting 2.0 JSON chapters (`podcast:chapters`, `application/json+chapters`).
public enum JSONChapters {
    /// `baseURL` is the URL of the chapters file; relative `img`/`url` values resolve against it.
    /// Entries keep their input order (sorting and normalizing happen elsewhere).
    public static func parse(_ data: Data, baseURL: URL?) throws -> [Chapter] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["chapters"] as? [Any]
        else { throw JSONChaptersError.invalid }

        return entries.compactMap { entry -> Chapter? in
            guard let object = entry as? [String: Any],
                let start = seconds(object["startTime"]), start >= 0
            else { return nil }
            // ASSUMPTION: a negative or unparseable endTime is treated as missing, not as a reason to skip the entry.
            let end = seconds(object["endTime"]).flatMap { $0 >= 0 ? $0 : nil }
            let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Chapter(
                start: start,
                end: end,
                title: title,
                imageURL: webURL(object["img"], base: baseURL),
                linkURL: webURL(object["url"], base: baseURL),
                isHidden: (object["toc"] as? Bool) == false)
        }
    }

    /// A JSON number or a numeric string; booleans, `null`, NaN and infinity give `nil`.
    private static func seconds(_ value: Any?) -> TimeInterval? {
        let number: Double?
        switch value {
        case let string as String:
            number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID():
            number = n.doubleValue
        default:
            number = nil
        }
        guard let number, number.isFinite else { return nil }
        return number
    }

    private static func webURL(_ value: Any?, base: URL?) -> URL? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
            let url = URL(string: raw, relativeTo: base)
        else { return nil }
        return FeedParser.parseWebURL(url.absoluteURL.absoluteString)
    }
}
