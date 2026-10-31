import Foundation

enum Cipher: String {
    case caesar, affine, vigenere, autokey, playfair, railfence, columnar

    var isSubstitution: Bool {
        switch self {
        case .caesar, .affine, .vigenere, .autokey: return true
        default: return false
        }
    }
}

enum CipherKey {
    case number(Int)
    case affine(Int, Int)
    case word([UInt8])

    var notation: String {
        switch self {
        case .number(let value): return String(value)
        case .affine(let multiplier, let offset): return "\(multiplier),\(offset)"
        case .word(let letters): return asciiString(letters)
        }
    }
}

struct JobError: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

enum OptionRule {
    case number(ClosedRange<Int>, Int)
    case keyList
}

struct Options {
    var numbers: [String: Int] = [:]
    var keys: String?

    subscript(_ name: String) -> Int { numbers[name]! }
}

let commands = ["ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY"]
let namingCommands = ["ENCRYPT", "DECRYPT", "BREAK"]

func isValidName(_ text: String) -> Bool {
    let bytes = Array(text.utf8)
    return (1...16).contains(bytes.count) && bytes.allSatisfy {
        (97...122).contains($0) || (48...57).contains($0) || $0 == 95
    }
}

func isDigitString(_ text: String, maxLength: Int) -> Bool {
    let bytes = Array(text.utf8)
    return (1...maxLength).contains(bytes.count) && bytes.allSatisfy { (48...57).contains($0) }
}

func parseKey(_ word: String, cipher: Cipher) throws -> CipherKey {
    let bytes = Array(word.utf8)
    switch cipher {
    case .caesar, .railfence:
        if isDigitString(word, maxLength: 2), let value = Int(word) {
            let range = cipher == .caesar ? 0...25 : 2...20
            if range.contains(value) { return .number(value) }
        }
    case .affine:
        let parts = word.components(separatedBy: ",")
        if parts.count == 2 && parts.allSatisfy({ isDigitString($0, maxLength: 2) }) {
            let multiplier = Int(parts[0])!
            let offset = Int(parts[1])!
            if affineMultipliers.contains(multiplier) && offset <= 25 {
                return .affine(multiplier, offset)
            }
        }
    case .columnar:
        if (2...9).contains(bytes.count) && bytes.allSatisfy({ isLetter($0) || (48...57).contains($0) }) {
            return .word(bytes.map(uppercaseLetter))
        }
    case .vigenere, .autokey, .playfair:
        let maximum = cipher == .playfair ? 25 : 20
        if (1...maximum).contains(bytes.count) && bytes.allSatisfy(isLetter) {
            let letters = bytes.map(uppercaseLetter)
            return .word(cipher == .playfair ? normalizePlayfair(letters) : letters)
        }
    }
    throw JobError("bad key \(word)")
}

func optionRules(_ command: String, cipher: Cipher? = nil) -> [String: OptionRule] {
    if command == "ANALYZE" { return ["MAXLEN": .number(2...20, 10)] }
    if command == "IDENTIFY" { return ["KEYS": .keyList] }
    var rules: [String: OptionRule] = ["TOP": .number(1...20, 5)]
    switch cipher! {
    case .caesar, .affine: break
    case .vigenere:
        rules["MAXLEN"] = .number(2...20, 10)
        rules["IOC"] = .number(1...100000, 6000)
        rules["KASISKI"] = .number(1...100, 60)
        rules["REFINE"] = .number(0...10, 5)
    case .autokey: rules["MAXLEN"] = .number(1...20, 8)
    case .railfence: rules["MAXRAILS"] = .number(2...20, 10)
    case .columnar: rules["MAXLEN"] = .number(2...6, 6)
    case .playfair: rules["KEYS"] = .keyList
    }
    return rules
}

func parseOptions(_ words: [String], rules: [String: OptionRule]) throws -> Options {
    var options = Options()
    for (name, rule) in rules {
        if case .number(_, let value) = rule { options.numbers[name] = value }
    }
    var seen: Set<String> = []
    for word in words {
        guard let equals = word.firstIndex(of: "=") else { throw JobError("bad option \(word)") }
        let name = String(word[..<equals])
        let value = String(word[word.index(after: equals)...])
        guard let rule = rules[name], seen.insert(name).inserted else {
            throw JobError("bad option \(word)")
        }
        switch rule {
        case .keyList:
            guard isValidName(value) else { throw JobError("bad option \(word)") }
            options.keys = value
        case .number(let range, _):
            guard isDigitString(value, maxLength: 6), let number = Int(value), range.contains(number) else {
                throw JobError("bad option \(word)")
            }
            options.numbers[name] = number
        }
    }
    return options
}

