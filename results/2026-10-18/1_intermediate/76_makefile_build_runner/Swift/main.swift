import Foundation

struct Expansion: Error {
    let reason: String
}

struct Abort: Error {
}

func words(_ s: String) -> [String] {
    s.split(separator: " ").map(String.init)
}

func trim(_ s: String) -> String {
    s.trimmingCharacters(in: CharacterSet(charactersIn: " "))
}

func part(_ s: String,_ start: Int,_ end: Int? = nil) -> String {
    String(decoding: s.utf8.dropFirst(start).prefix((end ?? s.utf8.count)-start),as: UTF8.self)
}

func position(_ s: String,_ c: UInt8) -> Int? {
    Array(s.utf8).firstIndex(of: c)
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
        seen.insert($0).inserted
    }
}

func stem(_ pattern: String,_ word: String) -> String? {
    guard let i = position(pattern,37) else {
        return pattern == word ? "" : nil
    }
    let a = part(pattern,0,i),b = part(pattern,i+1)
    return word.count >= a.count+b.count && word.hasPrefix(a) && word.hasSuffix(b) ? part(word,a.count,word.count-b.count) : nil
}

func substitute(_ s: String,_ m: String) -> String {
    guard let i = position(s,37) else {
        return s
    }
    return part(s,0,i)+m+part(s,i+1)
}

func replaceWord(_ w: String,_ p: String,_ r: String) -> String {
    guard let m = stem(p,w) else {
        return w
    }
    return p.contains("%") ? substitute(r,m) : r
}

func wildcard(_ pattern: String,_ word: String) -> Bool {
    let bytes = Array(word.utf8)
    var previous = Array(repeating: false,count: bytes.count+1)
    previous[0] = true
    for c in pattern.utf8 {
        var next = Array(repeating: false,count: bytes.count+1)
        if c == 42 {
            next[0] = previous[0]
        }
        for (i,b) in bytes.enumerated() {
            let j = i+1
            next[j] = c == 42 ? previous[j] || (b != 47 && next[j-1]) : previous[j-1] && (c == 63 ? b != 47 : c == b)
        }
        previous = next
    }
    return previous.last!
}

struct Variable {
    let simple: Bool
    var value: String
}

struct RecipeLine {
    let number: Int
    let text: String
}

final class Recipe {
    var lines = [RecipeLine]()
}

final class Rule {
    let target: String
    var deps: [String]
    var recipe: Recipe?
    var stem = ""
    init(_ target: String,_ deps: [String] = []) {
        self.target = target
        self.deps = deps
    }
}

final class Current {
    let targets: [String]
    let patterns: [Rule]
    var recipe: Recipe?
    init(_ targets: [String],_ patterns: [Rule]) {
        self.targets = targets
        self.patterns = patterns
    }
}

struct Condition {
    let outer: Bool
    var value: Bool
    var hadElse: Bool
    let line: Int
}

enum Scope {
    case foreach(String,String), call([String])
}

struct Determined {
    let deps: [String]
    let recipe: Recipe?
    let stem: String
    var source = false
    var absent = false
}

