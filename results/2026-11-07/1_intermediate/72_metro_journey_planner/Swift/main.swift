import Foundation
struct Problem: Error {
    let text: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(text: reason)
}
func time(_ s: String) -> Int {
    let p = s.components(separatedBy: ":")
    return Int(p[0])! * 60 + Int(p[1])!
}
func clock(_ t: Int) -> String {
    String(format: "%02d:%02d",t / 60,t % 60)
}
struct Segment: Hashable {
    let a: String, b: String
    init(_ x: String, _ y: String) {
        a = min(x,y)
        b = max(x,y)
    }
}
struct Station {
    let zone: Int, name: String
    var transfer = 0, closed = false
}
struct Line {
    let first: Int, last: Int, headway: Int, stops: [String], offsets: [Int]
    var delay = 0, suspended = false
    var total: Int {
        offsets.last!
    }
    var trips: Int {
        (last - first) / headway + 1
    }
    func direction(_ reverse: Bool) -> ([String],[Int]) {
        reverse ? (Array(stops.reversed()),offsets.reversed().map {
            total - $0
        }) : (stops,offsets)
    }
    func next(_ offset: Int, _ ready: Int) -> Int? {
        let delta = ready - first - delay - offset, q = delta <= 0 ? 0 : (delta + headway - 1) / headway
        return q < trips ? q : nil
    }
    func at(_ q: Int, _ offset: Int) -> Int {
        first + delay + q * headway + offset
    }
}
enum Leg {
    case ride(line: String, terminal: String, from: String, departure: Int, to: String, arrival: Int, stops: Int)
    case walk(from: String, departure: Int, to: String, arrival: Int)
    case stay(station: String, start: Int, end: Int)
    var end: Int {
        switch self {
            case .ride(_,_,_,_,_,let t,_), .walk(_,_,_,let t), .stay(_,_,let t): return t
        }
    }
    var isRide: Bool {
        if case .ride = self {
            return true
        }
        return false
    }
    var isWalk: Bool {
        if case .walk = self {
            return true
        }
        return false
    }
}
struct Label {
    let arrival: Int, journey: [Leg]
}
typealias Labels = [String: Label]
struct Tariff {
    let discount: Int, window: Int, prices: [Int]
}
@discardableResult func relax(_ labels: inout Labels, _ station: String, _ arrival: Int, _ journey: [Leg], _ leg: Leg) -> Bool {
    if let old = labels[station], old.arrival <= arrival {
        return false
    }
    labels[station] = Label(arrival: arrival,journey: journey + [leg])
    return true
}
func printJourney(_ heading: String, _ departure: Int, _ label: Label) -> [String] {
    var out = ["\(heading) \(clock(departure)) -> \(clock(label.arrival)) total \(label.arrival - departure) rides \(label.journey.filter(\.isRide).count) walks \(label.journey.filter(\.isWalk).count)"], previous = departure
    for leg in label.journey {
        switch leg {
            case .ride(let line,let terminal,let from,let d,let to,let a,let stops): out.append("RIDE \(line) toward \(terminal) \(from) \(clock(d)) -> \(to) \(clock(a)) wait \(d - previous) stops \(stops)")
            case .walk(let from,let d,let to,let a): out.append("WALK \(from) \(clock(d)) -> \(to) \(clock(a))")
            case .stay(let s,let start,let end): out.append("STAY \(s) \(clock(start)) -> \(clock(end))")
        }
        previous = leg.end
    }
    return out
}
final class Planner {
    var stations: [String: Station] = [:], lines: [String: Line] = [:], walks: [Segment: Int] = [:], closed = Set<Segment>(), tariff: Tariff? = nil
    func station(_ s: String) throws -> Station {
        guard let station = stations[s] else {
            try fail("unknown station " + s)
        }
        return station
    }
    func line(_ s: String) throws -> Line {
        guard let line = lines[s] else {
            try fail("unknown line " + s)
        }
        return line
    }
    func openStation(_ s: String) throws {
        if try station(s).closed {
            try fail("station \(s) is closed")
        }
    }
    func common(_ a: String, _ b: String) throws {
        _ = try station(a)
        _ = try station(b)
        if a == b {
            try fail("origin and destination are the same")
        }
        try openStation(a)
        try openStation(b)
    }
    func neighbors(_ s: String) -> [(String,Int)] {
        walks.compactMap {
            key,t -> (String,Int)? in key.a == s ? (key.b,t) : (key.b == s ? (key.a,t) : nil)
        }.sorted {
            $0.0 < $1.0
        }
    }
    func earliest(_ origin: String, _ departure: Int) -> Labels {
        var labels = [origin: Label(arrival: departure,journey: [])], settled = Set<String>()
        while let entry = labels.filter({
            !settled.contains($0.key)
        }).min(by: {
            a,b in a.value.arrival == b.value.arrival ? a.key < b.key : a.value.arrival < b.value.arrival
        }) {
            let u = entry.key, label = entry.value, ready = label.arrival + (u == origin ? 0 : stations[u]!.transfer)
            settled.insert(u)
            for id in lines.keys.sorted() {
                let line = lines[id]!
                if line.suspended || !line.stops.contains(u) {
                    continue
                }
                for reverse in [false,true] {
                    let (stops,offsets) = line.direction(reverse), i = stops.firstIndex(of: u)!
                    if i + 1 == stops.count {
                        continue
                    }
                    guard let q = line.next(offsets[i],ready) else {
                        continue
                    }
                    let d = line.at(q,offsets[i])
                    for j in (i + 1)..<stops.count {
                        if closed.contains(Segment(stops[j - 1],stops[j])) {
                            break
                        }
                        if stations[stops[j]]!.closed {
                            continue
                        }
                        let t = line.at(q,offsets[j])
                        relax(&labels,stops[j],t,label.journey,.ride(line: id,terminal: stops.last!,from: u,departure: d,to: stops[j],arrival: t,stops: j - i))
                    }
                }
            }
            for (v,w) in neighbors(u) {
                let t = label.arrival + w
                if !stations[v]!.closed && t <= 1440 {
                    relax(&labels,v,t,label.journey,.walk(from: u,departure: label.arrival,to: v,arrival: t))
                }
            }
        }
        return labels
    }
    func walkStep(_ labels: inout Labels, _ sources: Set<String>, _ changed: inout Set<String>) {
        let recorded = sources.sorted().map {
            ($0,labels[$0]!)
        }
        for (u,label) in recorded {
            for (v,w) in neighbors(u) {
                let t = label.arrival + w
                if !stations[v]!.closed && t <= 1440 && relax(&labels,v,t,label.journey,.walk(from: u,departure: label.arrival,to: v,arrival: t)) {
                    changed.insert(v)
                }
            }
        }
    }
    func rounds(_ origin: String, _ departure: Int) -> [Labels] {
        struct Boarded {
            let q: Int, index: Int, departure: Int, journey: [Leg]
        }
        var labels = [origin: Label(arrival: departure,journey: [])], changed: Set<String> = [origin]
        walkStep(&labels,[origin],&changed)
        var result = [labels]
        while !changed.isEmpty {
            let previous = labels, marked = changed
            changed = []
            var sources = Set<String>()
            for id in lines.keys.sorted() {
                let line = lines[id]!
                if line.suspended {
                    continue
                }
                for reverse in [false,true] {
                    let (stops,offsets) = line.direction(reverse)
                    var boarded: Boarded? = nil
                    for j in stops.indices {
                        if j > 0 && closed.contains(Segment(stops[j - 1],stops[j])) {
                            boarded = nil
                        }
                        if stations[stops[j]]!.closed {
                            continue
                        }
                        if let b = boarded {
                            let t = line.at(b.q,offsets[j])
                            if relax(&labels,stops[j],t,b.journey,.ride(line: id,terminal: stops.last!,from: stops[b.index],departure: b.departure,to: stops[j],arrival: t,stops: j - b.index)) {
                                sources.insert(stops[j])
                                changed.insert(stops[j])
                            }
                        }
                        if j + 1 < stops.count && marked.contains(stops[j]) {
                            let old = previous[stops[j]]!, ready = old.arrival + (stops[j] == origin ? 0 : stations[stops[j]]!.transfer)
                            if let q = line.next(offsets[j],ready), boarded == nil || q < boarded!.q {
                                boarded = Boarded(q: q,index: j,departure: line.at(q,offsets[j]),journey: old.journey)
                            }
                        }
                    }
                }
            }
            walkStep(&labels,sources,&changed)
            result.append(labels)
        }
        return result
    }
    func fare(_ journey: [Leg], _ child: Bool) -> (Int,[String]) {
        let tariff = tariff!
        func half(_ n: Int) -> Int {
            (n + 19) / 20 * 10
        }
        let cap = child ? half(tariff.discount) : tariff.discount
        var previous: Int? = nil, total = 0, tickets: [String] = []
        for leg in journey {
            if case .ride(let id,_,let from,let departure,let to,let arrival,_) = leg {
                let stops = lines[id]!.stops, a = stops.firstIndex(of: from)!, b = stops.firstIndex(of: to)!, zones = Set(stops[min(a,b)...max(a,b)].map {
                    stations[$0]!.zone
                }).count
                var price = tariff.prices[min(zones,tariff.prices.count) - 1]
                if child {
                    price = half(price)
                }
                let reduction = previous.map {
                    departure - $0 <= tariff.window
                } == true ? min(cap,price) : 0, pay = price - reduction
                total += pay
                previous = arrival
                tickets.append("TICKET \(id) \(from) \(to) zones \(zones) price \(price) discount \(reduction) pay \(pay)")
            }
        }
        return (total,tickets)
    }
    func command(_ w: [String]) throws -> [String] {
        let c = w[0], a = Array(w.dropFirst())
        func num(_ i: Int) -> Int {
            Int(a[i])!
        }
        var out: [String] = []
        switch c {
            case "STATION":
            if stations[a[0]] != nil {
                try fail("station \(a[0]) already exists")
            }
            stations[a[0]] = Station(zone: num(1),name: a[2])
            out.append("STATION \(a[0]) zone \(num(1)) \(a[2])")
            case "LINE":
            if lines[a[0]] != nil {
                try fail("line \(a[0]) already exists")
            }
            let stops = stride(from: 4,to: a.count,by: 2).map {
                a[$0]
            }
            for s in stops {
                _ = try station(s)
            }
            var seen = Set<String>()
            for s in stops {
                if !seen.insert(s).inserted {
                    try fail("station \(s) appears twice on line \(a[0])")
                }
            }
            let first = time(a[1]), last = time(a[2])
            var offsets = [0]
            for i in stride(from: 5,to: a.count,by: 2) {
                offsets.append(offsets.last! + num(i))
            }
            if first > last {
                try fail("line \(a[0]) first departure is after last departure")
            }
            if last + offsets.last! > 1440 {
                try fail("line \(a[0]) runs past 24:00")
            }
            let line = Line(first: first,last: last,headway: num(3),stops: stops,offsets: offsets)
            lines[a[0]] = line
            out.append("LINE \(a[0]) stops \(stops.count) time \(line.total) trips \(line.trips)")
            case "TRANSFER": _ = try station(a[0])
            stations[a[0]]!.transfer = num(1)
            out.append("TRANSFER \(a[0]) \(num(1))")
            case "WALK":
            _ = try station(a[0])
            _ = try station(a[1])
            if a[0] == a[1] {
                try fail("walk from \(a[0]) to itself")
            }
            let old = walks.updateValue(num(2),forKey: Segment(a[0],a[1]))
            out.append("WALK \(a[0]) \(a[1]) \(num(2))" + (old.map {
                " was \($0)"
            } ?? ""))
            case "TARIFF":
            let prices = (2..<a.count).map(num)
            if zip(prices,prices.dropFirst()).contains(where: {
                $0.0 > $0.1
            }) {
                try fail("tariff prices must not decrease")
            }
            tariff = Tariff(discount: num(0),window: num(1),prices: prices)
            out.append("TARIFF zones \(prices.count) discount \(num(0)) window \(num(1))")
            case "CLOSE","OPEN":
            _ = try station(a[0])
            let close = c == "CLOSE"
            if a.count == 1 {
                if stations[a[0]]!.closed == close {
                    try fail("station \(a[0]) is \(close ? "already" : "not") closed")
                }
                stations[a[0]]!.closed = close
                out.append(c + " " + a[0])
            }
            else {
                _ = try station(a[1])
                let key = Segment(a[0],a[1]), ids = lines.keys.sorted().filter {
                    id in let stops = lines[id]!.stops
                    return zip(stops,stops.dropFirst()).contains {
                        Segment($0.0,$0.1) == key
                    }
                }
                if close && ids.isEmpty {
                    try fail("no segment \(a[0])-\(a[1])")
                }
                if closed.contains(key) == close {
                    try fail("segment \(a[0])-\(a[1]) is \(close ? "already" : "not") closed")
                }
                if close {
                    closed.insert(key)
                } else {
                    closed.remove(key)
                }
                out.append("\(c) \(a[0])-\(a[1])" + (close ? " lines " + ids.joined(separator: " ") : ""))
            }
            case "DELAY":
            let line = try line(a[0])
            if line.last + num(1) + line.total > 1440 {
                try fail("line \(a[0]) runs past 24:00")
            }
            lines[a[0]]!.delay = num(1)
            out.append("DELAY \(a[0]) \(num(1))")
            case "SUSPEND","RESUME":
            let line = try line(a[0]), suspended = c == "SUSPEND"
            if line.suspended == suspended {
                try fail("line \(a[0]) is \(suspended ? "already" : "not") suspended")
            }
            lines[a[0]]!.suspended = suspended
            out.append(c + " " + a[0])
            case "ROUTE","FEWEST","PARETO","FARE","LASTTRAIN","ARRIVEBY","PROFILE":
            try common(a[0],a[1])
            if c == "FARE" {
                if !["ADULT","CHILD"].contains(a[3]) {
                    try fail("unknown fare class " + a[3])
                }
                if tariff == nil {
                    try fail("no tariff")
                }
            }
            if c == "PROFILE" && time(a[2]) > time(a[3]) {
                try fail("empty interval \(a[2]) \(a[3])")
            }
            let heading = "\(c) \(a[0]) \(a[1])"
            if c == "LASTTRAIN" || c == "ARRIVEBY" {
                let bound = c == "LASTTRAIN" ? 1440 : time(a[2]), title = c == "ARRIVEBY" ? heading + " by " + a[2] : heading
                if bound > 0 {
                    for t in stride(from: bound - 1,through: 0,by: -1) {
                        if let label = earliest(a[0],t)[a[1]], c == "LASTTRAIN" || label.arrival <= bound {
                            return printJourney(title,t,label)
                        }
                    }
                }
                out.append(title + " none")
            } else if c == "PROFILE" {
                let start = time(a[2]), end = time(a[3]), arrivals = (start...end).map {
                    earliest(a[0],$0)[a[1]]?.arrival
                }
                var selected: [String] = []
                for i in arrivals.indices {
                    if let arrival = arrivals[i], i + 1 == arrivals.count || arrivals[i + 1] == nil || arrival < arrivals[i + 1]! {
                        selected.append("\(clock(start + i)) -> \(clock(arrival)) total \(arrival - start - i)")
                    }
                }
                out.append("\(heading) \(a[2]) \(a[3]) count \(selected.count)")
                out += selected
            } else if c == "FEWEST" || c == "PARETO" {
                let start = time(a[2]), rounds = rounds(a[0],start)
                if c == "FEWEST" {
                    for (k,labels) in rounds.enumerated() {
                        if let label = labels[a[1]] {
                            return printJourney("\(heading) trips \(k)",start,label)
                        }
                    }
                    out.append("\(heading) \(a[2]) unreachable")
                }
                else {
                    var options: [String] = [], previous: Int? = nil, count = 0
                    for (k,labels) in rounds.enumerated() {
                        if let label = labels[a[1]] {
                            if previous == nil || previous! > label.arrival {
                                count += 1
                                options += printJourney("OPTION trips \(k)",start,label)
                            }
                            previous = label.arrival
                        }
                    }
                    out.append("\(heading) \(a[2]) options \(count)")
                    out += options
                }
            } else {
                let start = time(a[2])
                if let label = earliest(a[0],start)[a[1]] {
                    if c == "FARE" {
                        let (total,tickets) = fare(label.journey,a[3] == "CHILD")
                        out.append("\(heading) \(a[2]) \(a[3]) rides \(label.journey.filter(\.isRide).count) total \(total)")
                        out += tickets
                    }
                    else {
                        return printJourney(heading,start,label)
                    }
                } else {
                    out.append("\(heading) \(a[2])" + (c == "FARE" ? " " + a[3] : "") + " unreachable")
                }
            }
            case "VIA":
            _ = try station(a[0])
            _ = try station(a[1])
            _ = try station(a[2])
            if a[0] == a[2] {
                try fail("origin and destination are the same")
            }
            if a[1] == a[0] || a[1] == a[2] {
                try fail("via station \(a[1]) must differ from origin and destination")
            }
            try openStation(a[0])
            try openStation(a[1])
            try openStation(a[2])
            let start = time(a[3]), heading = "VIA \(a[0]) \(a[1]) \(a[2])"
            if let first = earliest(a[0],start)[a[1]] {
                let next = first.arrival + stations[a[1]]!.transfer
                if let second = earliest(a[1],next)[a[2]] {
                    return printJourney(heading,start,Label(arrival: second.arrival,journey: first.journey + [.stay(station: a[1],start: first.arrival,end: next)] + second.journey))
                }
            }
            out.append("\(heading) \(a[3]) unreachable")
            case "REACH":
            try openStation(a[0])
            let start = time(a[1]), selected = earliest(a[0],start).filter {
                $0.value.arrival <= start + num(2)
            }.sorted {
                a,b in a.value.arrival == b.value.arrival ? a.key < b.key : a.value.arrival < b.value.arrival
            }
            out.append("REACH \(a[0]) \(a[1]) \(num(2)) count \(selected.count)")
            for (s,label) in selected {
                out.append("\(s) \(stations[s]!.name) \(clock(label.arrival)) \(label.arrival - start) rides \(label.journey.filter(\.isRide).count)")
            }
            case "TIMETABLE":
            _ = try station(a[0])
            let line = try line(a[1])
            if !line.stops.contains(a[0]) {
                try fail("station \(a[0]) is not on line \(a[1])")
            }
            if a[2] != line.stops.first! && a[2] != line.stops.last! {
                try fail("\(a[2]) is not a terminal of line \(a[1])")
            }
            if a[0] == a[2] {
                try fail("no departures from \(a[0]) toward \(a[2])")
            }
            if line.suspended {
                try fail("line \(a[1]) is suspended")
            }
            try openStation(a[0])
            let (stops,offsets) = line.direction(a[2] == line.stops.first!), i = stops.firstIndex(of: a[0])!, selected = (0..<line.trips).map {
                line.at($0,offsets[i])
            }.filter {
                $0 >= time(a[3])
            }.prefix(num(4))
            out.append("TIMETABLE \(a[0]) \(a[1]) toward \(a[2]) \(a[3]) next \(selected.count)" + selected.map {
                " " + clock($0)
            }.joined())
            case "DEPARTURES","ARRIVALS":
            struct Event {
                let time: Int, line: String, direction: Int, endpoint: String
            }
            try openStation(a[0])
            var events: [Event] = []
            for id in lines.keys.sorted() {
                let line = lines[id]!
                if line.suspended || !line.stops.contains(a[0]) {
                    continue
                }
                for direction in 0...1 {
                    let (stops,offsets) = line.direction(direction == 1), i = stops.firstIndex(of: a[0])!
                    if (c == "DEPARTURES" && i + 1 == stops.count) || (c == "ARRIVALS" && i == 0) {
                        continue
                    }
                    for q in 0..<line.trips {
                        let t = line.at(q,offsets[i])
                        if t >= time(a[1]) {
                            events.append(Event(time: t,line: id,direction: direction,endpoint: c == "DEPARTURES" ? stops.last! : stops.first!))
                        }
                    }
                }
            }
            let selected = events.sorted {
                a,b in a.time != b.time ? a.time < b.time : (a.line != b.line ? a.line < b.line : a.direction < b.direction)
            }.prefix(num(2))
            out.append("\(c) \(a[0]) \(a[1]) count \(selected.count)")
            for e in selected {
                out.append("\(clock(e.time)) \(e.line) \(c == "DEPARTURES" ? "toward" : "from") \(e.endpoint)")
            }
            case "TRIP":
            let line = try line(a[0])
            if a[1] != line.stops.first! && a[1] != line.stops.last! {
                try fail("\(a[1]) is not a terminal of line \(a[0])")
            }
            if line.suspended {
                try fail("line \(a[0]) is suspended")
            }
            let (stops,offsets) = line.direction(a[1] == line.stops.first!), heading = "TRIP \(a[0]) toward \(a[1]) \(a[2])"
            if let q = line.next(0,time(a[2])) {
                out.append("\(heading) trip \(q + 1) departs \(clock(line.at(q,0)))")
                for j in stops.indices {
                    out.append("\(clock(line.at(q,offsets[j]))) \(stops[j])" + (stations[stops[j]]!.closed ? " closed" : "") + (j > 0 && closed.contains(Segment(stops[j - 1],stops[j])) ? " blocked" : ""))
                }
            }
            else {
                out.append(heading + " none")
            }
            case "SHOWLINE":
            let line = try line(a[0])
            out.append("SHOWLINE \(a[0]) \(line.suspended ? "suspended" : "running") first \(clock(line.first)) last \(clock(line.last)) headway \(line.headway) delay \(line.delay) trips \(line.trips)")
            for j in line.stops.indices {
                let s = line.stops[j]
                out.append("\(line.offsets[j]) \(s) zone \(stations[s]!.zone)" + (stations[s]!.closed ? " closed" : "") + (j > 0 && closed.contains(Segment(line.stops[j - 1],s)) ? " blocked" : ""))
            }
            case "INFO":
            let s = try station(a[0]), ids = lines.keys.sorted().filter {
                lines[$0]!.stops.contains(a[0])
            }, links = neighbors(a[0])
            out = ["INFO \(a[0]) \(s.name) zone \(s.zone) transfer \(s.transfer) \(s.closed ? "closed" : "open")","LINES " + (ids.isEmpty ? "none" : ids.joined(separator: " ")),"WALKS " + (links.isEmpty ? "none" : links.map {
                "\($0.0) \($0.1)"
            }.joined(separator: " "))]
            case "STATUS":
            out.append("STATUS stations \(stations.count) lines \(lines.count) walks \(walks.count)")
            for s in stations.keys.sorted() where stations[s]!.closed {
                out.append("CLOSED " + s)
            }
            for segment in closed.sorted(by: {
                $0.a == $1.a ? $0.b < $1.b : $0.a < $1.a
            }) {
                out.append("CLOSED \(segment.a)-\(segment.b)")
            }
            for id in lines.keys.sorted() where lines[id]!.suspended {
                out.append("SUSPENDED " + id)
            }
            for id in lines.keys.sorted() where lines[id]!.delay != 0 {
                out.append("DELAYED \(id) \(lines[id]!.delay)")
            }
            default: fatalError("unknown command")
        }
        return out
    }
}
let planner = Planner()
for _ in 0..<Int(readLine()!)! {
    do {
        for line in try planner.command(readLine()!.components(separatedBy: " ")) {
            print(line)
        }
    }
    catch let p as Problem {
        print("ERROR " + p.text)
    }
    catch {
        fatalError("unexpected error")
    }
}
