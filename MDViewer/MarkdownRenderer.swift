import Foundation

struct MarkdownHeading: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String
}

struct RenderedMarkdown: Equatable {
    let html: String
    let headings: [MarkdownHeading]
}

struct MarkdownRenderer {
    static func htmlDocument(markdown: String, title: String, stylesheet: String, errorMessage: String? = nil) -> String {
        render(markdown: markdown, title: title, stylesheet: stylesheet, errorMessage: errorMessage).html
    }

    static func render(markdown: String, title: String, stylesheet: String, errorMessage: String? = nil) -> RenderedMarkdown {
        let rendered = renderBlocks(markdown, collectHeadings: true)
        let errorBanner = errorMessage.map {
            "<aside class=\"app-error\"><strong>File warning</strong><span>\(escapeHTML($0))</span></aside>"
        } ?? ""

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
          \(baseCSS)
          \(stylesheet)
          </style>
        </head>
        <body>
          <main class="markdown-body">
            \(errorBanner)
            \(rendered.html)
          </main>
        </body>
        </html>
        """

        return RenderedMarkdown(html: html, headings: rendered.headings)
    }

    private static let baseCSS = """
    :root {
      color-scheme: light dark;
      text-rendering: optimizeLegibility;
      -webkit-font-smoothing: antialiased;
    }

    body {
      margin: 0;
      background: var(--page-bg, Canvas);
      color: var(--text, CanvasText);
      font-family: var(--body-font, -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif);
      line-height: 1.62;
    }

    .markdown-body {
      box-sizing: border-box;
      max-width: var(--content-width, 840px);
      min-height: 100vh;
      margin: 0 auto;
      padding: var(--content-padding, 48px 56px 72px);
      background: var(--content-bg, transparent);
    }

    .app-error {
      display: grid;
      gap: 2px;
      margin: 0 0 24px;
      padding: 12px 14px;
      border: 1px solid color-mix(in srgb, #c7522a 42%, transparent);
      border-radius: 8px;
      background: color-mix(in srgb, #c7522a 10%, transparent);
      color: var(--text, CanvasText);
      font-size: 0.92rem;
    }

    .app-error span {
      color: var(--muted, #6b7280);
    }

    h1[id],
    h2[id],
    h3[id],
    h4[id],
    h5[id],
    h6[id] {
      scroll-margin-top: 28px;
    }

    .mdviewer-find-highlight {
      border-radius: 3px;
      background: color-mix(in srgb, #ffd54f 68%, transparent);
      box-shadow: 0 0 0 1px color-mix(in srgb, #b17b00 22%, transparent);
    }

    @media (max-width: 720px) {
      .markdown-body {
        padding: 28px 24px 48px;
      }
    }
    """

    private struct RenderedBlocks {
        let html: String
        let headings: [MarkdownHeading]
    }

    private static func renderBlocks(_ markdown: String, collectHeadings: Bool = false) -> RenderedBlocks {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var html: [String] = []
        var headings: [MarkdownHeading] = []
        var usedAnchors: [String: Int] = [:]
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
            html.append("<p>\(renderInline(text))</p>")
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                flushParagraph()
                let rendered = renderCodeFence(lines: lines, startIndex: index, marker: fence.marker, language: fence.language)
                html.append(rendered.html)
                index = rendered.nextIndex
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                let anchor = uniqueAnchor(for: heading.text, usedAnchors: &usedAnchors)
                if collectHeadings {
                    headings.append(MarkdownHeading(id: anchor, level: heading.level, title: heading.text))
                }
                html.append("<h\(heading.level) id=\"\(escapeAttribute(anchor))\">\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                html.append("<hr>")
                index += 1
                continue
            }

            if isTableHeader(lines, at: index) {
                flushParagraph()
                let rendered = renderTable(lines: lines, startIndex: index)
                html.append(rendered.html)
                index = rendered.nextIndex
                continue
            }

            if let quote = blockquote(lines: lines, startIndex: index) {
                flushParagraph()
                html.append("<blockquote>\(quote.html)</blockquote>")
                index = quote.nextIndex
                continue
            }

            if let list = listBlock(lines: lines, startIndex: index) {
                flushParagraph()
                html.append(list.html)
                index = list.nextIndex
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return RenderedBlocks(html: html.joined(separator: "\n"), headings: headings)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level),
              line.dropFirst(level).first == " "
        else { return nil }

        return (level, String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func codeFence(in line: String) -> (marker: String, language: String)? {
        if line.hasPrefix("```") {
            return ("```", String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }

        if line.hasPrefix("~~~") {
            return ("~~~", String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces))
        }

        return nil
    }

    private static func renderCodeFence(
        lines: [String],
        startIndex: Int,
        marker: String,
        language: String
    ) -> (html: String, nextIndex: Int) {
        var code: [String] = []
        var index = startIndex + 1

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                let className = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
                return ("<pre><code\(className)>\(escapeHTML(code.joined(separator: "\n")))</code></pre>", index + 1)
            }

            code.append(lines[index])
            index += 1
        }

        return ("<pre><code>\(escapeHTML(code.joined(separator: "\n")))</code></pre>", index)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    private static func blockquote(lines: [String], startIndex: Int) -> (html: String, nextIndex: Int)? {
        var quoteLines: [String] = []
        var index = startIndex

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }

        guard !quoteLines.isEmpty else { return nil }
        return (renderBlocks(quoteLines.joined(separator: "\n")).html, index)
    }

    private static func listBlock(lines: [String], startIndex: Int) -> (html: String, nextIndex: Int)? {
        guard let first = listItem(from: lines[startIndex]) else { return nil }

        var items: [String] = []
        var index = startIndex

        while index < lines.count {
            guard let item = listItem(from: lines[index]), item.ordered == first.ordered else { break }
            items.append("<li>\(renderInline(item.text))</li>")
            index += 1
        }

        let tag = first.ordered ? "ol" : "ul"
        return ("<\(tag)>\n\(items.joined(separator: "\n"))\n</\(tag)>", index)
    }

    private static func listItem(from line: String) -> (ordered: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 2 else { return nil }

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return (false, String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }

        var digits = ""
        for character in trimmed {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }

        guard !digits.isEmpty else { return nil }
        let remainder = trimmed.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") || remainder.hasPrefix(") ") else { return nil }
        return (true, String(remainder.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func isTableHeader(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return splitTableRow(lines[index]).count > 1 && isTableDivider(lines[index + 1])
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard cells.count > 1 else { return false }
        return cells.allSatisfy { cell in
            let compact = cell.trimmingCharacters(in: .whitespaces)
            guard compact.count >= 3 else { return false }
            return compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func renderTable(lines: [String], startIndex: Int) -> (html: String, nextIndex: Int) {
        let headers = splitTableRow(lines[startIndex])
        var index = startIndex + 2
        var rows: [[String]] = []

        while index < lines.count {
            let cells = splitTableRow(lines[index])
            guard cells.count > 1 else { break }
            rows.append(cells)
            index += 1
        }

        let head = headers.map { "<th>\(renderInline($0))</th>" }.joined()
        let body = rows.map { row in
            "<tr>\(row.map { "<td>\(renderInline($0))</td>" }.joined())</tr>"
        }.joined(separator: "\n")

        return ("<table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>", index)
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func uniqueAnchor(for text: String, usedAnchors: inout [String: Int]) -> String {
        let base = slug(for: text)
        let count = usedAnchors[base, default: 0]
        usedAnchors[base] = count + 1
        return count == 0 ? base : "\(base)-\(count + 1)"
    }

    private static func slug(for text: String) -> String {
        var slug = ""
        var previousWasSeparator = false

        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                slug.append("-")
                previousWasSeparator = true
            }
        }

        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }

    private static func renderInline(_ raw: String) -> String {
        var codeSpans: [String] = []
        var text = replace(raw, pattern: "`([^`]+)`") { groups in
            let escaped = "<code>\(escapeHTML(groups[1]))</code>"
            codeSpans.append(escaped)
            return "\u{E000}\(codeSpans.count - 1)\u{E001}"
        }

        text = escapeHTML(text)

        text = replace(text, pattern: "!\\[([^\\]]*)\\]\\(([^\\s\\)]+)\\)") { groups in
            let alt = escapeAttribute(groups[1])
            let src = safeURL(groups[2])
            return "<img src=\"\(src)\" alt=\"\(alt)\">"
        }

        text = replace(text, pattern: "\\[([^\\]]+)\\]\\(([^\\s\\)]+)\\)") { groups in
            let label = groups[1]
            let href = safeURL(groups[2])
            return "<a href=\"\(href)\">\(label)</a>"
        }

        text = replace(text, pattern: "\\*\\*([^*]+)\\*\\*") { groups in
            "<strong>\(groups[1])</strong>"
        }

        text = replace(text, pattern: "__([^_]+)__") { groups in
            "<strong>\(groups[1])</strong>"
        }

        text = replace(text, pattern: "(^|\\s)\\*([^*]+)\\*") { groups in
            "\(groups[1])<em>\(groups[2])</em>"
        }

        text = replace(text, pattern: "(^|\\s)_([^_]+)_") { groups in
            "\(groups[1])<em>\(groups[2])</em>"
        }

        for (index, code) in codeSpans.enumerated() {
            text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: code)
        }

        return text
    }

    private static func replace(_ text: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text) else { continue }
            result += String(text[cursor..<fullRange.lowerBound])

            var groups: [String] = []
            for groupIndex in 0..<match.numberOfRanges {
                if let range = Range(match.range(at: groupIndex), in: text) {
                    groups.append(String(text[range]))
                } else {
                    groups.append("")
                }
            }

            result += transform(groups)
            cursor = fullRange.upperBound
        }

        result += String(text[cursor..<text.endIndex])
        return result
    }

    private static func safeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("javascript:") || lowercased.hasPrefix("data:text/html") {
            return "#"
        }

        return escapeAttribute(trimmed)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ value: String) -> String {
        escapeHTML(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
