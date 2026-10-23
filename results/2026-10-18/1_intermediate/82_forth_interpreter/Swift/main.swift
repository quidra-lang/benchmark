import Foundation

struct Fault: Error {
    let word: String
    let reason: String
    let code: Int?
}

func fail(_ word: String, _ reason: String, _ code: Int? = nil) throws -> Never {
    throw Fault(word: word, reason: reason, code: code)
}

final class Word {
    let name: String
    let original: String
    let kind: String
    let here: Int
    var value = 0
    var address = 0
    var token = 0
    var deferred: Word?
    var does: Word?
    var doesStart = 0
    var locals = 0
    var code = [Instruction]()

    init(_ name: String, _ original: String, _ kind: String, _ here: Int) {
        self.name = name
        self.original = original
        self.kind = kind
        self.here = here
    }
}

final class Instruction {
    let op: String
    let spelling: String
    let value: Int
    let word: Word?
    let text: String
    let slots: [Int]
    var target: Int

    init(_ op: String, _ spelling: String, _ value: Int = 0, word: Word? = nil, text: String = "", slots: [Int] = [], target: Int = 0) {
        self.op = op
        self.spelling = spelling
        self.value = value
        self.word = word
        self.text = text
        self.slots = slots
        self.target = target
    }
}

final class Control {
    let kind: String
    let index: Int
    let begin: Int
    var leaves = [Int]()
    var ends = [Int]()

    init(_ kind: String, _ index: Int, _ begin: Int = 0) {
        self.kind = kind
        self.index = index
        self.begin = begin
    }
}

final class Compiler {
    let word: Word
    let anonymous: Bool
    var locals = [String: Int]()
    var control = [Control]()

    init(_ word: Word, _ anonymous: Bool) {
        self.word = word
        self.anonymous = anonymous
    }
}

final class Forth {
    var data = [Int]()
    var returns = [Int]()
    var memory = [10]
    var users = [Word]()
    var builtins = [String: Word]()
    var tokens = [Word]()
    var output = [String]()
    var pending = ""
    var compiler: Compiler?
    var line = ""
    var at = 0
    var depth = 0
    let compileOnly: Set<String> = ["IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J", "BEGIN", "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT", "RECURSE", "DOES>", ";", ">R", "R>", "R@", "ABORT\"", "[']", "{:"]
    let interpretOnly: Set<String> = [":", ":NONAME", "FORGET"]
    let both: Set<String> = [".\"", "(", "\\", "TO", "IS"]

    init() {
        let names = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS"
        for part in names.split(separator: " ") {
            let n = String(part)
            builtins[n] = Word(n, n, "builtin", 8)
        }
    }

    func pop(_ n: Int, _ owner: String) throws -> [Int] {
        if data.count < n {
            try fail(owner, "stack underflow", -4)
        }
        let values = Array(data.suffix(n))
        data.removeLast(n)
        return values
    }

    func push(_ n: Int, _ owner: String) throws {
        data.append(n)
        if data.count > 1000 {
            try fail(owner, "stack overflow", -3)
        }
    }

    func pushAll(_ values: [Int], _ owner: String) throws {
        for n in values {
            try push(n, owner)
        }
    }

    func returnNeed(_ n: Int, _ owner: String) throws {
        if returns.count < n {
            try fail(owner, "return stack underflow", -6)
        }
    }

    func returnPush(_ n: Int, _ owner: String) throws {
        returns.append(n)
        if returns.count > 1000 {
            try fail(owner, "return stack overflow", -5)
        }
    }

    func address(_ n: Int, _ owner: String) throws -> Int {
        if n < 0 || n % 8 != 0 || n >= memory.count * 8 {
            try fail(owner, "invalid address", -9)
        }
        return n / 8
    }

    func readWord() -> String? {
        let bytes = Array(line.utf8)
        while at < bytes.count && bytes[at] == 32 {
            at += 1
        }
        let start = at
        while at < bytes.count && bytes[at] != 32 {
            at += 1
        }
        return at == start ? nil : String(decoding: bytes[start..<at], as: UTF8.self)
    }

    func readName(_ owner: String) throws -> String {
        guard let n = readWord() else {
            try fail(owner, "missing name", -16)
        }
        return n
    }

    func find(_ raw: String) -> Word? {
        let n = raw.uppercased()
        return users.last(where: {
            $0.name == n
        }) ?? builtins[n]
    }

