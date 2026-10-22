struct CommandError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

func rangeR(_ start: Int, _ count: Int) -> String {
    switch count {
    case 0: "\(start)"
    case 1: "\(start + 1)"
    default: "\(start + 1),\(start + count)"
    }
}

func rangeU(_ start: Int, _ count: Int) -> String {
    switch count {
    case 0: "\(start),0"
    case 1: "\(start + 1)"
    default: "\(start + 1),\(count)"
    }
}

func rangeM(_ start: Int, _ count: Int) -> String {
    "\(start + 1),\(count)"
}

func collapseSpaces(_ line: String) -> String {
    var result = ""
    for character in line where !(character == " " && result.last == " ") {
        result.append(character)
    }
    return result
}

func comparisonKey(_ line: String, options: [String]) -> String {
    var key = line
    if options.contains("ICASE") {
        key = key.lowercased()
    }
    if options.contains("IWHITE") {
        key = key.filter { $0 != " " }
    }
    if options.contains("ISPACE") {
        key = collapseSpaces(key)
    }
    return key
}

func matchedPairs<T: Equatable>(_ first: [T], _ second: [T]) -> [(Int, Int)] {
    let rows = first.count
    let columns = second.count
    var table = Array(repeating: Array(repeating: 0, count: columns + 1), count: rows + 1)
    for i in 0..<rows {
        for j in 0..<columns {
            table[i + 1][j + 1] =
                first[i] == second[j] ? table[i][j] + 1 : max(table[i][j + 1], table[i + 1][j])
        }
    }
    var pairs = [(rows + 1, columns + 1)]
    var i = rows
    var j = columns
    while i >= 1 && j >= 1 {
        if first[i - 1] == second[j - 1] {
            pairs.append((i, j))
            i -= 1
            j -= 1
        } else if table[i - 1][j] >= table[i][j - 1] {
            i -= 1
        } else {
            j -= 1
        }
    }
    pairs.append((0, 0))
    return pairs.reversed()
}

struct ChangeBlock {
    let p: Int
    let q: Int
    let x: Int
    let y: Int

    var letter: Character {
        if x >= 1 && y >= 1 {
            return "c"
        }
        return y == 0 ? "d" : "a"
    }
}

func changeBlocks<T: Equatable>(_ first: [T], _ second: [T]) -> [ChangeBlock] {
    let pairs = matchedPairs(first, second)
    var blocks: [ChangeBlock] = []
    for (current, next) in zip(pairs, pairs.dropFirst()) {
        if next.0 - current.0 > 1 || next.1 - current.1 > 1 {
            blocks.append(
                ChangeBlock(
                    p: current.0, q: current.1, x: next.0 - current.0 - 1, y: next.1 - current.1 - 1))
        }
    }
    return blocks
}

enum Step {
    case common(oldIndex: Int, newIndex: Int)
    case change(ChangeBlock)
}

func walk(_ blocks: [ChangeBlock], oldStart: Int, newStart: Int, oldEnd: Int) -> [Step] {
    var steps: [Step] = []
    var oldIndex = oldStart
    var newIndex = newStart
    for block in blocks {
        while oldIndex < block.p {
            steps.append(.common(oldIndex: oldIndex, newIndex: newIndex))
            oldIndex += 1
            newIndex += 1
        }
        steps.append(.change(block))
        oldIndex = block.p + block.x
        newIndex = block.q + block.y
    }
    while oldIndex < oldEnd {
        steps.append(.common(oldIndex: oldIndex, newIndex: newIndex))
        oldIndex += 1
        newIndex += 1
    }
    return steps
}

func sideRow(_ left: String, _ symbol: String, _ right: String, width: Int) -> String {
    let clipped = left.prefix(width)
    let padding = String(repeating: " ", count: width - clipped.count)
    var row = "\(clipped)\(padding) \(symbol) \(right.prefix(width))"
    while row.last == " " {
        row.removeLast()
    }
    return row
}

struct Hunk {
    let blocks: [ChangeBlock]
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int

    init(blocks: [ChangeBlock], context: Int, oldTotal: Int) {
        let first = blocks[0]
        let last = blocks[blocks.count - 1]
        let before = min(context, first.p)
        let after = min(context, oldTotal - last.p - last.x)
        self.blocks = blocks
        oldStart = first.p - before
        oldCount = last.p + last.x + after - oldStart
        newStart = first.q - before
        newCount = last.q + last.y + after - newStart
    }

    func steps() -> [Step] {
        walk(blocks, oldStart: oldStart, newStart: newStart, oldEnd: oldStart + oldCount)
    }
}

struct LineDiff {
    let oldLines: [String]
    let newLines: [String]
    let blocks: [ChangeBlock]

    init(oldLines: [String], newLines: [String], options: [String] = []) {
        self.oldLines = oldLines
        self.newLines = newLines
        blocks = changeBlocks(
            oldLines.map { comparisonKey($0, options: options) },
            newLines.map { comparisonKey($0, options: options) })
    }