func applyCipher(_ cipher: Cipher, key: CipherKey, text: [UInt8], decrypt: Bool) -> [UInt8] {
    switch (cipher, key) {
    case (.caesar, .number(let shift)): return caesar(text, shift: shift, decrypt: decrypt)
    case (.affine, .affine(let multiplier, let offset)):
        return affine(text, multiplier: multiplier, offset: offset, decrypt: decrypt)
    case (.vigenere, .word(let letters)): return vigenere(text, key: letters, decrypt: decrypt)
    case (.autokey, .word(let letters)): return autokey(text, key: letters, decrypt: decrypt)
    case (.playfair, .word(let letters)): return playfair(text, key: letters, decrypt: decrypt)
    case (.railfence, .number(let rails)): return railFence(text, rails: rails, decrypt: decrypt)
    case (.columnar, .word(let letters)): return columnar(text, key: letters, decrypt: decrypt)
    default: preconditionFailure("invalid cipher key")
    }
}

func groupForm(_ letters: [UInt8]) -> [String] {
    stride(from: 0, to: letters.count, by: 50).map { start in
        let end = min(start + 50, letters.count)
        return stride(from: start, to: end, by: 5).map { position in
            asciiString(Array(letters[position..<min(position + 5, end)]))
        }.joined(separator: " ")
    }
}

func solutionLines(_ cipher: Cipher, key: CipherKey, text: [UInt8], letters: [UInt8]) -> [String] {
    let result = applyCipher(cipher, key: key, text: cipher.isSubstitution ? text : letters, decrypt: true)
    return cipher.isSubstitution ? asciiString(result).components(separatedBy: "\n") : groupForm(result)
}

func numberList(_ numbers: [Int]) -> String {
    numbers.map(String.init).joined(separator: ",")
}

func countList(_ counts: [(text: String, count: Int)]) -> String {
    counts.prefix(10).map { "\($0.text):\($0.count)" }.joined(separator: " ")
}

func asSuffix(_ name: String?) -> String {
    name.map { " as=\($0)" } ?? ""
}

func playfairKeyList(_ text: [UInt8]) -> [[UInt8]] {
    var keys: [[UInt8]] = []
    var seen: Set<String> = []
    var run: [UInt8] = []
    for byte in text + [0] {
        if isLetter(byte) {
            let upper = uppercaseLetter(byte)
            run.append(upper == 74 ? 73 : upper)
        } else if !run.isEmpty {
            if seen.insert(asciiString(run)).inserted { keys.append(run) }
            run.removeAll(keepingCapacity: true)
        }
    }
    return keys
}

func permutations(_ letters: [UInt8]) -> [[UInt8]] {
    if letters.isEmpty { return [[]] }
    var result: [[UInt8]] = []
    for index in letters.indices {
        var rest = letters
        let first = rest.remove(at: index)
        result += permutations(rest).map { [first] + $0 }
    }
    return result
}

struct Period {
    let length: Int
    let indices: [Int]
    let average: Int
    let kasiski: Int

    var line: String {
        "L=\(length) ioc=\(average) kasiski=\(kasiski) cols=\(numberList(indices))"
    }
}

struct PeriodProfile {
    let repeats: [RepeatedTrigram]
    let gapCount: Int
    let periods: [Period]

    init(_ letters: [UInt8], maxLength: Int) {
        let found = repeatedTrigrams(letters)
        let gaps = found.flatMap { $0.gaps }
        repeats = found
        gapCount = gaps.count
        periods = (1...maxLength).map { length in
            let indices = columnIndices(letters, period: length)
            return Period(length: length, indices: indices, average: indices.reduce(0, +) / length,
                          kasiski: gaps.filter { $0 % length == 0 }.count)
        }
    }

    func decision(_ options: Options) -> (length: Int, method: String) {
        if gapCount > 0,
           let period = periods.dropFirst().last(where: { 100 * $0.kasiski >= options["KASISKI"] * gapCount }),
           period.average >= options["IOC"] {
            return (period.length, "kasiski")
        }
        if let period = periods.first(where: { $0.average >= options["IOC"] }) {
            return (period.length, "ioc")
        }
        var best = periods[0]
        for period in periods.dropFirst() where period.average > best.average { best = period }
        return (best.length, "maxioc")
    }

