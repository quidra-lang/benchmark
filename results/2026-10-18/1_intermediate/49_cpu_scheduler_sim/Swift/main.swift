import Foundation
let algorithms = ["FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ"]
let keys = ["cs", "q", "k", "s", "seed"], metrics = ["turnaround", "waiting", "response"], eventKinds = ["PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE"]
func allowed(_ a: String, _ k: String) -> Bool {
    k == "cs" || k == "q" && ["RR", "LOTTERY"].contains(a) || k == "k" && a == "PRIORITY" || k == "s" && a == "MLFQ" || k == "seed" && a == "LOTTERY"
}
func valid(_ k: String, _ v: Int) -> Bool {
    switch k {
        case "cs": return v <= 5
        case "q": return (1...20).contains(v)
        case "k": return (1...50).contains(v)
        case "s": return v <= 500
        case "seed": return (1...2147483646).contains(v)
        default: return false
    }
}
func decimal(_ n: Int, _ d: Int) -> String {
    let x = n * 100 / d
    return "\(x / 100)." + String(format: "%02d", x % 100)
}
struct CommandError: Error {
    let reason: String
}
func require(_ good: Bool, _ reason: String) throws {
    if !good {
        throw CommandError(reason: reason)
    }
}
func notation(_ p: [String: Int], _ a: String? = nil) -> String {
    keys.filter {
        a == nil || allowed(a!, $0)
    }
    .map {
        "\($0)=\(p[$0]!)"
    }
    .joined(separator: " ")
}
func row(_ cells: [String]) -> String {
    cells.enumerated().map {
        i, s in i == 0 ? s + String(repeating: " ", count: max(0, 8 - s.count)) : String(repeating: " ", count: max(0, 8 - s.count)) + s
    }
    .joined(separator: " ")
}
final class Process {
    let id: String, arrival: Int, bursts: [Int]
    var priority: Int, deadline: Int?
    init(_ id: String, _ arrival: Int, _ priority: Int, _ bursts: [Int]) {
        self.id = id
        self.arrival = arrival
        self.priority = priority
        self.bursts = bursts
    }
    var absolute: Int {
        arrival + (deadline ?? 0)
    }
    var describe: String {
        "\(id) arrival=\(arrival) priority=\(priority) deadline=\(deadline.map(String.init) ?? "none") bursts=\(bursts.enumerated().map { ($0.offset % 2 == 0 ? "C" : "I") + String($0.element) }.joined(separator: ","))"
    }
}
final class BurstRecord {
    let length: Int, ready: Int
    var start = -1, end = 0, slices = 0
    init(_ length: Int, _ ready: Int) {
        self.length = length
        self.ready = ready
    }
}
final class Job {
    let process: Process
    var state = "FUTURE", burst = 0, left: Int, effective: Int, wait = 0, level = 0, usage = 0, enqueued = 0, start = -1, finish = 0
    var records: [BurstRecord] = [], timeline = ""
    init(_ p: Process) {
        process = p
        left = p.bursts[0]
        effective = p.priority
    }
    var id: String {
        process.id
    }
    var metrics: [Int] {
        [finish - process.arrival, finish - process.arrival - process.bursts.reduce(0, +), start - process.arrival]
    }
    var missed: Bool {
        process.deadline != nil && finish > process.absolute
    }
    func advance() {
        burst += 1
        left = process.bursts[burst]
    }
}
final class Simulation {
    let jobs: [Job], algo: String, p: [String: Int], requested: Int?
    var queues: [[Job]] = [[], [], []], cpu = "IDLE", current: Job?, previous: Job?, switchLeft = 0, runLength = 0, time = 0, random: Int, end = 0, switches = 0
    var events: [String] = [], labels: [String] = [], cpuStates: [String] = [], snapshot: [String] = [], queueLengths: [Int] = [], counts: [String: Int] = [:]
    init(_ processes: [Process], _ algo: String, _ p: [String: Int], _ snapshot: Int? = nil) {
        jobs = processes.sorted {
            $0.id < $1.id
        }
        .map(Job.init)
        self.algo = algo
        self.p = p
        requested = snapshot
        random = p["seed"]!
        run()
    }
    func record(_ kind: String, _ details: String = "") {
        events.append("\(time) \(kind)" + (details.isEmpty ? "" : " " + details))
        counts[kind, default: 0] += 1
    }
    func enqueue(_ j: Job) {
        j.state = "READY"
        j.enqueued = time
        queues[j.level].append(j)
    }
    func release() {
        cpu = "IDLE"
        current = nil
    }
    func start(_ j: Job) {
        cpu = "RUN"
        current = j
        runLength = 0
        j.state = "RUN"
        if j.start < 0 {
            j.start = time
        }
        if j.records.last!.start < 0 {
            j.records.last!.start = time
        }
    }
    func preempt(_ j: Job) -> Bool {
        switch algo {
            case "SRTF": return queues[0].contains {
                $0.left < j.left
            }
            case "PRIORITY": return queues[0].contains {
                $0.effective < j.effective
            }
            case "EDF": return queues[0].contains {
                $0.process.deadline != nil && (j.process.deadline == nil || $0.process.absolute < j.process.absolute)
            }
            case "MLFQ": return queues.prefix(j.level).contains {
                !$0.isEmpty
            }
            default: return false
        }
    }
    func choose() -> Job {
        let q = queues[0]
        var best = q[0]
        if algo == "LOTTERY" {
            random = random * 48271 % 2147483647
            let r = random % q.reduce(0) {
                $0 + 10 - $1.process.priority
            }
            var total = 0
            for j in q {
                total += 10 - j.process.priority
                if total > r {
                    return j
                }
            }
        }
        for j in q.dropFirst() {
            let better: Bool
            switch algo {
                case "SJF", "SRTF": better = j.left < best.left
                case "PRIORITY": better = j.effective < best.effective
                case "HRRN": better = (time - j.enqueued + j.left) * best.left > (time - best.enqueued + best.left) * j.left
                case "EDF": better = j.process.deadline != nil && (best.process.deadline == nil || j.process.absolute < best.process.absolute)
                default: better = false
            }
            if better {
                best = j
            }
        }
        return best
    }
    func capture() {
        snapshot = [cpu == "IDLE" ? "CPU IDLE" : "CPU \(cpu) \(current!.id)"]
        func text(_ q: [Job]) -> String {
            q.isEmpty ? "none" : q.map(\.id).joined(separator: " ")
        }
        if algo == "MLFQ" {
            for i in 0..<3 {
                snapshot.append("QUEUE\(i) \(text(queues[i]))")
            }
        } else {
            snapshot.append("QUEUE \(text(queues[0]))")
        }
        for j in jobs {
            var line = j.state == "FUTURE" ? "\(j.id) FUTURE at=\(j.process.arrival)" : j.state == "DONE" ? "\(j.id) DONE at=\(j.finish)" : "\(j.id) \(j.state) burst=\(j.burst + 1) left=\(j.left)"
            if j.state != "FUTURE" && j.state != "DONE" {
                if algo == "PRIORITY" {
                    line += " prio=\(j.effective)"
                }
                if algo == "MLFQ" {
                    line += " level=\(j.level) used=\(j.usage)"
                }
            }
            snapshot.append(line)
        }
    }
    func run() {
        while true {
            if algo == "PRIORITY" {
                for j in queues[0] {
                    j.wait += 1
                    if j.wait == p["k"]! {
                        j.wait = 0
                        if j.effective > 0 {
                            j.effective -= 1
                            record("AGE", "\(j.id) \(j.effective)")
                        }
                    }
                }
            }
            for j in jobs where j.state == "IO" && j.left == 0 {
                j.advance()
                j.records.append(BurstRecord(j.left, time))
                enqueue(j)
                record("IODONE", j.id)
            }
            for j in jobs where j.state == "FUTURE" && j.process.arrival == time {
                j.records.append(BurstRecord(j.left, time))
                enqueue(j)
                record("ARRIVE", j.id)
            }
            if cpu == "SWITCH" && switchLeft == 0 {
                start(current!)
                record("START", current!.id)
            } else if cpu == "RUN" {
                let j = current!
                if j.left == 0 && j.burst == j.process.bursts.count - 1 {
                    j.state = "DONE"
                    j.finish = time
                    record("DONE", j.id)
                    release()
                } else {
                    let demoted = algo == "MLFQ" && j.level < 2 && j.usage == (j.level == 0 ? 4 : 8)
                    if demoted {
                        j.level += 1
                        j.usage = 0
                        record("DEMOTE", "\(j.id) \(j.level)")
                    }
                    if j.left == 0 {
                        j.advance()
                        j.state = "IO"
                        record("IO", "\(j.id) \(j.left)")
                        release()
                    } else if demoted {
                        enqueue(j)
                        release()
                    } else if ["RR", "LOTTERY"].contains(algo) && runLength == p["q"]! {
                        enqueue(j)
                        record("EXPIRE", j.id)
                        release()
                    } else if preempt(j) {
                        enqueue(j)
                        record("PREEMPT", j.id)
                        release()
                    }
                }
            }
            if jobs.allSatisfy({
                $0.state == "DONE"
            }
            ) {
                break
            }
            if algo == "MLFQ" && p["s"]! > 0 && time > 0 && time % p["s"]! == 0 {
                queues = [queues.flatMap {
                    $0
                }, [], []]
                for j in jobs {
                    j.level = 0
                    j.usage = 0
                }
                record("BOOST")
            }
            if cpu == "IDLE" && queues.contains(where: {
                !$0.isEmpty
            }
            ) {
                let level = algo == "MLFQ" ? queues.firstIndex {
                    !$0.isEmpty
                }! : 0, j = algo == "MLFQ" ? queues[level][0] : choose()
                queues[level].removeAll {
                    $0 === j
                }
                j.effective = j.process.priority
                j.wait = 0
                j.records.last!.slices += 1
                let switched = j !== previous
                if switched {
                    switches += 1
                }
                if switched && p["cs"]! > 0 {
                    cpu = "SWITCH"
                    current = j
                    switchLeft = p["cs"]!
                    j.state = "SWITCH"
                    record("SWITCH", j.id)
                } else {
                    start(j)
                    record("DISPATCH", j.id)
                }
            }
            if time == requested {
                capture()
            }
            for j in jobs {
                j.timeline += ["READY": ".", "SWITCH": "s", "RUN": "#", "IO": "i"][j.state] ?? "-"
            }
            queueLengths.append(queues.reduce(0) {
                $0 + $1.count
            })
            cpuStates.append(cpu)
            if cpu == "RUN" {
                let j = current!
                j.left -= 1
                j.usage += 1
                runLength += 1
                previous = j
                labels.append(j.id)
                if j.left == 0 {
                    j.records.last!.end = time + 1
                }
            } else if cpu == "SWITCH" {
                switchLeft -= 1
                labels.append("CS")
            } else {
                labels.append("IDLE")
            }
            for j in jobs where j.state == "IO" {
                j.left -= 1
            }
            time += 1
        }
        end = time
        if requested != nil && snapshot.isEmpty {
            capture()
        }
    }
    var totals: [Int] {
        (0..<3).map {
            i in jobs.reduce(0) {
                $0 + $1.metrics[i]
            }
        }
    }
    var averages: [String] {
        totals.map {
            decimal($0, jobs.count)
        }
    }
    var util: String {
        decimal(cpuStates.filter {
            $0 == "RUN"
        }
        .count * 100, end)
    }
    var missed: Int {
        jobs.filter(\.missed).count
    }
    func ticks(_ a: Int, _ b: Int) -> (Int, Int, Int) {
        let s = cpuStates[a..<b]
        return (s.filter {
            $0 == "RUN"
        }
        .count, s.filter {
            $0 == "SWITCH"
        }
        .count, s.filter {
            $0 == "IDLE"
        }
        .count)
    }
}
final class Scheduler {
    var registry: [String: Process] = [:], output: [String] = []
    func process(_ id: String) throws -> Process {
        try require(registry[id] != nil, "unknown process \(id)")
        return registry[id]!
    }
    func algorithm(_ a: String) throws {
        try require(algorithms.contains(a), "unknown algorithm \(a)")
    }
    func prepare(_ words: ArraySlice<String>, _ algo: String? = nil, _ preset: String? = nil) throws -> [String: Int] {
        var p = ["cs": 0, "q": 4, "k": 5, "s": 0, "seed": 1], seen: Set<String> = []
        if let preset {
            seen.insert(preset)
        }
        for word in words {
            let kv = word.split(separator: "=").map(String.init), k = kv[0], v = Int(kv[1])!
            try require(keys.contains(k), "unknown key \(k)")
            try require(algo == nil || allowed(algo!, k), "key \(k) not allowed for \(algo ?? "")")
            try require(!seen.contains(k), "duplicate key \(k)")
            try require(valid(k, v), "invalid \(k)")
            seen.insert(k)
            p[k] = v
        }
        try require(!registry.isEmpty, "no processes")
        return p
    }
    func sim(_ a: String, _ p: [String: Int], _ t: Int? = nil) -> Simulation {
        Simulation(Array(registry.values), a, p, t)
    }
    func command(_ w: [String]) throws {
        let c = w[0]
        func num(_ i: Int) -> Int {
            Int(w[i])!
        }
        if c == "PROC" {
            let id = w[1]
            try require(registry[id] == nil, "duplicate process \(id)")
            try require(registry.count < 10, "too many processes")
            try require(num(2) <= 200, "invalid arrival \(id)")
            try require(num(3) <= 9, "invalid priority \(id)")
            let words = Array(w.dropFirst(4)), bursts = words.map {
                Int($0.dropFirst())!
            }
            try require(words.count % 2 == 1 && words.enumerated().allSatisfy {
                $0.element.first! == ($0.offset % 2 == 0 ? "C" : "I") && (1...30).contains(bursts[$0.offset])
            }, "invalid bursts \(id)")
            registry[id] = Process(id, num(2), num(3), bursts)
            output.append("PROC \(id) cpu=\(bursts.enumerated().filter { $0.offset % 2 == 0 }.reduce(0) { $0 + $1.element }) io=\(bursts.enumerated().filter { $0.offset % 2 == 1 }.reduce(0) { $0 + $1.element })")
            return
        }
        if c == "GEN" {
            let ids = (1...num(2)).map {
                w[1] + String($0)
            }
            for id in ids {
                try require(registry[id] == nil, "duplicate process \(id)")
            }
            try require(registry.count + ids.count <= 10, "too many processes")
            output.append("GEN count=\(ids.count)")
            var x = num(3)
            func draw(_ m: Int) -> Int {
                x = x * 48271 % 2147483647
                return x % m
            }
            for id in ids {
                let arrival = draw(21), priority = draw(10), count = 1 + draw(3)
                var bursts: [Int] = []
                for j in 0..<count {
                    if j > 0 {
                        bursts.append(1 + draw(8))
                    }
                    bursts.append(1 + draw(9))
                }
                let p = Process(id, arrival, priority, bursts)
                registry[id] = p
                output.append(p.describe)
            }
            return
        }
        if ["SETPRIO", "DEADLINE", "DROP"].contains(c) {
            let p = try process(w[1])
            if c == "DROP" {
                registry.removeValue(forKey: w[1])
                output.append("DROP \(w[1])")
            } else if c == "SETPRIO" {
                try require(num(2) <= 9, "invalid priority \(w[1])")
                p.priority = num(2)
                output.append("SETPRIO \(w[1]) priority=\(w[2])")
            } else {
                try require(num(2) <= 1000, "invalid deadline \(w[1])")
                p.deadline = num(2) == 0 ? nil : num(2)
                output.append("DEADLINE \(w[1]) \(p.deadline.map(String.init) ?? "none")")
            }
            return
        }
        if c == "CLEAR" {
            output.append("CLEAR count=\(registry.count)")
            registry = [:]
            return
        }
        if c == "LIST" {
            output.append("LIST count=\(registry.count)")
            output += registry.keys.sorted().map {
                registry[$0]!.describe
            }
            return
        }
        if ["COMPARE", "RANK", "DIFF"].contains(c) {
            let offset = c == "COMPARE" ? 1 : c == "RANK" ? 2 : 3
            if c == "DIFF" {
                try algorithm(w[1])
                try algorithm(w[2])
            }
            if c == "RANK" {
                try require((metrics + ["end", "switches", "missed"]).contains(w[1]), "unknown metric \(w[1])")
            }
            let p = try prepare(w.dropFirst(offset))
            if c == "DIFF" {
                let a = sim(w[1], p), b = sim(w[2], p)
                output.append("DIFF \(w[1]) \(w[2]) \(notation(p))")
                var wins = 0, losses = 0
                for i in a.jobs.indices {
                    let x = a.jobs[i].metrics, y = b.jobs[i].metrics
                    output.append(a.jobs[i].id + " " + metrics.enumerated().map {
                        "\($0.element)=\(x[$0.offset])/\(y[$0.offset])"
                    }
                    .joined(separator: " "))
                    if x[0] < y[0] {
                        wins += 1
                    }
                    if x[0] > y[0] {
                        losses += 1
                    }
                }
                output.append("WINS \(w[1])=\(wins) \(w[2])=\(losses) ties=\(a.jobs.count - wins - losses)")
                return
            }
            let sims = algorithms.map {
                sim($0, p)
            }
            output.append(c == "COMPARE" ? "COMPARE \(notation(p))" : "RANK \(w[1]) \(notation(p))")
            if c == "COMPARE" {
                output.append(row(["ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS"]))
                for i in sims.indices {
                    let s = sims[i]
                    output.append(row([algorithms[i]] + s.averages + [s.util, String(s.end), String(s.switches), String(s.missed)]))
                }
                output.append("BEST " + metrics.enumerated().map {
                    j, m in let i = sims.indices.min {
                        sims[$0].totals[j] < sims[$1].totals[j]
                    }!
                    return "\(m)=\(algorithms[i])"
                }
                .joined(separator: " "))
            } else {
                let metric = metrics.firstIndex(of: w[1])
                func value(_ i: Int) -> Int {
                    if let metric {
                        return sims[i].totals[metric]
                    }
                    return w[1] == "end" ? sims[i].end : w[1] == "switches" ? sims[i].switches : sims[i].missed
                }
                let order = sims.indices.sorted {
                    value($0) == value($1) ? $0 < $1 : value($0) < value($1)
                }
                for i in order {
                    let rank = 1 + sims.indices.filter {
                        value($0) < value(i)
                    }
                    .count
                    output.append("\(rank) \(algorithms[i]) \(metric == nil ? String(value(i)) : decimal(value(i), registry.count))")
                }
            }
            return
        }
        let algo = w[1]
        try algorithm(algo)
        let offset = ["SNAPSHOT", "WINDOW"].contains(c) ? 3 : c == "SWEEP" ? 5 : 2
        if c == "WINDOW" {
            try require((1...1000).contains(num(2)), "invalid window")
        }
        if c == "SWEEP" {
            let k = w[2]
            try require(keys.contains(k), "unknown key \(k)")
            try require(allowed(algo, k), "key \(k) not allowed for \(algo)")
            try require(num(3) <= num(4) && valid(k, num(3)) && valid(k, num(4)) && num(4) - num(3) <= 20, "invalid range")
        }
        var p = try prepare(w.dropFirst(offset), algo, c == "SWEEP" ? w[2] : nil)
        if c == "SWEEP" {
            output.append("SWEEP \(algo) \(w[2]) \(w[3]) \(w[4])")
            var best = Int.max, value = num(3)
            for v in num(3)...num(4) {
                p[w[2]] = v
                let s = sim(algo, p), a = s.averages
                output.append("\(notation(p, algo)) turnaround=\(a[0]) waiting=\(a[1]) response=\(a[2]) util=\(s.util) end=\(s.end) switches=\(s.switches)")
                if s.totals[1] < best {
                    best = s.totals[1]
                    value = v
                }
            }
            output.append("BEST \(w[2])=\(value)")
            return
        }
        let s = sim(algo, p, c == "SNAPSHOT" ? num(2) : nil)
        if c == "TIMELINE" {
            try require(s.end <= 100, "too long \(s.end)")
        }
        output.append("\(c) \(algo) \(notation(p, algo))" + (c == "TIMELINE" ? " end=\(s.end)" : c == "SNAPSHOT" ? " t=\(w[2])" : c == "WINDOW" ? " width=\(w[2])" : ""))
        switch c {
            case "TRACE": output += s.events
            output.append("END \(s.end)")
            case "SNAPSHOT": output += s.snapshot
            case "TIMELINE": for j in s.jobs {
                output.append(j.id + String(repeating: " ", count: 9 - j.id.count) + j.timeline)
            }
            case "BURSTS": for j in s.jobs {
                for (i, r) in j.records.enumerated() {
                    output.append("\(j.id) #\(i + 1) len=\(r.length) ready=\(r.ready) start=\(r.start) end=\(r.end) wait=\(r.end - r.ready - r.length) slices=\(r.slices)")
                }
            }
            case "WINDOW":
            for a in stride(from: 0, to: s.end, by: num(2)) {
                let b = min(s.end, a + num(2)), (busy, sw, idle) = s.ticks(a, b)
                var counts: [String: Int] = [:]
                for i in a..<b where s.cpuStates[i] == "RUN" {
                    counts[s.labels[i], default: 0] += 1
                }
                let top = counts.keys.sorted {
                    counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]!
                }
                .first ?? "none"
                output.append("\(a)-\(b) busy=\(busy) switch=\(sw) idle=\(idle) util=\(decimal(busy * 100, b - a)) top=\(top)")
            }
            case "STATS":
            for i in 0..<3 {
                let v = s.jobs.map {
                    $0.metrics[i]
                }, sorted = v.sorted(), low = v.min()!, high = v.max()!, doubled = sorted.count % 2 == 1 ? 2 * sorted[sorted.count / 2] : sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]
                output.append("\(metrics[i]) min=\(low) (\(s.jobs[v.firstIndex(of: low)!].id)) max=\(high) (\(s.jobs[v.firstIndex(of: high)!].id)) median=\(doubled / 2).\(doubled % 2 * 5) total=\(v.reduce(0, +))")
            }
            case "RUN":
            var segments: [String] = [], start = 0
            for t in 1...s.end {
                if t == s.end || s.labels[t] != s.labels[start] {
                    segments.append("[\(start)-\(t) \(s.labels[start])]")
                    start = t
                }
            }
            for i in stride(from: 0, to: segments.count, by: 8) {
                output.append("GANTT " + segments[i..<min(i + 8, segments.count)].joined())
            }
            for j in s.jobs {
                let m = j.metrics
                output.append("\(j.id) arrival=\(j.process.arrival) done=\(j.finish) turnaround=\(m[0]) waiting=\(m[1]) response=\(m[2]) slices=\(j.records.reduce(0) { $0 + $1.slices })" + (j.process.deadline == nil ? "" : " deadline=\(j.process.absolute) late=\(max(0, j.finish - j.process.absolute))"))
            }
            let a = s.averages, (busy, sw, idle) = s.ticks(0, s.end)
            output.append("AVERAGE turnaround=\(a[0]) waiting=\(a[1]) response=\(a[2])")
            output.append("CPU end=\(s.end) busy=\(busy) switch=\(sw) idle=\(idle) switches=\(s.switches) util=\(s.util)")
            output.append("QUEUE max=\(s.queueLengths.max()!) avg=\(decimal(s.queueLengths.reduce(0, +), s.end))")
            output.append("EVENTS " + eventKinds.map {
                "\($0.lowercased())=\(s.counts[$0, default: 0])"
            }
            .joined(separator: " "))
            output.append("DEADLINE met=\(s.jobs.filter { $0.process.deadline != nil && !$0.missed }.count) missed=\(s.missed)")
            default: break
        }
    }
    func execute(_ line: String) {
        do {
            try command(line.split(separator: " ").map(String.init))
        } catch let e as CommandError {
            output.append("ERROR \(e.reason)")
        } catch {
            fatalError("Unexpected error")
        }
    }
}
let n = Int(readLine()!)!, scheduler = Scheduler()
for _ in 0..<n {
    scheduler.execute(readLine()!)
}
print(scheduler.output.joined(separator: "\n"))
