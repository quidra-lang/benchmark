import Foundation

let settingNames = ["CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF", "RESERVE", "COST",
                    "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"]
let settingRanges: [String: ClosedRange<Int>] = [
    "CAPACITY": 1...100000, "INITIAL": 0...100, "CHARGE": 1...20000,
    "DISCHARGE": 1...20000, "CEFF": 1...100, "DEFF": 1...100,
    "RESERVE": 0...100, "COST": 0...100000, "EXPORT": 0...100000,
    "FEEDIN": 0...10000, "FIXED": 0...100000, "DEMAND": 0...100000,
    "PVSCALE": 0...300
]
let strategyRanges = ["TOU": 1...100, "PEAKSHAVE": 0...100000, "BACKUP": 0...100]
let flowNames = ["PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
                 "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"]
let dayNames = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
typealias Settings = [String: Int]
typealias Prices = [String: Int]

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
func at(_ d: [String: Int], _ key: String) -> Int { d[key]! }
func sum(_ a: [Int]) -> Int { a.reduce(0, +) }
func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
func money(_ amount: Int) -> String {
    let n = abs(amount)
    return "\(amount < 0 ? "-" : "")\(n / 100).\(String(n % 100).leftPadded(2, by: "0"))"
}
func percentage(_ numerator: Int, _ denominator: Int) -> String {
    let value = denominator == 0 ? 0 : 10000 * numerator / denominator
    return "\(value / 100).\(String(value % 100).leftPadded(2, by: "0"))"
}
extension String {
    func leftPadded(_ width: Int, by character: String = " ") -> String {
        String(repeating: character, count: max(0, width - count)) + self
    }
}
func tableRow(_ fields: [String], _ widths: [Int]) -> String {
    zip(fields, widths).map { $0.leftPadded($1) }.joined()
}
func bar(_ width: Int) -> String { "|\(String(repeating: "#", count: width))\(String(repeating: ".", count: 20-width))|" }
func gcd(_ a: Int, _ b: Int) -> Int {
    var x = a, y = b
    while y != 0 { (x, y) = (y, x % y) }
    return x
}
func tariffExtremes(_ prices: Prices, _ names: [String]) -> (String, String) {
    var cheapest = names[0], peak = names[0]
    for name in names {
        if at(prices, name) < at(prices, cheapest) { cheapest = name }
        if at(prices, name) > at(prices, peak) { peak = name }
    }
    return (cheapest, peak)
}
struct Strategy {
    let name: String
    let parameter: Int?
    var text: String { parameter.map { "\(name) \($0)" } ?? name }
}
func parseStrategies(_ tokens: [String]) throws -> [Strategy] {
    var result: [Strategy] = []
    var i = 0
    while i < tokens.count {
        let name = tokens[i]; i += 1
        if name == "SELF" || name == "EXPORTPEAK" {
            result.append(Strategy(name: name, parameter: nil))
            continue
        }
        guard let range = strategyRanges[name] else { throw CommandError("unknown strategy \(name)") }
        guard i < tokens.count else { throw CommandError("missing parameter for \(name)") }
        let parameter = Int(tokens[i])!; i += 1
        guard range.contains(parameter) else { throw CommandError("invalid parameter for \(name)") }
        result.append(Strategy(name: name, parameter: parameter))
    }
    return result
}
func requireCount(_ tokens: [String], _ count: Int) throws {
    if tokens.count != count { throw CommandError("wrong number of arguments") }
}
func oneStrategy(_ tokens: [String]) throws -> Strategy {
    let strategies = try parseStrategies(tokens)
    if strategies.count != 1 { throw CommandError("wrong number of arguments") }
    return strategies[0]
}
func checkedRange(_ low: Int, _ high: Int, _ step: Int, _ bounds: ClosedRange<Int>) throws -> [Int] {
    guard step >= 1, low >= bounds.lowerBound, high <= bounds.upperBound, high >= low,
          (high-low)/step+1 <= 20 else { throw CommandError("invalid range") }
    return Array(stride(from: low, through: high, by: step))
}
func strings(_ a: [Int]) -> [String] { a.map(String.init) }

struct InputData {
    let initialSettings: Settings
    let initialPrices: Prices
    let periodNames: [String]
    let dayCount: Int
    let loads: [Int]
    let basePV: [Int]
    let dayNames: [String]
    let weekendDays: [Bool]
    let periods: [String]
    let commands: [String]

    init(_ lines: [String]) {
        var position = 0
        func read() -> [String] {
            let words = lines[position].split(separator: " ").map(String.init)
            position += 1
            return words
        }
        let battery = read().dropFirst().map { Int($0)! }
        let grid = read().dropFirst().map { Int($0)! }
        self.initialSettings = Dictionary(uniqueKeysWithValues: zip(settingNames, battery + grid + [100]))
        let periodCount = Int(read()[1])!
        var priceList: [String] = []
        var initialPrices: Prices = [:]
        for _ in 0..<periodCount {
            let pair = read()
            priceList.append(pair[0]); initialPrices[pair[0]] = Int(pair[1])!
        }
        self.initialPrices = initialPrices
        self.periodNames = priceList
        func periodHours(_ words: [String]) -> [String] {
            var hours: [String] = []
            for i in stride(from: 0, to: words.count, by: 2) {
                let start = Int(words[i])!
                let end = i+2 < words.count ? Int(words[i+2])! : 24
                hours += Array(repeating: words[i+1], count: end-start)
            }
            return hours
        }
        let weekday = periodHours(Array(read().dropFirst()))
        let weekend = periodHours(Array(read().dropFirst()))
        let profileCount = Int(read()[1])!
        var profiles: [String: [Int]] = [:]
        for _ in 0..<profileCount {
            let values = read()
            profiles[values[0] + "/" + values[1]] = values.dropFirst(2).map { Int($0)! }
        }
        let days = Int(read()[1])!
        self.dayCount = days
        var loads: [Int] = [], basePV: [Int] = []
        for _ in 0..<days {
            let row = read()
            let lpct = Int(row[1])!, ppct = Int(row[3])!
            loads += profiles["LOAD/" + row[0]]!.map { $0 * lpct / 100 }
            basePV += profiles["PV/" + row[2]]!.map { $0 * ppct / 100 }
        }
        let holidays = Set(read().dropFirst(2).map { Int($0)! })
        let overrideCount = Int(read()[1])!
        for _ in 0..<overrideCount {
            let row = read().map { Int($0)! }
            let index = (row[0]-1)*24 + row[1]
            loads[index] = row[2]; basePV[index] = row[3]
        }
        self.loads = loads; self.basePV = basePV
        var dnames: [String] = [], weekends: [Bool] = [], pnames: [String] = []
        for day in 1...days {
            let holiday = holidays.contains(day)
            let weekendDay = holiday || (day-1)%7 >= 5
            dnames.append(holiday ? "HOL" : SwiftDayName(day))
            weekends.append(weekendDay)
            pnames += weekendDay ? weekend : weekday
        }
        self.dayNames = dnames
        self.weekendDays = weekends
        self.periods = pnames
        self.commands = Array(lines.dropFirst(position))
    }
}
func SwiftDayName(_ day: Int) -> String { dayNames[(day-1)%7] }

struct HourRecord {
    let index: Int
    let period: String
    let load: Int
    let pv: Int
    let soc: Int
    let flows: [Int]
    let drawn: Int
    let shortfall: Int
    let loss: Int
    let importCost: Int
    let exportIncome: Int
    var day: Int { index/24 + 1 }
    var hour: Int { index%24 }
    var charge: Int { flows[1] + flows[7] }
    var discharge: Int { flows[4] + flows[5] }
    var imported: Int { flows[6] + flows[7] }
    var exported: Int { flows[2] + flows[5] }
    var curtailed: Int { flows[3] }
    var netCost: Int { importCost - exportIncome }
    init(_ index: Int, _ period: String, _ load: Int, _ pv: Int, _ soc: Int,
         _ flows: [Int], _ drawn: Int, _ shortfall: Int, _ loss: Int,
         _ price: Int, _ feedin: Int) {
        self.index=index; self.period=period; self.load=load; self.pv=pv
        self.soc=soc; self.flows=flows; self.drawn=drawn; self.shortfall=shortfall
        self.loss=loss
        self.importCost=(flows[6]+flows[7])*price/100000
        self.exportIncome=(flows[2]+flows[5])*feedin/100000
    }
}
struct Totals {
    let count: Int
    let load, pv, charge, discharge, imported, exported, curtailed: Int
    let drawn, loss, shortfall, importCost, exportIncome: Int
    let flows: [Int]
    var netCost: Int { importCost-exportIncome }
    init(_ records: [HourRecord]) {
        count=records.count
        load=records.reduce(0) { $0 + $1.load }
        pv=records.reduce(0) { $0 + $1.pv }
        charge=records.reduce(0) { $0 + $1.charge }
        discharge=records.reduce(0) { $0 + $1.discharge }
        imported=records.reduce(0) { $0 + $1.imported }
        exported=records.reduce(0) { $0 + $1.exported }
        curtailed=records.reduce(0) { $0 + $1.curtailed }
        drawn=records.reduce(0) { $0 + $1.drawn }
        loss=records.reduce(0) { $0 + $1.loss }
        shortfall=records.reduce(0) { $0 + $1.shortfall }
        importCost=records.reduce(0) { $0 + $1.importCost }
        exportIncome=records.reduce(0) { $0 + $1.exportIncome }
        flows=(0..<8).map { i in records.reduce(0) { $0 + $1.flows[i] } }
    }
}
struct SimulationResult {
    let strategy: Strategy
    let settings: Settings
    let prices: Prices
    let startSOC: Int
    let reserve: Int
    let hours: [HourRecord]
    let days: [[HourRecord]]
    let daily: [Totals]
    let byPeriod: [String: Totals]
    let total: Totals
    let peak: Int
    let demandCharge: Int
    let bill: Int
    let endSOC: Int
    let sufficiency: String
    init(_ strategy: Strategy, _ settings: Settings, _ prices: Prices,
         _ startSOC: Int, _ reserve: Int, _ records: [HourRecord]) {
        self.strategy=strategy; self.settings=settings; self.prices=prices
        self.startSOC=startSOC; self.reserve=reserve; hours=records
        days=stride(from: 0, to: records.count, by: 24).map { i in Array(records[i..<min(i+24, records.count)]) }
        daily=days.map(Totals.init)
        var byPeriod: [String: Totals] = [:]
        for name in prices.keys { byPeriod[name]=Totals(records.filter { $0.period==name }) }
        self.byPeriod=byPeriod
        total=Totals(records)
        peak=records.map(\.imported).max()!
        demandCharge=peak*at(settings, "DEMAND")/1000
        bill=total.netCost + at(settings, "FIXED") + demandCharge
        endSOC=records.last!.soc
        sufficiency=percentage(max(0, total.load-total.imported), total.load)
    }
}

final class Simulator {
    let data: InputData
    let strategy: Strategy
    let settings: Settings
    let prices: Prices
    let outage: ClosedRange<Int>?
    let capacity, ceff, deff, reserve, startSOC: Int
    let cheapest, peak: String
    let arbitrage: Bool
    var soc: Int
    init(_ data: InputData, _ strategy: Strategy, _ settings: Settings, _ prices: Prices,
         _ outage: ClosedRange<Int>? = nil) {
        self.data=data; self.strategy=strategy; self.settings=settings; self.prices=prices
        self.outage=outage
        capacity=at(settings, "CAPACITY"); ceff=at(settings, "CEFF"); deff=at(settings, "DEFF")
        let reservePct = strategy.name == "BACKUP" ? max(at(settings, "RESERVE"), strategy.parameter!) : at(settings, "RESERVE")
        reserve=capacity*reservePct/100
        startSOC=capacity*at(settings, "INITIAL")/100
        soc=startSOC
        (cheapest, peak)=tariffExtremes(prices, data.periodNames)
        arbitrage=strategy.name == "EXPORTPEAK" && at(settings, "FEEDIN") > at(prices, cheapest)
    }
    func dischargeTarget(_ deficit: Int, _ period: String) -> Int {
        if strategy.name == "TOU" { return period == peak ? deficit : 0 }
        if strategy.name == "PEAKSHAVE" { return max(0, deficit-strategy.parameter!) }
        if arbitrage && period == cheapest && period != peak { return 0 }
        return deficit
    }
    func gridCharge(_ period: String, _ pvCharge: Int, _ gridLoad: Int) -> Int {
        var headroom=at(settings, "CHARGE")-pvCharge
        var target: Int? = nil
        if strategy.name == "TOU" && period == cheapest && period != peak {
            target=capacity*strategy.parameter!/100
        } else if strategy.name == "PEAKSHAVE" && period == cheapest {
            target=capacity
            headroom=min(headroom, max(0, strategy.parameter!-gridLoad))
        } else if strategy.name == "BACKUP" && period == cheapest {
            target=reserve
        } else if arbitrage && period == cheapest && period != peak {
            target=capacity
        }
        guard let target=target else { return 0 }
        let amount=min(headroom, ceilDiv(100*max(0,target-soc), ceff))
        soc += amount*ceff/100
        return amount
    }
    func runHour(_ index: Int) -> HourRecord {
        let load=data.loads[index]
        let pv=data.basePV[index]*at(settings, "PVSCALE")/100
        let period=data.periods[index]
        let direct=min(load,pv)
        var surplus=pv-direct, deficit=load-direct
        let pvCharge=min(surplus,at(settings,"CHARGE"),ceilDiv(100*(capacity-soc),ceff))
        soc += pvCharge*ceff/100
        surplus -= pvCharge
        let isOutage=outage?.contains(index) ?? false
        let target=isOutage ? deficit : dischargeTarget(deficit,period)
        let lowerBound=isOutage ? 0 : reserve
        let loadDrawn=min(ceilDiv(100*target,deff), at(settings,"DISCHARGE"),max(0,soc-lowerBound))
        let loadDischarge=loadDrawn*deff/100
        soc -= loadDrawn
        deficit -= loadDischarge
        var gridLoad=0, shortfall=0, pvExport=0, curtailed=0, gridCharged=0
        var exportDrawn=0, batteryExport=0
        if isOutage {
            shortfall=deficit; curtailed=surplus
        } else {
            gridLoad=deficit
            pvExport=min(surplus,at(settings,"EXPORT"))
            curtailed=surplus-pvExport
            gridCharged=gridCharge(period,pvCharge,gridLoad)
            if arbitrage && period == peak && pvCharge == 0 {
                exportDrawn=min(ceilDiv(100*(at(settings,"EXPORT")-pvExport),deff),
                                at(settings,"DISCHARGE")-loadDrawn,max(0,soc-reserve))
                batteryExport=exportDrawn*deff/100
                soc -= exportDrawn
            }
        }
        let loss = pvCharge - pvCharge*ceff/100 + gridCharged - gridCharged*ceff/100
            + loadDrawn - loadDischarge + exportDrawn - batteryExport
        let flows=[direct,pvCharge,pvExport,curtailed,loadDischarge,batteryExport,gridLoad,gridCharged]
        return HourRecord(index,period,load,pv,soc,flows,loadDrawn+exportDrawn,shortfall,loss,
                          at(prices,period),at(settings,"FEEDIN"))
    }
    func run() -> SimulationResult {
        let records=(0..<data.loads.count).map(runHour)
        return SimulationResult(strategy,settings,prices,startSOC,reserve,records)
    }
}

final class DispatchDesk {
    let data: InputData
    var settings: Settings
    var prices: Prices
    var current: SimulationResult? = nil
    init(_ data: InputData) {
        self.data=data; settings=data.initialSettings; prices=data.initialPrices
    }
    func execute(_ tokens: [String]) -> [String] {
        let name=tokens[0], args=Array(tokens.dropFirst())
        let names: Set<String>=["RUN","SET","PRICE","RESET","CONFIG","NOBATTERY","COMPARE",
                                "SIZE","SWEEP","OUTAGE","DIFF","HOURLY","DAILY","BILL","SAVINGS",
                                "BYPERIOD","DAYTYPE","PEAKS","PROFILE","FLOWS","SELFSUFF","CYCLES",
                                "USAGE","HISTOGRAM","CHART"]
        if !names.contains(name) { return ["ERROR unknown command \(name)"] }
        do { return try command(name,args) }
        catch let error as CommandError { return ["ERROR \(error.message)"] }
        catch { fatalError("Unexpected execution failure: \(error)") }
    }
    func requireResult() throws -> SimulationResult {
        guard let result=current else { throw CommandError("no run") }
        return result
    }
    func checkedDay(_ text: String) throws -> Int {
        let day=Int(text)!
        if day < 1 || day > data.dayCount { throw CommandError("invalid day") }
        return day
    }
    func resultWithoutArguments(_ args: [String]) throws -> SimulationResult {
        try requireCount(args,0)
        return try requireResult()
    }
    func resultForDay(_ args: [String]) throws -> (Int,SimulationResult) {
        try requireCount(args,1)
        let day=try checkedDay(args[0])
        return (day,try requireResult())
    }
    func simulate(_ strategy: Strategy, _ settings: Settings? = nil,
                  _ prices: Prices? = nil, _ outage: ClosedRange<Int>? = nil) -> SimulationResult {
        Simulator(data,strategy,settings ?? self.settings,prices ?? self.prices,outage).run()
    }
    func baseline(_ settings: Settings, _ prices: Prices) -> SimulationResult {
        var settingCopy=settings
        settingCopy["CAPACITY"]=0
        return simulate(Strategy(name:"SELF",parameter:nil),settingCopy,prices)
    }
    func command(_ name: String, _ args: [String]) throws -> [String] {
        switch name {
        case "RUN":
            let strategy=try oneStrategy(args)
            let result=simulate(strategy)
            current=result
            let total=result.total
            return ["RUN \(strategy.text) bill \(money(result.bill)) import \(total.imported) export \(total.exported) soc \(result.endSOC)"]
        case "SET":
            try requireCount(args,2)
            let item=args[0]
            guard let range=settingRanges[item] else { throw CommandError("unknown parameter \(item)") }
            let value=Int(args[1])!
            guard range.contains(value) else { throw CommandError("invalid value for \(item)") }
            let old=at(settings,item)
            settings[item]=value
            return ["SET \(item) \(old) -> \(value)"]
        case "PRICE":
            try requireCount(args,2)
            let item=args[0], value=Int(args[1])!
            guard let old=prices[item] else { throw CommandError("unknown period \(item)") }
            guard (0...10000).contains(value) else { throw CommandError("invalid value for \(item)") }
            prices[item]=value
            let (low,high)=tariffExtremes(prices,data.periodNames)
            return ["PRICE \(item) \(old) -> \(value) cheapest \(low) peak \(high)"]
        case "RESET":
            try requireCount(args,0)
            settings=data.initialSettings; prices=data.initialPrices
            return ["RESET"]
        case "CONFIG":
            try requireCount(args,0)
            let battery=settingNames.prefix(8).map { "\($0.lowercased()) \(at(settings,$0))" }.joined(separator:" ")
            let grid=settingNames.dropFirst(8).prefix(4).map { "\($0.lowercased()) \(at(settings,$0))" }.joined(separator:" ")
            let tariff=data.periodNames.map { "\($0) \(at(prices,$0))" }.joined(separator:" ")
            let (low,high)=tariffExtremes(prices,data.periodNames)
            return ["BATTERY \(battery)","GRID \(grid)","SOLAR pvscale \(at(settings,"PVSCALE"))",
                    "TARIFF \(tariff) cheapest \(low) peak \(high)"]
        case "NOBATTERY":
            try requireCount(args,0)
            let result=baseline(settings,prices), total=result.total
            return ["NOBATTERY bill \(money(result.bill)) import \(total.imported) export \(total.exported) curtailed \(total.curtailed) peak \(result.peak)"]
        case "COMPARE":
            let strategies=try parseStrategies(args)
            if strategies.isEmpty { throw CommandError("wrong number of arguments") }
            let base=baseline(settings,prices)
            var trials: [(Int, SimulationResult)] = []
            for (index,strategy) in strategies.enumerated() { trials.append((index, simulate(strategy))) }
            trials.sort { lhs, rhs in
                if lhs.1.bill == rhs.1.bill { return lhs.0 < rhs.0 }
                return lhs.1.bill < rhs.1.bill
            }
            var output=["COMPARE baseline \(money(base.bill))"]
            for (index,trial) in trials.enumerated() {
                let result=trial.1
                output.append("\(index+1). \(result.strategy.text) bill \(money(result.bill)) saving \(money(base.bill-result.bill)) sufficiency \(result.sufficiency)%")
            }
            return output
        case "SIZE":
            try requireCount(args,3)
            let a=args.map { Int($0)! }
            let capacities=try checkedRange(a[0],a[1],a[2],settingRanges["CAPACITY"]!)
            let base=baseline(settings,prices)
            var output: [String]=[]
            var best: (capacity:Int,cost:Int,saving:Int)? = nil
            for capacity in capacities {
                var s=settings; s["CAPACITY"]=capacity
                let r=simulate(Strategy(name:"SELF",parameter:nil),s)
                let saving=base.bill-r.bill
                let cost=capacity*at(s,"COST")/1000
                var payback="never"
                if saving > 0 {
                    let tenths=10*cost/saving
                    payback="\(tenths/10).\(tenths%10)"
                    if best == nil || cost*best!.saving < best!.cost*saving {
                        best=(capacity,cost,saving)
                    }
                }
                output.append("SIZE \(capacity) bill \(money(r.bill)) saving \(money(saving)) cost \(money(cost)) payback \(payback)")
            }
            output.append("BEST \(best.map { String($0.capacity) } ?? "none")")
            return output
        case "SWEEP":
            guard args.count >= 5 else { throw CommandError("wrong number of arguments") }
            let item=args[0]
            guard let range=settingRanges[item] else { throw CommandError("unknown parameter \(item)") }
            let a=args[1...3].map { Int($0)! }
            let values=try checkedRange(a[0],a[1],a[2],range)
            let strategy=try oneStrategy(Array(args.dropFirst(4)))
            var output: [String]=[]
            var best: (value:Int,bill:Int)? = nil
            for value in values {
                var s=settings; s[item]=value
                let result=simulate(strategy,s)
                let base=baseline(s,prices)
                if best == nil || result.bill < best!.bill { best=(value,result.bill) }
                output.append("SWEEP \(item) \(value) bill \(money(result.bill)) saving \(money(base.bill-result.bill)) sufficiency \(result.sufficiency)%")
            }
            output.append("BEST \(best!.value)")
            return output
        case "OUTAGE":
            try requireCount(args,3)
            let day=try checkedDay(args[0])
            let start=Int(args[1])!, end=Int(args[2])!
            guard start >= 0 && end <= 23 && start <= end else { throw CommandError("invalid hours") }
            let prior=try requireResult()
            let first=(day-1)*24+start, last=(day-1)*24+end
            let result=simulate(prior.strategy,prior.settings,prior.prices,first...last)
            let soc=first == 0 ? result.startSOC : result.hours[first-1].soc
            var output=["OUTAGE day \(day) hours \(start)-\(end) strategy \(result.strategy.text) soc \(soc)",
                        "hour   load     pv  disch    soc  short   curt"]
            let records=Array(result.hours[first...last])
            for r in records {
                output.append(tableRow(strings([r.hour,r.load,r.pv,r.discharge,r.soc,r.shortfall,r.curtailed]),Array(repeating:7,count:7).enumerated().map { $0.offset == 0 ? 4 : $0.element }))
            }
            let t=Totals(records)
            let served=t.load != 0 ? percentage(t.load-t.shortfall,t.load) : "100.00"
            output.append("TOTAL load \(t.load) unserved \(t.shortfall) served \(served)% bill \(money(result.bill))")
            return output
        case "DIFF":
            guard args.count >= 2 else { throw CommandError("wrong number of arguments") }
            let day=try checkedDay(args[0])
            let strategy=try oneStrategy(Array(args.dropFirst()))
            let prior=try requireResult()
            let second=simulate(strategy,prior.settings,prior.prices)
            var output=["DIFF day \(day) \(data.dayNames[day-1]) \(prior.strategy.text) vs \(strategy.text)",
                        "hour   imp1   imp2   exp1   exp2   soc1   soc2"]
            for i in 0..<24 {
                let a=prior.days[day-1][i],b=second.days[day-1][i]
                output.append(tableRow(strings([a.hour,a.imported,b.imported,a.exported,b.exported,a.soc,b.soc]),[4,7,7,7,7,7,7]))
            }
            let cost1=prior.daily[day-1].netCost, cost2=second.daily[day-1].netCost
            output.append("TOTAL cost1 \(money(cost1)) cost2 \(money(cost2)) difference \(money(cost2-cost1))")
            return output
        case "HOURLY":
            let (day,result)=try resultForDay(args)
            var output=["HOURLY day \(day) \(data.dayNames[day-1]) strategy \(result.strategy.text)",
                        "hour   load     pv charge  disch    soc import export   curt"]
            let widths=[4]+Array(repeating:7,count:8)
            for r in result.days[day-1] {
                output.append(tableRow(strings([r.hour,r.load,r.pv,r.charge,r.discharge,r.soc,r.imported,r.exported,r.curtailed]),widths))
            }
            let t=result.daily[day-1]
            output.append(tableRow(["sum",String(t.load),String(t.pv),String(t.charge),String(t.discharge),"",String(t.imported),String(t.exported),String(t.curtailed)],widths))
            return output
        case "DAILY":
            let result=try resultWithoutArguments(args)
            var output=["DAILY strategy \(result.strategy.text)",
                        "day name    load      pv  import  export    curt     soc      cost"]
            for (index,t) in result.daily.enumerated() {
                let values=[String(index+1),data.dayNames[index],String(t.load),String(t.pv),String(t.imported),
                            String(t.exported),String(t.curtailed),String(result.days[index].last!.soc),money(t.netCost)]
                output.append(tableRow(values,[3,5,8,8,8,8,8,8,10]))
            }
            let t=result.total
            output.append("TOTAL load \(t.load) pv \(t.pv) import \(t.imported) export \(t.exported) curtailed \(t.curtailed) cost \(money(t.netCost))")
            return output
        default: return try additionalCommand(name,args)
        }
    }
    func additionalCommand(_ name: String, _ args: [String]) throws -> [String] {
        switch name {
        case "BILL":
            let result=try resultWithoutArguments(args)
            var output=["BILL strategy \(result.strategy.text) days \(data.dayCount)"]
            for period in data.periodNames {
                let total=result.byPeriod[period]!
                output.append("IMPORT \(period) \(total.imported) Wh \(money(total.importCost))")
            }
            let total=result.total
            output += ["EXPORT \(total.exported) Wh \(money(-total.exportIncome))",
                       "FIXED \(money(at(result.settings,"FIXED")))",
                       "DEMAND \(result.peak) Wh \(money(result.demandCharge))",
                       "TOTAL \(money(result.bill))"]
            return output
        case "SAVINGS":
            let result=try resultWithoutArguments(args)
            let base=baseline(result.settings,result.prices)
            var entries: [(String,Int,Int)] = []
            for period in data.periodNames {
                entries.append((period,base.byPeriod[period]!.importCost,result.byPeriod[period]!.importCost))
            }
            entries += [("EXPORT",-base.total.exportIncome,-result.total.exportIncome),
                        ("DEMAND",base.demandCharge,result.demandCharge),("TOTAL",base.bill,result.bill)]
            var output=["SAVINGS strategy \(result.strategy.text)"]
            for (label,before,after) in entries {
                output.append("\(label) \(money(before)) -> \(money(after)) saving \(money(before-after))")
            }
            return output
        case "BYPERIOD":
            let result=try resultWithoutArguments(args)
            var output=["BYPERIOD strategy \(result.strategy.text)"]
            for period in data.periodNames {
                let t=result.byPeriod[period]!
                output.append("\(period) hours \(t.count) load \(t.load) pv \(t.pv) charge \(t.charge) discharge \(t.discharge) import \(t.imported) export \(t.exported)")
            }
            return output
        case "DAYTYPE":
            let result=try resultWithoutArguments(args)
            var output=["DAYTYPE strategy \(result.strategy.text)"]
            for (label,weekend) in [("WEEKDAY",false),("WEEKEND",true)] {
                let indices=data.weekendDays.indices.filter { data.weekendDays[$0]==weekend }
                let rows=indices.flatMap { result.days[$0] }
                let t=Totals(rows),count=indices.count
                output.append("\(label) days \(count) load \(t.load/count) pv \(t.pv/count) import \(t.imported/count) export \(t.exported/count) cost \(money(t.netCost/count))")
            }
            return output
        case "PEAKS":
            try requireCount(args,1)
            let count=Int(args[0])!
            if count < 1 { throw CommandError("invalid count") }
            let result=try requireResult()
            let rows=result.hours.filter { $0.imported > 0 }.sorted {
                $0.imported == $1.imported ? $0.index < $1.index : $0.imported > $1.imported
            }
            var output=["PEAKS strategy \(result.strategy.text)"]
            for (i,r) in rows.prefix(count).enumerated() {
                output.append("\(i+1). day \(r.day) hour \(r.hour) \(r.period) import \(r.imported) load \(r.load) soc \(r.soc)")
            }
            if rows.isEmpty { output.append("none") }
            return output
        case "PROFILE":
            let result=try resultWithoutArguments(args)
            var output=["PROFILE strategy \(result.strategy.text) days \(data.dayCount)",
                        "hour   load     pv import export    soc"]
            for hour in 0..<24 {
                let records=result.hours.filter { $0.hour == hour }
                let count=data.dayCount
                let values=[hour,records.reduce(0) { $0+$1.load }/count,
                            records.reduce(0) { $0+$1.pv }/count,
                            records.reduce(0) { $0+$1.imported }/count,
                            records.reduce(0) { $0+$1.exported }/count,
                            records.reduce(0) { $0+$1.soc }/count]
                output.append(tableRow(strings(values),[4,7,7,7,7,7]))
            }
            return output
        case "FLOWS":
            let result=try resultWithoutArguments(args)
            var output=["FLOWS strategy \(result.strategy.text)"]
            for (i,name) in flowNames.enumerated() { output.append("\(name) \(result.total.flows[i])") }
            output.append("LOSSES \(result.total.loss)")
            output.append("STORED \(result.endSOC-result.startSOC)")
            return output
        case "SELFSUFF":
            let result=try resultWithoutArguments(args)
            let flows=result.total.flows
            return ["SELFSUFF sufficiency \(result.sufficiency)% consumption \(percentage(flows[0]+flows[1],result.total.pv))%"]
        case "CYCLES":
            let result=try resultWithoutArguments(args)
            let drawn=result.total.drawn, capacity=at(result.settings,"CAPACITY")
            let common=gcd(drawn,capacity)
            let thousandths=1000*drawn/capacity
            let decimal="\(thousandths/1000).\(String(thousandths%1000).leftPadded(3,by:"0"))"
            return ["CYCLES \(drawn/common)/\(capacity/common) \(decimal) drawn \(drawn) losses \(result.total.loss)"]
        case "USAGE":
            let result=try resultWithoutArguments(args),hours=result.hours
            let charging=hours.filter { $0.charge > 0 }.count
            let discharging=hours.filter { $0.drawn > 0 }.count
            let idle=hours.filter { $0.charge == 0 && $0.drawn == 0 }.count
            let full=hours.filter { $0.soc == at(result.settings,"CAPACITY") }.count
            var low=0,runLength=0,longest=0,first: HourRecord? = nil
            for row in hours {
                if row.soc <= result.reserve {
                    low += 1; runLength += 1
                    if runLength > longest {
                        longest=runLength
                        first=hours[row.index-runLength+1]
                    }
                } else { runLength=0 }
            }
            var line="USAGE charging \(charging) discharging \(discharging) idle \(idle) full \(full) low \(low) longest \(longest)"
            if let first=first { line += " from day \(first.day) hour \(first.hour)" }
            return [line]
        case "HISTOGRAM":
            let result=try resultWithoutArguments(args)
            let capacity=at(result.settings,"CAPACITY")
            var counts=Array(repeating:0,count:10)
            for r in result.hours { counts[min(9,10*r.soc/capacity)] += 1 }
            var output=["HISTOGRAM strategy \(result.strategy.text)"]
            for (i,count) in counts.enumerated() {
                let width=20*count/result.hours.count
                output.append("\(String(10*i).leftPadded(3))% \(bar(width)) \(count)")
            }
            return output
        case "CHART":
            let (day,result)=try resultForDay(args)
            let capacity=at(result.settings,"CAPACITY")
            var output=["CHART day \(day) \(data.dayNames[day-1]) strategy \(result.strategy.text)"]
            for r in result.days[day-1] {
                let width=20*r.soc/capacity
                output.append("\(String(r.hour).leftPadded(2)) \(bar(width)) \(percentage(r.soc,capacity))%")
            }
            return output
        default:
            fatalError("Unknown command case")
        }
    }
}

let bytes=FileHandle.standardInput.readDataToEndOfFile()
let input=String(data:bytes,encoding:.utf8)!
let lines=input.split(whereSeparator: \.isNewline).map(String.init)
let data=InputData(lines)
let desk=DispatchDesk(data)
var output: [String]=[]
for line in data.commands {
    let tokens=line.split(separator:" ").map(String.init)
    if tokens[0] == "END" { break }
    output += desk.execute(tokens)
}
if !output.isEmpty { print(output.joined(separator:"\n")) }
