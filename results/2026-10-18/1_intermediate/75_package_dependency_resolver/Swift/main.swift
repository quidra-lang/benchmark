import Foundation

struct Problem: Error {
    let text: String
}

func fail(_ s: String) throws -> Never {
    throw Problem(text: "error: "+s)
}

func number(_ s: String) -> Int? {
    let b = Array(s.utf8)
    return (1...4).contains(b.count) && b.allSatisfy {
        (48...57).contains($0)
    }
    && (b.count == 1 || b[0] != 48) ? Int(s) : nil
}

struct Version: Comparable {
    let core: [Int]
    var pre = [String]()
    var text: String {
        core.map(String.init).joined(separator: ".")+(pre.isEmpty ? "" : "-"+pre.joined(separator: "."))
    }
    static func < (a: Version,b: Version) -> Bool {
        for i in 0..<3 {
            if a.core[i] != b.core[i] {
                return a.core[i] < b.core[i]
            }
        }
        if a.pre.isEmpty || b.pre.isEmpty {
            return !a.pre.isEmpty && b.pre.isEmpty
        }
        for i in 0..<min(a.pre.count,b.pre.count) {
            let x = a.pre[i],y = b.pre[i]
            if x == y {
                continue
            }
            let nx = x.utf8.allSatisfy {
                (48...57).contains($0)
            },ny = y.utf8.allSatisfy {
                (48...57).contains($0)
            }
            if nx && ny {
                return Int(x)! < Int(y)!
            }
            if nx != ny {
                return nx
            }
            return x < y
        }
        return a.pre.count < b.pre.count
    }
}

func version(_ s: String) -> Version? {
    let p = s.components(separatedBy: "-")
    if p.count < 1 || p.count > 2 {
        return nil
    }
    let parts = p[0].components(separatedBy: ".")
    if parts.count != 3 {
        return nil
    }
    let core = parts.compactMap {
        number($0)
    }
    if core.count != 3 {
        return nil
    }
    let pre = p.count == 2 ? p[1].components(separatedBy: ".") : []
    for id in pre {
        if id.isEmpty || !id.utf8.allSatisfy( {
            (97...122).contains($0) || (48...57).contains($0)
        }) || (id.utf8.allSatisfy {
            (48...57).contains($0)
        }
        && number(id) == nil) {
            return nil
        }
    }
    return Version(core: core,pre: pre)
}

func checkedVersion(_ s: String) throws -> Version {
    guard let v = version(s) else {
        try fail("invalid version '\(s)'")
    }
    return v
}

struct Comparison {
    let op: String
    let version: Version
    func accepts(_ v: Version) -> Bool {
        switch op {
        case "=":
            return v == version
        case ">":
            return v > version
        case ">=":
            return v >= version
        case "<":
            return v < version
        default:
            return v <= version
        }
    }
}

struct Alternative {
    let comparisons: [Comparison]
    let prereleaseCores: [[Int]]
}

struct Constraint {
    let alternatives: [Alternative]
    func accepts(_ v: Version) -> Bool {
        alternatives.contains {
            (v.pre.isEmpty || $0.prereleaseCores.contains(v.core)) && $0.comparisons.allSatisfy {
                $0.accepts(v)
            }
        }
    }
    func normal() -> String {
        alternatives.map {
            a in let s = a.comparisons.map {
                $0.op+$0.version.text
            }.joined(separator: " ")
            return s.isEmpty ? "*" : s
        }.joined(separator: " || ")
    }
}

