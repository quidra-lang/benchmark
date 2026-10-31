import Foundation

struct Meta {
    let id: String
    let row: String
    let dan: String
    let contracted: Bool
}

struct Mora {
    let id: String
    let column: Int
}

struct Word {
    let text: String
    let start: Int
    var pattern = 0
    var morae: [Mora] = []
}

struct SyllableMatch {
    let id: String
    let length: Int
}

struct LongInfo {
    var paired: [Bool]
    var elements: [Bool]
    var vowels: [String]
}

struct Element {
    let base: String
    let voice: Int
    let size: Int
}

enum Problem: Error {
    case message(String)
}

final class Converter {
    let systems = ["HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO"]
    let rows = ["a", "ka", "sa", "ta", "na", "ha", "ma", "ya", "ra", "wa", "ga", "za", "da", "ba", "pa"]
    let gojuon = "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N"
    let iroha = "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N"
    let counts = [
            "CONVERT": 2, "NORMALIZE": 0, "REVERSE": 1, "VALID": 1, "DETECT": 0,
            "DIFF": 2, "SAME": 2, "MORAE": 1, "SYLLABLES": 1, "ROW": 1,
            "STATS": 1, "SORT": 1, "INDEX": 1, "FIND": 2, "HAIKU": 1,
            "KAIBUN": 1, "SHIRITORI": 1
        ]
    var table: [Meta] = []
    var metadata: [String: Meta] = [:]
    var readers: [String: [String: String]] = [:]
    var longSetting = "KEEP"
    var caseSetting = "KEEP"
    var orderSetting = "GOJUON"

    init() {
        let basicRows = [
            "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
            "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo",
            "ra ri ru re ro", "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo",
            "da di du de do", "ba bi bu be bo", "pa pi pu pe po"
        ]
        for (index, text) in basicRows.enumerated() {
            for token in text.split(separator: " ") {
                let id = String(token)
                table.append(Meta(id: id, row: rows[index], dan: String(id.last!), contracted: false))
            }
        }
        for row in ["ka", "sa", "ta", "na", "ha", "ma", "ra", "ga", "za", "da", "ba", "pa"] {
            for dan in ["ya", "yu", "yo"] {
                let id = String(row.first!) + dan
                table.append(Meta(id: id, row: row, dan: dan, contracted: true))
            }
        }
        for meta in table {
            metadata[meta.id] = meta
        }
        for system in systems + ["ANY"] {
            readers[system] = [:]
        }
        for meta in table {
            for system in systems {
                let written = spelling(system, meta.id)
                if readers[system]![written] == nil {
                    readers[system]![written] = meta.id
                }
                if readers["ANY"]![written] == nil {
                    readers["ANY"]![written] = meta.id
                }
            }
        }
    }

    func column(_ value: Int, _ message: String) -> Problem {
        .message("col \(value): \(message)")
    }

    func letter(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
    }

    func begins(_ text: String, _ choices: String) -> Bool {
        text.first.map { choices.contains($0) } ?? false
    }

    func regular(_ id: String) -> Bool {
        metadata[id] != nil
    }

    func vowel(_ id: String) -> Bool {
        id.count == 1 && "aiueo".contains(id)
    }

    func slice(_ text: String, _ start: Int, _ end: Int? = nil) -> String {
        String(text.dropFirst(start).prefix((end ?? text.count) - start))
    }

    func devoice(_ id: String) -> String {
        let voiced = Array("gzdbp")
        guard let index = voiced.firstIndex(of: id.first!) else {
            return id
        }
        return String(Array("ksthh")[index]) + slice(id, 1)
    }

    func baseRow(_ row: String) -> String {
        switch row {
        case "ga": return "ka"
        case "za": return "sa"
        case "da": return "ta"
        case "ba", "pa": return "ha"
        default: return row
        }
    }

    func voice(_ row: String) -> Int {
        row == "pa" ? 2 : (["ga", "za", "da", "ba"].contains(row) ? 1 : 0)
    }