    var lines: [String] {
        var result = periods.map { $0.line }
        result.append("kasiski repeats=\(repeats.count) spacings=\(gapCount)")
        result += repeats.map {
            "\($0.text) at=\(numberList($0.positions)) gaps=\(numberList($0.gaps)) gcd=\($0.gcd)"
        }
        return result
    }
}

struct Candidate {
    let key: CipherKey
    let plaintext: [UInt8]
    let score: Int
    let order: Int
}

struct BreakResult {
    let cipher: Cipher
    let candidates: [Candidate]
    var key: CipherKey
    var score: Int
    var profile: PeriodProfile?
    var length = 0
    var method = ""
    var passes = 0
    var changes = 0

    var margin: Int {
        candidates.count >= 2 ? candidates[0].score - candidates[1].score : 0
    }
}

final class CipherDesk {
    let weights: Weights
    var messages: [String: [String]]
    var jobCount = 0
    var okCounts = Dictionary(uniqueKeysWithValues: commands.map { ($0, 0) })
    var errorCounts = Dictionary(uniqueKeysWithValues: commands.map { ($0, 0) })
    var resultLines: [String] = []
    var candidateLines: [String] = []
    var analysisLines: [String] = []

    init(weights: Weights, messages: [String: [String]]) {
        self.weights = weights
        self.messages = messages
    }

    func messageText(_ name: String) throws -> [UInt8] {
        guard let lines = messages[name] else { throw JobError("unknown message \(name)") }
        return Array(lines.joined(separator: "\n").utf8)
    }

    func keyList(_ options: Options) throws -> [[UInt8]]? {
        guard let name = options.keys else { return nil }
        return playfairKeyList(try messageText(name))
    }

    func requireUnused(_ name: String?) throws {
        if let name, messages[name] != nil { throw JobError("duplicate message \(name)") }
    }

    func store(_ lines: [String], as name: String?) {
        if let name { messages[name] = lines }
    }

    func columnKey(_ cipher: Cipher, letters: [UInt8], length: Int) -> CipherKey {
        let key = textColumns(letters, period: length).map { column -> UInt8 in
            let counts = letterCounts(column)
            var bestShift = 0
            var bestScore = -1
            for shift in 0..<26 {
                let score: Int
                if cipher == .vigenere {
                    score = counts.indices.reduce(0) { $0 + counts[$1] * weights.monograms[modulo($1 - shift)] }
                } else {
                    var previous = shift
                    var total = 0
                    for letter in column {
                        previous = modulo(Int(letter - 65) - previous)
                        total += weights.monograms[previous]
                    }
                    score = total
                }
                if score > bestScore { bestScore = score; bestShift = shift }
            }
            return UInt8(65 + bestShift)
        }
        return .word(key)
    }

    func candidateKeys(_ cipher: Cipher, letters: [UInt8], options: Options, keys: [[UInt8]]?) -> [CipherKey] {
        switch cipher {
        case .caesar: return (0...25).map { .number($0) }
        case .affine: return affineMultipliers.flatMap { a in (0...25).map { .affine(a, $0) } }
        case .railfence: return (2...options["MAXRAILS"]).map { .number($0) }
        case .columnar:
            return (2...options["MAXLEN"]).flatMap { length in
                permutations((1...length).map { UInt8(48 + $0) }).map { .word($0) }
            }
        case .playfair: return keys!.map { .word($0) }
        case .vigenere, .autokey:
            return (1...options["MAXLEN"]).map { columnKey(cipher, letters: letters, length: $0) }
        }
    }

    func breakCipher(_ cipher: Cipher, letters: [UInt8], options: Options, keys: [[UInt8]]?) -> BreakResult {
        let candidates = candidateKeys(cipher, letters: letters, options: options, keys: keys).enumerated().map {
            order, key in
            let plaintext = applyCipher(cipher, key: key, text: letters, decrypt: true)
            let score = cipher == .caesar || cipher == .affine
                ? weights.monogramFitness(plaintext) : weights.bigramFitness(plaintext)
            return Candidate(key: key, plaintext: plaintext, score: score, order: order)
        }
        let ranked = candidates.sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
        var result = BreakResult(cipher: cipher, candidates: ranked, key: ranked[0].key, score: ranked[0].score)
        if cipher == .vigenere { refineVigenere(&result, letters: letters, candidates: candidates, options: options) }
        return result
    }

