import Foundation

/// Converts a `TaskCommentsBundle` into a markdown blob suitable for pasting
/// into an LLM chat: clear authorship, timestamps, quoted forwards, and
/// attachment names.
enum MarkdownCommentExporter {
    static func export(bundle: TaskCommentsBundle, taskURL: URL?) -> String {
        var lines: [String] = []

        let header = bundle.humanNumber.map { "# Задача #\($0): \(bundle.taskName)" }
            ?? "# \(bundle.taskName)"
        lines.append(header)
        if let url = taskURL {
            lines.append("")
            lines.append(url.absoluteString)
        }
        lines.append("")
        lines.append("## Комментарии (\(bundle.comments.count))")
        lines.append("")

        for comment in bundle.comments {
            lines.append(contentsOf: render(comment))
            lines.append("")
            lines.append("---")
            lines.append("")
        }

        // Drop trailing separator for a clean tail.
        while let last = lines.last, last == "---" || last.isEmpty {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ comment: MegaplanComment) -> [String] {
        var lines: [String] = []

        let timestamp = comment.timeCreated.map(formattedTimestamp) ?? "—"
        let author = (comment.authorName?.isEmpty == false ? comment.authorName! : "—")
        lines.append("### \(timestamp) — \(author)")
        lines.append("")

        if let forwarded = comment.forwardedFrom {
            let fwdTs = forwarded.timeCreated.map(formattedTimestamp) ?? "—"
            let fwdAuthor = (forwarded.authorName?.isEmpty == false ? forwarded.authorName! : "—")
            lines.append("> ┌─ 💬 **Цитата** · \(fwdAuthor) · \(fwdTs)")
            lines.append("> │")
            let body = htmlToMarkdown(forwarded.contentHTML)
            let bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false)
            if bodyLines.isEmpty {
                lines.append("> │ _(пусто)_")
            } else {
                for line in bodyLines {
                    let trimmed = String(line)
                    lines.append(trimmed.isEmpty ? "> │" : "> │ \(trimmed)")
                }
            }
            lines.append("> └─")
            lines.append("")
        }

        let body = htmlToMarkdown(comment.contentHTML)
        if !body.isEmpty {
            lines.append(body)
        }

        if !comment.attachments.isEmpty {
            lines.append("")
            let names = comment.attachments.map { attachment -> String in
                if let url = attachment.url {
                    return "[\(attachment.name)](\(url.absoluteString))"
                }
                return attachment.name
            }.joined(separator: ", ")
            lines.append("📎 \(names)")
        }

        return lines
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone.current
        return f
    }()

    private static func formattedTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    // MARK: - HTML → Markdown
    //
    // Megaplan stores rich-text bodies as HTML. We don't need full fidelity —
    // just enough to keep authors / mentions / links intact when an LLM reads
    // the export.

    /// Sentinels surrounding a quoted block. We swap `<blockquote>...</blockquote>`
    /// for these markers BEFORE the rest of the HTML pipeline runs (paragraphs,
    /// br's, mentions, etc.), then format every block at the very end so the
    /// inner text is already cleaned-up plain markdown.
    private static let bqStart = "\u{0001}MP_BQ_START\u{0001}"
    private static let bqEnd = "\u{0001}MP_BQ_END\u{0001}"

    private static let blockquoteRegex = try? NSRegularExpression(
        pattern: #"<blockquote[^>]*?>([\s\S]*?)</blockquote>"#,
        options: [.caseInsensitive]
    )

    private static let mentionRegex = try? NSRegularExpression(
        pattern: #"<megaplan:mention[^>]*?>([\s\S]*?)</megaplan:mention>"#,
        options: [.caseInsensitive]
    )

    private static let paragraphRegex = try? NSRegularExpression(
        pattern: #"<p[^>]*?>([\s\S]*?)</p>"#,
        options: [.caseInsensitive]
    )

    private static let linkRegex = try? NSRegularExpression(
        pattern: #"<a[^>]*?href\s*=\s*[\"']([^\"']*)[\"'][^>]*?>([\s\S]*?)</a>"#,
        options: [.caseInsensitive]
    )

