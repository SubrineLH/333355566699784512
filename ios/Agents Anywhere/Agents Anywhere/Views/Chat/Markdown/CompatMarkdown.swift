import Foundation
import UIKit

// A self-contained Markdown reader for the iOS 14 build.
//
// The shipping client parses Markdown into `AttributedString`, which requires
// iOS 15, and renders it through Textual, which requires iOS 18. iOS 14 has
// neither, so this file replaces both halves:
//
//   * `CompatMarkdownParser` turns the source into a block list. Only the block
//     kinds the chat transcript actually produces are recognised.
//   * Inline spans (emphasis, code, links, strikethrough) are resolved into an
//     `NSAttributedString`, which CoreText has supported since iOS 6.
//
// The parser is deliberately line-oriented. Streaming appends only ever add to
// the tail, and `MarkdownStreamSplit` already finds a safe boundary, so a block
// never has to be re-read after it has been closed.

// MARK: - Blocks

enum CompatMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case codeBlock(language: String?, code: String)
    case quote(String)
    case bullet(depth: Int, text: String)
    case numbered(depth: Int, number: String, text: String)
    case table(header: [String], rows: [[String]], alignments: [CompatTableAlignment])
    case image(url: String, alt: String)
    case rule
}

enum CompatTableAlignment: Equatable {
    case leading, center, trailing
}

// MARK: - Parser

