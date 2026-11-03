import Foundation

let bondTypes = ["FIXED", "ZERO", "AMORT", "FRN"]
let bucketNames = ["0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+"]
let frequencies: Set<Int> = [1, 2, 4, 12]
let dayCounts: Set<String> = ["30/360", "30E/360", "ACT/360", "ACT/365F", "ACT/ACT"]
let businessRules: Set<String> = ["FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED"]

func roundRatio(_ numerator: Int, _ denominator: Int) -> Int { (2 * numerator + denominator) / (2 * denominator) }
func priceValue(_ text: String) -> Int { Int(text.replacingOccurrences(of: ".", with: ""))! }
func hundredths(_ value: Int) -> String {
    let magnitude = value < 0 ? -value : value
    let cents = String(magnitude % 100)
    return (value < 0 ? "-" : "") + "\(magnitude / 100)." + String(repeating: "0", count: 2 - cents.count) + cents
}
func decimal(_ value: Double, _ digits: Int) -> String {
    var scale = 1
    for _ in 0..<digits { scale *= 10 }
    let magnitude = Int((value < 0 ? -value : value) * Double(scale) + 0.5)
    let fraction = String(magnitude % scale)
    return (value < 0 && magnitude != 0 ? "-" : "") + "\(magnitude / scale)." + String(repeating: "0", count: digits - fraction.count) + fraction
}
func percent(_ value: Double) -> String { decimal(value * 100, 4) }
func amount(_ value: Double) -> String { decimal(value / 100, 2) }
func maturityBucket(_ days: Int) -> Int {
    if days < 365 { return 0 }
    if days < 1095 { return 1 }
    if days < 1825 { return 2 }
    if days < 3650 { return 3 }
    return 4
}

struct InputProblem: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
struct ScheduleOption { let date: String; let value: Int }
struct Call { let date: Int; let price: Int }
struct Fixing { let date: Int; let rate: Int }
struct Scenario { let name: String; let shifts: [Int] }
struct Limit { let kind: String; let arguments: [String] }
struct BondOptions {
    var eom = false
    var longStub = false
    var lag = 0
    var cap = 1200
    var floor = 0
    var sinks: [ScheduleOption] = []
    var calls: [ScheduleOption] = []
}
struct Payment {
    let period: Int
    let start: Int
    let end: Int
    let payment: Int
    let fraction: Fraction
    let rate: Int
    let outstanding: Int
    let coupon: Int
    let principal: Int
    var cashFlow: Int { coupon + principal }
}
struct Bond {
    let code: String
    let type: String
    let issue: Int
    let maturity: Int
    let frequency: Int
    let daycount: String
    let face: Int
    let calls: [Call]
    let periods: [Payment]
}

func parseOptions(_ type: String, text: String) throws -> BondOptions {
    var result = BondOptions()
    let extra: Set<String>
    switch type {
    case "FIXED": extra = ["CALL"]
    case "AMORT": extra = ["SINK"]
    case "FRN": extra = ["LAG", "CAP", "FLOOR"]
    default: extra = []
    }
    let allowed = extra.union(["EOM", "LONG"])
    var seen: Set<String> = []
    if text != "-" {
        for item in text.components(separatedBy: ";") {
            let parts = item.components(separatedBy: "=")
            let key = parts[0]
            if !allowed.contains(key) || seen.contains(key) && key != "SINK" && key != "CALL" { throw InputProblem("invalid option") }
            seen.insert(key)
            let value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "EOM": result.eom = true
            case "LONG": result.longStub = true
            case "LAG": result.lag = Int(value)!
            case "CAP": result.cap = Int(value)!
            case "FLOOR": result.floor = Int(value)!
            case "SINK", "CALL":
                let fields = value.components(separatedBy: ":")
                let entry = ScheduleOption(date: fields[0], value: key == "CALL" ? priceValue(fields[1]) : Int(fields[1])!)
                if key == "SINK" { result.sinks.append(entry) } else { result.calls.append(entry) }
            default: break
            }
        }
    }
    if type == "FRN" && (!seen.contains("LAG") || !(1...5).contains(result.lag) || result.cap > 1200 || result.floor > result.cap) { throw InputProblem("invalid option") }
    return result
}

