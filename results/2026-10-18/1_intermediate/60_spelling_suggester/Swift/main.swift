let adjacentKeys: [Character: String] = [
    "a": "qswz", "b": "ghnv", "c": "dfvx", "d": "cefrsx", "e": "drsw",
    "f": "cdgrtv", "g": "bfhtvy", "h": "bgjnuy", "i": "jkou", "j": "hikmnu",
    "k": "ijlmo", "l": "kop", "m": "jkn", "n": "bhjm", "o": "iklp",
    "p": "lo", "q": "aw", "r": "deft", "s": "adewxz", "t": "fgry",
    "u": "hijy", "v": "bcfg", "w": "aeqs", "x": "cdsz", "y": "ghtu",
    "z": "asx",
]
let soundexGroups: [(letters: String, digit: Character)] = [
    ("bfpv", "1"), ("cgjkqsxz", "2"), ("dt", "3"), ("l", "4"),
    ("mn", "5"), ("r", "6"), ("aeiouy", "0"),
]
let soundexDigits: [Character: Character] = Dictionary(
    uniqueKeysWithValues: soundexGroups.flatMap { group in
        group.letters.map { ($0, group.digit) }
    })
let sentenceMarks: Set<Character> = [".", "!", "?"]
let findingKinds = ["unknown", "case", "capital", "repeats"]
let counterNames = ["checked", "unknown", "case", "capital", "repeats", "corrected"]
let optionMaximums = ["LIMIT": 3, "SUGGESTIONS": 10]
let keyboardModes: Set<String> = ["ON", "OFF"]
let maxWordLength = 30
let maxFrequency = 1_000_000
let maxListed = 20
let reportSize = 10

typealias Match = (distance: Int, frequency: Int, word: String)

struct CommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func wordArgument(_ text: String) throws -> String {
    guard (1...maxWordLength).contains(text.count), text.allSatisfy(\.isLetter) else {
        throw CommandError("BAD WORD \(text)")
    }
    return text.lowercased()
}

func numberArgument(_ text: String, _ minimum: Int, _ maximum: Int) throws -> Int {
    guard (1...7).contains(text.count), text.allSatisfy({ ("0"..."9").contains($0) }),
        let value = Int(text), (minimum...maximum).contains(value)
    else {
        throw CommandError("BAD NUMBER \(text)")
    }
    return value
}

func decimalText(_ numerator: Int, _ denominator: Int, _ digits: Int) -> String {
    let scale = repeatElement(10, count: digits).reduce(1, *)
    let value = (2 * numerator * scale + denominator) / (2 * denominator)
    let fraction = String(value % scale)
    return "\(value / scale).\(String(repeating: "0", count: digits - fraction.count))\(fraction)"
}

typealias Entry = (key: String, value: Int)

func frequencyOrdered(_ first: Entry, _ second: Entry) -> Bool {
    (-first.value, first.key) < (-second.value, second.key)
}

func inDistanceOrder(_ matches: [Match]) -> [Match] {
    matches.sorted { ($0.distance, -$0.frequency, $0.word) < ($1.distance, -$1.frequency, $1.word) }
}

func capitalizeFirst(_ word: String) -> String {
    word.prefix(1).uppercased() + word.dropFirst()
}

func applyCase(_ tokenText: String, _ word: String) -> String {
    if tokenText.count >= 2 && tokenText.allSatisfy(\.isUppercase) {
        return word.uppercased()
    }
    if tokenText.first?.isUppercase == true {
        return capitalizeFirst(word)
    }
    return word
}

struct Token {
    let number: Int
    let text: String
    let word: String
    let end: Int
    let gap: String
    let sentenceStart: Bool
    let isRepeat: Bool

    var mixedCase: Bool {
        text.dropFirst().contains(where: \.isUppercase) && !text.allSatisfy(\.isUppercase)
    }
}