    func deleted(_ block: ChangeBlock) -> ArraySlice<String> {
        oldLines[block.p..<block.p + block.x]
    }

    func inserted(_ block: ChangeBlock) -> ArraySlice<String> {
        newLines[block.q..<block.q + block.y]
    }

    func hunks(context: Int) -> [Hunk] {
        var groups: [[ChangeBlock]] = []
        for block in blocks {
            if let previous = groups.last?.last,
                block.p - (previous.p + previous.x) <= 2 * context
            {
                groups[groups.count - 1].append(block)
            } else {
                groups.append([block])
            }
        }
        return groups.map { Hunk(blocks: $0, context: context, oldTotal: oldLines.count) }
    }

    func normal() -> [String] {
        var lines: [String] = []
        for block in blocks {
            let letter = block.letter
            lines.append("\(rangeR(block.p, block.x))\(letter)\(rangeR(block.q, block.y))")
            lines += deleted(block).map { "< " + $0 }
            if letter == "c" {
                lines.append("---")
            }
            lines += inserted(block).map { "> " + $0 }
        }
        return lines
    }

    func ed() -> [String] {
        var lines: [String] = []
        for block in blocks.reversed() {
            let letter = block.letter
            lines.append("\(rangeR(block.p, block.x))\(letter)")
            if letter != "d" {
                lines += inserted(block)
                lines.append(".")
            }
        }
        return lines
    }

    func rcs() -> [String] {
        var lines: [String] = []
        for block in blocks {
            if block.x >= 1 {
                lines.append("d\(block.p + 1) \(block.x)")
            }
            if block.y >= 1 {
                lines.append("a\(block.p + block.x) \(block.y)")
                lines += inserted(block)
            }
        }
        return lines
    }

    func ifdef(_ macroName: String) -> [String] {
        var lines: [String] = []
        for step in walk(blocks, oldStart: 0, newStart: 0, oldEnd: oldLines.count) {
            switch step {
            case .common(let oldIndex, _):
                lines.append(oldLines[oldIndex])
            case .change(let block) where block.x >= 1 && block.y >= 1:
                lines.append("#ifndef \(macroName)")
                lines += deleted(block)
                lines.append("#else /* \(macroName) */")
                lines += inserted(block)
                lines.append("#endif /* \(macroName) */")
            case .change(let block) where block.y == 0:
                lines.append("#ifndef \(macroName)")
                lines += deleted(block)
                lines.append("#endif /* ! \(macroName) */")
            case .change(let block):
                lines.append("#ifdef \(macroName)")
                lines += inserted(block)
                lines.append("#endif /* \(macroName) */")
            }
        }
        return lines
    }

    func unified(context: Int, oldName: String, newName: String) -> [String] {
        var lines = ["--- \(oldName)", "+++ \(newName)"]
        for hunk in hunks(context: context) {
            let oldRange = rangeU(hunk.oldStart, hunk.oldCount)
            let newRange = rangeU(hunk.newStart, hunk.newCount)
            lines.append("@@ -\(oldRange) +\(newRange) @@")
            for step in hunk.steps() {
                switch step {
                case .common(let oldIndex, _):
                    lines.append(" " + oldLines[oldIndex])
                case .change(let block):
                    lines += deleted(block).map { "-" + $0 }
                    lines += inserted(block).map { "+" + $0 }
                }
            }
        }
        return lines
    }

    func context(_ context: Int, oldName: String, newName: String) -> [String] {
        var lines = ["*** \(oldName)", "--- \(newName)"]
        for hunk in hunks(context: context) {
            let steps = hunk.steps()
            lines.append(String(repeating: "*", count: 15))
            lines.append("*** \(rangeR(hunk.oldStart, hunk.oldCount)) ****")
            if hunk.blocks.contains(where: { $0.x >= 1 }) {
                for step in steps {
                    switch step {
                    case .common(let oldIndex, _):
                        lines.append("  " + oldLines[oldIndex])
                    case .change(let block):
                        let marker = block.y >= 1 ? "! " : "- "
                        lines += deleted(block).map { marker + $0 }
                    }
                }
            }
            lines.append("--- \(rangeR(hunk.newStart, hunk.newCount)) ----")
            if hunk.blocks.contains(where: { $0.y >= 1 }) {
                for step in steps {
                    switch step {
                    case .common(_, let newIndex):
                        lines.append("  " + newLines[newIndex])
                    case .change(let block):
                        let marker = block.x >= 1 ? "! " : "+ "
                        lines += inserted(block).map { marker + $0 }
                    }
                }
            }
        }
        return lines
    }