func constraint(_ text: String) throws -> Constraint {
    func invalid() throws -> Never {
        try fail("invalid constraint '\(text)'")
    }
    var alternatives = [Alternative]()
    for alternative in text.components(separatedBy: " || ") {
        var comparisons = [Comparison]()
        var prereleaseCores = [[Int]]()
        for term in alternative.components(separatedBy: " ") {
            let op = [">=","<=",">","<","=","^","~"].first {
                term.hasPrefix($0)
            } ?? ""
            let pattern = String(term.dropFirst(op.count))
            let k: Int
            let lower: Version
            if pattern.contains("-") {
                guard let v = version(pattern),!v.pre.isEmpty else {
                    try invalid()
                }
                lower = v
                k = 3
                prereleaseCores.append(v.core)
            } else {
                let parts = pattern.components(separatedBy: ".")
                if parts.count < 1 || parts.count > 3 {
                    try invalid()
                }
                var core = [Int]()
                var wildcard = false
                for part in parts {
                    if part == "x" || part == "*" {
                        wildcard = true
                    } else {
                        guard let n = number(part),!wildcard else {
                            try invalid()
                        }
                        core.append(n)
                    }
                }
                k = core.count
                while core.count < 3 {
                    core.append(0)
                }
                lower = Version(core: core)
            }
            func upper(_ i: Int) -> Version {
                var core = lower.core
                core[i-1] += 1
                if i < 3 {
                    for j in i..<3 {
                        core[j] = 0
                    }
                }
                return Version(core: core)
            }
            func add(_ op: String,_ v: Version) {
                comparisons.append(Comparison(op: op,version: v))
            }
            if k == 0 {
                if op == ">" || op == "<" {
                    add("<",Version(core: [0,0,0],pre: ["0"]))
                }
            } else {
                switch op {
                case "","=":
                    if k == 3 {
                        add("=",lower)
                    } else {
                        add(">=",lower)
                        add("<",upper(k))
                    }
                case ">":
                    add(k == 3 ? ">" : ">=",k == 3 ? lower : upper(k))
                case "<=":
                    add(k == 3 ? "<=" : "<",k == 3 ? lower : upper(k))
                case ">=","<":
                    add(op,lower)
                case "~":
                    add(">=",lower)
                    add("<",upper(k >= 2 ? 2 : 1))
                case "^":
                    add(">=",lower)
                    add("<",upper(lower.core[0] != 0 || k == 1 ? 1 : lower.core[1] != 0 || k == 2 ? 2 : 3))
                default:
                    break
                }
            }
        }
        alternatives.append(Alternative(comparisons: comparisons,prereleaseCores: prereleaseCores))
    }
    return Constraint(alternatives: alternatives)
}

struct Rule {
    let name: String
    let text: String
    let constraint: Constraint
}

final class Release {
    let version: Version
    let deps: [Rule]
    let conflicts: [Rule]
    var yanked = false
    init(_ version: Version,_ deps: [Rule],_ conflicts: [Rule]) {
        self.version = version
        self.deps = deps
        self.conflicts = conflicts
    }
}

struct Requirement {
    let rule: Rule
    var origin: (String,Release)?
}

struct Snapshot {
    let requests: [Rule]
    let installed: [String:Release]
}

