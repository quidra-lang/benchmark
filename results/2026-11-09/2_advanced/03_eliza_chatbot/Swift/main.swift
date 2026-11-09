import Foundation

let sources = ["keyword", "memory", "question", "default", "repeat"]
let cycledLists = ["DEFAULT", "QUESTION", "REPEAT"]

func normalize(_ text: String) -> [[String]] {
    text.lowercased().components(separatedBy: CharacterSet(charactersIn: ",.?!;")).map { part in
        String(decoding: part.utf8.map { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 39 ? byte : 32
        }, as: UTF8.self).split(separator: " ").map {
            String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        }.filter { !$0.isEmpty }
    }.filter { !$0.isEmpty }
}

func groupedLines(_ values: [String], width: Int) -> [String] {
    stride(from: 0, to: values.count, by: width).map { start in
        values[start..<min(start + width, values.count)].joined(separator: " ")
    }
}

func rankedCounts(_ counts: [String: Int]) -> String {
    let values = counts.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    return values.isEmpty ? "none" : values.prefix(5).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
}

func sourceLine(_ turns: Int, counts: [String: Int]) -> String {
    "turns=\(turns) " + sources.map { "\($0)=\(counts[$0]!)" }.joined(separator: " ")
}

final class Snapshot {
    let state: BotState
    init(_ state: BotState) { self.state = state }
}

struct Session {
    let name: String
    var turns = 0
    var counts = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0) })
    var previous: [[String]]?
    var history: [String] = []
    var lastTrace: [String]?
    var traceOn = false
    var topics: [String: Int] = [:]
    var words: [String: Int] = [:]
    var stored = 0
    var recalled = 0
    var unrecognized: [Int] = []
    var undo: Snapshot?
}

struct BotState {
    var positions: [Int]
    var hits: [Int]
    var itemUses: [Int]
    var keywordUses: [Int]
    var keywordReplies: [Int]
    var listPositions = Dictionary(uniqueKeysWithValues: cycledLists.map { ($0, 0) })
    var memory: MemoryQueue
    var session = Session(name: "")

    init(script: Script) {
        positions = Array(repeating: 0, count: script.rules.count)
        hits = Array(repeating: 0, count: script.rules.count)
        itemUses = Array(repeating: 0, count: script.items.count)
        keywordUses = Array(repeating: 0, count: script.keywords.count)
        keywordReplies = Array(repeating: 0, count: script.keywords.count)
        memory = MemoryQueue(capacity: script.capacity)
    }
}

final class Chatbot {
    let script: Script
    var state: BotState
    var transcript: [String] = []
    var totalTurns = 0
    var totalSources = Dictionary(uniqueKeysWithValues: sources.map { ($0, 0) })