    func sideBySide(width: Int) -> [String] {
        var lines: [String] = []
        for step in walk(blocks, oldStart: 0, newStart: 0, oldEnd: oldLines.count) {
            switch step {
            case .common(let oldIndex, let newIndex):
                lines.append(sideRow(oldLines[oldIndex], " ", newLines[newIndex], width: width))
            case .change(let block):
                for row in 0..<max(block.x, block.y) {
                    if row < block.x && row < block.y {
                        let left = oldLines[block.p + row]
                        lines.append(sideRow(left, "|", newLines[block.q + row], width: width))
                    } else if row < block.x {
                        lines.append(sideRow(oldLines[block.p + row], "<", "", width: width))
                    } else {
                        lines.append(sideRow("", ">", newLines[block.q + row], width: width))
                    }
                }
            }
        }
        return lines
    }
}

struct TokenTotals {
    var deleted = 0
    var inserted = 0
    var common = 0
}

func splitTokens(_ line: String, byWord: Bool) -> [String] {
    if byWord {
        return line.split(separator: " ").map { String($0) }
    }
    return line.map { String($0) }
}

func deletion(_ tokens: some Sequence<String>, separator: String) -> String {
    "[-" + tokens.joined(separator: separator) + "-]"
}

func insertion(_ tokens: some Sequence<String>, separator: String) -> String {
    "{+" + tokens.joined(separator: separator) + "+}"
}

func compareTokens(
    _ oldTokens: [String], _ newTokens: [String], separator: String, totals: inout TokenTotals
) -> String {
    var parts: [String] = []
    let blocks = changeBlocks(oldTokens, newTokens)
    for step in walk(blocks, oldStart: 0, newStart: 0, oldEnd: oldTokens.count) {
        switch step {
        case .common(let oldIndex, _):
            parts.append(oldTokens[oldIndex])
            totals.common += 1
        case .change(let block):
            if block.x >= 1 {
                parts.append(deletion(oldTokens[block.p..<block.p + block.x], separator: separator))
            }
            if block.y >= 1 {
                parts.append(insertion(newTokens[block.q..<block.q + block.y], separator: separator))
            }
            totals.deleted += block.x
            totals.inserted += block.y
        }
    }
    return parts.joined(separator: separator)
}

struct PatchHunk {
    static let offsets = [0, 1, -1, 2, -2, 3, -3]

    let lineNumber: Int
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    var body: [(kind: Character, text: String)] = []

    var leadingContext: Int {
        body.prefix { $0.kind == " " }.count
    }

    var trailingContext: Int {
        body.reversed().prefix { $0.kind == " " }.count
    }

    func texts(_ changeKind: Character) -> [String] {
        body.filter { $0.kind == " " || $0.kind == changeKind }.map { $0.text }
    }

    func sequences(reverse: Bool) -> (old: [String], new: [String]) {
        reverse ? (texts("+"), texts("-")) : (texts("-"), texts("+"))
    }

    func start(reverse: Bool) -> Int {
        reverse ? newStart : oldStart
    }
}

struct HunkMatch {
    let fuzz: Int
    let delta: Int
    let position: Int
    let lines: [String]

    func report(number: Int) -> String {
        var text = "Hunk #\(number) succeeded at \(position + 1)"
        if fuzz >= 1 {
            text += " with fuzz \(fuzz)"
        }
        if delta == 1 || delta == -1 {
            text += " (offset \(delta) line)"
        } else if delta != 0 {
            text += " (offset \(delta) lines)"
        }
        return text
    }
}

func parseNumber(_ text: Substring) -> Int? {
    guard (1...4).contains(text.count), text.allSatisfy({ ("0"..."9").contains($0) }) else {
        return nil
    }
    return Int(text)
}

func parseNumberPair(_ text: Substring) -> (first: Int, second: Int?)? {
    let parts = text.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count <= 2, let first = parseNumber(parts[0]) else {
        return nil
    }
    if parts.count == 1 {
        return (first, nil)
    }
    guard let second = parseNumber(parts[1]) else {
        return nil
    }
    return (first, second)
}

func parseRange(_ text: Substring, sign: Character) -> (start: Int, count: Int)? {
    guard text.first == sign, let pair = parseNumberPair(text.dropFirst()) else {
        return nil
    }
    let count = pair.second ?? 1
    if pair.first == 0 && count != 0 {
        return nil
    }
    return (pair.first, count)
}

func parseHunkHeader(_ line: String, lineNumber: Int) throws(CommandError) -> PatchHunk {
    let parts = line.split(separator: " ", omittingEmptySubsequences: false)
    guard parts.count == 4, parts[0] == "@@", parts[3] == "@@",
        let oldRange = parseRange(parts[1], sign: "-"),
        let newRange = parseRange(parts[2], sign: "+")
    else {
        throw CommandError("PATCH ERROR line \(lineNumber): bad hunk header")
    }
    return PatchHunk(
        lineNumber: lineNumber, oldStart: oldRange.start, oldCount: oldRange.count,
        newStart: newRange.start, newCount: newRange.count)
}