    func number(_ raw: String, _ owner: String, _ base: Int) throws -> Int? {
        let original = Array(raw.utf8)
        if original.count == 3 && original[0] == 39 && original[2] == 39 {
            return Int(original[1])
        }
        var bytes = Array(raw.uppercased().utf8)
        var radix = base
        if let c = bytes.first, [UInt8(36), 35, 37].contains(c) {
            radix = c == 36 ? 16 : c == 35 ? 10 : 2
            bytes.removeFirst()
        } else if radix < 2 || radix > 36 {
            try fail(owner, "invalid base", -40)
        }
        var sign = 1
        if bytes.first == 45 {
            sign = -1
            bytes.removeFirst()
        }
        if bytes.isEmpty {
            return nil
        }
        var digits = [Int]()
        for c in bytes {
            let d: Int
            if c >= 48 && c <= 57 {
                d = Int(c - 48)
            } else if c >= 65 && c <= 90 {
                d = Int(c - 65) + 10
            } else {
                return nil
            }
            if d >= radix {
                return nil
            }
            digits.append(d)
        }
        return sign * digits.reduce(0) {
            $0 * radix + $1
        }
    }

    func checkName(_ raw: String) throws {
        let n = raw.uppercased()
        if compileOnly.contains(n) || interpretOnly.contains(n) || both.contains(n) {
            try fail(raw, "invalid name", -19)
        }
        if try number(raw, raw, 10) != nil {
            try fail(raw, "invalid name", -19)
        }
    }

    func token(_ word: Word) -> Int {
        if word.token == 0 {
            tokens.append(word)
            word.token = tokens.count
        }
        return word.token
    }

    func tokenWord(_ value: Int, _ owner: String) throws -> Word {
        if value < 1 || value > tokens.count {
            try fail(owner, "invalid argument", -24)
        }
        return tokens[value - 1]
    }

    func radix(_ owner: String) throws -> Int {
        let b = memory[0]
        if b < 2 || b > 36 {
            try fail(owner, "invalid base", -40)
        }
        return b
    }

    func formatted(_ value: Int, _ base: Int) -> String {
        String(value, radix: base, uppercase: true)
    }

    func flush() {
        while pending.last == " " {
            pending.removeLast()
        }
        output.append(pending)
        pending = ""
    }

    func quotient(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return a % b != 0 && (a < 0) != (b < 0) ? q - 1 : q
    }

    func executeDefinition(_ definition: Word, _ start: Int, _ owner: String) throws {
        if depth == 100 {
            try fail(owner, "nesting too deep", -7)
        }
        depth += 1
        let oldReturn = returns.count
        var locals = Array(repeating: 0, count: definition.locals)
        var pc = start
        execution: while pc < definition.code.count {
            let i = definition.code[pc]
            let s = i.spelling
            pc += 1
            switch i.op {
            case "literal":
                try push(i.value, s)
            case "call":
                try execute(i.word!, s)
            case "local":
                try push(locals[i.value], s)
            case "local-set":
                locals[i.value] = try pop(1, s)[0]
            case "locals":
                let a = try pop(i.slots.count, s)
                for j in i.slots.indices {
                    locals[i.slots[j]] = a[j]
                }
            case "value-set":
                memory[i.word!.address / 8] = try pop(1, s)[0]
            case "defer-set":
                i.word!.deferred = try tokenWord(pop(1, s)[0], s)
            case "jump":
                pc = i.target
            case "zero":
                if try pop(1, s)[0] == 0 {
                    pc = i.target
                }
            case "exit":
                break execution
            case "does":
                guard let latest = users.last, latest.kind == "create" else {
                    try fail(s, "no CREATE word", -31)
                }
                latest.does = definition
                latest.doesStart = pc
                break execution
            case "abort-string":
                if try pop(1, s)[0] != 0 {
                    try fail(s, i.text, -2)
                }
            case "write":
                pending += i.text
            case "do", "?do":
                let a = try pop(2, s)
                if i.op == "?do" && a[0] == a[1] {
                    pc = i.target
                } else {
                    try returnPush(a[0], s)
                    try returnPush(a[1], s)
                }
            case "loop", "+loop":
                let step: Int
                if i.op == "loop" {
                    step = 1
                } else {
                    step = try pop(1, s)[0]
                }
                try returnNeed(2, s)
                let index = returns.last!
                let limit = returns[returns.count - 2]
                let next = index + step
                if (index - limit < 0) != (next - limit < 0) {
                    returns.removeLast(2)
                } else {
                    returns[returns.count - 1] = next
                    pc = i.target
                }
            case "leave":
                try returnNeed(2, s)
                returns.removeLast(2)
                pc = i.target
            case "of":
                let a = try pop(2, s)
                if a[0] != a[1] {
                    try push(a[0], s)
                    pc = i.target
                }
            case "endcase":
                _ = try pop(1, s)
            case ">R":
                try returnPush(pop(1, s)[0], s)
            case "R>":
                try returnNeed(1, s)
                try push(returns.removeLast(), s)
            case "R@", "I":
                try returnNeed(1, s)
                try push(returns.last!, s)
            case "J":
                try returnNeed(3, s)
                try push(returns[returns.count - 3], s)
            case "UNLOOP":
                try returnNeed(2, s)
                returns.removeLast(2)
            default:
                break
            }
        }
        if returns.count > oldReturn {
            returns.removeLast(returns.count - oldReturn)
        }
        depth -= 1
    }

