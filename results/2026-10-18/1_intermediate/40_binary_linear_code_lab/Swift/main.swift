typealias Word = UInt32
typealias Matrix = [Word]

struct CommandError: Error { let reason: String }
func fail(_ reason: String) throws -> Never { throw CommandError(reason: reason) }
func bit(_ word: Word, _ length: Int, _ column: Int) -> Bool { ((word >> (length - column - 1)) & 1) != 0 }
func bits(_ word: Word, _ length: Int) -> String {
    let text = String(word, radix: 2)
    return String(repeating: "0", count: length - text.count) + text
}
func degree(_ word: Word) -> Int { Word.bitWidth - 1 - word.leadingZeroBitCount }
func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func gcd(_ first: Int, _ second: Int) -> Int {
    var a = abs(first), b = abs(second)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}
func divide(_ original: Word, _ divisor: Word) -> (quotient: Word, remainder: Word) {
    var dividend = original, quotient: Word = 0
    let d = degree(divisor)
    while dividend != 0 && degree(dividend) >= d {
        let shift = degree(dividend) - d
        quotient ^= 1 << shift
        dividend ^= divisor << shift
    }
    return (quotient, dividend)
}
func basis(_ rows: Matrix, _ length: Int) -> Matrix {
    var pivots = Matrix(repeating: 0, count: length), kept: Matrix = []
    for original in rows {
        var row = original
        for column in 0..<length where bit(row, length, column) {
            if pivots[column] != 0 { row ^= pivots[column] }
            else { pivots[column] = row; kept.append(original); break }
        }
    }
    return kept
}
func rref(_ original: Matrix, _ length: Int) -> (rows: Matrix, columns: [Int]) {
    var rows = original, columns: [Int] = []
    for column in 0..<length {
        let pivot = columns.count
        guard let found = (pivot..<rows.count).first(where: { bit(rows[$0], length, column) }) else { continue }
        rows.swapAt(pivot, found)
        let pivotRow = rows[pivot]
        for row in rows.indices where row != pivot && bit(rows[row], length, column) { rows[row] ^= pivotRow }
        columns.append(column)
    }
    return (Array(rows.prefix(columns.count)), columns)
}
func nullspace(_ original: Matrix, _ length: Int) -> Matrix {
    let reduced = rref(original, length)
    var result: Matrix = []
    for column in 0..<length where !reduced.columns.contains(column) {
        var word: Word = 1 << (length - column - 1)
        for row in reduced.rows.indices where bit(reduced.rows[row], length, column) { word |= 1 << (length - reduced.columns[row] - 1) }
        result.append(word)
    }
    return result
}
func span(_ rows: Matrix) -> Matrix {
    var words: Matrix = [0]
    for row in rows {
        let count = words.count
        for index in 0..<count { let word = words[index] ^ row; words.append(word) }
    }
    return words
}
func distribution(_ words: Matrix, _ length: Int) -> [Int] {
    var counts = [Int](repeating: 0, count: length + 1)
    for word in words { counts[word.nonzeroBitCount] += 1 }
    return counts
}
func weightList(_ counts: [Int]) -> String {
    counts.indices.filter { counts[$0] != 0 }.map { "\($0):\(counts[$0])" }.joined(separator: " ")
}
func dimension(_ length: Int, _ rank: Int) throws {
    if rank < 1 || rank > 12 || length - rank < 1 || length - rank > 12 { try fail("bad dimension \(length) \(rank)") }
}
func removeBit(_ word: Word, _ length: Int, _ column: Int) -> Word {
    let low = length - column - 1
    return ((word >> (low + 1)) << low) | (word & ((1 << low) - 1))
}
func reedMuller(_ order: Int, _ variables: Int) -> Matrix {
    let length = 1 << variables
    if order == 0 { return [(1 << length) - 1] }
    let upper = reedMuller(min(order, variables - 1), variables - 1).map { ($0 << (length / 2)) | $0 }
    return upper + reedMuller(order - 1, variables - 1)
}

struct Decoded { let error: Word; let word: Word; let message: Int }
final class Code {
    let n: Int
    let k: Int
    let generator: Matrix
    let check: Matrix
    let polynomial: Word?
    private(set) var words: Matrix = []
    private(set) var messages: [Word: Int] = [:]
    private var leaderTable: Matrix?
    var encoder: String { polynomial == nil ? "matrix" : "polynomial" }

