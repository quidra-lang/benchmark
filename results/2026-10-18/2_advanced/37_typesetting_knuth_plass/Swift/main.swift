import Foundation

struct TextPosition {
    let word: Int
    let offset: Int
}

struct BreakPosition {
    let start: TextPosition
    let end: TextPosition
    let midword: Bool
    let appendHyphen: Bool
}

struct PieceRange {
    let word: Int
    let first: Int
    let last: Int
}

struct MeasuredLine {
    let pieces: [String]
    let ranges: [PieceRange]
    let slack: Int
    let last: Bool
    let midword: Bool
}

struct TextMetrics {
    let words: [[Character]]
    let firstCapacity: Int
    let laterCapacity: Int
    let offsets: [Int]
    let breaks: [BreakPosition]
    var end: Int { breaks.count - 1 }

    init(_ words: [String], _ firstCapacity: Int, _ laterCapacity: Int, _ dictionary: Hyphenation) {
        self.words = words.map(Array.init)
        self.firstCapacity = firstCapacity
        self.laterCapacity = laterCapacity
        var offsets: [Int] = []
        var breaks = [BreakPosition(start: TextPosition(word: 0, offset: 0),
                                    end: TextPosition(word: 0, offset: 0), midword: false, appendHyphen: false)]
        var offset = 0
        for (index, word) in words.enumerated() {
            offsets.append(offset)
            offset += word.count + 1
            for split in dictionary.splitPoints(word) {
                let position = TextPosition(word: index, offset: split.position)
                breaks.append(BreakPosition(start: position, end: position, midword: true,
                                            appendHyphen: split.appendHyphen))
            }
            breaks.append(BreakPosition(start: TextPosition(word: index + 1, offset: 0),
                                        end: TextPosition(word: index, offset: word.count),
                                        midword: false, appendHyphen: false))
        }
        self.offsets = offsets
        self.breaks = breaks
    }

    func capacity(_ start: Int) -> Int { start == 0 ? firstCapacity : laterCapacity }

    func length(_ start: Int, _ end: Int) -> Int {
        let first = breaks[start].start
        let last = breaks[end].end
        return offsets[last.word] + last.offset - offsets[first.word] - first.offset
            + (breaks[end].appendHyphen ? 1 : 0)
    }

    func slack(_ start: Int, _ end: Int) -> Int { capacity(start) - length(start, end) }

    func measure(_ start: Int, _ end: Int) -> MeasuredLine {
        let first = breaks[start].start
        let last = breaks[end].end
        var pieces: [String] = []
        var ranges: [PieceRange] = []
        for word in first.word...last.word {
            let lower = word == first.word ? first.offset : 0
            let upper = word == last.word ? last.offset : words[word].count
            pieces.append(String(words[word][lower..<upper]))
            ranges.append(PieceRange(word: word, first: lower, last: upper))
        }
        if breaks[end].appendHyphen { pieces[pieces.count - 1] += "-" }
        return MeasuredLine(pieces: pieces, ranges: ranges, slack: slack(start, end),
                            last: end == self.end, midword: breaks[end].midword)
    }
}

enum MarkKind {
    case footnote, index
}

struct WordMark {
    let kind: MarkKind
    let number: Int
    let offset: Int
}

final class LayoutLine {
    var text: String
    var footnotes: [Int] = []
    var indexes: [Int] = []
    var anchor: Int?
    var chapterStart = false

    init(_ text: String) { self.text = text }
}

struct TextLayout {
    var lines: [LayoutLine]
    let broken: [MeasuredLine]
    let cost: Int
}

final class Page {
    let content: [LayoutLine]
    let footnotes: [Int]
    let height: Int
    let endsByForce: Bool
    var blank = false
    var chapterStart = false
    var serial = 0
    var bodyNumber = 0
    var display = ""
    var header = ""
    var footer = ""
    var body: [String] = []

    init(content: [LayoutLine], footnotes: [Int], height: Int, endsByForce: Bool) {
        self.content = content
        self.footnotes = footnotes
        self.height = height
        self.endsByForce = endsByForce
    }
}

final class IndexEntry {
    let name: String
    var marks: [Int] = []
    var references: Set<String> = []
    var children: [String: IndexEntry] = [:]

    init(_ name: String) { self.name = name }
}

struct WarningText {
    let name: String
    let layout: TextLayout
    let justify: Bool
}