func parsePatch(_ patchLines: [String]) throws(CommandError) -> [PatchHunk] {
    guard var index = patchLines.firstIndex(where: { $0.hasPrefix("@@") }) else {
        throw CommandError("PATCH ERROR no hunks")
    }
    var hunks: [PatchHunk] = []
    while index < patchLines.count {
        var hunk = try parseHunkHeader(patchLines[index], lineNumber: index + 1)
        index += 1
        var oldSeen = 0
        var newSeen = 0
        while oldSeen < hunk.oldCount || newSeen < hunk.newCount {
            guard index < patchLines.count else {
                throw CommandError("PATCH ERROR line \(hunk.lineNumber): truncated hunk")
            }
            let line = patchLines[index]
            let kind = line[line.startIndex]
            let inOld = kind == " " || kind == "-"
            let inNew = kind == " " || kind == "+"
            if line.count < 2 || !(inOld || inNew) || (inOld && oldSeen == hunk.oldCount)
                || (inNew && newSeen == hunk.newCount)
            {
                throw CommandError("PATCH ERROR line \(index + 1): bad hunk line")
            }
            hunk.body.append((kind, String(line.dropFirst())))
            if inOld {
                oldSeen += 1
            }
            if inNew {
                newSeen += 1
            }
            index += 1
        }
        if hunk.body.allSatisfy({ $0.kind == " " }) {
            throw CommandError("PATCH ERROR line \(hunk.lineNumber): no changes")
        }
        hunks.append(hunk)
    }
    return hunks
}

func searchHunk(
    _ hunk: PatchHunk, in lines: [String], adjustment: Int, reverse: Bool, maxFuzz: Int
) -> HunkMatch? {
    let (oldLines, newLines) = hunk.sequences(reverse: reverse)
    let start = hunk.start(reverse: reverse)
    let expected = oldLines.isEmpty ? start + adjustment : start - 1 + adjustment
    let leading = hunk.leadingContext
    let trailing = hunk.trailingContext
    for fuzz in 0...maxFuzz {
        let head = min(fuzz, leading)
        let tail = min(fuzz, trailing)
        let oldPart = oldLines[head..<(oldLines.count - tail)]
        let newPart = newLines[head..<(newLines.count - tail)]
        for delta in PatchHunk.offsets {
            let position = expected + head + delta
            let end = position + oldPart.count
            guard position >= 0, end <= lines.count, lines[position..<end] == oldPart else {
                continue
            }
            var result = Array(lines[..<position])
            result += newPart
            result += lines[end...]
            return HunkMatch(fuzz: fuzz, delta: delta, position: position, lines: result)
        }
    }
    return nil
}

func parseEditCommand(_ line: String) -> (instruction: Character, first: Int, last: Int)? {
    guard let instruction = line.last, let pair = parseNumberPair(line.dropLast()) else {
        return nil
    }
    guard "acd".contains(instruction), !(instruction == "a" && pair.second != nil) else {
        return nil
    }
    return (instruction, pair.first, pair.second ?? pair.first)
}

func runEditScript(
    _ original: [String], script: [String]
) throws(CommandError) -> (lines: [String], executed: Int) {
    var lines = original
    var executed = 0
    var index = 0
    while index < script.count {
        let lineNumber = index + 1
        guard let command = parseEditCommand(script[index]) else {
            throw CommandError("EDIT ERROR line \(lineNumber): bad command")
        }
        let (instruction, first, last) = command
        let valid =
            instruction == "a"
            ? first <= lines.count
            : 1 <= first && first <= last && last <= lines.count
        guard valid else {
            throw CommandError("EDIT ERROR line \(lineNumber): bad range")
        }
        index += 1
        var text: ArraySlice<String> = []
        if instruction != "d" {
            guard let end = script[index...].firstIndex(of: ".") else {
                throw CommandError("EDIT ERROR line \(lineNumber): missing terminator")
            }
            text = script[index..<end]
            index = end + 1
        }
        switch instruction {
        case "a":
            lines.insert(contentsOf: text, at: first)
        case "c":
            lines.replaceSubrange(first - 1..<last, with: text)
        default:
            lines.removeSubrange(first - 1..<last)
        }
        executed += 1
    }
    return (lines, executed)
}

enum ChunkKind: String {
    case stable, a, b, both, conflict
}

struct Chunk {
    let kind: ChunkKind
    let baseStart: Int
    let oursStart: Int
    let theirsStart: Int
    let base: [String]
    let ours: [String]
    let theirs: [String]

    var location: String {
        "base \(rangeM(baseStart, base.count)) a \(rangeM(oursStart, ours.count))"
            + " b \(rangeM(theirsStart, theirs.count))"
    }
}

func chunkKind(_ base: [String], _ ours: [String], _ theirs: [String]) -> ChunkKind {
    if ours == base {
        return .b
    }
    if theirs == base {
        return .a
    }
    return ours == theirs ? .both : .conflict
}

func matchTable(_ first: [String], _ second: [String]) -> [Int] {
    var matches = Array(repeating: 0, count: first.count + 2)
    for (i, j) in matchedPairs(first, second).dropFirst().dropLast() {
        matches[i] = j
    }
    return matches
}