    init(_ length: Int, _ generator: Matrix, _ check: Matrix? = nil, _ polynomial: Word? = nil) throws {
        try dimension(length, generator.count)
        n = length; k = generator.count
        self.generator = generator; self.check = check ?? nullspace(generator, length)
        self.polynomial = polynomial
        for message in 0..<(1 << k) {
            let word = encode(message)
            messages[word] = message; words.append(word)
        }
        words.sort()
    }
    func encode(_ message: Int) -> Word {
        if let polynomial {
            let shifted = Word(message) << (n - k)
            return shifted | divide(shifted, polynomial).remainder
        }
        var word: Word = 0
        for row in 0..<k where bit(Word(message), k, row) { word ^= generator[row] }
        return word
    }
    func syndrome(_ word: Word) -> Int {
        check.reduce(0) { ($0 << 1) | (($1 & word).nonzeroBitCount % 2) }
    }
    func leaders() -> Matrix {
        if let leaderTable { return leaderTable }
        var result = Matrix(repeating: .max, count: 1 << (n - k))
        result[0] = 0
        var remaining = result.count - 1, count = 1
        while remaining > 0 {
            var word: Word = (1 << count) - 1
            while word < (1 << n) {
                let s = syndrome(word)
                if result[s] == .max {
                    result[s] = word; remaining -= 1
                    if remaining == 0 { break }
                }
                // Gosper's successor visits equal-weight vectors in lexicographic order.
                let lowest = word & (Word(0) &- word), next = word + lowest
                word = next | (((next ^ word) >> 2) / lowest)
            }
            count += 1
        }
        leaderTable = result
        return result
    }
    func decode(_ received: Word) -> Decoded {
        let error = leaders()[syndrome(received)], word = received ^ error
        return Decoded(error: error, word: word, message: messages[word]!)
    }
    func decodedText(_ value: Decoded) -> String {
        "codeword \(bits(value.word, n)) message \(bits(Word(value.message), k)) error \(bits(value.error, n)) weight \(value.error.nonzeroBitCount)"
    }
}

enum Verb: String, Hashable {
    case gen = "GEN", pcheck = "PCHECK", hamming = "HAMMING", simplex = "SIMPLEX", repetition = "REPETITION", parity = "PARITY"
    case rm = "RM", cyclic = "CYCLIC", dual = "DUAL", extend = "EXTEND", puncture = "PUNCTURE", shorten = "SHORTEN"
    case augment = "AUGMENT", expurgate = "EXPURGATE", permute = "PERMUTE", directsum = "DIRECTSUM", uuv = "UUV", product = "PRODUCT"
    case list = "LIST", delete = "DELETE", show = "SHOW", info = "INFO", systematic = "SYSTEMATIC", weights = "WEIGHTS"
    case covering = "COVERING", burst = "BURST", trellis = "TRELLIS", stdarray = "STDARRAY", equal = "EQUAL", encode = "ENCODE"
    case syndrome = "SYNDROME", decode = "DECODE", bounded = "BOUNDED", coset = "COSET", erasure = "ERASURE", interleave = "INTERLEAVE"
    case crc = "CRC", crccheck = "CRCCHECK", factor = "FACTOR", macwilliams = "MACWILLIAMS", bounds = "BOUNDS"
    var defining: Bool {
        switch self {
        case .gen, .pcheck, .hamming, .simplex, .repetition, .parity, .rm, .cyclic, .dual, .extend,
             .puncture, .shorten, .augment, .expurgate, .permute, .directsum, .uuv, .product: return true
        default: return false
        }
    }
}

