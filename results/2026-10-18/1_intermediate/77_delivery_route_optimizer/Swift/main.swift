import Foundation

struct Problem: Error {
    let text: String
}

func fail(_ s: String) throws -> Never {
    throw Problem(text: "error: "+s)
}

func time(_ s: String) -> Int {
    let p = s.split(separator: ":").map {
        Int($0)!
    }
    return p[0]*60+p[1]
}

func timeText(_ t: Int) -> String {
    String(format: "%02d:%02d",t/60,t%60)
}

func name(_ n: Int) -> String {
    n == 0 ? "D" : String(n)
}

func notation(_ p: [Int]) -> String {
    (["D"]+p.map(String.init)+["D"]).joined(separator: "-")
}

struct Stop {
    let x: Int
    let y: Int
    let demand: Int
    let service: Int
    let window: (Int,Int)?
}

struct Plan {
    let capacity: Int
    var routes: [[Int]]
}

struct Run {
    let lines: [String]
    let returned: Int
    let violations: Int
    let lateness: Int
}

struct TourMove {
    let path: [Int]
    let text: String
}

struct PlanMove {
    let routes: [[Int]]
    let text: String
}

struct State: Hashable {
    let mask: Int
    let at: Int
}

final class Workbench {
    var depot: (Int,Int)?
    var start = 480
    var stops = [Int:Stop]()
    var tour: [Int]?
    var plan: Plan?
    var ids: [Int] {
        stops.keys.sorted()
    }
    func point(_ n: Int) -> (Int,Int) {
        if n == 0 {
            return depot!
        }
        let s = stops[n]!
        return (s.x,s.y)
    }
    func d(_ a: Int,_ b: Int) -> Int {
        let x = point(a),y = point(b)
        return abs(x.0-y.0)+abs(x.1-y.1)
    }
    func length(_ p: [Int]) -> Int {
        var at = 0
        var sum = 0
        for n in p {
            sum += d(at,n)
            at = n
        }
        return sum+d(at,0)
    }
    func load(_ p: [Int]) -> Int {
        p.reduce(0) {
            $0+stops[$1]!.demand
        }
    }
    func normalize(_ routes: [[Int]]) -> [[Int]] {
        routes.filter {
            !$0.isEmpty
        }.map {
            $0.first! > $0.last! ? Array($0.reversed()) : $0
        }.sorted {
            $0.min()! < $1.min()!
        }
    }
    func total(_ p: Plan) -> Int {
        p.routes.reduce(0) {
            $0+length($1)
        }
    }
    func routeLines(_ p: Plan) -> [String] {
        p.routes.enumerated().map {
            i,r in "route \(i+1): \(notation(r)) load \(load(r)) length \(length(r))"
        }
    }
    func construction() throws {
        if depot == nil {
            try fail("no depot")
        }
        if stops.isEmpty {
            try fail("no stops")
        }
    }
    func getTour() throws -> [Int] {
        guard let tour = tour else {
            try fail("no tour")
        }
        return tour
    }
    func getPlan() throws -> Plan {
        guard let plan = plan else {
            try fail("no plan")
        }
        return plan
    }
    func capacity(_ q: Int) throws {
        for n in ids where stops[n]!.demand > q {
            try fail("stop \(n) demand \(stops[n]!.demand) exceeds capacity \(q)")
        }
    }
    func run(_ p: [Int]) -> Run {
        var at = 0
        var t = start
        var wait = 0
        var service = 0
        var violations = 0
        var late = 0
        var out = [String]()
        for n in p {
            let s = stops[n]!
            let arrival = t+d(at,n)
            let w = max(0,(s.window?.0 ?? arrival)-arrival)
            let begin = arrival+w
            let e = max(0,arrival-(s.window?.1 ?? arrival))
            t = begin+s.service
            wait += w
            service += s.service
            if e > 0 {
                violations += 1
            }
            late += e
            out.append("\(n) arrive \(timeText(arrival)) wait \(w) begin \(timeText(begin)) leave \(timeText(t)) "+(e > 0 ? "late \(e)" : "ok"))
            at = n
        }
        t += d(at,0)
        out.append("return \(timeText(t)), travel \(length(p)), wait \(wait), service \(service), violations \(violations), lateness \(late)")
        return Run(lines: out,returned: t,violations: violations,lateness: late)
    }
    func firstTourMove(_ p: [Int],_ kind: String) -> TourMove? {
        let before = length(p),n = p.count
        if kind == "OROPT" {
            for size in 1...3 where size <= n {
                for i in 0...(n-size) {
                    let segment = Array(p[i..<(i+size)])
                    let rest = Array(p.prefix(i))+Array(p.dropFirst(i+size))
                    for j in 0...rest.count where j != i {
                        let next = Array(rest.prefix(j))+segment+Array(rest.dropFirst(j))
                        let gain = before-length(next)
                        if gain > 0 {
                            return TourMove(path: next,text: "move "+segment.map(String.init).joined(separator: "-")+" after \(name(j == 0 ? 0 : rest[j-1])) gain \(gain)")
                        }
                    }
                }
            }
        } else if n >= 2 {
            for i in 0..<(n-1) {
                for j in (i+1)..<n {
                    var next = p
                    if kind == "TWOOPT" {
                        next.replaceSubrange(i...j,with: p[i...j].reversed())
                    } else {
                        next.swapAt(i,j)
                    }
                    let gain = before-length(next)
                    if gain > 0 {
                        return TourMove(path: next,text: kind == "TWOOPT" ? "reverse \(p[i])..\(p[j]) gain \(gain)" : "swap \(p[i]) and \(p[j]) gain \(gain)")
                    }
                }
            }
        }
        return nil
    }
    func firstPlanMove(_ p: Plan,_ kind: String) -> PlanMove? {
        let rs = p.routes,k = rs.count
        func replaced(_ r: Int,_ a: [Int],_ t: Int,_ b: [Int]) -> [[Int]] {
            var next = rs
            next[r] = a
            next[t] = b
            return next
        }
        if kind == "RELOCATE" {
            for r in 0..<k {
                for pos in rs[r].indices {
                    for t in 0..<k where t != r {
                        let c = rs[r][pos]
                        if load(rs[t])+stops[c]!.demand > p.capacity {
                            continue
                        }
                        for j in 0...rs[t].count {
                            var a = rs[r]
                            a.remove(at: pos)
                            var b = rs[t]
                            b.insert(c,at: j)
                            let gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                            if gain > 0 {
                                return PlanMove(routes: replaced(r,a,t,b),text: "relocate \(c) from route \(r+1) to route \(t+1) after \(name(j == 0 ? 0 : rs[t][j-1])) gain \(gain)")
                            }
                        }
                    }
                }
            }
        } else {
            for r in 0..<k {
                for t in (r+1)..<k {
                    if kind == "EXCHANGE" {
                        for pos in rs[r].indices {
                            for j in rs[t].indices {
                                let c = rs[r][pos],e = rs[t][j]
                                var a = rs[r],b = rs[t]
                                a[pos] = e
                                b[j] = c
                                if load(a) > p.capacity || load(b) > p.capacity {
                                    continue
                                }
                                let gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                                if gain > 0 {
                                    return PlanMove(routes: replaced(r,a,t,b),text: "exchange \(c) (route \(r+1)) with \(e) (route \(t+1)) gain \(gain)")
                                }
                            }
                        }
                    } else {
                        for i in 0...rs[r].count {
                            for j in 0...rs[t].count {
                                let a = Array(rs[r].prefix(i))+Array(rs[t].dropFirst(j))
                                let b = Array(rs[t].prefix(j))+Array(rs[r].dropFirst(i))
                                if load(a) > p.capacity || load(b) > p.capacity {
                                    continue
                                }
                                let gain = length(rs[r])+length(rs[t])-length(a)-length(b)
                                if gain > 0 {
                                    return PlanMove(routes: replaced(r,a,t,b),text: "cross route \(r+1) after \(name(i == 0 ? 0 : rs[r][i-1])) with route \(t+1) after \(name(j == 0 ? 0 : rs[t][j-1])) gain \(gain)")
                                }
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    func mst(_ initial: Int,_ vertices: [Int]) -> (Int,[String]) {
        var entered = [initial]
        var left = Set(vertices)
        left.remove(initial)
        var sum = 0
        var edges = [String]()
        while !left.isEmpty {
            var best: (Int,Int,Int)?
            for c in left.sorted() {
                for (i,p) in entered.enumerated() {
                    let candidate = (d(p,c),c,i)
                    if best == nil || candidate < best! {
                        best = candidate
                    }
                }
            }
            let (weight,c,i) = best!
            let p = entered[i]
            entered.append(c)
            left.remove(c)
            sum += weight
            edges.append("\(name(p))-\(c)")
        }
        return (sum,edges)
    }
    func exactCost(_ ids: [Int],_ mask: Int,_ at: Int,_ memo: inout [State:Int]) -> Int {
        if mask == (1 << ids.count)-1 {
            return d(at,0)
        }
        let key = State(mask: mask,at: at)
        if let value = memo[key] {
            return value
        }
        var best = Int.max
        for (i,n) in ids.enumerated() where mask & (1 << i) == 0 {
            let cost = d(at,n)+exactCost(ids,mask | (1 << i),n,&memo)
            best = min(best,cost)
        }
        memo[key] = best
        return best
    }
    func command(_ w: [String]) throws -> [String] {
        let c = w[0]
        let a = Array(w.dropFirst())
        func n(_ i: Int) -> Int {
            Int(a[i])!
        }
        var out = [String]()
        switch c {
        case "DEPOT":
            depot = (n(0),n(1))
            return ["depot at (\(a[0]),\(a[1]))"]
        case "START":
            start = time(a[0])
            return ["start \(timeText(start))"]
        case "STOP":
            let id = n(0)
            if stops[id] != nil {
                try fail("stop \(id) already exists")
            }
            let window = a.count == 7 ? (time(a[5]),time(a[6])) : nil
            if let window = window,window.0 > window.1 {
                try fail("invalid window")
            }
            stops[id] = Stop(x: n(1),y: n(2),demand: n(3),service: n(4),window: window)
            tour = nil
            plan = nil
            return ["stop \(id) added"]
        case "REMOVE":
            let id = n(0)
            if stops.removeValue(forKey: id) == nil {
                try fail("unknown stop \(id)")
            }
            if stops.isEmpty {
                tour = nil
                plan = nil
            } else {
                tour = tour?.filter {
                    $0 != id
                }
                if var p = plan {
                    p.routes = normalize(p.routes.map {
                        $0.filter {
                            $0 != id
                        }
                    })
                    plan = p
                }
            }
            return ["stop \(id) removed"]
        case "LIST":
            out.append(depot.map {
                "depot (\($0.0),\($0.1))"
            } ?? "depot none")
            out.append("start \(timeText(start))")
            out.append("stops \(stops.count)")
            for id in ids {
                let s = stops[id]!
                out.append("\(id) at (\(s.x),\(s.y)) demand \(s.demand) service \(s.service) window "+(s.window.map {
                    "\(timeText($0.0))-\(timeText($0.1))"
                } ?? "none"))
            }
            return out
        case "MATRIX":
            if depot == nil {
                try fail("no depot")
            }
            let locations = [0]+ids
            let rows = [[""]+locations.map {
                name($0)
            }]+locations.map {
                x in [name(x)]+locations.map {
                    String(d(x,$0))
                }
            }
            let width = rows.flatMap {
                $0
            }.map(\.count).max()!
            return rows.map {
                $0.map {
                    String(repeating: " ",count: width-$0.count)+$0
                }.joined(separator: " ")
            }
        case "TOUR":
            let p = try getTour()
            return ["tour: \(notation(p)) length \(length(p))"]
        case "TIMECHECK":
            let p: [Int]
            if a.isEmpty {
                p = try getTour()
                out.append("timecheck tour depart \(timeText(start))")
            } else {
                let plan = try getPlan()
                let r = n(0)
                if r > plan.routes.count {
                    try fail("no route \(r)")
                }
                p = plan.routes[r-1]
                out.append("timecheck route \(r) depart \(timeText(start))")
            }
            return out+run(p).lines
        case "TWOOPT","OROPT","SWAP":
            var p = try getTour()
            let before = length(p)
            var count = 0
            while let move = firstTourMove(p,c) {
                out.append(move.text)
                p = move.path
                count += 1
            }
            tour = p
            out.append("\(c.lowercased()): moves \(count), length \(before) -> \(length(p))")
            return out
        case "ROUTES":
            let p = try getPlan()
            return ["plan: capacity \(p.capacity), routes \(p.routes.count), length \(total(p))"]+routeLines(p)
        case "RELOCATE","EXCHANGE","CROSS":
            var p = try getPlan()
            let before = total(p),countBefore = p.routes.count
            var count = 0
            while let move = firstPlanMove(p,c) {
                out.append(move.text)
                p.routes = normalize(move.routes)
                count += 1
            }
            let routePart = c == "EXCHANGE" ? "" : "routes \(countBefore) -> \(p.routes.count), "
            out.append("\(c.lowercased()): moves \(count), \(routePart)length \(before) -> \(total(p))")
            plan = p
            return out
        case "ROUTEOPT":
            var p = try getPlan()
            let before = total(p)
            for i in p.routes.indices {
                let original = p.routes[i]
                var route = original
                var count = 0
                while let move = firstTourMove(route,"TWOOPT") {
                    route = move.path
                    count += 1
                }
                out.append("route \(i+1): moves \(count), length \(length(original)) -> \(length(route))")
                p.routes[i] = route
            }
            p.routes = normalize(p.routes)
            out.append("routeopt: length \(before) -> \(total(p))")
            plan = p
            return out
        case "REPORT":
            let demand = stops.values.reduce(0) {
                $0+$1.demand
            }
            out.append("report: stops \(stops.count), demand \(demand), service \(stops.values.reduce(0) { $0+$1.service }), windows \(stops.values.filter { $0.window != nil }.count)")
            if let tour = tour {
                let r = run(tour)
                out.append("tour: length \(length(tour)), return \(timeText(r.returned)), violations \(r.violations), lateness \(r.lateness)")
            } else {
                out.append("tour: none")
            }
            if let p = plan {
                let runs = p.routes.map {
                    run($0)
                }
                let capacity = p.routes.count*p.capacity
                let u = (2000*demand+capacity)/(2*capacity)
                out.append("plan: capacity \(p.capacity), routes \(p.routes.count), length \(total(p)), utilization \(u/10).\(u%10)%, return \(timeText(runs.map(\.returned).max()!)), violations \(runs.reduce(0) { $0+$1.violations }), lateness \(runs.reduce(0) { $0+$1.lateness })")
            } else {
                out.append("plan: none")
            }
            return out
        case "SPLIT":
            let p = try getTour()
            let q = n(0)
            try capacity(q)
            var values = Array(repeating: Int.max,count: p.count+1)
            var previous = Array(repeating: 0,count: p.count+1)
            values[0] = 0
            for j in 1...p.count {
                for i in 0..<j {
                    let part = Array(p[i..<j])
                    if load(part) <= q {
                        let candidate = values[i]+length(part)
                        if candidate < values[j] {
                            values[j] = candidate
                            previous[j] = i
                        }
                    }
                }
            }
            var routes = [[Int]]()
            var j = p.count
            while j > 0 {
                let i = previous[j]
                routes.append(Array(p[i..<j]))
                j = i
            }
            let result = Plan(capacity: q,routes: normalize(routes))
            plan = result
            return ["split: capacity \(q), routes \(result.routes.count), length \(total(result))"]+routeLines(result)
        default:
            break
        }
        try construction()
        switch c {
        case "ORDER":
            let values = a.map {
                Int($0)!
            }
            for id in values where stops[id] == nil {
                try fail("unknown stop \(id)")
            }
            var seen = Set<Int>()
            for id in values {
                if !seen.insert(id).inserted {
                    try fail("duplicate stop \(id)")
                }
            }
            if values.count != stops.count {
                try fail("order has \(values.count) stops, expected \(stops.count)")
            }
            tour = values
        case "NEAREST":
            var remaining = Set(ids)
            var p = [Int]()
            var at = 0
            while !remaining.isEmpty {
                let next = remaining.min {
                    (d(at,$0),$0) < (d(at,$1),$1)
                }!
                p.append(next)
                remaining.remove(next)
                at = next
            }
            tour = p
        case "INSERTION":
            var p = [Int]()
            while p.count < stops.count {
                var best: (Int,Int,Int)?
                for id in ids where !p.contains(id) {
                    for j in 0...p.count {
                        let left = j == 0 ? 0 : p[j-1],right = j == p.count ? 0 : p[j]
                        let candidate = (d(left,id)+d(id,right)-d(left,right),id,j)
                        if best == nil || candidate < best! {
                            best = candidate
                        }
                    }
                }
                let (_,id,j) = best!
                p.insert(id,at: j)
            }
            tour = p
        case "EXACT":
            if stops.count > 10 {
                try fail("too many stops for exact (\(stops.count))")
            }
            let ids = self.ids
            let full = (1 << ids.count)-1
            var memo = [State:Int]()
            var mask = 0
            var at = 0
            var p = [Int]()
            while mask != full {
                let target = exactCost(ids,mask,at,&memo)
                let i = ids.indices.first {
                    mask & (1 << $0) == 0 && d(at,ids[$0])+exactCost(ids,mask | (1 << $0),ids[$0],&memo) == target
                }!
                at = ids[i]
                p.append(at)
                mask |= 1 << i
            }
            tour = p
        case "BOUND":
            let ids = self.ids
            let (m,edges) = mst(0,ids)
            let tree = ids.count == 1 ? 2*d(0,ids[0]) : mst(ids[0],ids).0+ids.map {
                d(0,$0)
            }.sorted().prefix(2).reduce(0,+)
            let bound = max(m,tree)
            out.append("mst: "+edges.joined(separator: " ")+" (length \(m))")
            out.append("bound: mst \(m), one-tree \(tree), best \(bound)")
            if let p = tour {
                let l = length(p)
                let u = bound == 0 ? 0 : (2000*(l-bound)+bound)/(2*bound)
                out.append("gap: tour \(l), \(u/10).\(u%10)%")
            } else {
                out.append("gap: no tour")
            }
            return out
        case "VRP","SWEEP":
            let q = n(0)
            try capacity(q)
            let limit = a.count == 2 ? n(1) : nil
            if let limit = limit {
                for id in ids where 2*d(0,id) > limit {
                    try fail("stop \(id) too far for limit \(limit)")
                }
            }
            var routes = [[Int]]()
            var merges = 0
            if c == "VRP" {
                let ids = self.ids
                routes = ids.map {
                    [$0]
                }
                var savings = [(Int,Int,Int)]()
                for (i,x) in ids.enumerated() {
                    for y in ids.dropFirst(i+1) {
                        let saving = d(0,x)+d(0,y)-d(x,y)
                        if saving > 0 {
                            savings.append((-saving,x,y))
                        }
                    }
                }
                savings.sort {
                    $0 < $1
                }
                for (_,x,y) in savings {
                    let ia = routes.firstIndex {
                        $0.contains(x)
                    }!,ib = routes.firstIndex {
                        $0.contains(y)
                    }!
                    if ia == ib {
                        continue
                    }
                    var left = routes[ia],right = routes[ib]
                    if (x != left.first! && x != left.last!) || (y != right.first! && y != right.last!) {
                        continue
                    }
                    if load(left)+load(right) > q {
                        continue
                    }
                    if left.last! != x {
                        left.reverse()
                    }
                    if right.first! != y {
                        right.reverse()
                    }
                    let joined = left+right
                    if let limit = limit,length(joined) > limit {
                        continue
                    }
                    routes[ia] = joined
                    routes.remove(at: ib)
                    merges += 1
                }
            } else {
                let center = depot!
                let ordered = ids.sorted {
                    x,y in let a = point(x),b = point(y)
                    let ax = a.0-center.0,ay = a.1-center.1,bx = b.0-center.0,by = b.1-center.1
                    let az = ax == 0 && ay == 0,bz = bx == 0 && by == 0
                    if az || bz {
                        return az != bz ? az : x < y
                    }
                    let ah = ay > 0 || ay == 0 && ax > 0 ? 0 : 1,bh = by > 0 || by == 0 && bx > 0 ? 0 : 1
                    if ah != bh {
                        return ah < bh
                    }
                    let cross = ax*by-ay*bx
                    if cross != 0 {
                        return cross > 0
                    }
                    return d(0,x) == d(0,y) ? x < y : d(0,x) < d(0,y)
                }
                var route = [Int]()
                var load = 0
                for id in ordered {
                    let demand = stops[id]!.demand
                    if load+demand > q {
                        routes.append(route)
                        route = []
                        load = 0
                    }
                    route.append(id)
                    load += demand
                }
                routes.append(route)
            }
            let result = Plan(capacity: q,routes: normalize(routes))
            plan = result
            out.append(c == "VRP" ? "vrp: capacity \(q), merges \(merges), routes \(result.routes.count), length \(total(result))" : "sweep: capacity \(q), routes \(result.routes.count), length \(total(result))")
            out += routeLines(result)
            return out
        default:
            break
        }
        let p = try getTour()
        return ["\(c.lowercased()): \(notation(p)) length \(length(p))"]
    }
}

let workbench = Workbench()
if let first = readLine(),let count = Int(first) {
    for _ in 0..<count {
        do {
            for line in try workbench.command(readLine()!.split(separator: " ").map(String.init)) {
                print(line)
            }
        } catch let p as Problem {
            print(p.text)
        } catch {
        }
    }
}
