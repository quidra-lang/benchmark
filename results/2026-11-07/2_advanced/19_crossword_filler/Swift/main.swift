import Foundation

let letterPoints = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10]
func readLines(_ name: String) throws -> [String] {
    var lines = try String(contentsOfFile: "input/" + name, encoding: .utf8).components(separatedBy: "\n")
    lines.removeLast()
    return lines
}
func ignored(_ line: String) -> Bool { line.isEmpty || line.hasPrefix("#") }
func joined(_ items: [String], _ separator: String) -> String { items.isEmpty ? "-" : items.joined(separator: separator) }
func paragraphs(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for block in blocks { if !lines.isEmpty { lines.append("") }; lines += block }
    return lines
}
struct Settings { var budget: Int; var minimum: Int; var symmetry: String; let relax: Int; let weak: Int }
func readSettings(_ lines: [String]) -> Settings {
    var values: [String: String] = [:]
    for line in lines where !ignored(line) {
        let parts = line.split(separator: " ").map(String.init)
        values[parts[0]] = parts[1]
    }
    return Settings(budget: Int(values["node_budget"]!)!, minimum: Int(values["min_score"]!)!, symmetry: values["symmetry"]!,
        relax: Int(values["relax_step"]!)!, weak: Int(values["weak_score"]!)!)
}
struct WordList {
    let lineCount: Int
    let index: WordIndex
    let invalid: [(Int, String)]
    let duplicates: [(Int, String, Int)]
    init(_ lines: [String]) {
        lineCount = lines.count
        var scores: [String: Int] = [:]
        var firstLines: [String: Int] = [:]
        var invalid: [(Int, String)] = []
        var duplicates: [(Int, String, Int)] = []
        for (number, line) in lines.enumerated() {
            if let reason = wordLineError(line) { invalid.append((number + 1, reason)); continue }
            let parts = line.split(separator: " ").map(String.init)
            if let first = firstLines[parts[0]] { duplicates.append((number + 1, parts[0], first)) }
            else { scores[parts[0]] = Int(parts[1])!; firstLines[parts[0]] = number + 1 }
        }
        index = WordIndex(scores)
        self.invalid = invalid
        self.duplicates = duplicates
    }
    func report() -> [String] {
        var lines = ["WORDLIST lines=\(lineCount) valid=\(index.words.count) invalid=\(invalid.count) duplicates=\(duplicates.count)"]
        for (number, reason) in invalid { lines.append("invalid \(number) \(reason)") }
        for (number, word, first) in duplicates { lines.append("duplicate \(number) \(word) first=\(first)") }
        for length in index.byLength.keys.sorted() {
            let words = index.byLength[length]!
            let total = words.reduce(0) { $0 + index.words[$1].score }
            let best = index.words[words[0]]
            lines.append("length \(length) words=\(words.count) average=\(decimal(total, words.count, 2)) best=\(best.text):\(best.score)")
        }
        let bands = [(1, 20), (21, 40), (41, 60), (61, 80), (81, 100)].map { low, high in
            "\(low)-\(high)=\(index.words.filter { low <= $0.score && $0.score <= high }.count)"
        }
        lines.append("bands " + bands.joined(separator: " "))
        lines.append("top " + index.words.prefix(5).map { "\($0.text):\($0.score)" }.joined(separator: " "))
        let rare = (UInt8(65)...UInt8(90)).map { letter in (index.words.filter { $0.letters.contains(letter) }.count, letter) }
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        lines.append("rare_letters " + rare.prefix(5).map { count, letter in "\(Character(UnicodeScalar(letter))):\(count)" }.joined(separator: " "))
        return lines
    }
}
struct Clue { let text: String; var uses = 0 }
final class ClueBook {
    var entries = 0
    var added = 0
    var invalid: [(Int, String)] = []
    var unknown: [(Int, String)] = []
    var clues: [[Clue]]
    init(_ lines: [String], _ index: WordIndex) {
        clues = Array(repeating: [], count: index.words.count)
        for (number, line) in lines.enumerated() {
            if ignored(line) { continue }
            entries += 1
            if let reason = clueLineError(line) { invalid.append((number + 1, reason)); continue }
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if let id = index.lookup[parts[0]] { clues[id].append(Clue(text: parts[1])); added += 1 }
            else { unknown.append((number + 1, parts[0])) }
        }
    }
    func choose(_ id: Int) -> String? {
        guard let number = clues[id].indices.min(by: { clues[id][$0].uses == clues[id][$1].uses ? $0 < $1 : clues[id][$0].uses < clues[id][$1].uses }) else { return nil }
        clues[id][number].uses += 1
        return clues[id][number].text
    }
    func report(_ index: WordIndex) -> [String] {
        var lines = ["CLUES entries=\(entries) valid=\(added) invalid=\(invalid.count) unknown=\(unknown.count) words=\(clues.filter { !$0.isEmpty }.count)"]
        for (number, reason) in invalid { lines.append("clue_invalid \(number) \(reason)") }
        for (number, word) in unknown { lines.append("clue_unknown \(number) \(word)") }
        let used = clues.flatMap { $0 }.filter { $0.uses > 0 }.count
        let repeated = clues.flatMap { $0 }.filter { $0.uses >= 2 }.count
        lines.append("CLUE_USE used=\(used) unused=\(added - used) repeated=\(repeated)")
        for word in index.lookup.keys.sorted(by: asciiLess) {
            for (number, clue) in clues[index.lookup[word]!].enumerated() where clue.uses >= 2 { lines.append("repeated \(word) clue=\(number + 1) uses=\(clue.uses)") }
        }
        return lines
    }
}
struct Block { let name: String; var options: [String] = []; var rows: [String] = [] }
func splitBlocks(_ lines: [String]) -> [Block] {
    var blocks: [Block] = []
    var current: Block? = nil
    for line in lines {
        if var block = current {
            if line == "END" { blocks.append(block); current = nil }
            else {
                if line.contains(" ") { block.options.append(line) } else { block.rows.append(line) }
                current = block
            }
        } else if line.hasPrefix("TEMPLATE ") { current = Block(name: String(line.dropFirst(9))) }
    }
    return blocks
}
struct Prepared { let settings: Settings; let layout: Layout; let initial: GridState; let themeSlots: Set<Int> }
enum TemplateFailure: Error { case invalid(String) }
func prepare(_ block: Block, _ defaults: Settings, _ names: Set<String>, _ index: WordIndex) throws -> Prepared {
    if !(1...20).contains(block.name.utf8.count) || !block.name.utf8.allSatisfy({ 97...122 ~= $0 || 48...57 ~= $0 || $0 == 95 }) { throw TemplateFailure.invalid("bad name") }
    if names.contains(block.name) { throw TemplateFailure.invalid("duplicate name") }
    var settings = defaults
    var seen: Set<String> = []
    var themes: [String] = []
    for (number, line) in block.options.enumerated() {
        let split = line.firstIndex(of: " ")!
        let key = String(line[..<split])
        let value = String(line[line.index(after: split)...])
        var valid = false
        if key == "theme" {
            if isValidWord(value) && !themes.contains(value) { themes.append(value); valid = true }
        } else if !seen.contains(key) {
            if key == "node_budget" && isValidInteger(value, 1, 100000) { settings.budget = Int(value)!; valid = true }
            else if key == "min_score" && isValidInteger(value, 1, 100) { settings.minimum = Int(value)!; valid = true }
            else if key == "symmetry" && ["rot180", "mirror", "none"].contains(value) { settings.symmetry = value; valid = true }
        }
        if !valid { throw TemplateFailure.invalid("bad option \(number + 1)") }
        seen.insert(key)
    }
    if !(3...15).contains(block.rows.count) { throw TemplateFailure.invalid("bad height") }
    let width = block.rows[0].utf8.count
    for (number, row) in block.rows.enumerated() {
        if !(3...15).contains(row.utf8.count) || row.utf8.count != width || !row.utf8.allSatisfy({ $0 == 46 || $0 == 35 || 65...90 ~= $0 }) { throw TemplateFailure.invalid("bad row \(number + 1)") }
    }
    let grid = Grid(block.rows)
    if settings.symmetry != "none", let cell = grid.asymmetricCell(settings.symmetry) { throw TemplateFailure.invalid("asymmetric at \(grid.location(cell))") }
    if grid.componentCount != 1 { throw TemplateFailure.invalid("disconnected components=\(grid.componentCount)") }
    if let run = findShortRun(grid) { throw TemplateFailure.invalid("short slot at \(grid.location(run.cell)) \(run.direction)") }
    let layout = Layout(grid)
    if let cell = layout.orphanCell { throw TemplateFailure.invalid("orphan cell \(grid.location(cell))") }
    var initial = GridState(grid.cells, layout.slots.count)
    var themeSlots: Set<Int> = []
    for (number, theme) in themes.enumerated() {
        guard let id = index.lookup[theme] else { throw TemplateFailure.invalid("unknown theme \(number + 1)") }
        guard let slot = layout.slots.first(where: { initial.words[$0.index] == nil && $0.length == theme.utf8.count && matches(index.words[id].letters, initial.pattern($0)) }) else {
            throw TemplateFailure.invalid("theme \(number + 1) does not fit")
        }
        _ = initial.assign(slot, id, index)
        themeSlots.insert(slot.index)
    }
    return Prepared(settings: settings, layout: layout, initial: initial, themeSlots: themeSlots)
}
final class Completed {
    let prepared: Prepared
    let attempts: [Attempt]
    let state: GridState
    let chosen: [String?]
    init(_ prepared: Prepared, _ index: WordIndex, _ clues: ClueBook) {
        self.prepared = prepared
        var attempts: [Attempt] = []
        var minimum = prepared.settings.minimum
        while true {
            let attempt = Attempt(prepared.initial, minimum, prepared.settings.budget)
            attempt.run(prepared.layout, index)
            attempts.append(attempt)
            if attempt.outcome == "filled" || prepared.settings.relax == 0 || minimum <= 1 { break }
            minimum = max(minimum - prepared.settings.relax, 1)
        }
        self.attempts = attempts
        let state = attempts.last!.finalState
        self.state = state
        var chosen = Array<String?>(repeating: nil, count: prepared.layout.slots.count)
        for across in [true, false] {
            for slot in prepared.layout.slots where slot.across == across {
                if let word = state.words[slot.index] { chosen[slot.index] = clues.choose(word) }
            }
        }
        self.chosen = chosen
    }
    var finalAttempt: Attempt { attempts.last! }
    var filled: Bool { finalAttempt.outcome == "filled" }
    func totalScore(_ index: WordIndex) -> Int { state.words.reduce(0) { $0 + index.words[$1!].score } }
    func entry(_ slot: Slot, _ index: WordIndex) -> String {
        let word = index.words[state.words[slot.index]!]
        return "\(slot.label):\(word.text):\(word.score)"
    }
    func clueParagraph(_ name: String, _ index: WordIndex) -> [String] {
        var lines = ["TEMPLATE " + name]
        var clued = 0
        var missing = 0
        var unfilled = 0
        for (heading, across) in [("ACROSS", true), ("DOWN", false)] {
            let slots = prepared.layout.slots.filter { $0.across == across }
            if !slots.isEmpty { lines.append(heading) }
            for slot in slots {
                if let id = state.words[slot.index] {
                    let clue: String
                    if let chosen = chosen[slot.index] { clued += 1; clue = chosen } else { missing += 1; clue = "(no clue)" }
                    lines.append(listLine(slot, clue, index.words[id].text, String(index.words[id].score), prepared.themeSlots.contains(slot.index)))
                } else {
                    unfilled += 1
                    lines.append(listLine(slot, "(unfilled)", String(decoding: state.pattern(slot), as: UTF8.self), "-", false))
                }
            }
        }
        lines.append("clued=\(clued) missing=\(missing) unfilled=\(unfilled)")
        return lines
    }
    func statsParagraph(_ name: String, _ index: WordIndex) -> [String] {
        let p = prepared
        let layout = p.layout
        let grid = layout.grid
        let slots = layout.slots
        let whites = grid.whiteCells
        let blacks = grid.cells.count - whites.count
        let givens = whites.filter { grid.cells[$0] != 46 }.count
        let symmetries = ["rot180", "mirror"].filter { grid.asymmetricCell($0) == nil }
        let symmetry = symmetries.isEmpty ? "none" : symmetries.joined(separator: ",")
        let lengths = Set(slots.map(\.length)).sorted()
        let across = slots.filter(\.across).count
        let unchecked = whites.filter { layout.ownerCount($0) == 1 }.count
        let lengthText = lengths.map { length in "\(length):\(slots.filter { $0.length == length }.count)" }.joined(separator: ",")
        let lengthSum = slots.reduce(0) { $0 + $1.length }
        var lines = ["TEMPLATE " + name,
            "grid size=\(grid.width)x\(grid.height) blocks=\(blacks) white=\(whites.count) density=\(decimal(100 * blacks, grid.cells.count, 1)) givens=\(givens) required=\(p.settings.symmetry) symmetry=\(symmetry)",
            "slots across=\(across) down=\(slots.count - across) total=\(slots.count) lengths=\(lengthText) avg_length=\(decimal(lengthSum, slots.count, 2)) longest=\(lengths.last!) unchecked=\(unchecked)"]
        if !p.themeSlots.isEmpty { lines.append("themes " + slots.filter { p.themeSlots.contains($0.index) }.map { entry($0, index) }.joined(separator: " ")) }
        let supply = lengths.map { length in "\(length):\(index.byLength[length, default: []].filter { index.words[$0].score >= p.settings.minimum }.count)" }
        lines.append("coverage " + supply.joined(separator: " "))
        let tightest = slots.filter { !p.themeSlots.contains($0.index) }.map { slot in
            (index.candidates(p.initial.pattern(slot), p.settings.minimum, p.initial.used).count, slot.index)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        lines.append("tightest " + joined(tightest.prefix(3).map { count, number in "\(slots[number].label):\(count)" }, " "))
        for (number, attempt) in attempts.enumerated() {
            lines.append("attempt \(number + 1) min_score=\(attempt.minimum) budget=\(attempt.budget) outcome=\(attempt.outcome) nodes=\(attempt.nodes) backtracks=\(attempt.backtracks) prunes=\(attempt.prunes) dead_ends=\(attempt.deadEnds) max_depth=\(attempt.maxDepth)")
        }
        lines.append("trace " + joined(finalAttempt.trace, " "))
        let hotspots = slots.indices.filter { finalAttempt.failures[$0] > 0 }.sorted {
            finalAttempt.failures[$0] == finalAttempt.failures[$1] ? $0 < $1 : finalAttempt.failures[$0] > finalAttempt.failures[$1]
        }.prefix(3).map { "\(slots[$0].label):\(finalAttempt.failures[$0])" }
        lines.append("hotspots " + joined(hotspots, " "))
        if filled {
            lines.append("order " + joined(finalAttempt.sequence.map { slots[$0].label }, " "))
            let total = totalScore(index)
            let weakest = slots.min { first, second in
                let a = index.words[state.words[first.index]!].score
                let b = index.words[state.words[second.index]!].score
                return a == b ? first.index < second.index : a < b
            }!
            let weak = slots.filter { index.words[state.words[$0.index]!].score < p.settings.weak }.map { entry($0, index) }
            lines.append("quality total=\(total) average=\(decimal(total, slots.count, 2)) weakest=\(entry(weakest, index)) weak=\(joined(weak, ","))")
            let letters = Set(whites.map { state.letters[$0] })
            let missing = String(decoding: (UInt8(65)...UInt8(90)).filter { !letters.contains($0) }, as: UTF8.self)
            let points = whites.reduce(0) { $0 + letterPoints[Int(state.letters[$1] - 65)] }
            var worst: (sum: Int, cell: Int, across: Int, down: Int)? = nil
            for cell in whites {
                if let a = layout.acrossSlot[cell], let d = layout.downSlot[cell] {
                    let sum = index.words[state.words[a]!].score + index.words[state.words[d]!].score
                    if worst == nil || sum < worst!.sum { worst = (sum, cell, a, d) }
                }
            }
            var crossing = "-"
            if let worst {
                let a = worst.across
                let d = worst.down
                crossing = "\(grid.location(worst.cell)) \(slots[a].label):\(index.words[state.words[a]!].text)+\(slots[d].label):\(index.words[state.words[d]!].text)=\(worst.sum)"
            }
            lines.append("letters distinct=\(letters.count) pangram=\(missing.isEmpty ? "yes" : "no") missing=\(missing.isEmpty ? "-" : missing) scrabble=\(decimal(points, whites.count, 2)) worst_crossing=\(crossing)")
        } else {
            let assigned = state.words.filter { $0 != nil }.count
            let lettered = whites.filter { state.letters[$0] != 46 }.count
            let blocked = slots.filter { state.words[$0.index] == nil && index.candidates(state.pattern($0), finalAttempt.minimum, state.used).isEmpty }.map(\.label)
            lines.append("partial assigned=\(assigned)/\(slots.count) letters=\(lettered)/\(whites.count) blocked=\(joined(blocked, ","))")
        }
        return lines
    }
}
struct Template {
    let name: String
    let completed: Completed?
    let error: String?
    func gridParagraph() -> [String] {
        var lines = ["TEMPLATE " + name]
        if let error { lines.append("error " + error) }
        else {
            let result = completed!
            let lastAttempt = result.finalAttempt
            lines.append("outcome=\(lastAttempt.outcome) attempts=\(result.attempts.count) min_score=\(lastAttempt.minimum)")
            lines += gridLines(result.prepared.layout.grid, result.state.letters)
            lines.append("numbers")
            lines += numberLines(result.prepared.layout)
        }
        return lines
    }
}
func overallParagraphs(_ templates: [Template], _ index: WordIndex) -> [[String]] {
    let valid = templates.filter { $0.completed != nil }
    let filled = valid.filter { $0.completed!.filled }
    let ranked = filled.sorted { first, second in
        let a = first.completed!
        let b = second.completed!
        let left = a.totalScore(index) * b.prepared.layout.slots.count
        let right = b.totalScore(index) * a.prepared.layout.slots.count
        return left == right ? asciiLess(first.name, second.name) : left > right
    }
    var ranking = ["RANKING"]
    for (position, template) in ranked.enumerated() {
        let result = template.completed!
        let total = result.totalScore(index)
        let entries = result.prepared.layout.slots.count
        ranking.append("rank \(position + 1) \(template.name) average=\(decimal(total, entries, 2)) total=\(total) entries=\(entries)")
    }
    var appearances: [Int: [String]] = [:]
    for template in filled { for word in template.completed!.state.words { appearances[word!, default: []].append(template.name) } }
    let reused = appearances.keys.filter { appearances[$0]!.count >= 2 }.sorted {
        appearances[$0]!.count == appearances[$1]!.count ? asciiLess(index.words[$0].text, index.words[$1].text) : appearances[$0]!.count > appearances[$1]!.count
    }
    var reuse = ["REUSE"]
    for id in reused { reuse.append("reused \(index.words[id].text) \(appearances[id]!.count) \(appearances[id]!.joined(separator: ","))") }
    let attempts = valid.reduce(0) { $0 + $1.completed!.attempts.count }
    let nodes = valid.reduce(0) { sum, template in sum + template.completed!.attempts.reduce(0) { $0 + $1.nodes } }
    let unfillable = valid.filter { $0.completed!.finalAttempt.outcome == "unfillable" }.count
    let budget = valid.filter { $0.completed!.finalAttempt.outcome == "budget" }.count
    let summary = ["SUMMARY templates=\(templates.count) invalid=\(templates.count - valid.count) filled=\(filled.count) unfillable=\(unfillable) budget=\(budget) attempts=\(attempts) nodes=\(nodes)"]
    return [ranking, reuse, summary]
}

let settings = readSettings(try readLines("params.txt"))
let wordList = WordList(try readLines("words.txt"))
let index = wordList.index
let clues = ClueBook(try readLines("clues.txt"), index)
var templates: [Template] = []
var names: Set<String> = []
for block in splitBlocks(try readLines("templates.txt")) {
    do {
        let prepared = try prepare(block, settings, names, index)
        templates.append(Template(name: block.name, completed: Completed(prepared, index, clues), error: nil))
    } catch TemplateFailure.invalid(let reason) {
        templates.append(Template(name: block.name, completed: nil, error: reason))
    } catch { throw error }
    names.insert(block.name)
}
let grid = paragraphs(templates.map { $0.gridParagraph() })
let clueLines = paragraphs(templates.compactMap { template in template.completed.map { $0.clueParagraph(template.name, index) } })
var stats = templates.compactMap { template in template.completed.map { $0.statsParagraph(template.name, index) } }
stats += overallParagraphs(templates, index)
let words = wordList.report() + clues.report(index)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in [("grid.txt", grid), ("clues.txt", clueLines), ("search_stats.txt", paragraphs(stats)), ("wordlist.txt", words)] {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