    func execute(_ initial: Word, _ originalSpelling: String) throws {
        var word = initial
        var spelling = originalSpelling
        while word.kind == "defer" {
            guard let target = word.deferred else {
                try fail(spelling, "deferred word not set", -21)
            }
            word = target
            spelling = target.name
        }
        switch word.kind {
        case "colon":
            try executeDefinition(word, 0, spelling)
        case "create", "variable":
            try push(word.address, spelling)
            if let d = word.does {
                try executeDefinition(d, word.doesStart, spelling)
            }
        case "constant":
            try push(word.value, spelling)
        case "value":
            try push(memory[word.address / 8], spelling)
        default:
            try builtin(word.name, spelling)
        }
    }

    func builtin(_ name: String, _ owner: String) throws {
        switch name {
        case "+", "-", "*", "/", "MOD", "/MOD", "MIN", "MAX", "=", "<>", "<", ">", "AND", "OR", "XOR":
            let a = try pop(2, owner)
            let x = a[0]
            let y = a[1]
            if ["/", "MOD", "/MOD"].contains(name) && y == 0 {
                try fail(owner, "division by zero", -10)
            }
            let v: Int
            switch name {
            case "+":
                v = x + y
            case "-":
                v = x - y
            case "*":
                v = x * y
            case "/", "/MOD":
                v = quotient(x, y)
            case "MOD":
                v = x - y * quotient(x, y)
            case "MIN":
                v = min(x, y)
            case "MAX":
                v = max(x, y)
            case "=":
                v = x == y ? -1 : 0
            case "<>":
                v = x != y ? -1 : 0
            case "<":
                v = x < y ? -1 : 0
            case ">":
                v = x > y ? -1 : 0
            case "AND":
                v = x & y
            case "OR":
                v = x | y
            default:
                v = x ^ y
            }
            if name == "/MOD" {
                try push(x - y * v, owner)
            }
            try push(v, owner)
        case "*/", "*/MOD":
            let a = try pop(3, owner)
            if a[2] == 0 {
                try fail(owner, "division by zero", -10)
            }
            let p = a[0] * a[1]
            let q = quotient(p, a[2])
            if name == "*/MOD" {
                try push(p - a[2] * q, owner)
            }
            try push(q, owner)
        case "NEGATE", "ABS", "1+", "1-", "2*", "2/", "0=", "0<>", "0<", "0>", "INVERT", "CELLS", "CELL+":
            let a = try pop(1, owner)[0]
            let v: Int
            switch name {
            case "NEGATE":
                v = -a
            case "ABS":
                v = abs(a)
            case "1+":
                v = a + 1
            case "1-":
                v = a - 1
            case "2*":
                v = 2 * a
            case "2/":
                v = quotient(a, 2)
            case "0=":
                v = a == 0 ? -1 : 0
            case "0<>":
                v = a != 0 ? -1 : 0
            case "0<":
                v = a < 0 ? -1 : 0
            case "0>":
                v = a > 0 ? -1 : 0
            case "INVERT":
                v = ~a
            case "CELLS":
                v = 8 * a
            default:
                v = a + 8
            }
            try push(v, owner)
        case "WITHIN":
            let a = try pop(3, owner)
            try push(a[1] <= a[0] && a[0] < a[2] ? -1 : 0, owner)
        case "TRUE":
            try push(-1, owner)
        case "FALSE", "BASE":
            try push(0, owner)
        case "BL":
            try push(32, owner)
        case "DEPTH":
            try push(data.count, owner)
        case "HERE":
            try push(memory.count * 8, owner)
        case "DUP", "?DUP", "DROP", "SWAP", "OVER", "ROT", "-ROT", "NIP", "TUCK", "2DUP", "2DROP", "2SWAP", "2OVER":
            let count: Int
            switch name {
            case "DUP", "?DUP", "DROP":
                count = 1
            case "ROT", "-ROT":
                count = 3
            case "2SWAP", "2OVER":
                count = 4
            default:
                count = 2
            }
            let a = try pop(count, owner)
            let values: [Int]
            switch name {
            case "DUP":
                values = [a[0], a[0]]
            case "?DUP":
                values = a[0] == 0 ? a : [a[0], a[0]]
            case "DROP", "2DROP":
                values = []
            case "SWAP":
                values = [a[1], a[0]]
            case "OVER":
                values = a + [a[0]]
            case "ROT":
                values = [a[1], a[2], a[0]]
            case "-ROT":
                values = [a[2], a[0], a[1]]
            case "NIP":
                values = [a[1]]
            case "TUCK":
                values = [a[1], a[0], a[1]]
            case "2DUP":
                values = a + a
            case "2SWAP":
                values = [a[2], a[3], a[0], a[1]]
            default:
                values = a + Array(a.prefix(2))
            }
            try pushAll(values, owner)
        case "PICK", "ROLL":
            let u = try pop(1, owner)[0]
            if u < 0 {
                try fail(owner, "invalid argument", -24)
            }
            if u >= data.count {
                try fail(owner, "stack underflow", -4)
            }
            let i = data.count - 1 - u
            let v = name == "ROLL" ? data.remove(at: i) : data[i]
            try push(v, owner)
        case ".":
            let n = try pop(1, owner)[0]
            pending += formatted(n, try radix(owner)) + " "
        case ".R":
            let a = try pop(2, owner)
            let s = formatted(a[0], try radix(owner))
            pending += String(repeating: " ", count: max(0, a[1] - s.count)) + s
        case ".S":
            let b = try radix(owner)
            pending += "<\(formatted(data.count, b))> " + data.map {
                formatted($0, b) + " "
            }.joined()
        case "?":
            let i = try address(pop(1, owner)[0], owner)
            pending += formatted(memory[i], try radix(owner)) + " "
        case "CR":
            flush()
        case "EMIT":
            let c = try pop(1, owner)[0]
            if c < 32 || c > 126 {
                try fail(owner, "invalid argument", -24)
            }
            pending.append(Character(UnicodeScalar(c)!))
        case "SPACE":
            pending += " "
        case "SPACES":
            let n = try pop(1, owner)[0]
            if n > 0 {
                pending += String(repeating: " ", count: n)
            }
        case "!", "+!":
            let a = try pop(2, owner)
            let i = try address(a[1], owner)
            memory[i] = name == "!" ? a[0] : memory[i] + a[0]
        case "@":
            let i = try address(pop(1, owner)[0], owner)
            try push(memory[i], owner)
        case ",":
            memory.append(try pop(1, owner)[0])
        case "ALLOT":
            let n = try pop(1, owner)[0]
            if n < 0 || n % 8 != 0 {
                try fail(owner, "invalid argument", -24)
            }
            memory += Array(repeating: 0, count: n / 8)
        case "HEX":
            memory[0] = 16
        case "DECIMAL":
            memory[0] = 10
        case "CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER":
            let raw = try readName(owner)
            try checkName(raw)
            let value: Int
            if name == "CONSTANT" || name == "VALUE" {
                value = try pop(1, owner)[0]
            } else {
                value = 0
            }
            let word = Word(raw.uppercased(), raw, name.lowercased(), memory.count * 8)
            word.address = memory.count * 8
            word.value = value
            users.append(word)
            if name == "VARIABLE" || name == "VALUE" {
                memory.append(value)
            }
        case "'":
            let raw = try readName(owner)
            guard let word = find(raw) else {
                try fail(raw, "undefined word", -13)
            }
            try push(token(word), owner)
        case "EXECUTE":
            let word = try tokenWord(pop(1, owner)[0], owner)
            try execute(word, word.name)
        case "CATCH":
            let word = try tokenWord(pop(1, owner)[0], owner)
            let saved = data
            let size = returns.count
            let level = depth
            var code = 0
            do {
                try execute(word, word.name)
            } catch let e as Fault {
                guard let n = e.code else {
                    throw e
                }
                data = saved
                if returns.count > size {
                    returns.removeLast(returns.count - size)
                }
                depth = level
                code = n
            }
            try push(code, owner)
        case "THROW":
            let n = try pop(1, owner)[0]
            if n != 0 {
                try fail(owner, "exception \(n)", n)
            }
        case "ABORT":
            try fail(owner, "aborted", -1)
        case "WORDS":
            for w in users.reversed() {
                pending += w.name + " "
            }
        default:
            break
        }
    }

