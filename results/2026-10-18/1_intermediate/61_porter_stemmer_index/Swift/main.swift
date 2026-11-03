struct CommandError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct Rule: Sendable {
    let suffix: String
    let replacement: String
    let condition: @Sendable (String) -> Bool
}

enum Porter {
    static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
    static let stepNames = ["1a", "1b", "1c", "2", "3", "4", "5a", "5b"]
    static let step4Suffixes = [
        "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
        "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
    ]
    static let ruleTables: [String: [Rule]] = [
        "1a": rules(always, [("sses", "ss"), ("ies", "i"), ("ss", "ss"), ("s", "")]),
        "1b": [
            Rule(suffix: "eed", replacement: "ee", condition: measureAboveZero),
            Rule(suffix: "ed", replacement: "", condition: hasVowel),
            Rule(suffix: "ing", replacement: "", condition: hasVowel),
        ],
        "1c": [Rule(suffix: "y", replacement: "i", condition: hasVowel)],
        "2": rules(measureAboveZero, [
            ("ational", "ate"), ("tional", "tion"), ("enci", "ence"), ("anci", "ance"),
            ("izer", "ize"), ("abli", "able"), ("alli", "al"), ("entli", "ent"), ("eli", "e"),
            ("ousli", "ous"), ("ization", "ize"), ("ation", "ate"), ("ator", "ate"),
            ("alism", "al"), ("iveness", "ive"), ("fulness", "ful"), ("ousness", "ous"),
            ("aliti", "al"), ("iviti", "ive"), ("biliti", "ble"),
        ]),
        "3": rules(measureAboveZero, [
            ("icate", "ic"), ("ative", ""), ("alize", "al"), ("iciti", "ic"),
            ("ical", "ic"), ("ful", ""), ("ness", ""),
        ]),
        "4": step4Suffixes.map { suffix in
            Rule(
                suffix: suffix, replacement: "",
                condition: suffix == "ion" ? ionCondition : measureAboveOne)
        },
        "5a": [Rule(suffix: "e", replacement: "", condition: finalECondition)],
    ]

    static func rules(
        _ condition: @escaping @Sendable (String) -> Bool, _ pairs: [(String, String)]
    ) -> [Rule] {
        pairs.map { Rule(suffix: $0.0, replacement: $0.1, condition: condition) }
    }

    static func letterPattern(_ word: String) -> String {
        var kinds: [Character] = []
        for (index, letter) in word.enumerated() {
            let vowel =
                vowels.contains(letter) || (letter == "y" && index > 0 && kinds[index - 1] == "C")
            kinds.append(vowel ? "V" : "C")
        }
        return String(kinds)
    }

    static func measure(_ word: String) -> Int {
        let kinds = Array(letterPattern(word))
        return zip(kinds, kinds.dropFirst()).filter { $0 == "V" && $1 == "C" }.count
    }

    static func hasVowel(_ word: String) -> Bool {
        letterPattern(word).contains("V")
    }

    static func endsDouble(_ word: String) -> Bool {
        letterPattern(word).hasSuffix("CC") && word.last == word.dropLast().last
    }

    static func endsCvc(_ word: String) -> Bool {
        letterPattern(word).hasSuffix("CVC") && !"wxy".contains(word.last!)
    }

    static func always(_ remainder: String) -> Bool {
        true
    }

    static func measureAboveZero(_ remainder: String) -> Bool {
        measure(remainder) > 0
    }

    static func measureAboveOne(_ remainder: String) -> Bool {
        measure(remainder) > 1
    }

    static func ionCondition(_ remainder: String) -> Bool {
        measure(remainder) > 1 && (remainder.hasSuffix("s") || remainder.hasSuffix("t"))
    }

    static func finalECondition(_ remainder: String) -> Bool {
        let value = measure(remainder)
        return value > 1 || (value == 1 && !endsCvc(remainder))
    }