    func refineVigenere(_ result: inout BreakResult, letters: [UInt8], candidates: [Candidate], options: Options) {
        let profile = PeriodProfile(letters, maxLength: options["MAXLEN"])
        let decision = profile.decision(options)
        let initial = candidates[decision.length - 1]
        guard case .word(var key) = initial.key else { preconditionFailure("invalid Vigenere key") }
        var reference = initial.score
        var passes = 0
        var changes = 0
        while passes < options["REFINE"] {
            passes += 1
            var changed = false
            for index in key.indices {
                var trial = key
                var bestScore = -1
                var bestLetter: UInt8 = 65
                for letter in UInt8(65)...UInt8(90) {
                    trial[index] = letter
                    let score = weights.bigramFitness(vigenere(letters, key: trial, decrypt: true))
                    if score > bestScore { bestScore = score; bestLetter = letter }
                }
                if bestScore > reference {
                    key[index] = bestLetter
                    reference = bestScore
                    changes += 1
                    changed = true
                }
            }
            if !changed { break }
        }
        result.profile = profile
        result.length = decision.length
        result.method = decision.method
        result.key = .word(key)
        result.score = reference
        result.passes = passes
        result.changes = changes
    }

    func run(_ line: String) {
        jobCount += 1
        let words = line.components(separatedBy: " ")
        let command = words[0]
        guard commands.contains(command) else {
            resultLines.append("JOB \(jobCount) ERROR unknown command")
            return
        }
        do {
            try execute(command, words: words)
            okCounts[command, default: 0] += 1
        } catch let error as JobError {
            resultLines.append("JOB \(jobCount) ERROR \(error.reason)")
            errorCounts[command, default: 0] += 1
        } catch {
            preconditionFailure("unexpected job error")
        }
    }

    func execute(_ command: String, words original: [String]) throws {
        var words = original
        var newName: String?
        if namingCommands.contains(command) && words.count >= 5 && words[words.count - 2] == "AS" {
            guard isValidName(words.last!) else { throw JobError("bad syntax") }
            newName = words.removeLast()
            words.removeLast()
        }
        let valid: Bool
        switch command {
        case "ENCRYPT", "DECRYPT": valid = words.count == 4
        case "BREAK": valid = words.count >= 3
        case "ANALYZE", "IDENTIFY": valid = (2...3).contains(words.count)
        default: valid = words.count == 3
        }
        guard valid else { throw JobError("bad syntax") }
        switch command {
        case "ENCRYPT", "DECRYPT": try transform(command, words: words, newName: newName)
        case "BREAK": try breakMessage(words, newName: newName)
        case "ANALYZE": try analyze(words)
        case "COMPARE": try compare(words)
        default: try identify(words)
        }
    }

    func transform(_ command: String, words: [String], newName: String?) throws {
        guard let cipher = Cipher(rawValue: words[1]) else { throw JobError("unknown cipher \(words[1])") }
        let key = try parseKey(words[2], cipher: cipher)
        let source = words[3]
        let text = try messageText(source)
        try requireUnused(newName)
        let letters = letterString(text)
        guard !letters.isEmpty else { throw JobError("no letters") }
        if command == "DECRYPT" && cipher == .playfair && !isValidPlayfairCiphertext(letters) {
            throw JobError("bad playfair text")
        }
        let output = applyCipher(cipher, key: key, text: cipher.isSubstitution ? text : letters, decrypt: command == "DECRYPT")
        let lines = cipher.isSubstitution ? asciiString(output).components(separatedBy: "\n") : groupForm(output)
        resultLines.append("JOB \(jobCount) \(command) \(cipher.rawValue) key=\(key.notation) source=\(source) letters=\(letterString(output).count) lines=\(lines.count)\(asSuffix(newName))")
        resultLines += lines
        store(lines, as: newName)
    }