func threeWayChunks(base: [String], ours: [String], theirs: [String]) -> [Chunk] {
    let oursMatch = matchTable(base, ours)
    let theirsMatch = matchTable(base, theirs)
    var chunks: [Chunk] = []
    var x = 0
    var y = 0
    var z = 0
    while x < base.count || y < ours.count || z < theirs.count {
        if x < base.count && oursMatch[x + 1] == y + 1 && theirsMatch[x + 1] == z + 1 {
            chunks.append(
                Chunk(
                    kind: .stable, baseStart: x, oursStart: y, theirsStart: z,
                    base: [base[x]], ours: [ours[y]], theirs: [theirs[z]]))
            x += 1
            y += 1
            z += 1
            continue
        }
        var anchor = x + 1
        while anchor <= base.count && (oursMatch[anchor] == 0 || theirsMatch[anchor] == 0) {
            anchor += 1
        }
        let (nextX, nextY, nextZ) =
            anchor <= base.count
            ? (anchor - 1, oursMatch[anchor] - 1, theirsMatch[anchor] - 1)
            : (base.count, ours.count, theirs.count)
        let basePart = Array(base[x..<nextX])
        let oursPart = Array(ours[y..<nextY])
        let theirsPart = Array(theirs[z..<nextZ])
        chunks.append(
            Chunk(
                kind: chunkKind(basePart, oursPart, theirsPart), baseStart: x, oursStart: y,
                theirsStart: z, base: basePart, ours: oursPart, theirs: theirsPart))
        (x, y, z) = (nextX, nextY, nextZ)
    }
    return chunks
}

func kindCounts(_ chunks: [Chunk]) -> String {
    func count(_ kind: ChunkKind) -> Int {
        chunks.filter { $0.kind == kind }.count
    }
    return "a=\(count(.a)) b=\(count(.b)) both=\(count(.both)) conflicts=\(count(.conflict))"
}

func commonPrefixLength(_ first: [String], _ second: [String]) -> Int {
    var length = 0
    while length < first.count && length < second.count && first[length] == second[length] {
        length += 1
    }
    return length
}

func commonSuffixLength(_ first: [String], _ second: [String], limit: Int) -> Int {
    var length = 0
    while length < limit && first[first.count - 1 - length] == second[second.count - 1 - length] {
        length += 1
    }
    return length
}

func conflictLines(
    _ chunk: Chunk, mode: String, baseName: String, oursName: String, theirsName: String
) -> [String] {
    let ours = chunk.ours
    let theirs = chunk.theirs
    switch mode {
    case "OURS":
        return ours
    case "THEIRS":
        return theirs
    case "DIFF3":
        var lines = ["<<<<<<< \(oursName)"]
        lines += ours
        lines.append("||||||| \(baseName)")
        lines += chunk.base
        lines.append(Marker.separatorLine)
        lines += theirs
        lines.append(">>>>>>> \(theirsName)")
        return lines
    default:
        break
    }
    let head = commonPrefixLength(ours, theirs)
    let tail = commonSuffixLength(ours, theirs, limit: min(ours.count, theirs.count) - head)
    let oursMiddle = ours[head..<(ours.count - tail)]
    let theirsMiddle = theirs[head..<(theirs.count - tail)]
    var lines = Array(ours[..<head])
    if mode == "UNION" {
        lines += oursMiddle
        lines += theirsMiddle
    } else {
        lines.append("<<<<<<< \(oursName)")
        lines += oursMiddle
        lines.append(Marker.separatorLine)
        lines += theirsMiddle
        lines.append(">>>>>>> \(theirsName)")
    }
    lines += ours[(ours.count - tail)...]
    return lines
}

enum Marker {
    case start, base, separator, end

    static let separatorLine = "======="

    init?(line: String) {
        if line == Marker.separatorLine {
            self = .separator
            return
        }
        guard line.count == 7 || (line.count > 7 && line.dropFirst(7).first == " ") else {
            return nil
        }
        switch line.prefix(7) {
        case "<<<<<<<": self = .start
        case "|||||||": self = .base
        case ">>>>>>>": self = .end
        default: return nil
        }
    }
}

func marker(_ lines: [String], at index: Int) -> Marker? {
    index < lines.count ? Marker(line: lines[index]) : nil
}

func nextMarker(_ lines: [String], after index: Int) -> Int {
    var next = index + 1
    while next < lines.count && Marker(line: lines[next]) == nil {
        next += 1
    }
    return next
}

struct ConflictRegion {
    let start: Int
    let end: Int
    let ours: [String]
    let base: [String]?
    let theirs: [String]

    func part(_ side: String) -> [String] {
        switch side {
        case "OURS": ours
        case "THEIRS": theirs
        case "BASE": base ?? []
        default: ours + theirs
        }
    }
}

