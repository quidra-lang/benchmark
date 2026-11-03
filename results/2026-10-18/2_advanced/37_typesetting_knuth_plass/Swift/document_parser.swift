import Foundation

enum BlockKind: String {
    case paragraph, title, author, h1, h2, item, `enum`, quote, term
    case table, verbatim, toc, lot, index, bibliography

    var isBody: Bool { [.paragraph, .item, .enum, .quote, .term].contains(self) }
}

struct SourceLine {
    let number: Int
    let text: String
}

struct DocumentWarning {
    let line: Int
    let message: String
}

enum InlineToken {
    case text(String), reference(String), page(String), citation(String), footnote(Int), index(Int)
}

final class Block {
    let kind: BlockKind
    let lineNumber: Int
    let argument: String
    let width: Int
    var indent: Int
    let alignment: String
    var pageBreak: Bool
    var bodyLines: [SourceLine] = []
    var innerLines: [SourceLine] = []
    var term = ""
    var columns = ""
    var caption = ""
    var id = 0
    var label: String?
    var text = ""
    var number = ""
    var paragraphNumber = 0
    var tableLines: [String] = []
    var tokens: [InlineToken] = []

    init(kind: BlockKind, line: Int, argument: String, width: Int, indent: Int,
         alignment: String, pageBreak: Bool) {
        self.kind = kind
        lineNumber = line
        self.argument = argument
        self.width = width
        self.indent = indent
        self.alignment = alignment
        self.pageBreak = pageBreak
    }
}

final class BibliographyEntry {
    let lineNumber: Int
    let key: String
    let author: String
    let year: String
    let title: String
    var cited = false
    var baseLabel = ""
    var label = ""

    init(line: Int, key: String, author: String, year: String, title: String) {
        lineNumber = line
        self.key = key
        self.author = author
        self.year = year
        self.title = title
    }
}

final class Document {
    var blocks: [Block] = []
    var warnings: [DocumentWarning] = []
    var height = 40
    var pageWidth = 60
    var header = ["", "", ""]
    var footer = ["", "", ""]
    var hyphenationWords: [String] = []
    var bibliography: [BibliographyEntry] = []
}

func partition(_ text: String, at separator: Character) -> (String, String, Bool) {
    guard let position = text.firstIndex(of: separator) else { return (text, "", false) }
    return (String(text[..<position]), String(text[text.index(after: position)...]), true)
}

func asciiDigit(_ character: Character) -> Bool { character >= "0" && character <= "9" }
func lowercaseLetter(_ character: Character) -> Bool { character >= "a" && character <= "z" }

func validDictionaryWord(_ text: String) -> Bool {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    return !text.isEmpty && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(lowercaseLetter) }
}

func validArgument(_ name: String, _ argument: String) -> Bool {
    if name == "width" || name == "indent" || name == "page" {
        guard (1...9).contains(argument.count), argument.allSatisfy(asciiDigit), let value = Int(argument) else {
            return false
        }
        switch name {
        case "width": return (20...80).contains(value)
        case "indent": return (0...8).contains(value)
        default: return (10...100).contains(value)
        }
    }
    if name == "align" { return ["left", "right", "center", "justify"].contains(argument) }
    if name == "header" || name == "footer" { return argument.filter { $0 == "|" }.count == 2 }
    if ["newpage", "verbatim", "toc", "lot", "index", "bibliography"].contains(name) { return argument.isEmpty }
    if name == "hyphenation" { return argument.components(separatedBy: " ").allSatisfy(validDictionaryWord) }
    if name == "bib" {
        let (key, fields, separated) = partition(argument, at: " ")
        let parts = fields.components(separatedBy: "|")
        return separated && !key.isEmpty && key.allSatisfy { lowercaseLetter($0) || asciiDigit($0) }
            && parts.count == 3 && !parts[0].isEmpty && !parts[2].isEmpty
            && parts[1].count == 4 && parts[1].allSatisfy(asciiDigit)
    }
    if name == "term" {
        let (term, description, separated) = partition(argument, at: "|")
        return separated && !term.isEmpty && !description.isEmpty
    }
    if name == "table" {
        let columns = partition(argument, at: " ").0
        return !columns.isEmpty && columns.allSatisfy { "lrc".contains($0) }
    }
    return !argument.isEmpty
}

