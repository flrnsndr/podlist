import Foundation

/// Converts podcast show notes (HTML as found in feeds, rarely well-formed) into text.
///
/// A small hand-written tokenizer: no WebKit, no `NSAttributedString` HTML import, no `XMLParser`.
public enum HTMLText {
    public static func attributedString(fromHTML html: String) -> AttributedString {
        var converter = Converter(html: html)
        return linkTimestamps(in: converter.run())
    }

    /// Makes every timestamp that is not already inside a link tappable (`ShowNotesTimestamps.url(for:)`).
    private static func linkTimestamps(in text: AttributedString) -> AttributedString {
        var targets: [(Range<AttributedString.Index>, URL)] = []
        for run in text.runs where run.link == nil {
            let slice = text[run.range]
            let string = String(slice.characters)
            for match in ShowNotesTimestamps.matches(in: string) {
                let characters = slice.characters
                let lower = characters.index(
                    characters.startIndex, offsetBy: string.distance(from: string.startIndex, to: match.range.lowerBound))
                let upper = characters.index(
                    lower, offsetBy: string.distance(from: match.range.lowerBound, to: match.range.upperBound))
                targets.append((lower..<upper, ShowNotesTimestamps.url(for: match.time)))
            }
        }
        var result = text
        for (range, url) in targets { result[range].link = url }
        return result
    }

    public static func plainText(fromHTML html: String) -> String {
        String(attributedString(fromHTML: html).characters)
    }

    // MARK: - Converter

    private struct Style: Equatable {
        var intent: InlinePresentationIntent = []
        var link: URL?
        static let plain = Style()
    }

