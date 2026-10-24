import Foundation

let roomTypes = ["SINGLE", "DOUBLE", "SUITE"]
let weekdays = ["SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"]

struct DeskError: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

func leap(_ year: Int) -> Bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

func monthLengths(_ year: Int) -> [Int] {
    [31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
}

func dateNumber(_ text: String) throws -> Int {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { throw DeskError("invalid date \(text)") }
    let (year, month, day) = (parts[0], parts[1], parts[2])
    guard (2000...2099).contains(year), (1...12).contains(month),
          (1...monthLengths(year)[month - 1]).contains(day) else {
        throw DeskError("invalid date \(text)")
    }
    var result = 0
    if year > 2000 {
        for previous in 2000..<year {
            result += leap(previous) ? 366 : 365
        }
    }
    if month > 1 {
        for length in monthLengths(year).prefix(month - 1) {
            result += length
        }
    }
    return result + day - 1
}

func dateText(_ dayNumber: Int) -> String {
    var offset = dayNumber
    var year = 2000
    while offset >= (leap(year) ? 366 : 365) {
        offset -= leap(year) ? 366 : 365
        year += 1
    }
    var month = 1
    for days in monthLengths(year) {
        if offset < days { break }
        offset -= days
        month += 1
    }
    return String(format: "%04d-%02d-%02d", year, month, offset + 1)
}

func dateWeekday(_ day: Int) -> String {
    "\(dateText(day)) \(weekdays[day % 7])"
}

func cents(_ text: String) -> Int {
    let parts = text.split(separator: ".")
    return Int(parts[0])! * 100 + Int(parts[1])!
}

func money(_ amount: Int) -> String {
    "\(amount / 100)." + String(format: "%02d", amount % 100)
}

final class Room {
    let number: Int
    let kind: String
    var rate: Int
    var clean = true

    init(_ number: Int, _ kind: String, _ rate: Int) {
        self.number = number
        self.kind = kind
        self.rate = rate
    }
}

struct Night {
    let day: Int
    let room: Int
    let rate: Int
}

struct NightKey: Hashable {
    let day: Int
    let room: Int
}

struct Season {
    let start: Int
    let end: Int
    let percentage: Int
}

struct ExtraCharge {
    let item: String
    let amount: Int
}

struct Bill {
    let lodging: Int
    let discount: Int
    let penalty: Int
    let extras: Int
    let tax: Int
    let total: Int
}

final class Reservation {
    let id: String
    let guest: String
    var room: Room
    var arrival: Int
    var departure: Int
    var nights: [Night]
    var status = "booked"
    var extras: [ExtraCharge] = []
    var deposit = 0
    var paid = 0
    var posting: Int?
    var fee = 0
    var penalty: (day: Int, rate: Int)?
    var bill: Bill?

    init(id: String, guest: String, room: Room, arrival: Int, departure: Int, nights: [Night]) {
        self.id = id
        self.guest = guest
        self.room = room
        self.arrival = arrival
        self.departure = departure
        self.nights = nights
    }

    var lodging: Int { nights.reduce(0) { $0 + $1.rate } }
    var firstRate: Int { nights[0].rate }
}

struct WaitingEntry {
    let id: String
    let guest: String
    let kind: String
    let arrival: Int
    let departure: Int
}

struct Occupancy {
    let reservation: Reservation
    let rate: Int
}

struct DailyMetrics {
    let available: Int
    let occupied: Int
    let revenue: Int
}

final class HotelDesk {
    var today = try! dateNumber("2026-01-01")
    private var rooms: [Int: Room] = [:]
    private var seasons: [Season] = []
    private var blocks: Set<NightKey> = []
    private var reservations: [String: Reservation] = [:]
    private var reservationOrder: [String] = []
    private var waitlist: [WaitingEntry] = []
    private var usedIDs: Set<String> = []
    private var occupied: [NightKey: Occupancy] = [:]
    private(set) var output: [String] = []

    private func emit(_ parts: Any...) {
        output.append(parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func emitIndented(_ parts: Any...) {
        output.append("  " + parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func room(_ text: String) throws -> Room {
        guard let result = rooms[Int(text)!] else { throw DeskError("unknown room \(text)") }
        return result
    }

    private func requireType(_ kind: String) throws {
        guard roomTypes.contains(kind) else { throw DeskError("invalid type \(kind)") }
    }

    private func requireUnused(_ id: String) throws {
        guard !usedIDs.contains(id) else { throw DeskError("duplicate reservation \(id)") }
    }

    private func reservation(_ id: String, status: String? = nil) throws -> Reservation {
        guard let result = reservations[id] else { throw DeskError("unknown reservation \(id)") }
        if let status, result.status != status {
            throw DeskError("invalid status \(id) \(result.status)")
        }
        return result
    }

    private func stay(_ first: String, _ last: String) throws -> (Int, Int) {
        let arrival = try dateNumber(first)
        let departure = try dateNumber(last)
        if arrival < today { throw DeskError("past date \(first)") }
        if departure <= arrival { throw DeskError("invalid range \(first) \(last)") }
        if departure - arrival > 30 { throw DeskError("too long \(departure - arrival)") }
        return (arrival, departure)
    }

    private func period(_ first: String, _ last: String,
                        pastRestricted: Bool = false, limited: Bool = true) throws -> (Int, Int) {
        let start = try dateNumber(first)
        let end = try dateNumber(last)
        if pastRestricted && start < today { throw DeskError("past date \(first)") }
        if end < start { throw DeskError("invalid range \(first) \(last)") }
        if limited && end - start + 1 > 31 {
            throw DeskError("too long \(end - start + 1)")
        }
        return (start, end)
    }

    private func nightRate(_ room: Room, _ day: Int) -> Int {
        let percentage = seasons.reversed()
            .first(where: { $0.start <= day && day <= $0.end })?.percentage ?? 100
        return room.rate * percentage / 100
    }

    private func price(_ room: Room, _ arrival: Int, _ departure: Int) -> [Night] {
        (arrival..<departure).map { Night(day: $0, room: room.number, rate: nightRate(room, $0)) }
    }

    private func firstUnavailable(_ room: Room, _ arrival: Int, _ departure: Int,
                                  except reservation: Reservation? = nil) -> Int? {
        for day in arrival..<departure {
            let key = NightKey(day: day, room: room.number)
            if blocks.contains(key) { return day }
            if let occupant = occupied[key]?.reservation, occupant !== reservation { return day }
        }
        return nil
    }

    private func findRoom(_ kind: String, _ arrival: Int, _ departure: Int,
                          except reservation: Reservation? = nil) -> Room? {
        rooms.values.sorted { $0.number < $1.number }
            .first { $0.kind == kind && firstUnavailable($0, arrival, departure, except: reservation) == nil }
    }

    private func inHouse(_ room: Room) -> Reservation? {
        reservations.values.first { $0.status == "inhouse" && $0.room === room }
    }

    private func occupy(_ reservation: Reservation, _ nights: [Night]) {
        for night in nights {
            occupied[NightKey(day: night.day, room: night.room)] =
                Occupancy(reservation: reservation, rate: night.rate)
        }
    }

    private func release(_ reservation: Reservation, from first: Int? = nil) {
        for night in reservation.nights where first == nil || night.day >= first! {
            occupied.removeValue(forKey: NightKey(day: night.day, room: night.room))
        }
    }

    private func createReservation(id: String, guest: String, room: Room,
                                   arrival: Int, departure: Int, indented: Bool = false) {
        let nights = price(room, arrival, departure)
        let entry = Reservation(id: id, guest: guest, room: room, arrival: arrival,
                                departure: departure, nights: nights)
        reservations[id] = entry
        reservationOrder.append(id)
        usedIDs.insert(id)
        occupy(entry, nights)
        let line = "BOOK \(id) \(guest) room \(room.number) \(room.kind) " +
                   "\(dateText(arrival)) -> \(dateText(departure)) nights \(departure - arrival) " +
                   "total \(money(entry.lodging))"
        if indented { emitIndented(line) } else { emit(line) }
    }

    private func guestTotal(_ guest: String) -> Int {
        reservations.values.filter { $0.guest == guest }.reduce(0) { $0 + $1.paid }
    }

    private func tier(_ guest: String) -> String {
        let points = guestTotal(guest) / 100
        return points >= 2000 ? "GOLD" : points >= 500 ? "SILVER" : "BRONZE"
    }

    private func bill(_ reservation: Reservation) -> Bill {
        let lodging = reservation.lodging
        let percentage = tier(reservation.guest) == "GOLD" ? 10 :
                         tier(reservation.guest) == "SILVER" ? 5 : 0
        let discount = lodging * percentage / 100
        let penalty = reservation.penalty?.rate ?? 0
        let extras = reservation.extras.reduce(0) { $0 + $1.amount }
        let subtotal = lodging - discount + penalty + extras
        let tax = subtotal / 10
        return Bill(lodging: lodging, discount: discount, penalty: penalty,
                    extras: extras, tax: tax, total: subtotal + tax)
    }

    private func depositText(_ reservation: Reservation, _ total: Int) -> String {
        if total >= reservation.deposit {
            return "deposit \(money(reservation.deposit)) due \(money(total - reservation.deposit))"
        }
        return "deposit \(money(reservation.deposit)) refund \(money(reservation.deposit - total))"
    }

    private func checkout(_ reservation: Reservation, on day: Int, indented: Bool = false) {
        if day < reservation.departure {
            let rate = reservation.nights.first { $0.day == day }!.rate
            reservation.penalty = (day, rate)
            release(reservation, from: day)
            reservation.nights.removeAll { $0.day >= day }
            reservation.departure = day
        }
        let amount = bill(reservation)
        reservation.bill = amount
        reservation.paid = amount.total
        reservation.status = "checkedout"
        reservation.posting = day
        reservation.room.clean = false
        let line = "CHECKOUT \(reservation.id) nights \(reservation.nights.count) " +
                   "lodging \(money(amount.lodging)) discount \(money(amount.discount)) " +
                   "penalty \(money(amount.penalty)) extras \(money(amount.extras)) " +
                   "tax \(money(amount.tax)) total \(money(amount.total)) " +
                   depositText(reservation, amount.total)
        if indented { emitIndented(line) } else { emit(line) }
    }

    private func processWaitlist() {
        var remaining: [WaitingEntry] = []
        for entry in waitlist {
            if entry.arrival < today {
                emitIndented("WAITLIST", entry.id, "expired")
            } else if let room = findRoom(entry.kind, entry.arrival, entry.departure) {
                createReservation(id: entry.id, guest: entry.guest, room: room,
                                  arrival: entry.arrival, departure: entry.departure, indented: true)
            } else {
                remaining.append(entry)
            }
        }
        waitlist = remaining
    }

    private func occupancyText(_ numbers: [Int], _ day: Int) -> String {
        let blocked = numbers.filter { blocks.contains(NightKey(day: day, room: $0)) }.count
        let count = numbers.filter { occupied[NightKey(day: day, room: $0)] != nil }.count
        let available = numbers.count - blocked
        let rate = available > 0 ? "\(count * 100 / available)%" : "n/a"
        return "rooms \(numbers.count) blocked \(blocked) occupied \(count) rate \(rate)"
    }

    private func dailyMetrics(_ day: Int) -> DailyMetrics {
        let numbers = Array(rooms.keys)
        let available = numbers.count - numbers.filter {
            blocks.contains(NightKey(day: day, room: $0))
        }.count
        let nights = numbers.compactMap { occupied[NightKey(day: day, room: $0)] }
        return DailyMetrics(available: available, occupied: nights.count,
                            revenue: nights.reduce(0) { $0 + $1.rate })
    }

    private func metricsText(_ metrics: DailyMetrics) -> String {
        let (available, count, revenue) =
            (metrics.available, metrics.occupied, metrics.revenue)
        let rate = available == 0 ? "n/a" : "\(count * 100 / available)%"
        let adr = count == 0 ? "n/a" : money(revenue / count)
        let revpar = available == 0 ? "n/a" : money(revenue / available)
        return "sold \(count)/\(available) rate \(rate) revenue \(money(revenue)) " +
               "adr \(adr) revpar \(revpar)"
    }

    private func invoice(_ reservation: Reservation) {
        emit("INVOICE", reservation.id, reservation.guest, "room", reservation.room.number,
             reservation.room.kind, reservation.status)
        if reservation.status == "cancelled" || reservation.status == "noshow" {
            emitIndented(reservation.status == "cancelled" ? "cancellation" : "noshow",
                         "fee", money(reservation.fee))
            emitIndented("total", money(reservation.fee))
            emitIndented(depositText(reservation, reservation.fee))
            return
        }
        for night in reservation.nights {
            emitIndented(dateWeekday(night.day), "room", night.room, money(night.rate))
        }
        let amount = reservation.status == "checkedout" ? reservation.bill! : bill(reservation)
        emitIndented("lodging", money(amount.lodging))
        emitIndented("discount", money(amount.discount))
        if let penalty = reservation.penalty {
            emitIndented("penalty", dateWeekday(penalty.day), money(amount.penalty))
        }
        for extra in reservation.extras {
            emitIndented("extra", extra.item, money(extra.amount))
        }
        emitIndented("tax", money(amount.tax))
        emitIndented("total", money(amount.total))
        emitIndented(depositText(reservation, amount.total))
    }

    private func executeCommand(_ command: String, _ a: [String]) throws {
        switch command {
        case "ROOM":
            let number = Int(a[0])!
            if rooms[number] != nil { throw DeskError("duplicate room \(a[0])") }
            try requireType(a[1])
            rooms[number] = Room(number, a[1], cents(a[2]))
            emit("ROOM", a[0], a[1], a[2])

        case "RATE":
            let entry = try room(a[0])
            let previous = entry.rate
            entry.rate = cents(a[1])
            emit("RATE", a[0], money(previous), "->", a[1])

        case "SEASON":
            let (start, end) = try period(a[0], a[1], limited: false)
            seasons.append(Season(start: start, end: end, percentage: Int(a[2])!))
            emit("SEASON", seasons.count, a[0], "->", a[1], a[2] + "%")

        case "BLOCK", "UNBLOCK":
            let room = try self.room(a[0])
            let (start, end) = try period(a[1], a[2], pastRestricted: true)
            if command == "BLOCK" {
                for day in start...end {
                    if occupied[NightKey(day: day, room: room.number)] != nil {
                        throw DeskError("room unavailable \(a[0]) \(dateText(day))")
                    }
                }
            }
            var changed = 0
            for day in start...end {
                let key = NightKey(day: day, room: room.number)
                if command == "BLOCK" {
                    if blocks.insert(key).inserted { changed += 1 }
                } else if blocks.remove(key) != nil {
                    changed += 1
                }
            }
            if command == "BLOCK" {
                emit("BLOCK", a[0], a[1], "->", a[2], "added", changed)
            } else {
                emit("UNBLOCK", a[0], a[1], "->", a[2], "removed", changed)
            }

        case "CLEAN":
            let entry = try room(a[0])
            if entry.clean { throw DeskError("already clean \(a[0])") }
            entry.clean = true
            emit("CLEAN", a[0])

        case "TODAY":
            let day = try dateNumber(a[0])
            if day < today { throw DeskError("past date \(a[0])") }
            emit("TODAY", dateWeekday(day))
            let departures = reservations.values
                .filter { $0.status == "inhouse" && $0.departure < day }
                .sorted { ($0.departure, $0.id) < ($1.departure, $1.id) }
            for entry in departures {
                checkout(entry, on: entry.departure, indented: true)
            }
            let absences = reservations.values
                .filter { $0.status == "booked" && $0.arrival < day }
                .sorted { ($0.arrival, $0.id) < ($1.arrival, $1.id) }
            for entry in absences {
                release(entry)
                entry.fee = entry.firstRate
                entry.paid = entry.fee
                entry.status = "noshow"
                entry.posting = entry.arrival
                emitIndented("NOSHOW", entry.id, entry.guest, "fee",
                             money(entry.fee), depositText(entry, entry.fee))
            }
            today = day

        case "BOOK", "BOOKROOM", "WAITLIST":
            let id = a[0], guest = a[1]
            try requireUnused(id)
            let isSpecific = command == "BOOKROOM"
            if isSpecific {
                let selected = try room(a[2])
                let (arrival, departure) = try stay(a[3], a[4])
                if let day = firstUnavailable(selected, arrival, departure) {
                    throw DeskError("room unavailable \(a[2]) \(dateText(day))")
                }
                createReservation(id: id, guest: guest, room: selected,
                                  arrival: arrival, departure: departure)
            } else {
                let kind = a[2]
                try requireType(kind)
                let (arrival, departure) = try stay(a[3], a[4])
                if let selected = findRoom(kind, arrival, departure) {
                    createReservation(id: id, guest: guest, room: selected,
                                      arrival: arrival, departure: departure)
                } else if command == "BOOK" {
                    throw DeskError("no availability \(kind) \(a[3]) \(a[4])")
                } else {
                    waitlist.append(WaitingEntry(id: id, guest: guest, kind: kind,
                                                 arrival: arrival, departure: departure))
                    usedIDs.insert(id)
                    emit("WAITLIST", id, "queued position", waitlist.count)
                }
            }

        case "MODIFY":
            let entry = try reservation(a[0], status: "booked")
            let (arrival, departure) = try stay(a[1], a[2])
            var selected = entry.room
            var choice = "kept"
            if firstUnavailable(selected, arrival, departure, except: entry) != nil {
                guard let replacement = findRoom(selected.kind, arrival, departure, except: entry) else {
                    throw DeskError("no availability \(selected.kind) \(a[1]) \(a[2])")
                }
                selected = replacement
                choice = "reassigned"
            }
            let nights = price(selected, arrival, departure)
            release(entry)
            entry.room = selected
            entry.arrival = arrival
            entry.departure = departure
            entry.nights = nights
            occupy(entry, nights)
            emit("MODIFY", entry.id, "room", selected.number, choice,
                 a[1], "->", a[2], "nights", departure - arrival,
                 "total", money(entry.lodging))

        case "CANCEL":
            if let index = waitlist.firstIndex(where: { $0.id == a[0] }) {
                waitlist.remove(at: index)
                emit("CANCEL", a[0], "waitlist removed")
            } else {
                let entry = try reservation(a[0], status: "booked")
                let days = entry.arrival - today
                let fee = days >= 7 ? 0 : days >= 1 ? entry.firstRate / 2 : entry.firstRate
                release(entry)
                entry.fee = fee
                entry.paid = fee
                entry.status = "cancelled"
                entry.posting = today
                emit("CANCEL", entry.id, "days", days, "fee", money(fee),
                     depositText(entry, fee))
            }

        case "CHECKIN":
            let entry = try reservation(a[0], status: "booked")
            if entry.arrival != today {
                throw DeskError("not arrival date \(entry.id) \(dateText(entry.arrival))")
            }
            if let guest = inHouse(entry.room) {
                throw DeskError("room occupied \(entry.room.number) \(guest.id)")
            }
            if !entry.room.clean {
                throw DeskError("room dirty \(entry.room.number)")
            }
            entry.status = "inhouse"
            emit("CHECKIN", entry.id, entry.guest, "room", entry.room.number,
                 "until", dateText(entry.departure))

        case "MOVE":
            let entry = try reservation(a[0], status: "inhouse")
            let selected = try room(a[1])
            let previous = entry.room
            if selected === previous { throw DeskError("same room \(a[1])") }
            let remaining = entry.nights.filter { $0.day >= today }
            if remaining.isEmpty { throw DeskError("no remaining nights \(entry.id)") }
            if let day = firstUnavailable(selected, remaining[0].day, entry.departure, except: entry) {
                throw DeskError("room unavailable \(a[1]) \(dateText(day))")
            }
            if let guest = inHouse(selected) {
                throw DeskError("room occupied \(selected.number) \(guest.id)")
            }
            if !selected.clean { throw DeskError("room dirty \(selected.number)") }
            release(entry, from: today)
            entry.nights = entry.nights.map {
                Night(day: $0.day, room: $0.day >= today ? selected.number : $0.room, rate: $0.rate)
            }
            occupy(entry, entry.nights.filter { $0.day >= today })
            previous.clean = false
            entry.room = selected
            emit("MOVE", entry.id, previous.number, "->", selected.number,
                 "nights", remaining.count)

        case "EXTEND":
            let entry = try reservation(a[0], status: "inhouse")
            let departure = try dateNumber(a[1])
            if departure <= entry.departure {
                throw DeskError("invalid range \(dateText(entry.departure)) \(a[1])")
            }
            if departure - entry.arrival > 30 {
                throw DeskError("too long \(departure - entry.arrival)")
            }
            if let day = firstUnavailable(entry.room, entry.departure, departure, except: entry) {
                throw DeskError("room unavailable \(entry.room.number) \(dateText(day))")
            }
            let nights = price(entry.room, entry.departure, departure)
            entry.nights.append(contentsOf: nights)
            occupy(entry, nights)
            entry.departure = departure
            emit("EXTEND", entry.id, "until", a[1], "nights", entry.nights.count,
                 "total", money(entry.lodging))

        case "CHARGE":
            let entry = try reservation(a[0], status: "inhouse")
            let amount = cents(a[1])
            if amount == 0 { throw DeskError("invalid amount") }
            entry.extras.append(ExtraCharge(item: a[2], amount: amount))
            let total = entry.extras.reduce(0) { $0 + $1.amount }
            emit("CHARGE", entry.id, a[2], a[1], "extras", money(total))

        case "PAY":
            let entry = try reservation(a[0])
            if entry.status != "booked" && entry.status != "inhouse" {
                throw DeskError("invalid status \(entry.id) \(entry.status)")
            }
            let amount = cents(a[1])
            if amount == 0 { throw DeskError("invalid amount") }
            entry.deposit += amount
            emit("PAY", entry.id, a[1], "deposit", money(entry.deposit))

        case "CHECKOUT":
            let entry = try reservation(a[0], status: "inhouse")
            checkout(entry, on: today)

        case "INVOICE":
            invoice(try reservation(a[0]))

        case "AVAIL":
            try requireType(a[0])
            let (start, end) = try period(a[1], a[2])
            let numbers = rooms.values.filter { $0.kind == a[0] }.map(\.number).sorted()
            emit("AVAIL", a[0], a[1], "->", a[2])
            for day in start...end {
                let free = numbers.filter { number in
                    let key = NightKey(day: day, room: number)
                    return !blocks.contains(key) && occupied[key] == nil
                }
                var line = "\(dateWeekday(day)) free \(free.count)"
                if !free.isEmpty {
                    line += " " + free.map(String.init).joined(separator: " ")
                }
                emitIndented(line)
            }

        case "OCCUPANCY":
            let day = try dateNumber(a[0])
            emit("OCCUPANCY", dateWeekday(day), occupancyText(Array(rooms.keys), day))
            for kind in roomTypes {
                let numbers = rooms.values.filter { $0.kind == kind }.map(\.number)
                if !numbers.isEmpty { emitIndented(kind, occupancyText(numbers, day)) }
            }

        case "STATS":
            let (start, end) = try period(a[0], a[1])
            emit("STATS", a[0], "->", a[1])
            var sums = DailyMetrics(available: 0, occupied: 0, revenue: 0)
            for day in start...end {
                let item = dailyMetrics(day)
                sums = DailyMetrics(available: sums.available + item.available,
                                    occupied: sums.occupied + item.occupied,
                                    revenue: sums.revenue + item.revenue)
                emitIndented(dateWeekday(day), metricsText(item))
            }
            emitIndented("total", metricsText(sums))

        case "ROOMS":
            emit("ROOMS", dateWeekday(today), "rooms", rooms.count)
            for entry in rooms.values.sorted(by: { $0.number < $1.number }) {
                var parts = [String(entry.number), entry.kind, "base", money(entry.rate),
                             "tonight", money(nightRate(entry, today)),
                             entry.clean ? "clean" : "dirty"]
                if let guest = inHouse(entry) {
                    parts += ["occupied", guest.id]
                } else if blocks.contains(NightKey(day: today, room: entry.number)) {
                    parts.append("blocked")
                } else {
                    parts.append("vacant")
                }
                if let upcoming = reservations.values
                    .filter({ $0.status == "booked" && $0.room === entry })
                    .min(by: { ($0.arrival, $0.id) < ($1.arrival, $1.id) }) {
                    parts += ["next", upcoming.id, dateText(upcoming.arrival)]
                }
                emitIndented(parts.joined(separator: " "))
            }

        case "LIST":
            let entries = reservations.values.filter { $0.status == a[0] }
                .sorted { ($0.arrival, $0.id) < ($1.arrival, $1.id) }
            emit("LIST", a[0], entries.count)
            for entry in entries {
                emitIndented(entry.id, entry.guest, "room", entry.room.number,
                             dateText(entry.arrival), "->", dateText(entry.departure))
            }

        case "QUEUE":
            emit("QUEUE", waitlist.count)
            for (index, entry) in waitlist.enumerated() {
                emitIndented(index + 1, entry.id, entry.guest, entry.kind,
                             dateText(entry.arrival), "->", dateText(entry.departure))
            }

        case "SCHEDULE":
            let day = try dateNumber(a[0])
            let arrivals = reservations.values
                .filter { $0.arrival == day && $0.status != "cancelled" }
                .sorted { $0.id < $1.id }
            let departures = reservations.values
                .filter {
                    $0.departure == day &&
                    ["booked", "inhouse", "checkedout"].contains($0.status)
                }
                .sorted { $0.id < $1.id }
            emit("SCHEDULE", dateWeekday(day), "arrivals", arrivals.count,
                 "departures", departures.count)
            for entry in arrivals {
                emitIndented("arrival", entry.id, entry.guest, "room", entry.room.number,
                             entry.status)
            }
            for entry in departures {
                emitIndented("departure", entry.id, entry.guest, "room", entry.room.number,
                             entry.status)
            }

        case "GUEST":
            let entries = reservationOrder.compactMap { reservations[$0] }
                .filter { $0.guest == a[0] }
            if entries.isEmpty { throw DeskError("unknown guest \(a[0])") }
            emit("GUEST", a[0])
            for entry in entries {
                let active = entry.status == "booked" || entry.status == "inhouse"
                emitIndented(entry.id, "room", entry.room.number, entry.room.kind,
                             dateText(entry.arrival), "->", dateText(entry.departure),
                             entry.status, active ? "deposit" : "paid",
                             money(active ? entry.deposit : entry.paid))
            }
            let paid = guestTotal(a[0])
            emitIndented("total paid", money(paid), "points", paid / 100, "tier", tier(a[0]))

        case "REVENUE":
            let (start, end) = try period(a[0], a[1], limited: false)
            let posted = reservations.values.filter { entry in
                guard let day = entry.posting else { return false }
                return start <= day && day <= end
            }
            let checkedOut = posted.filter { $0.status == "checkedout" }
            let cancelled = posted.filter { $0.status == "cancelled" }
            let noShows = posted.filter { $0.status == "noshow" }
            let lodging = checkedOut.reduce(0) { $0 + $1.bill!.lodging }
            let discount = checkedOut.reduce(0) { $0 + $1.bill!.discount }
            let penalty = checkedOut.reduce(0) { $0 + $1.bill!.penalty }
            let extras = checkedOut.reduce(0) { $0 + $1.bill!.extras }
            let tax = checkedOut.reduce(0) { $0 + $1.bill!.tax }
            let cancellations = cancelled.reduce(0) { $0 + $1.fee }
            let noShowFees = noShows.reduce(0) { $0 + $1.fee }
            emit("REVENUE", a[0], "->", a[1])
            for (label, amount) in [
                ("lodging", lodging), ("discount", discount), ("penalty", penalty),
                ("extras", extras), ("tax", tax), ("cancellation", cancellations),
                ("noshow", noShowFees)
            ] {
                emitIndented(label, money(amount))
            }
            let total = lodging - discount + penalty + extras + tax + cancellations + noShowFees
            emitIndented("total", money(total))
            emitIndented("checkouts", checkedOut.count, "cancellations",
                         cancelled.count, "noshows", noShows.count)
        default:
            break
        }
    }

    func execute(_ line: String) {
        let fields = line.split(separator: " ").map(String.init)
        guard let command = fields.first else { return }
        do {
            try executeCommand(command, Array(fields.dropFirst()))
        } catch let error as DeskError {
            emit("ERROR", error.reason)
        } catch {
            fatalError("Unexpected hotel command failure: \(error)")
        }
        processWaitlist()
    }
}

let count = Int(readLine()!)!
let desk = HotelDesk()
for _ in 0..<count {
    desk.execute(readLine()!)
}
if !desk.output.isEmpty {
    print(desk.output.joined(separator: "\n"))
}
