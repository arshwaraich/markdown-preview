import Foundation

/// A small, dependency-free Markdown -> HTML converter.
/// Covers the subset people actually write: headings, lists, code, quotes,
/// tables, rules, and the usual inline emphasis/links/images.
enum Markdown {

    static func html(from markdown: String) -> String {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        var out = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code block
            if let fence = fenceMarker(trimmed) {
                let lang = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(fence), fenceMarker(t) != nil { i += 1; break }
                    body.append(lines[i])
                    i += 1
                }
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                out += "<pre><code\(cls)>\(escape(body.joined(separator: "\n")))</code></pre>\n"
                continue
            }

            // Horizontal rule
            if isRule(trimmed) { out += "<hr>\n"; i += 1; continue }

            // ATX heading
            if let (level, text) = heading(trimmed) {
                let id = slug(text)
                out += "<h\(level) id=\"\(id)\">\(inline(text))</h\(level)>\n"
                i += 1
                continue
            }

            // Setext heading
            if i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !next.isEmpty, next.allSatisfy({ $0 == "=" }) {
                    out += "<h1 id=\"\(slug(trimmed))\">\(inline(trimmed))</h1>\n"; i += 2; continue
                }
                if !next.isEmpty, next.allSatisfy({ $0 == "-" }), next.count >= 2 {
                    out += "<h2 id=\"\(slug(trimmed))\">\(inline(trimmed))</h2>\n"; i += 2; continue
                }
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else {
                        if t.isEmpty { break }
                        body.append(t); i += 1; continue
                    }
                    var rest = String(t.dropFirst())
                    if rest.hasPrefix(" ") { rest.removeFirst() }
                    body.append(rest)
                    i += 1
                }
                out += "<blockquote>\n" + html(from: body.joined(separator: "\n")) + "</blockquote>\n"
                continue
            }

            // Table
            if i + 1 < lines.count, trimmed.contains("|"),
               isTableDivider(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let aligns = alignments(lines[i + 1].trimmingCharacters(in: .whitespaces))
                var rows: [[String]] = []
                let header = cells(trimmed)
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty || !t.contains("|") { break }
                    rows.append(cells(t)); i += 1
                }
                out += "<table>\n<thead><tr>"
                for (n, c) in header.enumerated() { out += "<th\(style(aligns, n))>\(inline(c))</th>" }
                out += "</tr></thead>\n<tbody>\n"
                for row in rows {
                    out += "<tr>"
                    for (n, c) in row.enumerated() { out += "<td\(style(aligns, n))>\(inline(c))</td>" }
                    out += "</tr>\n"
                }
                out += "</tbody>\n</table>\n"
                continue
            }

            // Lists
            if listMarker(line) != nil {
                let (block, next) = takeList(lines, from: i)
                out += block
                i = next
                continue
            }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || isRule(t) || heading(t) != nil || fenceMarker(t) != nil
                    || t.hasPrefix(">") || listMarker(lines[i]) != nil { break }
                para.append(t)
                i += 1
            }
            if !para.isEmpty { out += "<p>\(inline(para.joined(separator: "\n")))</p>\n" }
        }

        _ = lines
        return out
    }

    // MARK: - Lists

    private struct Marker { let indent: Int; let ordered: Bool; let content: String; let start: String }

    private static func listMarker(_ line: String) -> Marker? {
        let indent = line.prefix(while: { $0 == " " }).count
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }
        if "-*+".contains(first), rest.dropFirst().first == " " {
            return Marker(indent: indent, ordered: false,
                          content: String(rest.dropFirst(2)), start: "1")
        }
        let digits = rest.prefix(while: { $0.isNumber })
        if !digits.isEmpty {
            let after = rest.dropFirst(digits.count)
            if let d = after.first, d == "." || d == ")", after.dropFirst().first == " " {
                return Marker(indent: indent, ordered: true,
                              content: String(after.dropFirst(2)), start: String(digits))
            }
        }
        return nil
    }

    private static func takeList(_ lines: [String], from start: Int) -> (String, Int) {
        guard let first = listMarker(lines[start]) else { return ("", start + 1) }
        let baseIndent = first.indent
        var items: [[String]] = []
        var i = start
        var loose = false
        var pendingBlank = false

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // A blank line ends the list unless the next line continues it.
                if i + 1 < lines.count {
                    let nxt = lines[i + 1]
                    let nxtIndent = nxt.prefix(while: { $0 == " " }).count
                    let continues = (listMarker(nxt).map { $0.indent >= baseIndent } ?? false)
                        || (nxtIndent > baseIndent && !nxt.trimmingCharacters(in: .whitespaces).isEmpty)
                    if continues { pendingBlank = true; i += 1; continue }
                }
                i += 1
                break
            }
            if let m = listMarker(line), m.indent <= baseIndent {
                if m.ordered != first.ordered && m.indent == baseIndent { break }
                if pendingBlank { loose = true; pendingBlank = false }
                items.append([m.content])
                i += 1
                continue
            }
            let indent = line.prefix(while: { $0 == " " }).count
            if indent > baseIndent, !items.isEmpty {
                if pendingBlank { loose = true; items[items.count - 1].append(""); pendingBlank = false }
                items[items.count - 1].append(String(line.dropFirst(min(indent, baseIndent + 2))))
                i += 1
                continue
            }
            if items.isEmpty { break }
            if pendingBlank { break }
            items[items.count - 1].append(trimmed) // lazy continuation
            i += 1
        }

        let tag = first.ordered ? "ol" : "ul"
        let startAttr = (first.ordered && first.start != "1") ? " start=\"\(first.start)\"" : ""
        var out = "<\(tag)\(startAttr)>\n"
        for item in items {
            let text = item.joined(separator: "\n")
            var body: String
            if loose || text.contains("\n\n") || text.contains("```") {
                body = html(from: text)
            } else {
                // Tight item: inline the first line, render any nested block after it.
                let parts = text.components(separatedBy: "\n")
                let head = parts[0]
                let tail = parts.dropFirst().joined(separator: "\n")
                body = inline(head) + (tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                       ? "" : "\n" + html(from: tail))
            }
            if let task = taskBox(&body) { body = task }
            out += "<li>\(body)</li>\n"
        }
        out += "</\(tag)>\n"
        return (out, i)
    }

    private static func taskBox(_ body: inout String) -> String? {
        let lower = body.lowercased()
        if lower.hasPrefix("[ ] ") {
            return "<input type=\"checkbox\" disabled> " + String(body.dropFirst(4))
        }
        if lower.hasPrefix("[x] ") {
            return "<input type=\"checkbox\" checked disabled> " + String(body.dropFirst(4))
        }
        return nil
    }

    // MARK: - Block helpers

    private static func fenceMarker(_ t: String) -> String? {
        for ch in ["```", "~~~"] where t.hasPrefix(ch) { return ch }
        return nil
    }

    private static func isRule(_ t: String) -> Bool {
        for ch: Character in ["-", "*", "_"] {
            let stripped = t.replacingOccurrences(of: " ", with: "")
            if stripped.count >= 3, stripped.allSatisfy({ $0 == ch }) { return true }
        }
        return false
    }

    private static func heading(_ t: String) -> (Int, String)? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isTableDivider(_ t: String) -> Bool {
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func cells(_ line: String) -> [String] {
        var t = line
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignments(_ divider: String) -> [String] {
        cells(divider).map { c in
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            if left && right { return "center" }
            if right { return "right" }
            if left { return "left" }
            return ""
        }
    }

    private static func style(_ aligns: [String], _ n: Int) -> String {
        guard n < aligns.count, !aligns[n].isEmpty else { return "" }
        return " style=\"text-align:\(aligns[n])\""
    }

    private static func slug(_ s: String) -> String {
        let allowed = s.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }

    // MARK: - Inline

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)

        // Code spans get stashed so nothing else rewrites their contents.
        var stash: [String] = []
        s = replace(s, #"(`+)(.+?)\1"#) { m in
            stash.append("<code>\(m[2])</code>")
            return "\u{0}\(stash.count - 1)\u{0}"
        }

        s = replace(s, #"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)"#) { m in
            "<img src=\"\(m[2])\" alt=\"\(m[1])\">"
        }
        s = replace(s, #"\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)"#) { m in
            "<a href=\"\(m[2])\">\(m[1])</a>"
        }
        s = replace(s, #"&lt;(https?://[^\s&]+)&gt;"#) { m in "<a href=\"\(m[1])\">\(m[1])</a>" }

        s = replace(s, #"\*\*\*(.+?)\*\*\*"#) { m in "<strong><em>\(m[1])</em></strong>" }
        s = replace(s, #"\*\*(.+?)\*\*"#) { m in "<strong>\(m[1])</strong>" }
        s = replace(s, #"__(.+?)__"#) { m in "<strong>\(m[1])</strong>" }
        s = replace(s, #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#) { m in "<em>\(m[1])</em>" }
        s = replace(s, #"(?<![\w_])_([^_\n]+)_(?![\w_])"#) { m in "<em>\(m[1])</em>" }
        s = replace(s, #"~~(.+?)~~"#) { m in "<del>\(m[1])</del>" }

        s = s.replacingOccurrences(of: "  \n", with: "<br>\n")

        for (n, code) in stash.enumerated() {
            s = s.replacingOccurrences(of: "\u{0}\(n)\u{0}", with: code)
        }
        return s
    }

    private static func replace(_ s: String, _ pattern: String,
                                _ body: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += body(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