    private static let blockTags: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "blockquote", "table", "tr", "section",
        "article", "header", "footer", "aside", "nav", "main", "pre", "hr", "dl", "dt", "dd", "figure",
        "figcaption", "form", "fieldset", "address", "thead", "tbody", "tfoot", "caption",
    ]

    private struct Converter {
        let chars: [Character]
        var i = 0
        /// Without any tag, line breaks in the source are kept.
        let keepsNewlines: Bool

        var result = AttributedString()
        var buffer = ""
        var bufferStyle = Style.plain
        var hasOutput = false
        var lastWasSpace = true
        var pendingSpace = false
        var pendingBreak = 0

        var boldDepth = 0
        var italicDepth = 0
        var links: [URL?] = []
        var listDepth = 0

        init(html: String) {
            chars = Array(html)
            var found = false
            for (index, c) in chars.enumerated() where c == "<" && index + 1 < chars.count {
                let next = chars[index + 1]
                if next.isASCII && (next.isLetter || next == "/" || next == "!" || next == "?") {
                    found = true
                    break
                }
            }
            keepsNewlines = !found
        }

        // MARK: Output

        var currentStyle: Style {
            var style = Style()
            if boldDepth > 0 { style.intent.insert(.stronglyEmphasized) }
            if italicDepth > 0 { style.intent.insert(.emphasized) }
            style.link = links.last ?? nil
            return style
        }

        mutating func emit(_ text: String, _ style: Style) {
            if style != bufferStyle { commit() }
            bufferStyle = style
            buffer += text
        }

        mutating func commit() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            if !bufferStyle.intent.isEmpty { piece.inlinePresentationIntent = bufferStyle.intent }
            if let link = bufferStyle.link { piece.link = link }
            result.append(piece)
            buffer = ""
        }

        mutating func flushPending() {
            if !hasOutput {
                // Leading whitespace and breaks are trimmed.
            } else if pendingBreak > 0 {
                emit(String(repeating: "\n", count: pendingBreak), .plain)
            } else if pendingSpace {
                emit(" ", .plain)
            }
            pendingBreak = 0
            pendingSpace = false
        }

        static func isCollapsibleSpace(_ c: Character) -> Bool {
            c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\r\n" || c == "\u{0C}"
        }

        mutating func addText(_ c: Character) {
            if keepsNewlines && (c == "\n" || c == "\r" || c == "\r\n") {
                pendingBreak = min(pendingBreak + 1, 2)
                pendingSpace = false
            } else if Self.isCollapsibleSpace(c) {
                if !lastWasSpace && pendingBreak == 0 { pendingSpace = true }
            } else {
                flushPending()
                emit(String(c), currentStyle)
                hasOutput = true
                lastWasSpace = false
            }
        }

        mutating func addText(_ s: String) {
            for c in s { addText(c) }
        }

        mutating func setBreak(_ count: Int) {
            pendingBreak = max(pendingBreak, count)
            pendingSpace = false
            lastWasSpace = true
        }

        mutating func addBullet() {
            setBreak(1)
            flushPending()
            emit("• ", .plain)
            hasOutput = true
            lastWasSpace = true
        }

        // MARK: Scanning

        mutating func run() -> AttributedString {
            while i < chars.count {
                let c = chars[i]
                if c == "<", let handled = scanMarkup() {
                    if !handled { break }
                } else if c == "&" {
                    scanEntity()
                } else {
                    addText(c)
                    i += 1
                }
            }
            commit()
            return result
        }

        func lowercasedPrefix(at index: Int, is text: String) -> Bool {
            let scalars = Array(text)
            guard index + scalars.count <= chars.count else { return false }
            for (offset, expected) in scalars.enumerated()
            where Character(chars[index + offset].lowercased()) != expected {
                return false
            }
            return true
        }

        func find(_ text: String, from start: Int) -> Int? {
            var index = start
            while index < chars.count {
                if lowercasedPrefix(at: index, is: text) { return index }
                index += 1
            }
            return nil
        }

        /// Returns `nil` if the `<` is plain text, `true` if markup was consumed, `false` if the
        /// rest of the input is unterminated markup (dropped).
        mutating func scanMarkup() -> Bool? {
            guard i + 1 < chars.count else { return nil }
            let next = chars[i + 1]

            if next == "!" || next == "?" {
                if lowercasedPrefix(at: i, is: "<!--") {
                    guard let end = find("-->", from: i + 4) else { return false }
                    i = end + 3
                } else {
                    guard let end = find(">", from: i + 2) else { return false }
                    i = end + 1
                }
                return true
            }

            let closing = next == "/"
            let nameStart = closing ? i + 2 : i + 1
            guard nameStart < chars.count, chars[nameStart].isASCII, chars[nameStart].isLetter else { return nil }

            // Find the end of the tag, honoring quoted attribute values.
            var j = nameStart
            var quote: Character?
            while j < chars.count {
                let c = chars[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == ">" {
                    break
                }
                j += 1
            }
            guard j < chars.count else { return false }

            let body = Array(chars[nameStart..<j])
            i = j + 1
            var nameEnd = 0
            while nameEnd < body.count, body[nameEnd].isASCII, body[nameEnd].isLetter || body[nameEnd].isNumber {
                nameEnd += 1
            }
            let name = String(body[0..<nameEnd]).lowercased()
            let selfClosing = body.last == "/"

            if closing {
                handleClose(name)
            } else {
                let attributes = Self.parseAttributes(Array(body[nameEnd...]))
                handleOpen(name, attributes: attributes)
                if (name == "script" || name == "style") && !selfClosing {
                    if let end = find("</\(name)", from: i), let close = find(">", from: end) {
                        i = close + 1
                    } else {
                        i = chars.count
                    }
                }
            }
            return true
        }

        mutating func handleOpen(_ name: String, attributes: [String: String]) {
            switch name {
            case "br":
                pendingBreak = min(pendingBreak + 1, 2)
                pendingSpace = false
                lastWasSpace = true
            case "li":
                addBullet()
            case "ul", "ol":
                setBreak(listDepth > 0 ? 1 : 2)
                listDepth += 1
            case "b", "strong":
                boldDepth += 1
            case "i", "em":
                italicDepth += 1
            case "a":
                links.append(Self.webLink(attributes["href"]))
            case "td", "th":
                if hasOutput && pendingBreak == 0 { pendingSpace = true }
            default:
                if HTMLText.blockTags.contains(name) { setBreak(2) }
            }
        }

        mutating func handleClose(_ name: String) {
            switch name {
            case "li":
                setBreak(1)
            case "ul", "ol":
                listDepth = max(0, listDepth - 1)
                setBreak(listDepth > 0 ? 1 : 2)
            case "b", "strong":
                boldDepth = max(0, boldDepth - 1)
            case "i", "em":
                italicDepth = max(0, italicDepth - 1)
            case "a":
                if !links.isEmpty { links.removeLast() }
            default:
                if HTMLText.blockTags.contains(name) { setBreak(2) }
            }
        }

        static func webLink(_ value: String?) -> URL? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                let url = URL(string: trimmed), let scheme = url.scheme?.lowercased()
            else { return nil }
            switch scheme {
            case "http", "https": return (url.host(percentEncoded: false) ?? "").isEmpty ? nil : url
            case "mailto": return url
            default: return nil
            }
        }

        static func parseAttributes(_ body: [Character]) -> [String: String] {
            var attributes: [String: String] = [:]
            var k = 0
            func skipSpace() { while k < body.count, isCollapsibleSpace(body[k]) { k += 1 } }
            while k < body.count {
                skipSpace()
                var key = ""
                while k < body.count, !isCollapsibleSpace(body[k]), body[k] != "=", body[k] != "/" {
                    key.append(body[k])
                    k += 1
                }
                if k < body.count, body[k] == "/", key.isEmpty { k += 1; continue }
                skipSpace()
                var value = ""
                if k < body.count, body[k] == "=" {
                    k += 1
                    skipSpace()
                    if k < body.count, body[k] == "\"" || body[k] == "'" {
                        let q = body[k]
                        k += 1
                        while k < body.count, body[k] != q { value.append(body[k]); k += 1 }
                        k += 1
                    } else {
                        while k < body.count, !isCollapsibleSpace(body[k]) { value.append(body[k]); k += 1 }
                    }
                }
                if !key.isEmpty { attributes[key.lowercased()] = decodeEntities(value) }
            }
            return attributes
        }

        // MARK: Entities

        mutating func scanEntity() {
            if let (text, length) = Self.entity(in: chars, at: i) {
                i += length
                addDecoded(text)
            } else {
                addText("&")
                i += 1
            }
        }

        mutating func addDecoded(_ text: String) {
            for c in text {
                if c == "\u{00A0}" {
                    flushPending()
                    emit(String(c), currentStyle)
                    hasOutput = true
                    lastWasSpace = false
                } else {
                    addText(c)
                }
            }
        }

        /// The decoded text and the number of characters consumed, or `nil` if not an entity.
        static func entity(in chars: [Character], at start: Int) -> (String, Int)? {
            guard chars[start] == "&" else { return nil }
            var end = start + 1
            while end < chars.count, end - start <= 12, chars[end] != ";" {
                let c = chars[end]
                guard c.isASCII, c.isLetter || c.isNumber || c == "#" else { return nil }
                end += 1
            }
            guard end < chars.count, chars[end] == ";", end > start + 1 else { return nil }
            let name = String(chars[(start + 1)..<end])
            let length = end - start + 1

            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let value: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") {
                    value = UInt32(digits.dropFirst(), radix: 16)
                } else {
                    value = UInt32(digits, radix: 10)
                }
                guard let value, let scalar = Unicode.Scalar(value) else { return nil }
                return (String(Character(scalar)), length)
            }
            guard let text = HTMLText.namedEntities[name] else { return nil }
            return (text, length)
        }

        static func decodeEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }
            let chars = Array(text)
            var out = ""
            var k = 0
            while k < chars.count {
                if chars[k] == "&", let (decoded, length) = entity(in: chars, at: k) {
                    out += decoded
                    k += length
                } else {
                    out.append(chars[k])
                    k += 1
                }
            }
            return out
        }
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "hellip": "…", "ndash": "–", "mdash": "—", "laquo": "«", "raquo": "»",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "sbquo": "‚",
        "copy": "©", "reg": "®", "trade": "™", "euro": "€", "bull": "•", "middot": "·", "deg": "°",
        "eacute": "é", "egrave": "è", "agrave": "à", "aacute": "á", "ccedil": "ç", "ntilde": "ñ",
        "oacute": "ó", "iacute": "í", "uacute": "ú", "ecirc": "ê", "acirc": "â", "ocirc": "ô",
        "times": "×",
    ]
}