    static func applyRules(_ word: String, _ rules: [Rule]) -> (word: String, suffix: String?) {
        let matching = rules.filter { word.hasSuffix($0.suffix) }
        guard let rule = matching.max(by: { $0.suffix.count < $1.suffix.count }) else {
            return (word, nil)
        }
        let remainder = String(word.dropLast(rule.suffix.count))
        guard rule.condition(remainder) else {
            return (word, nil)
        }
        return (remainder + rule.replacement, rule.suffix)
    }

    static func tidyStep1b(_ word: String) -> String {
        if word.hasSuffix("at") || word.hasSuffix("bl") || word.hasSuffix("iz") {
            return word + "e"
        }
        if endsDouble(word) && !"lsz".contains(word.last!) {
            return String(word.dropLast())
        }
        if measure(word) == 1 && endsCvc(word) {
            return word + "e"
        }
        return word
    }

    static func applyStep(_ name: String, _ word: String) -> String {
        if name == "5b" {
            if measure(word) > 1 && endsDouble(word) && word.hasSuffix("l") {
                return String(word.dropLast())
            }
            return word
        }
        let (result, suffix) = applyRules(word, ruleTables[name]!)
        if name == "1b" && (suffix == "ed" || suffix == "ing") {
            return tidyStep1b(result)
        }
        return result
    }

    static func stemmingSteps(
        _ word: String
    ) -> (stem: String, changes: [(name: String, result: String)]) {
        var word = word
        var changes: [(name: String, result: String)] = []
        if word.count > 2 {
            for name in stepNames {
                let result = applyStep(name, word)
                if result != word {
                    changes.append((name, result))
                }
                word = result
            }
        }
        return (word, changes)
    }

    static func stem(_ word: String) -> String {
        stemmingSteps(word).stem
    }
}

func isLetter(_ character: Character) -> Bool {
    character.isASCII && character.isLetter
}

func isWord(_ text: String) -> Bool {
    (1...30).contains(text.count) && text.allSatisfy(isLetter)
}

func yesNo(_ flag: Bool) -> String {
    flag ? "YES" : "NO"
}

func wordArgument(_ text: String) throws -> String {
    guard isWord(text) else {
        throw CommandError("BAD WORD \(text)")
    }
    return text.lowercased()
}

func numberArgument(_ text: String, _ minimum: Int, _ maximum: Int) throws -> Int {
    guard (1...7).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }),
        let value = Int(text), (minimum...maximum).contains(value)
    else {
        throw CommandError("BAD NUMBER \(text)")
    }
    return value
}

func splitArguments(_ name: String, _ rest: String) -> [String] {
    switch name {
    case "SEARCH":
        return [rest]
    case "APPEND":
        return rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
    default:
        return rest.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    }
}

func byCount(_ counts: [String: Int]) -> [(key: String, value: Int)] {
    counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
}

func closestDistance(_ positions: [Int], _ others: [Int], sameStem: Bool) -> Int? {
    if sameStem {
        return zip(positions, positions.dropFirst()).map { $1 - $0 }.min()
    }
    let tagged = positions.map { (position: $0, kind: 0) } + others.map { (position: $0, kind: 1) }
    let merged = tagged.sorted { $0.position < $1.position }
    return zip(merged, merged.dropFirst())
        .filter { $0.kind != $1.kind }
        .map { $1.position - $0.position }
        .min()
}

enum Lexeme: Equatable {
    case and, or, not, open, close
    case term(String)
    case prefix(String)
}