enum Argument: Equatable { case name, code, number, bits, erasure }
struct Format { let types: [Argument]; let repeated: Argument?; let maximum: Int }
let formats: [Verb: Format] = {
    var result: [Verb: Format] = [:]
    func add(_ verbs: [Verb], _ types: [Argument], _ repeated: Argument? = nil, _ maximum: Int = 0) {
        for verb in verbs { result[verb] = Format(types: types, repeated: repeated, maximum: maximum) }
    }
    add([.gen, .pcheck], [.name], .bits, 24)
    add([.hamming, .simplex, .repetition, .parity], [.name, .number])
    add([.rm], [.name, .number, .number])
    add([.cyclic], [.name, .number, .bits])
    add([.dual, .extend, .augment, .expurgate], [.name, .code])
    add([.puncture, .shorten], [.name, .code, .number])
    add([.permute], [.name, .code], .number, 24)
    add([.directsum, .uuv, .product], [.name, .code, .code])
    add([.list], [])
    add([.delete, .show, .info, .systematic, .weights, .covering, .burst, .trellis, .stdarray], [.code])
    add([.equal], [.code, .code])
    add([.encode, .syndrome, .decode, .coset], [.code, .bits])
    add([.bounded], [.code, .number, .bits])
    add([.erasure], [.code, .erasure])
    add([.interleave], [.code, .number, .number], .bits, 8)
    add([.crc, .crccheck], [.bits, .bits])
    add([.factor], [.number])
    add([.macwilliams], [.number], .number, 25)
    add([.bounds], [.number, .number])
    return result
}()
func valid(_ text: String, _ kind: Argument) -> Bool {
    let bytes = Array(text.utf8)
    func letter(_ c: UInt8) -> Bool { (65...90).contains(c) || (97...122).contains(c) }
    func digit(_ c: UInt8) -> Bool { (48...57).contains(c) }
    guard let first = bytes.first else { return false }
    switch kind {
    case .name, .code: return bytes.count <= 8 && letter(first) && bytes.allSatisfy { letter($0) || digit($0) }
    case .number: return bytes.count <= 4 && (bytes.count == 1 || first != 48) && bytes.allSatisfy(digit)
    case .bits, .erasure: return bytes.count <= 30 && bytes.allSatisfy { $0 == 48 || $0 == 49 || (kind == .erasure && $0 == 63) }
    }
}
func parseWord(_ text: String) -> Word { Word(text, radix: 2)! }
struct Command { let verb: Verb; let args: [String] }
let choose: [[Int]] = {
    var result = [[Int]](repeating: [Int](repeating: 0, count: 25), count: 25)
    for n in 0...24 {
        result[n][0] = 1; result[n][n] = 1
        if n >= 2 { for k in 1..<n { result[n][k] = result[n - 1][k - 1] + result[n - 1][k] } }
    }
    return result
}()
func binomial(_ n: Int, _ k: Int) -> Int { k < 0 || k > n ? 0 : choose[n][k] }

func independent(_ verb: Verb, _ args: [String]) throws -> [String] {
    if verb == .crc || verb == .crccheck {
        let generator = args[0], text = args[1], d = generator.count - 1
        if generator.first == "0" || generator.count < 2 || generator.count > 17 { try fail("bad parameter") }
        if verb == .crc && text.count + d > 30 { try fail("bad length") }
        let word = parseWord(text), divisor = parseWord(generator)
        let remainder = divide(verb == .crc ? word << d : word, divisor).remainder, suffix = bits(remainder, d)
        if verb == .crc { return ["crc remainder \(suffix) frame \(text)\(suffix)"] }
        return ["crccheck \(remainder == 0 ? "ok" : "error") remainder \(suffix)"]
    }
    let n = Int(args[0])!
    if verb == .bounds {
        let d = Int(args[1])!
        if d < 1 || d > n || n > 24 { try fail("bad parameter") }
        let volume = choose[n].prefix((d - 1) / 2 + 1).reduce(0, +)
        var hamming = 0, griesmer = 0, sum = 0
        for k in 0...n where (1 << k) * volume <= (1 << n) { hamming = k }
        for k in 1...n {
            let denominator = 1 << (k - 1)
            sum += (d + denominator - 1) / denominator
            if sum <= n { griesmer = k }
        }
        return ["bounds n \(n) d \(d) singleton \(n - d + 1) hamming \(hamming) griesmer \(griesmer)"]
    }
    if n < 1 || n > 24 { try fail("bad parameter") }
    if verb == .factor {
        var remaining: Word = (1 << n) | 1, candidate: Word = 2
        var divisors = 1, factors: [String] = []
        while 2 * degree(candidate) <= degree(remaining) {
            var exponent = 0
            while divide(remaining, candidate).remainder == 0 {
                remaining = divide(remaining, candidate).quotient; exponent += 1
            }
            if exponent > 0 { factors.append("\(String(candidate, radix: 2))^\(exponent)"); divisors *= exponent + 1 }
            candidate += 1
        }
        if remaining > 1 { factors.append("\(String(remaining, radix: 2))^1"); divisors *= 2 }
        return ["factor \(n) \(factors.joined(separator: " ")) divisors \(divisors)"]
    }
    let counts = args.dropFirst().map { Int($0)! }
    if counts.count != n + 1 { try fail("bad length") }
    if counts[0] != 1 { try fail("bad parameter") }
    let size = counts.reduce(0, +)
    var feasible = (size & (size - 1)) == 0, transformed: [String] = []
    for j in 0...n {
        var numerator = 0
        for x in 0...n {
            var krawtchouk = 0
            for y in 0...j { krawtchouk += (y % 2 == 0 ? 1 : -1) * binomial(x, y) * binomial(n - x, j - y) }
            numerator += counts[x] * krawtchouk
        }
        let divisor = gcd(numerator, size), p = numerator / divisor, q = size / divisor
        transformed.append(q == 1 ? "\(p)" : "\(p)/\(q)")
        if q != 1 || p < 0 { feasible = false }
    }
    return ["macwilliams n \(n) size \(size)", "dual \(transformed.joined(separator: " "))", "feasible \(yes(feasible))"]
}