    func spelling(_ system: String, _ id: String) -> String {
        let hepburn = system == "HEPBURN" || system == "TRADITIONAL"
        let wapuro = system == "WAPURO"
        if hepburn || wapuro {
            let result: String
            switch id {
            case "si": result = "shi"
            case "ti": result = "chi"
            case "tu": result = "tsu"
            case "hu": result = "fu"
            case "zi": result = "ji"
            case "di": result = hepburn ? "ji" : id
            case "du": result = hepburn ? "zu" : id
            case "wi": result = hepburn ? "i" : id
            case "we": result = hepburn ? "e" : id
            case "wo": result = hepburn ? "o" : id
            default: result = id
            }
            if id.hasPrefix("sy") {
                return "sh" + String(id.last!)
            }
            if id.hasPrefix("ty") {
                return "ch" + String(id.last!)
            }
            if id.hasPrefix("zy") || (hepburn && id.hasPrefix("dy")) {
                return "j" + String(id.last!)
            }
            return result
        }
        if system == "KUNREI" {
            switch id {
            case "di": return "zi"
            case "du": return "zu"
            case "wi": return "i"
            case "we": return "e"
            case "wo": return "o"
            default: return id.hasPrefix("dy") ? "z" + slice(id, 1) : id
            }
        }
        return id
    }

    func match(_ text: String, _ position: Int, _ system: String) -> SyllableMatch? {
        let maximum = min(3, text.count - position)
        if maximum < 1 {
            return nil
        }
        for length in stride(from: maximum, through: 1, by: -1) {
            if let id = readers[system]![slice(text, position, position + length)] {
                return SyllableMatch(id: id, length: length)
            }
        }
        return nil
    }

    func parse(_ word: Word, _ system: String) throws -> [Mora] {
        let text = word.text.lowercased()
        let characters = Array(text)
        let normalize = system == "ANY"
        var result: [Mora] = []
        var position = 0
        while position < characters.count {
            let c = characters[position]
            let next: Character = position + 1 < characters.count ? characters[position + 1] : "\0"
            let at = word.start + position + 1
            let id: String
            let advance: Int
            if c == "-" {
                guard let previous = result.last, regular(previous.id) else {
                    throw column(at, "misplaced long mark")
                }
                id = "L"
                advance = 1
            } else if c == "'" {
                throw column(at, "misplaced apostrophe")
            } else if let syllable = match(text, position, system) {
                id = syllable.id
                advance = syllable.length
            } else if (normalize || system == "WAPURO") && slice(text, position).hasPrefix("xtu") {
                id = "Q"
                advance = 3
            } else if c == "n" {
                id = "N"
                if normalize {
                    let third: Character = position + 2 < characters.count ? characters[position + 2] : "\0"
                    advance = next == "'" || (next == "n" && !"aiueoy'".contains(third)) ? 2 : 1
                } else if system == "WAPURO" {
                    advance = next == "n" ? 2 : 1
                } else {
                    advance = next == "'" ? 2 : 1
                }
            } else if (normalize || system == "TRADITIONAL") && c == "m" && "bmp".contains(next) {
                id = "N"
                advance = 1
            } else if letter(c) && !"aiueon".contains(c) && c == next && match(text, position + 1, system) != nil {
                id = "Q"
                advance = 1
            } else if (normalize || system == "HEPBURN" || system == "TRADITIONAL") && c == "t" &&
                        slice(text, position + 1).hasPrefix("ch") && match(text, position + 1, system) != nil {
                id = "Q"
                advance = 1
            } else {
                throw column(at, "unknown syllable")
            }
            result.append(Mora(id: id, column: at))
            position += advance
        }
        return result
    }

    func scan(_ text: String) -> [Word] {
        text.matches(of: #/[A-Za-z'-]+/#).map {
            Word(text: String($0.output), start: text.distance(from: text.startIndex, to: $0.range.lowerBound))
        }
    }

    func pattern(_ text: String) -> Int {
        let letters = text.filter { letter($0) }
        if letters.allSatisfy({ $0 >= "a" && $0 <= "z" }) {
            return 0
        }
        if text.first! >= "A" && text.first! <= "Z" &&
            letters.dropFirst().allSatisfy({ $0 >= "a" && $0 <= "z" }) {
            return 1
        }
        if letters.count >= 2 && letters.allSatisfy({ $0 >= "A" && $0 <= "Z" }) {
            return 2
        }
        return -1
    }