    init(script: Script) { self.script = script; state = BotState(script: script) }
    func logPrefix() -> String { "\(state.session.name) \(state.session.turns)" }
    func resetCycles() {
        state.positions = Array(repeating: 0, count: script.rules.count)
        for name in cycledLists { state.listPositions[name] = 0 }
    }
    func takeText(_ name: String) -> String {
        let texts = script.texts[name]!
        let position = state.listPositions[name]!
        state.listPositions[name] = (position + 1) % texts.count
        return texts[position]
    }
    func takeItem(_ ruleID: Int) -> (number: Int, item: Item) {
        let rule = script.rules[ruleID]
        let position = state.positions[ruleID]
        let itemID = rule.items[position]
        state.itemUses[itemID] += 1
        state.positions[ruleID] = (position + 1) % rule.items.count
        return (position + 1, script.items[itemID])
    }
    func preSubstitute(_ clauses: [[String]]) -> [[String]] {
        clauses.map { $0.flatMap { script.pre[$0] ?? [$0] } }
    }
    func prepared(_ text: String) -> [[String]] { preSubstitute(normalize(text)) }
    func isQuit(_ text: String) -> Bool {
        let words = normalize(text).flatMap { $0 }
        return words.count == 1 && script.quit.contains(words[0])
    }
    func selectClause(_ clauses: [[String]]) -> (number: Int, words: [String])? {
        for (index, clause) in clauses.enumerated() where clause.contains(where: { script.keywordMap[$0] != nil }) {
            return (index + 1, clause)
        }
        return nil
    }
    func keywordList(_ words: [String]) -> [Int] {
        var found: [Int] = []
        var seen: Set<Int> = []
        for word in words {
            if let id = script.keywordMap[word], seen.insert(id).inserted { found.append(id) }
        }
        return found.enumerated().sorted {
            let left = script.keywords[$0.element].rank
            let right = script.keywords[$1.element].rank
            return left == right ? $0.offset < $1.offset : left > right
        }.map { $0.element }
    }
    func ruleEntries(_ keyword: Keyword) -> [(label: String, number: Int, id: Int)] {
        keyword.memories.enumerated().map { ("memory", $0.offset + 1, $0.element) }
            + keyword.decomps.enumerated().map { ("decomp", $0.offset + 1, $0.element) }
    }
    func findRule(_ rules: [Int], words: [String]) -> (number: Int, id: Int, bindings: [[String]])? {
        for (index, ruleID) in rules.enumerated() {
            if let bindings = matchPattern(script.rules[ruleID].pattern, words: words, groups: script.groupWords) {
                return (index + 1, ruleID, bindings)
            }
        }
        return nil
    }
    func keywordReply(_ clauses: [[String]], trace: inout [String]) -> String? {
        guard let selected = selectClause(clauses) else { trace.append("CLAUSE none"); return nil }
        let words = selected.words
        trace.append("CLAUSE \(selected.number) \(words.joined(separator: " "))")
        let keys = keywordList(words)
        trace.append("KEYS " + keys.map { script.keywords[$0].word }.joined(separator: " "))
        let first = script.keywords[keys[0]]
        if let memory = findRule(first.memories, words: words) {
            trace.append("MEMORY \(first.word) \(memory.number)")
            state.hits[memory.id] += 1
            if !script.rules[memory.id].items.isEmpty {
                let text = buildReply(takeItem(memory.id).item.text, bindings: memory.bindings, post: script.post)
                let prefix = logPrefix()
                if state.memory.store(prefix, keyword: first.word, text: text) { state.session.stored += 1 }
            }
        }
        var entered: Set<Int> = []
        for original in keys {
            if entered.contains(original) { continue }
            var current = original
            var currentWords = words
            trace.append("ENTER \(script.keywords[current].word)")
            while true {
                entered.insert(current)
                state.keywordUses[current] += 1
                let keyword = script.keywords[current]
                guard let found = findRule(keyword.decomps, words: currentWords) else { trace.append("NOMATCH \(keyword.word)"); break }
                state.hits[found.id] += 1
                if script.rules[found.id].items.isEmpty { trace.append("DECOMP \(keyword.word) \(found.number) 0"); break }
                let taken = takeItem(found.id)
                let item = taken.item
                trace.append("DECOMP \(keyword.word) \(found.number) \(taken.number)")
                if item.kind == "REASM" {
                    state.keywordReplies[current] += 1
                    state.session.topics[keyword.word, default: 0] += 1
                    return buildReply(item.text, bindings: found.bindings, post: script.post)
                }
                if item.kind == "NEWKEY" { break }
                let targetWord = item.arguments[0]
                guard let target = script.keywordMap[targetWord], !entered.contains(target) else { trace.append("BLOCKED \(targetWord)"); break }
                if item.kind == "RESTATE" {
                    currentWords = restatedWords(Array(item.arguments.dropFirst()), bindings: found.bindings)
                    trace.append((["RESTATE", targetWord] + currentWords).joined(separator: " "))
                } else { trace.append("GOTO \(targetWord)") }
                current = target
            }
        }
        return nil
    }

    func decide(_ text: String) -> (reply: String, trace: [String]) {
        let clauses = normalize(text)
        var trace: [String] = []
        let reply: String
        let source: String
        if !script.texts["REPEAT"]!.isEmpty && !clauses.isEmpty && clauses == state.session.previous {
            trace.append("REPEAT"); reply = takeText("REPEAT"); source = "repeat"
        } else if let keyword = keywordReply(preSubstitute(clauses), trace: &trace) {
            reply = keyword; source = "keyword"
        } else if !state.memory.texts.isEmpty {
            state.session.recalled += 1
            let prefix = logPrefix()
            reply = state.memory.recall(prefix); source = "memory"
        } else if text.hasSuffix("?") && !script.texts["QUESTION"]!.isEmpty {
            reply = takeText("QUESTION"); source = "question"
        } else { reply = takeText("DEFAULT"); source = "default" }
        trace.append("REPLY \(source)")
        state.session.previous = clauses
        state.session.counts[source]! += 1
        if ["question", "default"].contains(source) { state.session.unrecognized.append(state.session.turns) }
        return (reply, trace)
    }

    func respond(_ text: String) {
        var snapshot = state
        snapshot.session.undo = nil
        state.session.undo = Snapshot(snapshot)
        state.session.turns += 1
        for word in normalize(text).flatMap({ $0 }) where !script.stop.contains(word) { state.session.words[word, default: 0] += 1 }
        state.session.history.append("\(state.session.turns): \(text)")
        let result = decide(text)
        transcript += elizaLines(result.reply)
        state.session.lastTrace = result.trace
        if state.session.traceOn { transcript += result.trace.map { "  \($0)" } }
    }

