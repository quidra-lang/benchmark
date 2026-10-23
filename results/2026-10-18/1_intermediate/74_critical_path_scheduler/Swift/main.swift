import Foundation

struct Problem: Error {
    let text: String
}

func fail(_ s: String) throws -> Never {
    throw Problem(text: "error: "+s)
}

func signed(_ n: Int) -> String {
    n >= 0 ? "+\(n)" : "\(n)"
}

func decimal(_ n: Int,_ d: Int) -> String {
    let h = n*100/d
    return "\(h/100)."+String(format: "%02d",h%100)
}

func leap(_ y: Int) -> Bool {
    y%4 == 0 && (y%100 != 0 || y%400 == 0)
}

func monthDays(_ y: Int,_ m: Int) -> Int {
    m == 2 && leap(y) ? 29 : [31,28,31,30,31,30,31,31,30,31,30,31][m-1]
}

func date(_ text: String) throws -> Int {
    let p = text.split(separator: "-").map {
        Int($0)!
    }
    let y = p[0],m = p[1],d = p[2]
    if m < 1 || m > 12 || d < 1 || d > monthDays(y,m) {
        try fail("invalid date \(text)")
    }
    var day = 0
    for year in 2000..<y {
        day += leap(year) ? 366 : 365
    }
    if m > 1 {
        for month in 1..<m {
            day += monthDays(y,month)
        }
    }
    return day+d-1
}

