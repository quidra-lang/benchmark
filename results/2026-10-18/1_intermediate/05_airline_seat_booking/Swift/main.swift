import Foundation

let classes = ["F","J","Y"]
struct Seat {
    let id: String
    let row: Int
    let letter: Character
    let block: Int
    let cabin: String
    let kind: String
}
final class Cabin {
    let name: String
    let first: Int
    let last: Int
    let blocks: [String]
    var seats: [Seat] = []
    init(_ name: String, _ first: Int, _ last: Int, _ blocks: [String]) {
        self.name = name
        self.first = first
        self.last = last
        self.blocks = blocks
    }
}
final class Aircraft {
    let model: String
    let base: Int
    let limit: Int
    var cabins: [String:Cabin] = [:]
    var seats: [String:Seat] = [:]
    var exits: Set<Int> = []
    var blocked: Set<String> = []
    init(_ model: String, _ base: Int, _ limit: Int) {
        self.model = model
        self.base = base
        self.limit = limit
    }
}
final class Flight {
    let name: String
    let aircraft: Aircraft
    var closed = false
    var limits: [String:Int] = [:]
    var blocked: Set<String>
    var occupied: [String:Passenger] = [:]
    var bookings: [Booking] = []
    var volunteers: [Passenger] = []
    init(_ name: String, _ aircraft: Aircraft) {
        self.name = name
        self.aircraft = aircraft
        blocked = aircraft.blocked
    }
}
final class Booking {
    let pnr: String
    unowned let flight: Flight
    var checked = false
    var passengers: [Passenger] = []
    init(_ pnr: String, _ flight: Flight) {
        self.pnr = pnr
        self.flight = flight
    }
}
final class Passenger: Hashable {
    let name: String
    let type: String
    let pref: String?
    var cabin: String
    unowned let booking: Booking
    var order = 0
    var lap: Passenger?
    weak var parent: Passenger?
    var seat: Seat?
    var needsSeat: Bool { type != "INFANT" }
    var result: String { !needsSeat ? "LAP" : (seat?.id ?? "UNASSIGNED") }
    init(_ name: String, _ type: String, _ pref: String?, _ cabin: String, _ booking: Booking) {
        self.name = name
        self.type = type
        self.pref = pref
        self.cabin = cabin
        self.booking = booking
    }
    static func == (a: Passenger, b: Passenger) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
struct Problem: Error { let message: String }

final class Airline {
    var aircraft: [String:Aircraft] = [:]
    var flights: [String:Flight] = [:]
    var flightOrder: [Flight] = []
    var bookings: [String:Booking] = [:]
    var used: Set<String> = []
    var tiers: [String:String] = [:]
    var defining: Aircraft!
    var nextOrder = 0
    func fail(_ message: String) -> Problem { Problem(message: message) }
    func tier(_ p: Passenger) -> String { tiers[p.name] ?? "NONE" }
    func tierRank(_ p: Passenger) -> Int { ["PLATINUM","GOLD","SILVER","NONE"].firstIndex(of: tier(p))! }
    func flight(_ name: String, _ open: Bool) throws -> Flight {
        guard let f = flights[name] else { throw fail("unknown flight "+name) }
        if open && f.closed { throw fail("flight "+name+" is closed") }
        return f
    }
    func booking(_ pnr: String, _ open: Bool) throws -> Booking {
        guard let b = bookings[pnr], !b.passengers.isEmpty else { throw fail("unknown PNR "+pnr) }
        if open && b.flight.closed { throw fail("flight "+b.flight.name+" is closed") }
        return b
    }
    func passenger(_ b: Booking, _ name: String) throws -> Passenger {
        guard let p = b.passengers.first(where: { $0.name == name }) else { throw fail("no passenger "+name+" in "+b.pnr) }
        return p
    }
    func passengers(_ f: Flight) -> [Passenger] { f.bookings.flatMap { $0.passengers } }
    func booked(_ f: Flight, _ cabin: String) -> Int { passengers(f).filter { $0.needsSeat && $0.cabin == cabin }.count }
    func seats(_ a: Aircraft, _ cabin: String, _ blocked: Set<String>) -> Int { a.cabins[cabin]!.seats.filter { !blocked.contains($0.id) }.count }
    func requireCabin(_ f: Flight, _ cabin: String) throws {
        guard f.aircraft.cabins[cabin] != nil else { throw fail("no cabin "+cabin+" on "+f.name) }
    }
    func sameBlock(_ a: Seat, _ b: Seat) -> Bool { a.row == b.row && a.block == b.block }
    func exitAllowed(_ p: Passenger, _ s: Seat) -> Bool {
        !p.booking.flight.aircraft.exits.contains(s.row) || (p.type != "CHILD" && p.lap == nil)
    }
    func infantAllowed(_ p: Passenger, _ s: Seat, _ vacated: Set<Passenger>, _ proposed: [Passenger:Seat]) -> Bool {
        if p.lap == nil { return true }
        let f = p.booking.flight
        for letter in f.aircraft.cabins[s.cabin]!.blocks[s.block] {
            if let q = f.occupied[String(s.row)+String(letter)], q !== p && q.lap != nil && !vacated.contains(q) { return false }
        }
        for (q,target) in proposed {
            if q !== p && q.lap != nil && sameBlock(target,s) { return false }
        }
        return true
    }
    func fits(_ p: Passenger, _ s: Seat, _ vacated: Set<Passenger> = [], _ proposed: [Passenger:Seat] = [:]) -> Bool {
        let f = p.booking.flight
        let occupant = f.occupied[s.id]
        return !f.blocked.contains(s.id) && (occupant == nil || vacated.contains(occupant!)) &&
            exitAllowed(p,s) && infantAllowed(p,s,vacated,proposed)
    }
    func seat(_ p: Passenger, _ target: Seat?) {
        let f = p.booking.flight
        if let old = p.seat { f.occupied.removeValue(forKey: old.id) }
        p.seat = target
        if let target { f.occupied[target.id] = p }
    }
    func select(_ p: Passenger, _ cabin: String) -> Seat? {
        var first: Seat? = nil
        for s in p.booking.flight.aircraft.cabins[cabin]!.seats {
            if !fits(p,s) { continue }
            if first == nil { first = s }
            if p.pref == s.kind { return s }
        }
        return first
    }
    func reassign(_ f: Flight, _ output: inout [String]) {
        for p in passengers(f) where p.needsSeat && p.seat == nil {
            if let target = select(p,p.cabin) {
                seat(p,target)
                output.append("REASSIGNED \(p.booking.pnr) \(p.name) \(target.id)")
            }
        }
    }
    func candidate(_ people: [Passenger], _ positions: [Seat]) -> Bool {
        let proposed = Dictionary(uniqueKeysWithValues: zip(people,positions))
        for p in people {
            if !fits(p,proposed[p]!,[],proposed) { return false }
        }
        for p in people { seat(p,proposed[p]!) }
        return true
    }
    func assign(_ b: Booking, _ cabinName: String) -> String {
        let people = b.passengers.filter { $0.needsSeat }
        if people.count == 1 {
            seat(people[0],select(people[0],cabinName))
            return "SINGLE"
        }
        let cabin = b.flight.aircraft.cabins[cabinName]!
        let a = b.flight.aircraft
        let k = people.count
        for stage in 1...3 {
            let lastH = stage == 3 ? k : 2
            for h in 2...lastH {
                let width = (k+h-1)/h
                for row in cabin.first...cabin.last {
                    let blocks = stage == 2 ? [cabin.blocks.joined()] : cabin.blocks
                    for block in blocks {
                        let letters = Array(block)
                        let span = stage == 3 ? width : k
                        if span > letters.count { continue }
                        for x in 0...(letters.count-span) {
                            var positions: [Seat] = []
                            for j in 0..<k {
                                let r = row+(stage == 3 ? j/width : 0)
                                if r > cabin.last { break }
                                let letter = letters[x+(stage == 3 ? j%width : j)]
                                positions.append(a.seats[String(r)+String(letter)]!)
                            }
                            if positions.count == k && candidate(people,positions) { return stage == 1 ? "BLOCK" : (stage == 2 ? "ROW" : "STACK") }
                        }
                    }
                }
            }
        }
        for p in people { seat(p,select(p,cabinName)) }
        return "SPLIT"
    }
    func targets(_ p: Passenger) -> [Passenger] { p.lap.map { [p,$0] } ?? [p] }
    func remove(_ targets: [Passenger]) {
        for p in targets {
            seat(p,nil)
            p.booking.flight.volunteers.removeAll { $0 === p }
            p.booking.passengers.removeAll { $0 === p }
            p.parent?.lap = nil
        }
    }
    func seatBefore(_ a: Passenger, _ b: Passenger) -> Bool {
        a.seat!.row == b.seat!.row ? a.seat!.letter < b.seat!.letter : a.seat!.row < b.seat!.row
    }
    func load(_ seated: Int, _ count: Int) -> String {
        let q = seated*1000/count
        return "\(q/10).\(q%10)%"
    }
    func boardingRank(_ p: Passenger) -> Int {
        if p.booking.passengers.contains(where: { !$0.needsSeat }) { return 0 }
        if p.cabin != "Y" { return 1 }
        return tierRank(p) <= 1 ? 2 : 3
    }
    func zone(_ p: Passenger) -> Int { (p.seat!.row-p.booking.flight.aircraft.cabins["Y"]!.first)/5+1 }
    func execute(_ line: String) throws -> [String] {
        let t = line.split(separator: " ").map(String.init)
        let command = t[0]
        var output: [String] = []
        switch command {
        case "AIRCRAFT": defining = Aircraft(t[1],Int(t[2])!,Int(t[3])!)
        case "CABIN":
            let c = Cabin(t[1],Int(t[2])!,Int(t[3])!,Array(t.dropFirst(4)))
            for row in c.first...c.last {
                for (block,string) in c.blocks.enumerated() {
                    let letters = Array(string)
                    for (i,letter) in letters.enumerated() {
                        let window = (block == 0 && i == 0) || (block == c.blocks.count-1 && i == letters.count-1)
                        let kind = window ? "W" : ((i == 0 || i == letters.count-1) ? "A" : "M")
                        let s = Seat(id: String(row)+String(letter),row: row,letter: letter,block: block,cabin: c.name,kind: kind)
                        c.seats.append(s)
                        defining.seats[s.id] = s
                    }
                }
            }
            defining.cabins[c.name] = c
        case "EXIT":
            for value in t.dropFirst() { defining.exits.insert(Int(value)!) }
        case "BLOCKED": defining.blocked.formUnion(t.dropFirst())
        case "END":
            aircraft[defining.model] = defining
            let counts = classes.filter { defining.cabins[$0] != nil }.map { " \($0) \(seats(defining,$0,defining.blocked))" }.joined()
            output.append("AIRCRAFT "+defining.model+counts)
        case "FLIGHT":
            guard flights[t[1]] == nil else { throw fail("duplicate flight "+t[1]) }
            guard let a = aircraft[t[2]] else { throw fail("unknown aircraft "+t[2]) }
            let f = Flight(t[1],a)
            var result = "FLIGHT "+f.name+" "+a.model
            for c in classes where a.cabins[c] != nil {
                let count = seats(a,c,a.blocked)
                let limit = count*(100+Int(t[3])!)/100
                f.limits[c] = limit
                result += " \(c) \(count)/\(limit)"
            }
            flights[f.name] = f
            flightOrder.append(f)
            output.append(result)
        case "BOOK":
            guard !used.contains(t[1]) else { throw fail("duplicate PNR "+t[1]) }
            let f = try flight(t[2],true)
            try requireCabin(f,t[3])
            let b = Booking(t[1],f)
            var seen: Set<String> = []
            var adults: [Passenger] = []
            var infants: [Passenger] = []
            for token in t.dropFirst(4) {
                let parts = token.split(separator: ":").map(String.init)
                guard seen.insert(parts[0]).inserted else { throw fail("duplicate name "+parts[0]+" in "+b.pnr) }
                let p = Passenger(parts[0],parts[1],parts.count == 3 ? parts[2] : nil,t[3],b)
                b.passengers.append(p)
                if p.type == "ADULT" { adults.append(p) }
                if p.type == "INFANT" { infants.append(p) }
            }
            let present = Set(passengers(f).map { $0.name })
            for p in b.passengers {
                if present.contains(p.name) { throw fail(p.name+" already on "+f.name) }
            }
            guard !adults.isEmpty else { throw fail("no adult in "+b.pnr) }
            guard infants.count <= adults.count else { throw fail("too many infants in "+b.pnr) }
            guard booked(f,t[3])+b.passengers.filter({ $0.needsSeat }).count <= f.limits[t[3]]! else {
                throw fail("limit exceeded for "+f.name+" "+t[3])
            }
            for i in infants.indices {
                adults[i].lap = infants[i]
                infants[i].parent = adults[i]
            }
            for p in b.passengers {
                p.order = nextOrder
                nextOrder += 1
            }
            let method = assign(b,t[3])
            f.bookings.append(b)
            bookings[b.pnr] = b
            used.insert(b.pnr)
            output.append("BOOKED \(b.pnr) \(f.name) \(t[3]) \(method) "+b.passengers.map { $0.name+":"+$0.result }.joined(separator: " "))
        case "SEAT":
            let b = try booking(t[1],true)
            let p = try passenger(b,t[2])
            guard p.needsSeat else { throw fail("infant "+p.name+" has no seat") }
            guard let target = b.flight.aircraft.seats[t[3]], target.cabin == p.cabin else { throw fail("no seat "+t[3]+" in cabin "+p.cabin) }
            guard !b.flight.blocked.contains(t[3]) else { throw fail("seat "+t[3]+" is blocked") }
            guard b.flight.occupied[t[3]] == nil else { throw fail("seat "+t[3]+" is occupied") }
            guard exitAllowed(p,target) else { throw fail("exit row \(target.row) not allowed for "+p.name) }
            guard infantAllowed(p,target,[],[:]) else { throw fail("infant limit reached at "+t[3]) }
            let old = p.result
            seat(p,target)
            output.append("MOVED \(b.pnr) \(p.name) \(old) -> \(t[3])")
            reassign(b.flight,&output)
        case "SWAP":
            let a = try booking(t[1],true)
            let p = try passenger(a,t[2])
            let b = try booking(t[3],true)
            let q = try passenger(b,t[4])
            guard p !== q else { throw fail("cannot swap "+p.name+" with itself") }
            for x in [p,q] {
                guard x.needsSeat else { throw fail("infant "+x.name+" has no seat") }
            }
            guard a.flight === b.flight else { throw fail(a.pnr+" and "+b.pnr+" are on different flights") }
            guard p.cabin == q.cabin else { throw fail(p.name+" and "+q.name+" are in different cabins") }
            for x in [p,q] {
                guard x.seat != nil else { throw fail(x.name+" has no seat") }
            }
            let ps = p.seat!
            let qs = q.seat!
            let vacated: Set<Passenger> = [p,q]
            let proposed = [p:qs,q:ps]
            guard fits(p,qs,vacated,proposed) && fits(q,ps,vacated,proposed) else {
                throw fail("swap of "+p.name+" and "+q.name+" breaks seating rules")
            }
            seat(p,nil)
            seat(q,nil)
            seat(p,qs)
            seat(q,ps)
            output.append("SWAPPED \(a.pnr) \(p.name) \(p.result) \(b.pnr) \(q.name) \(q.result)")
            reassign(a.flight,&output)
        case "CANCEL":
            let b = try booking(t[1],true)
            let selected: [Passenger]
            if t.count == 2 { selected = b.passengers }
            else {
                let p = try passenger(b,t[2])
                let removing = targets(p)
                let remaining = b.passengers.filter { !removing.contains($0) }
                guard remaining.isEmpty || remaining.contains(where: { $0.type == "ADULT" }) else { throw fail(b.pnr+" would have no adult") }
                selected = b.passengers.filter { removing.contains($0) }
            }
            let names = selected.map { $0.name }.joined(separator: " ")
            remove(selected)
            output.append("CANCELLED "+b.pnr+" "+names)
            reassign(b.flight,&output)
        case "STATUS":
            tiers[t[1]] = t[2]
            output.append("STATUS "+t[1]+" "+t[2])
        case "CHECKIN":
            let b = try booking(t[1],true)
            guard !b.checked else { throw fail(b.pnr+" already checked in") }
            b.checked = true
            output.append("CHECKIN \(b.pnr) \(b.passengers.count)")
        case "VOLUNTEER":
            let b = try booking(t[1],true)
            let p = try passenger(b,t[2])
            guard p.type == "ADULT" && p.lap == nil else { throw fail(p.name+" cannot volunteer") }
            guard p.seat != nil else { throw fail(p.name+" has no seat") }
            guard !b.flight.volunteers.contains(p) else { throw fail(p.name+" already volunteered") }
            b.flight.volunteers.append(p)
            output.append("VOLUNTEER \(b.pnr) \(p.name) \(p.result)")
        case "UPGRADE":
            let f = try flight(t[1],true)
            let cabins = classes.filter { f.aircraft.cabins[$0] != nil }
            var count = 0
            if cabins.count > 1 {
                for i in 0..<(cabins.count-1) {
                    let higher = cabins[i]
                    let lower = cabins[i+1]
                    let targets = passengers(f).filter { $0.cabin == lower && $0.type == "ADULT" && $0.lap == nil && tier($0) != "NONE" }.sorted {
                        tierRank($0) == tierRank($1) ? $0.order < $1.order : tierRank($0) < tierRank($1)
                    }
                    for p in targets {
                        if booked(f,higher) >= f.limits[higher]! { break }
                        guard let target = select(p,higher) else { break }
                        let old = p.result
                        p.cabin = higher
                        seat(p,target)
                        output.append("UPGRADED \(p.booking.pnr) \(p.name) \(lower) \(old) -> \(higher) \(target.id)")
                        count += 1
                    }
                }
            }
            reassign(f,&output)
            output.append("UPGRADE \(f.name) \(count)")
        case "CLOSE":
            let f = try flight(t[1],true)
            for b in f.bookings where !b.passengers.isEmpty && !b.checked {
                output.append("NOSHOW \(b.pnr) \(b.passengers.count)")
                remove(b.passengers)
            }
            reassign(f,&output)
            var count = 0
            var compensation = 0
            for c in classes where f.aircraft.cabins[c] != nil {
                let volunteers = f.volunteers.filter { $0.seat != nil && $0.cabin == c }
                for p in volunteers {
                    let useful = passengers(f).contains { $0.needsSeat && $0.seat == nil && $0.cabin == c && fits($0,p.seat!,[p]) }
                    if useful {
                        let value = c == "F" ? 500 : (c == "J" ? 300 : 150)
                        output.append("DENIED VOLUNTARY \(p.booking.pnr) \(p.name) \(c) \(value)")
                        count += 1
                        compensation += value
                        remove(targets(p))
                        reassign(f,&output)
                    }
                }
            }
            for p in passengers(f) where p.needsSeat && p.seat == nil {
                var value = p.cabin == "F" ? 1000 : (p.cabin == "J" ? 600 : 300)
                if p.type == "CHILD" { value /= 2 }
                output.append("DENIED INVOLUNTARY \(p.booking.pnr) \(p.name) \(p.cabin) \(value)")
                count += 1
                compensation += value
                remove(targets(p))
            }
            f.closed = true
            output.append("CLOSED \(f.name) denied \(count) compensation \(compensation)")
        case "BLOCK", "UNBLOCK":
            let f = try flight(t[1],true)
            guard f.aircraft.seats[t[2]] != nil else { throw fail("no seat "+t[2]+" on "+f.name) }
            let blocked = f.blocked.contains(t[2])
            if command == "BLOCK" && blocked { throw fail("seat "+t[2]+" is blocked") }
            if command == "UNBLOCK" && !blocked { throw fail("seat "+t[2]+" is not blocked") }
            output.append(command+" "+f.name+" "+t[2])
            if command == "BLOCK" {
                f.blocked.insert(t[2])
                if let p = f.occupied[t[2]] {
                    seat(p,nil)
                    seat(p,select(p,p.cabin))
                    output.append("DISPLACED \(p.booking.pnr) \(p.name) \(t[2]) -> \(p.result)")
                }
            } else { f.blocked.remove(t[2]) }
            reassign(f,&output)
        case "MAP":
            let f = try flight(t[1],false)
            output.append("MAP "+f.name)
            for name in classes {
                guard let c = f.aircraft.cabins[name] else { continue }
                output.append("CABIN "+name)
                output.append("   "+c.blocks.joined(separator: " "))
                for row in c.first...c.last {
                    let blocks = c.blocks.map { block in String(block.map { letter in
                        let id = String(row)+String(letter)
                        return f.blocked.contains(id) ? Character("#") : (f.occupied[id] != nil ? Character("X") : (f.aircraft.exits.contains(row) ? Character("E") : Character(".")))
                    }) }
                    output.append((row < 10 ? " " : "")+String(row)+" "+blocks.joined(separator: " "))
                }
            }
        case "MANIFEST":
            let f = try flight(t[1],false)
            let all = passengers(f)
            let seated = all.filter { $0.seat != nil }.sorted(by: seatBefore)
            let unassigned = all.filter { $0.needsSeat && $0.seat == nil }
            output.append("MANIFEST \(f.name) seated \(seated.count) unassigned \(unassigned.count) infants \(all.filter { !$0.needsSeat }.count)")
            for p in seated+unassigned {
                var result = "\(p.seat?.id ?? "---") \(p.cabin) \(p.booking.pnr) \(p.name) \(p.type)"
                if let infant = p.lap { result += " +"+infant.name }
                if tier(p) != "NONE" { result += " "+tier(p) }
                if p.booking.checked { result += " CHECKED" }
                if f.volunteers.contains(p) { result += " VOL" }
                output.append(result)
            }
        case "LOADFACTOR":
            let f = try flight(t[1],false)
            output.append("LOADFACTOR "+f.name)
            var totalSeated = 0
            var totalSeats = 0
            for c in classes where f.aircraft.cabins[c] != nil {
                let count = seats(f.aircraft,c,f.blocked)
                let seated = passengers(f).filter { $0.cabin == c && $0.seat != nil }.count
                output.append("\(c) \(seated)/\(count) \(load(seated,count)) booked \(booked(f,c))/\(f.limits[c]!)")
                totalSeated += seated
                totalSeats += count
            }
            output.append("ALL \(totalSeated)/\(totalSeats) \(load(totalSeated,totalSeats))")
        case "BALANCE":
            let f = try flight(t[1],false)
            var weight = 0
            var moment = 0
            for p in passengers(f) {
                guard let s = p.seat else { continue }
                let w = (p.type == "ADULT" ? 80 : 40)+(p.lap == nil ? 0 : 10)
                weight += w
                moment += w*(s.row-f.aircraft.base)
            }
            let limit = f.aircraft.limit
            let verdict = moment < -limit ? "NOSE-HEAVY" : (moment > limit ? "TAIL-HEAVY" : "OK")
            output.append("BALANCE \(f.name) weight \(weight) moment \(moment) limit \(limit) \(verdict)")
        case "BOARDING":
            let f = try flight(t[1],false)
            let ordered = passengers(f).filter { $0.seat != nil }.sorted { a,b in
                let ar = boardingRank(a)
                let br = boardingRank(b)
                if ar != br { return ar < br }
                if ar < 3 { return seatBefore(a,b) }
                if zone(a) != zone(b) { return zone(a) > zone(b) }
                let ak = ["W","M","A"].firstIndex(of: a.seat!.kind)!
                let bk = ["W","M","A"].firstIndex(of: b.seat!.kind)!
                if ak != bk { return ak < bk }
                if a.seat!.row != b.seat!.row { return a.seat!.row > b.seat!.row }
                return a.seat!.letter < b.seat!.letter
            }
            output.append("BOARDING \(f.name) \(ordered.count)")
            for (i,p) in ordered.enumerated() {
                let rank = boardingRank(p)
                let group = rank == 0 ? "PRE" : (rank == 1 ? "CABIN" : (rank == 2 ? "TIER" : "ZONE\(zone(p))"))
                output.append("\(i+1) \(group) \(p.result) \(p.booking.pnr) \(p.name)")
            }
        case "AVAIL":
            let f = try flight(t[1],false)
            try requireCabin(f,t[2])
            let free = f.aircraft.cabins[t[2]]!.seats.filter { !f.blocked.contains($0.id) && f.occupied[$0.id] == nil }
            output.append("AVAIL \(f.name) \(t[2]) free \(free.count) W \(free.filter { $0.kind == "W" }.count) M \(free.filter { $0.kind == "M" }.count) A \(free.filter { $0.kind == "A" }.count) EXIT \(free.filter { f.aircraft.exits.contains($0.row) }.count)")
        case "INFO":
            let b = try booking(t[1],false)
            output.append("INFO \(b.pnr) \(b.flight.name) \(b.passengers.count) \(b.checked ? "CHECKED" : "NOT-CHECKED")")
            for p in b.passengers { output.append("\(p.name) \(p.type) \(p.cabin) \(p.result)") }
        case "FIND":
            var found: [String] = []
            for f in flightOrder {
                for p in passengers(f) where p.name == t[1] {
                    found.append("\(f.name) \(p.booking.pnr) \(p.cabin) \(p.result) \(f.closed ? "CLOSED" : "OPEN")")
                }
            }
            output.append("FIND \(t[1]) \(tiers[t[1]] ?? "NONE") \(found.count)")
            output += found
        default: preconditionFailure("Unreachable command")
        }
        return output
    }
}

let app = Airline()
let count = Int(readLine()!)!
for _ in 0..<count {
    do {
        for line in try app.execute(readLine()!) { print(line) }
    } catch let problem as Problem {
        print("ERROR "+problem.message)
    } catch {
        preconditionFailure("Unexpected error")
    }
}