    func longInfo(_ morae: [Mora]) -> LongInfo {
        var info = LongInfo(
            paired: Array(repeating: false, count: morae.count),
            elements: Array(repeating: false, count: morae.count),
            vowels: Array(repeating: "", count: morae.count)
        )
        for index in morae.indices {
            if morae[index].id == "L" {
                info.elements[index] = true
                info.vowels[index] = String(morae[index - 1].id.last!)
            }
        }
        var index = 0
        while index + 1 < morae.count {
            let first = morae[index].id
            let second = morae[index + 1].id
            let v = String(first.last!)
            if regular(first) && vowel(second) && (v == second || (v == "o" && second == "u") || (v == "e" && second == "i")) {
                info.paired[index + 1] = true
                if (v == "o" && (second == "o" || second == "u")) || (v == "u" && second == "u") {
                    info.elements[index + 1] = true
                    info.vowels[index + 1] = v
                }
                index += 2
            } else {
                index += 1
            }
        }
        return info
    }

    func parts(_ word: Word, _ system: String, _ longMode: String) throws -> [String] {
        let info = longInfo(word.morae)
        var result: [String] = []
        for index in word.morae.indices {
            let mora = word.morae[index]
            let id = mora.id
            let nextId = index + 1 < word.morae.count ? word.morae[index + 1].id : ""
            let next = regular(nextId) ? spelling(system, nextId) : ""
            let part: String
            if info.elements[index] {
                let v = info.vowels[index]
                switch longMode {
                case "KEEP": part = id == "L" ? "-" : spelling(system, id)
                case "DROP": part = ""
                case "PASSPORT": part = v == "o" && !begins(next, "aiueo") ? "h" : ""
                case "HYPHEN": part = "-"
                default: part = v
                }
            } else if regular(id) {
                part = spelling(system, id)
            } else if id == "N" {
                if system == "WAPURO" {
                    part = nextId == "N" || begins(next, "aiueoyn") ? "nn" : "n"
                } else if system == "TRADITIONAL" && begins(next, "bmp") {
                    part = "m"
                } else {
                    part = begins(next, "aiueoy") ? "n'" : "n"
                }
            } else if !next.isEmpty && !begins(next, "aiueon") {
                part = (system == "HEPBURN" || system == "TRADITIONAL") && next.hasPrefix("ch") ? "t" : String(next.first!)
            } else if system == "WAPURO" {
                part = "xtu"
            } else {
                throw column(mora.column, "small tsu cannot be written")
            }
            result.append(part)
        }
        return result
    }

    func write(_ word: Word, _ system: String, _ longMode: String, _ caseMode: String) throws -> String {
        var result = try parts(word, system, longMode).joined()
        let outputPattern = caseMode == "KEEP" ? word.pattern : (caseMode == "LOWER" ? 0 : (caseMode == "TITLE" ? 1 : 2))
        if outputPattern == 1 {
            result = String(result.first!).uppercased() + slice(result, 1)
        }
        if outputPattern == 2 {
            result = result.uppercased()
        }
        return result
    }

    func canonical(_ word: Word, _ system: String) throws -> String {
        try write(word, system, "KEEP", "KEEP")
    }

    func ids(_ word: Word) -> [String] {
        word.morae.map { $0.id }
    }

    func loose(_ word: Word) -> [String] {
        let info = longInfo(word.morae)
        return word.morae.indices.filter { !info.elements[$0] }.map { word.morae[$0].id }
    }

    func elements(_ word: Word) -> [Element] {
        var result: [Element] = []
        for mora in word.morae {
            let id = mora.id
            if id == "L" {
                continue
            }
            if id == "N" {
                result.append(Element(base: "N", voice: 0, size: 0))
            } else if id == "Q" {
                result.append(Element(base: "tu", voice: 0, size: 1))
            } else {
                let meta = metadata[id]!
                if meta.contracted {
                    result.append(Element(base: devoice(String(meta.row.first!) + "i"), voice: voice(meta.row), size: 0))
                    result.append(Element(base: "y" + String(id.last!), voice: 0, size: 1))
                } else {
                    result.append(Element(base: devoice(id), voice: voice(meta.row), size: 0))
                }
            }
        }
        return result
    }

    func sorted(_ words: [Word]) -> [Word] {
        let bases = (orderSetting == "GOJUON" ? gojuon : iroha).split(separator: " ").map(String.init)
        let ranks = Dictionary(uniqueKeysWithValues: bases.enumerated().map { ($0.element, $0.offset) })
        func key(_ word: Word) -> [[Int]] {
            let collation = elements(word)
            return [
                collation.map { ranks[$0.base]! },
                collation.map { $0.voice },
                collation.map { $0.size },
                word.morae.map { $0.id == "L" ? 1 : 0 }
            ]
        }
        return words.map { (word: $0, key: key($0)) }.sorted {
            $0.key.lexicographicallyPrecedes($1.key) { $0.lexicographicallyPrecedes($1) }
        }.map { $0.word }
    }

