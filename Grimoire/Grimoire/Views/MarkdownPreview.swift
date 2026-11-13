import SwiftUI

enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case numbered(String, String)
    case task(Bool, String)
    case quote(String)
    case code(String)
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var inCode = false
        var codeLines: [String] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        for line in normalized.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            if t.isEmpty { continue }

            if t == "---" || t == "***" || t == "___" {
                blocks.append(.rule)
                continue
            }

            if t.hasPrefix("#") {
                var level = 0
                for ch in t {
                    if ch == "#" { level += 1 } else { break }
                }
                let rest = String(t.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level <= 6 && !rest.isEmpty {
                    blocks.append(.heading(level, rest))
                    continue
                }
            }

            if t.hasPrefix("- [ ] ") || t.hasPrefix("* [ ] ") {
                blocks.append(.task(false, String(t.dropFirst(6))))
                continue
            }
            if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") || t.hasPrefix("* [x] ") || t.hasPrefix("* [X] ") {
                blocks.append(.task(true, String(t.dropFirst(6))))
                continue
            }
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                blocks.append(.bullet(String(t.dropFirst(2))))
                continue
            }
            if t.hasPrefix(">") {
                blocks.append(.quote(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let dot = t.firstIndex(of: "."), dot != t.startIndex {
                let numberPart = String(t[t.startIndex..<dot])
                let afterDot = t.index(after: dot)
                if !numberPart.isEmpty,
                   numberPart.allSatisfy({ $0.isNumber }),
                   afterDot < t.endIndex,
                   t[afterDot] == " " {
                    let rest = String(t[afterDot...]).trimmingCharacters(in: .whitespaces)
                    blocks.append(.numbered(numberPart, rest))
                    continue
                }
            }

            blocks.append(.paragraph(t))
        }

        if inCode {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        return blocks
    }
}

struct MarkdownPreview: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("Nothing inscribed yet.")
                    .font(GrimoireTheme.body(16))
                    .foregroundStyle(GrimoireTheme.muted)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { entry in
                blockView(entry.element)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(GrimoireTheme.crimsonBright)
    }

    private func inline(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return Text(attributed)
        }
        return Text(source)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 23
        case 3: return 20
        default: return 18
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            VStack(alignment: .leading, spacing: 2) {
                inline(content)
                    .font(GrimoireTheme.title(headingSize(level)))
                    .foregroundStyle(level <= 2 ? GrimoireTheme.crimsonBright : GrimoireTheme.bone)
                if level == 1 {
                    OrnamentDivider()
                }
            }
            .padding(.top, 6)
        case .paragraph(let content):
            inline(content)
                .font(GrimoireTheme.body(17))
                .foregroundStyle(GrimoireTheme.bone)
        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("✦")
                    .font(.system(size: 11))
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                inline(content)
                    .font(GrimoireTheme.body(17))
                    .foregroundStyle(GrimoireTheme.bone)
            }
        case .numbered(let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number + ".")
                    .font(GrimoireTheme.title(16))
                    .foregroundStyle(GrimoireTheme.crimsonBright)
                inline(content)
                    .font(GrimoireTheme.body(17))
                    .foregroundStyle(GrimoireTheme.bone)
            }
        case .task(let done, let content):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? GrimoireTheme.crimsonBright : GrimoireTheme.muted)
                inline(content)
                    .font(GrimoireTheme.body(17))
                    .foregroundStyle(done ? GrimoireTheme.muted : GrimoireTheme.bone)
                    .strikethrough(done)
            }
        case .quote(let content):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(GrimoireTheme.crimson)
                    .frame(width: 3)
                inline(content)
                    .font(Font.system(size: 17, design: .serif).italic())
                    .foregroundStyle(GrimoireTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let content):
            Text(content)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(GrimoireTheme.bone)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GrimoireTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GrimoireTheme.crimson.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case .rule:
            OrnamentDivider()
        }
    }
}
