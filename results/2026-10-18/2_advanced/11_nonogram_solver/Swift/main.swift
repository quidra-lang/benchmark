import Foundation

func readBlocks(_ path: String) throws -> [[String]] {
    var blocks: [[String]] = [], current: [String] = [], inside = false
    for line in try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n") {
        if !inside { if !line.isEmpty && !line.hasPrefix("#") { current = [line]; inside = true } }
        else if line == "END" { blocks.append(current); current = []; inside = false }
        else { current.append(line) }
    }
    return blocks
}
func validName(_ name: String) -> Bool { (1...20).contains(name.utf8.count) && name.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 } }
func numberList(_ numbers: [Int]) -> String { numbers.isEmpty ? "-" : numbers.map(String.init).joined(separator: ",") }
func cellText(_ cell: Cell) -> String { "\(cell.row + 1),\(cell.column + 1)" }
func stateGrid(_ lines: [String]) -> [[Int]] { lines.map { $0.map(charState) } }
func gridColumns(_ grid: [[Int]]) -> [[Int]] { grid[0].indices.map { lineCells(grid, false, $0) } }
func differingCells(_ first: [[Int]], _ second: [[Int]]) -> [Cell] { first.indices.flatMap { row in first[row].indices.filter { first[row][$0] != second[row][$0] }.map { Cell(row: row, column: $0) } } }
struct Given: Equatable { let row: Int; let column: Int; let state: Int; var cell: Cell { Cell(row: row, column: column) } }
struct RawGiven { let row: Int; let column: Int; let value: String }
func checkClues(_ lines: [String], _ kind: String, _ length: Int) -> ([[Int]], String) {
    var result: [[Int]] = []
    for (index, text) in lines.enumerated() { guard let clue = parseClue(text) else { return ([], "bad clue \(kind) \(index + 1)") }; if !clueFits(clue, length) { return ([], "\(kind) \(index + 1) too long") }; result.append(clue) }
    return (result, "")
}
final class Puzzle {
    let name: String
    let width: Int
    let height: Int
    let rowLines: [String]
    let columnLines: [String]
    let givenLines: [RawGiven]
    let answerPresent: Bool
    let answerLines: [String]
    var rowClues: [[Int]] = [], columnClues: [[Int]] = [], answer: [[Int]] = []
    var givens: [Given] = []
    init(_ texts: [String]) {
        name = String(texts[0].dropFirst(7)); let dimensions = texts[1].split(separator: " "); width = Int(dimensions[1])!; height = Int(dimensions[2])!
        var position = 3
        while texts[position] != "COLUMNS" { position += 1 }
        rowLines = Array(texts[3..<position]); position += 1
        var columns: [String] = [], given: [RawGiven] = []
        while position < texts.count && isClueLine(texts[position]) { columns.append(texts[position]); position += 1 }
        while position < texts.count && texts[position].hasPrefix("GIVEN ") { let fields = texts[position].split(separator: " ").map(String.init); given.append(RawGiven(row: Int(fields[1])!, column: Int(fields[2])!, value: fields[3])); position += 1 }
        columnLines = columns; givenLines = given; answerPresent = position < texts.count; answerLines = position < texts.count ? Array(texts[(position + 1)...]) : []
    }
    func validate(_ earlier: Set<String>) -> String {
        if !validName(name) { return "bad name" }
        if earlier.contains(name) { return "duplicate name" }
        if !(1...30).contains(width) || !(1...30).contains(height) { return "bad size" }
        if rowLines.count != height { return "row count \(rowLines.count) expected \(height)" }
        if columnLines.count != width { return "column count \(columnLines.count) expected \(width)" }
        let (rows, rowProblem) = checkClues(rowLines, "row", width); if !rowProblem.isEmpty { return rowProblem }
        let (columns, columnProblem) = checkClues(columnLines, "column", height); if !columnProblem.isEmpty { return columnProblem }
        rowClues = rows; columnClues = columns
        let rowTotal = rows.flatMap { $0 }.reduce(0, +), columnTotal = columns.flatMap { $0 }.reduce(0, +)
        if rowTotal != columnTotal { return "total mismatch rows=\(rowTotal) columns=\(columnTotal)" }
        var taken: Set<Int> = []
        for (index, given) in givenLines.enumerated() {
            if !(1...height).contains(given.row) || !(1...width).contains(given.column) || !["#", "."].contains(given.value) { return "bad given \(index + 1)" }
            if !taken.insert(given.row * width + given.column).inserted { return "duplicate given \(index + 1)" }
            givens.append(Given(row: given.row - 1, column: given.column - 1, state: given.value == "#" ? filled : empty))
        }
        if answerPresent {
            if answerLines.count != height || answerLines.contains(where: { $0.count != width || $0.contains { $0 != "#" && $0 != "." && $0 != "?" } }) { return "bad answer" }
            answer = stateGrid(answerLines)
        }
        return ""
    }
}
struct Picture {
    let name: String
    let rows: [String]
    init(_ texts: [String]) { name = String(texts[0].dropFirst(8)); rows = Array(texts.dropFirst()) }
    func validate(_ earlier: Set<String>) -> String {
        if !validName(name) { return "bad name" }
        if earlier.contains(name) { return "duplicate name" }
        if !(1...30).contains(rows.count) { return "bad height" }
        for (index, row) in rows.enumerated() { if !(1...30).contains(row.count) || row.count != rows[0].count || row.contains(where: { $0 != "#" && $0 != "." }) { return "bad row \(index + 1)" } }
        return ""
    }
}
struct Logical { let grid: [[Int]]; let details: Propagation; let result: String }
func logicalSolve(_ rows: [[Int]], _ columns: [[Int]], _ givens: [Given], _ precise: Bool) -> Logical {
    var grid = Array(repeating: Array(repeating: unknown, count: columns.count), count: rows.count)
    for given in givens { grid[given.row][given.column] = given.state }
    let details = propagate(&grid, rows, columns, precise, Array(repeating: true, count: rows.count), Array(repeating: true, count: columns.count))
    return Logical(grid: grid, details: details, result: details.conflict.map { "contradiction at=" + $0.label } ?? (determinedCount(grid) == rows.count * columns.count ? "solved" : "stuck"))
}
struct Analysis {
    let simple: Logical
    let logic: Logical
    let search: Search
    let searched: Bool
    let solutions: [[[Int]]]
    let difficulty: String
    let status: String
    var lineSolves: Int { logic.details.steps.count + search.lineSolves }
    var guesses: Int { search.guesses.count }
    var maxDepth: Int { search.maxDepth }
    init(_ rows: [[Int]], _ columns: [[Int]], _ givens: [Given]) {
        let simple = logicalSolve(rows, columns, givens, false), logic = logicalSolve(rows, columns, givens, true), search = Search(rows, columns)
        var solutions: [[[Int]]] = [], difficulty = "-", status = "contradiction", searched = false
        if logic.details.conflict == nil {
            if logic.result == "solved" { status = "unique"; solutions = [logic.grid]; difficulty = simple.result == "solved" ? "easy" : "medium" }
            else { searched = true; search.run(logic.grid); solutions = search.solutions; status = solutions.isEmpty ? "none" : solutions.count == 1 ? "unique" : "multiple"; if status == "unique" { difficulty = "hard" } }
        }
        self.simple = simple; self.logic = logic; self.search = search; self.searched = searched; self.solutions = solutions; self.difficulty = difficulty; self.status = status
    }
}
func clueStatistics(_ rows: [[Int]], _ columns: [[Int]]) -> String {
    let rowBlocks = rows.reduce(0) { $0 + $1.count }, columnBlocks = columns.reduce(0) { $0 + $1.count }, filled = rows.flatMap { $0 }.reduce(0, +), maxBlock = (rows + columns).flatMap { $0 }.max() ?? 0
    let fixed = rows.filter { $0.isEmpty || $0.reduce(0, +) + $0.count - 1 == columns.count }.count + columns.filter { $0.isEmpty || $0.reduce(0, +) + $0.count - 1 == rows.count }.count
    return "row_blocks=\(rowBlocks) column_blocks=\(columnBlocks) filled=\(filled) max_block=\(maxBlock) fixed_lines=\(fixed)"
}
func stepStatistics(_ details: Propagation) -> String {
    let steps = details.steps.filter { !$0.contradiction }, productive = details.steps.filter { !$0.contradiction && $0.gain > 0 }.count
    let best = steps.map(\.gain).max() ?? 0, at = steps.first { $0.gain == best }?.label ?? "-"
    return "productive=\(productive) idle=\(steps.count - productive) best=\(best) at=\(best == 0 ? "-" : at)"
}
func featuresText(_ grid: [[Int]]) -> String {
    let height = grid.count, width = grid[0].count
    var seen = Array(repeating: Array(repeating: false, count: width), count: height), filledCount = 0, components = 0, largest = 0, minRow = height, minColumn = width, maxRow = -1, maxColumn = -1
    var lr = true, ud = true, rot180 = true
    for row in 0..<height {
        for column in 0..<width {
            lr = lr && grid[row][column] == grid[row][width - 1 - column]; ud = ud && grid[row][column] == grid[height - 1 - row][column]; rot180 = rot180 && grid[row][column] == grid[height - 1 - row][width - 1 - column]
            if grid[row][column] != filled { continue }
            filledCount += 1; minRow = min(minRow, row); minColumn = min(minColumn, column); maxRow = max(maxRow, row); maxColumn = max(maxColumn, column)
            if seen[row][column] { continue }
            seen[row][column] = true
            var stack = [Cell(row: row, column: column)], count = 0
            while let current = stack.popLast() {
                count += 1
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] { let r = current.row + dr, c = current.column + dc; if (0..<height).contains(r) && (0..<width).contains(c) && grid[r][c] == filled && !seen[r][c] { seen[r][c] = true; stack.append(Cell(row: r, column: c)) } }
            }
            components += 1; largest = max(largest, count)
        }
    }
    let bbox = filledCount == 0 ? "-" : "\(minRow + 1),\(minColumn + 1),\(maxRow + 1),\(maxColumn + 1)"
    let symmetries = [("lr", lr), ("ud", ud), ("rot180", rot180)].filter { $0.1 }.map { $0.0 }
    return "filled=\(filledCount) components=\(components) largest=\(largest) bbox=\(bbox) symmetry=\(symmetries.isEmpty ? "none" : symmetries.joined(separator: ","))"
}
func unknownSummary(_ lines: [[Int]]) -> String { lines.enumerated().compactMap { index, cells in let count = cells.filter { $0 == unknown }.count; return count > 0 ? "\(index + 1):\(count)" : nil }.joined(separator: " ") }
func searchLines(_ search: Search) -> [String] { ["search guesses=\(search.guesses.count) max_depth=\(search.maxDepth) backtracks=\(search.backtracks) solutions=\(search.solutions.count) line_solves=\(search.lineSolves)"] + search.guesses.map { "guess \($0.number) depth=\($0.depth) cell=\(cellText($0.cell)) value=\(stateChar($0.value)) solves=\($0.solves) known=\($0.known) result=\($0.result)" } }
func displayLines(_ analysis: Analysis) -> [String] {
    var names: [String] = [], grids: [[[Int]]] = []
    if analysis.status == "contradiction" { names = ["partial"]; grids = [analysis.logic.grid] }
    else { if analysis.simple.result == "stuck" { names.append("simple"); grids.append(analysis.simple.grid) }; if analysis.logic.result == "stuck" { names.append("logic"); grids.append(analysis.logic.grid) }; if analysis.status == "multiple" { names += ["first", "second"]; grids += analysis.solutions } }
    return names.isEmpty ? [] : gridDisplay(names, grids)
}
func evaluateGivens(_ puzzle: Puzzle, _ analysis: Analysis) -> String {
    if puzzle.givens.isEmpty || analysis.status == "multiple" { return "" }
    let numbers = puzzle.givens.indices.filter { index in let others = puzzle.givens.enumerated().filter { $0.offset != index }.map(\.element); let status = Analysis(puzzle.rowClues, puzzle.columnClues, others).status; return status == "unique" || (analysis.status != "unique" && status == "multiple") }.map { $0 + 1 }
    return "givens \(analysis.status == "unique" ? "redundant" : "blame")=\(numberList(numbers))"
}
struct Grading { let result: String; let lines: [String] }
func gradeAnswer(_ puzzle: Puzzle, _ analysis: Analysis) -> Grading {
    let rows = (0..<puzzle.height).filter { !hasPlacement(puzzle.answer[$0], puzzle.rowClues[$0]) }, columns = (0..<puzzle.width).filter { !hasPlacement(lineCells(puzzle.answer, false, $0), puzzle.columnClues[$0]) }
    let givens = puzzle.givens.indices.filter { let given = puzzle.givens[$0], state = puzzle.answer[given.row][given.column]; return state != unknown && state != given.state }
    let known = determinedCount(puzzle.answer), mismatched = !rows.isEmpty || !columns.isEmpty || !givens.isEmpty
    let result = known < puzzle.width * puzzle.height ? "partial" : mismatched ? "wrong" : "correct"
    var text = "answer result=\(result) known=\(known) rows=\(numberList(rows.map { $0 + 1 })) columns=\(numberList(columns.map { $0 + 1 })) givens=\(numberList(givens.map { $0 + 1 }))"
    if result == "partial" {
        var extendable = false
        if !mismatched {
            var additions = puzzle.givens
            for row in 0..<puzzle.height { for column in 0..<puzzle.width where puzzle.answer[row][column] != unknown && !puzzle.givens.contains(where: { $0.row == row && $0.column == column }) { additions.append(Given(row: row, column: column, state: puzzle.answer[row][column])) } }
            extendable = ["unique", "multiple"].contains(Analysis(puzzle.rowClues, puzzle.columnClues, additions).status)
        }
        text += " extendable=\(extendable ? "yes" : "no")"
    }
    if analysis.status == "unique" { let differs = puzzle.answer.indices.reduce(0) { count, row in count + puzzle.answer[row].indices.filter { puzzle.answer[row][$0] != unknown && puzzle.answer[row][$0] != analysis.solutions[0][row][$0] }.count }; text += " differs=\(differs)" }
    var lines = [text]
    for (isRow, indices) in [(true, rows), (false, columns)] { for index in indices { let clue = isRow ? puzzle.rowClues[index] : puzzle.columnClues[index], cells = lineCells(puzzle.answer, isRow, index); let suffix = result == "partial" ? "cells=" + stateString(cells) : "got=" + clueText(runClue(cells), ","); lines.append("mismatch \(lineLabel(isRow, index)) expected=\(clueText(clue, ",")) \(suffix)") } }
    return Grading(result: result, lines: lines)
}

