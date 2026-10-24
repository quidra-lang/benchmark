import Foundation

let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
let fieldNames = ["minute", "hour", "day-of-month", "month", "day-of-week"]
let limits = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)]
let macros = ["@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
              "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"]
struct CommandError: Error { let reason: String }
func fail(_ reason: String) throws -> Never { throw CommandError(reason: reason) }
func pad(_ value: Int) -> String { (value < 10 ? "0" : "") + String(value) }
func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
func words(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }
func leap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
func monthLength(_ year: Int, _ month: Int) -> Int {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] + (month == 2 && leap(year) ? 1 : 0)
}
func leapCount(_ year: Int) -> Int { year / 4 - year / 100 + year / 400 }
func yearStart(_ year: Int) -> Int { 365 * (year - 2000) + leapCount(year - 1) - leapCount(1999) }
func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
    yearStart(year) + (1..<month).reduce(0) { $0 + monthLength(year, $1) } + day - 1
}
struct CivilDate { let number, year, month, day, weekday, length: Int }
func civil(_ number: Int) -> CivilDate {
    var year = 2000 + number / 366
    while yearStart(year + 1) <= number { year += 1 }
    var remaining = number - yearStart(year), month = 1
    while remaining >= monthLength(year, month) { remaining -= monthLength(year, month); month += 1 }
    return CivilDate(number: number, year: year, month: month, day: remaining + 1,
                     weekday: (number + 6) % 7, length: monthLength(year, month))
}
func dateText(_ date: CivilDate) -> String { "\(date.year)-\(pad(date.month))-\(pad(date.day))" }
func timeText(_ minute: Int) -> String { "\(pad(minute / 60)):\(pad(minute % 60))" }
func dateNotation(_ day: Int) -> String {
    let date = civil(day)
    return "\(dateText(date)) \(weekdays[date.weekday].prefix(3))"
}
func datetimeNotation(_ minute: Int) -> String {
    let date = civil(minute / 1440)
    return "\(dateText(date)) \(timeText(minute % 1440)) \(weekdays[date.weekday].prefix(3))"
}
func spanText(_ minutes: Int) -> String { "\(minutes / 1440)d\(pad(minutes % 1440 / 60))h\(pad(minutes % 60))m" }
func parseDate(_ text: String, reason: String = "invalid date") throws -> Int {
    guard matches(text, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") else { try fail(reason) }
    let parts = text.split(separator: "-").map { Int($0)! }, year = parts[0], month = parts[1], day = parts[2]
    guard (2001...2098).contains(year), (1...12).contains(month), day >= 1, day <= monthLength(year, month) else { try fail(reason) }
    return dayNumber(year, month, day)
}
func parseDatetime(_ date: String, _ time: String) throws -> Int {
    let day = try parseDate(date, reason: "invalid datetime")
    guard matches(time, "^[0-9]{2}:[0-9]{2}$") else { try fail("invalid datetime") }
    let parts = time.split(separator: ":").map { Int($0)! }
    guard parts[0] <= 23, parts[1] <= 59 else { try fail("invalid datetime") }
    return day * 1440 + parts[0] * 60 + parts[1]
}
func parseMonth(_ text: String) throws -> (year: Int, month: Int) {
    guard matches(text, "^[0-9]{4}-[0-9]{2}$") else { try fail("invalid month") }
    let parts = text.split(separator: "-").map { Int($0)! }
    guard (2001...2098).contains(parts[0]), (1...12).contains(parts[1]) else { try fail("invalid month") }
    return (parts[0], parts[1])
}
func boundedNumber(_ text: String, digits: Int, maximum: Int, reason: String) throws -> Int {
    guard text.count <= digits, matches(text, "^[1-9][0-9]*$"), let value = Int(text), value <= maximum else { try fail(reason) }
    return value
}

enum Special: Equatable {
    case lastDay, lastWeekday, beforeLast(Int), nearestWeekday(Int), nthWeekday(Int, Int), lastOccurrence(Int)
    var canonical: String {
        switch self {
        case .lastDay: return "L"
        case .lastWeekday: return "LW"
        case .beforeLast(let number): return "L-\(number)"
        case .nearestWeekday(let number): return "\(number)W"
        case .nthWeekday(let weekday, let number): return "\(weekday)#\(number)"
        case .lastOccurrence(let weekday): return "\(weekday)L"
        }
    }
}
struct Field {
    let set: Set<Int>
    let values: [Int]
    let specials: [Special]
    let unrestricted: Bool

    init(_ text: String, index: Int) throws {
        let (minimum, maximum) = limits[index]
        var values = Set<Int>(), specials = [Special]()
        func error(_ reason: String) throws -> Never { try fail("\(fieldNames[index]) \(reason)") }
        func natural(_ text: String, _ low: Int, _ high: Int) throws -> Int {
            guard matches(text, "^[0-9]{1,2}$") else { try error("invalid value") }
            let number = Int(text)!
            guard low <= number, number <= high else { try error("out of range") }
            return number
        }
        func value(_ text: String) throws -> Int {
            let names = index == 3 ? months : index == 4 ? weekdays : []
            if let found = names.firstIndex(where: { $0.prefix(3).uppercased() == text }) { return found + (index == 3 ? 1 : 0) }
            return try natural(text, minimum, maximum)
        }
        func special(_ item: Special) { if !specials.contains(item) { specials.append(item) } }
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let item = String(part)
            guard !item.isEmpty else { try error("empty item") }
            if index == 2 && (item.hasPrefix("L") || item.hasSuffix("W")) {
                if item == "L" { special(.lastDay) }
                else if item == "LW" { special(.lastWeekday) }
                else if item.hasPrefix("L-") { special(.beforeLast(try natural(String(item.dropFirst(2)), 1, 30))) }
                else if item.hasSuffix("W") { special(.nearestWeekday(try natural(String(item.dropLast()), 1, 31))) }
                else { try error("invalid value") }
                continue
            }
            if index == 4, let hash = item.firstIndex(of: "#") {
                let weekday = try value(String(item[..<hash])) % 7
                let numberText = String(item[item.index(after: hash)...])
                guard matches(numberText, "^[0-9]$") else { try error("invalid value") }
                let number = Int(numberText)!
                guard (1...5).contains(number) else { try error("out of range") }
                special(.nthWeekday(weekday, number)); continue
            }
            if index == 4 && item.count >= 2 && item.hasSuffix("L") {
                special(.lastOccurrence(try value(String(item.dropLast())) % 7)); continue
            }
            let slash = item.firstIndex(of: "/"), base = String(item[..<(slash ?? item.endIndex)])
            let first, last: Int
            if base == "*" { first = minimum; last = maximum }
            else if let dash = base.firstIndex(of: "-") {
                first = try value(String(base[..<dash]))
                last = try value(String(base[base.index(after: dash)...]))
                guard first <= last else { try error("invalid range") }
            } else { first = try value(base); last = slash == nil ? first : maximum }
            var step = 1
            if let slash {
                let part = String(item[item.index(after: slash)...])
                guard matches(part, "^[0-9]{1,2}$"), let number = Int(part), number >= 1 else { try error("invalid step") }
                step = number
            }
            for number in stride(from: first, through: last, by: step) { values.insert(index == 4 ? number % 7 : number) }
        }
        self.set = values; self.values = values.sorted(); self.specials = specials
        unrestricted = text.hasPrefix("*")
    }
}

