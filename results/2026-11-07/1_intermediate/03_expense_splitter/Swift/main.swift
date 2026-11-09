import Foundation

struct Amount {
    let value: Int
    let currency: String
}
struct Member {
    let active: Bool
    let day: Int
}
struct Part {
    let name: String
    let value: Int
}
struct Settlement {
    let day: Int
    let record: Int
    let from: String
    let to: String
    let amount: Amount
    let total: Int
}
struct Entry {
    let day: Int
    let record: Int
    let label: String
    let change: Int
}
struct Transfer {
    let from: String
    let to: String
    let amount: Int
}
struct Problem: Error {
    let message: String
}
final class Expense {
    var id = ""
    var category = ""
    var mode = ""
    var amount = Amount(value: 0,currency: "")
    var payers: [Part] = []
    var participants: [Part] = []
    var contributions: [Int] = []
    var shares: [Int] = []
    var day = 0
    var record = 0
    var total = 0
    var interval = 0
    var next = 0
    var copies = 0
    func copyContents() -> Expense {
        let e = Expense()
        e.amount = amount
        e.category = category
        e.mode = mode
        e.payers = payers
        e.participants = participants
        return e
    }
}

final class Splitter {
    var members: [String:Member] = [:]
    var currencies: [String:Int] = [:]
    var budgets: [String:Int] = [:]
    var expenses: [String:Expense] = [:]
    var used: Set<String> = []
    var settlements: [Settlement] = []
    var day = 1
    var serial = 0
    func fail(_ message: String) -> Problem { Problem(message: message) }
    func money(_ s: String) -> Int { Int(s.replacingOccurrences(of: ".",with: ""))! }
    func amount(_ s: String) -> Amount {
        let p = s.split(separator: "@").map(String.init)
        return Amount(value: money(p[0]),currency: p.count == 2 ? p[1] : "")
    }
    func fmt(_ n: Int) -> String {
        String(format: "%ld.%02ld",locale: Locale(identifier: "en_US_POSIX"),n/100,n%100)
    }
    func signed(_ n: Int) -> String { n > 0 ? "+"+fmt(n) : (n < 0 ? "-"+fmt(-n) : "0.00") }
    func rate(_ n: Int) -> String {
        String(format: "%ld.%04ld",locale: Locale(identifier: "en_US_POSIX"),n/10000,n%10000)
    }
    func percent(_ p: Int, _ w: Int) -> String { fmt(p*10000/w)+"%" }
    func note(_ a: Amount) -> String { a.currency.isEmpty ? "" : " [\(fmt(a.value)) \(a.currency)]" }
    func registered(_ name: String) throws {
        guard members[name] != nil else { throw fail("unknown member "+name) }
    }
    func active(_ name: String) throws {
        try registered(name)
        guard members[name]!.active else { throw fail("inactive member "+name) }
    }
    func convert(_ a: Amount) throws -> Int {
        if a.currency.isEmpty { return a.value }
        guard let r = currencies[a.currency] else { throw fail("unknown currency "+a.currency) }
        return (a.value*r+5000)/10000
    }
    func expense(_ id: String) throws -> Expense {
        guard let e = expenses[id] else { throw fail("unknown expense "+id) }
        return e
    }
    func thawed(_ e: Expense) throws {
        for p in e.payers+e.participants {
            guard members[p.name]!.active else { throw fail("inactive member "+p.name) }
        }
    }
    func distribute(_ total: Int, _ weights: [Int]) -> [Int] {
        let sum = weights.reduce(0,+)
        var result = weights.map { total*$0/sum }
        let remainders = weights.map { total*$0%sum }
        let order = weights.indices.sorted {
            remainders[$0] == remainders[$1] ? $0 < $1 : remainders[$0] > remainders[$1]
        }
        let left = total-result.reduce(0,+)
        for i in 0..<left { result[order[i]] += 1 }
        return result
    }
    func compute(_ e: Expense) throws {
        let a = e.amount.value
        e.total = try convert(e.amount)
        let sum = e.participants.reduce(0) { $0+$1.value }
        let portions: [Int]
        switch e.mode {
        case "EXACT":
            guard sum == a else { throw fail("splits do not add up") }
            portions = e.participants.map { $0.value }
        case "PERCENT", "SHARES":
            if (e.mode == "PERCENT" && sum != 10000) || (e.mode == "SHARES" && sum == 0) {
                throw fail("splits do not add up")
            }
            portions = distribute(a,e.participants.map { $0.value })
        default:
            let extras = e.mode == "ADJUST" ? sum : 0
            guard extras <= a else { throw fail("splits do not add up") }
            let k = e.participants.count
            portions = e.participants.enumerated().map { i,p in
                (a-extras)/k+(i < (a-extras)%k ? 1 : 0)+(e.mode == "ADJUST" ? p.value : 0)
            }
        }
        e.shares = distribute(e.total,portions)
        e.contributions = distribute(e.total,e.payers.map { $0.value })
    }
    func build(_ t: [String]) throws -> Expense {
        try active(t[2])
        let e = Expense()
        e.amount = amount(t[3])
        let total = try convert(e.amount)
        guard e.amount.value > 0 && total > 0 else { throw fail("invalid amount") }
        e.category = t[4]
        e.mode = t[5]
        e.payers = [Part(name: t[2],value: e.amount.value)]
        if e.mode == "EQUAL" && t[6] == "ALL" {
            e.participants = activeNames().map { Part(name: $0,value: 0) }
        } else {
            var seen: Set<String> = []
            for token in t.dropFirst(6) {
                let p = token.split(separator: ":").map(String.init)
                try active(p[0])
                guard seen.insert(p[0]).inserted else { throw fail("duplicate member "+p[0]) }
                let value = p.count == 1 ? 0 : ((e.mode == "EXACT" || e.mode == "ADJUST") ? money(p[1]) : Int(p[1])!)
                e.participants.append(Part(name: p[0],value: value))
            }
        }
        try compute(e)
        return e
    }
    func chronological() -> [Expense] {
        expenses.values.sorted { $0.day == $1.day ? $0.record < $1.record : $0.day < $1.day }
    }
    func includes(_ e: Expense, _ name: String) -> Bool { (e.payers+e.participants).contains { $0.name == name } }
    func net(_ e: Expense) -> [String:Int] {
        var result: [String:Int] = [:]
        for (i,p) in e.payers.enumerated() { result[p.name,default: 0] += e.contributions[i] }
        for (i,p) in e.participants.enumerated() { result[p.name,default: 0] -= e.shares[i] }
        return result
    }
    func balances() -> [String:Int] {
        var result = Dictionary(uniqueKeysWithValues: members.keys.map { ($0,0) })
        for e in expenses.values {
            for (name,value) in net(e) { result[name,default: 0] += value }
        }
        for s in settlements {
            result[s.from,default: 0] += s.total
            result[s.to,default: 0] -= s.total
        }
        return result
    }
    func activeNames() -> [String] { members.keys.filter { members[$0]!.active }.sorted() }
    func categoryTotals() -> [String:Int] {
        var result: [String:Int] = [:]
        for e in expenses.values { result[e.category,default: 0] += e.total }
        return result
    }
    func warning(_ e: Expense, _ output: inout [String]) {
        if let budget = budgets[e.category] {
            let spent = categoryTotals()[e.category]!
            if spent > budget { output.append("  WARNING \(e.category) over budget by \(fmt(spent-budget))") }
        }
    }
    func pairs(_ people: [Part], _ values: [Int]) -> String {
        people.indices.map { people[$0].name+" "+fmt(values[$0]) }.joined(separator: " + ")
    }
    func greedy(_ balances: [String:Int]) -> [Transfer] {
        var work = balances
        let names = work.keys.sorted()
        var result: [Transfer] = []
        while !work.isEmpty {
            let from = names.min { work[$0]! < work[$1]! }!
            let to = names.max { work[$0]! < work[$1]! }!
            let minimum = work[from]!
            let maximum = work[to]!
            if minimum >= 0 { break }
            let value = min(-minimum,maximum)
            result.append(Transfer(from: from,to: to,amount: value))
            work[from] = minimum+value
            work[to] = maximum-value
        }
        return result
    }
    func debts(_ names: [String]) -> [[Int]] {
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element,$0.offset) })
        var result = Array(repeating: Array(repeating: 0,count: names.count),count: names.count)
        for e in expenses.values {
            var amounts = net(e)
            let borrowers = amounts.keys.filter { amounts[$0]! < 0 }.sorted()
            let lenders = amounts.keys.filter { amounts[$0]! > 0 }.sorted()
            var a = 0
            var b = 0
            while a < borrowers.count && b < lenders.count {
                let x = borrowers[a]
                let y = lenders[b]
                let value = min(-amounts[x]!,amounts[y]!)
                let i = index[x]!
                let j = index[y]!
                result[i][j] += value
                result[j][i] -= value
                amounts[x]! += value
                amounts[y]! -= value
                if amounts[x] == 0 { a += 1 }
                if amounts[y] == 0 { b += 1 }
            }
        }
        for s in settlements {
            let i = index[s.from]!
            let j = index[s.to]!
            result[i][j] -= s.total
            result[j][i] += s.total
        }
        return result
    }
    func indexes(_ mask: Int, _ n: Int) -> [Int] { (0..<n).filter { mask & (1 << $0) != 0 } }
    func execute(_ line: String) throws -> [String] {
        let t = line.split(separator: " ").map(String.init)
        let command = t[0]
        var output: [String] = []
        switch command {
        case "DAY":
            let d = Int(t[1])!
            guard d > day else { throw fail("invalid day "+t[1]) }
            output.append("DAY \(d)")
            while let template = expenses.values.filter({ $0.interval > 0 && $0.next <= d }).min(by: {
                $0.next == $1.next ? $0.record < $1.record : $0.next < $1.next
            }) {
                let allActive = (template.payers+template.participants).allSatisfy { members[$0.name]!.active }
                let total = try convert(template.amount)
                if !allActive || total == 0 {
                    template.interval = 0
                    output.append("  CANCEL "+template.id)
                } else {
                    let copy = template.copyContents()
                    copy.id = template.id+"#\(template.copies+2)"
                    copy.day = template.next
                    serial += 1
                    copy.record = serial
                    try compute(copy)
                    expenses[copy.id] = copy
                    used.insert(copy.id)
                    template.copies += 1
                    template.next += template.interval
                    output.append("  RECUR \(copy.id) \(fmt(copy.total))")
                    warning(copy,&output)
                }
            }
            day = d
        case "MEMBER":
            let old = members[t[1]]
            guard old?.active != true else { throw fail("duplicate member "+t[1]) }
            members[t[1]] = Member(active: true,day: day)
            output.append("MEMBER "+t[1]+(old == nil ? " joined" : " rejoined"))
        case "LEAVE":
            try active(t[1])
            guard balances()[t[1]]! == 0 else { throw fail("member has a balance "+t[1]) }
            members[t[1]] = Member(active: false,day: day)
            output.append("LEAVE "+t[1])
        case "CURRENCY":
            let value = Int(t[2])!
            let old = currencies.updateValue(value,forKey: t[1])
            output.append("CURRENCY \(t[1]) \(rate(value))"+(old.map { " was "+rate($0) } ?? ""))
        case "EXPENSE", "EDIT":
            let old: Expense?
            if command == "EDIT" {
                old = try expense(t[1])
                try thawed(old!)
            } else {
                guard !used.contains(t[1]) else { throw fail("duplicate id "+t[1]) }
                old = nil
            }
            let e = try build(t)
            e.id = t[1]
            e.day = old?.day ?? day
            if let old {
                e.record = old.record
                e.interval = old.interval
                e.next = old.next
                e.copies = old.copies
            } else {
                serial += 1
                e.record = serial
            }
            expenses[e.id] = e
            used.insert(e.id)
            output.append("\(command) \(e.id) \(fmt(e.total))\(note(e.amount)) = \(pairs(e.participants,e.shares))")
            warning(e,&output)
        case "PAYERS":
            let e = try expense(t[1])
            try thawed(e)
            var payers: [Part] = []
            var seen: Set<String> = []
            for token in t.dropFirst(2) {
                let p = token.split(separator: ":").map(String.init)
                try active(p[0])
                guard seen.insert(p[0]).inserted else { throw fail("duplicate member "+p[0]) }
                payers.append(Part(name: p[0],value: money(p[1])))
            }
            guard payers.reduce(0,{ $0+$1.value }) == e.amount.value else { throw fail("payers do not add up") }
            let contributions = distribute(e.total,payers.map { $0.value })
            e.payers = payers
            e.contributions = contributions
            output.append("PAYERS \(e.id) \(fmt(e.total))\(note(e.amount)) = \(pairs(payers,contributions))")
        case "DELETE":
            let e = try expense(t[1])
            try thawed(e)
            expenses.removeValue(forKey: e.id)
            output.append("DELETE "+e.id)
        case "RECURRING":
            let e = try expense(t[1])
            e.interval = Int(t[2])!
            e.next = day+e.interval
            output.append("RECURRING "+e.id+(e.interval == 0 ? " stopped" : " interval \(e.interval) next \(e.next)"))
        case "SETTLE":
            try active(t[1])
            try active(t[2])
            guard t[1] != t[2] else { throw fail("same member "+t[1]) }
            let a = amount(t[3])
            let total = try convert(a)
            guard a.value > 0 && total > 0 else { throw fail("invalid amount") }
            serial += 1
            settlements.append(Settlement(day: day,record: serial,from: t[1],to: t[2],amount: a,total: total))
            output.append("SETTLE \(t[1]) -> \(t[2]) \(fmt(total))\(note(a))")
        case "BUDGET":
            let value = money(t[2])
            if value == 0 { budgets.removeValue(forKey: t[1]) }
            else { budgets[t[1]] = value }
            output.append("BUDGET "+t[1]+(value == 0 ? " removed" : " "+fmt(value)))
        case "BALANCES":
            output.append("BALANCES")
            let values = balances()
            for name in activeNames() { output.append("  "+name+" "+signed(values[name]!)) }
        case "OWES", "MATRIX":
            if command == "OWES" { try registered(t[1]) }
            let names = members.keys.sorted()
            let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element,$0.offset) })
            let debt = debts(names)
            output.append(command == "OWES" ? "OWES "+t[1] : "MATRIX")
            if command == "OWES" {
                let i = index[t[1]]!
                for j in names.indices {
                    if debt[i][j] > 0 { output.append("  \(t[1]) owes \(names[j]) \(fmt(debt[i][j]))") }
                    if debt[i][j] < 0 { output.append("  \(names[j]) owes \(t[1]) \(fmt(-debt[i][j]))") }
                }
            } else {
                let active = activeNames()
                if active.isEmpty { output.append("  (none)") }
                else {
                    let l = active.map { $0.count }.max()!
                    func cell(_ a: String, _ b: String) -> String { a == b ? "-" : fmt(max(0,debt[index[a]!][index[b]!])) }
                    let width = max(l,active.flatMap { a in active.map { cell(a,$0).count } }.max()!)
                    func right(_ s: String) -> String { String(format: "%*@",width,s) }
                    output.append(String(repeating: " ",count: l)+active.map { "  "+right($0) }.joined())
                    for a in active {
                        output.append(a+String(repeating: " ",count: l-a.count)+active.map { "  "+right(cell(a,$0)) }.joined())
                    }
                }
            }
        case "HISTORY":
            try registered(t[1])
            var entries: [Entry] = []
            for e in expenses.values {
                if includes(e,t[1]) { entries.append(Entry(day: e.day,record: e.record,label: e.id,change: net(e)[t[1]]!)) }
            }
            for s in settlements {
                if s.from == t[1] || s.to == t[1] {
                    entries.append(Entry(day: s.day,record: s.record,label: s.from+"->"+s.to,change: s.from == t[1] ? s.total : -s.total))
                }
            }
            entries.sort { $0.day == $1.day ? $0.record < $1.record : $0.day < $1.day }
            output.append("HISTORY "+t[1])
            var balance = 0
            for e in entries {
                balance += e.change
                output.append("  day \(e.day) \(e.label) \(signed(e.change)) balance \(signed(balance))")
            }
        case "CATEGORY":
            output.append("CATEGORY")
            let totals = categoryTotals()
            let all = totals.values.reduce(0,+)
            for category in totals.keys.sorted(by: { totals[$0] == totals[$1] ? $0 < $1 : totals[$0]! > totals[$1]! }) {
                let total = totals[category]!
                output.append("  \(category) \(fmt(total)) \(percent(total,all))")
                var shares: [String:Int] = [:]
                for e in expenses.values where e.category == category {
                    for (i,p) in e.participants.enumerated() { shares[p.name,default: 0] += e.shares[i] }
                }
                let names = shares.keys.filter { shares[$0]! > 0 }.sorted { shares[$0] == shares[$1] ? $0 < $1 : shares[$0]! > shares[$1]! }
                for name in names { output.append("    \(name) \(fmt(shares[name]!)) \(percent(shares[name]!,total))") }
            }
        case "BUDGETS":
            output.append("BUDGETS")
            let totals = categoryTotals()
            for category in budgets.keys.sorted() {
                let b = budgets[category]!
                let s = totals[category] ?? 0
                output.append("  \(category) spent \(fmt(s)) budget \(fmt(b)) used \(percent(s,b))"+
                    (s <= b ? " left "+fmt(b-s) : " over "+fmt(s-b)))
            }
        case "TOTALS":
            output.append("TOTALS")
            for name in members.keys.sorted() {
                var paid = 0
                var share = 0
                for e in expenses.values {
                    for (i,p) in e.payers.enumerated() where p.name == name { paid += e.contributions[i] }
                    for (i,p) in e.participants.enumerated() where p.name == name { share += e.shares[i] }
                }
                let sent = settlements.filter { $0.from == name }.reduce(0) { $0+$1.total }
                let received = settlements.filter { $0.to == name }.reduce(0) { $0+$1.total }
                output.append("  \(name) paid \(fmt(paid)) share \(fmt(share)) sent \(fmt(sent)) received \(fmt(received))")
            }
            for currency in currencies.keys.sorted() {
                let group = expenses.values.filter { $0.amount.currency == currency }
                if !group.isEmpty {
                    output.append("  currency \(currency) expenses \(group.count) amount \(fmt(group.reduce(0) { $0+$1.amount.value })) base \(fmt(group.reduce(0) { $0+$1.total }))")
                }
            }
            output.append("  expenses \(expenses.count) total \(fmt(expenses.values.reduce(0) { $0+$1.total })) settlements \(settlements.count) total \(fmt(settlements.reduce(0) { $0+$1.total }))")
        case "MEMBERS":
            output.append("MEMBERS")
            for name in members.keys.sorted() {
                let m = members[name]!
                let count = expenses.values.filter { includes($0,name) }.count
                output.append("  \(name) \(m.active ? "active" : "left") day \(m.day) expenses \(count)")
            }
        case "EXPENSES":
            if t[1] == "MEMBER" { try registered(t[2]) }
            output.append(line)
            var count = 0
            var total = 0
            for e in chronological() {
                let matches: Bool
                switch t[1] {
                case "CATEGORY": matches = e.category == t[2]
                case "MEMBER": matches = includes(e,t[2])
                case "DAYS": matches = e.day >= Int(t[2])! && e.day <= Int(t[3])!
                default: matches = true
                }
                if matches {
                    output.append("  day \(e.day) \(e.id) \(e.category) \(fmt(e.total)) by "+e.payers.map { $0.name }.joined(separator: ","))
                    count += 1
                    total += e.total
                }
            }
            output.append("  count \(count) total \(fmt(total))")
        case "PERIODS":
            let k = Int(t[1])!
            output.append("PERIODS \(k)")
            let groups = Dictionary(grouping: expenses.values,by: { ($0.day-1)/k })
            for i in groups.keys.sorted() {
                let group = groups[i]!
                output.append("  days \(i*k+1)-\(i*k+k) expenses \(group.count) total \(fmt(group.reduce(0) { $0+$1.total }))")
            }
        case "SHOW":
            let e = try expense(t[1])
            output.append("SHOW "+e.id)
            output.append("  day \(e.day) category \(e.category) mode \(e.mode) total \(fmt(e.total))\(note(e.amount))")
            for (i,p) in e.payers.enumerated() { output.append("  paid \(p.name) \(fmt(e.contributions[i]))") }
            let sum = e.participants.reduce(0) { $0+$1.value }
            for (i,p) in e.participants.enumerated() {
                let suffix: String
                switch e.mode {
                case "EXACT": suffix = " "+fmt(p.value)
                case "PERCENT": suffix = " "+fmt(p.value)+"%"
                case "SHARES": suffix = " \(p.value)/\(sum)"
                case "ADJUST": suffix = " +"+fmt(p.value)
                default: suffix = ""
                }
                output.append("  share \(p.name) \(fmt(e.shares[i]))"+suffix)
            }
            if e.interval > 0 { output.append("  recurring interval \(e.interval) next \(e.next)") }
        case "SIMPLIFY":
            let all = balances().filter { $0.value != 0 }
            if t[1] == "GREEDY" {
                let transfers = greedy(all)
                output.append("SIMPLIFY GREEDY transfers \(transfers.count)")
                for x in transfers { output.append("  \(x.from) -> \(x.to) \(fmt(x.amount))") }
            } else {
                let names = all.keys.sorted()
                let n = names.count
                guard n <= 12 else { throw fail("too many members") }
                let size = 1 << n
                var sums = Array(repeating: 0,count: size)
                var dp = Array(repeating: -1000,count: size)
                dp[0] = 0
                if size > 1 {
                    for mask in 1..<size {
                        let bit = mask.trailingZeroBitCount
                        sums[mask] = sums[mask ^ (1 << bit)]+all[names[bit]]!
                        let first = mask & -mask
                        var sub = mask
                        while sub > 0 {
                            if sub & first != 0 && sums[sub] == 0 { dp[mask] = max(dp[mask],1+dp[mask ^ sub]) }
                            sub = (sub-1) & mask
                        }
                    }
                }
                var remaining = size-1
                var groups: [Int] = []
                while remaining != 0 {
                    let first = remaining & -remaining
                    var best = 0
                    var sub = remaining
                    while sub > 0 {
                        if sub & first != 0 && sums[sub] == 0 && 1+dp[remaining ^ sub] == dp[remaining] &&
                            (best == 0 || indexes(sub,n).lexicographicallyPrecedes(indexes(best,n))) { best = sub }
                        sub = (sub-1) & remaining
                    }
                    groups.append(best)
                    remaining ^= best
                }
                let transfers = groups.map { mask in
                    greedy(Dictionary(uniqueKeysWithValues: indexes(mask,n).map { (names[$0],all[names[$0]]!) }))
                }
                output.append("SIMPLIFY OPTIMAL transfers \(transfers.reduce(0) { $0+$1.count }) groups \(groups.count)")
                for i in groups.indices {
                    output.append("  group "+indexes(groups[i],n).map { names[$0] }.joined(separator: " "))
                    for x in transfers[i] { output.append("    \(x.from) -> \(x.to) \(fmt(x.amount))") }
                }
            }
        default:
            preconditionFailure("Unreachable command")
        }
        if ["BALANCES","OWES","HISTORY","CATEGORY","BUDGETS","MEMBERS","PERIODS"].contains(command) && output.count == 1 {
            output.append("  (none)")
        }
        return output
    }
}

let app = Splitter()
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