    private static let breakRegex = try? NSRegularExpression(
        pattern: #"<br\s*/?>"#,
        options: [.caseInsensitive]
    )

    private static let listItemRegex = try? NSRegularExpression(
        pattern: #"<li[^>]*?>([\s\S]*?)</li>"#,
        options: [.caseInsensitive]
    )

    private static let strongRegex = try? NSRegularExpression(
        pattern: #"<(b|strong)[^>]*?>([\s\S]*?)</\1>"#,
        options: [.caseInsensitive]
    )

    private static let emphasisRegex = try? NSRegularExpression(
        pattern: #"<(i|em)[^>]*?>([\s\S]*?)</\1>"#,
        options: [.caseInsensitive]
    )

    private static let stripRegex = try? NSRegularExpression(
        pattern: #"<[^>]+?>"#,
        options: []
    )

    private static let collapseRegex = try? NSRegularExpression(
        pattern: #"\n{3,}"#,
        options: []
    )

    private static func apply(_ regex: NSRegularExpression?, to string: String, template: String) -> String {
        guard let regex else { return string }
        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: template)
    }

    static func htmlToMarkdown(_ html: String) -> String {
        var s = html
        // Wrap blockquotes in sentinels so we can format them after the rest of
        // the HTML has been reduced to plain markdown.
        s = apply(blockquoteRegex, to: s, template: "\n\n\(bqStart)$1\(bqEnd)\n\n")
        // Megaplan-specific mention tags first so the inner text is preserved.
        s = apply(mentionRegex, to: s, template: "@$1")
        // Markdown links from anchors.
        s = apply(linkRegex, to: s, template: "[$2]($1)")
        // Paragraph spacing.
        s = apply(paragraphRegex, to: s, template: "$1\n\n")
        // Line breaks.
        s = apply(breakRegex, to: s, template: "\n")
        // Bullet items.
        s = apply(listItemRegex, to: s, template: "- $1\n")
        // Inline emphasis.
        s = apply(strongRegex, to: s, template: "**$2**")
        s = apply(emphasisRegex, to: s, template: "_$2_")
        // Drop any remaining tags.
        s = apply(stripRegex, to: s, template: "")
        // Decode entities (re-uses HTMLCleaner's decoding for shared semantics).
        s = HTMLCleaner.cleanEntities(s)
        // Format the marked blockquote regions as visible quote blocks.
        s = formatBlockquoteSentinels(in: s)
        // Normalise whitespace runs.
        s = apply(collapseRegex, to: s, template: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces every `bqStart … bqEnd` region with a clearly delimited quote
    /// block. Non-greedy match, processed iteratively so multiple top-level
    /// quotes in the same body are all formatted (Megaplan rarely nests quotes,
    /// but if it does the inner pair lands as a sub-quote inside the outer).
    private static func formatBlockquoteSentinels(in input: String) -> String {
        var output = input
        while let startRange = output.range(of: bqStart),
              let endRange = output.range(of: bqEnd, range: startRange.upperBound..<output.endIndex) {
            let inner = String(output[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let formatted = renderQuoteBlock(inner)
            output.replaceSubrange(startRange.lowerBound..<endRange.upperBound, with: formatted)
        }
        return output
    }

    /// Wraps `inner` (already cleaned-up plain markdown) into the canonical
    /// quote frame. Empty quotes are kept so the reader still sees something
    /// was quoted.
    private static func renderQuoteBlock(_ inner: String) -> String {
        var lines: [String] = []
        lines.append("> ┌─ 💬 **Цитата**")
        lines.append("> │")
        let bodyLines = inner.split(separator: "\n", omittingEmptySubsequences: false)
        if bodyLines.isEmpty || (bodyLines.count == 1 && bodyLines[0].isEmpty) {
            lines.append("> │ _(пусто)_")
        } else {
            for raw in bodyLines {
                let trimmed = String(raw)
                lines.append(trimmed.isEmpty ? "> │" : "> │ \(trimmed)")
            }
        }
        lines.append("> └─")
        return "\n\n" + lines.joined(separator: "\n") + "\n\n"
    }
}