struct Report {
    let puzzle: Puzzle
    let analysis: Analysis
    let evaluation: String
    let grading: Grading
    init(_ puzzle: Puzzle) { let result = Analysis(puzzle.rowClues, puzzle.columnClues, puzzle.givens); self.puzzle = puzzle; analysis = result; evaluation = evaluateGivens(puzzle, result); grading = puzzle.answerPresent ? gradeAnswer(puzzle, result) : Grading(result: "-", lines: []) }
    var score: Int { analysis.lineSolves + 25 * analysis.guesses }
    var paragraph: [String] {
        var lines = ["PUZZLE " + puzzle.name,
            "size=\(puzzle.width)x\(puzzle.height) givens=\(puzzle.givens.count) status=\(analysis.status) difficulty=\(analysis.difficulty)",
            "clues " + clueStatistics(puzzle.rowClues, puzzle.columnClues),
            "simple known=\(determinedCount(analysis.simple.grid)) line_solves=\(analysis.simple.details.steps.count) result=\(analysis.simple.result)",
            "logic known=\(determinedCount(analysis.logic.grid)) line_solves=\(analysis.logic.details.steps.count) result=\(analysis.logic.result)",
            "steps " + stepStatistics(analysis.logic.details)]
        if puzzle.width * puzzle.height <= 49 { lines.append("trace " + analysis.logic.details.record) }
        if analysis.logic.result == "stuck" { lines.append("stuck rows=\(unknownSummary(analysis.logic.grid)) columns=\(unknownSummary(gridColumns(analysis.logic.grid)))") }
        if let conflict = analysis.logic.details.conflict { let clue = conflict.isRow ? puzzle.rowClues[conflict.index] : puzzle.columnClues[conflict.index]; lines.append("conflict line=\(conflict.label) clue=\(clueText(clue, ",")) cells=\(stateString(lineCells(analysis.logic.grid, conflict.isRow, conflict.index)))") }
        if analysis.searched { lines += searchLines(analysis.search) }
        if analysis.status == "multiple" { let cells = differingCells(analysis.solutions[0], analysis.solutions[1]); lines.append("differ count=\(cells.count) cells=\(cells.map(cellText).joined(separator: " "))") }
        lines += displayLines(analysis)
        if analysis.status == "unique" { lines += ["sheet"] + answerSheet(puzzle.rowClues, puzzle.columnClues, analysis.solutions[0]) + ["picture " + featuresText(analysis.solutions[0])] }
        if !evaluation.isEmpty { lines.append(evaluation) }
        if puzzle.answerPresent { lines += grading.lines }
        return lines
    }
    var statsRow: String { [puzzle.name, analysis.status, analysis.difficulty, String(puzzle.width), String(puzzle.height), String(puzzle.givens.count), String(determinedCount(analysis.simple.grid)), String(determinedCount(analysis.logic.grid)), String(analysis.lineSolves), String(analysis.guesses), String(analysis.maxDepth), String(analysis.solutions.count), grading.result].joined(separator: ",") }
}
func difficultyOrder(_ value: String) -> Int { value == "easy" ? 0 : value == "medium" ? 1 : 2 }
func rankingLines(_ reports: [Report]) -> [String] {
    let ranked = reports.filter { $0.analysis.status == "unique" }.sorted { first, second in
        let a = difficultyOrder(first.analysis.difficulty), b = difficultyOrder(second.analysis.difficulty)
        if a != b { return a < b }; if first.score != second.score { return first.score < second.score }; return first.puzzle.name < second.puzzle.name
    }
    return ["RANKING"] + ranked.enumerated().map { index, report in "rank \(index + 1) \(report.puzzle.name) \(report.analysis.difficulty) score=\(report.score) size=\(report.puzzle.width)x\(report.puzzle.height)" }
}
func joinParagraphs(_ paragraphs: [[String]]) -> [String] { paragraphs.enumerated().flatMap { index, paragraph in (index == 0 ? [] : [""]) + paragraph } }
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8) }
func processPuzzles(_ blocks: [[String]]) throws -> [Report] {
    var earlier: Set<String> = [], reports: [Report] = [], paragraphs: [[String]] = [], stats = ["puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer"]
    for block in blocks {
        let puzzle = Puzzle(block), problem = puzzle.validate(earlier)
        earlier.insert(puzzle.name)
        if !problem.isEmpty { paragraphs.append(["PUZZLE " + puzzle.name, "error " + problem]); stats.append(puzzle.name + ",invalid" + String(repeating: ",-", count: 11)) }
        else { let report = Report(puzzle); reports.append(report); paragraphs.append(report.paragraph); stats.append(report.statsRow) }
    }
    func countStatus(_ status: String) -> Int { reports.filter { $0.analysis.status == status }.count }
    func countDifficulty(_ difficulty: String) -> Int { reports.filter { $0.analysis.difficulty == difficulty }.count }
    paragraphs.append(rankingLines(reports))
    paragraphs.append(["SUMMARY puzzles=\(blocks.count) invalid=\(blocks.count - reports.count) contradiction=\(countStatus("contradiction")) none=\(countStatus("none")) unique=\(countStatus("unique")) multiple=\(countStatus("multiple")) easy=\(countDifficulty("easy")) medium=\(countDifficulty("medium")) hard=\(countDifficulty("hard")) line_solves=\(reports.reduce(0) { $0 + $1.analysis.lineSolves }) guesses=\(reports.reduce(0) { $0 + $1.analysis.guesses })"])
    try writeLines("solutions.txt", joinParagraphs(paragraphs)); try writeLines("stats.csv", stats)
    return reports
}
struct Generation {
    let grid: [[Int]]
    let rowClues: [[Int]]
    let columnClues: [[Int]]
    let givens: [Given]
    let log: [String]
    let initial: Analysis
    let finalAnalysis: Analysis
    init(_ grid: [[Int]]) {
        let rows = grid.map(runClue), columns = gridColumns(grid).map(runClue)
        let initial = Analysis(rows, columns, [])
        var givens: [Given] = [], log: [String] = [], current = initial
        while current.status == "multiple" {
            let chosen = differingCells(current.solutions[0], current.solutions[1])[0], value = grid[chosen.row][chosen.column]
            givens.append(Given(row: chosen.row, column: chosen.column, state: value)); current = Analysis(rows, columns, givens)
            log.append("# hint \(givens.count) cell=\(cellText(chosen)) value=\(stateChar(value)) status=\(current.status)")
        }
        let original = givens
        for given in original { let others = givens.filter { $0.cell != given.cell }; if Analysis(rows, columns, others).status == "unique" { givens = others; log.append("# drop cell=\(cellText(given.cell))") } }
        current = Analysis(rows, columns, givens)
        var logicHints = 0
        while current.difficulty == "hard" {
            let chosen = guessCell(current.logic.grid), value = grid[chosen.row][chosen.column]
            givens.append(Given(row: chosen.row, column: chosen.column, state: value)); current = Analysis(rows, columns, givens); logicHints += 1
            log.append("# logic hint \(logicHints) cell=\(cellText(chosen)) value=\(stateChar(value)) difficulty=\(current.difficulty)")
        }
        self.grid = grid; rowClues = rows; columnClues = columns; self.givens = givens; self.log = log; self.initial = initial; finalAnalysis = current
    }
    func puzzleLines(_ name: String) -> [String] {
        ["PUZZLE " + name, "SIZE \(columnClues.count) \(rowClues.count)", "ROWS"] + rowClues.map { clueText($0) } + ["COLUMNS"] + columnClues.map { clueText($0) } + givens.sorted { $0.row != $1.row ? $0.row < $1.row : $0.column < $1.column }.map { "GIVEN \($0.row + 1) \($0.column + 1) \(stateChar($0.state))" } + ["END"]
    }
}
func processPictures(_ blocks: [[String]], _ reports: [Report]) throws {
    var earlier: Set<String> = [], paragraphs: [[String]] = [], valid = 0, unique = 0, lineLogic = 0, hinted = 0, hints = 0
    for block in blocks {
        let picture = Picture(block), problem = picture.validate(earlier)
        earlier.insert(picture.name)
        if !problem.isEmpty { paragraphs.append(["# picture \(picture.name) error \(problem)"]); continue }
        let generation = Generation(stateGrid(picture.rows))
        let duplicate = reports.first { $0.puzzle.rowClues == generation.rowClues && $0.puzzle.columnClues == generation.columnClues }?.puzzle.name ?? "-"
        valid += 1; if generation.initial.status == "unique" { unique += 1 }; if ["easy", "medium"].contains(generation.initial.difficulty) { lineLogic += 1 }; if !generation.givens.isEmpty { hinted += 1 }; hints += generation.givens.count
        let lines = ["# picture \(picture.name) size=\(generation.grid[0].count)x\(generation.grid.count) \(featuresText(generation.grid))",
            "# clues \(clueStatistics(generation.rowClues, generation.columnClues)) duplicate_of=\(duplicate)",
            "# plain status=\(generation.initial.status) difficulty=\(generation.initial.difficulty) line_solves=\(generation.initial.lineSolves) guesses=\(generation.initial.guesses)"] + generation.log + ["# final status=\(generation.finalAnalysis.status) difficulty=\(generation.finalAnalysis.difficulty) hints=\(generation.givens.count) line_solves=\(generation.finalAnalysis.lineSolves) guesses=\(generation.finalAnalysis.guesses)"] + generation.puzzleLines(picture.name)
        paragraphs.append(lines)
    }
    paragraphs.append(["# SUMMARY pictures=\(blocks.count) invalid=\(blocks.count - valid) unique=\(unique) line_logic=\(lineLogic) hinted=\(hinted) hints=\(hints)"])
    try writeLines("generated.txt", joinParagraphs(paragraphs))
}
let reports = try processPuzzles(readBlocks("input/puzzles.txt"))
try processPictures(readBlocks("input/pictures.txt"), reports)