    func command(_ line: String) -> [String] {
        let split = line.firstIndex(of: " ")
        let name = split.map { String(line[..<$0]) } ?? line
        let text = split.map { String(line[line.index(after: $0)...]) } ?? ""
        let args = text.isEmpty ? [] : text.components(separatedBy: " ")
        let none: Set<String> = [":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo"]
        let some: Set<String> = [":prepare", ":reflect", ":say", ":explain"]
        let one: Set<String> = [":groups", ":find", ":script", ":cycles", ":coverage"]
        guard none.union(some).union(one).union([":trace", ":test"]).contains(name) else { return ["unknown command \(name)"] }
        if none.contains(name) && !args.isEmpty || some.contains(name) && text.isEmpty || one.contains(name) && args.count != 1 || name == ":trace" && args != ["on"] && args != ["off"] || name == ":test" && args.count < 2 { return ["bad arguments"] }
        if [":script", ":cycles", ":coverage", ":test"].contains(name) && script.keywordMap[args[0]] == nil { return ["unknown keyword \(args[0])"] }
        switch name {
        case ":prepare":
            let clauses = prepared(text)
            var result = clauses.enumerated().map { "clause \($0.offset + 1): \($0.element.joined(separator: " "))" }
            if clauses.isEmpty { result.append("no words") }
            if let selected = selectClause(clauses) {
                result.append("selected \(selected.number)")
                result.append("keys " + keywordList(selected.words).map { "\(script.keywords[$0].word)/\(script.keywords[$0].rank)" }.joined(separator: " "))
            } else { result.append("selected none") }
            return result
        case ":test":
            let utterance = text.firstIndex(of: " ").map { String(text[text.index(after: $0)...]) } ?? ""
            let words = prepared(utterance).flatMap { $0 }
            let result = ruleEntries(script.keywords[script.keywordMap[args[0]]!]).map { entry -> String in
                let detail: String
                if let bindings = matchPattern(script.rules[entry.id].pattern, words: words, groups: script.groupWords) {
                    detail = bindings.isEmpty ? "match" : bindings.map { "[\($0.joined(separator: " "))]" }.joined(separator: " ")
                } else { detail = "no match" }
                return "\(entry.label) \(entry.number): \(detail)"
            }
            return result.isEmpty ? ["no rules"] : result
        case ":reflect":
            let clauses = prepared(text)
            return clauses.isEmpty ? ["no words"] : clauses.map { reflect($0, post: script.post).joined(separator: " ") }
        case ":keys":
            let keys = script.keywords.sorted { $0.rank == $1.rank ? $0.word < $1.word : $0.rank > $1.rank }
            return groupedLines(keys.map { "\($0.word)/\($0.rank)" }, width: 8)
        case ":groups":
            let names = script.groups.filter { $0.members.contains(args[0]) }.map { $0.name }.sorted()
            return [names.isEmpty ? "none" : names.joined(separator: " ")]
        case ":find": return find(args[0])
        case ":script":
            let keyword = script.keywords[script.keywordMap[args[0]]!]
            let numbers = [keyword.line] + (keyword.memories + keyword.decomps).flatMap { id in
                [script.rules[id].line] + script.rules[id].items.map { script.items[$0].line }
            }
            return numbers.sorted().map { "\($0) \(script.lines[$0 - 1])" }
        case ":why": return state.session.lastTrace ?? ["no reply yet"]
        case ":trace": state.session.traceOn = args[0] == "on"; return ["trace \(args[0])"]
        case ":history": return state.session.history.isEmpty ? ["no turns yet"] : Array(state.session.history.suffix(5))
        case ":memory": return ["memory \(state.memory.texts.count)/\(state.memory.capacity)"] + state.memory.texts.enumerated().map { "\($0.offset + 1): \($0.element)" }
        case ":forget":
            let count = state.memory.texts.count
            let prefix = logPrefix()
            state.memory.clear(prefix)
            return ["forgot \(count)"]
        case ":cycles", ":coverage":
            let entries = ruleEntries(script.keywords[script.keywordMap[args[0]]!])
            let result = entries.map { entry -> String in
                let rule = script.rules[entry.id]
                let details: String
                if name == ":cycles" { details = rule.items.isEmpty ? "empty" : "next \(state.positions[entry.id] + 1)/\(rule.items.count)" }
                else {
                    let uses = rule.items.map { String(state.itemUses[$0]) }.joined(separator: " ")
                    details = "hits \(state.hits[entry.id]) entries \(uses.isEmpty ? "-" : uses)"
                }
                return "\(entry.label) \(entry.number): \(details)"
            }
            return result.isEmpty ? ["no rules"] : result
        case ":reset": resetCycles(); return ["cycles reset"]
        case ":unused":
            let numbers = script.items.indices.filter { state.itemUses[$0] == 0 }.map { script.items[$0].line }.sorted()
            return ["unused \(numbers.count)"] + groupedLines(numbers.map(String.init), width: 12)
        case ":stats": return [sourceLine(state.session.turns, counts: state.session.counts)]
        case ":say", ":explain":
            if isQuit(text) { return ["would quit"] }
            let saved = state
            let result = decide(text)
            state = saved
            return name == ":say" ? [result.reply] : result.trace
        default:
            guard let snapshot = state.session.undo else { return ["nothing to undo"] }
            state = snapshot.state
            return ["undone turn \(state.session.turns + 1)"]
        }
    }