final class Simulator {
    var files = [String:Int]()
    var clock = 0
    var loaded = false
    var variables = [String:Variable]()
    var rules = [String:Rule]()
    var patterns = [Rule]()
    var phony = Set<String>()
    var goal: String?
    var output = [String]()
    var location = "make"
    var scopes = [Scope]()
    var expanding = Set<String>()
    var automatic = [String:String]()
    func error(_ reason: String) throws -> Never {
        throw Expansion(reason: reason)
    }
    func diagnostic(_ e: Expansion) {
        output.append("\(location): *** \(e.reason).  Stop.")
    }
    func tick(_ n: String) {
        clock += 1
        files[n] = clock
    }
    func clear() {
        loaded = false
        variables = [:]
        rules = [:]
        patterns = []
        phony = []
        goal = nil
        scopes = []
        expanding = []
        automatic = [:]
    }
    func closing(_ s: String,_ start: Int) throws -> Int {
        let b = Array(s.utf8)
        let opening = b[start]
        let close: UInt8 = opening == 40 ? 41 : 125
        var depth = 0
        for i in start..<b.count {
            if b[i] == opening {
                depth += 1
            }
            if b[i] == close {
                depth -= 1
                if depth == 0 {
                    return i
                }
            }
        }
        try error("unterminated variable reference")
    }
    func outside(_ s: String) throws -> [UInt8:Int] {
        let b = Array(s.utf8)
        var result = [UInt8:Int]()
        var i = 0
        while i < b.count {
            if b[i] == 36 {
                if i+1 < b.count && (b[i+1] == 40 || b[i+1] == 123) {
                    i = try closing(s,i+1)+1
                } else {
                    i = min(b.count,i+2)
                }
            } else {
                if [UInt8(61),58,59].contains(b[i]) && result[b[i]] == nil {
                    result[b[i]] = i
                }
                i += 1
            }
        }
        return result
    }
    func value(_ name: String) throws -> String {
        for scope in scopes.reversed() {
            switch scope {
            case let .foreach(n,v):
                if n == name {
                    return v
                }
            case let .call(values):
                if !name.isEmpty && name.utf8.allSatisfy({
                    (48...57).contains($0)
                }) {
                    let i = Int(name)!
                    return i < values.count ? values[i] : ""
                }
            }
        }
        if let v = automatic[name] {
            return v
        }
        guard let v = variables[name] else {
            return ""
        }
        if v.simple {
            return v.value
        }
        if !expanding.insert(name).inserted {
            try error("Recursive variable '\(name)' references itself (eventually)")
        }
        defer {
            expanding.remove(name)
        }
        return try expand(v.value)
    }
    func expand(_ s: String) throws -> String {
        let b = Array(s.utf8)
        var out = ""
        var i = 0
        while i < b.count {
            if b[i] != 36 {
                out.append(Character(UnicodeScalar(b[i])))
                i += 1
                continue
            }
            if i+1 == b.count {
                break
            }
            let c = b[i+1]
            if c == 36 {
                out += "$"
                i += 2
            } else if c == 40 || c == 123 {
                let end = try closing(s,i+1)
                out += try reference(part(s,i+2,end),c)
                i = end+1
            } else {
                out += try value(part(s,i+1,i+2))
                i += 2
            }
        }
        return out
    }
    func limits(_ n: String) -> (Int,Int)? {
        switch n {
        case "subst","patsubst","wordlist","foreach":
            return (3,3)
        case "findstring","filter","filter-out","word","addsuffix","addprefix":
            return (2,2)
        case "if":
            return (2,3)
        case "call":
            return (1,Int.max)
        case "strip","sort","words","firstword","lastword","dir","notdir","suffix","basename","wildcard","value","info","warning","error":
            return (1,1)
        default:
            return nil
        }
    }
    func reference(_ content: String,_ opening: UInt8) throws -> String {
        if let space = position(content,32),limits(part(content,0,space)) != nil {
            let raw = part(content,space+1).drop(while: {
                $0 == " "
            })
            return try function(part(content,0,space),String(raw),opening)
        }
        let n = try expand(content)
        if let colon = position(n,58),let after = position(part(n,colon+1),61) {
            let equal = colon+1+after
            var p = part(n,colon+1,equal),r = part(n,equal+1)
            if !p.contains("%") {
                p = "%"+p
                r = "%"+r
            }
            return try words(value(part(n,0,colon))).map {
                replaceWord($0,p,r)
            }.joined(separator: " ")
        }
        return try value(n)
    }
    func arguments(_ text: String,_ opening: UInt8,_ maximum: Int) -> [String] {
        let close: UInt8 = opening == 40 ? 41 : 125
        var depth = 0
        var start = 0
        var result = [String]()
        for (i,c) in text.utf8.enumerated() {
            if c == opening {
                depth += 1
            }
            if c == close {
                depth -= 1
            }
            if c == 44 && depth == 0 && result.count < maximum-1 {
                result.append(part(text,start,i))
                start = i+1
            }
        }
        result.append(part(text,start))
        return result
    }
    func function(_ name: String,_ text: String,_ opening: UInt8) throws -> String {
        let (minimum,maximum) = limits(name)!
        let raw = arguments(text,opening,maximum)
        if raw.count < minimum {
            try error("insufficient number of arguments (\(raw.count)) to function '\(name)'")
        }
        if name == "foreach" {
            let n = try trim(expand(raw[0]))
            let list = try words(expand(raw[1]))
            var result = [String]()
            for word in list {
                scopes.append(.foreach(n,word))
                do {
                    let s = try expand(raw[2])
                    scopes.removeLast()
                    result.append(s)
                } catch {
                    scopes.removeLast()
                    throw error
                }
            }
            return result.joined(separator: " ")
        }
        if name == "if" {
            let condition = try trim(expand(raw[0]))
            if !condition.isEmpty {
                return try expand(raw[1])
            }
            if raw.count == 3 {
                return try expand(raw[2])
            }
            return ""
        }
        var args = [String]()
        for r in raw {
            let s = try expand(r)
            args.append(name == "subst" || name == "call" ? s : trim(s))
        }
        func list(_ i: Int) -> [String] {
            words(args[i])
        }
        func joined(_ xs: [String]) -> String {
            xs.joined(separator: " ")
        }
        switch name {
        case "call":
            let n = trim(args[0])
            guard let v = variables[n] else {
                return ""
            }
            if v.simple {
                return v.value
            }
            scopes.append(.call([n]+Array(args.dropFirst())))
            defer {
                scopes.removeLast()
            }
            return try expand(v.value)
        case "value":
            return variables[args[0]]?.value ?? ""
        case "info":
            output.append(args[0])
            return ""
        case "warning":
            output.append("\(location): \(args[0])")
            return ""
        case "error":
            try error(args[0])
        case "subst":
            return args[0].isEmpty ? args[2] : args[2].replacingOccurrences(of: args[0],with: args[1])
        case "patsubst":
            return joined(list(2).map {
                replaceWord($0,args[0],args[1])
            })
        case "strip":
            return joined(list(0))
        case "findstring":
            return args[1].contains(args[0]) ? args[0] : ""
        case "filter","filter-out":
            return joined(list(1).filter {
                w in list(0).contains {
                    stem($0,w) != nil
                } == (name == "filter")
            })
        case "sort":
            return joined(Set(list(0)).sorted())
        case "word":
            let n = args[0]
            if n.isEmpty || !n.utf8.allSatisfy({
                (48...57).contains($0)
            }) {
                try error("non-numeric first argument to 'word' function: '\(n)'")
            }
            let i = Int(n)!
            if i == 0 {
                try error("first argument to 'word' function must be greater than 0")
            }
            let values = list(1)
            return i <= values.count ? values[i-1] : ""
        case "wordlist":
            let a = args[0],b = args[1]
            if a.isEmpty || !a.utf8.allSatisfy({
                (48...57).contains($0)
            }) {
                try error("non-numeric first argument to 'wordlist' function: '\(a)'")
            }
            if b.isEmpty || !b.utf8.allSatisfy({
                (48...57).contains($0)
            }) {
                try error("non-numeric second argument to 'wordlist' function: '\(b)'")
            }
            let start = Int(a)!,end = Int(b)!
            if start == 0 {
                try error("invalid first argument to 'wordlist' function: '\(a)'")
            }
            return joined(list(2).enumerated().filter {
                $0.offset+1 >= start && $0.offset+1 <= end
            }.map(\.element))
        case "words":
            return String(list(0).count)
        case "firstword":
            return list(0).first ?? ""
        case "lastword":
            return list(0).last ?? ""
        case "dir":
            return joined(list(0).map {
                w in if let i = Array(w.utf8).lastIndex(of: 47) {
                    return part(w,0,i+1)
                }
                return "./"
            })
        case "notdir":
            return joined(list(0).map {
                w in part(w,(Array(w.utf8).lastIndex(of: 47) ?? -1)+1)
            })
        case "suffix":
            return joined(list(0).compactMap {
                w in let b = Array(w.utf8)
                if let i = b.lastIndex(of: 46),i > (b.lastIndex(of: 47) ?? -1) {
                    return part(w,i)
                }
                return nil
            })
        case "basename":
            return joined(list(0).map {
                w in let b = Array(w.utf8)
                if let i = b.lastIndex(of: 46),i > (b.lastIndex(of: 47) ?? -1) {
                    return part(w,0,i)
                }
                return w
            })
        case "addsuffix":
            return joined(list(1).map {
                $0+args[0]
            })
        case "addprefix":
            return joined(list(1).map {
                args[0]+$0
            })
        case "wildcard":
            return joined(list(0).flatMap {
                glob($0)
            })
        default:
            return ""
        }
    }
    func glob(_ pattern: String) -> [String] {
        if pattern.contains("*") || pattern.contains("?") {
            return files.keys.filter {
                wildcard(pattern,$0)
            }.sorted()
        }
        return files[pattern] != nil ? [pattern] : []
    }
    func register(_ n: String,_ deps: [String]) {
        if rules[n] == nil {
            rules[n] = Rule(n)
        }
        for d in unique(deps) where !rules[n]!.deps.contains(d) {
            rules[n]!.deps.append(d)
        }
        if goal == nil && !n.hasPrefix(".") {
            goal = n
        }
    }
    func addRecipe(_ current: Current,_ line: RecipeLine) {
        if current.targets.isEmpty && current.patterns.isEmpty {
            return
        }
        if current.recipe == nil {
            let fresh = Recipe()
            for n in current.targets {
                if let old = rules[n]!.recipe {
                    output.append("Makefile:\(line.number): warning: overriding recipe for target '\(n)'")
                    output.append("Makefile:\(old.lines[0].number): warning: ignoring old recipe for target '\(n)'")
                }
                rules[n]!.recipe = fresh
            }
            for rule in current.patterns {
                rule.recipe = fresh
            }
            current.recipe = fresh
        }
        current.recipe!.lines.append(line)
    }
    func load(_ body: [String]) {
        clear()
        do {
            try loadBody(body)
        } catch let e as Expansion {
            diagnostic(e)
            clear()
        } catch {
        }
        location = "make"
        scopes = []
        expanding = []
        automatic = [:]
    }
    func loadBody(_ body: [String]) throws {
        var current: Current?
        var conditions = [Condition]()
        func active() -> Bool {
            conditions.last.map {
                $0.outer && $0.value
            } ?? true
        }
        var i = 0
        while i < body.count {
            let lineNumber = i+1
            location = "Makefile:\(lineNumber)"
            var text = body[i]
            i += 1
            if text.hasPrefix(">") {
                if !active() {
                    continue
                }
                guard let current = current else {
                    try error("recipe commences before first target")
                }
                addRecipe(current,RecipeLine(number: lineNumber,text: String(text.dropFirst()).drop(while: {
                    $0 == " "
                }).description))
                continue
            }
            while text.hasSuffix("\\") && i < body.count {
                text.removeLast()
                while text.hasSuffix(" ") {
                    text.removeLast()
                }
                text += " "+String(body[i].drop(while: {
                    $0 == " "
                }))
                i += 1
            }
            text = trim(text.components(separatedBy: "#")[0])
            let space = position(text,32)
            let first = space.map {
                part(text,0,$0)
            } ?? text
            let rest = space.map {
                trim(part(text,$0+1))
            } ?? ""
            if ["ifdef","ifndef","ifeq","ifneq"].contains(first) {
                let outer = active()
                var truth = false
                if outer {
                    if first == "ifdef" || first == "ifndef" {
                        let n = try trim(expand(rest))
                        truth = variables[n]?.value.isEmpty == false
                        if first == "ifndef" {
                            truth = !truth
                        }
                    } else {
                        if rest.count < 2 || !rest.hasPrefix("(") || !rest.hasSuffix(")") {
                            try error("invalid syntax in conditional")
                        }
                        let inner = part(rest,1,rest.count-1)
                        var depth = 0
                        var comma: Int?
                        for (j,c) in inner.utf8.enumerated() {
                            if c == 40 {
                                depth += 1
                            }
                            if c == 41 {
                                depth -= 1
                            }
                            if c == 44 && depth == 0 {
                                comma = j
                                break
                            }
                        }
                        guard let comma = comma else {
                            try error("invalid syntax in conditional")
                        }
                        let left = try trim(expand(part(inner,0,comma)))
                        let right = try trim(expand(part(inner,comma+1)))
                        truth = (left == right) == (first == "ifeq")
                    }
                }
                conditions.append(Condition(outer: outer,value: truth,hadElse: false,line: lineNumber))
                continue
            }
            if first == "else" {
                if conditions.isEmpty {
                    try error("extraneous 'else'")
                }
                let j = conditions.count-1
                if conditions[j].hadElse {
                    try error("only one 'else' per conditional")
                }
                conditions[j].value.toggle()
                conditions[j].hadElse = true
                continue
            }
            if first == "endif" {
                if conditions.isEmpty {
                    try error("extraneous 'endif'")
                }
                conditions.removeLast()
                continue
            }
            if text.isEmpty || !active() {
                continue
            }
            let positions = try outside(text)
            let equal = positions[61],colon = positions[58]
            if let equal = equal,colon == nil || colon! >= equal-1 {
                let bytes = Array(text.utf8)
                let special = equal > 0 && [UInt8(58),43,63].contains(bytes[equal-1])
                let op = special ? part(text,equal-1,equal+1) : "="
                let n = trim(part(text,0,equal-(special ? 1 : 0)))
                let rhs = trim(part(text,equal+1))
                if n.isEmpty {
                    try error("empty variable name")
                }
                let old = variables[n]
                switch op {
                case "=":
                    variables[n] = Variable(simple: false,value: rhs)
                case ":=":
                    variables[n] = Variable(simple: true,value: try expand(rhs))
                case "?=":
                    if old == nil {
                        variables[n] = Variable(simple: false,value: rhs)
                    }
                case "+=":
                    if let old = old {
                        let addition: String
                        if old.simple {
                            addition = try expand(rhs)
                        } else {
                            addition = rhs
                        }
                        variables[n] = Variable(simple: old.simple,value: old.value.isEmpty ? addition : old.value+" "+addition)
                    } else {
                        variables[n] = Variable(simple: false,value: rhs)
                    }
                default:
                    break
                }
                current = nil
            } else if let colon = colon {
                let targets = try unique(words(expand(part(text,0,colon))))
                var remainder = part(text,colon+1)
                let semi = try outside(remainder)[59]
                let inline = semi.map {
                    String(part(remainder,$0+1).drop(while: {
                        $0 == " "
                    }))
                }
                if let semi = semi {
                    remainder = part(remainder,0,semi)
                }
                let second = try outside(remainder)[58]
                var targetPattern: String?
                if let second = second {
                    targetPattern = try trim(expand(part(remainder,0,second)))
                    remainder = part(remainder,second+1)
                }
                let deps = try words(expand(remainder))
                var registered = [String]()
                var implicit = [Rule]()
                if targets == [".PHONY"] {
                    phony.formUnion(deps)
                } else if let pattern = targetPattern {
                    if !pattern.contains("%") {
                        try error("target pattern contains no '%'")
                    }
                    for t in targets {
                        if let m = stem(pattern,t),!m.isEmpty {
                            register(t,deps.map {
                                substitute($0,m)
                            })
                            rules[t]!.stem = m
                            registered.append(t)
                        } else {
                            output.append("Makefile:\(lineNumber): target '\(t)' doesn't match the target pattern")
                        }
                    }
                } else if targets.contains(where: {
                    $0.contains("%")
                }) {
                    if targets.contains(where: {
                        !$0.contains("%")
                    }) {
                        try error("mixed implicit and normal rules")
                    }
                    for t in targets {
                        let r = Rule(t,deps)
                        patterns.append(r)
                        implicit.append(r)
                    }
                } else {
                    for t in targets {
                        register(t,deps)
                        registered.append(t)
                    }
                }
                let rule = Current(registered,implicit)
                if let inline = inline {
                    addRecipe(rule,RecipeLine(number: lineNumber,text: inline))
                }
                current = rule
            } else if try !trim(expand(text)).isEmpty {
                try error("missing separator")
            }
        }
        if let top = conditions.last {
            location = "Makefile:\(top.line)"
            try error("missing 'endif'")
        }
        loaded = true
        output.append("Makefile loaded: lines=\(body.count) variables=\(variables.count) targets=\(rules.count) patterns=\(patterns.filter { $0.recipe != nil }.count) goal=\(goal ?? "(none)")")
    }
    func determine(_ t: String) -> Determined {
        let explicit = rules[t]
        if let r = explicit,r.recipe != nil {
            return Determined(deps: r.deps,recipe: r.recipe,stem: r.stem)
        }
        if !phony.contains(t) {
            let candidates = patterns.enumerated().compactMap {
                i,r -> (Rule,String,Int)? in guard r.recipe != nil,let m = stem(r.target,t),!m.isEmpty else {
                    return nil
                }
                return (r,m,i)
            }.sorted {
                $0.1.count == $1.1.count ? $0.2 < $1.2 : $0.1.count < $1.1.count
            }
            for (r,m,_) in candidates {
                let deps = r.deps.map {
                    substitute($0,m)
                }
                if deps.allSatisfy({
                    files[$0] != nil || rules[$0] != nil
                }) {
                    return Determined(deps: unique(deps+(explicit?.deps ?? [])),recipe: r.recipe,stem: m)
                }
            }
        }
        if explicit != nil || phony.contains(t) {
            return Determined(deps: explicit?.deps ?? [],recipe: nil,stem: explicit?.stem ?? "")
        }
        return Determined(deps: [],recipe: nil,stem: "",source: files[t] != nil,absent: files[t] == nil)
    }
    func make(_ args: [String]) {
        var options = Set<Character>()
        var goals = [String]()
        for arg in args {
            if arg.hasPrefix("-") {
                for c in arg.dropFirst() {
                    if !"nBkis".contains(c) {
                        output.append("make: invalid option -- '\(c)'")
                        return
                    }
                    options.insert(c)
                }
            } else {
                goals.append(arg)
            }
        }
        if goals.isEmpty {
            if !loaded {
                output.append("make: *** No targets specified and no makefile found.  Stop.")
                return
            }
            guard let goal = goal else {
                output.append("make: *** No targets.  Stop.")
                return
            }
            goals = [goal]
        }
        let original = files,oldClock = clock
        let build = Build(self,options)
        do {
            for g in goals {
                let before = build.runs
                let result = try build.target(g,nil)
                if result == .success && build.runs == before {
                    output.append(phony.contains(g) || build.used[g]!.recipe == nil ? "make: Nothing to be done for '\(g)'." : "make: '\(g)' is up to date.")
                } else if result == .dependencyFailure {
                    output.append("make: Target '\(g)' not remade because of errors.")
                }
            }
        } catch {
        }
        if options.contains("n") {
            files = original
            clock = oldClock
        }
        automatic = [:]
        scopes = []
        expanding = []
        location = "make"
    }
    func command(_ line: String) {
        output.append("$ "+line)
        let w = words(line)
        switch w[0] {
        case "MAKE":
            make(Array(w.dropFirst()))
        case "TOUCH":
            for n in w.dropFirst() {
                tick(n)
            }
        case "RM":
            for n in w.dropFirst() {
                if files.removeValue(forKey: n) == nil {
                    output.append("rm: cannot remove '\(n)': No such file or directory")
                }
            }
        case "FILES":
            output.append("clock \(clock)")
            output += files.keys.sorted().map {
                "\($0) \(files[$0]!)"
            }
        case "RULES":
            if loaded {
                for r in rules.keys.sorted().map({
                    rules[$0]!
                })+patterns.filter({
                    $0.recipe != nil
                }) {
                    output.append(r.target+":"+r.deps.map {
                        " "+$0
                    }.joined())
                    if let recipe = r.recipe {
                        output += recipe.lines.map {
                            ">"+$0.text
                        }
                    }
                }
                if !phony.isEmpty {
                    output.append(".PHONY:"+phony.sorted().map {
                        " "+$0
                    }.joined())
                }
            }
        case "VARS":
            if loaded {
                do {
                    for n in variables.keys.sorted() {
                        let s = try trim(value(n))
                        output.append(n+" "+(variables[n]!.simple ? ":=" : "=")+(s.isEmpty ? "" : " "+s))
                    }
                } catch let e as Expansion {
                    diagnostic(e)
                } catch {
                }
            }
        case "EXPAND":
            do {
                output.append("["+(try expand(part(line,7)))+"]")
            } catch let e as Expansion {
                diagnostic(e)
            } catch {
            }
        default:
            break
        }
    }
}