struct GeneratedLines {
    let source: Block
    let lines: [LayoutLine]
}

final class LayoutResult {
    let method: BreakingMethod
    var bodies: [Int: TextLayout] = [:]
    var footnotes: [Int: TextLayout] = [:]
    var warningTexts: [WarningText] = []
    var generated: [GeneratedLines] = []
    var pages: [Page] = []
    var frontMatter = 0
    var blockPages: [Int: Page] = [:]
    var markPages: [Int: Int] = [:]
    var labelValues: [String: String] = [:]

    init(_ method: BreakingMethod) { self.method = method }
}

func splitLabel(_ text: String) -> (String, String?) {
    if text.hasSuffix("}"), let range = text.range(of: " {#", options: .backwards) {
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...].dropLast()))
    }
    return (text, nil)
}

func wordsIn(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }

func nameOrder(_ first: String, _ second: String) -> Bool {
    let a = first.lowercased()
    let b = second.lowercased()
    return a == b ? first < second : a < b
}

final class Typesetter {
    let document: Document
    let parameters: [String: Int]
    let dictionary: Hyphenation
    var labels: [String: Block] = [:]
    var bibliography: [String: BibliographyEntry] = [:]
    var bibliographyOrder: [BibliographyEntry] = []
    var citedEntries: [BibliographyEntry] = []
    var bodyBlocks: [Block] = []
    var headings: [Block] = []
    var numberedTables: [Block] = []
    var footnotes: [String] = []
    var indexMarks: [String] = []
    var indexEntries: [String: IndexEntry] = [:]
    var warnings: [DocumentWarning]

    init(_ document: Document, _ parameters: [String: Int], _ dictionaryLines: [String]) {
        self.document = document
        self.parameters = parameters
        warnings = document.warnings
        dictionary = Hyphenation(lines: dictionaryLines, additions: document.hyphenationWords,
                                  leftMinimum: parameters["left_min"]!, rightMinimum: parameters["right_min"]!)
        registerDocument()
        checkDocument()
        assignBibliographyLabels()
        prepareIndex()
        warnings = warnings.enumerated().sorted {
            $0.element.line == $1.element.line ? $0.offset < $1.offset : $0.element.line < $1.element.line
        }.map { $0.element }
    }

    func warn(_ line: Int, _ message: String) { warnings.append(DocumentWarning(line: line, message: message)) }

    func registerDocument() {
        var chapter = 0
        var section = 0
        var table = 0
        var previous: Block?
        for (index, block) in document.blocks.enumerated() {
            block.id = index
            switch block.kind {
            case .h1, .h2:
                (block.text, block.label) = splitLabel(block.argument)
                if block.kind == .h1 {
                    chapter += 1
                    section = 0
                    block.number = String(chapter)
                    if index > 0 { block.pageBreak = true }
                } else {
                    section += 1
                    block.number = "\(chapter).\(section)"
                }
                headings.append(block)
            case .enum:
                block.number = String(previous?.kind == .enum ? Int(previous!.number)! + 1 : 1)
            case .table:
                (block.caption, block.label) = splitLabel(block.caption)
                if !block.caption.isEmpty {
                    table += 1
                    block.number = String(table)
                    numberedTables.append(block)
                }
            default: break
            }
            if let label = block.label {
                if labels[label] != nil {
                    warn(block.lineNumber, "duplicate label \(label)")
                    block.label = nil
                } else { labels[label] = block }
            }
            if block.kind == .paragraph && (previous?.kind == .h1 || previous?.kind == .h2) { block.indent = 0 }
            if block.kind.isBody {
                bodyBlocks.append(block)
                block.paragraphNumber = bodyBlocks.count
            }
            previous = block
        }
        for entry in document.bibliography {
            if bibliography[entry.key] != nil { warn(entry.lineNumber, "duplicate bibliography key \(entry.key)") }
            else {
                bibliography[entry.key] = entry
                bibliographyOrder.append(entry)
            }
        }
    }

    func checkTable(_ block: Block) {
        let count = block.columns.count
        var rows: [[String]] = []
        for line in block.innerLines {
            var cells = line.text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count != count {
                warn(line.number, "table row has \(cells.count) cells, expected \(count)")
                cells += Array(repeating: "", count: max(0, count - cells.count))
                cells = Array(cells.prefix(count))
            }
            rows.append(cells)
        }
        block.tableLines = formatTable(rows, block.columns, block.caption, block.number)
        let excess = block.tableLines.map { $0.count }.max()! - block.width
        if excess > 0 { warn(block.lineNumber, "table too wide by \(excess)") }
    }