func region(_ lines: [String], at start: Int) -> ConflictRegion? {
    guard marker(lines, at: start) == .start else {
        return nil
    }
    var middle = nextMarker(lines, after: start)
    var baseMarker: Int?
    if marker(lines, at: middle) == .base {
        baseMarker = middle
        middle = nextMarker(lines, after: middle)
    }
    guard marker(lines, at: middle) == .separator else {
        return nil
    }
    let end = nextMarker(lines, after: middle)
    guard marker(lines, at: end) == .end else {
        return nil
    }
    return ConflictRegion(
        start: start + 1,
        end: end + 1,
        ours: Array(lines[(start + 1)..<(baseMarker ?? middle)]),
        base: baseMarker.map { Array(lines[($0 + 1)..<middle]) },
        theirs: Array(lines[(middle + 1)..<end]))
}

func conflictRegions(_ lines: [String]) -> [ConflictRegion] {
    var regions: [ConflictRegion] = []
    var index = 0
    while index < lines.count {
        if let found = region(lines, at: index) {
            regions.append(found)
            index = found.end
        } else {
            index += 1
        }
    }
    return regions
}

struct Workspace {
    static let dataCommands: Set<String> = ["FILE", "PATCH", "EDIT"]
    static let formatsWithArgument: Set<String> = ["IFDEF", "UNIFIED", "CONTEXT", "SIDE"]
    static let graphWidth = 20

    private var files: [String: [String]] = [:]
    private var history: [String: [[String]?]] = [:]
    private(set) var output: [String] = []

    private func contents(of name: String) throws(CommandError) -> [String] {
        guard let lines = files[name] else {
            throw CommandError("ERROR no such file \(name)")
        }
        return lines
    }

    private mutating func save(_ name: String, _ lines: [String]) {
        history[name, default: []].append(files[name])
        files[name] = lines
    }

    private mutating func loadFile(_ arguments: [String], data: [String]) {
        let name = arguments[0]
        save(name, data)
        output.append("FILE \(name) lines=\(data.count)")
    }

    private mutating func copy(_ arguments: [String]) throws(CommandError) {
        let source = arguments[0]
        let target = arguments[1]
        let lines = try contents(of: source)
        save(target, lines)
        output.append("COPY \(source) \(target) lines=\(lines.count)")
    }

    private mutating func printFile(_ arguments: [String]) throws(CommandError) {
        let name = arguments[0]
        let lines = try contents(of: name)
        output.append("PRINT \(name) lines=\(lines.count)")
        for (index, line) in lines.enumerated() {
            let number = String(index + 1)
            let padding = String(repeating: " ", count: max(0, 3 - number.count))
            output.append("\(padding)\(number)| \(line)")
        }
    }

    private mutating func listFiles() {
        output.append("FILES count=\(files.count)")
        for (name, lines) in files.sorted(by: { $0.key < $1.key }) {
            output.append("\(name) lines=\(lines.count) undo=\(history[name, default: []].count)")
        }
    }

    private mutating func undo(_ arguments: [String]) throws(CommandError) {
        let name = arguments[0]
        guard let state = history[name]?.popLast() else {
            throw CommandError("ERROR nothing to undo \(name)")
        }
        if let lines = state {
            files[name] = lines
            output.append("UNDO \(name) lines=\(lines.count)")
        } else {
            files[name] = nil
            output.append("UNDO \(name) removed")
        }
    }

    private mutating func diff(_ arguments: [String]) throws(CommandError) {
        let oldName = arguments[0]
        let newName = arguments[1]
        let form = arguments[2]
        let oldLines = try contents(of: oldName)
        let newLines = try contents(of: newName)
        let hasParameter = Workspace.formatsWithArgument.contains(form)
        let parameter = hasParameter ? arguments[3] : ""
        let options = Array(arguments.dropFirst(hasParameter ? 4 : 3))
        let diff = LineDiff(oldLines: oldLines, newLines: newLines, options: options)
        if diff.blocks.isEmpty {
            output.append("Files \(oldName) and \(newName) are identical")
            return
        }
        switch form {
        case "BRIEF":
            output.append("Files \(oldName) and \(newName) differ")
        case "NORMAL":
            output += diff.normal()
        case "ED":
            output += diff.ed()
        case "RCS":
            output += diff.rcs()
        case "IFDEF":
            output += diff.ifdef(parameter)
        case "UNIFIED":
            output += diff.unified(context: Int(parameter)!, oldName: oldName, newName: newName)
        case "CONTEXT":
            output += diff.context(Int(parameter)!, oldName: oldName, newName: newName)
        default:
            output += diff.sideBySide(width: Int(parameter)!)
        }
    }