    func patternMorae(_ pattern: String, _ system: String) throws -> [String] {
        let characters = Array(pattern)
        guard !characters.isEmpty && characters.allSatisfy({ ($0 >= "a" && $0 <= "z") || "'-?*".contains($0) }) else {
            throw Problem.message("invalid pattern")
        }
        var result: [String] = []
        var start = 0
        do {
            for index in 0...characters.count {
                if index == characters.count || characters[index] == "?" || characters[index] == "*" {
                    if index > start {
                        let chunk = Word(text: String(characters[start..<index]), start: 0)
                        result.append(contentsOf: try parse(chunk, system).map { $0.id })
                    }
                    if index < characters.count {
                        result.append(String(characters[index]))
                    }
                    start = index + 1
                }
            }
        } catch {
            throw Problem.message("invalid pattern")
        }
        return result
    }

    func matches(_ pattern: [String], _ word: [String]) -> Bool {
        var dp = Array(repeating: false, count: word.count + 1)
        dp[0] = true
        for token in pattern {
            var next = Array(repeating: false, count: word.count + 1)
            next[0] = token == "*" && dp[0]
            if !word.isEmpty {
                for index in 1...word.count {
                    next[index] = token == "*" ? dp[index] || next[index - 1] :
                        dp[index - 1] && (token == "?" || token == word[index - 1])
                }
            }
            dp = next
        }
        return dp[word.count]
    }

    func detect(_ words: [Word]) -> String {
        var result: [String] = []
        for system in systems {
            var verdict = "canonical"
            do {
                let parsed = try words.map { original in
                    var word = original
                    word.morae = try parse(word, system)
                    return word
                }
                for word in parsed {
                    let expected = try canonical(word, system)
                    if word.text != expected {
                        verdict = "readable"
                    }
                }
            } catch {
                verdict = "error"
            }
            result.append(system + "=" + verdict)
        }
        return result.joined(separator: " ")
    }