nonisolated enum CompatMarkdownParser {
    static func parse(_ text: String) -> [CompatMarkdownBlock] {
        var blocks: [CompatMarkdownBlock] = []
        var lines = text.components(separatedBy: "\n")
        var index = 0

        func flushParagraph(_ buffer: inout [String]) {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            buffer.removeAll(keepingCapacity: true)
        }

        var paragraph: [String] = []

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if let fence = fenceMarker(line) {
                flushParagraph(&paragraph)
                index += 1
                var body: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if isClosingFence(candidate, marker: fence.character, count: fence.count) {
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                let language = String(line.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                blocks.append(.codeBlock(
                    language: language.isEmpty ? nil : language,
                    code: body.joined(separator: "\n")
                ))
                continue
            }

            // Blank line closes the open paragraph.
            if line.isEmpty {
                flushParagraph(&paragraph)
                index += 1
                continue
            }

            // Thematic break.
            if isThematicBreak(line) {
                flushParagraph(&paragraph)
                blocks.append(.rule)
                index += 1
                continue
            }

            // ATX heading.
            if let heading = heading(line) {
                flushParagraph(&paragraph)
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Pipe table: a header row followed by a delimiter row.
            if line.contains("|"), index + 1 < lines.count,
               let alignments = tableDelimiter(lines[index + 1]) {
                flushParagraph(&paragraph)
                let header = tableCells(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|"), !candidate.isEmpty else { break }
                    rows.append(tableCells(candidate))
                    index += 1
                }
                if alignments.count == header.count {
                    blocks.append(.table(header: header, rows: rows, alignments: alignments))
                } else {
                    // A malformed delimiter row is just text.
                    blocks.append(.paragraph(header.joined(separator: " | ")))
                }
                continue
            }

            // Block quote, kept as one paragraph of its stripped lines.
            if line.hasPrefix(">") {
                flushParagraph(&paragraph)
                var body: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var stripped = String(candidate.dropFirst())
                    if stripped.hasPrefix(" ") { stripped.removeFirst() }
                    body.append(stripped)
                    index += 1
                }
                blocks.append(.quote(body.joined(separator: "\n")))
                continue
            }

            // Standalone image paragraph.
            if let image = standaloneImage(line) {
                flushParagraph(&paragraph)
                blocks.append(.image(url: image.url, alt: image.alt))
                index += 1
                continue
            }

            // List item, with leading-indent depth.
            if let item = listItem(raw) {
                flushParagraph(&paragraph)
                switch item.kind {
                case .bullet:
                    blocks.append(.bullet(depth: item.depth, text: item.text))
                case .numbered(let number):
                    blocks.append(.numbered(depth: item.depth, number: number, text: item.text))
                }
                index += 1
                continue
            }

            // Continuation of the open paragraph.
            paragraph.append(line)
            index += 1
        }

        flushParagraph(&paragraph)
        return blocks
    }

    // MARK: Line recognisers

    private static func fenceMarker(_ line: String) -> (character: Character, count: Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        if first == "`", line.dropFirst(count).contains("`") { return nil }
        return (first, count)
    }

    private static func isClosingFence(_ line: String, marker: Character, count: Int) -> Bool {
        let length = line.prefix { $0 == marker }.count
        guard length >= count else { return false }
        return line.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " || rest.isEmpty else { return nil }
        var text = String(rest).trimmingCharacters(in: .whitespaces)
        // ATX closing sequence.
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes.count, text.trimmingCharacters(in: .whitespaces))
    }

    private static func tableDelimiter(_ line: String) -> [CompatTableAlignment]? {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [CompatTableAlignment] = []
        for cell in cells {
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("-") else { return nil }
            let body = trimmed.filter { $0 != ":" }
            guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return nil }
            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") {
                alignments.append(.center)
            } else if trimmed.hasSuffix(":") {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }

    private static func tableCells(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func standaloneImage(_ line: String) -> (url: String, alt: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")") else { return nil }
        guard let close = line.range(of: "](") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
        let url = String(line[close.upperBound...].dropLast())
        guard !url.isEmpty, !url.contains(" ") else { return nil }
        return (url, alt)
    }

    private enum ListKind: Equatable {
        case bullet
        case numbered(String)
    }

    private static func listItem(_ raw: String) -> (kind: ListKind, depth: Int, text: String)? {
        let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
        let depth = min(3, indent / 2)
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let first = line.first else { return nil }

        if "-*+".contains(first) {
            let rest = line.dropFirst()
            guard let separator = rest.first, separator == " " || separator == "\t" else { return nil }
            return (.bullet, depth, String(rest).trimmingCharacters(in: .whitespaces))
        }

        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        let after = rest.dropFirst()
        guard let separator = after.first, separator == " " || separator == "\t" else { return nil }
        return (.numbered(String(digits)), depth, String(after).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Inline

    /// Resolves emphasis, code spans, links and strikethrough into an attributed
    /// string. `base` is reused so a whole block shares one font.
    static func inline(
        _ text: String,
        font: UIFont,
        codeFont: UIFont,
        color: UIColor,
        secondaryColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        applyInlineAttributes(
            result,
            range: NSRange(location: 0, length: result.length),
            font: font,
            codeFont: codeFont,
            color: color,
            secondaryColor: secondaryColor
        )
        return result
    }

    private struct Span {
        let pattern: String
        let options: NSRegularExpression.Options
        let apply: (NSMutableAttributedString, NSRange, Attributes) -> Void
    }

    private struct Attributes {
        let font: UIFont
        let codeFont: UIFont
        let color: UIColor
        let secondaryColor: UIColor
    }

    private static func applyInlineAttributes(
        _ text: NSMutableAttributedString,
        range: NSRange,
        font: UIFont,
        codeFont: UIFont,
        color: UIColor,
        secondaryColor: UIColor
    ) {
        let attributes = Attributes(font: font, codeFont: codeFont, color: color, secondaryColor: secondaryColor)

        // Code spans win over emphasis, so resolve them first and mark the range
        // with a sentinel colour that later passes skip.
        applyCodeSpans(text, range: range, attributes: attributes)

        for span in emphasisSpans {
            guard let expression = try? NSRegularExpression(pattern: span.pattern, options: span.options) else { continue }
            let matches = expression.matches(in: text.string, options: [], range: range)
            // Apply back to front so earlier ranges keep their locations.
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3 else { continue }
                let inner = match.range(at: 1)
                guard inner.location != NSNotFound, !isInsideCode(text, at: inner.location) else { continue }
                let full = match.range
                text.replaceCharacters(in: full, with: text.attributedSubstring(from: inner))
                span.apply(text, inner, attributes)
            }
        }

        applyLinks(text, range: NSRange(location: 0, length: text.length), attributes: attributes)
    }

    private static let emphasisSpans: [Span] = [
        Span(pattern: #"\*\*(.+?)\*\*"#, options: [.dotMatchesLineSeparators]) { text, range, attributes in
            let descriptor = attributes.font.fontDescriptor.withSymbolicTraits(.traitBold) ?? attributes.font.fontDescriptor
            text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: attributes.font.pointSize), range: range)
        },
        Span(pattern: #"__(.+?)__"#, options: [.dotMatchesLineSeparators]) { text, range, attributes in
            let descriptor = attributes.font.fontDescriptor.withSymbolicTraits(.traitBold) ?? attributes.font.fontDescriptor
            text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: attributes.font.pointSize), range: range)
        },
        Span(pattern: #"(?<![\*\w])\*(?!\*)(.+?)(?<!\*)\*(?![\*\w])"#, options: [.dotMatchesLineSeparators]) { text, range, attributes in
            let descriptor = attributes.font.fontDescriptor.withSymbolicTraits(.traitItalic) ?? attributes.font.fontDescriptor
            text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: attributes.font.pointSize), range: range)
        },
        Span(pattern: #"~~(.+?)~~"#, options: [.dotMatchesLineSeparators]) { text, range, _ in
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        },
    ]

    private static func applyCodeSpans(_ text: NSMutableAttributedString, range: NSRange, attributes: Attributes) {
        guard let expression = try? NSRegularExpression(pattern: #"`([^`\n]+)`"#, options: []) else { return }
        let matches = expression.matches(in: text.string, options: [], range: range)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let inner = match.range(at: 1)
            guard inner.location != NSNotFound else { continue }
            text.replaceCharacters(in: match.range, with: text.attributedSubstring(from: inner))
            text.addAttributes([
                .font: attributes.codeFont,
                .backgroundColor: attributes.secondaryColor,
                .markedClauseSegment: 1,
            ], range: inner)
        }
    }

    private static func isInsideCode(_ text: NSMutableAttributedString, at location: Int) -> Bool {
        guard location < text.length else { return false }
        return text.attribute(.markedClauseSegment, at: location, effectiveRange: nil) != nil
    }

    private static func applyLinks(_ text: NSMutableAttributedString, range: NSRange, attributes: Attributes) {
        guard let expression = try? NSRegularExpression(
            pattern: #"\[([^\]\n]+)\]\(([^)\s]+)\)"#, options: []
        ) else { return }
        let matches = expression.matches(in: text.string, options: [], range: range)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let label = match.range(at: 1)
            let destination = (text.string as NSString).substring(with: match.range(at: 2))
            guard label.location != NSNotFound, let url = URL(string: destination) else { continue }
            text.replaceCharacters(in: match.range, with: text.attributedSubstring(from: label))
            text.addAttributes([
                .link: url,
                .foregroundColor: UIColor.link,
            ], range: label)
        }
        _ = attributes
    }
}