    private mutating func tokenDiff(_ arguments: [String], byWord: Bool) throws(CommandError) {
        let oldName = arguments[0]
        let newName = arguments[1]
        let oldLines = try contents(of: oldName)
        let newLines = try contents(of: newName)
        let diff = LineDiff(oldLines: oldLines, newLines: newLines)
        if diff.blocks.isEmpty {
            output.append("Files \(oldName) and \(newName) are identical")
            return
        }
        let separator = byWord ? " " : ""
        var totals = TokenTotals()
        for block in diff.blocks {
            for row in 0..<max(block.x, block.y) {
                let oldNumber = block.p + row + 1
                let newNumber = block.q + row + 1
                if row < block.x && row < block.y {
                    let oldTokens = splitTokens(oldLines[oldNumber - 1], byWord: byWord)
                    let newTokens = splitTokens(newLines[newNumber - 1], byWord: byWord)
                    let text = compareTokens(
                        oldTokens, newTokens, separator: separator, totals: &totals)
                    output.append("a\(oldNumber) b\(newNumber): \(text)")
                } else if row < block.x {
                    let oldTokens = splitTokens(oldLines[oldNumber - 1], byWord: byWord)
                    totals.deleted += oldTokens.count
                    output.append("a\(oldNumber): \(deletion(oldTokens, separator: separator))")
                } else {
                    let newTokens = splitTokens(newLines[newNumber - 1], byWord: byWord)
                    totals.inserted += newTokens.count
                    output.append("b\(newNumber): \(insertion(newTokens, separator: separator))")
                }
            }
        }
        let label = byWord ? "WORDS" : "CHARS"
        output.append(
            "\(label) deleted=\(totals.deleted) inserted=\(totals.inserted) common=\(totals.common)")
    }

    private static func statGraph(inserted: Int, deleted: Int) -> String {
        let total = inserted + deleted
        var plus = inserted
        var minus = deleted
        if total > graphWidth {
            plus = graphWidth * inserted / total
            minus = graphWidth * deleted / total
            if inserted >= 1 && plus == 0 {
                plus = 1
            }
            if deleted >= 1 && minus == 0 {
                minus = 1
            }
        }
        return String(repeating: "+", count: plus) + String(repeating: "-", count: minus)
    }

    private mutating func stat(_ arguments: [String]) throws(CommandError) {
        let oldName = arguments[0]
        let newName = arguments[1]
        let oldLines = try contents(of: oldName)
        let newLines = try contents(of: newName)
        let options = Array(arguments.dropFirst(2))
        let diff = LineDiff(oldLines: oldLines, newLines: newLines, options: options)
        let deleted = diff.blocks.reduce(0) { $0 + $1.x }
        let inserted = diff.blocks.reduce(0) { $0 + $1.y }
        let total = deleted + inserted
        let unchanged = oldLines.count - deleted
        var summary = "\(oldName) -> \(newName) | \(total)"
        if total > 0 {
            summary += " " + Workspace.statGraph(inserted: inserted, deleted: deleted)
        }
        output.append(summary)
        let lineTotal = oldLines.count + newLines.count
        let similarity = lineTotal > 0 ? 200 * unchanged / lineTotal : 100
        output.append(
            "changes=\(diff.blocks.count) insertions=\(inserted) deletions=\(deleted)"
                + " unchanged=\(unchanged) similarity=\(similarity)%")
    }

    private mutating func patch(_ arguments: [String], data: [String]) throws(CommandError) {
        let name = arguments[0]
        var lines = try contents(of: name)
        let options = Array(arguments.dropFirst(2))
        let reverse = options.contains("REVERSE")
        let dryRun = options.contains("DRYRUN")
        let maxFuzz = options.firstIndex(of: "FUZZ").map { Int(options[$0 + 1])! } ?? 0
        let hunks = try parsePatch(data)
        output.append((dryRun ? "checking file " : "patching file ") + name)
        let first = hunks[0]
        if searchHunk(first, in: lines, adjustment: 0, reverse: reverse, maxFuzz: maxFuzz) == nil
            && searchHunk(first, in: lines, adjustment: 0, reverse: !reverse, maxFuzz: maxFuzz)
                != nil
        {
            output.append("Reversed (or previously applied) patch detected! Skipping patch.")
            output.append("RESULT applied=0 failed=0 ignored=\(hunks.count) lines=\(lines.count)")
            return
        }
        var adjustment = 0
        var applied = 0
        var failed = 0
        for (index, hunk) in hunks.enumerated() {
            guard
                let match = searchHunk(
                    hunk, in: lines, adjustment: adjustment, reverse: reverse, maxFuzz: maxFuzz)
            else {
                failed += 1
                output.append("Hunk #\(index + 1) FAILED at \(hunk.start(reverse: reverse))")
                continue
            }
            let (oldLines, newLines) = hunk.sequences(reverse: reverse)
            lines = match.lines
            adjustment += match.delta + newLines.count - oldLines.count
            applied += 1
            output.append(match.report(number: index + 1))
        }
        output.append("RESULT applied=\(applied) failed=\(failed) ignored=0 lines=\(lines.count)")
        if !dryRun && applied >= 1 {
            save(name, lines)
        }
    }

    private mutating func edit(_ arguments: [String], data: [String]) throws(CommandError) {
        let name = arguments[0]
        let original = try contents(of: name)
        let (lines, executed) = try runEditScript(original, script: data)
        output.append("EDIT \(name) commands=\(executed) lines=\(lines.count)")
        save(name, lines)
    }