    func execute(_ line: String) throws -> String {
        let command = String(line.split(separator: " ", maxSplits: 1)[0])
        guard counts[command] != nil || command == "SET" || command == "TABLE" else {
            throw Problem.message("unknown command " + command)
        }
        if command == "SET" || command == "TABLE" {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            if tokens.count < 3 {
                throw Problem.message("missing argument")
            }
            if tokens.count > 3 {
                throw Problem.message("too many arguments")
            }
            if command == "SET" {
                let allowed: [String]
                switch tokens[1] {
                case "LONG": allowed = ["KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"]
                case "CASE": allowed = ["KEEP", "LOWER", "UPPER", "TITLE"]
                case "ORDER": allowed = ["GOJUON", "IROHA"]
                default: throw Problem.message("unknown option " + tokens[1])
                }
                guard allowed.contains(tokens[2]) else {
                    throw Problem.message("unknown value " + tokens[2])
                }
                if tokens[1] == "LONG" {
                    longSetting = tokens[2]
                }
                if tokens[1] == "CASE" {
                    caseSetting = tokens[2]
                }
                if tokens[1] == "ORDER" {
                    orderSetting = tokens[2]
                }
                return tokens[1] + "=" + tokens[2]
            }
            guard systems.contains(tokens[1]) else {
                throw Problem.message("unknown system " + tokens[1])
            }
            guard rows.contains(tokens[2]) else {
                throw Problem.message("unknown row " + tokens[2])
            }
            return table.filter { $0.row == tokens[2] }.map { spelling(tokens[1], $0.id) }.joined(separator: " ")
        }
        let fixed = counts[command]!
        let tokens = line.split(separator: " ", maxSplits: fixed + 1, omittingEmptySubsequences: false).map(String.init)
        guard tokens.count >= fixed + 2 else {
            throw Problem.message("missing argument")
        }
        let arguments = Array(tokens[1..<(fixed + 1)])
        let text = tokens[fixed + 1]
        let systemCount = command == "NORMALIZE" || command == "DETECT" ? 0 :
            (["CONVERT", "DIFF", "SAME"].contains(command) ? 2 : 1)
        for index in 0..<systemCount {
            guard systems.contains(arguments[index]) else {
                throw Problem.message("unknown system " + arguments[index])
            }
        }
        let searchPattern: [String]
        if command == "FIND" {
            searchPattern = try patternMorae(arguments[1], arguments[0])
        } else {
            searchPattern = []
        }
        let slash = command == "SAME" || command == "HAIKU"
        for (index, c) in text.enumerated() {
            if !letter(c) && c != "'" && c != "-" && !" 0123456789.,!?;:()\"".contains(c) && !(slash && c == "/") {
                throw column(index + 1, "invalid character")
            }
        }
        let poem = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if command == "SAME" && (poem.count != 2 || scan(poem[0]).isEmpty || scan(poem[1]).isEmpty) {
            throw Problem.message("expected two texts")
        }
        if command == "HAIKU" {
            guard (poem.count == 3 || poem.count == 5) && poem.allSatisfy({ !scan($0).isEmpty }) else {
                throw Problem.message("expected 3 or 5 lines")
            }
        }
        var words = scan(text)
        guard !words.isEmpty else {
            throw Problem.message("no words")
        }
        for index in words.indices {
            let casePattern = pattern(words[index].text)
            if casePattern < 0 {
                throw column(words[index].start + 1, "mixed case")
            }
            words[index].pattern = casePattern
        }
        if command == "DETECT" {
            return detect(words)
        }
        let slashPosition = Array(text).firstIndex(of: "/") ?? -1
        for index in words.indices {
            let source = command == "NORMALIZE" ? "ANY" :
                (command == "SAME" && words[index].start > slashPosition ? arguments[1] : arguments[0])
            words[index].morae = try parse(words[index], source)
        }
        let system = command == "NORMALIZE" ? "HEPBURN" : arguments[0]
        switch command {
        case "CONVERT", "NORMALIZE", "REVERSE":
            let target = command == "CONVERT" ? arguments[1] : system
            var result = ""
            var cursor = 0
            for word in words {
                result += slice(text, cursor, word.start)
                var written = word
                if command == "REVERSE" {
                    var reversed: [Mora] = []
                    for index in word.morae.indices {
                        let mora = word.morae[index]
                        let id = mora.id == "L" ? String(word.morae[index - 1].id.last!) : mora.id
                        reversed.append(Mora(id: id, column: mora.column))
                    }
                    written.morae = Array(reversed.reversed())
                }
                result += try write(written, target, longSetting, caseSetting)
                cursor = word.start + word.text.count
            }
            return result + slice(text, cursor)
        case "VALID":
            for word in words {
                let expected = try canonical(word, system)
                if word.text != expected {
                    let actualCharacters = Array(word.text)
                    let expectedCharacters = Array(expected)
                    var index = 0
                    while index < min(actualCharacters.count, expectedCharacters.count) && actualCharacters[index] == expectedCharacters[index] {
                        index += 1
                    }
                    return "INVALID col \(word.start + index + 1): expected \(expected)"
                }
            }
            return "VALID"
        case "DIFF":
            var changes: [String] = []
            for word in words {
                let first = try write(word, system, longSetting, caseSetting)
                let second = try write(word, arguments[1], longSetting, caseSetting)
                if first != second {
                    changes.append(first + ">" + second)
                }
            }
            return "\(changes.count) of \(words.count)" + (changes.isEmpty ? "" : ": " + changes.joined(separator: " "))
        case "SAME":
            let left = words.filter { $0.start < slashPosition }
            let right = words.filter { $0.start > slashPosition }
            var exact = true
            for index in 0..<min(left.count, right.count) {
                if loose(left[index]) != loose(right[index]) {
                    return "DIFFERENT at word \(index + 1)"
                }
                if ids(left[index]) != ids(right[index]) {
                    exact = false
                }
            }
            if left.count != right.count {
                return "DIFFERENT at word \(min(left.count, right.count) + 1)"
            }
            return exact ? "EXACT" : "LOOSE"
        case "MORAE":
            var result: [String] = []
            var count = 0
            for word in words {
                let pieces = word.morae.map { mora in
                    regular(mora.id) ? spelling(system, mora.id) : (mora.id == "L" ? "-" : mora.id)
                }
                count += pieces.count
                result.append(pieces.joined(separator: "."))
            }
            return "\(count): " + result.joined(separator: " ")
        case "SYLLABLES":
            var result: [String] = []
            var count = 0
            for word in words {
                let pieces = try parts(word, system, "KEEP")
                let info = longInfo(word.morae)
                var syllables: [String] = []
                for index in pieces.indices {
                    if index == 0 || (regular(word.morae[index].id) && !info.paired[index]) {
                        syllables.append(pieces[index])
                    } else {
                        syllables[syllables.count - 1] += pieces[index]
                    }
                }
                count += syllables.count
                result.append(syllables.joined(separator: "."))
            }
            return "\(count): " + result.joined(separator: " ")
        case "ROW":
            var result: [String] = []
            for word in words {
                for mora in word.morae {
                    if let meta = metadata[mora.id] {
                        result.append(spelling(system, meta.id) + ": " + meta.row + " " + meta.dan)
                    } else {
                        result.append((mora.id == "L" ? "-" : mora.id) + ": special")
                    }
                }
            }
            return result.joined(separator: ", ")
        case "STATS":
            let morae = words.flatMap { $0.morae }
            let regular = morae.compactMap { metadata[$0.id] }
            let rowCounts = Dictionary(grouping: regular, by: { baseRow($0.row) }).mapValues { $0.count }
            var result = ["morae=\(morae.count)"]
            result += rows.prefix(10).compactMap { row in rowCounts[row].map { row + "=\($0)" } }
            result += [
                "voiced=\(regular.filter { voice($0.row) == 1 }.count)",
                "semivoiced=\(regular.filter { voice($0.row) == 2 }.count)",
                "contracted=\(regular.filter { $0.contracted }.count)",
                "N=\(morae.filter { $0.id == "N" }.count)",
                "Q=\(morae.filter { $0.id == "Q" }.count)",
                "L=\(morae.filter { $0.id == "L" }.count)"
            ]
            return result.joined(separator: " ")
        case "SORT", "INDEX":
            let ordered = sorted(words)
            if command == "SORT" {
                return ordered.map { $0.text }.joined(separator: " ")
            }
            var groups: [String] = []
            var group: [String] = []
            var previous = ""
            for word in ordered {
                let base = elements(word)[0].base
                let heading = orderSetting == "IROHA" || base == "N" ? base : metadata[base]!.row
                if heading != previous && !group.isEmpty {
                    groups.append(previous + ": " + group.joined(separator: " "))
                    group.removeAll()
                }
                previous = heading
                group.append(word.text)
            }
            groups.append(previous + ": " + group.joined(separator: " "))
            return groups.joined(separator: "; ")
        case "FIND":
            let found = words.filter { matches(searchPattern, ids($0)) }.map { $0.text }
            return "\(found.count) of \(words.count)" + (found.isEmpty ? "" : ": " + found.joined(separator: " "))
        case "HAIKU":
            var totals = Array(repeating: 0, count: poem.count)
            for word in words {
                let index = slice(text, 0, word.start).filter { $0 == "/" }.count
                totals[index] += word.morae.count
            }
            let expected = poem.count == 3 ? [5, 7, 5] : [5, 7, 5, 7, 7]
            return (totals == expected ? "OK " : "NG ") + (poem.count == 3 ? "haiku " : "tanka ") +
                totals.map(String.init).joined(separator: "-")
        case "KAIBUN":
            let bases = words.flatMap { elements($0).map { $0.base } }
            return (bases == Array(bases.reversed()) ? "YES " : "NO ") + bases.joined(separator: ".")
        case "SHIRITORI":
            var seen: Set<String> = []
            var previous = ""
            for (index, word) in words.enumerated() {
                let collation = elements(word)
                let head = collation.first!.base
                let tail = collation.last!.base
                let prefix = "NG \(index + 1): " + word.text
                if index > 0 && head != previous {
                    return prefix + " must start with " + spelling(system, previous)
                }
                let key = ids(word).joined(separator: ".")
                if !seen.insert(key).inserted {
                    return prefix + " is repeated"
                }
                if tail == "N" {
                    return prefix + " ends with N"
                }
                previous = tail
            }
            return "OK \(words.count)"
        default:
            preconditionFailure("Unreachable command")
        }
    }
}

let converter = Converter()
let count = Int(readLine()!)!
for _ in 0..<count {
    do {
        print(try converter.execute(readLine()!))
    } catch Problem.message(let message) {
        print("ERROR " + message)
    } catch {
        preconditionFailure("Unexpected error")
    }
}
