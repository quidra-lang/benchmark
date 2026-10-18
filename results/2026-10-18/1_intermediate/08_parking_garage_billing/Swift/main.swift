import Foundation

let types = ["MOTORCYCLE","CAR","ECAR","VAN","BUS"]
let kinds = ["MOTO","COMPACT","LARGE","EV"]
let prefs = [[0,1,2],[1,2],[3,1,2],[2],[2]]
enum Fault: Error { case message(String) }
func error(_ condition: Bool, _ message: String) throws {
    if condition { throw Fault.message(message) }
}
func two(_ n: Int) -> String { (n < 10 ? "0" : "")+String(n) }
func time(_ n: Int) -> String { "\(n/1440+1)-\(two(n/60%24)):\(two(n%60))" }
func duration(_ n: Int) -> String { "\(n/60):\(two(n%60))" }
func tenths(_ n: Int) -> String { "\(n/10).\(n%10)" }
final class Spot {
    let level: Int
    let number: Int
    let kind: Int
    let order: Int
    var closed = false
    weak var occupant: Vehicle?
    init(_ level: Int, _ number: Int, _ kind: Int, _ order: Int) {
        self.level = level
        self.number = number
        self.kind = kind
        self.order = order
    }
    func id() -> String { "L\(level)-\(number)" }
    func free() -> Bool { !closed && occupant == nil }
}
final class Vehicle {
    let plate: String
    let kind: Int
    let entry: Int
    var spots: [Spot]
    var energy = 0
    var charge = 0
    var validation = 0
    var paidAt = -1
    var paidParking = 0
    var paidNight = 0
    init(_ plate: String, _ kind: Int, _ entry: Int, _ spots: [Spot]) {
        self.plate = plate
        self.kind = kind
        self.entry = entry
        self.spots = spots
    }
    func location() -> String { spots[0].id()+(kind == 4 ? "..\(spots[2].number)" : "") }
}
struct Waiting {
    let plate: String
    let kind: Int
    let joined: Int
}
struct Visit {
    let entry: Int
    let exit: Int
    let location: String
    let kind: Int
    let total: Int
    let loss: Bool
}
final class Ledger { var rows = Array(repeating:Array(repeating:0,count:4),count:5) }
final class Garage {
    var now = 0
    var peak = 0
    var peakAt = 0
    var levels: [[Spot]] = []
    var spots: [Spot] = []
    var parked: [String:Vehicle] = [:]
    var queue: [Waiting] = []
    var passes: [String:Int] = [:]
    var history: [String:[Visit]] = [:]
    var rates = [[100,800],[200,1600],[200,1600],[300,2400],[600,4800]]
    var night = 300
    var lost = 2000
    var kwh = 30
    var stats = Array(repeating:Array(repeating:0,count:9),count:5)
    var days: [Int:Ledger] = [:]
    var output: [String] = []
    func emit(_ s: String) { output.append(s) }
    func daily(_ date: Int) -> Ledger {
        if let existing = days[date] { return existing }
        let result = Ledger()
        days[date] = result
        return result
    }
    func hasPass(_ plate: String) -> Bool { (passes[plate] ?? 0) >= now/1440+1 }
    func vehicle(_ plate: String) throws -> Vehicle {
        guard let v = parked[plate] else { throw Fault.message(plate+" is not parked") }
        return v
    }
    func spot(_ id: String) throws -> Spot {
        let p = id.dropFirst().split(separator:"-")
        let l = Int(p[0])!
        let n = Int(p[1])!
        try error(l > levels.count || n > levels[l-1].count,"unknown spot "+id)
        return levels[l-1][n-1]
    }
    func assign(_ kind: Int) -> [Spot]? {
        if kind == 4 {
            for level in levels where level.count >= 3 {
                for i in 0..<(level.count-2) {
                    let triple = Array(level[i..<i+3])
                    if triple.allSatisfy({ $0.kind == 2 && $0.free() }) { return triple }
                }
            }
        } else {
            for wanted in prefs[kind] {
                for s in spots where s.kind == wanted && s.free() { return [s] }
            }
        }
        return nil
    }
    func occupy(_ v: Vehicle) { for s in v.spots { s.occupant = v } }
    func free(_ v: Vehicle) { for s in v.spots { s.occupant = nil } }
    func park(_ plate: String, _ kind: Int, _ assigned: [Spot]) -> Vehicle {
        let v = Vehicle(plate,kind,now,assigned)
        parked[plate] = v
        occupy(v)
        stats[kind][0] += 1
        daily(now/1440+1).rows[kind][0] += 1
        if parked.count > peak {
            peak = parked.count
            peakAt = now
        }
        return v
    }
    func refuse(_ kind: Int, _ at: Int) {
        stats[kind][2] += 1
        daily(at/1440+1).rows[kind][2] += 1
    }
    func giveup() {
        for w in queue {
            if now-w.joined >= 30 {
                queue.removeAll { $0.plate == w.plate }
                refuse(w.kind,w.joined+30)
                emit("GIVEUP \(w.plate) \(types[w.kind]) \(time(w.joined+30))")
            }
        }
    }
    func admit() {
        for w in queue {
            if let assigned = assign(w.kind) {
                queue.removeAll { $0.plate == w.plate }
                let v = park(w.plate,w.kind,assigned)
                emit("ADMIT \(v.plate) \(types[v.kind]) \(v.location()) waited \(duration(now-w.joined))")
            }
        }
    }
    func interval(_ v: Vehicle, _ start: Int, _ free: Int) -> [Int] {
        let total = now-start
        if hasPass(v.plate) || total <= free { return [0,0] }
        var parking = 0
        for offset in stride(from:0,to:total,by:1440) {
            let billable = min(total-offset,1440)-(offset == 0 ? free : 0)
            parking += min((billable+29)/30*rates[v.kind][0],rates[v.kind][1])
        }
        return [parking,(now/1440-start/1440)*night]
    }
    func fees(_ v: Vehicle, _ loss: Bool) -> [Int] {
        let pair = interval(v,v.paidAt < 0 ? v.entry : v.paidAt,v.paidAt < 0 ? 15+v.validation : 15)
        let parking = pair[0]+(v.paidAt < 0 ? 0 : v.paidParking)
        let surcharge = pair[1]+(v.paidAt < 0 ? 0 : v.paidNight)
        let ticket = loss ? lost : 0
        let total = parking+surcharge+ticket+v.charge
        return [parking,surcharge,ticket,v.charge,total,v.paidAt < 0 ? total : pair[0]+pair[1]]
    }
    func feeLine(_ label: String, _ v: Vehicle, _ f: [Int]) -> String {
        "\(label) \(v.plate) \(v.location()) stay \(duration(now-v.entry)) parking \(f[0])"+
        " night \(f[1]) lost \(f[2]) charge \(f[3]) total \(f[4]) due \(f[5])"
    }
    func annotation(_ v: Vehicle) -> String {
        (hasPass(v.plate) ? " PASS" : "")+(v.validation > 0 ? " VAL \(v.validation)" : "")+
        (v.energy > 0 ? " KWH \(v.energy)" : "")+(v.paidAt >= 0 ? " PAID" : "")
    }
    func ordered() -> [Vehicle] { parked.values.sorted { $0.spots[0].order < $1.spots[0].order } }
    func move(_ v: Vehicle, _ target: [Spot]) {
        let old = v.location()
        free(v)
        v.spots = target
        occupy(v)
        emit("MOVE \(v.plate) \(old) -> \(v.location())")
    }
    func occupancy(_ target: [Spot]) -> [Int] {
        var a = Array(repeating:0,count:9)
        for s in target {
            if s.closed { a[8] += 1 }
            else { a[4+s.kind] += 1 }
            if s.occupant != nil { a[s.kind] += 1 }
        }
        return a
    }
    func occupancyLine(_ label: String, _ a: [Int]) -> String {
        label+(0..<4).map { " \(kinds[$0]) \(a[$0])/\(a[$0+4])" }.joined()+" closed \(a[8])"
    }
    func revenueLine(_ label: String, _ a: [Int]) -> String {
        "\(label) exits \(a[1]) parking \(a[4]) night \(a[5]) lost \(a[6]) charge \(a[7]) total \(a[8])"
    }
    func statsLine(_ label: String, _ a: [Int]) -> String {
        "\(label) entries \(a[0]) exits \(a[1]) refused \(a[2]) avg_stay \(tenths(a[1] == 0 ? 0 : a[3]*10/a[1]))"
    }
    func dailyLine(_ label: String, _ a: [Int]) -> String { "\(label) entries \(a[0]) exits \(a[1]) refused \(a[2]) revenue \(a[3])" }
    func sum(_ a: [[Int]], _ width: Int) -> [Int] { (0..<width).map { i in a.reduce(0) { $0+$1[i] } } }
    func execute(_ t: [String]) throws {
        var trigger = false
        let command = t[2]
        switch command {
        case "LEVEL":
            var added: [Spot] = []
            let counts = (0..<4).map { Int(t[$0+3])! }
            for k in 0..<4 {
                for _ in 0..<counts[k] {
                    let s = Spot(levels.count+1,added.count+1,k,spots.count)
                    added.append(s)
                    spots.append(s)
                }
            }
            levels.append(added)
            emit("LEVEL \(levels.count) spots \(added.count) MOTO \(counts[0]) COMPACT \(counts[1]) LARGE \(counts[2]) EV \(counts[3])")
            trigger = true
        case "CLOSE", "OPEN":
            let s = try spot(t[3])
            if command == "CLOSE" {
                try error(s.closed,"spot \(t[3]) is already closed")
                try error(s.occupant != nil,"spot \(t[3]) is occupied by \(s.occupant?.plate ?? "")")
                s.closed = true
            } else {
                try error(!s.closed,"spot \(t[3]) is not closed")
                s.closed = false
                trigger = true
            }
            emit("\(command) \(s.id()) \(kinds[s.kind])")
        case "RATE":
            guard let k = types.firstIndex(of:t[3]) else { throw Fault.message("unknown type "+t[3]) }
            let rate = Int(t[4])!
            let cap = Int(t[5])!
            try error(cap < rate,"cap below rate for "+t[3])
            rates[k] = [rate,cap]
            emit("RATE \(t[3]) \(rate) \(cap)")
        case "FEE":
            let amount = Int(t[4])!
            try error(!["NIGHT","LOST","KWH"].contains(t[3]),"unknown fee "+t[3])
            switch t[3] {
            case "NIGHT": night = amount
            case "LOST": lost = amount
            default: kwh = amount
            }
            emit("FEE \(t[3]) \(amount)")
        case "ENTER":
            let plate = t[3]
            guard let k = types.firstIndex(of:t[4]) else { throw Fault.message("unknown type "+t[4]) }
            let existing = parked[plate]
            try error(existing != nil,"\(plate) is already parked at \(existing?.location() ?? "")")
            try error(queue.contains { $0.plate == plate },plate+" is already waiting")
            if let assigned = assign(k) { emit("ENTER \(plate) \(types[k]) \(park(plate,k,assigned).location())") }
            else if queue.count < 3 {
                queue.append(Waiting(plate:plate,kind:k,joined:now))
                emit("WAIT \(plate) \(types[k]) \(queue.count)")
            } else {
                refuse(k,now)
                emit("FULL \(plate) \(types[k])")
            }
        case "LEAVE":
            guard let w = queue.first(where:{ $0.plate == t[3] }) else { throw Fault.message(t[3]+" is not waiting") }
            queue.removeAll { $0.plate == w.plate }
            emit("LEAVE \(w.plate) \(types[w.kind])")
        case "EXIT", "PAY", "QUOTE":
            let v = try vehicle(t[3])
            let loss = t.count == 5
            try error(v.paidAt >= 0 && (command == "PAY" || loss),v.plate+" has already paid")
            let f = fees(v,loss)
            if command == "PAY" {
                v.paidAt = now
                v.paidParking = f[0]
                v.paidNight = f[1]
                emit("PAY \(v.plate) parking \(f[0]) night \(f[1]) charge \(f[3]) total \(f[4])")
            } else {
                emit(feeLine(command,v,f))
                if command == "EXIT" {
                    history[v.plate,default:[]].append(Visit(entry:v.entry,exit:now,location:v.location(),kind:v.kind,total:f[4],loss:loss))
                    stats[v.kind][1] += 1
                    stats[v.kind][3] += now-v.entry
                    for i in 0..<5 { stats[v.kind][i+4] += f[i] }
                    let d = daily(now/1440+1)
                    d.rows[v.kind][1] += 1
                    d.rows[v.kind][3] += f[4]
                    free(v)
                    parked.removeValue(forKey:v.plate)
                    trigger = true
                }
            }
        case "CHARGE":
            let v = try vehicle(t[3])
            try error(v.kind != 2,v.plate+" is not an electric car")
            try error(v.spots[0].kind != 3,v.plate+" is not at a charger")
            try error(v.paidAt >= 0,v.plate+" has already paid")
            let energy = Int(t[4])!
            try error(v.energy+energy > 100,"charge limit exceeded for "+v.plate)
            let cost = energy*kwh
            v.energy += energy
            v.charge += cost
            emit("CHARGE \(v.plate) kwh \(energy) cost \(cost) stay_kwh \(v.energy) stay_cost \(v.charge)")
        case "VALIDATE":
            let v = try vehicle(t[3])
            try error(v.paidAt >= 0,v.plate+" has already paid")
            let minutes = Int(t[4])!
            try error(v.validation+minutes > 180,"validation limit exceeded for "+v.plate)
            v.validation += minutes
            emit("VALIDATE \(v.plate) \(minutes) total \(v.validation)")
        case "PASS":
            let end = (hasPass(t[3]) ? passes[t[3]]! : now/1440)+Int(t[4])!
            passes[t[3]] = end
            emit("PASS \(t[3]) until \(end)")
        case "UNPASS":
            try error(!hasPass(t[3]),t[3]+" has no pass")
            passes.removeValue(forKey:t[3])
            emit("UNPASS "+t[3])
        case "MOVE":
            let v = try vehicle(t[3])
            try error(v.kind == 4,"bus \(v.plate) cannot be moved")
            let s = try spot(t[4])
            try error(v.spots[0] === s,"\(v.plate) is already at \(t[4])")
            try error(s.closed,"spot \(t[4]) is closed")
            try error(s.occupant != nil,"spot \(t[4]) is occupied by \(s.occupant?.plate ?? "")")
            try error(!prefs[v.kind].contains(s.kind),"\(types[v.kind]) cannot use \(kinds[s.kind]) spot \(t[4])")
            move(v,[s])
            trigger = true
        case "REBALANCE":
            var moved = 0
            for v in ordered() where v.kind != 4 {
                if let target = assign(v.kind), prefs[v.kind].firstIndex(of:target[0].kind)! < prefs[v.kind].firstIndex(of:v.spots[0].kind)! {
                    move(v,target)
                    moved += 1
                }
            }
            emit("REBALANCE \(moved)")
            trigger = true
        case "WHERE":
            let v = parked[t[3]]
            let p = queue.firstIndex { $0.plate == t[3] }
            let visits = history[t[3]]
            try error(v == nil && p == nil && visits == nil,"unknown plate "+t[3])
            if let v { emit("WHERE \(v.plate) \(v.location()) \(types[v.kind]) \(time(v.entry)) stay \(duration(now-v.entry))\(annotation(v))") }
            else if let p { emit("WHERE \(t[3]) waiting \(p+1)") }
            else { emit("WHERE \(t[3]) gone \(time(visits!.last!.exit))") }
        case "LIST":
            let l = t.count == 4 ? Int(t[3])! : 0
            try error(l > levels.count,"unknown level \(l)")
            let found = ordered().filter { l == 0 || $0.spots[0].level == l }
            emit("LIST \(found.count)")
            for v in found { emit("\(v.location()) \(v.plate) \(types[v.kind]) \(time(v.entry))\(annotation(v))") }
        case "MAP":
            emit("MAP \(levels.count)")
            for (i,level) in levels.enumerated() {
                let symbols = level.map { s -> Character in
                    if s.closed { return "#" }
                    let initial = kinds[s.kind].first!
                    return s.occupant != nil ? initial : Character(String(initial).lowercased())
                }
                var chunks: [String] = []
                for j in stride(from:0,to:symbols.count,by:10) { chunks.append(String(symbols[j..<min(j+10,symbols.count)])) }
                emit("L\(i+1) "+chunks.joined(separator:" "))
            }
        case "OCCUPANCY":
            emit("OCCUPANCY vehicles \(parked.count) waiting \(queue.count)")
            for (i,level) in levels.enumerated() { emit(occupancyLine("L\(i+1)",occupancy(level))) }
            let a = occupancy(spots)
            let used = a.prefix(4).reduce(0,+)
            let available = a[4..<8].reduce(0,+)
            emit(occupancyLine("TOTAL",a)+" rate \(tenths(available == 0 ? 0 : used*1000/available))%")
        case "SIGN":
            var line = "SIGN"
            for k in 0..<5 {
                var count = 0
                if k == 4 {
                    for level in levels {
                        var run = 0
                        for s in level {
                            if s.kind == 2 && s.free() {
                                run += 1
                                if run == 3 {
                                    count += 1
                                    run = 0
                                }
                            } else { run = 0 }
                        }
                    }
                } else {
                    for wanted in prefs[k] { count += spots.filter { $0.kind == wanted && $0.free() }.count }
                }
                line += " \(types[k]) "+(count == 0 ? "FULL" : String(count))
            }
            emit(line)
        case "RATES":
            emit("RATES")
            for k in 0..<5 { emit("\(types[k]) \(rates[k][0]) \(rates[k][1])") }
            emit("NIGHT \(night) LOST \(lost) KWH \(kwh)")
        case "PASSES":
            let found = passes.keys.filter { hasPass($0) }.sorted()
            emit("PASSES \(found.count)")
            for plate in found { emit("\(plate) until \(passes[plate]!)"+(parked[plate] != nil ? " IN" : "")) }
        case "OVERSTAY":
            let hours = Int(t[3])!
            let found = ordered().filter { now-$0.entry >= hours*60 }.sorted {
                $0.entry == $1.entry ? $0.spots[0].order < $1.spots[0].order : $0.entry < $1.entry
            }
            emit("OVERSTAY \(hours) \(found.count)")
            for v in found { emit("\(v.location()) \(v.plate) \(types[v.kind]) \(time(v.entry)) stay \(duration(now-v.entry))") }
        case "HISTORY":
            guard let visits = history[t[3]] else { throw Fault.message("no history for "+t[3]) }
            emit("HISTORY \(t[3]) visits \(visits.count) paid \(visits.reduce(0) { $0+$1.total })")
            for v in visits { emit("\(time(v.entry)) \(time(v.exit)) \(v.location) \(types[v.kind]) \(v.total)"+(v.loss ? " LOST" : "")) }
        case "REVENUE":
            emit("REVENUE")
            for k in 0..<5 { emit(revenueLine(types[k],stats[k])) }
            emit(revenueLine("TOTAL",sum(stats,9)))
        case "DAILY":
            let d = Int(t[3])!
            let a = daily(d).rows
            emit(dailyLine("DAILY \(d)",sum(a,4)))
            for k in 0..<5 { emit(dailyLine(types[k],a[k])) }
        case "STATS":
            emit("STATS parked \(parked.count) peak \(peak) at "+(peak == 0 ? "-" : time(peakAt)))
            for k in 0..<5 { emit(statsLine(types[k],stats[k])) }
            emit(statsLine("ALL",sum(stats,9)))
        default: break
        }
        if trigger { admit() }
    }
    func process(_ line: String) -> [String] {
        let t = line.split(separator:" ").map(String.init)
        let hm = t[1].split(separator:":")
        now = (Int(t[0])!-1)*1440+Int(hm[0])!*60+Int(hm[1])!
        output = []
        giveup()
        do { try execute(t) }
        catch Fault.message(let message) { emit("ERROR "+message) }
        catch { fatalError("Unexpected error") }
        return output
    }
}
let garage = Garage()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    for line in garage.process(readLine()!) { print(line) }
}