    private func threeWay(
        _ baseName: String, _ oursName: String, _ theirsName: String
    ) throws(CommandError) -> [Chunk] {
        let base = try contents(of: baseName)
        let ours = try contents(of: oursName)
        let theirs = try contents(of: theirsName)
        return threeWayChunks(base: base, ours: ours, theirs: theirs)
    }

    private mutating func diff3(_ arguments: [String]) throws(CommandError) {
        let chunks = try threeWay(arguments[0], arguments[1], arguments[2])
        let changes = chunks.filter { $0.kind != .stable }
        for chunk in changes {
            output.append("==== \(chunk.kind.rawValue) \(chunk.location)")
            output += chunk.base.map { "O " + $0 }
            if chunk.kind != .b {
                output += chunk.ours.map { "A " + $0 }
            }
            if chunk.kind == .b || chunk.kind == .conflict {
                output += chunk.theirs.map { "B " + $0 }
            }
        }
        output.append("DIFF3 chunks=\(changes.count) \(kindCounts(chunks))")
    }

    private mutating func merge(_ arguments: [String]) throws(CommandError) {
        let baseName = arguments[0]
        let oursName = arguments[1]
        let theirsName = arguments[2]
        let target = arguments[3]
        let mode = arguments.count == 5 ? arguments[4] : "MARKERS"
        let chunks = try threeWay(baseName, oursName, theirsName)
        var result: [String] = []
        var conflicts: [Chunk] = []
        for chunk in chunks {
            switch chunk.kind {
            case .b:
                result += chunk.theirs
            case .conflict:
                result += conflictLines(
                    chunk, mode: mode, baseName: baseName, oursName: oursName,
                    theirsName: theirsName)
                conflicts.append(chunk)
            default:
                result += chunk.ours
            }
        }
        output.append("MERGE \(target) lines=\(result.count) \(kindCounts(chunks))")
        for (index, chunk) in conflicts.enumerated() {
            output.append("CONFLICT \(index + 1) \(chunk.location)")
        }
        save(target, result)
    }

    private mutating func conflicts(_ arguments: [String]) throws(CommandError) {
        let name = arguments[0]
        let lines = try contents(of: name)
        let regions = conflictRegions(lines)
        output.append("CONFLICTS \(name) count=\(regions.count)")
        for (index, region) in regions.enumerated() {
            let base = region.base.map { String($0.count) } ?? "none"
            output.append(
                "\(index + 1): lines \(region.start)-\(region.end) ours=\(region.ours.count)"
                    + " base=\(base) theirs=\(region.theirs.count)")
        }
    }

    private mutating func resolve(_ arguments: [String]) throws(CommandError) {
        let name = arguments[0]
        let side = arguments[2]
        let lines = try contents(of: name)
        let number = Int(arguments[1])!
        let regions = conflictRegions(lines)
        guard number <= regions.count else {
            throw CommandError("ERROR no conflict \(number) in \(name)")
        }
        let region = regions[number - 1]
        if side == "BASE" && region.base == nil {
            throw CommandError("ERROR no base section in conflict \(number)")
        }
        var content = Array(lines[..<(region.start - 1)])
        content += region.part(side)
        content += lines[region.end...]
        let remaining = conflictRegions(content).count
        output.append("RESOLVE \(name) \(number) \(side) lines=\(content.count) remaining=\(remaining)")
        save(name, content)
    }

    mutating func execute(_ words: [String], data: [String]) {
        let arguments = Array(words.dropFirst())
        do throws(CommandError) {
            switch words[0] {
            case "FILE":
                loadFile(arguments, data: data)
            case "COPY":
                try copy(arguments)
            case "PRINT":
                try printFile(arguments)
            case "FILES":
                listFiles()
            case "DIFF":
                try diff(arguments)
            case "WORDDIFF":
                try tokenDiff(arguments, byWord: true)
            case "CHARDIFF":
                try tokenDiff(arguments, byWord: false)
            case "STAT":
                try stat(arguments)
            case "PATCH":
                try patch(arguments, data: data)
            case "EDIT":
                try edit(arguments, data: data)
            case "DIFF3":
                try diff3(arguments)
            case "MERGE":
                try merge(arguments)
            case "CONFLICTS":
                try conflicts(arguments)
            case "RESOLVE":
                try resolve(arguments)
            case "UNDO":
                try undo(arguments)
            default:
                preconditionFailure("unknown command \(words[0])")
            }
        } catch {
            output.append(error.message)
        }
    }
}

var input: [String] = []
while let line = readLine() {
    input.append(line)
}
var workspace = Workspace()
var position = 1
for _ in 0..<Int(input[0])! {
    let words = input[position].split(separator: " ", omittingEmptySubsequences: false)
        .map { String($0) }
    position += 1
    var data: [String] = []
    if Workspace.dataCommands.contains(words[0]) {
        let count = Int(words[2])!
        data = Array(input[position..<position + count])
        position += count
    }
    workspace.execute(words, data: data)
}
print(workspace.output.joined(separator: "\n"))