struct Cron {
    let original, expanded: String
    let fields: [Field]
    let times: [Int]
    let useOr: Bool

    init(_ input: [String]) throws {
        original = input.joined(separator: " ")
        var tokens = input
        if tokens.count == 1 && tokens[0].hasPrefix("@") {
            guard let expression = macros[tokens[0]] else { try fail("unknown macro") }
            tokens = words(expression)
        }
        guard tokens.count == 5 else { try fail("field count") }
        expanded = tokens.joined(separator: " ")
        let parsed = try tokens.enumerated().map { try Field($0.element, index: $0.offset) }
        fields = parsed
        useOr = !parsed[2].unrestricted && !parsed[4].unrestricted
        times = parsed[1].values.flatMap { hour in parsed[0].values.map { hour * 60 + $0 } }
    }
    func days(_ date: CivilDate) -> (dom: Bool, dow: Bool, matches: Bool) {
        func nearest(_ day: Int) -> Int {
            let weekday = (date.number - date.day + day + 6) % 7
            if weekday == 6 { return day == 1 ? 3 : day - 1 }
            if weekday == 0 { return day == date.length ? day - 2 : day + 1 }
            return day
        }
        let dom = fields[2].set.contains(date.day) || fields[2].specials.contains { item in
            switch item {
            case .lastDay: return date.day == date.length
            case .lastWeekday: return date.day == nearest(date.length)
            case .beforeLast(let number): return date.day == date.length - number
            case .nearestWeekday(let number): return number <= date.length && date.day == nearest(number)
            default: return false
            }
        }
        let dow = fields[4].set.contains(date.weekday) || fields[4].specials.contains { item in
            switch item {
            case .nthWeekday(let weekday, let number): return date.weekday == weekday && (date.day - 1) / 7 + 1 == number
            case .lastOccurrence(let weekday): return date.weekday == weekday && date.day + 7 > date.length
            default: return false
            }
        }
        return (dom, dow, useOr ? dom || dow : dom && dow)
    }
    func scheduled(_ date: CivilDate) -> Bool { fields[3].set.contains(date.month) && days(date).matches }
    func reasons(_ minute: Int, holidays: Set<Int>) -> [String] {
        let date = civil(minute / 1440), day = days(date)
        var reasons = [String]()
        if !fields[0].set.contains(minute % 60) { reasons.append("minute") }
        if !fields[1].set.contains(minute % 1440 / 60) { reasons.append("hour") }
        if !day.matches && !day.dom { reasons.append("day-of-month") }
        if !fields[3].set.contains(date.month) { reasons.append("month") }
        if !day.matches && !day.dow { reasons.append("day-of-week") }
        if holidays.contains(date.number) { reasons.append("excluded") }
        return reasons
    }
    func eachFire(_ low: Int, _ high: Int, holidays: Set<Int>, reverse: Bool = false, _ visit: (Int) -> Bool) {
        let first = low / 1440, last = high / 1440, daily = reverse ? Array(times.reversed()) : times
        for day in stride(from: reverse ? last : first, through: reverse ? first : last, by: reverse ? -1 : 1) {
            if holidays.contains(day) || !scheduled(civil(day)) { continue }
            for time in daily {
                let minute = 1440 * day + time
                if low <= minute && minute <= high && !visit(minute) { return }
            }
        }
    }
}

