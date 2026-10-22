import SwiftUI

/// The block-level Markdown Claude writes in hints and reports: headings,
/// bullet and numbered lists, paragraphs. Inline styling (bold, italics,
/// code, links) is left to AttributedString.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(marker: String, text: String, depth: Int)
    case paragraph(String)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if let match = line.wholeMatch(of: /(#{1,6})\s+(.+)/) {
                flushParagraph()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
            } else if let match = line.wholeMatch(of: /[-*•]\s+(.+)/) {
                flushParagraph()
                blocks.append(.bullet(marker: "•", text: String(match.1), depth: indent / 2))
            } else if let match = line.wholeMatch(of: /(\d+[.)])\s+(.+)/) {
                flushParagraph()
                blocks.append(.bullet(marker: String(match.1), text: String(match.2), depth: indent / 2))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

struct MarkdownText: View {
    let markdown: String
    var style: Font.TextStyle = .body
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { index, block in
                switch block {
                case .heading(let level, let text) where level <= 2:
                    Text(Self.inline(text))
                        .font(.scaled(level == 1 ? .title2 : .title3, scale, weight: .bold))
                        .padding(.top, index == 0 ? 0 : 12 * scale)
                case .heading(_, let text):
                    // Section labels ("### What it is" in full answers, one
                    // per question in reports): body-sized, tinted, spaced
                    // apart so each section reads as its own chunk.
                    Text(Self.inline(text))
                        .font(.scaled(style, scale, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, index == 0 ? 0 : 10 * scale)
                case .bullet(let marker, let text, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).foregroundStyle(.secondary)
                        Text(Self.inline(text))
                    }
                    .padding(.leading, CGFloat(depth) * 14 * scale)
                case .paragraph(let text):
                    Text(Self.inline(text))
                }
            }
        }
        .font(.scaled(style, scale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