func tokenize(_ text: String) -> [Token] {
    let characters = Array(text)
    var tokens: [Token] = []
    var position = 0
    var index = 0
    while index < characters.count {
        guard characters[index].isLetter else {
            index += 1
            continue
        }
        let start = index
        while index < characters.count && characters[index].isLetter {
            index += 1
        }
        let gap = String(characters[position..<start])
        let tokenText = String(characters[start..<index])
        let word = tokenText.lowercased()
        let previous = tokens.last
        tokens.append(
            Token(
                number: tokens.count + 1, text: tokenText, word: word, end: index, gap: gap,
                sentenceStart: previous == nil || gap.contains { sentenceMarks.contains($0) },
                isRepeat: previous?.word == word && gap.allSatisfy { $0 == " " }))
        position = index
    }
    return tokens
}

func gapCost(_ keyboard: Bool) -> Int {
    keyboard ? 2 : 1
}

func substitutionCost(_ first: Character, _ second: Character, _ keyboard: Bool) -> Int {
    if first == second {
        return 0
    }
    if !keyboard {
        return 1
    }
    return adjacentKeys[first, default: ""].contains(second) ? 1 : 2
}

func isSwap(_ first: [Character], _ second: [Character], _ i: Int, _ j: Int) -> Bool {
    i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1]
}

func distanceTable(_ first: [Character], _ second: [Character], _ keyboard: Bool) -> [[Int]] {
    let gap = gapCost(keyboard)
    let row = Array(repeating: 0, count: second.count + 1)
    var table = Array(repeating: row, count: first.count + 1)
    for i in 0...first.count {
        table[i][0] = i * gap
    }
    for j in 0...second.count {
        table[0][j] = j * gap
    }
    for i in 1...first.count {
        for j in 1...second.count {
            let substitution = substitutionCost(first[i - 1], second[j - 1], keyboard)
            var best = min(
                table[i - 1][j] + gap, table[i][j - 1] + gap, table[i - 1][j - 1] + substitution)
            if isSwap(first, second, i, j) {
                best = min(best, table[i - 2][j - 2] + 1)
            }
            table[i][j] = best
        }
    }
    return table
}

func editDistance(_ first: String, _ second: String, _ keyboard: Bool) -> Int {
    distanceTable(Array(first), Array(second), keyboard)[first.count][second.count]
}

func prefixDistance(_ word: String, _ other: String, _ keyboard: Bool) -> Int {
    distanceTable(Array(word), Array(other), keyboard)[word.count].min()!
}