func naturalList(_ parts: [String], conjunction: String = "and") -> String {
    guard let last = parts.last else { return "" }
    return parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " \(conjunction) " + last
}
func valueList(_ values: [Int], index: Int, conjunction: String = "and") -> String {
    func label(_ value: Int) -> String { index == 3 ? months[value - 1] : index == 4 ? weekdays[value] : String(value) }
    var parts = [String](), first = 0
    while first < values.count {
        var end = first + 1
        while end < values.count && values[end] == values[end - 1] + 1 { end += 1 }
        if end - first >= 3 { parts.append("\(label(values[first])) through \(label(values[end - 1]))") }
        else { parts.append(contentsOf: values[first..<end].map(label)) }
        first = end
    }
    return naturalList(parts, conjunction: conjunction)
}
func stepped(_ values: [Int], maximum: Int) -> Int? {
    guard values.count >= 2, values[0] == 0, values[1] >= 2 else { return nil }
    let step = values[1]
    return values.count == maximum / step + 1 && values.enumerated().allSatisfy { $0.element == $0.offset * step } ? step : nil
}
func description(_ cron: Cron) -> String {
    let minutes = cron.fields[0].values, hours = cron.fields[1].values
    let dom = cron.fields[2], month = cron.fields[3].values, dow = cron.fields[4]
    var time: String
    if cron.times.count <= 4 { time = "At " + naturalList(cron.times.map(timeText)) }
    else {
        if minutes.count == 60 { time = "Every minute" }
        else if let step = stepped(minutes, maximum: 59) { time = "Every \(step) minutes" }
        else if minutes.count == 1 { time = "At minute \(minutes[0])" }
        else { time = "At minutes " + valueList(minutes, index: 0) }
        if hours.count == 24 { if time.hasPrefix("At minute") { time += " of every hour" } }
        else if let step = stepped(hours, maximum: 23) { time += ", every \(step) hours" }
        else if hours.last! - hours[0] + 1 == hours.count { time += ", between \(pad(hours[0])):00 and \(pad(hours.last!)):59" }
        else { time += ", during hours " + valueList(hours, index: 1) }
    }
    var domParts = [String]()
    if !dom.values.isEmpty { domParts.append(dom.values.count == 1 ? "day \(dom.values[0])" : "days " + valueList(dom.values, index: 2)) }
    for item in dom.specials {
        switch item {
        case .lastDay: domParts.append("the last day")
        case .lastWeekday: domParts.append("the last weekday")
        case .beforeLast(let number): domParts.append("\(number) \(number == 1 ? "day" : "days") before the last day")
        case .nearestWeekday(let number): domParts.append("the weekday nearest day \(number)")
        default: break
        }
    }
    let domClause = naturalList(domParts) + " of the month"
    func dowClause(_ conjunction: String = "and") -> String {
        let ordinals = ["1st", "2nd", "3rd", "4th", "5th"]
        var parts = dow.values.isEmpty ? [] : [valueList(dow.values, index: 4, conjunction: conjunction)]
        for item in dow.specials {
            switch item {
            case .nthWeekday(let weekday, let number): parts.append("the \(ordinals[number - 1]) \(weekdays[weekday])")
            case .lastOccurrence(let weekday): parts.append("the last \(weekdays[weekday])")
            default: break
            }
        }
        return naturalList(parts, conjunction: conjunction) + (dow.specials.isEmpty ? "" : " of the month")
    }
    let domFull = dom.values.count == 31, dowFull = dow.values.count == 7
    var day = ""
    if cron.useOr {
        if !domFull && !dowFull { day = ", on \(domClause) or on \(dowClause())" }
    } else if !domFull && !dowFull { day = ", on \(domClause) if it is \(dowClause("or"))" }
    else if !domFull { day = ", on \(domClause)" }
    else if !dowFull { day = ", on \(dowClause())" }
    return time + day + (month.count == 12 ? "" : ", in " + valueList(month, index: 3))
}