    func find(_ word: String) -> [String] {
        var result: [String] = []
        if let id = script.keywordMap[word] { result.append("keyword rank \(script.keywords[id].rank)") }
        for (label, substitutions) in [("pre", script.pres), ("post", script.posts)] {
            for sub in substitutions where sub.source == word || sub.replacement.contains(word) {
                result.append("\(label) \(sub.line): \(sub.source) -> \(sub.replacement.joined(separator: " "))")
            }
        }
        for group in script.groups where group.members.contains(word) { result.append("group \(group.name) line \(group.line)") }
        for keyword in script.keywords {
            for entry in ruleEntries(keyword) where script.rules[entry.id].pattern.contains(word) {
                result.append("pattern \(keyword.word) \(entry.label) \(entry.number)")
            }
        }
        if script.stop.contains(word) { result.append("stop word") }
        if script.quit.contains(word) { result.append("quit word") }
        return result.isEmpty ? ["not found"] : result
    }

    func notes() {
        let session = state.session
        let unrecognized = session.unrecognized.isEmpty ? "none" : session.unrecognized.map(String.init).joined(separator: " ")
        transcript.append("NOTES \(session.name)")
        transcript += [sourceLine(session.turns, counts: session.counts), "topics: \(rankedCounts(session.topics))", "words: \(rankedCounts(session.words))", "memory: stored=\(session.stored) recalled=\(session.recalled) pending=\(state.memory.texts.count)", "unrecognized: \(unrecognized)"].map { "  \($0)" }
        totalTurns += session.turns
        for source in sources { totalSources[source]! += session.counts[source]! }
    }

    func run(_ lines: [String]) {
        var sessions = 0
        for line in lines {
            if line.hasPrefix("SESSION ") {
                let name = String(line.dropFirst(8))
                sessions += 1
                if sessions > 1 {
                    transcript.append("")
                    if !script.persist.contains("cycles") { resetCycles() }
                    if !script.persist.contains("memory") { state.memory.clear("\(name) 0") }
                }
                state.session = Session(name: name)
                transcript.append(line)
                let texts = script.texts["INITIAL"]!
                transcript += elizaLines(texts[(sessions - 1) % texts.count])
            } else if line.hasPrefix(":") {
                transcript.append(line)
                transcript += command(line).map { "  \($0)" }
            } else {
                transcript.append("YOU: \(line)")
                if isQuit(line) {
                    let texts = script.texts["FINAL"]!
                    transcript += elizaLines(texts[(sessions - 1) % texts.count])
                    notes()
                } else { respond(line) }
            }
        }
        transcript.append("")
        transcript.append("SUMMARY sessions=\(sessions) \(sourceLine(totalTurns, counts: totalSources))")
    }

    func keywordStats() -> [String] {
        let indices = script.keywords.indices.sorted {
            state.keywordUses[$0] == state.keywordUses[$1] ? script.keywords[$0].word < script.keywords[$1].word : state.keywordUses[$0] > state.keywordUses[$1]
        }
        return ["keyword,rank,uses,replies,decomposition_hits"] + indices.map { index in
            let keyword = script.keywords[index]
            let hits = keyword.decomps.map { String(state.hits[$0]) }.joined(separator: "/")
            return "\(keyword.word),\(keyword.rank),\(state.keywordUses[index]),\(state.keywordReplies[index]),\(hits.isEmpty ? "-" : hits)"
        }
    }
}

func writeLines(_ name: String, _ lines: [String]) throws {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}

func runEliza() throws {
    let script = try loadScript("input/script.txt")
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("lint.txt", lintLines(lint(script)))
    let bot = Chatbot(script: script)
    bot.run(try readLines("input/dialogue.txt"))
    try writeLines("transcript.txt", bot.transcript)
    try writeLines("keyword_stats.csv", bot.keywordStats())
    try writeLines("memory_log.txt", bot.state.memory.log)
}

try runEliza()