func lexemes(_ expression: String) -> [String] {
    var found: [String] = []
    var current = ""
    for character in expression {
        if character == " " || character == "(" || character == ")" {
            if !current.isEmpty {
                found.append(current)
                current = ""
            }
            if character != " " {
                found.append(String(character))
            }
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty {
        found.append(current)
    }
    return found
}

func classify(_ text: String) throws -> Lexeme {
    switch text {
    case "AND": return .and
    case "OR": return .or
    case "NOT": return .not
    case "(": return .open
    case ")": return .close
    default:
        if isWord(text) {
            return .term(text.lowercased())
        }
        let spelling = String(text.dropLast())
        if text.hasSuffix("*") && isWord(spelling) {
            return .prefix(spelling.lowercased())
        }
        throw CommandError("BAD TERM \(text)")
    }
}

struct Token {
    let text: String
    let form: String
    let stem: String
    let line: Int
    let position: Int
    let start: Int

    var end: Int { start + text.count }
}

final class Document {
    let number: Int
    private(set) var lines: [String] = []
    private(set) var tokens: [Token] = []

    init(number: Int) {
        self.number = number
    }

    @discardableResult
    func addLine(_ text: String) -> ArraySlice<Token> {
        lines.append(text)
        let first = tokens.count
        let characters = Array(text)
        var start = 0
        while start < characters.count {
            guard isLetter(characters[start]) else {
                start += 1
                continue
            }
            var end = start
            while end < characters.count && isLetter(characters[end]) {
                end += 1
            }
            let word = String(characters[start..<end])
            let form = word.lowercased()
            tokens.append(
                Token(
                    text: word, form: form, stem: Porter.stem(form), line: lines.count,
                    position: tokens.count + 1, start: start))
            start = end
        }
        return tokens[first...]
    }

    func lineTokens(_ lineNumber: Int) -> [Token] {
        tokens.filter { $0.line == lineNumber }
    }

    func reference(_ token: Token) -> String {
        "\(number):\(token.line):\(token.position)"
    }
}

typealias Occurrence = (document: Document, token: Token)
typealias Evaluation = (canonical: String, documents: Set<Int>)

func documentCount(_ occurrences: [Occurrence]) -> Int {
    Set(occurrences.map(\.document.number)).count
}

final class QueryParser {
    private let items: [Lexeme]
    private let stemSets: [Int: Set<String>]
    private var position = 0

    init(items: [Lexeme], stemSets: [Int: Set<String>]) {
        self.items = items
        self.stemSets = stemSets
    }

    private func peek() -> Lexeme? {
        position < items.count ? items[position] : nil
    }

    private func take() throws -> Lexeme {
        guard position < items.count else {
            throw CommandError("SYNTAX")
        }
        position += 1
        return items[position - 1]
    }

    func parse() throws -> Evaluation {
        let result = try expression()
        if position < items.count {
            throw CommandError("SYNTAX")
        }
        return result
    }

    private func expression() throws -> Evaluation {
        var (canonical, documents) = try conjunction()
        while peek() == .or {
            position += 1
            let (right, rightDocuments) = try conjunction()
            canonical = "(\(canonical) OR \(right))"
            documents.formUnion(rightDocuments)
        }
        return (canonical, documents)
    }

    private func continuesConjunction() -> Bool {
        switch peek() {
        case .and, .not, .open, .term, .prefix:
            return true
        default:
            return false
        }
    }

    private func conjunction() throws -> Evaluation {
        var (canonical, documents) = try negation()
        while continuesConjunction() {
            if peek() == .and {
                position += 1
            }
            let (right, rightDocuments) = try negation()
            canonical = "(\(canonical) AND \(right))"
            documents.formIntersection(rightDocuments)
        }
        return (canonical, documents)
    }

    private func negation() throws -> Evaluation {
        if peek() == .not {
            position += 1
            let (canonical, documents) = try negation()
            return ("(NOT \(canonical))", Set(stemSets.keys).subtracting(documents))
        }
        return try element()
    }

    private func element() throws -> Evaluation {
        switch try take() {
        case .open:
            let result = try expression()
            guard try take() == .close else {
                throw CommandError("SYNTAX")
            }
            return result
        case .term(let spelling):
            let stem = Porter.stem(spelling)
            return (stem, matching { stems in stems.contains(stem) })
        case .prefix(let spelling):
            let documents = matching { stems in stems.contains { $0.hasPrefix(spelling) } }
            return ("\(spelling)*", documents)
        default:
            throw CommandError("SYNTAX")
        }
    }

    private func matching(_ predicate: (Set<String>) -> Bool) -> Set<Int> {
        Set(stemSets.filter { predicate($0.value) }.keys)
    }
}

struct Fraction: Comparable, CustomStringConvertible {
    let numerator: Int
    let denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        let divisor = gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    var description: String { "\(numerator)/\(denominator)" }

    static func < (lhs: Fraction, rhs: Fraction) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }
}

func gcd(_ a: Int, _ b: Int) -> Int {
    b == 0 ? a : gcd(b, a % b)
}

final class SearchEngine {
    static let kwicWidth = 30
    static let maxCount = 100
    static let maxDocumentNumber = 999
    static let maxLineNumber = 999

    private var stopwords: Set<String>
    private var documents: [Int: Document] = [:]
    private(set) var output: [String] = []

    private typealias Handler = ([String]) throws -> Void

    private lazy var handlers: [String: (minimum: Int, maximum: Int, handler: Handler)] = [
        "STEM": (1, 10, stemWords),
        "STEPS": (1, 1, showSteps),
        "MEASURE": (1, 1, showMeasure),
        "INDEX": (0, 1, showIndex),
        "SEARCH": (1, 1, search),
        "PHRASE": (2, 10, phrase),
        "NEAR": (3, 3, near),
        "TOP": (1, 2, top),
        "KWIC": (1, 1, kwic),
        "TF": (2, 2, termFrequency),
        "DF": (1, 1, documentFrequency),
        "VARIANTS": (1, 1, variants),
        "SIMILAR": (2, 2, similar),
        "RANK": (2, 11, rank),
        "INFO": (1, 1, info),
        "LINE": (2, 2, showLine),
        "STATS": (0, 0, stats),
        "STOP": (1, 1, stop),
        "UNSTOP": (1, 1, unstop),
        "APPEND": (2, 2, append),
        "DELETE": (1, 1, delete),
    ]

    init(stopwords: Set<String>) {
        self.stopwords = stopwords
    }

    private func emit(_ parts: [String]) {
        output.append(parts.joined(separator: " "))
    }

    func addDocument(_ number: Int) -> Document {
        let document = Document(number: number)
        documents[number] = document
        return document
    }

    private func orderedDocuments() -> [Document] {
        documents.keys.sorted().map { documents[$0]! }
    }

    private func isIndexed(_ token: Token) -> Bool {
        !stopwords.contains(token.form)
    }

    private func indexedTokens(_ document: Document) -> [Token] {
        document.tokens.filter(isIndexed)
    }

    private func termFrequencies(_ document: Document) -> [String: Int] {
        indexedTokens(document).reduce(into: [:]) { counts, token in
            counts[token.stem, default: 0] += 1
        }
    }

    private func stemSet(_ document: Document) -> Set<String> {
        Set(indexedTokens(document).map(\.stem))
    }

    private func totalFrequencies() -> [String: Int] {
        documents.values.reduce(into: [:]) { totals, document in
            totals.merge(termFrequencies(document), uniquingKeysWith: +)
        }
    }

    private func occurrenceMap() -> [String: [Occurrence]] {
        var occurrences: [String: [Occurrence]] = [:]
        for document in orderedDocuments() {
            for token in indexedTokens(document) {
                occurrences[token.stem, default: []].append((document, token))
            }
        }
        return occurrences
    }

    private func stemPositions(_ document: Document, _ stem: String) -> [Int] {
        indexedTokens(document).filter { $0.stem == stem }.map(\.position)
    }

    private func formCount(_ form: String) -> Int {
        documents.values.map { document in document.tokens.filter { $0.form == form }.count }
            .reduce(0, +)
    }

    private func tokenMatches(_ token: Token, _ target: String) -> Bool {
        target == "?" || (isIndexed(token) && token.stem == target)
    }

    private func describeToken(_ token: Token) -> String {
        isIndexed(token) ? "\(token.form)/\(token.stem)" : "\(token.form)/-"
    }

    private func termArgument(_ text: String) throws -> String {
        let word = try wordArgument(text)
        if stopwords.contains(word) {
            throw CommandError("STOPWORD \(word)")
        }
        return Porter.stem(word)
    }

    private func documentArgument(_ text: String) throws -> Document {
        let number = try numberArgument(text, 1, Self.maxDocumentNumber)
        guard let document = documents[number] else {
            throw CommandError("NO DOC \(number)")
        }
        return document
    }

    private func stemWords(_ arguments: [String]) throws {
        let words = try arguments.map(wordArgument)
        emit(["STEM"] + words.map { "\($0):\(Porter.stem($0))" })
    }

    private func showSteps(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        let changes = Porter.stemmingSteps(word).changes
        if changes.isEmpty {
            emit(["STEPS", word, "NONE"])
        } else {
            emit(["STEPS", word] + changes.map { "\($0.name):\($0.result)" })
        }
    }

    private func showMeasure(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        emit([
            "MEASURE", word, Porter.letterPattern(word), "m=\(Porter.measure(word))",
            "vowel=\(yesNo(Porter.hasVowel(word)))", "double=\(yesNo(Porter.endsDouble(word)))",
            "cvc=\(yesNo(Porter.endsCvc(word)))",
        ])
    }

    private func showIndex(_ arguments: [String]) throws {
        let prefix = try arguments.first.map(wordArgument) ?? ""
        let occurrences = occurrenceMap()
        let stems = occurrences.keys.filter { $0.hasPrefix(prefix) }.sorted()
        emit(["INDEX", "stems=\(stems.count)"])
        for stem in stems {
            let found = occurrences[stem]!
            let references = found.map { $0.document.reference($0.token) }
            emit([stem, "df=\(documentCount(found))"] + references)
        }
    }

    private func search(_ arguments: [String]) throws {
        let items = try lexemes(arguments[0]).map(classify)
        let stemSets = documents.mapValues(stemSet)
        let (canonical, matches) = try QueryParser(items: items, stemSets: stemSets).parse()
        for case .term(let spelling) in items where stopwords.contains(spelling) {
            throw CommandError("STOPWORD \(spelling)")
        }
        emit(["SEARCH", canonical, "count=\(matches.count)"] + matches.sorted().map(String.init))
    }

    private func phrase(_ arguments: [String]) throws {
        let words = try arguments.map(wordArgument)
        if words.allSatisfy(stopwords.contains) {
            throw CommandError("STOPWORDS ONLY")
        }
        let targets = words.map { stopwords.contains($0) ? "?" : Porter.stem($0) }
        var matches: [String] = []
        for document in orderedDocuments() {
            let tokens = document.tokens
            guard tokens.count >= targets.count else {
                continue
            }
            for start in 0...(tokens.count - targets.count)
            where targets.indices.allSatisfy({ tokenMatches(tokens[start + $0], targets[$0]) }) {
                matches.append(document.reference(tokens[start]))
            }
        }
        let phraseText = targets.joined(separator: " ")
        emit(["PHRASE \"\(phraseText)\"", "matches=\(matches.count)"] + matches)
    }

    private func near(_ arguments: [String]) throws {
        let first = try termArgument(arguments[0])
        let second = try termArgument(arguments[1])
        let limit = try numberArgument(arguments[2], 1, Self.maxCount)
        var found: [String] = []
        for document in orderedDocuments() {
            let distance = closestDistance(
                stemPositions(document, first), stemPositions(document, second),
                sameStem: first == second)
            if let distance, distance <= limit {
                found.append("\(document.number):\(distance)")
            }
        }
        emit(["NEAR", first, second, "\(limit)", "count=\(found.count)"] + found)
    }

    private func top(_ arguments: [String]) throws {
        let limit = try numberArgument(arguments[0], 1, Self.maxCount)
        let counts: [String: Int]
        let header: String
        if arguments.count == 2 {
            let document = try documentArgument(arguments[1])
            counts = termFrequencies(document)
            header = "TOP \(limit) doc=\(document.number)"
        } else {
            counts = totalFrequencies()
            header = "TOP \(limit)"
        }
        emit([header] + byCount(counts).prefix(limit).map { "\($0.key):\($0.value)" })
    }

    private func kwic(_ arguments: [String]) throws {
        let stem = try termArgument(arguments[0])
        let found = occurrenceMap()[stem] ?? []
        emit(["KWIC", stem, "count=\(found.count)"])
        let width = Self.kwicWidth
        for (document, token) in found {
            let text = Array(document.lines[token.line - 1])
            let before = String(text[max(0, token.start - width)..<token.start])
            let after = String(text[token.end..<min(text.count, token.end + width)])
            let left = String(repeating: " ", count: width - before.count) + before
            let right = after + String(repeating: " ", count: width - after.count)
            emit(["|\(left)[\(token.text)]\(right)|", document.reference(token)])
        }
    }

    private func termFrequency(_ arguments: [String]) throws {
        let document = try documentArgument(arguments[0])
        let stem = try termArgument(arguments[1])
        emit(["TF", "\(document.number)", stem, "\(termFrequencies(document)[stem, default: 0])"])
    }

    private func documentFrequency(_ arguments: [String]) throws {
        let stem = try termArgument(arguments[0])
        emit(["DF", stem, "\(documentCount(occurrenceMap()[stem] ?? []))"])
    }

    private func variants(_ arguments: [String]) throws {
        let stem = try termArgument(arguments[0])
        let found = occurrenceMap()[stem] ?? []
        let forms = found.reduce(into: [String: Int]()) { counts, occurrence in
            counts[occurrence.token.form, default: 0] += 1
        }
        let items = forms.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }
        emit(["VARIANTS", stem, "count=\(forms.count)"] + items)
    }

    private func similar(_ arguments: [String]) throws {
        let document = try documentArgument(arguments[0])
        let limit = try numberArgument(arguments[1], 1, Self.maxCount)
        let stems = stemSet(document)
        var scores: [(score: Fraction, number: Int)] = []
        for other in documents.values where other !== document {
            let otherStems = stemSet(other)
            let union = stems.union(otherStems).count
            let score =
                union > 0 ? Fraction(stems.intersection(otherStems).count, union) : Fraction(0, 1)
            scores.append((score, other.number))
        }
        scores.sort { ($1.score, $0.number) < ($0.score, $1.number) }
        let items = scores.prefix(limit).map { "\($0.number):\($0.score)" }
        emit(["SIMILAR", "\(document.number)"] + items)
    }

    private func rank(_ arguments: [String]) throws {
        let limit = try numberArgument(arguments[0], 1, Self.maxCount)
        let query = try Set(arguments.dropFirst().map(termArgument))
        var ranked: [(matched: Int, total: Int, number: Int)] = []
        for document in documents.values {
            let counts = termFrequencies(document)
            let matched = query.filter { counts[$0] != nil }.count
            let total = query.map { counts[$0, default: 0] }.reduce(0, +)
            if matched > 0 {
                ranked.append((matched, total, document.number))
            }
        }
        ranked.sort { ($1.matched, $1.total, $0.number) < ($0.matched, $0.total, $1.number) }
        let items = ranked.prefix(limit).map { "\($0.number):\($0.matched):\($0.total)" }
        emit(["RANK count=\(ranked.count)"] + items)
    }

    private func info(_ arguments: [String]) throws {
        let document = try documentArgument(arguments[0])
        let counts = termFrequencies(document)
        let top = byCount(counts).first.map { "\($0.key):\($0.value)" } ?? "-"
        emit([
            "INFO", "\(document.number)", "lines=\(document.lines.count)",
            "tokens=\(document.tokens.count)", "indexed=\(counts.values.reduce(0, +))",
            "stems=\(counts.count)", "top=\(top)",
        ])
    }

    private func showLine(_ arguments: [String]) throws {
        let document = try documentArgument(arguments[0])
        let lineNumber = try numberArgument(arguments[1], 1, Self.maxLineNumber)
        if lineNumber > document.lines.count {
            throw CommandError("NO LINE \(document.number):\(lineNumber)")
        }
        let tokens = document.lineTokens(lineNumber)
        let header = "LINE \(document.number):\(lineNumber)"
        emit([header, "tokens=\(tokens.count)"] + tokens.map(describeToken))
    }

    private func stats(_ arguments: [String]) throws {
        let all = Array(documents.values)
        emit([
            "STATS", "docs=\(all.count)", "lines=\(all.map(\.lines.count).reduce(0, +))",
            "tokens=\(all.map(\.tokens.count).reduce(0, +))",
            "indexed=\(all.map { indexedTokens($0).count }.reduce(0, +))",
            "stems=\(totalFrequencies().count)", "stopwords=\(stopwords.count)",
        ])
    }

    private func stop(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        guard stopwords.insert(word).inserted else {
            throw CommandError("ALREADY STOPWORD \(word)")
        }
        emit(["STOP", word, "unindexed=\(formCount(word))"])
    }

    private func unstop(_ arguments: [String]) throws {
        let word = try wordArgument(arguments[0])
        guard stopwords.remove(word) != nil else {
            throw CommandError("NOT STOPWORD \(word)")
        }
        emit(["UNSTOP", word, "indexed=\(formCount(word))"])
    }

    private func append(_ arguments: [String]) throws {
        let number = try numberArgument(arguments[0], 1, Self.maxDocumentNumber)
        let created = documents[number] == nil
        let document = documents[number] ?? addDocument(number)
        let tokens = document.addLine(arguments[1])
        emit([
            "APPEND", "\(number)", "line=\(document.lines.count)", "tokens=\(tokens.count)",
            "indexed=\(tokens.filter(isIndexed).count)", "new=\(yesNo(created))",
        ])
    }

    private func delete(_ arguments: [String]) throws {
        let document = try documentArgument(arguments[0])
        documents[document.number] = nil
        emit([
            "DELETE", "\(document.number)", "lines=\(document.lines.count)",
            "tokens=\(document.tokens.count)",
        ])
    }

    func execute(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0])
        do {
            guard let command = handlers[name] else {
                throw CommandError("UNKNOWN COMMAND \(name)")
            }
            let arguments = parts.count > 1 ? splitArguments(name, String(parts[1])) : []
            guard (command.minimum...command.maximum).contains(arguments.count) else {
                throw CommandError("BAD ARGUMENTS \(name)")
            }
            try command.handler(arguments)
        } catch {
            emit(["ERROR", "\(error)"])
        }
    }
}

var lines: [String] = []
while let line = readLine() {
    lines.append(line)
}
let stopwords = lines[0].split(separator: " ").dropFirst().map(String.init)
let engine = SearchEngine(stopwords: Set(stopwords))
var index = 1
while lines[index].hasPrefix("DOC ") {
    let document = engine.addDocument(Int(lines[index].dropFirst(4))!)
    index += 1
    while lines[index] != "ENDDOC" {
        document.addLine(lines[index])
        index += 1
    }
    index += 1
}
for line in lines[index...] {
    if line == "END" {
        break
    }
    engine.execute(line)
}
print(engine.output.joined(separator: "\n"))