    func breakMessage(_ words: [String], newName: String?) throws {
        guard let cipher = Cipher(rawValue: words[1]) else { throw JobError("unknown cipher \(words[1])") }
        let source = words[2]
        let options = try parseOptions(Array(words.dropFirst(3)), rules: optionRules("BREAK", cipher: cipher))
        if cipher == .playfair && options.keys == nil { throw JobError("missing option KEYS") }
        let text = try messageText(source)
        let keys = try keyList(options)
        try requireUnused(newName)
        let letters = letterString(text)
        guard letters.count >= 40 else { throw JobError("text too short") }
        if cipher == .playfair {
            guard isValidPlayfairCiphertext(letters) else { throw JobError("bad playfair text") }
            guard !keys!.isEmpty else { throw JobError("empty key list") }
        }
        let result = breakCipher(cipher, letters: letters, options: options, keys: keys)
        let lines = solutionLines(cipher, key: result.key, text: text, letters: letters)
        resultLines.append("JOB \(jobCount) BREAK \(cipher.rawValue) source=\(source) key=\(result.key.notation) score=\(result.score) lines=\(lines.count)\(asSuffix(newName))")
        resultLines += lines
        store(lines, as: newName)
        candidateLines.append("JOB \(jobCount) BREAK \(cipher.rawValue) source=\(source) tried=\(result.candidates.count) margin=\(result.margin)")
        for (rank, candidate) in result.candidates.prefix(options["TOP"]).enumerated() {
            candidateLines.append("\(rank + 1) \(candidate.key.notation) \(candidate.score) \(asciiString(Array(candidate.plaintext.prefix(40))))")
        }
        if cipher == .vigenere {
            analysisLines += ["JOB \(jobCount) BREAK vigenere source=\(source)", "letters=\(letters.count)"]
            analysisLines += result.profile!.lines
            analysisLines.append("decision length=\(result.length) method=\(result.method)")
            analysisLines.append("refine passes=\(result.passes) changes=\(result.changes) key=\(result.key.notation)")
        } else if cipher == .playfair {
            let pairs = pairCounts(normalizePlayfair(letters), step: 2)
            guard case .word(let key) = result.key else { preconditionFailure("invalid Playfair key") }
            let square = playfairSquare(key)
            let rows = stride(from: 0, to: 25, by: 5).map { asciiString(Array(square[$0..<($0 + 5)])) }
            analysisLines += ["JOB \(jobCount) BREAK playfair source=\(source)", "letters=\(letters.count)",
                              "digraphs pairs=\(letters.count / 2) distinct=\(pairs.count)",
                              "top \(countList(pairs))", "square \(rows.joined(separator: " "))"]
        }
    }

    func analyze(_ words: [String]) throws {
        let source = words[1]
        let options = try parseOptions(Array(words.dropFirst(2)), rules: optionRules("ANALYZE"))
        let letters = letterString(try messageText(source))
        let count = letters.count
        guard count >= 40 else { throw JobError("text too short") }
        let counts = letterCounts(letters)
        var doubles = 0
        var pairDoubles = 0
        for index in 0..<(count - 1) where letters[index] == letters[index + 1] {
            doubles += 1
            if index % 2 == 0 { pairDoubles += 1 }
        }
        resultLines.append("JOB \(jobCount) ANALYZE source=\(source) letters=\(count)")
        analysisLines += ["JOB \(jobCount) ANALYZE source=\(source)", "letters=\(count)",
                          "ioc=\(coincidenceIndex(letters)) mono=\(weights.monogramFitness(letters)) bigram=\(weights.bigramFitness(letters))",
                          "doubles=\(doubles) pair_doubles=\(pairDoubles) distinct=\(counts.filter { $0 > 0 }.count)"]
        for value in 0..<26 {
            analysisLines.append("\(asciiString([UInt8(65 + value)])) \(counts[value]) \(percentage(counts[value], total: count))")
        }
        analysisLines.append("bigrams \(countList(pairCounts(letters, step: 1)))")
        analysisLines += PeriodProfile(letters, maxLength: options["MAXLEN"]).lines
    }

    func compare(_ words: [String]) throws {
        let first = letterString(try messageText(words[1]))
        let second = letterString(try messageText(words[2]))
        let prefix = "JOB \(jobCount) COMPARE \(words[1]) \(words[2])"
        if first == second {
            resultLines.append("\(prefix) equal letters=\(first.count)")
            return
        }
        let shared = min(first.count, second.count)
        var firstMismatch = shared + 1
        var mismatches = 0
        for index in 0..<shared where first[index] != second[index] {
            if mismatches == 0 { firstMismatch = index + 1 }
            mismatches += 1
        }
        resultLines.append("\(prefix) differ letters=\(first.count),\(second.count) first=\(firstMismatch) mismatches=\(mismatches)")
    }