func fixingRate(_ fixings: [Fixing], day: Int) -> Int? {
    var lo = 0
    var hi = fixings.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if fixings[mid].date <= day { lo = mid + 1 } else { hi = mid }
    }
    return lo == 0 ? nil : fixings[lo - 1].rate
}

func buildBond(_ fields: [String], calendar: BusinessCalendar, fixings: [Fixing]) throws -> Bond {
    let code = fields[0]
    let type = fields[1]
    guard bondTypes.contains(type) else { throw InputProblem("unknown type") }
    guard validDate(fields[2]) && validDate(fields[3]) else { throw InputProblem("invalid date") }
    let issue = parseDate(fields[2])
    let maturity = parseDate(fields[3])
    guard maturity > issue else { throw InputProblem("maturity not after issue") }
    let coupon = Int(fields[4])!
    let frequency = Int(fields[5])!
    guard frequencies.contains(frequency) else { throw InputProblem("invalid frequency") }
    let daycount = fields[6]
    guard dayCounts.contains(daycount) else { throw InputProblem("unknown day count") }
    let bdc = fields[7]
    guard businessRules.contains(bdc) else { throw InputProblem("unknown business day rule") }
    let face = Int(fields[8])!
    guard face % 100000 == 0 && face <= 10000000 else { throw InputProblem("invalid face") }
    guard coupon <= 1200 && !(type == "ZERO" && coupon != 0) else { throw InputProblem("invalid coupon") }
    let options = try parseOptions(type, text: fields[9])
    let dates = couponSchedule(issue: issue, maturity: maturity, frequency: frequency, endOfMonth: options.eom, longStub: options.longStub)
    let intermediate = Set(dates.dropFirst().dropLast())
    var sinks: [Int: Int] = [:]
    var previous = -1
    var total = 0
    for entry in options.sinks {
        guard validDate(entry.date) else { throw InputProblem("invalid sinking fund") }
        let date = parseDate(entry.date)
        guard intermediate.contains(date) && date > previous && entry.value > 0 else { throw InputProblem("invalid sinking fund") }
        previous = date
        total += entry.value
        sinks[date] = entry.value
    }
    if type == "AMORT" && (total == 0 || total >= face) { throw InputProblem("invalid sinking fund") }
    var calls: [Call] = []
    previous = -1
    for entry in options.calls {
        guard validDate(entry.date) else { throw InputProblem("invalid call schedule") }
        let date = parseDate(entry.date)
        guard intermediate.contains(date) && date > previous && (100000...110000).contains(entry.value) else { throw InputProblem("invalid call schedule") }
        previous = date
        calls.append(Call(date: date, price: entry.value))
    }
    var periods: [Payment] = []
    var outstanding = face
    for index in 1..<dates.count {
        let start = dates[index - 1]
        let end = dates[index]
        let fraction = yearFraction(daycount, start: start, end: end)
        var rate = type == "ZERO" ? 0 : coupon
        if type == "FRN" {
            let fixingDay = calendar.move(calendar.adjust(start, rule: bdc), count: options.lag, direction: -1)
            guard let fixing = fixingRate(fixings, day: fixingDay) else { throw InputProblem("missing fixing") }
            rate = min(max(rate + fixing, options.floor), options.cap)
        }
        let principal = index == dates.count - 1 ? outstanding : sinks[end, default: 0]
        let interest = roundRatio(outstanding * rate * fraction.numerator, 10000 * fraction.denominator)
        periods.append(Payment(period: index, start: start, end: end, payment: calendar.adjust(end, rule: bdc), fraction: fraction, rate: rate, outstanding: outstanding, coupon: interest, principal: principal))
        outstanding -= principal
    }
    return Bond(code: code, type: type, issue: issue, maturity: maturity, frequency: frequency, daycount: daycount, face: face, calls: calls, periods: periods)
}