    func acceptCommand(_ name: String, _ argument: String, _ line: Int) -> InlineToken {
        switch name {
        case "ref", "page":
            if labels[argument] == nil { warn(line, "undefined label \(argument)") }
            return name == "ref" ? .reference(argument) : .page(argument)
        case "cite":
            for key in argument.components(separatedBy: ",") {
                if let entry = bibliography[key] { entry.cited = true }
                else { warn(line, "undefined citation \(key)") }
            }
            return .citation(argument)
        case "fn":
            footnotes.append(argument)
            return .footnote(footnotes.count)
        default:
            indexMarks.append(argument)
            return .index(indexMarks.count)
        }
    }

    func parseBodyLine(_ text: String, _ line: Int) -> [InlineToken] {
        let characters = Array(text)
        var tokens: [InlineToken] = []
        var position = 0
        while position < characters.count {
            guard let opening = characters[position...].firstIndex(of: "{") else {
                tokens.append(.text(String(characters[position...])))
                break
            }
            if opening > position { tokens.append(.text(String(characters[position..<opening]))) }
            guard let closing = characters[(opening + 1)...].firstIndex(of: "}") else {
                warn(line, "unclosed brace")
                tokens.append(.text(String(characters[opening...])))
                break
            }
            let content = String(characters[(opening + 1)..<closing])
            let (name, argument, separated) = partition(content, at: ":")
            if ["ref", "page", "fn", "idx", "cite"].contains(name) && separated && !argument.isEmpty {
                tokens.append(acceptCommand(name, argument, line))
            } else { warn(line, "bad command {\(content)}") }
            position = closing + 1
        }
        return tokens
    }

    func checkDocument() {
        for block in document.blocks {
            if block.kind == .table { checkTable(block) }
            else if block.kind == .verbatim {
                for line in block.innerLines where line.text.count > block.width {
                    warn(line.number, "verbatim line too long by \(line.text.count - block.width)")
                }
            } else if block.kind.isBody {
                for (index, line) in block.bodyLines.enumerated() {
                    if index > 0 { block.tokens.append(.text(" ")) }
                    block.tokens += parseBodyLine(line.text, line.number)
                }
            }
        }
        for entry in bibliographyOrder where !entry.cited { warn(entry.lineNumber, "unused bibliography entry \(entry.key)") }
    }

    func assignBibliographyLabels() {
        for entry in bibliographyOrder where entry.cited {
            let surnames = entry.author.components(separatedBy: " and ")
            let base: String
            if surnames.count == 1 { base = String(surnames[0].prefix(3)) }
            else if surnames.count <= 4 { base = surnames.map { String($0.prefix(1)) }.joined() }
            else { base = surnames.prefix(3).map { String($0.prefix(1)) }.joined() + "+" }
            entry.baseLabel = base + String(entry.year.suffix(2))
            citedEntries.append(entry)
        }
        citedEntries.sort {
            let first = [$0.baseLabel, $0.author, $0.title, $0.key]
            let second = [$1.baseLabel, $1.author, $1.title, $1.key]
            return first.lexicographicallyPrecedes(second)
        }
        let groups = Dictionary(grouping: citedEntries, by: { $0.baseLabel })
        for entry in citedEntries {
            let group = groups[entry.baseLabel]!
            let position = group.firstIndex { $0 === entry }!
            entry.label = entry.baseLabel + (group.count > 1 ? String(UnicodeScalar(97 + position)!) : "")
        }
    }

    func prepareIndex() {
        for (index, phrase) in indexMarks.enumerated() {
            let (entryPart, reference, hasReference) = partition(phrase, at: "|")
            let (parentName, childName, hasChild) = partition(entryPart, at: "!")
            let parent = indexEntries[parentName] ?? IndexEntry(parentName)
            indexEntries[parentName] = parent
            let entry: IndexEntry
            if hasChild {
                entry = parent.children[childName] ?? IndexEntry(childName)
                parent.children[childName] = entry
            } else { entry = parent }
            if hasReference { entry.references.insert(reference) }
            else { entry.marks.append(index + 1) }
        }
    }