enum Policy: String { case allow = "ALLOW", forbid = "FORBID", replace = "REPLACE" }
final class Job {
    var id: String
    let cron: Cron
    var enabled = true
    var duration = 1
    var policy = Policy.allow
    init(id: String, cron: Cron) { self.id = id; self.cron = cron }
}
final class Scheduler {
    private var jobs = [String: Job]()
    private var holidays = Set<Int>()

    private func newId(_ id: String) throws {
        guard matches(id, "^[a-z][a-z0-9_]{0,15}$") else { try fail("invalid id") }
        guard jobs[id] == nil else { try fail("duplicate job") }
    }
    private func existing(_ id: String) throws -> Job {
        guard let job = jobs[id] else { try fail("unknown job") }
        return job
    }
    private func ordered(enabled: Bool = false) -> [Job] {
        jobs.values.filter { !enabled || $0.enabled }.sorted { $0.id < $1.id }
    }
    private func window(_ args: [String], start: Int) throws -> (low: Int, high: Int) {
        let low = try parseDatetime(args[start], args[start + 1])
        let high = try parseDatetime(args[start + 2], args[start + 3])
        guard low <= high else { try fail("invalid window") }
        guard high - low <= 44640 else { try fail("window too long") }
        return (low, high)
    }
    private func fireTimes(_ job: Job, _ low: Int, _ high: Int, limit: Int? = nil, reverse: Bool = false) -> [Int] {
        var result = [Int]()
        job.cron.eachFire(low, high, holidays: holidays, reverse: reverse) { minute in
            result.append(minute)
            return limit == nil || result.count < limit!
        }
        return result
    }
    private func grouped(_ low: Int, _ high: Int) -> [(minute: Int, ids: [String])] {
        var groups = [Int: [String]]()
        for job in ordered(enabled: true) {
            job.cron.eachFire(low, high, holidays: holidays) { minute in
                groups[minute, default: []].append(job.id)
                return true
            }
        }
        return groups.keys.sorted().map { ($0, groups[$0]!) }
    }
    private func simulate(_ low: Int, _ high: Int) -> [String] {
        var events = [Int: Int](), rows = [String]()
        for job in ordered(enabled: true) {
            var lastEnd: Int?, started = 0, skipped = 0, replaced = 0, busy = 0
            job.cron.eachFire(low, high, holidays: holidays) { minute in
                if let end = lastEnd, end > minute {
                    if job.policy == .forbid { skipped += 1; return true }
                    if job.policy == .replace {
                        events[end, default: 0] += 1; events[minute, default: 0] -= 1
                        busy -= end - minute; replaced += 1
                    }
                }
                lastEnd = minute + job.duration
                events[minute, default: 0] += 1; events[minute + job.duration, default: 0] -= 1
                busy += job.duration; started += 1
                return true
            }
            rows.append("\(job.id) \(job.policy.rawValue) started \(started) skipped \(skipped) replaced \(replaced) busy \(busy)")
        }
        var running = 0, peak = 0, earliest = 0
        for minute in events.keys.sorted() {
            running += events[minute]!
            if running > peak { peak = running; earliest = minute }
        }
        return ["SIMULATE \(rows.count) peak \(peak)" + (peak > 0 ? " at " + datetimeNotation(earliest) : "")] + rows
    }
    private func week(_ first: Int, text: String) -> [String] {
        let jobs = ordered(enabled: true)
        var rows = [String](), total = 0
        for day in first..<(first + 7) {
            var hours = Array(repeating: 0, count: 24)
            let date = civil(day)
            if !holidays.contains(day) {
                for job in jobs where job.cron.scheduled(date) {
                    for hour in job.cron.fields[1].values { hours[hour] += job.cron.fields[0].values.count }
                }
            }
            let count = hours.reduce(0, +)
            total += count
            let cells = hours.map { $0 == 0 ? "." : $0 < 10 ? String($0) : "+" }.joined()
            rows.append("\(dateNotation(day)) \(cells) \(count)")
        }
        return ["WEEK \(text) \(total)"] + rows
    }
    private func calendar(_ job: Job, year: Int, month: Int, text: String) -> [String] {
        let first = dayNumber(year, month, 1), length = monthLength(year, month)
        var cells = Array(repeating: "...", count: (first + 6) % 7), active = 0
        for day in 1...length {
            let number = first + day - 1
            let mark = !job.cron.scheduled(civil(number)) ? "-" : holidays.contains(number) ? "x" : "*"
            if mark == "*" { active += 1 }
            cells.append(pad(day) + mark)
        }
        while cells.count % 7 != 0 { cells.append("...") }
        var rows = ["CALENDAR \(job.id) \(text) days \(active) runs \(active * job.cron.times.count)", "Sun Mon Tue Wed Thu Fri Sat"]
        for index in stride(from: 0, to: cells.count, by: 7) { rows.append(cells[index..<(index + 7)].joined(separator: " ")) }
        return rows
    }
    private func gap(_ job: Job, base: Int) -> [String] {
        let times = fireTimes(job, base, base + 44640), prefix = "GAP \(job.id) runs \(times.count)"
        guard times.count >= 2 else { return [prefix + " none"] }
        var counts = [Int: Int](), shortest = times[1] - times[0], longest = shortest, from = 0
        for index in 1..<times.count {
            let difference = times[index] - times[index - 1]
            counts[difference, default: 0] += 1; shortest = min(shortest, difference)
            if difference > longest { longest = difference; from = index - 1 }
        }
        let header = prefix + " shortest \(spanText(shortest)) longest \(spanText(longest)) from \(datetimeNotation(times[from])) to \(datetimeNotation(times[from + 1]))"
        return [header] + counts.keys.sorted().map { "\(spanText($0)) \(counts[$0]!)" }
    }
}