struct Analytics {
    let bond: Bond
    let price: Int
    let remaining: [Payment]
    let outstanding: Int
    let accrued: Double
    let accruedAmount: Int
    let cleanAmount: Int
    let unitValue: Int
    let target: Double
    let ytm: Double
    let risk: RiskMeasures
    let ytw: Double
    let workout: Int
    let cashPeriods: [Payment]
    let flows: [CurveFlow]
    let nextPayment: Int
    let wal: Double
    let curveClean: Double
    let zspread: Double

    init(bond: Bond, price: Int, settlement: Int, curve: ZeroCurve) throws {
        let current = bond.periods.firstIndex { $0.end > settlement }!
        let remaining = Array(bond.periods.dropFirst(current))
        let outstanding = remaining[0].outstanding
        let accruedFraction = yearFraction(bond.daycount, start: remaining[0].start, end: settlement)
        let accrued = Double(remaining[0].rate) * Double(accruedFraction.numerator) / (100 * Double(accruedFraction.denominator))
        let accruedAmount = roundRatio(outstanding * remaining[0].rate * accruedFraction.numerator, 10000 * accruedFraction.denominator)
        let cleanAmount = roundRatio(outstanding * price, 100000)
        let unitValue = cleanAmount + accruedAmount
        let target = Double(price) / 1000 + accrued
        let fraction = Double(bond.frequency) * yearFraction(bond.daycount, start: settlement, end: remaining[0].end).value
        let pricer = YieldPricer(flows: remaining.map { $0.cashFlow }, fraction: fraction, frequency: bond.frequency, outstanding: outstanding)
        guard pricer.inRange(target) else { throw InputProblem("yield out of range") }
        let ytm = pricer.solve(target)
        var ytw = ytm
        var workout = bond.maturity
        for call in bond.calls where call.date > settlement {
            let periods = Array(remaining.prefix { $0.end <= call.date })
            var cashFlows = periods.map { $0.coupon }
            cashFlows[cashFlows.count - 1] += roundRatio(periods[periods.count - 1].outstanding * call.price, 100000)
            let callYield = YieldPricer(flows: cashFlows, fraction: fraction, frequency: bond.frequency, outstanding: outstanding).solve(target)
            if callYield < ytw { ytw = callYield; workout = call.date }
        }
        let cashPeriods = remaining.filter { $0.cashFlow > 0 }
        let flows = cashPeriods.map { CurveFlow(days: $0.payment - settlement, amount: Double($0.cashFlow)) }
        var weightedPrincipal = 0.0
        for period in cashPeriods { weightedPrincipal += Double(period.principal) * Double(period.payment - settlement) }
        self.bond = bond
        self.price = price
        self.remaining = remaining
        self.outstanding = outstanding
        self.accrued = accrued
        self.accruedAmount = accruedAmount
        self.cleanAmount = cleanAmount
        self.unitValue = unitValue
        self.target = target
        self.ytm = ytm
        risk = pricer.risk(ytm)
        self.ytw = ytw
        self.workout = workout
        self.cashPeriods = cashPeriods
        self.flows = flows
        nextPayment = cashPeriods[0].payment
        wal = weightedPrincipal / (365 * Double(outstanding))
        curveClean = curve.presentValue(flows) * 100 / Double(outstanding) - accrued
        zspread = curve.zSpread(flows, target: Double(unitValue))
    }
}

struct Position {
    let analytics: Analytics
    var units = 0
    var book = 0
    var bond: Bond { analytics.bond }
    var value: Int { units * analytics.unitValue }
    var face: Int { units * bond.face }
    var outstanding: Int { units * analytics.outstanding }
    var gain: Int { units * analytics.cleanAmount - book }
    var dv01: Double { analytics.risk.dv01 * Double(units) * Double(analytics.outstanding) / 10000 }
    func curveValue(_ curve: ZeroCurve) -> Double { Double(units) * curve.presentValue(analytics.flows, spread: analytics.zspread) }
}

final class PortfolioReporter {
    let curve: ZeroCurve
    let settlement: Int
    let scenarios: [Scenario]
    let limits: [Limit]
    var report: [String] = []
    var scenarioLines = ["portfolio,scenario,bond,value,pnl"]
    var compliance: [String] = []