    func identify(_ words: [String]) throws {
        let source = words[1]
        let options = try parseOptions(Array(words.dropFirst(2)), rules: optionRules("IDENTIFY"))
        let text = try messageText(source)
        let keys = try keyList(options)
        let letters = letterString(text)
        let count = letters.count
        guard count >= 40 else { throw JobError("text too short") }
        let ioc = coincidenceIndex(letters)
        let average = weights.monogramFitness(letters) / count
        let distinct = letterCounts(letters).filter { $0 > 0 }.count
        let shaped = count % 2 == 0 && !letters.contains(74) && isValidPlayfairCiphertext(letters)
        let family: String
        let ciphers: [Cipher]
        if shaped {
            family = "playfair"
            ciphers = keys == nil ? [] : [.playfair]
            if let keys, keys.isEmpty { throw JobError("empty key list") }
        } else if ioc >= 5500 && average >= 44 {
            family = "transposition"
            ciphers = [.railfence, .columnar]
        } else if ioc >= 5500 {
            family = "monoalphabetic"
            ciphers = [.affine]
        } else {
            family = "polyalphabetic"
            ciphers = [.vigenere, .autokey]
        }
        var tried: [BreakResult] = []
        for cipher in ciphers {
            let defaults = try parseOptions([], rules: optionRules("BREAK", cipher: cipher))
            tried.append(breakCipher(cipher, letters: letters, options: defaults, keys: keys))
        }
        analysisLines += ["JOB \(jobCount) IDENTIFY source=\(source)",
                          "letters=\(count) ioc=\(ioc) mono_avg=\(average) distinct=\(distinct) shape=\(shaped ? "yes" : "no")",
                          "family=\(family)"]
        for result in tried {
            analysisLines.append("try \(result.cipher.rawValue) key=\(result.key.notation) score=\(result.score)")
        }
        let header = "JOB \(jobCount) IDENTIFY source=\(source) family=\(family)"
        guard var chosen = tried.first else {
            resultLines.append(header)
            return
        }
        for result in tried.dropFirst() where result.score > chosen.score { chosen = result }
        var cipher = chosen.cipher
        var key = chosen.key
        if cipher == .affine, case .affine(1, let offset) = key {
            cipher = .caesar
            key = .number(offset)
        }
        let lines = solutionLines(cipher, key: key, text: text, letters: letters)
        resultLines.append("\(header) cipher=\(cipher.rawValue) key=\(key.notation) score=\(chosen.score) lines=\(lines.count)")
        resultLines += lines
        analysisLines.append("choice \(cipher.rawValue)")
    }

    func finish() {
        for command in commands {
            resultLines.append("TOTAL \(command) ok=\(okCounts[command]!) errors=\(errorCounts[command]!)")
        }
        let ok = okCounts.values.reduce(0, +)
        resultLines.append("SUMMARY jobs=\(jobCount) ok=\(ok) errors=\(jobCount - ok) messages=\(messages.count)")
    }
}

func parseMessages(_ text: String) -> [String: [String]] {
    var messages: [String: [String]] = [:]
    var name: String?
    var body: [String] = []
    for line in text.components(separatedBy: "\n") {
        if let current = name {
            if line == "END" {
                messages[current] = body
                name = nil
            } else {
                body.append(line)
            }
        } else if line.hasPrefix("MESSAGE ") {
            name = String(line.dropFirst(8))
            body = []
        }
    }
    return messages
}

func writeLines(_ lines: [String], path: String) throws {
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

func runCipherDesk() throws {
    let weights = Weights(try String(contentsOfFile: "input/weights.txt", encoding: .utf8))
    let messages = parseMessages(try String(contentsOfFile: "input/messages.txt", encoding: .utf8))
    let desk = CipherDesk(weights: weights, messages: messages)
    let jobs = try String(contentsOfFile: "input/jobs.txt", encoding: .utf8)
    for line in jobs.components(separatedBy: "\n") where !line.isEmpty && !line.hasPrefix("#") { desk.run(line) }
    desk.finish()
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines(desk.resultLines, path: "output/results.txt")
    try writeLines(desk.candidateLines, path: "output/candidates.txt")
    try writeLines(desk.analysisLines, path: "output/analysis.txt")
}

try runCipherDesk()