let argumentCounts = ["REMOVE": 1, "RENAME": 2, "ENABLE": 1, "DISABLE": 1, "RUNTIME": 3, "LIST": 0,
                      "EXPAND": 2, "DESCRIBE": 1, "MATCH": 3, "NEXT": 4, "PREV": 4, "COUNT": 5,
                      "GAP": 3, "OVERLAP": 6, "TIMELINE": 4, "CONFLICTS": 4, "WEEK": 1, "CALENDAR": 2,
                      "SIMULATE": 4, "EXCLUDE": 1, "INCLUDE": 1, "HOLIDAYS": 0]
extension Scheduler {
    func execute(_ line: String) throws -> [String] {
        let tokens = words(line), command = tokens[0], args = Array(tokens.dropFirst())
        if command == "JOB" || command == "VALIDATE" {
            guard args.count >= (command == "JOB" ? 2 : 1) else { try fail("wrong arguments") }
            if command == "VALIDATE" {
                let cron = try Cron(args)
                return ["VALID \(cron.expanded) \(cron.useOr ? "OR" : "AND") \(cron.times.count)"]
            }
            let id = args[0]
            try newId(id)
            let cron = try Cron(Array(args.dropFirst()))
            jobs[id] = Job(id: id, cron: cron)
            return ["JOB \(id) added"]
        }
        guard let count = argumentCounts[command] else { try fail("unknown command") }
        guard args.count == count else { try fail("wrong arguments") }
        switch command {
        case "LIST":
            return ["LIST \(jobs.count)"] + ordered().map { "\($0.id) \($0.enabled ? "on" : "off") \($0.duration) \($0.policy.rawValue) \($0.cron.original)" }
        case "HOLIDAYS": return ["HOLIDAYS \(holidays.count)"] + holidays.sorted().map(dateNotation)
        case "EXCLUDE", "INCLUDE":
            let day = try parseDate(args[0]), exclude = command == "EXCLUDE"
            guard holidays.contains(day) != exclude else { try fail(exclude ? "already excluded" : "not excluded") }
            if exclude { holidays.insert(day) } else { holidays.remove(day) }
            return ["\(command) \(dateNotation(day)) holidays \(holidays.count)"]
        case "WEEK":
            let first = try parseDate(args[0])
            return week(first, text: args[0])
        case "TIMELINE", "CONFLICTS", "SIMULATE":
            let range = try window(args, start: 0)
            if command == "SIMULATE" { return simulate(range.low, range.high) }
            let groups = grouped(range.low, range.high)
            var rows = [String](), total = 0, peak = 0
            for (minute, ids) in groups {
                if command == "TIMELINE" {
                    total += ids.count
                    for id in ids where rows.count < 100 { rows.append("\(datetimeNotation(minute)) \(id)") }
                } else if ids.count >= 2 {
                    total += 1; peak = max(peak, ids.count)
                    if rows.count < 100 { rows.append("\(datetimeNotation(minute)) \(ids.count) " + ids.joined(separator: " ")) }
                }
            }
            rows.insert("\(command) \(total)" + (command == "CONFLICTS" ? " peak \(peak)" : ""), at: 0)
            if total > 100 { rows.append("... \(total - 100) more") }
            return rows
        default: break
        }
        let job = try existing(args[0])
        switch command {
        case "REMOVE":
            jobs.removeValue(forKey: job.id)
            return ["REMOVE \(job.id)"]
        case "RENAME":
            try newId(args[1])
            let old = job.id
            jobs.removeValue(forKey: old); job.id = args[1]; jobs[job.id] = job
            return ["RENAME \(old) \(job.id)"]
        case "ENABLE", "DISABLE":
            let enabled = command == "ENABLE"
            guard job.enabled != enabled else { try fail(enabled ? "already enabled" : "already disabled") }
            job.enabled = enabled
            return ["\(command) \(job.id)"]
        case "RUNTIME":
            let duration = try boundedNumber(args[1], digits: 4, maximum: 1440, reason: "invalid duration")
            guard let policy = Policy(rawValue: args[2]) else { try fail("invalid policy") }
            job.duration = duration; job.policy = policy
            return ["RUNTIME \(job.id) \(duration) \(policy.rawValue)"]
        case "EXPAND":
            guard let index = fieldNames.firstIndex(of: args[1]) else { try fail("invalid field") }
            let field = job.cron.fields[index]
            return [(["EXPAND", job.id, args[1], String(field.values.count)] + field.values.map(String.init) + field.specials.map(\.canonical)).joined(separator: " ")]
        case "DESCRIBE": return ["DESCRIBE \(job.id) \(description(job.cron))"]
        case "CALENDAR":
            let date = try parseMonth(args[1])
            return calendar(job, year: date.year, month: date.month, text: args[1])
        case "OVERLAP":
            let second = try existing(args[1])
            let range = try window(args, start: 2)
            let other = Set(fireTimes(second, range.low, range.high))
            let shared = fireTimes(job, range.low, range.high).filter { other.contains($0) }
            var row = "OVERLAP \(job.id) \(second.id) \(shared.count)"
            if let first = shared.first, let last = shared.last { row += " first \(datetimeNotation(first)) last \(datetimeNotation(last))" }
            return [row]
        case "COUNT":
            let range = try window(args, start: 1)
            var runs = 0, days = Set<Int>()
            job.cron.eachFire(range.low, range.high, holidays: holidays) { minute in
                runs += 1; days.insert(minute / 1440); return true
            }
            return ["COUNT \(job.id) runs \(runs) days \(days.count)"]
        default: break
        }
        let base = try parseDatetime(args[1], args[2])
        if command == "MATCH" {
            let reasons = job.cron.reasons(base, holidays: holidays)
            return ["MATCH \(job.id) \(datetimeNotation(base))" + (reasons.isEmpty ? " yes" : " no " + reasons.joined(separator: " "))]
        }
        if command == "GAP" { return gap(job, base: base) }
        let requested = try boundedNumber(args[3], digits: 2, maximum: 50, reason: "invalid count")
        let reverse = command == "PREV"
        let times = fireTimes(job, reverse ? base - 527040 : base + 1, reverse ? base - 1 : base + 527040, limit: requested, reverse: reverse)
        var rows = ["\(command) \(job.id) \(times.count)"]
        rows += times.map { "\(datetimeNotation($0)) \(reverse ? "-" : "+")\(spanText(abs($0 - base)))" }
        if times.count < requested { rows.append("NONE") }
        return rows
    }
}

let commandCount = Int(readLine()!)!, scheduler = Scheduler()
for _ in 0..<commandCount {
    do { for row in try scheduler.execute(readLine()!) { print(row) } }
    catch let error as CommandError { print("ERROR \(error.reason)") }
    catch { throw error }
}