    init(curve: ZeroCurve, settlement: Int, scenarios: [Scenario], limits: [Limit]) {
        self.curve = curve; self.settlement = settlement; self.scenarios = scenarios; self.limits = limits
    }

    func write(_ name: String, positions: [Position]) {
        let totalValue = positions.reduce(0) { $0 + $1.value }
        func weighted(_ value: (Analytics) -> Double) -> Double {
            var total = 0.0
            for position in positions { total += Double(position.value) * value(position.analytics) }
            return total / Double(totalValue)
        }
        let ytm = weighted { $0.ytm }
        let modified = weighted { $0.risk.modified }
        let convexity = weighted { $0.risk.convexity }
        let zspread = weighted { $0.zspread }
        var dv01 = 0.0
        for position in positions { dv01 += position.dv01 }
        let flows = positions.flatMap { position in
            position.analytics.cashPeriods.map { CurveFlow(days: $0.payment - settlement, amount: Double(position.units * $0.cashFlow)) }
        }
        let cashYield = bisection(low: 0, high: 1, target: Double(totalValue)) { ZeroCurve(days: [0], rates: [$0]).presentValue(flows) }
        func values(_ shifted: ZeroCurve) -> [Double] { positions.map { $0.curveValue(shifted) } }
        func sum(_ values: [Double]) -> Double { var total = 0.0; for value in values { total += value }; return total }
        let base = values(curve)
        let baseValue = sum(base)
        let down = curve.shifted(Array(repeating: -0.0001, count: curve.days.count))
        let up = curve.shifted(Array(repeating: 0.0001, count: curve.days.count))
        let effective = (sum(values(down)) - sum(values(up))) / (2 * 0.0001 * baseValue)
        let krd = curve.days.indices.map { index -> Double in
            var delta = Array(repeating: 0.0, count: curve.days.count)
            delta[index] = -0.0001
            let lower = sum(values(curve.shifted(delta)))
            delta[index] = 0.0001
            return (lower - sum(values(curve.shifted(delta)))) / (2 * 0.0001 * baseValue)
        }
        report.append("portfolio \(name)")
        for position in positions {
            let a = position.analytics
            report.append("position \(position.bond.code) face \(hundredths(position.face)) outstanding \(hundredths(position.outstanding)) clean \(decimal(Double(a.price) / 1000, 6)) value \(hundredths(position.value)) weight \(decimal(Double(position.value) * 100 / Double(totalValue), 4)) book \(hundredths(position.book)) gain \(hundredths(position.gain)) ytm \(percent(a.ytm)) modified \(decimal(a.risk.modified, 4)) dv01 \(decimal(position.dv01, 2))")
        }
        var income = 0
        for position in positions {
            for period in position.analytics.cashPeriods where period.payment - settlement <= 365 { income += position.units * period.coupon }
        }
        report.append("total positions \(positions.count) face \(hundredths(positions.reduce(0) { $0 + $1.face })) outstanding \(hundredths(positions.reduce(0) { $0 + $1.outstanding })) value \(hundredths(totalValue)) book \(hundredths(positions.reduce(0) { $0 + $1.book })) gain \(hundredths(positions.reduce(0) { $0 + $1.gain })) income \(hundredths(income))")
        report.append("risk ytm \(percent(ytm)) yield \(percent(cashYield)) modified \(decimal(modified, 4)) convexity \(decimal(convexity, 4)) zspread \(percent(zspread)) dv01 \(decimal(dv01, 2))")
        report.append("curve effective \(decimal(effective, 4)) krd \(krd.map { decimal($0, 4) }.joined(separator: " "))")
        func groupLine(_ label: String, _ group: String, _ selected: [Position]) -> String {
            let value = selected.reduce(0) { $0 + $1.value }
            var duration = 0.0
            var risk = 0.0
            for position in selected { duration += Double(position.value) * position.analytics.risk.modified; risk += position.dv01 }
            return "\(label) \(group) positions \(selected.count) value \(hundredths(value)) weight \(decimal(Double(value) * 100 / Double(totalValue), 4)) duration \(decimal(duration / Double(totalValue), 4)) dv01 \(decimal(risk, 2))"
        }
        for type in bondTypes { report.append(groupLine("type", type, positions.filter { $0.bond.type == type })) }
        for index in bucketNames.indices { report.append(groupLine("bucket", bucketNames[index], positions.filter { maturityBucket($0.bond.maturity - settlement) == index })) }
        var ladder: [Int: (coupon: Int, principal: Int)] = [:]
        for position in positions {
            for period in position.analytics.cashPeriods {
                let year = civilDate(period.payment).year
                let previous = ladder[year] ?? (0, 0)
                ladder[year] = (previous.coupon + position.units * period.coupon, previous.principal + position.units * period.principal)
            }
        }
        var coupons = 0
        var principal = 0
        for year in ladder.keys.sorted() {
            let totals = ladder[year]!
            coupons += totals.coupon
            principal += totals.principal
            report.append("ladder \(year) coupon \(hundredths(totals.coupon)) principal \(hundredths(totals.principal)) total \(hundredths(totals.coupon + totals.principal))")
        }
        report.append("ladder total coupon \(hundredths(coupons)) principal \(hundredths(principal)) total \(hundredths(coupons + principal))")
        var worst: (name: String, pnl: Double, positions: [Double])?
        for scenario in [Scenario(name: "BASE", shifts: Array(repeating: 0, count: curve.days.count))] + scenarios {
            let scenarioValues = scenario.name == "BASE" ? base : values(curve.shifted(scenario.shifts.map { Double($0) * 0.0001 }))
            let pnl = scenarioValues.indices.map { scenarioValues[$0] - base[$0] }
            for index in positions.indices { scenarioLines.append("\(name),\(scenario.name),\(positions[index].bond.code),\(amount(scenarioValues[index])),\(amount(pnl[index]))") }
            let portfolioPnl = sum(scenarioValues) - baseValue
            scenarioLines.append("\(name),\(scenario.name),*,\(amount(sum(scenarioValues))),\(amount(portfolioPnl))")
            if scenario.name != "BASE" && (worst == nil || portfolioPnl < worst!.pnl) { worst = (scenario.name, portfolioPnl, pnl) }
        }
        if let worst {
            let losers = positions.indices.sorted { worst.positions[$0] == worst.positions[$1] ? positions[$0].bond.code < positions[$1].bond.code : worst.positions[$0] < worst.positions[$1] }.prefix(3)
            report.append("stress worst \(worst.name) pnl \(amount(worst.pnl)) losers " + losers.map { "\(positions[$0].bond.code) \(amount(worst.positions[$0]))" }.joined(separator: " "))
        }
        var breaches = 0
        for limit in limits {
            let args = limit.arguments
            let details: String
            let breach: Bool
            switch limit.kind {
            case "position_weight":
                let position = positions.sorted { $0.value == $1.value ? $0.bond.code < $1.bond.code : $0.value > $1.value }[0]
                let threshold = Int(args[0])!
                breach = position.value * 10000 > threshold * totalValue
                details = "\(position.bond.code) \(decimal(Double(position.value) * 100 / Double(totalValue), 4)) limit \(hundredths(threshold))"
            case "type_weight":
                let value = positions.filter { $0.bond.type == args[0] }.reduce(0) { $0 + $1.value }
                let threshold = Int(args[1])!
                breach = value * 10000 > threshold * totalValue
                details = "\(args[0]) \(decimal(Double(value) * 100 / Double(totalValue), 4)) limit \(hundredths(threshold))"
            case "max_maturity":
                let years = Int(args[0])!
                let count = positions.filter { $0.bond.maturity - settlement > 365 * years }.count
                breach = count > 0
                details = "\(years)Y positions \(count)"
            case "min_yield":
                let threshold = Int(args[0])!
                breach = ytm * 10000 < Double(threshold)
                details = "\(percent(ytm)) limit \(hundredths(threshold))"
            case "duration":
                let low = Int(args[0])!
                let high = Int(args[1])!
                breach = modified < Double(low) / 100 || modified > Double(high) / 100
                details = "\(decimal(modified, 4)) range \(hundredths(low)) \(hundredths(high))"
            default:
                let threshold = Int(args[0])!
                breach = dv01 * 100 > Double(threshold)
                details = "\(decimal(dv01, 2)) limit \(hundredths(threshold))"
            }
            if breach { breaches += 1 }
            compliance.append("\(name) \(limit.kind) \(details) \(breach ? "BREACH" : "PASS")")
        }
        compliance.append("\(name) breaches \(breaches)")
    }
}

