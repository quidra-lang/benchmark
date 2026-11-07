import Foundation

let rateSettings: Set<String> = [
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
]
let initialSettings: [(String, Int)] = [
    ("STATE", 500), ("SUPP", 2200), ("SSRATE", 620), ("MEDRATE", 145),
    ("ADDMED", 90), ("UIRATE", 270), ("MATCH", 5000), ("MATCHMAX", 600),
    ("GARNCAP", 2500), ("SSBASE", 16860000), ("ADDBASE", 20000000),
    ("UIBASE", 700000), ("RETIRECAP", 2300000), ("ALLOWANCE", 15000),
    ("NIGHT", 100)
]
let fields = [
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment",
    "net", "employer_social", "employer_medicare", "unemployment", "match",
    "employer", "W", "Y", "F", "J"
]
let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

struct PayrollError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func cents(_ text: String) -> Int {
    let parts = text.split(separator: ".")
    return Int(parts[0])! * 100 + Int(parts[1])!
}

func money(_ value: Int) -> String {
    "\(value / 100)." + String(format: "%02d", value % 100)
}

func rateText(_ value: Int) -> String { money(value) + "%" }

func duration(_ minutes: Int) -> String {
    "\(minutes / 60):" + String(format: "%02d", minutes % 60)
}

func clock(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

func weekday(_ day: Int) -> String { weekdays[(day - 1) % 7] }
func periodOf(_ day: Int) -> Int { (day - 1) / 14 + 1 }

func emptyTotals() -> [String: Int] {
    Dictionary(uniqueKeysWithValues: fields.map { ($0, 0) })
}

func sumStubs(_ stubs: [[String: Int]]) -> [String: Int] {
    var totals = emptyTotals()
    for stub in stubs {
        for field in fields {
            totals[field, default: 0] += stub[field, default: 0]
        }
    }
    return totals
}

func progressive(_ table: [Int: Int], _ amount: Int) -> Int {
    let pairs = table.sorted { $0.key < $1.key }
    var numerator = 0
    for i in pairs.indices {
        let lower = pairs[i].key
        if lower >= amount { break }
        let upper = i + 1 < pairs.count ? pairs[i + 1].key : amount
        numerator += pairs[i].value * (min(amount, upper) - lower)
    }
    return numerator / 10000
}

struct Shift {
    let start: Int
    let end: Int
}

struct Garnishment {
    let rate: Int
    var balance: Int
}

struct Stub {
    var values = emptyTotals()
    var balances: [Int] = []
    var garnishmentBalance = 0
    var ptoBalance = 0

    subscript(_ field: String) -> Int {
        get { values[field, default: 0] }
        set { values[field] = newValue }
    }
}

struct StubRecord {
    let stub: Stub
    let department: String
}

final class Employee {
    let id: Int
    var department: String
    let kind: String
    var base: Int
    var active = true
    var retirement = 0
    var health = 0
    var allowances = 0
    var extra = 0
    var garnishments: [Garnishment] = []
    var bonus = 0
    var ptoBalance = 0
    var shifts: [Int: [Shift]] = [:]
    var pto: [Int: Int] = [:]
    var leave: Set<Int> = []
    var sales: [Int: Int] = [:]
    var stubs: [Int: StubRecord] = [:]
    var ytd = emptyTotals()
    var periods = 0

    init(id: Int, department: String, kind: String, base: Int) {
        self.id = id
        self.department = department
        self.kind = kind
        self.base = base
    }

    var garnishmentBalance: Int { garnishments.reduce(0) { $0 + $1.balance } }
}

struct Daily {
    let worked: Int
    let regular: Int
    let overtime: Int
    let double: Int
    let night: Int
    let pto: Int

    var classified: [Int] { [regular, overtime, double, night, pto] }
}

final class Payroll {
    private var settings: [String: Int]
    private var brackets: [Int: Int] = [:]
    private var tiers: [Int: Int] = [:]
    private var holidays: Set<Int> = []
    private var employees: [Int: Employee] = [:]
    private var closed = 0
    private(set) var output: [String] = []

    init() {
        settings = Dictionary(uniqueKeysWithValues: initialSettings)
    }

    private func put(_ indent: Int, _ parts: Any...) {
        output.append(String(repeating: " ", count: indent) +
                      parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func putParts(_ indent: Int, _ parts: [Any]) {
        output.append(String(repeating: " ", count: indent) +
                      parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func employee(_ text: String, active: Bool = false,
                          kind: String? = nil) throws -> Employee {
        guard let person = employees[Int(text)!] else {
            throw PayrollError("unknown employee \(text)")
        }
        if active && !person.active { throw PayrollError("terminated employee \(text)") }
        if let kind, person.kind != kind {
            throw PayrollError("not \(kind.lowercased()) \(text)")
        }
        return person
    }

    private func checkDay(_ text: String) throws -> Int {
        let day = Int(text)!
        if !(1...364).contains(day) { throw PayrollError("invalid day \(text)") }
        let period = periodOf(day)
        if period <= closed { throw PayrollError("period closed \(period)") }
        return day
    }

    private func checkPeriod(_ text: String) throws -> Int {
        let period = Int(text)!
        if !(1...26).contains(period) { throw PayrollError("invalid period \(text)") }
        return period
    }

    private func checkRate(_ text: String) throws -> Int {
        let rate = cents(text)
        if rate > 10000 { throw PayrollError("invalid rate \(text)") }
        return rate
    }

    private func checkAmount(_ text: String) throws -> Int {
        let amount = cents(text)
        if amount == 0 { throw PayrollError("invalid amount") }
        return amount
    }

    private func checkTime(_ text: String) throws -> Int {
        let parts = text.split(separator: ":")
        let hour = Int(parts[0])!, minute = Int(parts[1])!
        if hour > 23 || minute > 59 { throw PayrollError("invalid time \(text)") }
        return hour * 60 + minute
    }

    private func daily(_ employee: Employee, _ day: Int) -> Daily {
        let shifts = employee.shifts[day] ?? []
        let worked = shifts.reduce(0) { $0 + $1.end - $1.start }
        let night = shifts.reduce(0) { count, shift in
            count + max(0, min(shift.end, 360) - shift.start) +
                max(0, shift.end - max(shift.start, 1320))
        }
        let pto = employee.pto[day] ?? 0
        if day % 7 == 0 || holidays.contains(day) {
            return Daily(worked: worked, regular: 0, overtime: 0,
                         double: worked, night: night, pto: pto)
        }
        return Daily(worked: worked, regular: min(worked, 480),
                     overtime: min(max(0, worked - 480), 240),
                     double: max(0, worked - 720), night: night, pto: pto)
    }

    private func weekly(_ employee: Employee, _ week: Int) -> ([Int], Int) {
        var totals = [Int](repeating: 0, count: 5)
        for day in (7 * week - 6)...(7 * week) {
            let values = daily(employee, day).classified
            for i in totals.indices { totals[i] += values[i] }
        }
        let overtime = max(0, totals[0] - 2400)
        totals[0] -= overtime
        totals[1] += overtime
        return (totals, overtime)
    }

    private func breakdown(_ employee: Employee, _ period: Int) -> [Int] {
        let first = weekly(employee, 2 * period - 1).0
        let second = weekly(employee, 2 * period).0
        return zip(first, second).map { $0.0 + $0.1 }
    }

    private func calculate(_ employee: Employee, _ period: Int) -> Stub? {
        var stub = Stub()
        if employee.kind == "HOURLY" {
            let hours = breakdown(employee, period)
            for i in 0..<5 { stub[fields[i]] = hours[i] }
            let weighted = 2 * (hours[0] + hours[4]) + 3 * hours[1] + 4 * hours[2]
            stub["earnings"] = (weighted * employee.base +
                                2 * hours[3] * settings["NIGHT"]!) / 120
        } else if employee.kind == "SALARIED" {
            if employee.active {
                stub["salary"] = employee.base / 26
                stub["leave"] = employee.leave.filter {
                    periodOf($0) == period && !holidays.contains($0)
                }.count
                stub["deduction"] = stub["leave"] * (employee.base / 260)
                stub["earnings"] = stub["salary"] - stub["deduction"]
            }
        } else {
            stub["sales"] = employee.sales[period] ?? 0
            stub["commission"] = progressive(tiers, stub["sales"])
            stub["earnings"] = stub["commission"] + (employee.active ? employee.base : 0)
        }

        stub["bonus"] = employee.bonus
        let gross = stub["earnings"] + stub["bonus"]
        if gross == 0 { return nil }
        stub["gross"] = gross
        var remaining = gross

        func deduct(_ field: String, _ amount: Int) {
            let value = min(amount, remaining)
            stub[field] = value
            remaining -= value
        }

        let retirementRoom = max(0, settings["RETIRECAP"]! - employee.ytd["retirement"]!)
        deduct("retirement", min(gross * employee.retirement / 10000, retirementRoom))
        deduct("health", employee.health)
        stub["W"] = remaining
        let baseTaxable = max(0, stub["earnings"] - stub["retirement"] - stub["health"])
        let allowanceTaxable = max(0, baseTaxable - employee.allowances * settings["ALLOWANCE"]!)
        deduct("federal", progressive(brackets, allowanceTaxable) + employee.extra)
        deduct("supplemental", (stub["W"] - baseTaxable) * settings["SUPP"]! / 10000)
        deduct("state", stub["W"] * settings["STATE"]! / 10000)

        let medicareWages = gross - stub["health"]
        let socialWages = min(medicareWages,
                              max(0, settings["SSBASE"]! - employee.ytd["Y"]!))
        let additional = max(0, min(medicareWages,
                                    employee.ytd["F"]! + medicareWages - settings["ADDBASE"]!))
        stub["F"] = medicareWages
        stub["Y"] = socialWages
        deduct("social", socialWages * settings["SSRATE"]! / 10000)
        deduct("medicare", medicareWages * settings["MEDRATE"]! / 10000 +
               additional * settings["ADDMED"]! / 10000)

        let disposable = remaining
        let cap = disposable * settings["GARNCAP"]! / 10000
        var garnished = 0
        for order in employee.garnishments {
            let taken = min(disposable * order.rate / 10000,
                            order.balance, cap - garnished)
            garnished += taken
            stub.balances.append(order.balance - taken)
        }
        stub["garnishment"] = garnished
        stub.garnishmentBalance = stub.balances.reduce(0, +)
        stub["net"] = remaining - garnished
        stub["employer_social"] = socialWages * settings["SSRATE"]! / 10000
        stub["employer_medicare"] = medicareWages * settings["MEDRATE"]! / 10000
        stub["J"] = min(medicareWages, max(0, settings["UIBASE"]! - employee.ytd["J"]!))
        stub["unemployment"] = stub["J"] * settings["UIRATE"]! / 10000
        let eligibleMatch = min(stub["retirement"], gross * settings["MATCHMAX"]! / 10000)
        stub["match"] = eligibleMatch * settings["MATCH"]! / 10000
        stub["employer"] = stub["employer_social"] + stub["employer_medicare"] +
                           stub["unemployment"] + stub["match"]
        if employee.kind == "HOURLY" {
            stub["accrued"] = min(960 - employee.ptoBalance,
                                  (stub["R"] + stub["O"] + stub["D"]) / 20)
        }
        stub.ptoBalance = employee.ptoBalance + stub["accrued"]
        return stub
    }

    private func hoursParts(_ values: [Int]) -> [Any] {
        let labels = ["reg", "ot", "dbl", "night", "pto"]
        var parts: [Any] = []
        for (label, minutes) in zip(labels, values) {
            parts += [label, duration(minutes)]
        }
        return parts
    }

    private func stubBlock(_ employee: Employee, _ values: [String: Int],
                           ptoBalance: Int, garnishmentBalance: Int, indent: Int) {
        func value(_ field: String) -> Int { values[field, default: 0] }
        if employee.kind == "HOURLY" {
            putParts(indent, ["hours"] + hoursParts(["R", "O", "D", "N", "P"].map(value)))
            put(indent, "pto", "accrued", duration(value("accrued")),
                "balance", duration(ptoBalance))
        } else if employee.kind == "SALARIED" {
            put(indent, "salary", money(value("salary")), "leave", value("leave"),
                "deduction", money(value("deduction")))
        } else {
            put(indent, "sales", money(value("sales")),
                "commission", money(value("commission")))
        }
        for field in [
            "earnings", "bonus", "gross", "retirement", "health", "federal",
            "supplemental", "state", "social", "medicare"
        ] {
            put(indent, field == "social" ? "social-security" : field, money(value(field)))
        }
        put(indent, "garnishment", money(value("garnishment")),
            "balance", money(garnishmentBalance))
        put(indent, "net", money(value("net")))
        put(indent, "employer", "social-security", money(value("employer_social")),
            "medicare", money(value("employer_medicare")),
            "unemployment", money(value("unemployment")),
            "match", money(value("match")))
    }

    private func printStub(_ employee: Employee, _ period: Int,
                           _ stub: Stub, _ department: String) {
        put(2, "STUB", employee.id, department, employee.kind, "period", period)
        stubBlock(employee, stub.values, ptoBalance: stub.ptoBalance,
                  garnishmentBalance: stub.garnishmentBalance, indent: 4)
    }

    private func showHours(_ employee: Employee, _ period: Int) {
        put(0, "HOURS", employee.id, "period", period)
        var found = false
        for day in (14 * period - 13)...(14 * period) {
            let shifts = (employee.shifts[day] ?? []).sorted { $0.start < $1.start }
            if shifts.isEmpty && employee.pto[day] == nil { continue }
            let daily = daily(employee, day)
            var parts: [Any] = ["day", day, weekday(day)]
            if holidays.contains(day) { parts.append("holiday") }
            for shift in shifts {
                parts.append("\(clock(shift.start))-\(clock(shift.end))")
            }
            parts += ["total", duration(daily.worked)]
            parts += hoursParts(daily.classified)
            putParts(2, parts)
            found = true
        }
        if !found { put(2, "(none)") }
        for week in [2 * period - 1, 2 * period] {
            let (values, overtime) = weekly(employee, week)
            putParts(2, ["week", week] + hoursParts(values) +
                     ["weekly-ot", duration(overtime)])
        }
        putParts(2, ["total"] + hoursParts(breakdown(employee, period)))
    }

    private func run(_ period: Int) {
        closed = period
        put(0, "RUN", period, "days", "\(14 * period - 13)-\(14 * period)")
        var paid = 0, skipped = 0
        var stubs: [[String: Int]] = []
        for id in employees.keys.sorted() {
            let employee = employees[id]!
            guard let stub = calculate(employee, period) else {
                if employee.active { skipped += 1 }
                continue
            }
            printStub(employee, period, stub, employee.department)
            employee.bonus = 0
            employee.ptoBalance = stub.ptoBalance
            for i in employee.garnishments.indices {
                employee.garnishments[i].balance = stub.balances[i]
            }
            for field in fields {
                employee.ytd[field, default: 0] += stub[field]
            }
            employee.periods += 1
            employee.stubs[period] = StubRecord(stub: stub, department: employee.department)
            stubs.append(stub.values)
            paid += 1
        }
        let totals = sumStubs(stubs)
        let gross = totals["gross"]!
        let net = totals["net"]!
        put(2, "TOTAL", "paid", paid, "skipped", skipped, "gross", money(gross),
            "deductions", money(gross - net), "net", money(net),
            "employer", money(totals["employer"]!))
    }

    private func journal(_ period: Int) {
        let stubs = employees.values.compactMap { $0.stubs[period]?.stub.values }
        let totals = sumStubs(stubs)
        func v(_ key: String) -> Int { totals[key, default: 0] }
        let rows: [(String, String, Int)] = [
            ("debit", "wages", v("gross")),
            ("debit", "employer-tax",
                v("employer_social") + v("employer_medicare") + v("unemployment")),
            ("debit", "retirement-match", v("match")),
            ("credit", "retirement", v("retirement") + v("match")),
            ("credit", "health", v("health")),
            ("credit", "federal", v("federal") + v("supplemental")),
            ("credit", "state", v("state")),
            ("credit", "fica", v("social") + v("medicare") +
                v("employer_social") + v("employer_medicare")),
            ("credit", "unemployment", v("unemployment")),
            ("credit", "garnishment", v("garnishment")),
            ("credit", "net-pay", v("net"))
        ]
        put(0, "JOURNAL", period, "stubs", stubs.count)
        var debit = 0, credit = 0
        for (side, name, amount) in rows {
            put(2, side, name, money(amount))
            if side == "debit" { debit += amount } else { credit += amount }
        }
        put(2, "total", "debit", money(debit), "credit", money(credit))
    }

    private func reportLine(_ department: String, _ stubs: [[String: Int]]) {
        let totals = sumStubs(stubs)
        func v(_ field: String) -> Int { totals[field, default: 0] }
        let taxes = v("federal") + v("supplemental") + v("state") +
                    v("social") + v("medicare")
        put(2, department, "stubs", stubs.count, "gross", money(v("gross")),
            "pretax", money(v("retirement") + v("health")), "taxes", money(taxes),
            "garnishment", money(v("garnishment")), "net", money(v("net")),
            "employer", money(v("employer")))
    }

    private func command(_ cmd: String, _ a: [String]) throws {
        switch cmd {
        case "SET":
            guard let previous = settings[a[0]] else {
                throw PayrollError("unknown setting \(a[0])")
            }
            let rate = rateSettings.contains(a[0])
            let value = try rate ? checkRate(a[1]) : cents(a[1])
            settings[a[0]] = value
            put(0, "SET", a[0], rate ? rateText(previous) : money(previous),
                "->", rate ? rateText(value) : money(value))

        case "BRACKET", "TIER":
            let rate = try checkRate(a[1])
            let lower = cents(a[0])
            let replaced = cmd == "BRACKET" ? brackets[lower] != nil : tiers[lower] != nil
            if cmd == "BRACKET" { brackets[lower] = rate }
            else { tiers[lower] = rate }
            put(0, cmd, money(lower), rateText(rate), replaced ? "replaced" : "added")

        case "EMP":
            let id = Int(a[0])!
            if employees[id] != nil { throw PayrollError("duplicate employee \(a[0])") }
            let amount = try checkAmount(a[3])
            employees[id] = Employee(id: id, department: a[1], kind: a[2], base: amount)
            put(0, "EMP", id, a[1], a[2], money(amount))

        case "RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS":
            let person = try employee(a[0], active: true)
            switch cmd {
            case "RATE":
                let amount = try checkAmount(a[1])
                let previous = person.base
                person.base = amount
                put(0, "RATE", person.id, money(previous), "->", money(amount))
            case "DEPT":
                if person.department == a[1] { throw PayrollError("same department \(a[1])") }
                let old = person.department
                person.department = a[1]
                put(0, "DEPT", person.id, old, "->", a[1])
            case "BENEFIT":
                let rate = try checkRate(a[1])
                person.retirement = rate
                person.health = cents(a[2])
                put(0, "BENEFIT", person.id, "retirement", rateText(rate),
                    "health", money(person.health))
            case "W4":
                person.allowances = Int(a[1])!
                person.extra = cents(a[2])
                put(0, "W4", person.id, "allowances", person.allowances,
                    "extra", money(person.extra))
            case "GARNISH":
                let rate = try checkRate(a[1])
                let amount = try checkAmount(a[2])
                person.garnishments.append(Garnishment(rate: rate, balance: amount))
                put(0, "GARNISH", person.id, "order", person.garnishments.count,
                    rateText(rate), "balance", money(amount))
            case "TERM":
                person.active = false
                put(0, "TERM", person.id)
            default:
                let amount = try checkAmount(a[1])
                person.bonus += amount
                put(0, "BONUS", person.id, money(amount), "pending", money(person.bonus))
            }

        case "HOLIDAY":
            let day = try checkDay(a[0])
            if holidays.contains(day) { throw PayrollError("duplicate holiday \(a[0])") }
            holidays.insert(day)
            put(0, "HOLIDAY", day, weekday(day))

        case "TIME", "UNTIME", "PTO", "LEAVE", "SALES":
            let kind = cmd == "LEAVE" ? "SALARIED" :
                       cmd == "SALES" ? "COMMISSION" : "HOURLY"
            let person = try employee(a[0], active: true, kind: kind)
            let day = try checkDay(a[1])
            switch cmd {
            case "TIME":
                let start = try checkTime(a[2])
                let end = try checkTime(a[3])
                if start >= end { throw PayrollError("invalid shift \(a[2])-\(a[3])") }
                let shifts = (person.shifts[day] ?? []).sorted { $0.start < $1.start }
                for shift in shifts {
                    if start < shift.end && shift.start < end {
                        throw PayrollError("overlapping shift \(clock(shift.start))-\(clock(shift.end))")
                    }
                }
                if shifts.reduce(0, { $0 + $1.end - $1.start }) + end - start > 960 {
                    throw PayrollError("daily limit \(a[0]) \(a[1])")
                }
                person.shifts[day, default: []].append(Shift(start: start, end: end))
                put(0, "TIME", person.id, "day", day,
                    "\(clock(start))-\(clock(end))", duration(end - start))
            case "UNTIME":
                let start = try checkTime(a[2])
                let oldShifts = person.shifts[day] ?? []
                guard let index = oldShifts.firstIndex(where: { $0.start == start }) else {
                    throw PayrollError("no shift \(a[0]) \(a[1]) \(a[2])")
                }
                let removed = oldShifts[index]
                person.shifts[day]!.remove(at: index)
                put(0, "UNTIME", person.id, "day", day,
                    "\(clock(removed.start))-\(clock(removed.end))")
            case "PTO":
                let parts = a[2].split(separator: ":")
                let hour = Int(parts[0])!, minute = Int(parts[1])!
                let length = hour * 60 + minute
                if minute > 59 || length < 1 || length > 480 {
                    throw PayrollError("invalid duration \(a[2])")
                }
                if person.pto[day] != nil { throw PayrollError("duplicate pto \(a[0]) \(a[1])") }
                if length > person.ptoBalance {
                    throw PayrollError("insufficient pto \(a[0]) \(duration(person.ptoBalance))")
                }
                person.pto[day] = length
                person.ptoBalance -= length
                put(0, "PTO", person.id, "day", day, duration(length),
                    "balance", duration(person.ptoBalance))
            case "LEAVE":
                if day % 7 == 0 || day % 7 == 6 || holidays.contains(day) {
                    throw PayrollError("not workday \(a[1])")
                }
                if person.leave.contains(day) {
                    throw PayrollError("duplicate leave \(a[0]) \(a[1])")
                }
                person.leave.insert(day)
                put(0, "LEAVE", person.id, "day", day, weekday(day))
            default:
                let amount = try checkAmount(a[2])
                let period = periodOf(day)
                person.sales[period, default: 0] += amount
                put(0, "SALES", person.id, "day", day, money(amount),
                    "period", period, "total", money(person.sales[period]!))
            }

        case "HOURS":
            let person = try employee(a[0], kind: "HOURLY")
            showHours(person, try checkPeriod(a[1]))

        case "RUN":
            let period = Int(a[0])!
            if period != closed + 1 || period > 26 {
                throw PayrollError("invalid period \(a[0])")
            }
            run(period)

        case "PREVIEW":
            let person = try employee(a[0])
            let period = closed + 1
            let stub = calculate(person, period)
            put(0, "PREVIEW", person.id, "period", period)
            if let stub { printStub(person, period, stub, person.department) }
            else { put(2, "no pay") }

        case "REPRINT":
            let person = try employee(a[0])
            let period = try checkPeriod(a[1])
            guard let record = person.stubs[period] else {
                throw PayrollError("no stub \(a[0]) \(a[1])")
            }
            put(0, "REPRINT", person.id, period)
            printStub(person, period, record.stub, record.department)

        case "YTD":
            let person = try employee(a[0])
            put(0, "YTD", person.id, person.department, person.kind,
                person.active ? "active" : "terminated", "periods", person.periods)
            stubBlock(person, person.ytd, ptoBalance: person.ptoBalance,
                      garnishmentBalance: person.garnishmentBalance, indent: 2)
            put(2, "wages", "federal", money(person.ytd["W"]!),
                "social-security", money(person.ytd["Y"]!),
                "medicare", money(person.ytd["F"]!),
                "unemployment", money(person.ytd["J"]!))
            put(2, "retirement-room",
                money(max(0, settings["RETIRECAP"]! - person.ytd["retirement"]!)),
                "pending-bonus", money(person.bonus))

        case "JOURNAL":
            let period = Int(a[0])!
            if period < 1 || period > closed { throw PayrollError("no run \(a[0])") }
            journal(period)

        case "REPORT":
            var departments: [String: [[String: Int]]] = [:]
            var all: [[String: Int]] = []
            for person in employees.values {
                for record in person.stubs.values {
                    departments[record.department, default: []].append(record.stub.values)
                    all.append(record.stub.values)
                }
            }
            put(0, "REPORT", "period", closed)
            for department in departments.keys.sorted() {
                reportLine(department, departments[department]!)
            }
            reportLine("total", all)

        case "TOP":
            let count = Int(a[0])!
            let ranking = employees.values.filter { $0.periods > 0 }
                .sorted {
                    let left = $0.ytd["gross"]!, right = $1.ytd["gross"]!
                    return left == right ? $0.id < $1.id : left > right
                }
            put(0, "TOP", count)
            for (index, person) in ranking.prefix(count).enumerated() {
                put(2, index + 1, person.id, person.department, "gross",
                    money(person.ytd["gross"]!), "net", money(person.ytd["net"]!))
            }
            if ranking.isEmpty { put(2, "(none)") }

        case "EMPLOYEES":
            put(0, "EMPLOYEES")
            for id in employees.keys.sorted() {
                let person = employees[id]!
                put(2, person.id, person.department, person.kind, money(person.base),
                    person.active ? "active" : "terminated",
                    "retirement", rateText(person.retirement),
                    "health", money(person.health), "allowances", person.allowances,
                    "extra", money(person.extra), "bonus", money(person.bonus))
                for (index, order) in person.garnishments.enumerated() {
                    put(4, "garnish", index + 1, rateText(order.rate),
                        "balance", money(order.balance))
                }
            }
            if employees.isEmpty { put(2, "(none)") }

        case "CONFIG":
            put(0, "CONFIG")
            for (name, _) in initialSettings {
                let value = settings[name]!
                put(2, name, rateSettings.contains(name) ? rateText(value) : money(value))
            }
            for (lower, rate) in brackets.sorted(by: { $0.key < $1.key }) {
                put(2, "bracket", money(lower), rateText(rate))
            }
            for (lower, rate) in tiers.sorted(by: { $0.key < $1.key }) {
                put(2, "tier", money(lower), rateText(rate))
            }
        default:
            break
        }
    }

    func execute(_ line: String) {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first else { return }
        do {
            try self.command(command, Array(words.dropFirst()))
        } catch let error as PayrollError {
            put(0, "ERROR", error.message)
        } catch {
            fatalError("Unexpected payroll error: \(error)")
        }
    }
}

let count = Int(readLine()!)!
let payroll = Payroll()
for _ in 0..<count {
    payroll.execute(readLine()!)
}
for line in payroll.output { print(line) }