func editOperations(_ first: String, _ second: String, _ keyboard: Bool) -> (Int, [String]) {
    let first = Array(first)
    let second = Array(second)
    let table = distanceTable(first, second, keyboard)
    let gap = gapCost(keyboard)
    var operations: [String] = []
    var i = first.count
    var j = second.count
    while i > 0 || j > 0 {
        if i >= 1 && j >= 1
            && table[i][j]
                == table[i - 1][j - 1] + substitutionCost(first[i - 1], second[j - 1], keyboard)
        {
            if first[i - 1] != second[j - 1] {
                operations.append("sub:\(first[i - 1])>\(second[j - 1])")
            }
            i -= 1
            j -= 1
        } else if isSwap(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1 {
            operations.append("swap:\(first[i - 2])\(first[i - 1])")
            i -= 2
            j -= 2
        } else if i >= 1 && table[i][j] == table[i - 1][j] + gap {
            operations.append("del:\(first[i - 1])")
            i -= 1
        } else {
            operations.append("ins:\(second[j - 1])")
            j -= 1
        }
    }
    return (table[first.count][second.count], operations.reversed())
}

func soundex(_ word: String) -> String {
    var code = word.prefix(1).uppercased()
    // h and w have no digit; as the first letter they count as 0
    var previous = soundexDigits[word.first!, default: "0"]
    for letter in word.dropFirst() where letter != "h" && letter != "w" {
        let digit = soundexDigits[letter, default: "0"]
        if digit != "0" && digit != previous {
            code.append(digit)
        }
        previous = digit
    }
    return String((code + "000").prefix(4))
}

func segment(_ word: String, _ dictionary: [String: Int]) -> (ways: Int, best: [String]?) {
    let characters = Array(word)
    let length = characters.count
    var ways = Array(repeating: 0, count: length + 1)
    var best: [[String]?] = Array(repeating: nil, count: length + 1)
    ways[length] = 1
    best[length] = []
    for start in stride(from: length - 1, through: 0, by: -1) {
        for end in (start + 1)...length {
            let piece = String(characters[start..<end])
            guard dictionary[piece] != nil, let rest = best[end] else {
                continue
            }
            ways[start] += ways[end]
            let candidate = [piece] + rest
            // pieces share their start: with equal counts the earlier, shorter one is smaller
            if let current = best[start], current.count <= candidate.count {
                continue
            }
            best[start] = candidate
        }
    }
    return (ways[0], best[0])
}

struct UndoRecord {
    let name: String
    let dictionary: [String: Int]
    let ignored: Set<String>
    let rules: [String: String]
}

struct CorrectionPair: Hashable {
    let word: String
    let correction: String
}

enum Handler {
    case text((String) -> Void)
    case words(Int, ([String]) throws -> Void)
}

final class SpellChecker {
    private var dictionary: [String: Int]
    private var ignored: Set<String> = []
    private var rules: [String: String] = [:]
    private var keyboard = false
    private var baseLimit = 2
    private var suggestionCount = 5
    private var undoHistory: [UndoRecord] = []
    private var unknownLog: [String: Int] = [:]
    private var correctionLog: [CorrectionPair: Int] = [:]
    private var counters: [String: Int] = [:]
    private(set) var output: [String] = []

    init(dictionary: [String: Int]) {
        self.dictionary = dictionary
    }

    private func emit(_ parts: [String]) {
        output.append(parts.joined(separator: " "))
    }

    private var limit: Int {
        keyboard ? 2 * baseLimit : baseLimit
    }

    private func isKnown(_ word: String) -> Bool {
        dictionary[word] != nil || ignored.contains(word)
    }

    private func frequencyOrder() -> [String] {
        dictionary.sorted(by: frequencyOrdered).map(\.key)
    }

    private func requireEntry(_ word: String) throws -> Int {
        guard let frequency = dictionary[word] else {
            throw CommandError("NOT FOUND \(word)")
        }
        return frequency
    }

    private func candidates(_ word: String) -> [Match] {
        let gap = gapCost(keyboard)
        var found: [Match] = []
        for (other, frequency) in dictionary
        where other != word && abs(other.count - word.count) * gap <= limit {
            let distance = editDistance(word, other, keyboard)
            if distance <= limit {
                found.append((distance, frequency, other))
            }
        }
        return inDistanceOrder(found)
    }

    private func correction(_ word: String) -> String? {
        guard !isKnown(word) else { return nil }
        if let target = rules[word] {
            return target
        }
        return candidates(word).first?.word
    }

    private func recordUndo(_ name: String) {
        undoHistory.append(
            UndoRecord(name: name, dictionary: dictionary, ignored: ignored, rules: rules))
    }

    private func logCorrection(_ word: String, _ replacement: String) {
        correctionLog[CorrectionPair(word: word, correction: replacement), default: 0] += 1
        counters["corrected", default: 0] += 1
    }

    private func unknownFinding(_ token: Token) -> String {
        let prefix = "UNKNOWN \(token.number) \(token.text)"
        if let target = rules[token.word] {
            return "\(prefix) RULE \(target)"
        }
        let found = candidates(token.word)
        if found.isEmpty {
            return "\(prefix) NONE"
        }
        let words = found.prefix(suggestionCount).map(\.word)
        return ([prefix, "SUGGEST"] + words).joined(separator: " ")
    }

    private func check(_ text: String) {
        let tokens = tokenize(text)
        var findings: [(kind: String, line: String)] = []
        for token in tokens {
            if !isKnown(token.word) {
                findings.append(("unknown", unknownFinding(token)))
                unknownLog[token.word, default: 0] += 1
            }
            if token.mixedCase {
                findings.append(("case", "CASE \(token.number) \(token.text)"))
            }
            if token.sentenceStart && token.text.first?.isLowercase == true {
                findings.append(("capital", "CAPITAL \(token.number) \(token.text)"))
            }
            if token.isRepeat {
                findings.append(("repeats", "REPEAT \(token.number) \(token.text)"))
            }
        }
        let counts = findingKinds.map { kind in findings.filter { $0.kind == kind }.count }
        counters["checked", default: 0] += tokens.count
        for (kind, count) in zip(findingKinds, counts) {
            counters[kind, default: 0] += count
        }
        emit(["CHECK", "words=\(tokens.count)"] + zip(findingKinds, counts).map { "\($0)=\($1)" })
        output.append(contentsOf: findings.map(\.line))
    }

    private func correct(_ text: String) {
        var result = ""
        var position = 0
        var changed = 0
        for token in tokenize(text) {
            result += token.gap
            if let replacement = correction(token.word) {
                result += applyCase(token.text, replacement)
                logCorrection(token.word, replacement)
                changed += 1
            } else {
                result += token.text
            }
            position = token.end
        }
        result.append(contentsOf: text.dropFirst(position))
        emit(["CORRECT changed=\(changed):", result])
    }

    private func fix(_ text: String) {
        var result = ""
        var position = 0
        var removed = 0
        var replaced = 0
        var recased = 0
        for token in tokenize(text) {
            position = token.end
            if token.isRepeat {
                removed += 1
                continue
            }
            let replacement = correction(token.word)
            var fixed = applyCase(token.text, replacement ?? token.word)
            if token.sentenceStart && fixed.first?.isLowercase == true {
                fixed = capitalizeFirst(fixed)
            }
            if let replacement {
                logCorrection(token.word, replacement)
                replaced += 1
            } else if fixed != token.text {
                recased += 1
            }
            result += token.gap + fixed
        }
        result.append(contentsOf: text.dropFirst(position))
        emit(["FIX", "removed=\(removed)", "replaced=\(replaced)", "recased=\(recased):", result])
    }

    private func profile(_ text: String) {
        let tokens = tokenize(text)
        let distinct = Set(tokens.map(\.word)).count
        let unknown = tokens.filter { !isKnown($0.word) }.count
        let sentences = tokens.filter(\.sentenceStart).count
        var rate = "0.0"
        var average = "0.00"
        var longest = "-"
        if let longestToken = tokens.max(by: { $0.text.count < $1.text.count }) {
            let characters = tokens.map(\.text.count).reduce(0, +)
            rate = decimalText(100 * unknown, tokens.count, 1)
            average = decimalText(characters, tokens.count, 2)
            longest = longestToken.word
        }
        emit([
            "PROFILE", "words=\(tokens.count)", "distinct=\(distinct)", "unknown=\(unknown)",
            "rate=\(rate)", "avglen=\(average)", "longest=\(longest)", "sentences=\(sentences)",
        ])
    }

    private func learn(_ text: String) {
        recordUndo("LEARN")
        var updated = 0
        var added = 0
        var skipped = 0
        for token in tokenize(text) {
            if token.word.count > maxWordLength {
                skipped += 1
            } else if dictionary[token.word] != nil {
                dictionary[token.word, default: 0] += 1
                updated += 1
            } else {
                dictionary[token.word] = 1
                ignored.remove(token.word)
                added += 1
            }
        }
        emit(["LEARN", "updated=\(updated)", "added=\(added)", "skipped=\(skipped)"])
    }

    private func suggest(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        if isKnown(word) {
            emit(["SUGGEST", word, "KNOWN"])
        } else if let target = rules[word] {
            emit(["SUGGEST", word, "RULE", target])
        } else {
            let found = candidates(word)
            let shown = found.prefix(suggestionCount).map { "\($0.word):\($0.distance)" }
            emit(["SUGGEST", word, "found=\(found.count)"] + shown)
        }
    }

    private func dist(_ arguments: [String]) throws {
        let first = try wordArgument(arguments[0])
        let second = try wordArgument(arguments[1])
        let (distance, operations) = editOperations(first, second, keyboard)
        emit(["DIST", first, second, String(distance)] + operations)
    }

    private func soundexCode(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        emit(["SOUNDEX", word, soundex(word)])
    }

    private func sounds(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let code = soundex(word)
        let matches = frequencyOrder().filter { $0 != word && soundex($0) == code }
        emit(["SOUNDS", word, code, "count=\(matches.count)"] + matches.prefix(reportSize))
    }

    private func split(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let (ways, best) = segment(word, dictionary)
        if let best {
            emit(["SPLIT", word, "ways=\(ways)", "->"] + best)
        } else {
            emit(["SPLIT", word, "ways=0", "->", "NONE"])
        }
    }

    private func prefix(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let count = try numberArgument(arguments[1], 1, maxListed)
        let matches = frequencyOrder().filter { $0.hasPrefix(word) }
        let shown = matches.prefix(count).map { "\($0):\(dictionary[$0]!)" }
        emit(["PREFIX", word, "count=\(matches.count)"] + shown)
    }

    private func complete(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let count = try numberArgument(arguments[1], 1, maxListed)
        let threshold = limit / 2
        var matches: [Match] = []
        for (other, frequency) in dictionary {
            let distance = prefixDistance(word, other, keyboard)
            if distance <= threshold {
                matches.append((distance, frequency, other))
            }
        }
        let shown = inDistanceOrder(matches).prefix(count).map { "\($0.word):\($0.distance)" }
        emit(["COMPLETE", word, "count=\(matches.count)"] + shown)
    }

    private func listWords(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let count = try numberArgument(arguments[1], 1, maxListed)
        let matches = dictionary.keys.filter { $0 >= word }.sorted()
        let shown = matches.prefix(count).map { "\($0):\(dictionary[$0]!)" }
        emit(["LIST", word, "count=\(matches.count)"] + shown)
    }

    private func wordInfo(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let frequency = try requireEntry(word)
        let rank = frequencyOrder().firstIndex(of: word)! + 1
        emit([
            "WORD", word, "freq=\(frequency)", "rank=\(rank)", "soundex=\(soundex(word))",
            "neighbors=\(candidates(word).count)",
        ])
    }

    private func add(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let frequency = try numberArgument(arguments[1], 1, maxFrequency)
        if dictionary[word] != nil {
            throw CommandError("DUPLICATE \(word)")
        }
        recordUndo("ADD")
        dictionary[word] = frequency
        ignored.remove(word)
        emit(["ADD", word, String(frequency)])
    }

    private func remove(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let frequency = try requireEntry(word)
        recordUndo("REMOVE")
        dictionary[word] = nil
        emit(["REMOVE", word, String(frequency)])
    }

    private func ignore(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        if dictionary[word] != nil {
            throw CommandError("IN DICTIONARY \(word)")
        }
        if ignored.contains(word) {
            throw CommandError("ALREADY IGNORED \(word)")
        }
        recordUndo("IGNORE")
        ignored.insert(word)
        emit(["IGNORE", word])
    }

    private func unignore(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        if !ignored.contains(word) {
            throw CommandError("NOT IGNORED \(word)")
        }
        recordUndo("UNIGNORE")
        ignored.remove(word)
        emit(["UNIGNORE", word])
    }

    private func rule(_ arguments: [String]) throws {
        let source = try wordArgument(arguments[0])
        let target = try wordArgument(arguments[1])
        if dictionary[source] != nil {
            throw CommandError("IN DICTIONARY \(source)")
        }
        if dictionary[target] == nil {
            throw CommandError("NOT FOUND \(target)")
        }
        recordUndo("RULE")
        if let previous = rules.updateValue(target, forKey: source) {
            emit(["RULE", source, target, "REPLACED", previous])
        } else {
            emit(["RULE", source, target])
        }
    }

    private func unrule(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        guard let target = rules[word] else {
            throw CommandError("NO RULE \(word)")
        }
        recordUndo("UNRULE")
        rules[word] = nil
        emit(["UNRULE", word, target])
    }

    private func showRules() {
        let shown = rules.sorted { $0.key < $1.key }.map { "\($0.key)>\($0.value)" }
        emit(["RULES", "count=\(rules.count)"] + shown)
    }

    private func keyboardMode(_ arguments: [String]) throws {
        let mode = arguments[0]
        guard keyboardModes.contains(mode) else {
            throw CommandError("BAD MODE \(mode)")
        }
        keyboard = mode == "ON"
        emit(["KEYBOARD", mode])
    }

    private func setOption(_ arguments: [String]) throws {
        let option = arguments[0]
        guard let maximum = optionMaximums[option] else {
            throw CommandError("BAD OPTION \(option)")
        }
        let value = try numberArgument(arguments[1], 1, maximum)
        if option == "LIMIT" {
            baseLimit = value
        } else {
            suggestionCount = value
        }
        emit(["SET", option, String(value)])
    }

    private func undo() throws {
        guard let record = undoHistory.popLast() else {
            throw CommandError("NOTHING TO UNDO")
        }
        dictionary = record.dictionary
        ignored = record.ignored
        rules = record.rules
        emit(["UNDO", record.name])
    }

    private func report() {
        let entries = unknownLog.sorted { (-$0.value, $0.key) < (-$1.value, $1.key) }
        let shown = entries.prefix(reportSize).map { "\($0.key):\($0.value)" }
        emit(["REPORT", "distinct=\(entries.count)"] + shown)
    }

    private func history() {
        let entries = correctionLog.sorted {
            (-$0.value, $0.key.word, $0.key.correction)
                < (-$1.value, $1.key.word, $1.key.correction)
        }
        let shown = entries.prefix(reportSize).map {
            "\($0.key.word)>\($0.key.correction):\($0.value)"
        }
        emit(["HISTORY", "distinct=\(entries.count)"] + shown)
    }

    private func stats() {
        let top = dictionary.min(by: frequencyOrdered)!
        let characters = dictionary.keys.map(\.count).reduce(0, +)
        emit([
            "STATS", "words=\(dictionary.count)", "total=\(dictionary.values.reduce(0, +))",
            "avglen=\(decimalText(characters, dictionary.count, 2))", "top=\(top.key):\(top.value)",
            "ignored=\(ignored.count)", "rules=\(rules.count)",
            "keyboard=\(keyboard ? "ON" : "OFF")", "limit=\(limit)",
            "suggestions=\(suggestionCount)", "undo=\(undoHistory.count)",
        ])
        emit(["SESSION"] + counterNames.map { "\($0)=\(counters[$0, default: 0])" })
    }

    private func handler(for name: String) -> Handler? {
        switch name {
        case "CHECK": .text(check)
        case "CORRECT": .text(correct)
        case "FIX": .text(fix)
        case "PROFILE": .text(profile)
        case "LEARN": .text(learn)
        case "SUGGEST": .words(1, suggest)
        case "DIST": .words(2, dist)
        case "SOUNDEX": .words(1, soundexCode)
        case "SOUNDS": .words(1, sounds)
        case "SPLIT": .words(1, split)
        case "PREFIX": .words(2, prefix)
        case "COMPLETE": .words(2, complete)
        case "LIST": .words(2, listWords)
        case "WORD": .words(1, wordInfo)
        case "ADD": .words(2, add)
        case "REMOVE": .words(1, remove)
        case "IGNORE": .words(1, ignore)
        case "UNIGNORE": .words(1, unignore)
        case "RULE": .words(2, rule)
        case "UNRULE": .words(1, unrule)
        case "RULES": .words(0) { _ in self.showRules() }
        case "KEYBOARD": .words(1, keyboardMode)
        case "SET": .words(2, setOption)
        case "UNDO": .words(0) { _ in try self.undo() }
        case "REPORT": .words(0) { _ in self.report() }
        case "HISTORY": .words(0) { _ in self.history() }
        case "STATS": .words(0) { _ in self.stats() }
        default: nil
        }
    }

    func execute(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0])
        let rest = parts.count > 1 ? String(parts[1]) : nil
        do {
            switch handler(for: name) {
            case nil:
                throw CommandError("UNKNOWN COMMAND \(name)")
            case .text(let run)?:
                guard let rest else {
                    throw CommandError("BAD ARGUMENTS \(name)")
                }
                run(rest)
            case .words(let arity, let run)?:
                let arguments =
                    rest?.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
                    ?? []
                guard arguments.count == arity else {
                    throw CommandError("BAD ARGUMENTS \(name)")
                }
                try run(arguments)
            }
        } catch {
            emit(["ERROR \(error)"])
        }
    }
}

var dictionary: [String: Int] = [:]
let wordCount = Int(readLine()!)!
for _ in 0..<wordCount {
    let parts = readLine()!.split(separator: " ")
    dictionary[String(parts[0])] = Int(parts[1])!
}
let checker = SpellChecker(dictionary: dictionary)
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    checker.execute(readLine() ?? "")
}
print(checker.output.joined(separator: "\n"))