    func string(_ owner: String) throws -> String {
        let bytes = Array(line.utf8)
        if at == bytes.count {
            try fail(owner, "unterminated string")
        }
        let start = at + 1
        guard let end = bytes[start...].firstIndex(of: 34) else {
            try fail(owner, "unterminated string")
        }
        at = end + 1
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    func target(_ raw: String, _ kind: String) throws -> Word {
        guard let w = find(raw) else {
            try fail(raw, "undefined word", -13)
        }
        if w.kind != kind {
            try fail(raw, kind == "value" ? "not a value" : "not deferred")
        }
        return w
    }

    func process(_ raw: String) throws {
        let name = raw.uppercased()
        let c = compiler
        if name == "\\" {
            at = line.utf8.count
            return
        }
        if name == "(" {
            let bytes = Array(line.utf8)
            guard let end = bytes[at...].firstIndex(of: 41) else {
                try fail(raw, "unterminated comment")
            }
            at = end + 1
            return
        }
        if c == nil && compileOnly.contains(name) {
            try fail(raw, "compile only")
        }
        if c != nil && interpretOnly.contains(name) {
            try fail(raw, "interpret only")
        }
        if name == ".\"" || name == "ABORT\"" {
            let text = try string(raw)
            if let c = c {
                c.word.code.append(Instruction(name == ".\"" ? "write" : "abort-string", raw, text: text))
            } else {
                pending += text
            }
            return
        }
        if name == "TO" || name == "IS" {
            let n = try readName(raw)
            if name == "TO", let c = c, let slot = c.locals[n.uppercased()] {
                c.word.code.append(Instruction("local-set", raw, slot))
                return
            }
            let w = try target(n, name == "TO" ? "value" : "defer")
            if let c = c {
                c.word.code.append(Instruction(name == "TO" ? "value-set" : "defer-set", raw, word: w))
            } else if name == "TO" {
                memory[w.address / 8] = try pop(1, raw)[0]
            } else {
                w.deferred = try tokenWord(pop(1, raw)[0], raw)
            }
            return
        }
        if name == ":" || name == ":NONAME" {
            let n: String
            if name == ":" {
                n = try readName(raw)
                try checkName(n)
            } else {
                n = raw
            }
            compiler = Compiler(Word(name == ":" ? n.uppercased() : ":NONAME", n, "colon", memory.count * 8), name == ":NONAME")
            return
        }
        if name == "FORGET" {
            let n = try readName(raw)
            guard let i = users.lastIndex(where: {
                $0.name == n.uppercased()
            }) else {
                try fail(n, "undefined word", -13)
            }
            let here = users[i].here / 8
            users.removeSubrange(i...)
            if memory.count > here {
                memory.removeLast(memory.count - here)
            }
            return
        }
        if let c = c {
            try compile(raw, name, c)
            return
        }
        if let w = find(raw) {
            try execute(w, raw)
        } else {
            guard let n = try number(raw, raw, memory[0]) else {
                try fail(raw, "undefined word", -13)
            }
            try push(n, raw)
        }
    }

    func compile(_ raw: String, _ name: String, _ c: Compiler) throws {
        let word = c.word

        func mismatch() throws -> Never {
            try fail(raw, "control structure mismatch")
        }

        func top(_ kinds: [String]) throws -> Control {
            guard let t = c.control.last, kinds.contains(t.kind) else {
                try mismatch()
            }
            return t
        }
        @discardableResult func append(_ op: String, _ value: Int = 0, target: Int = 0) -> Int {
            word.code.append(Instruction(op, raw, value, target: target))
            return word.code.count - 1
        }
        switch name {
        case ";":
            if let t = c.control.last {
                let k = t.kind == "ELSE" ? "IF" : t.kind == "WHILE" ? "BEGIN" : t.kind
                try fail(raw, "unclosed \(k)")
            }
            compiler = nil
            if c.anonymous {
                try push(token(word), raw)
            } else {
                users.append(word)
            }
        case "IF":
            c.control.append(Control("IF", append("zero")))
        case "ELSE":
            let t = try top(["IF"])
            c.control.removeLast()
            let i = append("jump")
            word.code[t.index].target = word.code.count
            c.control.append(Control("ELSE", i))
        case "THEN":
            let t = try top(["IF", "ELSE"])
            c.control.removeLast()
            word.code[t.index].target = word.code.count
        case "BEGIN":
            c.control.append(Control("BEGIN", word.code.count))
        case "UNTIL", "AGAIN":
            let t = try top(["BEGIN"])
            c.control.removeLast()
            append(name == "UNTIL" ? "zero" : "jump", target: t.index)
        case "WHILE":
            let t = try top(["BEGIN"])
            c.control.removeLast()
            c.control.append(Control("WHILE", append("zero"), t.index))
        case "REPEAT":
            let t = try top(["WHILE"])
            c.control.removeLast()
            append("jump", target: t.begin)
            word.code[t.index].target = word.code.count
        case "DO", "?DO":
            c.control.append(Control(name, append(name == "DO" ? "do" : "?do")))
        case "LOOP", "+LOOP":
            let t = try top(["DO", "?DO"])
            c.control.removeLast()
            append(name == "LOOP" ? "loop" : "+loop", target: t.index + 1)
            word.code[t.index].target = word.code.count
            for i in t.leaves {
                word.code[i].target = word.code.count
            }
        case "LEAVE":
            guard let t = c.control.last(where: {
                $0.kind == "DO" || $0.kind == "?DO"
            }) else {
                try mismatch()
            }
            t.leaves.append(append("leave"))
        case "CASE":
            c.control.append(Control("CASE", word.code.count))
        case "OF":
            _ = try top(["CASE"])
            c.control.append(Control("OF", append("of")))
        case "ENDOF":
            let t = try top(["OF"])
            c.control.removeLast()
            let i = append("jump")
            word.code[t.index].target = word.code.count
            try top(["CASE"]).ends.append(i)
        case "ENDCASE":
            let t = try top(["CASE"])
            c.control.removeLast()
            append("endcase")
            for i in t.ends {
                word.code[i].target = word.code.count
            }
        case "EXIT":
            append("exit")
        case "DOES>":
            if !c.control.isEmpty {
                try mismatch()
            }
            append("does")
        case "RECURSE":
            word.code.append(Instruction("call", raw, word: word))
        case "[']":
            let n = try readName(raw)
            guard let target = find(n) else {
                try fail(n, "undefined word", -13)
            }
            append("literal", token(target))
        case "{:":
            var names = [String]()
            var closed = false
            while let n = readWord() {
                if n.uppercased() == ":}" {
                    closed = true
                    break
                }
                names.append(n)
            }
            if !closed {
                try fail(raw, "unterminated locals")
            }
            var slots = [Int]()
            for n in names {
                if n == "--" {
                    break
                }
                try checkName(n)
                let slot = word.locals
                word.locals += 1
                slots.append(slot)
                c.locals[n.uppercased()] = slot
            }
            word.code.append(Instruction("locals", raw, slots: slots))
        case ">R", "R>", "R@", "I", "J", "UNLOOP":
            append(name)
        default:
            if let slot = c.locals[name] {
                append("local", slot)
            } else if let target = find(raw) {
                word.code.append(Instruction("call", raw, word: target))
            } else {
                guard let n = try number(raw, raw, memory[0]) else {
                    try fail(raw, "undefined word", -13)
                }
                append("literal", n)
            }
        }
    }

    func input(_ text: String) {
        line = text
        at = 0
        do {
            while let word = readWord() {
                try process(word)
            }
        } catch let e as Fault {
            if !pending.isEmpty {
                flush()
            }
            output.append("ERROR \(e.word): \(e.reason)")
            data = []
            returns = []
            compiler = nil
            depth = 0
        } catch {
        }
        if !pending.isEmpty {
            flush()
        }
    }
}
let forth = Forth()
while let line = readLine() {
    if line == "BYE" {
        if let c = forth.compiler {
            forth.output.append("ERROR \(c.word.original): unterminated definition")
        }
        break
    }
    forth.input(line)
}
for line in forth.output {
    print(line)
}