func parseDocument(_ lines: [String]) -> Document {
    let document = Document()
    let settings: Set<String> = ["width", "indent", "align"]
    let preamble: Set<String> = ["page", "header", "footer"]
    let others: Set<String> = ["newpage", "hyphenation", "bib"]
    var width = 60
    var indent = 0
    var alignment = "left"
    var accepted: Set<String> = []
    var openBody: Block?
    var innerBlock: Block?
    var pendingPageBreak = false

    func createBlock(_ kind: BlockKind, _ number: Int, _ argument: String = "") -> Block {
        if document.blocks.isEmpty { document.pageWidth = width }
        let block = Block(kind: kind, line: number, argument: argument, width: width, indent: indent,
                          alignment: alignment, pageBreak: pendingPageBreak)
        pendingPageBreak = false
        document.blocks.append(block)
        return block
    }

    for (index, line) in lines.enumerated() {
        let number = index + 1
        if let block = innerBlock {
            if line == ".end" { innerBlock = nil }
            else { block.innerLines.append(SourceLine(number: number, text: line)) }
            continue
        }
        if line.isEmpty {
            openBody = nil
            continue
        }
        if !line.hasPrefix(".") {
            if openBody == nil { openBody = createBlock(.paragraph, number) }
            openBody!.bodyLines.append(SourceLine(number: number, text: line))
            continue
        }
        openBody = nil
        let (name, argument, _) = partition(String(line.dropFirst()), at: " ")
        let kind = BlockKind(rawValue: name)
        var warning: String?
        if !(settings.contains(name) || preamble.contains(name) || others.contains(name)
             || (kind != nil && kind != .paragraph)) {
            warning = "unknown directive .\(name)"
        } else if !validArgument(name, argument) {
            warning = "bad argument for .\(name)"
        } else if preamble.contains(name) && !document.blocks.isEmpty {
            warning = ".\(name) ignored after the preamble"
        } else if preamble.contains(name) && accepted.contains(name) {
            warning = "duplicate .\(name)"
        }
        if let warning {
            document.warnings.append(DocumentWarning(line: number, message: warning))
            continue
        }
        switch name {
        case "width": width = Int(argument)!
        case "indent": indent = Int(argument)!
        case "align": alignment = argument
        case "page", "header", "footer":
            accepted.insert(name)
            if name == "page" { document.height = Int(argument)! }
            else if name == "header" { document.header = argument.components(separatedBy: "|") }
            else { document.footer = argument.components(separatedBy: "|") }
        case "newpage": pendingPageBreak = true
        case "hyphenation": document.hyphenationWords += argument.components(separatedBy: " ")
        case "bib":
            let (key, fields, _) = partition(argument, at: " ")
            let parts = fields.components(separatedBy: "|")
            document.bibliography.append(BibliographyEntry(line: number, key: key, author: parts[0],
                                                           year: parts[1], title: parts[2]))
        default:
            let block = createBlock(kind!, number, argument)
            switch block.kind {
            case .item, .enum, .quote:
                block.bodyLines.append(SourceLine(number: number, text: argument))
                openBody = block
            case .term:
                let (term, description, _) = partition(argument, at: "|")
                block.term = term
                block.bodyLines.append(SourceLine(number: number, text: description))
                openBody = block
            case .table:
                let (columns, caption, _) = partition(argument, at: " ")
                block.columns = columns
                block.caption = caption
                innerBlock = block
            case .verbatim: innerBlock = block
            default: break
            }
        }
    }
    if let block = innerBlock {
        document.warnings.append(DocumentWarning(line: block.lineNumber,
                                                 message: "unterminated \(block.kind.rawValue)"))
    }
    return document
}
