import Foundation

// Value parsers for the messy strings real feeds contain. All pure: no `DateFormatter`,
// no `Locale.current`, no `TimeZone.current`, no clock.

extension FeedParser {
    // MARK: Numbers and URLs

    /// A trimmed integer, `nil` for anything else (`"5.5"`, `"S1"`, empty).
    static func parseInt(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// An absolute `http`/`https` URL with a host; everything else (relative, `ftp`, `file`, junk) is `nil`.
    static func parseWebURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    // MARK: Durations and chapter times

    /// `itunes:duration`: `H:MM:SS`, `MM:SS` or seconds (decimals allowed). Garbage, negative and 0 give `nil`.
    static func parseDuration(_ raw: String) -> TimeInterval? {
        guard let seconds = parseClock(raw), seconds > 0 else { return nil }
        return seconds
    }

    /// A clock value as used by durations and Podlove chapter starts (NPT): `HH:MM:SS(.mmm)`,
    /// `MM:SS(.mmm)` or seconds, optionally prefixed with `npt:`. Zero is valid here.
    static func parseClock(_ raw: String) -> TimeInterval? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("npt:") { text = String(text.dropFirst(4)) }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            guard let value = decimal(part, allowFraction: index == parts.count - 1) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Digits with at most one `.` (and, if allowed, a fractional part). Rejects signs, exponents, `inf`, `nan`.
    private static func decimal(_ text: Substring, allowFraction: Bool) -> Double? {
        var dots = 0
        var digits = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digits += 1
            case UInt8(ascii: "."): dots += 1
            default: return nil
            }
        }
        guard digits > 0, dots == 0 || (dots == 1 && allowFraction) else { return nil }
        return Double(text)
    }

    // MARK: Dates

    /// `pubDate`: RFC 822/1123 in the variants seen in the wild, plus ISO 8601. `nil` if unparseable.
    /// A date without a zone is read as UTC.
    static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let bytes = Array(text.utf8)
        let looksISO = bytes.count >= 5 && bytes[0..<4].allSatisfy(isDigit) && bytes[4] == UInt8(ascii: "-")
        return looksISO ? parseISODate(bytes) : parseRFCDate(text)
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let weekdayNames = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private static let namedZones: [String: Int] = [
        "Z": 0, "UT": 0, "UTC": 0, "GMT": 0,
        "EST": -5, "EDT": -4, "CST": -6, "CDT": -5, "MST": -7, "MDT": -6, "PST": -8, "PDT": -7,
        // ASSUMPTION: Central European zones occur in German feeds although RFC 822 does not define them.
        "CET": 1, "CEST": 2,
    ]

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    private static func parseRFCDate(_ text: String) -> Date? {
        var tokens = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        if let first = tokens.first, first.allSatisfy(\.isLetter), weekdayNames.contains(String(first.lowercased().prefix(3))) {
            tokens.removeFirst()
        }
        guard tokens.count >= 3 else { return nil }
        guard let day = digits(tokens[0], maxLength: 2),
            let month = monthNames.firstIndex(of: String(tokens[1].lowercased().prefix(3))).map({ $0 + 1 }),
            tokens[1].allSatisfy(\.isLetter),
            var year = digits(tokens[2], maxLength: 4), tokens[2].count != 1
        else { return nil }
        // RFC 2822: 2-digit years 00-49 are 20xx, 50-99 are 19xx; 3-digit years are 1900 + n.
        switch tokens[2].count {
        case 2: year += year < 50 ? 2000 : 1900
        case 3: year += 1900
        default: break
        }

        var seconds = 0
        var hour = 0
        var minute = 0
        if tokens.count >= 4 {
            let clock = tokens[3].split(separator: ":", omittingEmptySubsequences: false)
            guard clock.count == 2 || clock.count == 3, let parsedHour = digits(clock[0], maxLength: 2),
                let parsedMinute = digits(clock[1], maxLength: 2)
            else { return nil }
            hour = parsedHour
            minute = parsedMinute
            if clock.count == 3 {
                // Ignore a fractional part ("30.5").
                guard let parsedSeconds = digits(clock[2].split(separator: ".", omittingEmptySubsequences: false).first ?? "", maxLength: 2)
                else { return nil }
                seconds = parsedSeconds
            }
        }
        var offset = 0
        if tokens.count >= 5 {
            guard let parsedOffset = zoneOffset(String(tokens[4])) else { return nil }
            offset = parsedOffset
        }
        return epoch(year: year, month: month, day: day, hour: hour, minute: minute, second: seconds, fraction: 0, offset: offset)
    }

    /// Offset in seconds east of UTC for `Z`, `GMT`, `EST`, `+0200`, `-05:00`, `+02`, `GMT+0200`.
    private static func zoneOffset(_ raw: String) -> Int? {
        let zone = raw.uppercased()
        if let hours = namedZones[zone] { return hours * 3600 }
        for prefix in ["GMT", "UTC", "UT"] where zone.hasPrefix(prefix) {
            return numericOffset(String(zone.dropFirst(prefix.count)))
        }
        return numericOffset(zone)
    }

    private static func numericOffset(_ text: String) -> Int? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = text.dropFirst().filter { $0 != ":" }
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) else { return nil }
        let hours: Int
        let minutes: Int
        switch digits.count {
        case 1, 2: (hours, minutes) = (value, 0)
        case 3, 4: (hours, minutes) = (value / 100, value % 100)
        default: return nil
        }
        guard hours <= 23, minutes <= 59 else { return nil }
        return (sign == "+" ? 1 : -1) * (hours * 3600 + minutes * 60)
    }

    private static func digits(_ text: Substring, maxLength: Int) -> Int? {
        guard !text.isEmpty, text.count <= maxLength, text.utf8.allSatisfy(isDigit) else { return nil }
        return Int(text)
    }

    // MARK: ISO 8601

    private static func parseISODate(_ bytes: [UInt8]) -> Date? {
        var position = 0
        func number(_ count: Int) -> Int? {
            guard position + count <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[position..<position + count] {
                guard isDigit(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            position += count
            return value
        }
        func eat(_ character: Character) -> Bool {
            guard position < bytes.count, bytes[position] == character.asciiValue else { return false }
            position += 1
            return true
        }

        guard let year = number(4), eat("-"), let month = number(2), eat("-"), let day = number(2) else { return nil }
        var hour = 0
        var minute = 0
        var second = 0
        var fraction = 0.0
        var offset = 0
        if position < bytes.count {
            guard eat("T") || eat("t") || eat(" "), let parsedHour = number(2), eat(":"), let parsedMinute = number(2) else { return nil }
            hour = parsedHour
            minute = parsedMinute
            if eat(":") {
                guard let parsedSecond = number(2) else { return nil }
                second = parsedSecond
                if eat(".") || eat(",") {
                    var scale = 0.1
                    var count = 0
                    while position < bytes.count, isDigit(bytes[position]) {
                        fraction += Double(bytes[position] - UInt8(ascii: "0")) * scale
                        scale /= 10
                        position += 1
                        count += 1
                    }
                    guard count > 0 else { return nil }
                }
            }
            if position < bytes.count {
                if eat("Z") || eat("z") {
                    offset = 0
                } else {
                    guard let parsed = numericOffset(String(decoding: bytes[position...], as: UTF8.self)) else { return nil }
                    offset = parsed
                    position = bytes.count
                }
            }
            guard position == bytes.count else { return nil }
        }
        return epoch(year: year, month: month, day: day, hour: hour, minute: minute, second: second, fraction: fraction, offset: offset)
    }

    // MARK: Calendar arithmetic

    /// Proleptic Gregorian date and time to a `Date`, validated, without `Calendar`.
    private static func epoch(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, fraction: Double, offset: Int
    ) -> Date? {
        guard year >= 1, (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month),
            hour <= 23, minute <= 59, second <= 60
        else { return nil }
        // Days from civil (Howard Hinnant's algorithm).
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
