import Foundation

let noNet = 1000000
enum Fault: Error { case reason(String) }
func error(_ condition: Bool, _ reason: String) throws {
    if condition { throw Fault.reason(reason) }
}
func away(_ n: Int, _ d: Int) -> Int { n < 0 ? -((2*(-n)+d)/(2*d)) : (2*n+d)/(2*d) }
func up(_ n: Int, _ d: Int) -> Int {
    let a = 2*n+d
    return a/(2*d)-(a%(2*d) < 0 ? 1 : 0)
}
func signed(_ n: Int) -> String { (n < 0 ? "-" : "")+"\(abs(n)/10).\(abs(n)%10)" }
func index(_ n: Int?) -> String {
    guard let n else { return "none" }
    return n < 0 ? "+"+signed(-n) : signed(n)
}
func handicap(_ n: Int?) -> String {
    guard let n else { return "none" }
    return n < 0 ? "+\(-n)" : String(n)
}
func cents(_ n: Int) -> String {
    String(format: "%ld.%02ld",locale: Locale(identifier: "en_US_POSIX"),n/100,n%100)
}
func average(_ total: Int, _ count: Int) -> String { count == 0 ? "-" : cents(total*100/count) }
func sum(_ a: [Int], _ from: Int = 0, _ to: Int = 18) -> Int { a[from..<to].reduce(0,+) }
final class Tee {
    let id: String
    let rating: Int
    let slope: Int
    init(_ id: String, _ rating: Int, _ slope: Int) {
        self.id = id
        self.rating = rating
        self.slope = slope
    }
}
final class Course {
    let id: String
    let par: [Int]
    let si: [Int]
    let total: Int
    var tees: [String:Tee] = [:]
    init(_ id: String, _ par: [Int], _ si: [Int]) {
        self.id = id
        self.par = par
        self.si = si
        total = par.reduce(0,+)
    }
}
struct IndexRecord {
    let day: Int
    let value: Int
}
struct Calculation {
    let k: Int
    let average: Int
    let adjustment: Int
    let low: Int?
    let hard: Bool
    let soft: Bool
    let maximum: Bool
}
struct Round {
    let course: Course
    let tee: Tee
    let day: Int
    let raw: [String]
    let handicap: Int?
    let scores: [Int]
    let adjusted: [Int]
    let ags: Int
    let diff: Int
    let exceptional: Int
    let oldIndex: Int?
    let oldCalculation: Calculation?
    let oldRecords: Int
}
final class Player {
    let id: String
    let name: String
    var index: Int?
    var calculation: Calculation?
    var rounds: [Round] = []
    var records: [IndexRecord] = []
    init(_ id: String, _ name: String, _ index: Int?) {
        self.id = id
        self.name = name
        self.index = index
    }
}
struct Event {
    let id: String
    let format: String
    let course: Course
    let tee: Tee
    let day: Int
    let allowance: Int
    let players: [Player]
}
struct Eligible {
    let start: Int
    let adjusted: [Int]
    let counting: [Int]
    let k: Int
    let adjustment: Int
}
struct EventData {
    let e: Event
    let rounds: [Round]
    let ph: [Int]
    let strokes: [Int]
    let nets: [[Int]]
    let points: [[Int]]
    let par: [[Int]]
}
struct Match {
    let statuses: [String]
    let result: String
}
func allocate(_ c: Course, _ h: Int) -> [Int] {
    (0..<18).map { i in
        h >= 0 ? h/18+(c.si[i] <= h%18 ? 1 : 0) : -((-h)/18)-(c.si[i] >= 19-(-h)%18 ? 1 : 0)
    }
}
func courseHandicap(_ c: Course, _ t: Tee, _ i: Int) -> Int { up(i*t.slope+113*(t.rating-10*c.total),1130) }
final class Scorer {
    var courses: [String:Course] = [:]
    var players: [String:Player] = [:]
    var events: [String:Event] = [:]
    var eventOrder: [Event] = []
    var output: [String] = []
    func player(_ id: String) throws -> Player {
        guard let p = players[id] else { throw Fault.reason("unknown player") }
        return p
    }
    func course(_ id: String) throws -> Course {
        guard let c = courses[id] else { throw Fault.reason("unknown course") }
        return c
    }
    func tee(_ c: Course, _ id: String) throws -> Tee {
        guard let t = c.tees[id] else { throw Fault.reason("unknown tee") }
        return t
    }
    func low(_ p: Player, _ day: Int) -> IndexRecord? {
        p.records.filter { $0.day >= day-365 && $0.day < day }.min {
            $0.value == $1.value ? $0.day < $1.day : $0.value < $1.value
        }
    }
    func eligible(_ p: Player) -> Eligible {
        let start = max(0,p.rounds.count-20)
        let n = p.rounds.count-start
        var reduction = 0
        var adjusted = Array(repeating:0,count:n)
        if n > 0 {
            for i in stride(from:n-1,through:0,by:-1) {
                let r = p.rounds[start+i]
                reduction += r.exceptional
                adjusted[i] = r.diff-reduction
            }
        }
        let k: Int
        switch n {
        case 0...2: k = 0
        case 3...5: k = 1
        case 6...8: k = 2
        case 9...11: k = 3
        case 12...14: k = 4
        case 15...16: k = 5
        case 17...18: k = 6
        case 19: k = 7
        default: k = 8
        }
        let adjustment = n == 3 ? -20 : n == 4 || n == 6 ? -10 : 0
        let counting = Array((0..<n).sorted { adjusted[$0] == adjusted[$1] ? $0 > $1 : adjusted[$0] < adjusted[$1] }.prefix(k))
        return Eligible(start:start,adjusted:adjusted,counting:counting,k:k,adjustment:adjustment)
    }
    func update(_ p: Player, _ day: Int) {
        let e = eligible(p)
        if e.k == 0 {
            p.calculation = nil
            return
        }
        let a = away(e.counting.reduce(0) { $0+e.adjusted[$1] },e.k)
        var c = a+e.adjustment
        let l = low(p,day)?.value
        var soft = false
        var hard = false
        var maximum = false
        if let l, c-l > 30 {
            let next = l+30+(c-l-30)/2
            soft = next != c
            c = next
        }
        if let l, c-l > 50 {
            c = l+50
            hard = true
        }
        if c > 540 {
            c = 540
            maximum = true
        }
        p.index = c
        p.calculation = Calculation(k:e.k,average:a,adjustment:e.adjustment,low:l,hard:hard,soft:soft,maximum:maximum)
    }
    func data(_ e: Event) throws -> EventData {
        var rounds: [Round] = []
        let n = e.players.count
        var ph = Array(repeating:0,count:n)
        for i in 0..<n {
            guard let r = e.players[i].rounds.first(where:{ $0.course === e.course && $0.tee === e.tee && $0.day == e.day }) else {
                throw Fault.reason("missing round")
            }
            guard let h = r.handicap else { throw Fault.reason("no index") }
            rounds.append(r)
            ph[i] = up(h*e.allowance,100)
        }
        let minimum = ph.min()!
        let relative = ["MATCH","NASSAU","FOURBALL"].contains(e.format)
        let strokes = ph.map { $0-(relative ? minimum : 0) }
        var nets = Array(repeating:Array(repeating:0,count:18),count:n)
        var points = nets
        var par = nets
        for i in 0..<n {
            let allocation = allocate(e.course,strokes[i])
            for h in 0..<18 {
                nets[i][h] = rounds[i].scores[h] == noNet ? noNet : rounds[i].scores[h]-allocation[h]
                points[i][h] = nets[i][h] == noNet ? 0 : max(0,e.course.par[h]+2-nets[i][h])
                par[i][h] = nets[i][h] == noNet || nets[i][h] > e.course.par[h] ? -1 : nets[i][h] < e.course.par[h] ? 1 : 0
            }
        }
        return EventData(e:e,rounds:rounds,ph:ph,strokes:strokes,nets:nets,points:points,par:par)
    }
    func rank(_ values: [[Int]], _ candidates: [Int], _ high: Bool, _ ids: [String]) -> [Int] {
        candidates.map { i in
            (index:i,key:[0,9,12,15,17].map { (high ? -1 : 1)*sum(values[i],$0) })
        }.sorted { a,b in
            a.key == b.key ? ids[a.index] < ids[b.index] : a.key.lexicographicallyPrecedes(b.key)
        }.map { $0.index }
    }
    func ranked(_ d: EventData) -> [Int] {
        let candidates = d.ph.indices.filter { d.e.format != "STROKE" || !d.rounds[$0].scores.contains(noNet) }
        let values = d.e.format == "STROKE" ? d.nets : d.e.format == "PAR" ? d.par : d.points
        return rank(values,candidates,d.e.format != "STROKE",d.e.players.map { $0.id })
    }
    func status(_ lead: Int) -> String { lead == 0 ? "AS" : lead > 0 ? "\(lead) UP" : "\(-lead) DN" }
    func match(_ wins: [Int], _ first: Int, _ last: Int, _ a: String, _ b: String) -> Match {
        var lead = 0
        var remaining = 0
        var statuses: [String] = []
        for h in first...last {
            lead += wins[h]
            remaining = last-h
            statuses.append(status(lead))
            if abs(lead) > remaining { break }
        }
        let result = lead == 0 ? "AS" : (lead > 0 ? a : b)+" \(abs(lead))"+(remaining > 0 ? "&\(remaining)" : " UP")
        return Match(statuses:statuses,result:result)
    }
    func results(_ e: Event, _ d: EventData) {
        output.append("results \(e.id): \(e.format) \(e.course.id) \(e.tee.id) day \(e.day) allowance \(e.allowance)")
        let n = e.players.count
        let ids = e.players.map { $0.id }
        switch e.format {
        case "STROKE", "STABLEFORD", "PAR":
            let order = ranked(d)
            for (r,i) in order.enumerated() {
                let value: String
                if e.format == "STROKE" { value = "net \(sum(d.nets[i])) gross \(sum(d.rounds[i].scores))" }
                else if e.format == "STABLEFORD" { value = "points \(sum(d.points[i]))" }
                else { value = status(sum(d.par[i])) }
                output.append("\(r+1) \(ids[i]) \(value) hcp \(handicap(d.ph[i]))")
            }
            if e.format == "STROKE" {
                for i in ids.indices.filter({ !order.contains($0) }).sorted(by:{ ids[$0] < ids[$1] }) {
                    output.append("NR \(ids[i]) hcp \(handicap(d.ph[i]))")
                }
                if !order.isEmpty {
                    let gross = d.rounds.map { $0.scores }
                    let winner = rank(gross,order,false,ids)[0]
                    output.append("gross \(ids[winner]) \(sum(gross[winner]))")
                }
            }
        case "MATCH", "NASSAU", "FOURBALL":
            output.append("strokes"+ids.indices.map { " \(ids[$0]) \(d.strokes[$0])" }.joined())
            let size = n/2
            let a = ids.prefix(size).joined(separator:"+")
            let b = ids.dropFirst(size).joined(separator:"+")
            let wins = (0..<18).map { h -> Int in
                let left = (0..<size).map { d.nets[$0][h] }.min()!
                let right = (size..<n).map { d.nets[$0][h] }.min()!
                return right < left ? -1 : right > left ? 1 : 0
            }
            if e.format == "NASSAU" {
                output.append("front "+match(wins,0,8,a,b).result)
                output.append("back "+match(wins,9,17,a,b).result)
                output.append("total "+match(wins,0,17,a,b).result)
            } else {
                let m = match(wins,0,17,a,b)
                output.append("status "+m.statuses.joined(separator:", "))
                output.append("result "+m.result)
            }
        case "BETTERBALL":
            let values = (0..<n/2).map { i in (0..<18).map { h in max(d.points[2*i][h],d.points[2*i+1][h]) } }
            let order = rank(values,Array(0..<n/2),true,(0..<n/2).map { ids[2*$0] })
            for (r,i) in order.enumerated() {
                output.append("\(r+1) \(ids[2*i])+\(ids[2*i+1]) points \(sum(values[i])) hcp \(handicap(d.ph[2*i])) \(handicap(d.ph[2*i+1]))")
            }
        case "SKINS":
            var carry = 0
            var totals = Array(repeating:0,count:n)
            var tied = Array(ids.indices)
            for h in 0..<18 {
                carry += 1
                let minimum = ids.indices.map { d.nets[$0][h] }.min()!
                tied = ids.indices.filter { d.nets[$0][h] == minimum }
                if minimum != noNet && tied.count == 1 {
                    let i = tied[0]
                    output.append("hole \(h+1) \(ids[i]) \(carry)")
                    totals[i] += carry*100
                    carry = 0
                }
            }
            if carry > 0 {
                tied.sort { ids[$0] < ids[$1] }
                for i in tied { totals[i] += carry*100/tied.count }
                output.append("carry \(carry)"+tied.map { " \(ids[$0])" }.joined())
            }
            let order = ids.indices.sorted { totals[$0] == totals[$1] ? ids[$0] < ids[$1] : totals[$0] > totals[$1] }
            for i in order { output.append("\(ids[i]) \(cents(totals[i]))") }
        default: break
        }
    }
    func cardTotal(_ label: String, _ r: Round, _ strokes: [Int], _ nets: [Int], _ points: [Int], _ from: Int, _ to: Int) {
        let complete = !r.scores[from..<to].contains(noNet)
        let gross = complete ? String(sum(r.scores,from,to)) : "-"
        let net = complete ? String(sum(nets,from,to)) : "-"
        output.append("\(label) \(sum(r.course.par,from,to)) \(gross) \(sum(r.adjusted,from,to)) \(sum(strokes,from,to)) \(net) \(sum(points,from,to))")
    }
    func card(_ p: Player, _ number: Int, _ r: Round) {
        output.append("card \(p.id) \(number): \(r.course.id) \(r.tee.id) day \(r.day) handicap \(handicap(r.handicap))")
        let strokes = allocate(r.course,r.handicap ?? 0)
        let nets = (0..<18).map { r.scores[$0] == noNet ? noNet : r.scores[$0]-strokes[$0] }
        let points = (0..<18).map { nets[$0] == noNet ? 0 : max(0,r.course.par[$0]+2-nets[$0]) }
        for h in 0..<18 {
            let net = nets[h] == noNet ? "-" : String(nets[h])
            output.append("\(h+1) \(r.course.par[h]) \(r.course.si[h]) \(r.raw[h]) \(r.adjusted[h]) \(strokes[h]) \(net) \(points[h])")
            if h == 8 { cardTotal("OUT",r,strokes,nets,points,0,9) }
            if h == 17 {
                cardTotal("IN",r,strokes,nets,points,9,18)
                cardTotal("TOTAL",r,strokes,nets,points,0,18)
            }
        }
        output.append("ags \(r.ags) diff \(signed(r.diff))")
    }
    func statistics(_ p: Player) {
        var category = Array(repeating:0,count:7)
        var totals = Array(repeating:0,count:3)
        var counts = Array(repeating:0,count:3)
        var complete: [Int] = []
        for r in p.rounds {
            var full = true
            for h in 0..<18 {
                if r.raw[h] == "X" { category[6] += 1 }
                if r.scores[h] == noNet {
                    full = false
                    continue
                }
                let relative = r.scores[h]-r.course.par[h]
                let k = relative <= -2 ? 0 : relative <= 2 ? relative+2 : 5
                category[k] += 1
                let i = r.course.par[h]-3
                totals[i] += r.scores[h]
                counts[i] += 1
            }
            if full { complete.append(sum(r.scores)) }
        }
        let best = complete.min().map(String.init) ?? "-"
        var line = "stats \(p.id): rounds \(p.rounds.count) best \(best) average \(average(complete.reduce(0,+),complete.count))"
        let labels = ["eagles","birdies","pars","bogeys","doubles","others","pickups"]
        for i in 0..<7 { line += " \(labels[i]) \(category[i])" }
        for i in 0..<3 { line += " par\(i+3) \(average(totals[i],counts[i]))" }
        output.append(line)
    }
    func execute(_ t: [String]) throws {
        switch t[0] {
        case "COURSE":
            try error(courses[t[1]] != nil,"duplicate course")
            let par = (0..<18).map { Int(t[$0+2])! }
            let si = (0..<18).map { Int(t[$0+20])! }
            try error(par.contains { $0 < 3 || $0 > 5 } || Set(si).count != 18 || si.contains { $0 < 1 || $0 > 18 },"invalid course")
            courses[t[1]] = Course(t[1],par,si)
        case "TEE":
            let c = try course(t[1])
            try error(c.tees[t[2]] != nil,"duplicate tee")
            let rating = Int(t[3])!
            let slope = Int(t[4])!
            try error(rating < 500 || rating > 900 || slope < 55 || slope > 155,"invalid tee")
            c.tees[t[2]] = Tee(t[2],rating,slope)
        case "PLAYER":
            try error(players[t[1]] != nil,"duplicate player")
            let i: Int? = t.count == 4 ? Int(t[3])! : nil
            try error(i != nil && (i! < -100 || i! > 540),"invalid index")
            players[t[1]] = Player(t[1],t[2],i)
        case "ROUND":
            let p = try player(t[1])
            let c = try course(t[2])
            let tee = try tee(c,t[3])
            let day = Int(t[4])!
            try error(!p.rounds.isEmpty && day < p.rounds.last!.day,"invalid day")
            let raw = Array(t.dropFirst(5))
            try error(raw.filter { $0 == "-" }.count >= 5,"too few holes")
            let previous = p.index
            let hcp = previous.map { courseHandicap(c,tee,$0) }
            let strokes = allocate(c,hcp ?? 0)
            let scores = raw.map { Int($0) ?? noNet }
            let adjusted = (0..<18).map { h -> Int in
                let limit = c.par[h]+(previous == nil ? 5 : 2+strokes[h])
                if raw[h] == "-" { return c.par[h]+strokes[h] }
                if raw[h] == "X" { return limit }
                return min(scores[h],limit)
            }
            let ags = adjusted.reduce(0,+)
            let diff = away(113*(10*ags-tee.rating),tee.slope)
            let exceptional = previous != nil && previous!-diff >= 70 ? (previous!-diff >= 100 ? 20 : 10) : 0
            let r = Round(course:c,tee:tee,day:day,raw:raw,handicap:hcp,scores:scores,adjusted:adjusted,ags:ags,diff:diff,
                exceptional:exceptional,oldIndex:previous,oldCalculation:p.calculation,oldRecords:p.records.count)
            p.rounds.append(r)
            update(p,day)
            if let i = p.index { p.records.append(IndexRecord(day:day,value:i)) }
            output.append("round \(p.id) \(p.rounds.count): ags \(ags) diff \(signed(diff))"+(exceptional == 0 ? "" : " exceptional \(signed(-exceptional))")+" index \(index(p.index))")
        case "REMOVE":
            let p = try player(t[1])
            try error(p.rounds.isEmpty,"no rounds")
            let number = p.rounds.count
            let r = p.rounds.removeLast()
            p.index = r.oldIndex
            p.calculation = r.oldCalculation
            p.records.removeSubrange(r.oldRecords..<p.records.count)
            output.append("removed \(p.id) \(number): index \(index(p.index))")
        case "INDEX":
            let p = try player(t[1])
            var line = "index \(p.id): \(index(p.index)) rounds \(p.rounds.count)"
            if let c = p.calculation {
                line += " lowest \(c.k) average \(signed(c.average)) adjustment \(signed(c.adjustment))"+
                    (c.low == nil ? "" : " low \(index(c.low))")+(c.hard ? " hard cap" : c.soft ? " soft cap" : "")+(c.maximum ? " maximum" : "")
            }
            output.append(line)
        case "HISTORY":
            let p = try player(t[1])
            let e = eligible(p)
            output.append("history \(p.id): rounds \(p.rounds.count)")
            for i in e.adjusted.indices {
                let r = p.rounds[e.start+i]
                output.append("\(e.start+i+1) day \(r.day) \(r.course.id) \(r.tee.id) ags \(r.ags) diff \(signed(r.diff))"+
                    (r.diff == e.adjusted[i] ? "" : " adjusted \(signed(e.adjusted[i]))")+(e.counting.contains(i) ? " *" : ""))
            }
        case "LOWINDEX":
            let p = try player(t[1])
            let day = Int(t[2])!
            let r = low(p,day)
            output.append("lowindex \(p.id) \(day): "+(r == nil ? "none" : "\(index(r!.value)) day \(r!.day)"))
        case "COURSEHCP":
            let p = try player(t[1])
            let c = try course(t[2])
            let tee = try tee(c,t[3])
            guard let i = p.index else { throw Fault.reason("no index") }
            let h = courseHandicap(c,tee,i)
            output.append("coursehcp \(p.id) \(c.id) \(tee.id): \(handicap(h)) strokes "+allocate(c,h).map(String.init).joined(separator:" "))
        case "HCPTABLE":
            let c = try course(t[1])
            let tee = try tee(c,t[2])
            let first = Int(t[3])!
            let last = Int(t[4])!
            try error(first < -100 || first > last || last > 540,"invalid index")
            output.append("hcptable \(c.id) \(tee.id): \(index(first)) to \(index(last))")
            var start = first
            var h = courseHandicap(c,tee,first)
            for i in (first+1)...(last+1) {
                let next = i <= last ? courseHandicap(c,tee,i) : h+1
                if next != h {
                    output.append("\(index(start)) to \(index(i-1)): \(handicap(h))")
                    start = i
                    h = next
                }
            }
        case "CARD":
            let p = try player(t[1])
            let n = Int(t[2])!
            try error(n > p.rounds.count,"unknown round")
            card(p,n,p.rounds[n-1])
        case "STATS": try statistics(player(t[1]))
        case "HOLESTATS":
            let c = try course(t[1])
            let rounds = players.values.flatMap { $0.rounds }.filter { $0.course === c }
            var totals = Array(repeating:0,count:18)
            var counts = Array(repeating:0,count:18)
            var ranks = Array(repeating:0,count:18)
            for r in rounds {
                for h in 0..<18 where r.scores[h] != noNet {
                    totals[h] += r.scores[h]
                    counts[h] += 1
                }
            }
            let order = (0..<18).sorted { a,b in
                if counts[a] == 0 || counts[b] == 0 {
                    return counts[a] == counts[b] ? a < b : counts[a] != 0
                }
                let left = (totals[a]-c.par[a]*counts[a])*counts[b]
                let right = (totals[b]-c.par[b]*counts[b])*counts[a]
                return left == right ? a < b : left > right
            }
            for (i,h) in order.enumerated() { ranks[h] = i+1 }
            output.append("holestats \(c.id): rounds \(rounds.count)")
            for h in 0..<18 { output.append("\(h+1) par \(c.par[h]) si \(c.si[h]) scores \(counts[h]) avg \(average(totals[h],counts[h])) rank \(ranks[h])") }
        case "PLAYERS":
            let order = players.values.sorted { a,b in
                if a.index == nil || b.index == nil { return a.index == b.index ? a.id < b.id : a.index != nil }
                return a.index == b.index ? a.id < b.id : a.index! < b.index!
            }
            output.append("players \(order.count)")
            for p in order { output.append("\(p.id) \(p.name) \(index(p.index)) rounds \(p.rounds.count)") }
        case "EVENT":
            try error(events[t[1]] != nil,"duplicate event")
            let c = try course(t[3])
            let tee = try tee(c,t[4])
            let allowance = Int(t[6])!
            try error(allowance < 1 || allowance > 100,"invalid allowance")
            let list = try t.dropFirst(7).map { try player($0) }
            let n = list.count
            let valid: Bool
            switch t[2] {
            case "MATCH", "NASSAU": valid = n == 2
            case "FOURBALL": valid = n == 4
            case "BETTERBALL": valid = [4,6,8].contains(n)
            default: valid = n >= 2 && n <= 8
            }
            try error(Set(list.map { $0.id }).count != n || !valid,"invalid players")
            let e = Event(id:t[1],format:t[2],course:c,tee:tee,day:Int(t[5])!,allowance:allowance,players:list)
            events[t[1]] = e
            eventOrder.append(e)
        case "RESULTS":
            guard let e = events[t[1]] else { throw Fault.reason("unknown event") }
            try results(e,data(e))
        case "MERIT":
            var merit: [String:[Int]] = [:]
            let awards = [10,8,6,5,4,3,2,1]
            var count = 0
            for e in eventOrder where ["STROKE","STABLEFORD","PAR"].contains(e.format) {
                guard let d = try? data(e) else { continue }
                count += 1
                for p in e.players { merit[p.id,default:[0,0,0]][2] += 1 }
                for (i,p) in ranked(d).enumerated() {
                    let id = e.players[p].id
                    merit[id]![0] += awards[i]
                    if i == 0 { merit[id]![1] += 1 }
                }
            }
            let order = merit.keys.sorted { a,b in
                if merit[a]![0] != merit[b]![0] { return merit[a]![0] > merit[b]![0] }
                if merit[a]![1] != merit[b]![1] { return merit[a]![1] > merit[b]![1] }
                return a < b
            }
            output.append("merit: events \(count)")
            for (i,id) in order.enumerated() {
                let a = merit[id]!
                output.append("\(i+1) \(id) \(a[0]) wins \(a[1]) played \(a[2])")
            }
        default: break
        }
    }
    func process(_ line: String) -> [String] {
        output = []
        do { try execute(line.split(separator:" ").map(String.init)) }
        catch Fault.reason(let reason) { output.append("ERROR "+reason) }
        catch { fatalError("Unexpected error") }
        return output
    }
}
let scorer = Scorer()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    for line in scorer.process(readLine()!) { print(line) }
}