final class Manager {
    var registry = [String:[Release]]()
    var requests = [Rule]()
    var installed = [String:Release]()
    var held = Set<String>()
    var advisories = [String:Rule]()
    var history = [Snapshot]()
    func releases(_ n: String) -> [Release] {
        (registry[n] ?? []).sorted {
            $0.version > $1.version
        }
    }
    func registered(_ n: String,_ v: String) throws -> Release {
        guard let r = registry[n]?.first(where: {
            $0.version.text == v
        }) else {
            try fail("\(n)@\(v) is not registered")
        }
        return r
    }
    func checkInstalled(_ n: String) throws -> Release {
        guard let r = installed[n] else {
            try fail("\(n) is not installed")
        }
        return r
    }
    func applicable(_ n: String,_ v: Version) -> [String] {
        advisories.keys.filter {
            advisories[$0]!.name == n && advisories[$0]!.constraint.accepts(v)
        }.sorted()
    }
    func display(_ n: String,_ r: Release) -> String {
        var flags = [String]()
        if r.yanked {
            flags.append("yanked")
        }
        if installed[n]?.version == r.version {
            flags.append("installed")
        }
        return "\(n)@\(r.version.text)"+(flags.isEmpty ? "" : " ("+flags.joined(separator: ", ")+")")
    }
    func resolve(_ newRequests: [Rule],_ preferred: Set<String>,_ audit: Bool) -> ([String:Release]?,[String]) {
        var selected = [String:Release]()
        var origins = [String:Requirement]()
        var failureDepth = -1
        var failure = [String]()
        func chain(_ r: Requirement) -> [String] {
            if let (n,v) = r.origin {
                return chain(origins[n]!)+["\(n)@\(v.version.text) requires \(r.rule.name) \(r.rule.text)"]
            }
            return ["requested \(r.rule.name) \(r.rule.text)"]
        }
        // Materialize a failure before backtracking changes its selection and origins.
        func record(_ r: Requirement,_ reason: String,_ other: String? = nil) {
            if selected.count > failureDepth {
                failureDepth = selected.count
                failure = ["UNSATISFIABLE"]+chain(r).map {
                    "  "+$0
                }+["  "+reason]
                if let n = other {
                    failure += chain(origins[n]!).map {
                        "    "+$0
                    }
                }
            }
        }
        func usable(_ n: String,_ r: Release) -> Bool {
            (!r.yanked || installed[n]?.version == r.version) && (!audit || applicable(n,r.version).isEmpty)
        }
        func search(_ queue: [Requirement]) -> Bool {
            if queue.isEmpty {
                return true
            }
            let r = queue[0]
            let n = r.rule.name
            let rest = Array(queue.dropFirst())
            if let old = selected[n] {
                if r.rule.constraint.accepts(old.version) {
                    return search(rest)
                }
                record(r,"\(n)@\(old.version.text) was selected by:",n)
                return false
            }
            var candidates = [Release]()
            if held.contains(n) {
                let fixed = installed[n]!
                if !r.rule.constraint.accepts(fixed.version) || !usable(n,fixed) {
                    record(r,"\(n)@\(fixed.version.text) is held")
                    return false
                }
                candidates = [fixed]
            } else {
                candidates = releases(n).filter {
                    r.rule.constraint.accepts($0.version) && usable(n,$0)
                }
                if preferred.contains(n),let i = candidates.firstIndex(where: {
                    $0.version == installed[n]?.version
                }) {
                    let first = candidates.remove(at: i)
                    candidates.insert(first,at: 0)
                }
                if candidates.isEmpty {
                    record(r,"no version of \(n) matches \(r.rule.text)")
                    return false
                }
            }
            for candidate in candidates {
                let conflict = selected.keys.sorted().first {
                    q in let w = selected[q]!
                    return candidate.conflicts.contains {
                        $0.name == q && $0.constraint.accepts(w.version)
                    }
                    || w.conflicts.contains {
                        $0.name == n && $0.constraint.accepts(candidate.version)
                    }
                }
                if let q = conflict {
                    record(r,"\(n)@\(candidate.version.text) conflicts with \(q)@\(selected[q]!.version.text), which was selected by:",q)
                    continue
                }
                selected[n] = candidate
                origins[n] = r
                if search(candidate.deps.map {
                    Requirement(rule: $0,origin: (n,candidate))
                }+rest) {
                    return true
                }
                selected.removeValue(forKey: n)
                origins.removeValue(forKey: n)
            }
            return false
        }
        return search(newRequests.map {
            Requirement(rule: $0)
        }) ? (selected,[]) : (nil,failure)
    }
    func plan(_ next: [String:Release]) -> [String] {
        var out = [String]()
        var counts = [0,0,0,0]
        var remaining = Set(next.keys)
        while !remaining.isEmpty {
            let n = remaining.sorted().first {
                next[$0]!.deps.allSatisfy {
                    !remaining.contains($0.name)
                }
            }!
            remaining.remove(n)
            let v = next[n]!.version
            if let old = installed[n]?.version {
                if v != old {
                    let up = v > old
                    out.append("\(up ? "upgrade" : "downgrade") \(n) \(old.text) -> \(v.text)")
                    counts[up ? 1 : 2] += 1
                }
            } else {
                out.append("install \(n)@\(v.text)")
                counts[0] += 1
            }
        }
        remaining = Set(installed.keys).subtracting(next.keys)
        while !remaining.isEmpty {
            let n = remaining.sorted().first {
                n in !remaining.contains {
                    q in installed[q]!.deps.contains {
                        $0.name == n
                    }
                }
            }!
            remaining.remove(n)
            out.append("remove \(n)@\(installed[n]!.version.text)")
            counts[3] += 1
        }
        out.append(out.isEmpty ? "no changes" : "\(counts[0]) installed, \(counts[1]) upgraded, \(counts[2]) downgraded, \(counts[3]) removed")
        return out
    }
    func update(_ newRequests: [Rule],_ next: [String:Release]) {
        history.append(Snapshot(requests: requests,installed: installed))
        requests = newRequests
        installed = next
        held.formIntersection(installed.keys)
    }
    func parent(_ n: String) -> String {
        installed.keys.sorted().first {
            installed[$0]!.deps.contains {
                $0.name == n
            }
        }!
    }
    func command(_ line: String) throws -> [String] {
        let clauses = line.components(separatedBy: "; ")
        let w = clauses[0].components(separatedBy: " ")
        let c = w[0]
        let a = Array(w.dropFirst())
        var out = [String]()
        func rest(_ i: Int) -> String {
            a.dropFirst(i).joined(separator: " ")
        }
        switch c {
        case "PKG":
            let v = try checkedVersion(a[1])
            if registry[a[0]]?.contains(where: {
                $0.version == v
            }) == true {
                try fail("\(a[0])@\(a[1]) is already registered")
            }
            var deps = [Rule]()
            var conflicts = [Rule]()
            for clause in clauses.dropFirst() {
                let words = clause.components(separatedBy: " ")
                let text = words.dropFirst(2).joined(separator: " ")
                let rule = Rule(name: words[1],text: text,constraint: try constraint(text))
                if words[0] == "DEP" {
                    deps.append(rule)
                } else {
                    conflicts.append(rule)
                }
            }
            registry[a[0],default: []].append(Release(v,deps,conflicts))
            return ["registered \(a[0])@\(a[1])"]
        case "YANK","INFO":
            let r = try registered(a[0],a[1])
            if c == "YANK" {
                if r.yanked {
                    try fail("\(a[0])@\(a[1]) is already yanked")
                }
                r.yanked = true
                return ["yanked \(a[0])@\(a[1])"]
            }
            out.append(display(a[0],r))
            out += r.deps.map {
                "  requires \($0.name) \($0.text)"
            }
            out += r.conflicts.map {
                "  conflicts with \($0.name) \($0.text)"
            }
            out += applicable(a[0],r.version).map {
                "  advisory "+$0
            }
            return out
        case "VERSIONS":
            let con: Constraint?
            if a.count > 1 {
                con = try constraint(rest(1))
            } else {
                con = nil
            }
            if registry[a[0]] == nil {
                try fail("unknown package \(a[0])")
            }
            out = releases(a[0]).filter {
                con == nil || con!.accepts($0.version)
            }.map {
                display(a[0],$0)
            }
            return out.isEmpty ? ["no matching versions"] : out
        case "DEPENDENTS":
            let v: Version?
            if a.count > 1 {
                v = try checkedVersion(a[1])
            } else {
                v = nil
            }
            for n in registry.keys.sorted() {
                for r in releases(n) {
                    for d in r.deps where d.name == a[0] && (v == nil || d.constraint.accepts(v!)) {
                        out.append("\(n)@\(r.version.text) requires \(d.name) \(d.text)")
                    }
                }
            }
            return out.isEmpty ? ["no dependents"] : out
        case "COMPARE":
            let x = try checkedVersion(a[0])
            let y = try checkedVersion(a[1])
            return ["\(a[0]) \(x < y ? "<" : x > y ? ">" : "=") \(a[1])"]
        case "MATCH":
            let v = try checkedVersion(a[0])
            let con = try constraint(rest(1))
            return [con.accepts(v) ? "yes" : "no"]
        case "RANGE":
            return [try constraint(rest(0)).normal()]
        case "INSTALL","SIMULATE":
            let text = a.count > 1 ? rest(1) : "*"
            let con = try constraint(text)
            if registry[a[0]] == nil {
                try fail("unknown package \(a[0])")
            }
            let rule = Rule(name: a[0],text: text,constraint: con)
            var nextRequests = requests
            if let i = nextRequests.firstIndex(where: {
                $0.name == a[0]
            }) {
                nextRequests[i] = rule
            } else {
                nextRequests.append(rule)
            }
            let (next,failure) = resolve(nextRequests,Set(installed.keys),false)
            guard let next = next else {
                return failure
            }
            out = plan(next)
            if c == "INSTALL" {
                update(nextRequests,next)
            }
            return out
        case "REMOVE":
            let n = a[0]
            if !requests.contains(where: {
                $0.name == n
            }) {
                if installed[n] != nil {
                    try fail("\(n) is required by \(parent(n))")
                }
                try fail("\(n) is not installed")
            }
            let nextRequests = requests.filter {
                $0.name != n
            }
            var keep = Set(nextRequests.map(\.name))
            while true {
                let next = keep.flatMap {
                    installed[$0]!.deps.map(\.name)
                }
                let before = keep.count
                keep.formUnion(next)
                if keep.count == before {
                    break
                }
            }
            if keep.contains(n) {
                out.append("\(n)@\(installed[n]!.version.text) is still required by \(parent(n))")
                update(nextRequests,installed)
            } else {
                let next = installed.filter {
                    keep.contains($0.key)
                }
                out = plan(next)
                update(nextRequests,next)
            }
            return out
        case "UPGRADE":
            if !a.isEmpty {
                _ = try checkInstalled(a[0])
            }
            let preferred = a.isEmpty ? Set<String>() : Set(installed.keys).subtracting([a[0]])
            let (next,failure) = resolve(requests,preferred,false)
            guard let next = next else {
                return failure
            }
            out = plan(next)
            update(requests,next)
            return out
        case "ROLLBACK":
            guard let snapshot = history.popLast() else {
                try fail("nothing to roll back")
            }
            out = plan(snapshot.installed)
            requests = snapshot.requests
            installed = snapshot.installed
            held.formIntersection(installed.keys)
            return out
        case "HOLD":
            let r = try checkInstalled(a[0])
            if held.contains(a[0]) {
                try fail("\(a[0]) is already held")
            }
            held.insert(a[0])
            return ["held \(a[0])@\(r.version.text)"]
        case "UNHOLD":
            if !held.contains(a[0]) {
                try fail("\(a[0]) is not held")
            }
            held.remove(a[0])
            return ["released \(a[0])"]
        case "WHY":
            let n = a[0]
            let r = try checkInstalled(n)
            let roots = Set(requests.map(\.name))
            if roots.contains(n) {
                return ["\(n)@\(r.version.text) is explicitly installed"]
            }
            var seen = roots
            var queue = roots.sorted()
            var head = 0
            var parents = [String:String]()
            while head < queue.count {
                let u = queue[head]
                head += 1
                for v in installed[u]!.deps.map(\.name).sorted() where seen.insert(v).inserted {
                    parents[v] = u
                    queue.append(v)
                }
            }
            var p = [n]
            while !roots.contains(p.last!) {
                p.append(parents[p.last!]!)
            }
            return [p.reversed().map {
                "\($0)@\(installed[$0]!.version.text)"
            }.joined(separator: " -> ")]
        case "TREE":
            if !a.isEmpty {
                _ = try checkInstalled(a[0])
            }
            let roots = a.isEmpty ? requests.map(\.name).sorted() : [a[0]]
            if roots.isEmpty {
                return ["(empty)"]
            }
            var seen = Set<String>()
            func visit(_ n: String,_ text: String?,_ prefix: String,_ indent: String) {
                let r = installed[n]!
                let body = prefix+"\(n)@\(r.version.text)"+(text.map {
                    " [\($0)]"
                } ?? "")
                if !seen.insert(n).inserted {
                    out.append(body+" (*)")
                    return
                }
                out.append(body)
                for (i,d) in r.deps.enumerated() {
                    let last = i == r.deps.count-1
                    visit(d.name,d.text,indent+(last ? "`-- " : "|-- "),indent+(last ? "    " : "|   "))
                }
            }
            for n in roots {
                visit(n,requests.first {
                    $0.name == n
                }?.text,"","")
            }
            return out
        case "OUTDATED":
            for n in installed.keys.sorted() {
                let r = installed[n]!
                let constraints = requests.filter {
                    $0.name == n
                }.map(\.constraint)+installed.values.flatMap(\.deps).filter {
                    $0.name == n
                }.map(\.constraint)
                let versions = releases(n)
                let wanted = versions.first {
                    candidate in (!candidate.yanked || candidate.version == r.version) && constraints.allSatisfy {
                        $0.accepts(candidate.version)
                    }
                }!
                let latest = versions.first {
                    !$0.yanked && $0.version.pre.isEmpty
                }
                if wanted.version != r.version || (latest != nil && latest!.version > r.version) {
                    out.append("\(n) \(r.version.text) \(wanted.version.text) \(latest?.version.text ?? "-")")
                }
            }
            return out.isEmpty ? ["all packages are up to date"] : out
        case "LOCK":
            out = installed.keys.sorted().map {
                "\($0)@\(installed[$0]!.version.text)"
            }
            return out.isEmpty ? ["(empty)"] : out
        case "STATUS":
            out = requests.map {
                "\($0.name) \($0.text) -> \(installed[$0.name]!.version.text)"
            }
            if out.isEmpty {
                out = ["no requests"]
            }
            out.append("\(installed.count) installed, \(held.count) held, \(history.count) snapshots")
            return out
        case "ADVISORY":
            if advisories[a[0]] != nil {
                try fail("advisory \(a[0]) already exists")
            }
            let text = rest(2)
            let con = try constraint(text)
            advisories[a[0]] = Rule(name: a[1],text: text,constraint: con)
            return ["advisory \(a[0]) recorded"]
        case "AUDIT":
            if !a.isEmpty {
                let (next,failure) = resolve(requests,Set(installed.keys),true)
                guard let next = next else {
                    return failure
                }
                out = plan(next)
                update(requests,next)
                return out
            }
            for n in installed.keys.sorted() {
                let r = installed[n]!
                let ids = applicable(n,r.version)
                if ids.isEmpty {
                    continue
                }
                let fix = releases(n).reversed().first {
                    $0.version > r.version && $0.version.pre.isEmpty && !$0.yanked && applicable(n,$0.version).isEmpty
                }
                out.append("\(n)@\(r.version.text): "+ids.joined(separator: ", ")+" "+(fix.map {
                    "(fix: \($0.version.text))"
                } ?? "(no fix)"))
            }
            return out.isEmpty ? ["no known vulnerabilities"] : out
        default:
            return out
        }
    }
}

let manager = Manager()
if let first = readLine(),let count = Int(first) {
    for _ in 0..<count {
        do {
            for line in try manager.command(readLine()!) {
                print(line)
            }
        } catch let problem as Problem {
            print(problem.text)
        } catch {
        }
    }
}
