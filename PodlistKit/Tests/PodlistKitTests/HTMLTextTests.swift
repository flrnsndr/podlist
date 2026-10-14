import Foundation
import Testing

@testable import PodlistKit

struct HTMLTextTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let html: String
        let expected: String
        var testDescription: String { html }
        init(_ html: String, _ expected: String) {
            self.html = html
            self.expected = expected
        }
    }

    static let plainCases: [Case] = [
        // Paragraphs and blocks
        Case("<p>One</p><p>Two</p>", "One\n\nTwo"),
        Case("<p>One</p>\n\n\n<p>Two</p>", "One\n\nTwo"),
        Case("<div>One</div><div>Two</div>", "One\n\nTwo"),
        Case("<h1>Title</h1><p>Body</p>", "Title\n\nBody"),
        Case("<p></p><p></p><p>Only</p>", "Only"),
        Case("<blockquote>Quote</blockquote><p>After</p>", "Quote\n\nAfter"),
        Case("Before<p>Para</p>After", "Before\n\nPara\n\nAfter"),
        Case("<table><tr><td>A</td></tr><tr><td>B</td></tr></table>", "A\n\nB"),
        // Line breaks
        Case("One<br>Two", "One\nTwo"),
        Case("One<br/>Two<br />Three", "One\nTwo\nThree"),
        Case("One<BR>Two", "One\nTwo"),
        // Lists
        Case("<ul><li>A</li><li>B</li></ul>", "• A\n• B"),
        Case("<p>Intro</p><ul><li>A</li><li>B</li></ul><p>Outro</p>", "Intro\n\n• A\n• B\n\nOutro"),
        Case("<ol><li>A</li><li>B</li></ol>", "• A\n• B"),
        Case("<ul><li>A<li>B</ul>", "• A\n• B"),
        Case("<ul>\n  <li>A</li>\n  <li>B</li>\n</ul>", "• A\n• B"),
        // Inline formatting, links and unknown tags
        Case("a <b>bold</b> and <i>it</i> and <strong>s</strong> <em>e</em>", "a bold and it and s e"),
        Case("<a href=\"https://e.com\">link</a>", "link"),
        Case("<span class=\"x\">span</span><font color=red>font</font>", "spanfont"),
        // Whitespace
        Case("  <p>  lots   of \n\t space  </p>  ", "lots of space"),
        Case("a <b>b</b> c", "a b c"),
        Case("a<b> b </b>c", "a b c"),
        Case("<p>trailing </p><p> leading</p>", "trailing\n\nleading"),
        // Entities
        Case("Tom &amp; Jerry", "Tom & Jerry"),
        Case("1 &lt; 2 &gt; 0 &quot;q&quot; it&apos;s", "1 < 2 > 0 \"q\" it's"),
        Case("a&nbsp;b", "a\u{00A0}b"),
        Case("&auml;&ouml;&uuml;&Auml;&Ouml;&Uuml;&szlig;", "äöüÄÖÜß"),
        Case("&hellip;&ndash;&mdash;", "…–—"),
        Case("&laquo;x&raquo; &bdquo;y&ldquo; &ldquo;z&rdquo; &lsquo;a&rsquo;", "«x» „y“ “z” ‘a’"),
        Case("&#65;&#228;&#x41;&#xE4;&#X41;", "AäAäA"),
        Case("&#128512;", "😀"),
        // Dropped content
        Case("a<script>var x = '<p>no</p>';</script>b", "ab"),
        Case("a<style>p { color: red }</style>b", "ab"),
        Case("<SCRIPT type=\"text/javascript\">alert(1)</SCRIPT>text", "text"),
        Case("a<!-- comment <p>x</p> -->b", "ab"),
        // Plain text without tags keeps its line breaks
        Case("Line one\nLine two\n\nLine four", "Line one\nLine two\n\nLine four"),
        Case("  \nplain\n  ", "plain"),
        Case("Plain &amp; simple\nsecond", "Plain & simple\nsecond"),
        Case("", ""),
        // Garbage
        Case("1 < 2", "1 < 2"),
        Case("a < b > c", "a < b > c"),
        Case("Tom & Jerry", "Tom & Jerry"),
        Case("&unknown; &#; &#xZZ; &amp", "&unknown; &#; &#xZZ; &amp"),
        Case("<p>unclosed <b>bold", "unclosed bold"),
        Case("text <", "text <"),
        Case("text <a href=\"x", "text"),
        Case("<<p>>x", "<\n\n>x"),
        Case("</p></div>stray", "stray"),
        Case("&#99999999999;&#xD800;", "&#99999999999;&#xD800;"),
    ]

    @Test(arguments: plainCases)
    func plainText(_ c: Case) {
        #expect(HTMLText.plainText(fromHTML: c.html) == c.expected)
    }

    @Test(arguments: plainCases)
    func attributedStringCharactersMatchPlainText(_ c: Case) {
        #expect(String(HTMLText.attributedString(fromHTML: c.html).characters) == c.expected)
    }

    // MARK: Attributes

    private func runs(_ html: String) -> [(text: String, intent: InlinePresentationIntent?, link: URL?)] {
        let attributed = HTMLText.attributedString(fromHTML: html)
        return attributed.runs.map {
            (String(attributed[$0.range].characters), $0.inlinePresentationIntent, $0.link)
        }
    }

    @Test func boldAndItalic() {
        let r = runs("a <b>b</b> <i>i</i> <strong>s</strong> <em>e</em> <b><i>bi</i></b>")
        func intent(_ text: String) -> InlinePresentationIntent? { r.first { $0.text == text }?.intent }
        #expect(intent("b") == .stronglyEmphasized)
        #expect(intent("i") == .emphasized)
        #expect(intent("s") == .stronglyEmphasized)
        #expect(intent("e") == .emphasized)
        #expect(intent("bi") == [.stronglyEmphasized, .emphasized])
        #expect(r.first?.intent == nil)
    }

    @Test func linkHTTPS() {
        let r = runs("see <a href=\"https://example.com/x?a=1&amp;b=2\">here</a>.")
        let link = r.first { $0.text == "here" }
        #expect(link?.link == URL(string: "https://example.com/x?a=1&b=2"))
        #expect(r.filter { $0.link != nil }.count == 1)
    }

    @Test(arguments: [
        ("<a href=\"http://e.com\">t</a>", "http://e.com"),
        ("<a href='https://e.com'>t</a>", "https://e.com"),
        ("<A HREF=\"mailto:a@e.com\">t</A>", "mailto:a@e.com"),
        ("<a class=\"c\" href=https://e.com>t</a>", "https://e.com"),
    ])
    func linkAccepted(_ html: String, _ expected: String) {
        #expect(runs(html).first?.link == URL(string: expected))
    }

    @Test(arguments: [
        "<a href=\"javascript:alert(1)\">t</a>",
        "<a href=\"ftp://e.com\">t</a>",
        "<a href=\"/relative\">t</a>",
        "<a href=\"#anchor\">t</a>",
        "<a href=\"\">t</a>",
        "<a>t</a>",
        "<a name=\"x\">t</a>",
    ])
    func linkRejected(_ html: String) {
        let r = runs(html)
        #expect(r.allSatisfy { $0.link == nil })
        #expect(String(HTMLText.attributedString(fromHTML: html).characters) == "t")
    }

    @Test func linkWithBoldInside() {
        let r = runs("<a href=\"https://e.com\"><b>x</b></a>")
        #expect(r.first?.link == URL(string: "https://e.com"))
        #expect(r.first?.intent == .stronglyEmphasized)
    }

    @Test func listItemsAreNotBoldAndBulletHasNoLink() {
        let r = runs("<ul><li><a href=\"https://e.com\">x</a></li></ul>")
        #expect(r.map(\.text).joined() == "• x")
        #expect(r.first { $0.text.contains("•") }?.link == nil)
    }

    // MARK: Timestamps

    @Test func timestampsBecomeLinks() {
        let r = runs("<p>Siehe 12:34 und (1:02:03).</p>")
        let links = r.compactMap(\.link)
        #expect(links == [ShowNotesTimestamps.url(for: 754), ShowNotesTimestamps.url(for: 3723)])
        #expect(r.first { $0.link == ShowNotesTimestamps.url(for: 754) }?.text == "12:34")
        #expect(r.map(\.text).joined() == "Siehe 12:34 und (1:02:03).")
    }

    @Test func timestampsInsideLinksKeepTheirLink() {
        let r = runs("<a href=\"https://e.com\">ab 12:34</a> und 5:00")
        #expect(r.first { $0.text.contains("12:34") }?.link == URL(string: "https://e.com"))
        #expect(r.compactMap(\.link).contains(ShowNotesTimestamps.url(for: 300)))
        #expect(!r.compactMap(\.link).contains(ShowNotesTimestamps.url(for: 754)))
    }

    @Test func timestampInBoldKeepsEmphasis() {
        let r = runs("<b>12:34</b>")
        #expect(r.first?.link == ShowNotesTimestamps.url(for: 754))
        #expect(r.first?.intent == .stronglyEmphasized)
    }

    @Test func showNotesPipelineGivesChapters() {
        let html = """
            <p>Heute sprechen wir über Rom &amp; die Antike.</p>
            <p>Kapitel:</p>
            <ul>
            <li>00:00:00 Intro</li>
            <li>00:03:20 Begrüßung &amp; Neuigkeiten</li>
            <li>00:45:10 Interview mit Anna – Teil 1</li>
            <li>1:02:03 Abschied</li>
            </ul>
            <p>Mehr unter <a href="https://example.com">example.com</a></p>
            """
        let text = HTMLText.plainText(fromHTML: html)
        let chapters = ShowNotesTimestamps.chapters(inPlainText: text, duration: 4000)
        #expect(chapters.map(\.title) == ["Intro", "Begrüßung & Neuigkeiten", "Interview mit Anna – Teil 1", "Abschied"])
        #expect(chapters.map(\.start) == [0, 200, 2710, 3723])
    }

    @Test func lineBreaksSurviveForChapters() {
        let text = HTMLText.plainText(fromHTML: "00:00 Intro<br>01:00 Eins<br/>02:00 Zwei<p>03:00 Drei</p>")
        #expect(ShowNotesTimestamps.chapters(inPlainText: text, duration: nil).map(\.title) == ["Intro", "Eins", "Zwei", "Drei"])
    }

    @Test func garbageDoesNotCrash() {
        var generator = SystemRandomNumberGenerator()
        let pieces = ["<", ">", "&", ";", "#", "x", "<p>", "</p>", "<a href=\"", "\"", "<b>", "</i>", "&#", "<script>", "</script>", "<!--", "-->", "<li>", " ", "\n", "ä", "<br"]
        for _ in 0..<300 {
            let html = (0..<Int.random(in: 0..<30, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
            _ = HTMLText.attributedString(fromHTML: html)
            _ = HTMLText.plainText(fromHTML: html)
        }
    }
}