final class Laboratory {
    private var codes: [String: Code] = [:]

    func parse(_ line: String) throws -> Command {
        let words = line.split(separator: " ").map(String.init)
        guard let verb = Verb(rawValue: words[0]) else { try fail("unknown command \(words[0])") }
        let spec = formats[verb]!, args = Array(words.dropFirst()), extra = args.count - spec.types.count
        if spec.repeated == nil ? extra != 0 : extra < 1 || extra > spec.maximum { try fail("bad arguments") }
        for index in args.indices {
            let kind = index < spec.types.count ? spec.types[index] : spec.repeated!
            if !valid(args[index], kind) { try fail("bad arguments") }
        }
        for index in spec.types.indices where spec.types[index] == .code && codes[args[index]] == nil { try fail("no code \(args[index])") }
        return Command(verb: verb, args: args)
    }
    private func define(_ verb: Verb, _ args: [String]) throws -> [String] {
        let name = args[0], source = codes[args[1]], other = args.count > 2 ? codes[args[2]] : nil
        var n = 0, generator: Matrix = []
        var check: Matrix? = nil
        var polynomial: Word? = nil
        switch verb {
        case .gen, .pcheck:
            n = args[1].count
            let values = args.dropFirst()
            if values.contains(where: { $0.count != n }) { try fail("bad length") }
            let rows = basis(values.map(parseWord), n)
            if verb == .gen { generator = rows }
            else { check = rows; generator = nullspace(rows, n) }
        case .hamming, .simplex:
            let r = Int(args[1])!
            if r < 2 || r > 4 { try fail("bad parameter") }
            n = (1 << r) - 1
            var rows = Matrix(repeating: 0, count: r)
            for column in 1...n { for row in 0..<r { rows[row] = (rows[row] << 1) | (bit(Word(column), r, row) ? 1 : 0) } }
            if verb == .hamming { check = rows; generator = nullspace(rows, n) }
            else { generator = rows }
        case .repetition, .parity:
            n = Int(args[1])!
            if n < 2 || n > 24 { try fail("bad parameter") }
            generator = verb == .repetition ? [(1 << n) - 1] : (0..<(n - 1)).map { (1 << (n - $0 - 1)) | 1 }
        case .rm:
            let r = Int(args[1])!, m = Int(args[2])!
            if m < 1 || m > 4 || r > m { try fail("bad parameter") }
            n = 1 << m; generator = reedMuller(r, m)
        case .cyclic:
            n = Int(args[1])!
            let text = args[2], d = text.count - 1
            if n < 2 || n > 24 || text.first == "0" || text.count < 2 || text.count > n { try fail("bad parameter") }
            let g = parseWord(text)
            if divide((1 << n) | 1, g).remainder != 0 { try fail("not a divisor") }
            let k = n - d
            try dimension(n, k)
            polynomial = g
            generator = (0..<k).map { g << (k - $0 - 1) }
            var rows = Matrix(repeating: 0, count: d)
            for column in 0..<n {
                let remainder = divide(1 << (n - column - 1), g).remainder
                for row in 0..<d { rows[row] = (rows[row] << 1) | (bit(remainder, d, row) ? 1 : 0) }
            }
            check = rows
        case .dual:
            let a = source!
            n = a.n; generator = a.check; check = a.generator
        case .extend:
            let a = source!
            n = a.n + 1; generator = a.generator.map { ($0 << 1) | Word($0.nonzeroBitCount % 2) }
        case .puncture, .shorten:
            let a = source!, column = Int(args[2])! - 1
            if column < 0 || column >= a.n { try fail("bad position") }
            var rows = a.generator
            if verb == .shorten, let pivot = rows.firstIndex(where: { bit($0, a.n, column) }) {
                let z = rows.remove(at: pivot)
                rows = rows.map { bit($0, a.n, column) ? $0 ^ z : $0 }
            }
            n = a.n - 1
            generator = rows.map { removeBit($0, a.n, column) }
            if verb == .puncture { generator = basis(generator, n) }
        case .augment:
            let a = source!
            n = a.n; generator = basis(a.generator + [(1 << n) - 1], n)
        case .expurgate:
            let a = source!
            n = a.n; generator = a.generator
            if let pivot = generator.firstIndex(where: { $0.nonzeroBitCount % 2 != 0 }) {
                let z = generator.remove(at: pivot)
                generator = generator.map { $0.nonzeroBitCount % 2 != 0 ? $0 ^ z : $0 }
            }
        case .permute:
            let a = source!, order = args.dropFirst(2).map { Int($0)! }
            n = a.n
            if order.count != n || Set(order) != Set(1...n) { try fail("bad permutation") }
            generator = a.generator.map { row in order.reduce(Word(0)) { ($0 << 1) | (bit(row, n, $1 - 1) ? 1 : 0) } }
        case .directsum, .uuv, .product:
            let a = source!, b = other!
            if verb == .uuv && a.n != b.n { try fail("bad length") }
            n = verb == .product ? a.n * b.n : a.n + b.n
            try dimension(n, verb == .product ? a.k * b.k : a.k + b.k)
            if verb == .product {
                generator = a.generator.flatMap { x in b.generator.map { y in
                    (0..<a.n).reduce(Word(0)) { ($0 << b.n) | (bit(x, a.n, $1) ? y : 0) }
                } }
            } else { generator = a.generator.map { ($0 << b.n) | (verb == .uuv ? $0 : 0) } + b.generator }
        default: preconditionFailure("Not a defining command")
        }
        let code = try Code(n, generator, check, polynomial), replaced = codes[name] != nil
        codes[name] = code
        return ["\(replaced ? "redefined" : "defined") \(name) n \(n) k \(code.k)"]
    }
    private func systematic(_ name: String, _ code: Code) -> [String] {
        let n = code.n, k = code.k
        var rows = code.generator, order = Array(1...n)
        for pivot in 0..<k {
            var column = pivot
            while !rows[pivot...].contains(where: { bit($0, n, column) }) { column += 1 }
            if column != pivot {
                let mask: Word = (1 << (n - pivot - 1)) | (1 << (n - column - 1))
                for row in rows.indices where bit(rows[row], n, pivot) != bit(rows[row], n, column) { rows[row] ^= mask }
                order.swapAt(pivot, column)
            }
            let found = (pivot..<k).first { bit(rows[$0], n, pivot) }!
            rows.swapAt(pivot, found)
            let pivotRow = rows[pivot]
            for row in rows.indices where row != pivot && bit(rows[row], n, pivot) { rows[row] ^= pivotRow }
        }
        var output = ["systematic \(name) perm \(order.map(String.init).joined(separator: " "))"]
        output += rows.map { "G \(bits($0, n))" }
        for column in k..<n {
            var row = rows.reduce(Word(0)) { ($0 << 1) | (bit($1, n, column) ? 1 : 0) }
            row = (row << (n - k)) | (1 << (n - column - 1))
            output.append("H \(bits(row, n))")
        }
        return output
    }
    private func burst(_ name: String, _ code: Code) -> [String] {
        let detect = code.words.dropFirst().map { degree($0) - $0.trailingZeroBitCount }.min()!
        var seen: Set<Int> = [0]
        for length in 1...code.n {
            for start in 0...(code.n - length) {
                let limit: Word = length == 1 ? 1 : 1 << (length - 2)
                for middle in 0..<limit {
                    let pattern: Word = length == 1 ? 1 : (1 << (length - 1)) | (middle << 1) | 1
                    let syndrome = code.syndrome(pattern << (code.n - start - length))
                    if !seen.insert(syndrome).inserted { return ["burst \(name) detect \(detect) correct \(length - 1)"] }
                }
            }
        }
        preconditionFailure("A nonzero codeword must be an undetectable burst")
    }
    private func interleave(_ name: String, _ code: Code, _ args: [String]) throws -> [String] {
        let messages = Array(args.dropFirst(3)), start = Int(args[1])!, length = Int(args[2])!, depth = messages.count
        if messages.contains(where: { $0.count != code.k }) { try fail("bad length") }
        if start < 1 || length < 1 || start + length - 1 > depth * code.n { try fail("bad burst") }
        let sentWords = messages.map { code.encode(Int($0, radix: 2)!) }
        var receivedWords = Matrix(repeating: 0, count: depth), sent = "", received = ""
        for column in 0..<code.n { for row in 0..<depth {
            let position = column * depth + row + 1, original = bit(sentWords[row], code.n, column)
            let changed = original != (start <= position && position < start + length)
            sent += original ? "1" : "0"; received += changed ? "1" : "0"
            receivedWords[row] = (receivedWords[row] << 1) | (changed ? 1 : 0)
        } }
        var output = ["interleave \(name) depth \(depth) burst \(start) \(length)", "sent \(sent)", "recv \(received)"]
        var correct = 0
        for row in 0..<depth {
            let decoded = code.decode(receivedWords[row]), message = bits(Word(decoded.message), code.k), ok = message == messages[row]
            if ok { correct += 1 }
            output.append("row \(row + 1) errors \((receivedWords[row] ^ sentWords[row]).nonzeroBitCount) corrected \(decoded.error.nonzeroBitCount) message \(message) \(ok ? "ok" : "wrong")")
        }
        output.append("result ok \(correct) wrong \(depth - correct)")
        return output
    }
    func execute(_ command: Command) throws -> [String] {
        let verb = command.verb, args = command.args
        if verb.defining { return try define(verb, args) }
        if [Verb.crc, .crccheck, .factor, .macwilliams, .bounds].contains(verb) { return try independent(verb, args) }
        if verb == .list {
            return ["codes \(codes.count)"] + codes.keys.sorted().map { name in
                let code = codes[name]!
                return "\(name) n \(code.n) k \(code.k) encoder \(code.encoder)"
            }
        }
        let name = args[0]
        if verb == .delete { codes.removeValue(forKey: name); return ["deleted \(name)"] }
        let code = codes[name]!, n = code.n, k = code.k
        switch verb {
        case .show:
            var output = ["code \(name) n \(n) k \(k) encoder \(code.encoder)"]
            if let polynomial = code.polynomial {
                output.append("poly g \(bits(polynomial, n - k + 1)) h \(bits(divide((1 << n) | 1, polynomial).quotient, k + 1))")
            }
            return output + code.generator.map { "G \(bits($0, n))" } + code.check.map { "H \(bits($0, n))" }
        case .info:
            let distance = code.words.dropFirst().map(\.nonzeroBitCount).min()!, t = (distance - 1) / 2, divisor = gcd(n, k)
            let volume = choose[n].prefix(t + 1).reduce(0, +)
            let cyclic = code.generator.allSatisfy { code.messages[(($0 << 1) & ((1 << n) - 1)) | ($0 >> (n - 1))] != nil }
            return ["info \(name) n \(n) k \(k) rate \(k / divisor)/\(n / divisor) d \(distance) t \(t) perfect \(yes(volume == (1 << (n - k)))) mds \(yes(distance == n - k + 1)) cyclic \(cyclic ? String(code.words[1], radix: 2) : "no")"]
        case .systematic: return systematic(name, code)
        case .weights:
            let a = distribution(code.words, n), b = distribution(span(code.check), n)
            let orthogonal = code.generator.allSatisfy { x in code.generator.allSatisfy { (x & $0).nonzeroBitCount % 2 == 0 } }
            return ["weights \(name) \(weightList(a))", "dual \(name) \(weightList(b))",
                "duality \(name) self-orthogonal \(yes(orthogonal)) self-dual \(yes(orthogonal && n == 2 * k)) formally-self-dual \(yes(a == b))"]
        case .covering:
            let counts = distribution(code.leaders(), n), radius = counts.lastIndex(where: { $0 != 0 })!
            let items = (0...radius).map { "\($0):\(counts[$0])" }.joined(separator: " ")
            return ["covering \(name) radius \(radius) leaders \(items)"]
        case .burst: return burst(name, code)
        case .trellis:
            let profile = (0...n).map { cut in
                let right = n - cut, prefix = code.generator.map { $0 >> right }, suffix = code.generator.map { $0 & ((1 << right) - 1) }
                return basis(prefix, cut).count + basis(suffix, right).count - k
            }
            return ["trellis \(name) profile \(profile.map(String.init).joined(separator: " ")) max \(profile.max()!)"]
        case .stdarray:
            if n - k > 6 || k > 4 { try fail("too large") }
            let leaders = code.leaders()
            let syndromes = leaders.indices.sorted {
                let a = leaders[$0], b = leaders[$1]
                return a.nonzeroBitCount != b.nonzeroBitCount ? a.nonzeroBitCount < b.nonzeroBitCount : a < b
            }
            return ["stdarray \(name) rows \(leaders.count) columns \(code.words.count)"] + syndromes.map { s in
                "\(bits(Word(s), n - k)): \(code.words.map { bits($0 ^ leaders[s], n) }.joined(separator: " "))"
            }
        case .equal:
            let other = codes[args[1]]!
            if n != other.n { return ["equal \(name) \(args[1]) no lengths \(n) \(other.n)"] }
            let common = k + other.k - basis(code.generator + other.generator, n).count
            return ["equal \(name) \(args[1]) \(yes(k == common && other.k == common)) intersection \(common)"]
        case .encode:
            if args[1].count != k { try fail("bad length") }
            return ["encode \(name) message \(args[1]) codeword \(bits(code.encode(Int(args[1], radix: 2)!), n))"]
        case .syndrome, .decode, .bounded, .coset:
            let text = args[verb == .bounded ? 2 : 1]
            if text.count != n { try fail("bad length") }
            let word = parseWord(text), syndrome = code.syndrome(word)
            if verb == .syndrome { return ["syndrome \(name) \(bits(Word(syndrome), n - k)) codeword \(yes(syndrome == 0))"] }
            let decoded = code.decode(word)
            if verb == .coset {
                let counts = distribution(code.words.map { $0 ^ word }, n)
                return ["coset \(name) syndrome \(bits(Word(syndrome), n - k)) leader \(bits(decoded.error, n)) weights \(weightList(counts))"]
            }
            if verb == .bounded && decoded.error.nonzeroBitCount > Int(args[1])! { return ["bounded \(name) fail weight \(decoded.error.nonzeroBitCount)"] }
            return ["\(verb == .bounded ? "bounded" : "decode") \(name) \(code.decodedText(decoded))"]
        case .erasure:
            let text = args[1]
            if text.count != n { try fail("bad length") }
            var mask: Word = 0, known: Word = 0, erased = 0
            for character in text {
                mask = (mask << 1) | (character != "?" ? 1 : 0)
                known = (known << 1) | (character == "1" ? 1 : 0)
                if character == "?" { erased += 1 }
            }
            let candidates = code.words.filter { ($0 & mask) == known }
            var output = "erasure \(name) erased \(erased) candidates \(candidates.count)"
            if candidates.count == 1 { output += " codeword \(bits(candidates[0], n)) message \(bits(Word(code.messages[candidates[0]]!), k))" }
            return [output]
        case .interleave: return try interleave(name, code, args)
        default: preconditionFailure("Unhandled command")
        }
    }
}

let commandCount = Int(readLine()!)!, laboratory = Laboratory()
for _ in 0..<commandCount {
    do {
        let command = try laboratory.parse(readLine()!)
        for row in try laboratory.execute(command) { print(row) }
    } catch let error as CommandError { print("error: \(error.reason)") }
}