func dateText(_ day: Int) -> String {
    var left = day
    var y = 2000
    while left >= (leap(y) ? 366 : 365) {
        left -= leap(y) ? 366 : 365
        y += 1
    }
    var m = 1
    while left >= monthDays(y,m) {
        left -= monthDays(y,m)
        m += 1
    }
    return String(format: "%04d-%02d-%02d",y,m,left+1)+" "+["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][(day+5)%7]
}

struct Task {
    let base: Int
    let resource: String
    let units: Int
    var notBefore = 0
    var crash: (Int,Int)?
    var used = 0
    var pert: [Int]?
    var duration: Int {
        base-used
    }
}

struct Dep {
    let a: String
    let b: String
    let kind: String
    let lag: Int
}

struct Times {
    let duration: Int
    let es: Int
    let ef: Int
    var ls = 0
    var lf = 0
    var tf = 0
    var ff = 0
}

struct Schedule {
    var times: [String:Times]
    let total: Int
}

struct Baseline {
    let total: Int
    let times: [String:(Int,Int)]
}

final class Project {
    var tasks = [String:Task]()
    var deps = [Dep]()
    var holidays = Set<Int>()
    var capacities = [String:Int]()
    var start: Int?
    var deadline: Int?
    var baseline: Baseline?
    var names: [String] {
        tasks.keys.sorted()
    }
    func check(_ n: String) throws {
        if tasks[n] == nil {
            try fail("unknown task \(n)")
        }
    }
    func preds(_ n: String) -> [Dep] {
        deps.filter {
            $0.b == n
        }.sorted {
            $0.a < $1.a
        }
    }
    func succs(_ n: String) -> [Dep] {
        deps.filter {
            $0.a == n
        }.sorted {
            $0.b < $1.b
        }
    }
    // Kahn removal also supplies the exact remainder used to choose a cycle.
    func order() -> ([String],String?) {
        var remaining = Set(names)
        var result = [String]()
        while let n = remaining.sorted().first(where: {
            t in preds(t).allSatisfy {
                !remaining.contains($0.a)
            }
        }) {
            remaining.remove(n)
            result.append(n)
        }
        if remaining.isEmpty {
            return (result,nil)
        }
        var walked = [remaining.sorted().first!]
        while true {
            let n = preds(walked.last!).first {
                remaining.contains($0.a)
            }!.a
            if let q = walked.firstIndex(of: n) {
                let cycle = [n]+Array(walked.dropFirst(q+1).reversed())
                let k = cycle.indices.min {
                    cycle[$0] < cycle[$1]
                }!
                let rotated = Array(cycle.dropFirst(k))+Array(cycle.prefix(k))
                return (result,(rotated+[rotated.first!]).joined(separator: " -> "))
            }
            walked.append(n)
        }
    }
    func schedule(_ changed: String? = nil,_ duration: Int = 0) -> Schedule {
        let order = order().0
        var times = [String:Times]()
        for n in order {
            let t = tasks[n]!
            let d = n == changed ? duration : t.duration
            var es = t.notBefore
            for e in preds(n) {
                let p = times[e.a]!
                es = max(es,e.kind == "FS" ? p.ef+e.lag : e.kind == "SS" ? p.es+e.lag : p.ef+e.lag-d)
            }
            times[n] = Times(duration: d,es: es,ef: es+d)
        }
        let total = times.values.map(\.ef).max()!
        for n in order.reversed() {
            var t = times[n]!
            var lf = total
            for e in succs(n) {
                let p = times[e.b]!
                lf = min(lf,e.kind == "FS" ? p.ls-e.lag : e.kind == "SS" ? p.ls-e.lag+t.duration : p.lf-e.lag)
            }
            t.lf = lf
            t.ls = lf-t.duration
            t.tf = t.ls-t.es
            times[n] = t
        }
        let s = Schedule(times: times,total: total)
        for n in order {
            var t = times[n]!
            t.ff = min(total-t.ef,succs(n).map {
                margin($0,s)
            }.min() ?? Int.max)
            times[n] = t
        }
        return Schedule(times: times,total: total)
    }
    func margin(_ e: Dep,_ s: Schedule) -> Int {
        let a = s.times[e.a]!,b = s.times[e.b]!
        return e.kind == "FS" ? b.es-a.ef-e.lag : e.kind == "SS" ? b.es-a.es-e.lag : b.ef-a.ef-e.lag
    }
    func critical(_ s: Schedule) -> [String] {
        names.filter {
            s.times[$0]!.tf == 0
        }
    }
    func paths(_ s: Schedule) -> [[String]] {
        let links = deps.filter {
            s.times[$0.a]!.tf == 0 && s.times[$0.b]!.tf == 0 && margin($0,s) == 0
        }
        var result = [[String]]()
        func visit(_ p: [String]) {
            let next = links.filter {
                $0.a == p.last!
            }.map(\.b).sorted()
            if next.isEmpty {
                result.append(p)
            } else {
                for n in next {
                    visit(p+[n])
                }
            }
        }
        for n in critical(s) where !links.contains(where: {
            $0.b == n
        }) {
            visit([n])
        }
        return result
    }
    func working(_ d: Int) -> Bool {
        (d+5)%7 < 5 && !holidays.contains(d)
    }
    func usage(_ resource: String,_ times: [String:(Int,Int)],_ total: Int) -> [Int] {
        (0..<total).map {
            day in tasks.reduce(0) {
                sum,pair in let (n,t) = pair
                let interval = times[n]!
                return sum+(t.resource == resource && day >= interval.0 && day < interval.1 ? t.units : 0)
            }
        }
    }
    func command(_ w: [String]) throws -> [String] {
        let c = w[0]
        let a = Array(w.dropFirst())
        func num(_ i: Int) -> Int {
            Int(a[i])!
        }
        var out = [String]()
        switch c {
        case "TASK":
            if tasks[a[0]] != nil {
                try fail("task \(a[0]) already exists")
            }
            tasks[a[0]] = Task(base: num(1),resource: a[2],units: num(3))
            return ["task \(a[0]) added"]
        case "DEP","UNDEP":
            try check(a[0])
            try check(a[1])
            let i = deps.firstIndex {
                $0.a == a[0] && $0.b == a[1]
            }
            if c == "DEP" {
                if a[0] == a[1] {
                    try fail("self dependency \(a[0])")
                }
                if i != nil {
                    try fail("dependency \(a[0]) -> \(a[1]) already exists")
                }
                deps.append(Dep(a: a[0],b: a[1],kind: a[2],lag: num(3)))
                return ["dependency \(a[0]) -> \(a[1]) \(a[2])\(signed(num(3))) added"]
            }
            guard let i = i else {
                try fail("no dependency \(a[0]) -> \(a[1])")
            }
            deps.remove(at: i)
            return ["dependency \(a[0]) -> \(a[1]) removed"]
        case "REMOVE":
            try check(a[0])
            let k = deps.filter {
                $0.a == a[0] || $0.b == a[0]
            }.count
            deps.removeAll {
                $0.a == a[0] || $0.b == a[0]
            }
            tasks.removeValue(forKey: a[0])
            return ["task \(a[0]) removed with \(k) dependencies"]
        case "NOTBEFORE":
            try check(a[0])
            tasks[a[0]]!.notBefore = num(1)
            return ["notbefore \(a[0]) \(a[1])"]
        case "CRASHCOST":
            try check(a[0])
            let t = tasks[a[0]]!
            if num(1) >= t.base {
                try fail("crash limit too large for \(a[0])")
            }
            if num(1) < t.used {
                try fail("crash limit below used days for \(a[0])")
            }
            tasks[a[0]]!.crash = (num(1),num(2))
            return ["crash \(a[0]) max \(a[1]) cost \(a[2])"]
        case "UNCRASH":
            try check(a[0])
            out.append("uncrash \(a[0]) restored \(tasks[a[0]]!.used) days")
            tasks[a[0]]!.used = 0
            return out
        case "PERT":
            try check(a[0])
            let o = num(1),m = num(2),p = num(3)
            if o > m || m > p {
                try fail("invalid estimate")
            }
            tasks[a[0]]!.pert = [o,m,p]
            return ["pert \(a[0]) expected \(decimal(o+4*m+p,6)) variance \(decimal((p-o)*(p-o),36))"]
        case "CAPACITY":
            capacities[a[0]] = num(1)
            return ["capacity \(a[0]) \(a[1])"]
        case "START","HOLIDAY","DEADLINE":
            let d = try date(a[0])
            if c == "HOLIDAY" && holidays.contains(d) {
                try fail("duplicate holiday \(a[0])")
            }
            if c == "START" {
                start = d
            } else if c == "DEADLINE" {
                deadline = d
            } else {
                holidays.insert(d)
            }
            return ["\(c.lowercased()) \(dateText(d))"]
        case "LIST":
            out.append("tasks \(tasks.count), dependencies \(deps.count), holidays \(holidays.count)")
            for n in names {
                let t = tasks[n]!
                let p = preds(n).map(\.a).joined(separator: " ")
                out.append("\(n) duration \(t.duration) resource \(t.resource) units \(t.units) preds \(p.isEmpty ? "none" : p)")
            }
            return out
        case "SHOW":
            let n = a[0]
            try check(n)
            let t = tasks[n]!
            out.append("task \(n) duration \(t.duration) resource \(t.resource) units \(t.units)"+(t.notBefore != 0 ? " notbefore \(t.notBefore)" : ""))
            let p = preds(n).map {
                "\($0.a) \($0.kind)\(signed($0.lag))"
            }.joined(separator: ", ")
            let q = succs(n).map {
                "\($0.b) \($0.kind)\(signed($0.lag))"
            }.joined(separator: ", ")
            out.append("preds: "+(p.isEmpty ? "none" : p))
            out.append("succs: "+(q.isEmpty ? "none" : q))
            out.append(t.crash.map {
                "crash: max \($0.0) used \(t.used) cost \($0.1)"
            } ?? "crash: none")
            out.append(t.pert.map {
                "pert: "+$0.map(String.init).joined(separator: " ")
            } ?? "pert: none")
            if order().1 != nil {
                out.append("schedule: unavailable")
            } else {
                let x = schedule().times[n]!
                out.append("schedule: ES \(x.es) EF \(x.ef) LS \(x.ls) LF \(x.lf) TF \(x.tf) FF \(x.ff)"+(x.tf == 0 ? " critical" : ""))
            }
            return out
        case "IMPACT":
            try check(a[0])
            var reached: Set<String> = [a[0]]
            while true {
                let before = reached.count
                for e in deps where reached.contains(e.a) {
                    reached.insert(e.b)
                }
                if reached.count == before {
                    break
                }
            }
            reached.remove(a[0])
            return ["impact \(a[0]): "+(reached.isEmpty ? "none" : reached.sorted().joined(separator: " "))]
        default:
            break
        }
        if tasks.isEmpty {
            try fail("no tasks")
        }
        if let cycle = order().1 {
            try fail("cycle "+cycle)
        }
        switch c {
        case "CALENDAR":
            if start == nil {
                try fail("no start date")
            }
        case "LEVEL":
            for n in names {
                let t = tasks[n]!
                let cap = capacities[t.resource] ?? num(0)
                if t.units > cap {
                    try fail("capacity \(cap) too small for \(n)")
                }
            }
        case "LOAD":
            if !tasks.values.contains(where: {
                $0.resource == a[0]
            }) {
                try fail("unknown resource \(a[0])")
            }
        case "WHATIF":
            try check(a[0])
        case "VARIANCE":
            if baseline == nil {
                try fail("no baseline")
            }
        default:
            break
        }
        let s = schedule()
        let byStart = names.sorted {
            s.times[$0]!.es == s.times[$1]!.es ? $0 < $1 : s.times[$0]!.es < s.times[$1]!.es
        }
        let resources = Set(tasks.values.map(\.resource)).sorted()
        let initialTimes = s.times.mapValues {
            ($0.es,$0.ef)
        }
        switch c {
        case "CPM":
            let width = max(4,names.map(\.count).max()!)
            func right(_ s: String,_ w: Int) -> String {
                s+String(repeating: " ",count: max(0,w-s.count))
            }
            func left(_ s: String) -> String {
                String(repeating: " ",count: max(0,5-s.count))+s
            }
            out.append(right("TASK",width)+["DUR","ES","EF","LS","LF","TF","FF"].map {
                left($0)
            }.joined())
            for n in names {
                let x = s.times[n]!
                out.append(right(n,width)+[x.duration,x.es,x.ef,x.ls,x.lf,x.tf,x.ff].map {
                    left(String($0))
                }.joined()+(x.tf == 0 ? " *" : ""))
            }
            out.append("project duration \(s.total)")
        case "CRITICAL":
            let p = paths(s)
            out.append("critical paths: \(p.count)")
            out += p.map {
                $0.joined(separator: " -> ")
            }
        case "SLACK":
            for f in Set(s.times.values.map(\.tf)).sorted() {
                out.append("float \(f): "+names.filter {
                    s.times[$0]!.tf == f
                }.joined(separator: " "))
            }
        case "DRAG":
            for n in critical(s) {
                out.append("\(n) drag \(s.total-schedule(n,0).total)")
            }
        case "STATS":
            let count = critical(s).count
            let sum = s.times.values.reduce(0) {
                $0+$1.tf
            }
            out.append("tasks \(tasks.count), critical \(count), dependencies \(deps.count) (FS \(deps.filter { $0.kind == "FS" }.count), SS \(deps.filter { $0.kind == "SS" }.count), FF \(deps.filter { $0.kind == "FF" }.count))")
            out.append("work "+resources.map {
                r in "\(r) \(tasks.values.filter { $0.resource == r }.reduce(0) { $0+$1.duration*$1.units })"
            }.joined(separator: ", "))
            out.append("float total \(sum), average \(decimal(sum,tasks.count))")
            out.append("duration \(s.total), critical share \(decimal(100*count,tasks.count))%")
        case "CALENDAR":
            var dates = [Int]()
            var day = start!
            while dates.count < s.total {
                if working(day) {
                    dates.append(day)
                }
                day += 1
            }
            for n in byStart {
                let x = s.times[n]!
                out.append("\(n) \(dateText(dates[x.es])) - \(dateText(dates[x.ef-1]))")
            }
            let first = dates.first!,last = dates.last!
            out.append("project \(dateText(first)) - \(dateText(last)), \(s.total) working days, \(last-first+1) calendar days")
            if let d = deadline {
                let low = min(d,last),high = max(d,last)
                let count = low < high ? ((low+1)...high).filter {
                    working($0)
                }.count : 0
                out.append(last <= d ? "deadline \(dateText(d)) met, \(count) working days to spare" : "deadline \(dateText(d)) missed by \(count) working days")
            }
            let h = holidays.filter {
                $0 >= first && $0 <= last && ($0+5)%7 < 5
            }.sorted().map {
                dateText($0)
            }.joined(separator: ", ")
            out.append("holidays in span: "+(h.isEmpty ? "none" : h))
        case "GANTT":
            if s.total > 60 {
                try fail("chart too wide (\(s.total) days)")
            }
            let width = names.map(\.count).max()!
            out.append(String(repeating: " ",count: width)+" |"+(0..<s.total).map {
                String($0%10)
            }.joined()+"|")
            for n in byStart {
                let x = s.times[n]!
                let bar = (0..<s.total).map {
                    k in k >= x.es && k < x.ef ? (x.tf == 0 ? "=" : "-") : k >= x.ef && k < x.lf ? "." : " "
                }.joined()
                out.append(n+String(repeating: " ",count: width-n.count)+" |"+bar+"|")
            }
        case "LEVEL":
            var decided = [String:(Int,Int)]()
            var decision = [String]()
            var daily = [String:[Int:Int]]()
            while decided.count < tasks.count {
                let n = names.filter {
                    decided[$0] == nil && preds($0).allSatisfy {
                        decided[$0.a] != nil
                    }
                }.min {
                    s.times[$0]!.ls == s.times[$1]!.ls ? $0 < $1 : s.times[$0]!.ls < s.times[$1]!.ls
                }!
                let t = tasks[n]!
                var begin = t.notBefore
                for e in preds(n) {
                    let p = decided[e.a]!
                    begin = max(begin,e.kind == "FS" ? p.1+e.lag : e.kind == "SS" ? p.0+e.lag : p.1+e.lag-t.duration)
                }
                let capacity = capacities[t.resource] ?? num(0)
                while (begin..<(begin+t.duration)).contains(where: {
                    (daily[t.resource]?[$0] ?? 0)+t.units > capacity
                }) {
                    begin += 1
                }
                let finish = begin+t.duration
                decided[n] = (begin,finish)
                decision.append(n)
                for d in begin..<finish {
                    daily[t.resource,default: [:]][d,default: 0] += t.units
                }
            }
            let total = decided.values.map {
                $0.1
            }.max()!
            out.append("level capacity \(a[0]): duration \(s.total) -> \(total)")
            for n in decision {
                let p = decided[n]!
                out.append("\(n) start \(p.0) finish \(p.1) shift \(p.0-s.times[n]!.es)")
            }
            for r in resources {
                out.append("resource \(r) capacity \(capacities[r] ?? num(0)) peak \(usage(r,initialTimes,s.total).max()!) -> \(usage(r,decided,total).max()!)")
            }
        case "LOAD":
            let load = usage(a[0],initialTimes,s.total)
            let peak = load.max()!
            out.append("load \(a[0]): "+load.map(String.init).joined(separator: " "))
            out.append("peak \(peak) on day \(load.firstIndex(of: peak)!)")
            if let cap = capacities[a[0]] {
                out.append("capacity \(cap) exceeded on \(load.filter { $0 > cap }.count) days")
            }
        case "PERTSUM":
            for p in paths(s) {
                var expected = 0
                var variance = 0
                for n in p {
                    let t = tasks[n]!
                    let values = t.pert ?? [t.duration,t.duration,t.duration]
                    expected += values[0]+4*values[1]+values[2]
                    variance += (values[2]-values[0])*(values[2]-values[0])
                }
                out.append(p.joined(separator: " -> ")+": expected \(decimal(expected,6)) variance \(decimal(variance,36))")
            }
        case "CRASH":
            let budget = num(0)
            var remaining = budget
            var count = 0
            var reason = ""
            while true {
                let now = schedule()
                let candidates = critical(now).filter {
                    n in let t = tasks[n]!
                    return t.crash != nil && t.used < t.crash!.0 && schedule(n,t.duration-1).total < now.total
                }
                if candidates.isEmpty {
                    reason = "no candidate"
                    break
                }
                let n = candidates.min {
                    tasks[$0]!.crash!.1 == tasks[$1]!.crash!.1 ? $0 < $1 : tasks[$0]!.crash!.1 < tasks[$1]!.crash!.1
                }!
                let cost = tasks[n]!.crash!.1
                if cost > remaining {
                    reason = "insufficient budget"
                    break
                }
                let before = tasks[n]!.duration
                tasks[n]!.used += 1
                remaining -= cost
                count += 1
                out.append("step \(count): \(n) \(before) -> \(tasks[n]!.duration), cost \(cost), project \(schedule().total)")
            }
            out.append("crash done: \(count) days, cost \(budget-remaining), project \(s.total) -> \(schedule().total), budget left \(remaining), \(reason)")
        case "WHATIF":
            let after = schedule(a[0],num(1))
            out.append("whatif \(a[0]) \(tasks[a[0]]!.duration) -> \(a[1]): project \(s.total) -> \(after.total)")
            for n in names {
                let x = s.times[n]!,y = after.times[n]!
                let fields = [("ES",x.es,y.es),("EF",x.ef,y.ef),("TF",x.tf,y.tf)].filter {
                    $0.1 != $0.2
                }
                if !fields.isEmpty {
                    out.append(n+fields.map {
                        " \($0.0) \($0.1)->\($0.2)"
                    }.joined())
                }
            }
            let beforeCritical = critical(s),afterCritical = critical(after)
            if beforeCritical != afterCritical {
                out.append("critical "+beforeCritical.joined(separator: " ")+" -> "+afterCritical.joined(separator: " "))
            }
        case "BASELINE":
            baseline = Baseline(total: s.total,times: initialTimes)
            out.append("baseline saved: \(tasks.count) tasks, duration \(s.total)")
        case "VARIANCE":
            let old = baseline!
            out.append("variance: duration \(old.total) -> \(s.total) (\(signed(s.total-old.total)))")
            for n in Set(old.times.keys).union(tasks.keys).sorted() {
                if let x = old.times[n] {
                    if let y = initialTimes[n] {
                        if x.0 != y.0 || x.1 != y.1 {
                            out.append("\(n) start \(signed(y.0-x.0)) finish \(signed(y.1-x.1))")
                        }
                    } else {
                        out.append("\(n) removed")
                    }
                } else {
                    out.append("\(n) new")
                }
            }
            if out.count == 1 {
                out.append("no task changes")
            }
        default:
            break
        }
        return out
    }
}

let project = Project()
if let first = readLine(),let count = Int(first) {
    for _ in 0..<count {
        do {
            for line in try project.command(readLine()!.split(separator: " ").map(String.init)) {
                print(line)
            }
        } catch let problem as Problem {
            print(problem.text)
        } catch {
        }
    }
}