func readLines(_ name: String) throws -> [String] {
    Array(try String(contentsOfFile: "input/\(name)", encoding: .utf8).components(separatedBy: "\n").dropLast())
}
func csvRows(_ name: String) throws -> [(line: Int, fields: [String])] {
    try readLines(name).dropFirst().enumerated().map { ($0.offset + 2, $0.element.components(separatedBy: ",")) }
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}

func runBondAnalytics() throws {
    let parameters = try readLines("params.txt").map { $0.components(separatedBy: " ") }
    let valuation = parseDate(parameters.first { $0[0] == "valuation_date" }![1])
    let calendar = BusinessCalendar(holidays: Set(try readLines("calendar.txt").map(parseDate)))
    let settlement = calendar.move(valuation, count: Int(parameters.first { $0[0] == "settlement_days" }![1])!)
    let fixings = try csvRows("fixings.csv").map { Fixing(date: parseDate($0.fields[0]), rate: Int($0.fields[1])!) }
    var errors: [String] = []
    func error(_ file: String, _ line: Int, _ key: String, _ reason: String) { errors.append("\(file):\(line): \(key): \(reason)") }
    var pillars: [Pillar] = []
    var seenPillars: Set<String> = []
    for (line, fields) in try csvRows("curve_quotes.csv") {
        let reason: String?
        if !seenPillars.insert(fields[0]).inserted { reason = "duplicate pillar" }
        else if !validDate(fields[0]) { reason = "invalid date" }
        else if parseDate(fields[0]) <= settlement { reason = "pillar not after settlement" }
        else if !frequencies.contains(Int(fields[2])!) { reason = "invalid frequency" }
        else { reason = nil }
        if let reason { error("curve_quotes.csv", line, fields[0], reason) }
        else { pillars.append(Pillar(maturity: parseDate(fields[0]), coupon: Int(fields[1])!, frequency: Int(fields[2])!)) }
    }
    pillars.sort { $0.maturity < $1.maturity }
    var scenarios: [Scenario] = []
    var seenScenarios: Set<String> = []
    var limits: [Limit] = []
    for (index, words) in parameters.enumerated() {
        if words[0] == "limit" { limits.append(Limit(kind: words[1], arguments: Array(words.dropFirst(2)))) }
        if words[0] != "scenario" { continue }
        let reason: String?
        if !seenScenarios.insert(words[1]).inserted { reason = "duplicate scenario" }
        else if words.count - 2 != pillars.count { reason = "wrong number of shifts" }
        else { reason = nil }
        if let reason { error("params.txt", index + 1, words[1], reason) }
        else { scenarios.append(Scenario(name: words[1], shifts: words.dropFirst(2).map { Int($0)! })) }
    }
    let curve = bootstrap(settlement: settlement, pillars: pillars)
    var bonds: [String: Bond] = [:]
    var seenBonds: Set<String> = []
    for (line, fields) in try csvRows("bonds.csv") {
        if !seenBonds.insert(fields[0]).inserted { error("bonds.csv", line, fields[0], "duplicate id"); continue }
        do { bonds[fields[0]] = try buildBond(fields, calendar: calendar, fixings: fixings) }
        catch let problem as InputProblem { error("bonds.csv", line, fields[0], problem.reason) }
    }
    var priced: [String: Analytics] = [:]
    var seenPrices: Set<String> = []
    for (line, fields) in try csvRows("prices.csv") {
        let duplicate = !seenPrices.insert(fields[0]).inserted
        guard let bond = bonds[fields[0]] else { error("prices.csv", line, fields[0], "unknown bond"); continue }
        if duplicate { error("prices.csv", line, fields[0], "duplicate price"); continue }
        if !(bond.issue <= settlement && settlement < bond.maturity) { error("prices.csv", line, fields[0], "not outstanding"); continue }
        do { priced[fields[0]] = try Analytics(bond: bond, price: priceValue(fields[1]), settlement: settlement, curve: curve) }
        catch let problem as InputProblem { error("prices.csv", line, fields[0], problem.reason) }
    }
    var portfolios: [String: [String: Position]] = [:]
    for (line, fields) in try csvRows("holdings.csv") {
        guard let bond = bonds[fields[1]] else { error("holdings.csv", line, fields[1], "unknown bond"); continue }
        guard let analytics = priced[fields[1]] else { error("holdings.csv", line, fields[1], "no price"); continue }
        let face = Int(fields[2])!
        guard face % bond.face == 0 else { error("holdings.csv", line, fields[1], "invalid face"); continue }
        let units = face / bond.face
        var positions = portfolios[fields[0]] ?? [:]
        var position = positions[fields[1]] ?? Position(analytics: analytics)
        position.units += units
        position.book += roundRatio(units * analytics.outstanding * priceValue(fields[3]), 100000)
        positions[fields[1]] = position
        portfolios[fields[0]] = positions
    }
    var cashflowLines = ["bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"]
    for code in bonds.keys.sorted() {
        let bond = bonds[code]!
        for period in bond.periods where period.cashFlow > 0 {
            cashflowLines.append("\(bond.code),\(period.period),\(dateText(period.start)),\(dateText(period.end)),\(dateText(period.payment)),\(decimal(period.fraction.value, 6)),\(period.rate),\(period.outstanding),\(period.coupon),\(period.principal)")
        }
    }
    var analyticsLines = ["bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"]
    for code in priced.keys.sorted() {
        let a = priced[code]!
        analyticsLines.append([a.bond.code, decimal(Double(a.price) / 1000, 6), decimal(a.accrued, 6), decimal(a.target, 6), percent(a.ytm), percent(a.ytw), dateText(a.workout), dateText(a.nextPayment), decimal(a.wal, 4), decimal(a.risk.macaulay, 4), decimal(a.risk.modified, 4), decimal(a.risk.convexity, 4), decimal(a.risk.dv01, 6), decimal(a.curveClean, 6), percent(a.zspread)].joined(separator: ","))
    }
    var curveLines = ["valuation \(dateText(valuation)) settlement \(dateText(settlement))"]
    for (index, pillar) in pillars.enumerated() {
        let days = pillar.maturity - settlement
        let previous = index == 0 ? 0 : pillars[index - 1].maturity - settlement
        curveLines.append("pillar \(dateText(pillar.maturity)) days \(days) frequency \(pillar.frequency) par \(hundredths(pillar.coupon)) zero \(percent(curve.rates[index])) df \(decimal(curve.discount(days), 6)) forward \(percent(curve.forward(start: previous, end: days)))")
    }
    let years = curve.days[curve.days.count - 1] / 365
    if years >= 1 {
        for year in 1...years {
            curveLines.append("grid \(year)Y days \(365 * year) zero \(percent(curve.zeroRate(365 * year))) df \(decimal(curve.discount(365 * year), 6)) forward \(percent(curve.forward(start: 365 * (year - 1), end: 365 * year)))")
        }
    }
    let reporter = PortfolioReporter(curve: curve, settlement: settlement, scenarios: scenarios, limits: limits)
    for name in portfolios.keys.sorted() {
        let positions = portfolios[name]!
        reporter.write(name, positions: positions.keys.sorted().map { positions[$0]! })
    }
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try writeLines("errors.txt", errors)
    try writeLines("cashflows.csv", cashflowLines)
    try writeLines("analytics.csv", analyticsLines)
    try writeLines("curve.txt", curveLines)
    try writeLines("portfolio.txt", reporter.report)
    try writeLines("scenarios.csv", reporter.scenarioLines)
    try writeLines("compliance.txt", reporter.compliance)
}

try runBondAnalytics()
