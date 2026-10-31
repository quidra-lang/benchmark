import Foundation

func readLines(_ name: String) throws -> [String] {
    var lines = try String(contentsOfFile: "input/" + name, encoding: .utf8).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}
func yearStart(_ year: Int) -> Int { dayNumber(year, 1, 1) * secondsPerDay }
func clockSeconds(_ text: String) -> Int { let fields = text.split(separator: ":"); return Int(fields[0])! * 3600 + Int(fields[1])! * 60 }
func namesOrNone(_ names: [String], _ separator: String) -> String { names.isEmpty ? "none" : names.joined(separator: separator) }
func indented(_ lines: [String]) -> [String] { lines.enumerated().map { $0.offset == 0 ? $0.element : "  " + $0.element } }
func mergeIntervals(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
    var merged: [(Int, Int)] = []
    for (low, high) in intervals.sorted(by: { ($0.0, $0.1) < ($1.0, $1.1) }) {
        if let last = merged.last, low <= last.1 { merged[merged.count - 1].1 = max(last.1, high) }
        else { merged.append((low, high)) }
    }
    return merged
}
func intersectIntervals(_ first: [(Int, Int)], _ second: [(Int, Int)]) -> [(Int, Int)] {
    var pieces: [(Int, Int)] = []
    for (a, b) in first { for (c, d) in second { let low = max(a, c), high = min(b, d); if low < high { pieces.append((low, high)) } } }
    return mergeIntervals(pieces)
}
enum LineKind: Equatable { case rule, zone, continuation, link, unknown }
final class SourceLine {
    let number: Int
    let fields: [String]
    let kind: LineKind
    var block: Int?
    var position = 0
    var zoneLine: ZoneLine?
    var fieldError = false
    var error: String?
    init(_ number: Int, _ content: String) {
        let fields = splitFields(content)
        self.number = number; self.fields = fields
        if content.hasPrefix(" ") { kind = .continuation }
        else { switch fields[0] { case "Rule": kind = .rule; case "Zone": kind = .zone; case "Link": kind = .link; default: kind = .unknown } }
    }
    var acceptsContinuation: Bool { kind == .zone && fields.count >= 6 || kind == .continuation && fields.count >= 4 }
}
final class Block {
    let name: String
    let number: Int
    var lines: [Int] = []
    var defined = false
    init(_ first: SourceLine) { name = first.fields[1]; number = first.number }
}
struct ZoneLine {
    let stdoff: Int
    let rulesText: String
    let ruleSet: String?
    let save: Int
    let format: String
    let until: Until?
    var start = negativeInfinity
    var end = positiveInfinity
    init(_ fields: [String]) throws {
        stdoff = try parseStdoff(fields[0])
        let rulesText = fields[1]
        var ruleSet: String? = nil, save = 0
        if (48...57).contains(rulesText.utf8.first!) { save = try parseSave(rulesText) }
        else if rulesText != "-" { ruleSet = rulesText }
        try checkFormat(fields[2], ruleSet != nil)
        let until: Until?
        if fields.count > 3 { until = try parseUntil(Array(fields.dropFirst(3))) } else { until = nil }
        self.rulesText = rulesText; self.ruleSet = ruleSet; self.save = save; format = fields[2]; self.until = until
    }
    var rulesNotation: String { if let ruleSet = ruleSet { return ruleSet }; return rulesText == "-" ? "-" : clockText(save) }
    var untilNotation: String { let value = until!; return "\(value.yearText) \(value.monthText) \(value.dayText) \(clockText(value.time))\(value.timeType)" }
}
final class Zone {
    let name: String
    let lines: [ZoneLine]
    var aliases: [String] = []
    let applied: [Int: Int]
    let timeline: Timeline
    init(_ name: String, _ lines: [ZoneLine], _ applied: [Int: Int], _ timeline: Timeline) { self.name = name; self.lines = lines; self.applied = applied; self.timeline = timeline }
    var ruleSets: [String] {
        var names: [String] = []
        for line in lines { if let name = line.ruleSet, !names.contains(name) { names.append(name) } }
        return names
    }
    func lineNumberAt(_ time: Int) -> Int { lines.firstIndex { $0.start <= time && time < $0.end }! + 1 }
}
func parseRule(_ line: SourceLine) throws -> Rule {
    let fields = line.fields, from = try parseYear(line.fields[2]), to = try parseTo(line.fields[3], from)
    if fields[4] != "-" { throw FieldError.invalid("syntax error") }
    let month = try parseMonth(fields[5]), day = try parseDaySpec(fields[6], month)
    let (at, kind) = try parseTime(fields[7])
    let save = try parseSave(fields[8]), letter = try parseLetter(fields[9])
    return Rule(number: line.number, fields: fields, name: fields[1], fromYear: from, toYear: to, month: month, day: day, at: at, atType: kind, save: save, letter: letter)
}
final class Database {
    var lines: [SourceLine] = []
    var blocks: [Block] = []
    var rules: [Rule] = []
    var ruleSets: [String: [Int]] = [:]
    var ruleOrder: [String] = []
    var sequences: [String: [RuleInstance]] = [:]
    var zones: [String: Zone] = [:]
    var aliases: [String: String] = [:]
    init(_ rawLines: [String]) throws {
        for (index, raw) in rawLines.enumerated() { let content = lineContent(raw); if !content.isEmpty { lines.append(SourceLine(index + 1, content)) } }
        assembleBlocks()
        for index in lines.indices {
            do { try parseFields(index) }
            catch FieldError.invalid(let message) { lines[index].fieldError = true; lines[index].error = message }
        }
        var zoneNames = Set<String>()
        for index in lines.indices { if lines[index].zoneLine != nil { lines[index].error = structuralError(index, &zoneNames) } }
        for name in ruleOrder { sequences[name] = instanceSequence(rules, ruleSets[name]!) }
        for block in blocks {
            block.defined = block.lines.allSatisfy { lines[$0].error == nil }
            if block.defined { let zone = defineZone(block); zones[zone.name] = zone }
        }
        for line in lines { if line.kind == .link && line.error == nil { registerLink(line) } }
    }
    func assembleBlocks() {
        var previous: Int? = nil
        for index in lines.indices {
            let line = lines[index]
            var block: Int? = nil
            if line.kind == .zone { blocks.append(Block(line)); block = blocks.count - 1 }
            else if line.kind == .continuation, let previous = previous, lines[previous].acceptsContinuation { block = lines[previous].block }
            if let block = block { line.block = block; line.position = blocks[block].lines.count; blocks[block].lines.append(index) }
            previous = index
        }
    }
    func parseFields(_ index: Int) throws {
        let line = lines[index]
        if line.kind == .unknown || line.kind == .continuation && line.block == nil { throw FieldError.invalid("syntax error") }
        let bounds: ClosedRange<Int>
        switch line.kind { case .rule: bounds = 10...10; case .zone: bounds = 5...9; case .continuation: bounds = 3...7; case .link: bounds = 3...3; case .unknown: bounds = 0...0 }
        if !bounds.contains(line.fields.count) { throw FieldError.invalid("syntax error") }
        switch line.kind {
        case .rule:
            let rule = try parseRule(line)
            if ruleSets[rule.name] == nil { ruleOrder.append(rule.name) }
            ruleSets[rule.name, default: []].append(rules.count); rules.append(rule)
        case .zone: line.zoneLine = try ZoneLine(Array(line.fields.dropFirst(2)))
        case .continuation: line.zoneLine = try ZoneLine(line.fields)
        default: break
        }
    }
    func structuralError(_ index: Int, _ names: inout Set<String>) -> String? {
        let line = lines[index], zoneLine = line.zoneLine!
        if line.kind == .zone && !names.insert(line.fields[1]).inserted { return "duplicate zone " + line.fields[1] }
        if let name = zoneLine.ruleSet, ruleSets[name] == nil { return "unknown rule " + name }
        guard let until = zoneLine.until else { return nil }
        let block = blocks[line.block!]
        if line.kind == .continuation {
            let previous = lines[block.lines[line.position - 1]]
            if !previous.fieldError && until.value <= previous.zoneLine!.until!.value { return "until not increasing" }
        }
        return line.position + 1 == block.lines.count ? "missing continuation" : nil
    }
    func defineZone(_ block: Block) -> Zone {
        var zoneLines = block.lines.map { lines[$0].zoneLine! }
        var applied: [Int: Int] = [:], switches: [Period] = []
        var start = negativeInfinity
        for position in zoneLines.indices {
            var line = zoneLines[position]
            line.start = start
            var lineSwitches: [(Int, Int, String)] = []
            if let name = line.ruleSet {
                let instances = sequences[name]!, run = runInstances(instances, rules, line.stdoff, start, line.until)
                line.end = run.end
                if let index = run.lastPreStart { lineSwitches.append((start, rules[index].save, rules[index].letter)) }
                else { let letter = instances.first { rules[$0.rule].save == 0 }.map { rules[$0.rule].letter } ?? ""; lineSwitches.append((start, 0, letter)) }
                for (time, index) in run.applied { let rule = rules[index]; lineSwitches.append((time, rule.save, rule.letter)); applied[rule.number, default: 0] += 1 }
            } else {
                if let until = line.until { line.end = until.value - adjustment(until.timeType, line.stdoff, line.save) }
                lineSwitches.append((start, line.save, ""))
            }
            for (time, save, letter) in lineSwitches { switches.append(Period(start: time, offset: line.stdoff + save, dst: save != 0, abbreviation: abbreviation(line.format, save, letter))) }
            start = line.end; zoneLines[position] = line
        }
        var periods: [Period] = []
        for period in switches { if periods.last.map({ !$0.sameState(period) }) ?? true { periods.append(period) } }
        return Zone(block.name, zoneLines, applied, Timeline(periods: periods))
    }
    func registerLink(_ line: SourceLine) {
        let target = line.fields[1], alias = line.fields[2]
        if zones[target] == nil { line.error = "unknown link target " + target }
        else if zones[alias] != nil || aliases[alias] != nil { line.error = "duplicate link " + alias }
        else { aliases[alias] = target; zones[target]!.aliases.append(alias) }
    }
    func findZone(_ word: String) -> Zone? { zones[word] ?? aliases[word].flatMap { zones[$0] } }
    var errorLines: [String] { lines.compactMap { line in line.error.map { "line \(line.number): \($0)" } } }
}
func offsetShift(_ timeline: Timeline, _ index: Int) -> Int { timeline.periods[index].offset - timeline.periods[index - 1].offset }
func transitionsBetween(_ timeline: Timeline, _ low: Int, _ high: Int) -> [Int] { (1..<timeline.periods.count).filter { low <= timeline.periods[$0].start && timeline.periods[$0].start < high } }
func changeAt(_ timeline: Timeline, _ index: Int) -> String { changeText(timeline.periods[index].start, timeline.periods[index - 1], timeline.periods[index]) }
func transitionLine(_ timeline: Timeline, _ index: Int) -> String {
    let time = timeline.periods[index].start, shift = offsetShift(timeline, index)
    let kind = shift > 0 ? "gap " + durationText(shift) : (shift < 0 ? "overlap " + durationText(-shift) : "no shift")
    return "\(changeAt(timeline, index)) (local \(localText(time + timeline.periods[index - 1].offset)) -> \(localText(time + timeline.periods[index].offset)), \(kind))"
}
func shiftsText(_ timeline: Timeline, _ indices: [Int]) -> String {
    var gaps = 0, overlaps = 0, unchanged = 0
    for index in indices { let shift = offsetShift(timeline, index); if shift > 0 { gaps += 1 } else if shift < 0 { overlaps += 1 } else { unchanged += 1 } }
    return "gaps \(gaps), overlaps \(overlaps), no shift \(unchanged)"
}
func candidateText(_ timeline: Timeline, _ local: Int, _ index: Int) -> String { let period = timeline.periods[index]; return "\(utText(local - period.offset)) (\(stateText(period)))" }
func chosenCandidate(_ candidates: [Int], _ option: String?) -> Int? {
    if candidates.count == 1 { return candidates[0] }
    if candidates.count == 2 { if option == "EARLIER" { return candidates[0] }; if option == "LATER" { return candidates[1] } }
    return nil
}
func unresolvedText(_ timeline: Timeline, _ local: Int, _ candidates: [Int]) -> String {
    if !candidates.isEmpty { return "AMBIGUOUS " + candidates.map { candidateText(timeline, local, $0) }.joined(separator: " or ") }
    let index = timeline.skippingTransition(local)
    let time = timeline.periods[index].start
    return "NONEXISTENT gap \(localText(time + timeline.periods[index - 1].offset)) to \(localText(time + timeline.periods[index].offset)) at \(utText(time))"
}
func workingHours(_ timeline: Timeline, _ start: Int, _ end: Int) -> [(Int, Int)] {
    var pieces: [(Int, Int)] = []
    for index in timeline.nearby(start, end) {
        let period = timeline.periods[index], low = max(start - timeline.periods[index].offset, timeline.periods[index].start)
        let high = min(end - period.offset, timeline.endOf(index))
        if low < high { pieces.append((low, high)) }
    }
    return mergeIntervals(pieces)
}
func parseValue(_ kind: String, _ word: String) -> Int? {
    let bytes = Array(word.utf8)
    func number(_ start: Int, _ count: Int) -> Int { Int(String(bytes: bytes[start..<(start + count)], encoding: .utf8)!)! }
    let year = number(0, 4)
    if !(minYear...maxYear).contains(year) { return nil }
    if kind == "year" { return year }
    let month = number(5, 2), day = number(8, 2)
    if !(1...12).contains(month) || day < 1 || day > daysInMonth(year, month) { return nil }
    if kind == "date" { return dayNumber(year, month, day) }
    let hour = number(11, 2), minute = number(14, 2), second = number(17, 2)
    if hour > 23 || minute > 59 || second > 59 { return nil }
    return timeValue(year, month, day, hour, minute, second)
}
enum QueryError: Error { case invalid(String) }
enum Argument {
    case zone(Zone), number(Int)
    var zoneValue: Zone? { if case .zone(let value) = self { return value }; return nil }
    var numericValue: Int? { if case .number(let value) = self { return value }; return nil }
}
func queryKinds(_ command: String, _ count: Int) -> [String] {
    switch command {
    case "TOUTC": return ["zone", "local"]
    case "TOLOCAL", "OFFSET": return ["zone", "ut"]
    case "CONVERT": return ["zone", "zone", "local"]
    case "TRANSITIONS": return ["zone", "year", "year"]
    case "DURATION": return ["zone", "local", "local"]
    default: return ["date"] + Array(repeating: "zone", count: count - 1)
    }
}
func processQuery(_ database: Database, _ line: String, _ workStart: Int, _ workEnd: Int) throws -> (String, [String]?) {
    var words = line.split(separator: " ").map(String.init)
    let command = words.removeFirst()
    var option: String? = nil
    if (command == "TOUTC" || command == "CONVERT") && (words.last == "EARLIER" || words.last == "LATER") { option = words.removeLast() }
    var values: [Argument] = []
    for (kind, word) in zip(queryKinds(command, words.count), words) {
        if kind == "zone" { guard let zone = database.findZone(word) else { throw QueryError.invalid("unknown zone " + word) }; values.append(.zone(zone)) }
        else { guard let value = parseValue(kind, word) else { throw QueryError.invalid("invalid value " + word) }; values.append(.number(value)) }
    }
    if command == "MEETING" {
        let start = values[0].numericValue! * secondsPerDay + workStart, end = values[0].numericValue! * secondsPerDay + workEnd
        let zones = values.dropFirst().map { $0.zoneValue! }
        var common = workingHours(zones[0].timeline, start, end)
        for zone in zones.dropFirst() { common = intersectIntervals(common, workingHours(zone.timeline, start, end)) }
        var parts: [String] = []
        for (low, high) in common {
            let members = zip(words.dropFirst(), zones).map { word, zone -> String in let period = zone.timeline.periodAt(low); return "\(word) \(localText(low + period.offset)) \(period.abbreviation)" }
            parts.append("\(utText(low)) to \(utText(high)) (\(durationText(high - low))) [\(members.joined(separator: ", "))]")
        }
        return (parts.isEmpty ? "NONE" : parts.joined(separator: "; "), nil)
    }
    if command == "CONVERT" {
        let source = values[0].zoneValue!, target = values[1].zoneValue!, local = values[2].numericValue!
        let candidates = source.timeline.candidates(local)
        guard let index = chosenCandidate(candidates, option) else { return (unresolvedText(source.timeline, local, candidates), nil) }
        let time = local - source.timeline.periods[index].offset
        let period = target.timeline.periodAt(time)
        let targetLocal = time + period.offset
        let shift = floorDiv(targetLocal, secondsPerDay) - floorDiv(local, secondsPerDay)
        let shiftText = shift > 0 ? "+\(shift)" : String(shift)
        return ("\(localText(targetLocal)) (\(stateText(period))) at \(utText(time)), day shift \(shiftText)", nil)
    }
    let timeline = values[0].zoneValue!.timeline, first = values[1].numericValue!
    switch command {
    case "TOUTC":
        let candidates = timeline.candidates(first)
        return (chosenCandidate(candidates, option).map { candidateText(timeline, first, $0) } ?? unresolvedText(timeline, first, candidates), nil)
    case "TOLOCAL": let period = timeline.periodAt(first); return ("\(localText(first + period.offset)) (\(stateText(period)))", nil)
    case "OFFSET":
        let index = timeline.indexAt(first)
        var text = stateText(timeline.periods[index])
        if index > 0 { text += " since " + utText(timeline.periods[index].start) }
        if index + 1 < timeline.periods.count { text += " until " + utText(timeline.periods[index + 1].start) }
        return (text, nil)
    case "TRANSITIONS":
        let last = values[2].numericValue!
        if first > last { throw QueryError.invalid("invalid range") }
        let selected = transitionsBetween(timeline, yearStart(first), yearStart(last + 1))
        return ("transitions: \(selected.count)", [line] + selected.map { transitionLine(timeline, $0) } + [shiftsText(timeline, selected)])
    default:
        let locals = [first, values[2].numericValue!]
        var offsets: [Int] = []
        for (position, local) in locals.enumerated() {
            let candidates = timeline.candidates(local)
            if candidates.count == 2 { return ("AMBIGUOUS " + words[position + 1], nil) }
            if candidates.isEmpty { return ("NONEXISTENT " + words[position + 1], nil) }
            offsets.append(timeline.periods[candidates[0]].offset)
        }
        let elapsed = (locals[1] - offsets[1]) - (locals[0] - offsets[0])
        return ("\(elapsed) s (\(durationText(elapsed))), wall clock \(durationText(locals[1] - locals[0])), offset change \(offsetText(offsets[1] - offsets[0]))", nil)
    }
}
func ruleText(_ rule: Rule) -> String { "rule \(rule.name) \(rule.fields[2]) \(rule.fields[3]) \(rule.fields[5]) \(rule.fields[6]) \(clockText(rule.at))\(rule.atType) \(clockText(rule.save)) \(rule.fields[9])" }
func databaseBlock(_ database: Database) -> [String] {
    let ruleLines = database.lines.filter { $0.kind == .rule }, linkLines = database.lines.filter { $0.kind == .link }
    let validRules = ruleLines.filter { $0.error == nil }.count, validLinks = linkLines.filter { $0.error == nil }.count
    let zones = Array(database.zones.values), used = Set(database.zones.values.flatMap(\.ruleSets))
    let unused = database.ruleOrder.filter { !used.contains($0) }
    let invalid = database.blocks.filter { !$0.defined }.map { "\($0.name) (line \($0.number))" }
    let zoneLines = zones.reduce(0) { $0 + $1.lines.count }
    var lines = ["DATABASE", "rule lines: \(validRules) valid, \(ruleLines.count - validRules) invalid", "zones: \(zones.count) defined, \(database.blocks.count - zones.count) invalid", "zone lines: \(zoneLines) in defined zones", "links: \(validLinks) defined, \(linkLines.count - validLinks) invalid", "errors: \(database.errorLines.count)", "unused rules: " + namesOrNone(unused, " "), "invalid zones: " + namesOrNone(invalid, ", ")]
    for name in database.ruleOrder {
        let rules = database.ruleSets[name]!.map { database.rules[$0] }
        let first = rules.map(\.fromYear).min()!, last = rules.contains { $0.fields[3] == "max" } ? "max" : String(rules.map(\.toYear).max()!)
        let count = zones.filter { $0.ruleSets.contains(name) }.count
        lines.append("rule set \(name): lines \(rules.count), years \(first)-\(last), zones \(count)")
    }
    return lines
}
func dstLines(_ timeline: Timeline, _ reference: Int) -> [String] {
    let indices = timeline.periods.indices.filter { timeline.periods[$0].dst }
    var lines: [String]
    if indices.isEmpty { lines = ["dst years: none"] }
    else { let years = indices.map { splitTime(timeline.periods[$0].start).0 }; lines = ["dst years: \(years.min()!)-\(years.max()!)"] }
    let year = splitTime(reference).0, low = yearStart(splitTime(reference).0), high = yearStart(splitTime(reference).0 + 1)
    var pieces: [(Int, Int)] = []
    for index in indices { let start = max(low, timeline.periods[index].start), end = min(high, timeline.endOf(index)); if start < end { pieces.append((start, end)) } }
    var total = 0
    for (start, end) in mergeIntervals(pieces) { lines.append("dst period: \(utText(start)) to \(utText(end)) (\(durationText(end - start)))"); total += end - start }
    lines.append("dst total \(year): \(durationText(total))")
    return lines
}
func zoneBlock(_ database: Database, _ zone: Zone, _ reference: Int) -> [String] {
    let timeline = zone.timeline, periods = zone.timeline.periods
    var lines = ["ZONE " + zone.name, "aliases: " + namesOrNone(zone.aliases, " ")]
    for (index, line) in zone.lines.enumerated() {
        var text = "line \(index + 1): \(offsetText(line.stdoff)) \(line.rulesNotation) \(line.format)"
        if index > 0 { text += " from " + utText(line.start) }
        if line.until != nil { text += " until \(line.untilNotation) = \(utText(line.end))" }
        lines.append("\(text), transitions \(transitionsBetween(timeline, line.start, line.end).count)")
    }
    for name in zone.ruleSets { for index in database.ruleSets[name]! { let rule = database.rules[index]; lines.append("\(ruleText(rule)), applied \(zone.applied[rule.number, default: 0])") } }
    lines.append("offset range: \(offsetText(periods.map(\.offset).min()!)) to \(offsetText(periods.map(\.offset).max()!))")
    var states: [(String, Int)] = []
    for period in periods { let state = stateText(period); if let index = states.firstIndex(where: { $0.0 == state }) { states[index].1 += 1 } else { states.append((state, 1)) } }
    for (state, count) in states { lines.append("state \(state), periods \(count)") }
    let index = timeline.indexAt(reference), period = periods[timeline.indexAt(reference)]
    lines.append("reference: \(localText(reference + period.offset)) (\(stateText(period))), line \(zone.lineNumberAt(reference))")
    lines.append("previous transition: " + (index > 0 ? changeAt(timeline, index) : "none"))
    lines.append("next transition: " + (index + 1 < periods.count ? changeAt(timeline, index + 1) : "none"))
    let every = Array(1..<periods.count)
    lines.append("transitions: \(every.count), \(shiftsText(timeline, every))")
    lines += dstLines(timeline, reference)
    return lines
}
func main() throws {
    let database = try Database(readLines("tzdata.txt")), params = try readLines("params.txt")
    let reference = parseValue("ut", params[0].split(separator: " ").map(String.init)[1])!
    let work = params[1].split(separator: " ").map(String.init)
    let workStart = clockSeconds(work[1]), workEnd = clockSeconds(work[2])
    var answers: [String] = [], transitionBlocks: [[String]] = []
    for line in try readLines("queries.txt") {
        let result: String
        do { let (text, block) = try processQuery(database, line, workStart, workEnd); result = text; if let block = block { transitionBlocks.append(block) } }
        catch QueryError.invalid(let message) { result = "ERROR " + message }
        answers.append(line + " => " + result)
    }
    var blocks = [indented(databaseBlock(database))]
    for name in database.zones.keys.sorted() { blocks.append(indented(zoneBlock(database, database.zones[name]!, reference))) }
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("output/answers.txt", answers); try writeLines("output/errors.txt", database.errorLines)
    try writeBlocks("output/transitions.txt", transitionBlocks); try writeBlocks("output/zone_summary.txt", blocks)
}
try main()