    func citationText(_ argument: String) -> String {
        var labels: Set<String> = []
        var undefined = false
        for key in argument.components(separatedBy: ",") {
            if let entry = bibliography[key] { labels.insert(entry.label) }
            else { undefined = true }
        }
        var parts = labels.sorted()
        if undefined { parts.append("?") }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    func expandBody(_ block: Block, _ pageValues: [String: String]) -> (words: [String], marks: [Int: [WordMark]]) {
        var expanded: [Character] = []
        var marks: [(offset: Int, kind: MarkKind, number: Int)] = []
        for token in block.tokens {
            let text: String
            switch token {
            case .text(let value): text = value
            case .index(let number):
                marks.append((expanded.count - 1, .index, number))
                continue
            case .footnote(let number):
                marks.append((expanded.count, .footnote, number))
                text = "[\(number)]"
            case .reference(let label): text = labels[label]?.number ?? "??"
            case .page(let label): text = pageValues[label] ?? "??"
            case .citation(let argument): text = citationText(argument)
            }
            expanded += Array(text)
        }
        var starts: [Int] = []
        var words: [String] = []
        var position = 0
        while position < expanded.count {
            if expanded[position] == " " { position += 1; continue }
            let start = position
            while position < expanded.count && expanded[position] != " " { position += 1 }
            starts.append(start)
            words.append(String(expanded[start..<position]))
        }
        var wordMarks: [Int: [WordMark]] = [:]
        for mark in marks {
            var low = 0
            var high = starts.count
            while low < high {
                let middle = (low + high) / 2
                if starts[middle] <= mark.offset { low = middle + 1 } else { high = middle }
            }
            let word = low - 1
            wordMarks[word, default: []].append(WordMark(kind: mark.kind, number: mark.number,
                                                       offset: mark.offset - starts[word]))
        }
        return (words, wordMarks)
    }

    func layOutText(_ words: [String], capacities: (Int, Int), alignment: String,
                    prefixes: (String, String), method: BreakingMethod,
                    marks: [Int: [WordMark]] = [:]) -> TextLayout {
        let metrics = TextMetrics(words, capacities.0, capacities.1, dictionary)
        let breaking = breakText(metrics, method, parameters)
        var lines: [LayoutLine] = []
        var measuredLines: [MeasuredLine] = []
        var start = 0
        for (index, end) in breaking.positions.enumerated() {
            let measured = metrics.measure(start, end)
            let text = displayLine(measured.pieces, measured.slack, alignment, last: measured.last)
            let line = LayoutLine((index == 0 ? prefixes.0 : prefixes.1) + text)
            for range in measured.ranges {
                for mark in marks[range.word, default: []] where range.first <= mark.offset && mark.offset < range.last {
                    if mark.kind == .footnote { line.footnotes.append(mark.number) }
                    else { line.indexes.append(mark.number) }
                }
            }
            lines.append(line)
            measuredLines.append(measured)
            start = end
        }
        return TextLayout(lines: lines, broken: measuredLines, cost: breaking.cost)
    }

    func layOutBody(_ block: Block, _ pageValues: [String: String], _ method: BreakingMethod) -> TextLayout {
        let expanded = expandBody(block, pageValues)
        let capacities: (Int, Int)
        let prefixes: (String, String)
        switch block.kind {
        case .paragraph:
            capacities = (block.width - block.indent, block.width)
            prefixes = (spaces(block.indent), "")
        case .item:
            capacities = (block.width - 2, block.width - 2)
            prefixes = ("- ", "  ")
        case .enum:
            capacities = (block.width - 4, block.width - 4)
            prefixes = (spaces(max(0, 2 - block.number.count)) + block.number + ". ", spaces(4))
        case .quote:
            capacities = (block.width - 8, block.width - 8)
            prefixes = (spaces(4), spaces(4))
        default:
            capacities = (block.width - 12, block.width - 12)
            prefixes = (block.term.count <= 10 ? block.term + spaces(12 - block.term.count) : spaces(12), spaces(12))
        }
        var result = layOutText(expanded.words, capacities: capacities, alignment: block.alignment,
                                prefixes: prefixes, method: method, marks: expanded.marks)
        if block.kind == .term && block.term.count >= 11 { result.lines.insert(LayoutLine(block.term), at: 0) }
        return result
    }

    func layOutFootnotes(_ method: BreakingMethod) -> [Int: TextLayout] {
        var result: [Int: TextLayout] = [:]
        for (index, text) in footnotes.enumerated() {
            let prefix = "[\(index + 1)] "
            let capacity = document.pageWidth - prefix.count
            result[index + 1] = layOutText(wordsIn(text), capacities: (capacity, capacity), alignment: "left",
                                          prefixes: (prefix, spaces(prefix.count)), method: method)
        }
        return result
    }

    func layOutReference(_ entry: BibliographyEntry, _ width: Int, _ method: BreakingMethod) -> TextLayout {
        let margin = citedEntries.map { $0.label.count }.max()! + 3
        let text = "\(entry.author). \(entry.year). \(entry.title)"
        let capacity = width - margin
        let prefix = "[\(entry.label)]"
        return layOutText(wordsIn(text), capacities: (capacity, capacity), alignment: "left",
                          prefixes: (prefix + spaces(margin - prefix.count), spaces(margin)), method: method)
    }

    func pageList(_ numbers: [Int]) -> String {
        let numbers = Set(numbers).sorted()
        var parts: [String] = []
        var first = 0
        while first < numbers.count {
            var last = first
            while last + 1 < numbers.count && numbers[last + 1] == numbers[last] + 1 { last += 1 }
            if last - first >= 2 { parts.append("\(numbers[first])-\(numbers[last])") }
            else { parts += numbers[first...last].map(String.init) }
            first = last + 1
        }
        return parts.joined(separator: ", ")
    }

    func indexEntryLine(_ entry: IndexEntry, _ markPages: [Int: Int], child: Bool = false) -> String {
        var text = (child ? "  " : "") + entry.name
        let numbers = entry.marks.compactMap { markPages[$0] }
        if !numbers.isEmpty { text += ", " + pageList(numbers) }
        if !entry.references.isEmpty { text += ", see " + entry.references.sorted().joined(separator: ", ") }
        return text
    }

    func indexLines(_ markPages: [Int: Int]) -> [String] {
        var lines: [String] = []
        var previousGroup: String?
        for name in indexEntries.keys.sorted(by: nameOrder) {
            let parent = indexEntries[name]!
            let group = isLetter(name.first!) ? String(name.prefix(1)).uppercased() : "Symbols"
            if group != previousGroup {
                lines.append(group)
                previousGroup = group
            }
            lines.append(indexEntryLine(parent, markPages))
            for child in parent.children.keys.sorted(by: nameOrder) {
                lines.append(indexEntryLine(parent.children[child]!, markPages, child: true))
            }
        }
        return lines
    }

    func contentsLines(_ block: Block, _ blockPages: [Int: Page]) -> [String] {
        let entries = block.kind == .toc ? headings : numberedTables
        return entries.map { entry in
            let left: String
            if block.kind == .toc { left = (entry.kind == .h2 ? "  " : "") + entry.number + " " + entry.text }
            else { left = "Table \(entry.number). \(entry.caption)" }
            let number = blockPages[entry.id]?.display ?? "??"
            let dots = block.width - left.count - number.count - 2
            return left + " " + String(repeating: ".", count: dots) + " " + number
        }
    }

    func addLayoutBlock(_ layout: inout [LayoutBlock], source: Block, kind: LayoutKind,
                        lines: [LayoutLine], list: Bool = false, first: Bool = true) {
        if first {
            lines[0].anchor = source.id
            if source.kind == .h1 { lines[0].chapterStart = true }
        }
        layout.append(LayoutBlock(kind: kind, lines: lines, list: list, pageBreak: first && source.pageBreak))
    }

    func buildLayoutBlocks(_ pageValues: [String: String], _ result: LayoutResult) -> [LayoutBlock] {
        var layout: [LayoutBlock] = []
        for block in document.blocks {
            if block.kind.isBody {
                let body = layOutBody(block, pageValues, result.method)
                result.bodies[block.id] = body
                result.warningTexts.append(WarningText(name: "paragraph \(block.paragraphNumber)",
                                                       layout: body, justify: block.alignment == "justify"))
                addLayoutBlock(&layout, source: block, kind: .flow, lines: body.lines,
                               list: [.item, .enum, .term].contains(block.kind))
                continue
            }
            switch block.kind {
            case .title, .author:
                let text = block.kind == .title ? block.argument.uppercased() : block.argument
                addLayoutBlock(&layout, source: block, kind: .heading,
                               lines: [LayoutLine(spaces((block.width - text.count) / 2) + text)])
            case .h1, .h2:
                let text = block.number + " " + (block.kind == .h1 ? block.text.uppercased() : block.text)
                let rule = String(repeating: block.kind == .h1 ? "=" : "-", count: text.count)
                addLayoutBlock(&layout, source: block, kind: .heading, lines: [LayoutLine(text), LayoutLine(rule)])
            case .table:
                addLayoutBlock(&layout, source: block, kind: .solid, lines: block.tableLines.map(LayoutLine.init))
            case .verbatim:
                addLayoutBlock(&layout, source: block, kind: .flow, lines: block.innerLines.map { LayoutLine($0.text) })
            case .toc, .lot, .index:
                let title = block.kind == .toc ? "CONTENTS" : block.kind == .lot ? "TABLES" : "INDEX"
                addLayoutBlock(&layout, source: block, kind: .heading,
                               lines: [LayoutLine(title), LayoutLine(String(repeating: "=", count: title.count))])
                let entries = block.kind == .index ? indexLines([:]) : contentsLines(block, [:])
                let lines = entries.map(LayoutLine.init)
                addLayoutBlock(&layout, source: block, kind: .flow, lines: lines, first: false)
                result.generated.append(GeneratedLines(source: block, lines: lines))
            case .bibliography:
                addLayoutBlock(&layout, source: block, kind: .heading,
                               lines: [LayoutLine("REFERENCES"), LayoutLine("==========")])
                for entry in citedEntries {
                    let reference = layOutReference(entry, block.width, result.method)
                    result.warningTexts.append(WarningText(name: "reference \(entry.label)", layout: reference, justify: false))
                    addLayoutBlock(&layout, source: block, kind: .flow, lines: reference.lines, list: true, first: false)
                }
            default: break
            }
        }
        return layout
    }

    func roman(_ number: Int) -> String {
        String(repeating: "x", count: number / 10) + ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"][number % 10]
    }

    func numberPages(_ pages: [Page], _ result: LayoutResult) {
        var numbered: [Page] = []
        for page in pages {
            let chapterStart = page.content.first?.chapterStart ?? false
            var serial = numbered.count + 1
            if chapterStart && serial % 2 == 0 {
                let blank = Page(content: [], footnotes: [], height: 0, endsByForce: true)
                blank.serial = serial
                blank.blank = true
                numbered.append(blank)
                serial += 1
            }
            page.serial = serial
            page.chapterStart = chapterStart
            numbered.append(page)
        }
        var blockPages: [Int: Page] = [:]
        for page in numbered {
            for line in page.content {
                if let anchor = line.anchor { blockPages[anchor] = page }
            }
        }
        let frontMatter = headings.first.map { blockPages[$0.id]!.serial - 1 } ?? 0
        var markPages: [Int: Int] = [:]
        for page in numbered {
            page.bodyNumber = page.serial - frontMatter
            page.display = page.serial <= frontMatter ? roman(page.serial) : String(page.bodyNumber)
            for line in page.content {
                for mark in line.indexes { markPages[mark] = page.bodyNumber }
            }
        }
        result.pages = numbered
        result.frontMatter = frontMatter
        result.blockPages = blockPages
        result.markPages = markPages
        result.labelValues = labels.mapValues { blockPages[$0.id]!.display }
    }

    func layoutOnce(_ pageValues: [String: String], _ method: BreakingMethod) -> LayoutResult {
        let result = LayoutResult(method)
        result.footnotes = layOutFootnotes(method)
        let layout = buildLayoutBlocks(pageValues, result)
        let heights = result.footnotes.mapValues { $0.lines.count }
        let pages = choosePages(layout, heights, document.height,
                                parameters["orphan_lines"]!, parameters["widow_lines"]!)
        numberPages(pages, result)
        for number in result.footnotes.keys.sorted() {
            result.warningTexts.append(WarningText(name: "footnote \(number)", layout: result.footnotes[number]!, justify: false))
        }
        return result
    }

    func completeGeneratedLines(_ result: LayoutResult) {
        for generated in result.generated {
            let texts = generated.source.kind == .index ? indexLines(result.markPages)
                : contentsLines(generated.source, result.blockPages)
            for (line, text) in zip(generated.lines, texts) { line.text = text }
        }
    }

    func assemblePages(_ result: LayoutResult) {
        var chapter = ""
        var section = ""
        let height = document.height
        let total = result.pages.count - result.frontMatter
        for page in result.pages {
            if page.blank {
                page.body = Array(repeating: "", count: height)
                continue
            }
            for line in page.content {
                guard let anchor = line.anchor else { continue }
                let block = document.blocks[anchor]
                if block.kind == .h1 {
                    chapter = block.number + " " + block.text
                    section = ""
                } else if block.kind == .h2 { section = block.number + " " + block.text }
            }
            let values = [("page", page.display), ("pages", String(total)), ("chapter", chapter), ("section", section)]
            page.header = page.chapterStart ? "" : runningHead(document.header, values, document.pageWidth, page.serial)
            page.footer = runningHead(document.footer, values, document.pageWidth, page.serial)
            let content = page.content.map { $0.text }
            let noteLines = page.footnotes.flatMap { result.footnotes[$0]!.lines.map { $0.text } }
            if !noteLines.isEmpty {
                page.body = content + Array(repeating: "", count: height - content.count - noteLines.count - 1)
                    + ["----------"] + noteLines
            } else { page.body = content + Array(repeating: "", count: height - content.count) }
        }
    }

    func layout(_ method: BreakingMethod) -> LayoutResult {
        var pageValues = labels.mapValues { _ in "??" }
        while true {
            let result = layoutOnce(pageValues, method)
            if result.labelValues == pageValues {
                completeGeneratedLines(result)
                assemblePages(result)
                return result
            }
            pageValues = result.labelValues
        }
    }

    func layoutWarnings(_ result: LayoutResult) -> [String] {
        var warnings: [String] = []
        for text in result.warningTexts {
            for (index, line) in text.layout.broken.enumerated() {
                if line.slack < 0 { warnings.append("\(text.name) line \(index + 1): overfull by \(-line.slack)") }
                else if text.justify && !line.last && line.slack >= parameters["underfull_slack"]! {
                    warnings.append("\(text.name) line \(index + 1): underfull, slack \(line.slack)")
                }
            }
        }
        for page in result.pages where !page.blank && !page.endsByForce {
            let empty = document.height - page.height
            if empty >= parameters["underfull_page"]! { warnings.append("page \(page.serial): underfull, \(empty) empty lines") }
        }
        let hyphenated = result.bodies.values.reduce(0) { $0 + $1.broken.filter { $0.midword }.count }
        warnings.append("\(result.pages.count) pages, \(hyphenated) hyphenated lines")
        return warnings.map { result.method.rawValue + ": " + $0 }
    }

    func statistics(_ optimal: LayoutResult, _ greedy: LayoutResult) -> String {
        var lines = ["paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy"]
        var totals = [0, 0, 0, 0]
        for block in bodyBlocks {
            let first = optimal.bodies[block.id]!
            let second = greedy.bodies[block.id]!
            let values = [first.broken.count, first.cost, second.broken.count, second.cost]
            for index in totals.indices { totals[index] += values[index] }
            lines.append(([block.paragraphNumber] + values).map(String.init).joined(separator: ","))
        }
        lines.append("total," + totals.map(String.init).joined(separator: ","))
        return lines.joined(separator: "\n") + "\n"
    }

    func writeOutputs(_ optimal: LayoutResult, _ greedy: LayoutResult) throws {
        try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
        try pagesText(optimal.pages).write(toFile: "output/pages.txt", atomically: true, encoding: .ascii)
        try pagesText(greedy.pages).write(toFile: "output/greedy_pages.txt", atomically: true, encoding: .ascii)
        try statistics(optimal, greedy).write(toFile: "output/stats.csv", atomically: true, encoding: .ascii)
        var lines = warnings.map { "line \($0.line): \($0.message)" }
        lines += layoutWarnings(optimal)
        lines += layoutWarnings(greedy)
        try (lines.joined(separator: "\n") + "\n").write(toFile: "output/log.txt", atomically: true, encoding: .ascii)
    }
}

func readLines(_ path: String) throws -> [String] {
    var lines = try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

var parameters: [String: Int] = [:]
for line in try readLines("input/params.txt") {
    let parts = line.split(separator: " ")
    parameters[String(parts[0])] = Int(parts[1])!
}
let dictionaryLines = try readLines("input/hyphenation.txt")
let document = parseDocument(try readLines("input/document.txt"))
let typesetter = Typesetter(document, parameters, dictionaryLines)
let optimal = typesetter.layout(.kp)
let greedy = typesetter.layout(.greedy)
try typesetter.writeOutputs(optimal, greedy)