enum Status: Equatable {
    case success, failure, dependencyFailure
}

final class Build {
    let sim: Simulator
    let options: Set<Character>
    var results = [String:Status]()
    var used = [String:Determined]()
    var being = Set<String>()
    var runs = 0
    init(_ sim: Simulator,_ options: Set<Character>) {
        self.sim = sim
        self.options = options
    }
    func time(_ t: String) -> Int? {
        sim.phony.contains(t) ? nil : sim.files[t]
    }
    func execute(_ command: String) -> Int {
        let w = words(command)
        switch w[0] {
        case "echo":
            sim.output.append(w.dropFirst().joined(separator: " "))
        case "touch":
            for n in w.dropFirst() {
                sim.tick(n)
            }
        case "rm":
            let force = w.count > 1 && w[1] == "-f"
            var status = 0
            for p in w.dropFirst(force ? 2 : 1) {
                var names = sim.glob(p)
                if names.isEmpty {
                    names = [p]
                }
                for n in names {
                    if sim.files.removeValue(forKey: n) == nil && !force {
                        sim.output.append("rm: cannot remove '\(n)': No such file or directory")
                        status = 1
                    }
                }
            }
            return status
        case "false":
            return 1
        case "exit":
            return w.count > 1 ? Int(w[1])! : 0
        default:
            break
        }
        return 0
    }
    func run(_ t: String,_ d: Determined,_ deps: [String],_ fresh: [String]) throws -> Status {
        sim.automatic = ["@":t,"<":deps.first ?? "","^":deps.joined(separator: " "),"?":fresh.joined(separator: " "),"*":d.stem]
        var expanded = [(RecipeLine,String)]()
        do {
            for line in d.recipe!.lines {
                sim.location = "Makefile:\(line.number)"
                expanded.append((line,try sim.expand(line.text)))
            }
        } catch let e as Expansion {
            sim.diagnostic(e)
            sim.automatic = [:]
            sim.location = "make"
            throw Abort()
        }
        sim.automatic = [:]
        sim.location = "make"
        let dry = options.contains("n")
        for (line,text) in expanded {
            let prefix = String(text.prefix {
                $0 == " " || $0 == "@" || $0 == "-"
            })
            var command = String(text.dropFirst(prefix.count))
            while command.hasSuffix(" ") {
                command.removeLast()
            }
            if command.isEmpty {
                continue
            }
            if dry || (!prefix.contains("@") && !options.contains("s")) {
                sim.output.append(command)
            }
            if dry {
                continue
            }
            let status = execute(command)
            if status != 0 {
                if prefix.contains("-") || options.contains("i") {
                    sim.output.append("make: [Makefile:\(line.number): \(t)] Error \(status) (ignored)")
                } else {
                    sim.output.append("make: *** [Makefile:\(line.number): \(t)] Error \(status)")
                    if !options.contains("k") {
                        throw Abort()
                    }
                    return .failure
                }
            }
        }
        return .success
    }
    func target(_ t: String,_ parent: String?) throws -> Status {
        if let result = results[t] {
            return result
        }
        let d = sim.determine(t)
        used[t] = d
        if d.absent {
            results[t] = .failure
            let keep = options.contains("k")
            sim.output.append("make: *** No rule to make target '\(t)'"+(parent.map {
                ", needed by '\($0)'"
            } ?? "")+"."+(keep ? "" : "  Stop."))
            if !keep {
                throw Abort()
            }
            return .failure
        }
        if d.source {
            results[t] = .success
            return .success
        }
        being.insert(t)
        var deps = [String]()
        var failed = false
        for q in d.deps {
            if being.contains(q) {
                sim.output.append("make: Circular \(t) <- \(q) dependency dropped.")
            } else {
                deps.append(q)
                if try target(q,t) != .success {
                    failed = true
                }
            }
        }
        being.remove(t)
        let result: Status
        if failed {
            result = .dependencyFailure
        } else {
            let oldTime = time(t)
            let fresh = deps.filter {
                n in options.contains("B") || oldTime == nil || time(n) == nil || time(n)! > oldTime!
            }
            if d.recipe == nil || (!options.contains("B") && oldTime != nil && fresh.isEmpty) {
                result = .success
            } else {
                runs += 1
                result = try run(t,d,deps,fresh)
                if result == .success && !sim.phony.contains(t) {
                    sim.tick(t)
                }
            }
        }
        results[t] = result
        return result
    }
}

var input = [String]()
while let line = readLine() {
    input.append(line)
}

let sim = Simulator()

var index = 1
while input[index] != "END FILES" {
    let w = words(input[index])
    let t = Int(w[1])!
    sim.files[w[0]] = t
    sim.clock = max(sim.clock,t)
    index += 1
}
index += 1
while input[index] != "QUIT" {
    let line = input[index]
    index += 1
    if line == "MAKEFILE" {
        sim.output.append("$ MAKEFILE")
        var body = [String]()
        while input[index] != "END MAKEFILE" {
            body.append(input[index])
            index += 1
        }
        index += 1
        sim.load(body)
    } else {
        sim.command(line)
    }
}
for line in sim.output {
    print(line)
}
