import Foundation

let stationNames = ["GRILL", "FRY", "COLD", "BAR"]
let courseNames = ["DRINK", "STARTER", "MAIN", "DESSERT"]

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func cents(_ text: String) -> Int {
    let parts = text.split(separator: ".", omittingEmptySubsequences: false)
    return Int(parts[0])! * 100 + Int(parts[1])!
}

func money(_ cents: Int) -> String {
    return String(format: "%d.%02d", cents / 100, cents % 100)
}

func clock(_ elapsed: Int) -> String {
    let minutes = elapsed + 660
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

func rounded(_ value: Int, _ rate: Int) -> Int {
    return (value * rate + 50) / 100
}

final class DiningTable {
    let number: Int
    let seats: Int
    var check: Check?

    init(_ number: Int, _ seats: Int) {
        self.number = number
        self.seats = seats
    }
}

final class Server {
    let name: String
    var load = 0
    var parties = 0
    var sales = 0
    var tips = 0

    init(_ name: String) { self.name = name }
}

final class MenuItem {
    let name: String
    var station: String
    var prep: Int
    var price: Int
    var course: String
    var stock: Int?

    init(_ name: String, _ station: String, _ prep: Int,
         _ price: Int, _ course: String) {
        self.name = name
        self.station = station
        self.prep = prep
        self.price = price
        self.course = course
    }
}

final class Check {
    let party: String
    let size: Int
    var table: DiningTable
    let server: Server
    let since: Int
    var lines: [OrderLine] = []
    var paid = 0
    var discount = 0
    var closed = false

    init(_ party: String, _ size: Int, _ table: DiningTable,
         _ server: Server, _ since: Int) {
        self.party = party
        self.size = size
        self.table = table
        self.server = server
        self.since = since
    }

    var active: [OrderLine] { lines.filter { $0.state != "VOID" } }

    func amounts() -> [Int] {
        let subtotal = active.reduce(0) { $0 + $1.amount }
        let reduction = rounded(subtotal, discount)
        let afterDiscount = subtotal - reduction
        let service = size >= 6 ? rounded(afterDiscount, 18) : 0
        let tax = rounded(afterDiscount, 8)
        let total = afterDiscount + service + tax
        return [subtotal, reduction, service, tax, total, total - paid]
    }
}

final class OrderLine {
    let number: Int
    let check: Check
    var seat: Int
    let name: String
    let quantity: Int
    let station: String
    let prep: Int
    let price: Int
    let course: String
    var state = "ORDERED"
    var comp: String?
    var fired = 0
    var ready = 0
    var started = false

    init(_ number: Int, _ check: Check, _ seat: Int, _ item: MenuItem,
         _ quantity: Int, _ price: Int) {
        self.number = number
        self.check = check
        self.seat = seat
        self.name = item.name
        self.quantity = quantity
        self.station = item.station
        self.prep = item.prep
        self.price = price
        self.course = item.course
    }

    var amount: Int { comp == nil ? price * quantity : 0 }
    var tag: String { "#\(number)" }
}

final class Station {
    let name: String
    let capacity: Int
    var up = true
    var queue: [OrderLine] = []
    var cooking: [OrderLine] = []
    var tickets = 0
    var ticketTotal = 0
    var ticketMax = 0
    var remakes = 0

    init(_ name: String) {
        self.name = name
        self.capacity = name == "BAR" ? 2 : 1
    }
}

struct Waiting {
    let party: String
    let size: Int
    let joined: Int
}

final class Restaurant {
    var time = 0
    var tables: [Int: DiningTable] = [:]
    var servers: [Server] = []
    var serverNames: Set<String> = []
    var waiting: [Waiting] = []
    var seated: [String: Check] = [:]
    var menu: [String: MenuItem] = [:]
    var lines: [OrderLine] = []
    var stations: [String: Station] = Dictionary(
        uniqueKeysWithValues: stationNames.map { ($0, Station($0)) }
    )
    var happyRate = 0
    var happyUntil: Int?
    var guests = 0
    var parties = 0
    var closed = 0
    var stayTotal = 0
    var sales = [Int](repeating: 0, count: 4)
    var totals = [Int](repeating: 0, count: 5)
    var payments: [String: Int] = ["CASH": 0, "CARD": 0]
    var tips = 0
    var comps = 0
    var compAmount = 0
    var voids = 0
    var served: [String: Int] = [:]
    var output: [String] = []

    func emit(_ items: Any...) {
        emitParts(items)
    }

    func emitParts(_ items: [Any]) {
        output.append(items.map { String(describing: $0) }.joined(separator: " "))
    }

    func table(_ text: String, occupied: Bool = false) throws -> DiningTable {
        guard let number = Int(text), let selected = tables[number] else {
            throw CommandError("unknown table \(text)")
        }
        if occupied && selected.check == nil {
            throw CommandError("table \(text) is free")
        }
        return selected
    }

    func line(_ text: String) throws -> OrderLine {
        guard let number = Int(text), number >= 1 && number <= lines.count else {
            throw CommandError("unknown line \(text)")
        }
        return lines[number - 1]
    }

    func unlocked(_ check: Check) throws {
        if check.paid != 0 {
            throw CommandError("check for table \(check.table.number) is locked")
        }
    }

    func modification(_ order: OrderLine) throws {
        if order.state == "VOID" {
            throw CommandError("\(order.tag) is void")
        }
        if order.check.closed {
            throw CommandError("\(order.tag) is on a closed check")
        }
        try unlocked(order.check)
    }

    func allServed(_ check: Check) throws {
        let count = check.active.filter { $0.state != "SERVED" }.count
        if count > 0 {
            throw CommandError("table \(check.table.number) has \(count) unserved items")
        }
    }

    func selectTable(_ size: Int) -> DiningTable? {
        tables.values
            .filter { $0.check == nil && $0.seats >= size }
            .min { ($0.seats, $0.number) < ($1.seats, $1.number) }
    }

    func seatParty(_ party: String, _ size: Int, _ table: DiningTable) -> Check {
        let server = servers.min { $0.load < $1.load }!
        let check = Check(party, size, table, server, time)
        table.check = check
        seated[party] = check
        server.load += 1
        server.parties += 1
        guests += size
        parties += 1
        return check
    }

    func processWaitlist() {
        var remaining: [Waiting] = []
        for entry in waiting {
            if let table = selectTable(entry.size) {
                let check = seatParty(entry.party, entry.size, table)
                emit("SEATED", entry.party, entry.size, "table", table.number,
                     "server", check.server.name, "waited", time - entry.joined)
            } else {
                remaining.append(entry)
            }
        }
        waiting = remaining
    }

    func closeCheck(_ check: Check) {
        let amounts = check.amounts()
        for order in check.active {
            sales[courseNames.firstIndex(of: order.course)!] += order.amount
        }
        for i in totals.indices { totals[i] += amounts[i] }
        let stayed = time - check.since
        closed += 1
        stayTotal += stayed
        check.server.sales += amounts[4]
        check.server.load -= 1
        check.closed = true
        check.table.check = nil
        seated.removeValue(forKey: check.party)
        emit("FREE", "table", check.table.number, check.party, "stayed", stayed)
        processWaitlist()
    }

    func startStation(_ name: String, _ when: Int) {
        let station = stations[name]!
        while station.up && !station.queue.isEmpty &&
              station.cooking.count < station.capacity {
            let order = station.queue.removeFirst()
            order.state = "COOKING"
            order.started = true
            order.ready = when + order.prep
            station.cooking.append(order)
        }
    }

    func startAll(_ when: Int) {
        for name in stationNames { startStation(name, when) }
    }

    func seatSubtotals(_ check: Check) -> [Int: Int] {
        var amounts: [Int: Int] = [:]
        for order in check.active { amounts[order.seat, default: 0] += order.amount }
        return amounts
    }

    func allocate(_ values: [Int: Int], _ rate: Int) -> [Int: Int] {
        var amounts: [Int: Int] = [:]
        var sum = 0
        var allocated = 0
        for (seat, value) in values {
            let amount = value * rate / 100
            amounts[seat] = amount
            sum += value
            allocated += amount
        }
        let extra = rounded(sum, rate) - allocated
        let ranked = values.keys.sorted {
            let a = values[$0]! * rate % 100
            let b = values[$1]! * rate % 100
            return a != b ? a > b : $0 < $1
        }
        if extra > 0 {
            for seat in ranked.prefix(extra) { amounts[seat, default: 0] += 1 }
        }
        return amounts
    }

    func cmdTable(_ a: [String]) throws {
        let number = Int(a[0])!, seats = Int(a[1])!
        if tables[number] != nil {
            throw CommandError("table \(number) already exists")
        }
        tables[number] = DiningTable(number, seats)
        emit("TABLE", number, "seats", seats)
        processWaitlist()
    }

    func cmdStaff(_ a: [String]) throws {
        if serverNames.contains(a[0]) {
            throw CommandError("\(a[0]) is already on duty")
        }
        servers.append(Server(a[0]))
        serverNames.insert(a[0])
        emit("STAFF", a[0])
    }

    func cmdSeat(_ a: [String]) throws {
        let party = a[0], size = Int(a[1])!
        if let existing = seated[party] {
            throw CommandError("\(party) is already seated at table \(existing.table.number)")
        }
        if waiting.contains(where: { $0.party == party }) {
            throw CommandError("\(party) is already waiting")
        }
        if !tables.values.contains(where: { $0.seats >= size }) {
            throw CommandError("no table for party of \(size)")
        }
        if servers.isEmpty { throw CommandError("no server on duty") }
        if let table = selectTable(size) {
            let check = seatParty(party, size, table)
            emit("SEAT", party, size, "table", table.number, "server", check.server.name)
        } else {
            waiting.append(Waiting(party: party, size: size, joined: time))
            emit("WAIT", party, size, "position", waiting.count)
        }
    }

    func cmdCancel(_ a: [String]) throws {
        guard let index = waiting.firstIndex(where: { $0.party == a[0] }) else {
            throw CommandError("\(a[0]) is not waiting")
        }
        let entry = waiting.remove(at: index)
        emit("CANCEL", entry.party, entry.size, "waited", time - entry.joined)
    }

    func cmdMove(_ a: [String]) throws {
        let source = try table(a[0])
        let destination = try table(a[1])
        guard let check = source.check else {
            throw CommandError("table \(a[0]) is free")
        }
        if destination.check != nil { throw CommandError("table \(a[1]) is occupied") }
        if destination.seats < check.size {
            throw CommandError("table \(a[1]) is too small for \(check.party)")
        }
        source.check = nil
        destination.check = check
        check.table = destination
        emit("MOVE", check.party, "table", a[0], "->", a[1])
        processWaitlist()
    }

    func cmdMenu(_ a: [String]) throws {
        if !stationNames.contains(a[1]) { throw CommandError("unknown station \(a[1])") }
        if !courseNames.contains(a[4]) { throw CommandError("unknown course \(a[4])") }
        let action: String
        if let item = menu[a[0]] {
            item.station = a[1]
            item.prep = Int(a[2])!
            item.price = cents(a[3])
            item.course = a[4]
            action = "UPDATE"
        } else {
            menu[a[0]] = MenuItem(a[0], a[1], Int(a[2])!, cents(a[3]), a[4])
            action = "ADD"
        }
        emit("MENU", action, a[0], a[1], a[2], a[3], a[4])
    }

    func cmdStock(_ a: [String]) throws {
        guard let item = menu[a[0]] else {
            throw CommandError("unknown item \(a[0])")
        }
        item.stock = Int(a[1])!
        emit("STOCK", a[0], a[1])
    }

    func cmdHappy(_ a: [String]) {
        happyRate = Int(a[0])!
        happyUntil = time + Int(a[1])!
        emit("HAPPY", "\(a[0])%", "until", clock(happyUntil!))
    }

    func cmdItems() {
        emit("ITEMS", menu.count)
        let sorted = menu.values.sorted {
            let a = courseNames.firstIndex(of: $0.course)!
            let b = courseNames.firstIndex(of: $1.course)!
            return a != b ? a < b : $0.name < $1.name
        }
        for item in sorted {
            emit(item.course, item.name, item.station, item.prep,
                 money(item.price), item.stock.map { String($0) } ?? "-")
        }
    }

    func cmdOrder(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        try unlocked(check)
        let seat = Int(a[1])!, quantity = Int(a[3])!
        if seat > check.size {
            throw CommandError("seat \(seat) out of range for table \(a[0])")
        }
        guard let item = menu[a[2]] else {
            throw CommandError("unknown item \(a[2])")
        }
        if let stock = item.stock, stock < quantity {
            throw CommandError("only \(stock) \(item.name) left")
        }
        let happy = item.course == "DRINK" && happyUntil != nil && time < happyUntil!
        let price = item.price - (happy ? rounded(item.price, happyRate) : 0)
        let order = OrderLine(lines.count + 1, check, seat, item, quantity, price)
        lines.append(order)
        check.lines.append(order)
        var text = "ORDER \(order.tag) table \(a[0]) seat \(seat) " +
                   "\(item.name) x\(quantity) \(money(order.amount))"
        if happy { text += " HAPPY" }
        emit(text)
        if let stock = item.stock {
            item.stock = stock - quantity
            if item.stock == 0 { emit("SOLDOUT", item.name) }
        }
    }

    func cmdFire(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        guard let index = courseNames.firstIndex(of: a[1]) else {
            throw CommandError("unknown course \(a[1])")
        }
        let selected = check.lines.filter {
            $0.course == a[1] && $0.state == "ORDERED"
        }
        if selected.isEmpty {
            throw CommandError("nothing to fire for \(a[1]) at table \(a[0])")
        }
        if index >= 2 {
            for earlier in 1..<index {
                if check.lines.contains(where: {
                    $0.course == courseNames[earlier] && $0.state == "ORDERED"
                }) {
                    throw CommandError("fire \(courseNames[earlier]) first")
                }
            }
        }
        for order in selected {
            order.state = "QUEUED"
            order.fired = time
            stations[order.station]!.queue.append(order)
        }
        emitParts(["FIRE", "table", a[0], a[1]] + selected.map { $0.tag })
        startAll(time)
    }

    func cmdTick(_ a: [String]) {
        let target = time + Int(a[0])!
        emit("TICK", clock(target))
        while true {
            let cooking = stations.values.flatMap { $0.cooking }
            guard let completion = cooking.map({ $0.ready }).min(),
                  completion <= target else { break }
            for name in stationNames {
                let station = stations[name]!
                let finished = station.cooking.filter { $0.ready == completion }
                    .sorted { $0.number < $1.number }
                for order in finished {
                    station.cooking.removeAll { $0 === order }
                    order.state = "READY"
                    let ticket = completion - order.fired
                    station.tickets += 1
                    station.ticketTotal += ticket
                    station.ticketMax = max(station.ticketMax, ticket)
                    emit("READY", clock(completion), name, order.tag, order.name,
                         "x\(order.quantity)", "table", order.check.table.number,
                         "seat", order.seat)
                }
            }
            startAll(completion)
        }
        time = target
    }

    func cmdServe(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        let selected = check.lines.filter { $0.state == "READY" }
        if selected.isEmpty { throw CommandError("nothing ready for table \(a[0])") }
        for order in selected {
            order.state = "SERVED"
            served[order.name, default: 0] += order.quantity
        }
        emitParts(["SERVE", "table", a[0]] + selected.map { $0.tag })
    }

    func cmdRush(_ a: [String]) throws {
        let order = try line(a[0])
        if order.state != "QUEUED" { throw CommandError("\(order.tag) is not queued") }
        let station = stations[order.station]!
        station.queue.removeAll { $0 === order }
        station.queue.insert(order, at: 0)
        emit("RUSH", order.tag, order.station)
    }

    func cmdRemake(_ a: [String]) throws {
        let order = try line(a[0])
        if order.check.closed {
            throw CommandError("\(order.tag) is on a closed check")
        }
        if order.state != "READY" && order.state != "SERVED" {
            throw CommandError("\(order.tag) is not ready or served")
        }
        let station = stations[order.station]!
        order.state = "QUEUED"
        order.fired = time
        station.queue.insert(order, at: 0)
        station.remakes += 1
        emit("REMAKE", order.tag, order.name, order.station)
        startStation(order.station, time)
    }

    func cmdVoid(_ a: [String]) throws {
        let order = try line(a[0])
        if order.state == "VOID" { throw CommandError("\(order.tag) is already void") }
        if order.started { throw CommandError("\(order.tag) has already started") }
        if order.state == "QUEUED" {
            stations[order.station]!.queue.removeAll { $0 === order }
        }
        order.state = "VOID"
        let item = menu[order.name]!
        if let stock = item.stock { item.stock = stock + order.quantity }
        voids += 1
        emit("VOID", order.tag, order.name, "x\(order.quantity)")
    }

    func cmdStation(_ a: [String]) throws {
        guard let station = stations[a[0]] else {
            throw CommandError("unknown station \(a[0])")
        }
        if a[1] == "DOWN" && !station.up {
            throw CommandError("station \(a[0]) is already down")
        }
        if a[1] == "UP" && station.up {
            throw CommandError("station \(a[0]) is not down")
        }
        station.up = a[1] == "UP"
        if station.up { startStation(a[0], time) }
        emit("STATION", a[0], a[1])
    }

    func cmdComp(_ a: [String]) throws {
        let order = try line(a[0])
        try modification(order)
        if order.comp != nil { throw CommandError("\(order.tag) is already comped") }
        let amount = order.amount
        emit("COMP", order.tag, order.name, money(amount), a[1])
        comps += 1
        compAmount += amount
        order.comp = a[1]
    }

    func cmdTransfer(_ a: [String]) throws {
        let order = try line(a[0])
        try modification(order)
        let seat = Int(a[1])!
        if seat > order.check.size {
            throw CommandError("seat \(seat) out of range for table \(order.check.table.number)")
        }
        if seat == order.seat {
            throw CommandError("\(order.tag) is already on seat \(seat)")
        }
        emit("TRANSFER", order.tag, "seat", order.seat, "->", seat)
        order.seat = seat
    }

    func cmdDiscount(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        try unlocked(check)
        check.discount = Int(a[1])!
        emit("DISCOUNT", "table", a[0], "\(a[1])%")
    }

    func cmdBill(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        emit("BILL", "table", a[0], check.party, "guests", check.size)
        let subtotals = seatSubtotals(check)
        for seat in subtotals.keys.sorted() {
            emit("SEAT", seat, money(subtotals[seat]!))
            for order in check.lines where order.state != "VOID" && order.seat == seat {
                var text = "\(order.tag) \(order.name) x\(order.quantity) \(money(order.amount))"
                if let reason = order.comp { text += " COMP \(reason)" }
                emit(text)
            }
        }
        let amounts = check.amounts()
        emit("SUBTOTAL", money(amounts[0]))
        if check.discount != 0 {
            emit("DISCOUNT", "\(check.discount)%", money(amounts[1]))
        }
        if check.size >= 6 { emit("SERVICE", money(amounts[2])) }
        emit("TAX", money(amounts[3]))
        emit("TOTAL", money(amounts[4]))
        if check.paid != 0 {
            emit("PAID", money(check.paid))
            emit("DUE", money(amounts[5]))
        }
    }

    func cmdSplit(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        let due = check.amounts()[5]
        if due == 0 { throw CommandError("nothing to split for table \(a[0])") }
        if a[1] == "EVEN" {
            let count = Int(a[2])!
            if count > check.size {
                throw CommandError("cannot split table \(a[0]) \(count) ways")
            }
            emit("SPLIT", "table", a[0], "EVEN", count, "due", money(due))
            for payer in 1...count {
                emit("PAYER", payer, money(due / count + (payer <= due % count ? 1 : 0)))
            }
            return
        }
        if check.paid != 0 {
            throw CommandError("table \(a[0]) has payments")
        }
        let subtotals = seatSubtotals(check)
        let discounts = allocate(subtotals, check.discount)
        var after: [Int: Int] = [:]
        for (seat, subtotal) in subtotals {
            after[seat] = subtotal - discounts[seat]!
        }
        let services = check.size >= 6 ? allocate(after, 18) :
            Dictionary(uniqueKeysWithValues: after.keys.map { ($0, 0) })
        let taxes = allocate(after, 8)
        emit("SPLIT", "table", a[0], "BYSEAT", "total", money(check.amounts()[4]))
        for seat in subtotals.keys.sorted() {
            let total = after[seat]! + services[seat]! + taxes[seat]!
            emit("SEAT", seat, "subtotal", money(subtotals[seat]!),
                 "discount", money(discounts[seat]!), "service", money(services[seat]!),
                 "tax", money(taxes[seat]!), "total", money(total))
        }
    }

    func cmdPay(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        guard payments[a[1]] != nil else { throw CommandError("unknown method \(a[1])") }
        try allServed(check)
        let due = check.amounts()[5]
        if due == 0 { throw CommandError("nothing to pay for table \(a[0])") }
        let value = cents(a[2])
        let applied = min(value, due)
        check.paid += applied
        payments[a[1], default: 0] += applied
        if value < due {
            emit("PAY", "table", a[0], a[1], a[2], "remaining", money(due - value))
        } else {
            let excess = value - due
            emit("PAY", "table", a[0], a[1], a[2],
                 a[1] == "CASH" ? "change" : "tip", money(excess))
            if a[1] == "CARD" {
                tips += excess
                check.server.tips += excess
            }
            closeCheck(check)
        }
    }

    func cmdClose(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        try allServed(check)
        let due = check.amounts()[5]
        if due != 0 {
            throw CommandError("table \(a[0]) still owes \(money(due))")
        }
        closeCheck(check)
    }

    func cmdStatus(_ a: [String]) throws {
        let check = try table(a[0], occupied: true).check!
        emit("STATUS", "table", a[0], check.party, "guests", check.size,
             "since", clock(check.since))
        for order in check.lines {
            var text = "\(order.tag) seat \(order.seat) \(order.name) " +
                       "x\(order.quantity) \(order.course) \(order.state)"
            if order.state == "COOKING" { text += " until \(clock(order.ready))" }
            if let comp = order.comp { text += " COMP \(comp)" }
            emit(text)
        }
    }

    func cmdKitchen() {
        emit("KITCHEN", clock(time))
        for name in stationNames {
            let station = stations[name]!
            let cooking = station.cooking.sorted {
                ($0.ready, $0.number) < ($1.ready, $1.number)
            }
            let cookingText = cooking.isEmpty ? "-" :
                cooking.map { "\($0.tag)@\(clock($0.ready))" }.joined(separator: " ")
            let queueText = station.queue.isEmpty ? "-" :
                station.queue.map { $0.tag }.joined(separator: " ")
            emit(name, station.up ? "up" : "down", "cooking", cookingText,
                 "queue", queueText)
        }
    }

    func cmdFloor() {
        let occupied = tables.values.filter { $0.check != nil }.count
        emit("FLOOR", clock(time), "free", tables.count - occupied,
             "seated", occupied, "waiting", waiting.count)
        for number in tables.keys.sorted() {
            let table = tables[number]!
            guard let check = table.check else {
                emit("table", number, "seats", table.seats, "free")
                continue
            }
            var text = "table \(number) seats \(table.seats) " +
                       "\(check.party) guests \(check.size) server \(check.server.name) " +
                       "since \(clock(check.since)) items \(check.active.count) " +
                       "total \(money(check.amounts()[4]))"
            if check.paid != 0 { text += " paid \(money(check.paid))" }
            emit(text)
        }
        for (index, entry) in waiting.enumerated() {
            emit("WAITING", index + 1, entry.party, entry.size,
                 "since", clock(entry.joined))
        }
    }

    func cmdReport() {
        emit("REPORT", clock(time))
        emit("COVERS", guests, "parties", parties)
        emit("TURNS", closed, "avg_stay",
             closed > 0 ? String(stayTotal / closed) : "-")
        emit("SALES", "DRINK", money(sales[0]), "STARTER", money(sales[1]),
             "MAIN", money(sales[2]), "DESSERT", money(sales[3]))
        emit("TOTALS", "subtotal", money(totals[0]), "discount", money(totals[1]),
             "service", money(totals[2]), "tax", money(totals[3]),
             "total", money(totals[4]))
        emit("PAYMENTS", "cash", money(payments["CASH"]!),
             "card", money(payments["CARD"]!), "tips", money(tips))
        emit("COMPS", comps, money(compAmount), "VOIDS", voids)
        let ranked = served.keys.sorted {
            served[$0]! != served[$1]! ? served[$0]! > served[$1]! : $0 < $1
        }
        for (index, name) in ranked.prefix(3).enumerated() {
            emit("TOP", index + 1, name, served[name]!)
        }
        for name in stationNames {
            let station = stations[name]!
            emit(name, "tickets", station.tickets, "avg",
                 station.tickets > 0 ? String(station.ticketTotal / station.tickets) : "-",
                 "max", station.tickets > 0 ? String(station.ticketMax) : "-",
                 "remakes", station.remakes)
        }
        for server in servers {
            emit("SERVER", server.name, "tables", server.load,
                 "parties", server.parties, "sales", money(server.sales),
                 "tips", money(server.tips))
        }
    }

    func execute(_ input: String) {
        let parts = input.split(separator: " ").map(String.init)
        guard let command = parts.first else { return }
        let args = Array(parts.dropFirst())
        do {
            switch command {
            case "TABLE": try cmdTable(args)
            case "STAFF": try cmdStaff(args)
            case "SEAT": try cmdSeat(args)
            case "CANCEL": try cmdCancel(args)
            case "MOVE": try cmdMove(args)
            case "MENU": try cmdMenu(args)
            case "STOCK": try cmdStock(args)
            case "HAPPY": cmdHappy(args)
            case "ITEMS": cmdItems()
            case "ORDER": try cmdOrder(args)
            case "FIRE": try cmdFire(args)
            case "TICK": cmdTick(args)
            case "SERVE": try cmdServe(args)
            case "RUSH": try cmdRush(args)
            case "REMAKE": try cmdRemake(args)
            case "VOID": try cmdVoid(args)
            case "STATION": try cmdStation(args)
            case "COMP": try cmdComp(args)
            case "TRANSFER": try cmdTransfer(args)
            case "DISCOUNT": try cmdDiscount(args)
            case "BILL": try cmdBill(args)
            case "SPLIT": try cmdSplit(args)
            case "PAY": try cmdPay(args)
            case "CLOSE": try cmdClose(args)
            case "STATUS": try cmdStatus(args)
            case "KITCHEN": cmdKitchen()
            case "FLOOR": cmdFloor()
            case "REPORT": cmdReport()
            default: break
            }
        } catch let error as CommandError {
            emit("ERROR", error.message)
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}

let count = Int(readLine()!)!
let restaurant = Restaurant()
for _ in 0..<count {
    restaurant.execute(readLine()!)
}
for line in restaurant.output {
    print(line)
}
