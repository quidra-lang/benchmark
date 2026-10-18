import Foundation

enum Fault: Error { case reason(String) }
func failIf(_ condition: Bool, _ reason: String) throws {
    if condition { throw Fault.reason(reason) }
}
func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(of:"\\A(?:"+pattern+")\\z",options:.regularExpression) != nil
}
func normalize(_ raw: String) throws -> String {
    let s = raw.replacingOccurrences(of:"-",with:"")
    let a = Array(s.utf8)
    if matches(s,"[0-9]{9}[0-9X]") {
        var sum = 0
        for i in 0..<10 { sum += (10-i)*(a[i] == 88 ? 10 : Int(a[i])-48) }
        try failIf(sum%11 != 0,"invalid isbn")
        let prefix = "978"+String(s.prefix(9))
        let digits = Array(prefix.utf8)
        sum = 0
        for i in 0..<12 { sum += (i%2 == 0 ? 1 : 3)*(Int(digits[i])-48) }
        return prefix+String((10-sum%10)%10)
    }
    try failIf(!matches(s,"97[89][0-9]{10}"),"invalid isbn")
    var sum = 0
    for i in 0..<13 { sum += (i%2 == 0 ? 1 : 3)*(Int(a[i])-48) }
    try failIf(sum%10 != 0,"invalid isbn")
    return s
}
func parseMoney(_ s: String) -> Int {
    let p = s.split(separator:".")
    return Int(p[0])!*100+Int(p[1])!
}
func money(_ n: Int) -> String { "\(n/100)."+(n%100 < 10 ? "0" : "")+String(n%100) }
func lower(_ s: String) -> String {
    String(bytes:s.utf8.map { $0 >= 65 && $0 <= 90 ? $0+32 : $0 },encoding:.utf8)!
}
final class Item {
    let day: Int
    let kind: String
    let isbn: String
    let amount: Int
    var unpaid: Int
    init(_ day: Int, _ kind: String, _ isbn: String, _ amount: Int) {
        self.day = day
        self.kind = kind
        self.isbn = isbn
        self.amount = amount
        unpaid = amount
    }
}
final class Member {
    let id: String
    let type: String
    let name: String
    let limit: Int
    let period: Int
    let rate: Int
    let cap: Int
    let reservationLimit: Int
    let fee: Int
    var queued = 0
    var loans: [String:Copy] = [:]
    var holds: [String:Copy] = [:]
    var items: [Item] = []
    var history: [String] = []
    init(_ id: String, _ type: String, _ name: String) {
        self.id = id
        self.type = type
        self.name = name
        let student = type == "STUDENT"
        limit = student ? 3 : 10
        period = student ? 14 : 28
        rate = student ? 25 : 10
        cap = student ? 1000 : 2000
        reservationLimit = student ? 2 : 5
        fee = student ? 50 : 100
    }
    func balance() -> Int { items.reduce(0) { $0+$1.unpaid } }
    func reservations() -> Int { queued+holds.count }
    func blocked() -> Bool { balance() > 500 }
    func status() -> String { blocked() ? "BLOCKED" : "OK" }
}
final class Title {
    let isbn: String
    let name: String
    var price: Int
    var borrowed = 0
    var copies: [Copy] = []
    var queue: [Member] = []
    init(_ isbn: String, _ name: String, _ price: Int) {
        self.isbn = isbn
        self.name = name
        self.price = price
    }
    func count(_ state: String) -> Int { copies.filter { $0.state == state }.count }
    func holdings() -> Int { count("AVAILABLE")+count("LOANED")+count("HOLD") }
}
final class Copy {
    unowned let title: Title
    let number: Int
    var state = "AVAILABLE"
    weak var owner: Member?
    var loanDay = 0
    var due = 0
    var renewals = 0
    var expiry = 0
    init(_ title: Title, _ number: Int) {
        self.title = title
        self.number = number
    }
}
final class Library {
    var day = 1
    var borrowed = 0
    var returned = 0
    var renewed = 0
    var lost = 0
    var fines = 0
    var fees = 0
    var charges = 0
    var paid = 0
    var waived = 0
    var titles: [String:Title] = [:]
    var members: [String:Member] = [:]
    var closed = Set<Int>()
    var copies: [Copy] = []
    var output: [String] = []
    func emit(_ line: String) { output.append(line) }
    func orderedTitles() -> [Title] { titles.keys.sorted().map { titles[$0]! } }
    func orderedMembers() -> [Member] { members.keys.sorted().map { members[$0]! } }
    func member(_ id: String) throws -> Member {
        guard let m = members[id] else { throw Fault.reason("unknown member") }
        return m
    }
    func book(_ raw: String) throws -> Title {
        let isbn = try normalize(raw)
        guard let b = titles[isbn] else { throw Fault.reason("unknown book") }
        return b
    }
    func loan(_ m: Member, _ b: Title) throws -> Copy {
        guard let c = m.loans[b.isbn] else { throw Fault.reason("not borrowed") }
        return c
    }
    func open(_ start: Int) -> Int {
        var d = start
        while closed.contains(d) { d += 1 }
        return d
    }
    func late(_ c: Copy) -> Int { max(0,day-c.due) }
    func fine(_ c: Copy) -> Int { min(late(c)*c.owner!.rate,c.owner!.cap) }
    func charge(_ m: Member, _ kind: String, _ b: Title, _ amount: Int) {
        if amount == 0 { return }
        m.items.append(Item(day,kind,b.isbn,amount))
        switch kind {
        case "FINE": fines += amount
        case "FEE": fees += amount
        default: charges += amount
        }
    }
    func release(_ c: Copy) {
        let b = c.title
        c.owner = nil
        if b.queue.isEmpty { c.state = "AVAILABLE" }
        else {
            let m = b.queue.removeFirst()
            m.queued -= 1
            c.state = "HOLD"
            c.owner = m
            c.expiry = open(day+3)
            m.holds[b.isbn] = c
            emit("HOLD \(b.isbn) copy \(c.number) \(m.id) until \(c.expiry)")
        }
    }
    func endLoan(_ c: Copy, _ loss: Bool) -> (Int,Int) {
        let m = c.owner!
        let l = late(c)
        let f = fine(c)
        m.loans.removeValue(forKey:c.title.isbn)
        charge(m,"FINE",c.title,f)
        m.history.append((loss ? "LOST " : "RETURNED ")+"\(c.title.isbn) copy \(c.number)"+
            " from \(c.loanDay) to \(day) late \(l) fine \(money(f))"+(loss ? " price \(money(c.title.price))" : ""))
        return (l,f)
    }
    func loss(_ c: Copy, _ heading: String) {
        let m = c.owner!
        let b = c.title
        let (l,f) = endLoan(c,true)
        charge(m,"PRICE",b,b.price)
        c.state = "LOST"
        c.owner = nil
        lost += 1
        emit("\(heading) \(m.id) \(b.isbn) copy \(c.number) late \(l) fine \(money(f)) price \(money(b.price)) balance \(money(m.balance()))")
        if b.holdings() == 0 {
            for queued in b.queue {
                queued.queued -= 1
                emit("DROPPED \(b.isbn) \(queued.id)")
            }
            b.queue.removeAll()
        }
    }
    func renewalReason(_ c: Copy) -> String? {
        if c.due < day { return "loan overdue" }
        if c.renewals == 2 { return "renewal limit" }
        if !c.title.queue.isEmpty { return "title reserved" }
        return nil
    }
    func renew(_ c: Copy) {
        c.due = open(day+c.owner!.period)
        c.renewals += 1
        renewed += 1
        emit("RENEW \(c.owner!.id) \(c.title.isbn) copy \(c.number) due \(c.due) renewals \(c.renewals)")
    }
    func orderedLoans(_ m: Member) -> [Copy] {
        m.loans.values.sorted {
            if $0.due != $1.due { return $0.due < $1.due }
            return $0.title.isbn < $1.title.isbn
        }
    }
    func orderedHolds(_ m: Member) -> [Copy] {
        m.holds.values.sorted {
            if $0.expiry != $1.expiry { return $0.expiry < $1.expiry }
            return $0.title.isbn < $1.title.isbn
        }
    }
    func showMember(_ m: Member) {
        emit("MEMBER \(m.id) \(m.type) \(m.name)")
        emit("STATUS loans \(m.loans.count)/\(m.limit) reservations \(m.reservations())/\(m.reservationLimit) balance \(money(m.balance())) \(m.status())")
        for c in orderedLoans(m) {
            emit("LOAN \(c.title.isbn) copy \(c.number) due \(c.due) renewals \(c.renewals)"+
                (c.due < day ? " late \(late(c)) fine \(money(fine(c)))" : ""))
        }
        for c in orderedHolds(m) { emit("HOLD \(c.title.isbn) copy \(c.number) until \(c.expiry)") }
        for b in orderedTitles() {
            if let p = b.queue.firstIndex(where:{ $0 === m }) { emit("QUEUE \(b.isbn) position \(p+1)") }
        }
    }
    func execute(_ line: String) throws {
        let t = line.split(separator:" ").map(String.init)
        switch t[0] {
        case "DAY":
            let d = Int(t[1])!
            try failIf(d <= day,"invalid day")
            emit("DAY \(d)")
            while day < d {
                day += 1
                let losses = copies.filter { $0.state == "LOANED" && $0.due+365 <= day }.sorted {
                    if $0.owner!.id != $1.owner!.id { return $0.owner!.id < $1.owner!.id }
                    return $0.title.isbn < $1.title.isbn
                }
                for c in losses { loss(c,"AUTOLOST") }
                let expired = copies.filter { $0.state == "HOLD" && $0.expiry < day }.sorted {
                    if $0.title.isbn != $1.title.isbn { return $0.title.isbn < $1.title.isbn }
                    return $0.number < $1.number
                }
                for c in expired {
                    let m = c.owner!
                    charge(m,"FEE",c.title,m.fee)
                    m.holds.removeValue(forKey:c.title.isbn)
                    emit("EXPIRED \(c.title.isbn) copy \(c.number) \(m.id) fee \(money(m.fee))")
                    release(c)
                }
            }
        case "CLOSED":
            let d = Int(t[1])!
            try failIf(d <= day,"invalid day")
            try failIf(closed.contains(d),"already closed")
            closed.insert(d)
            emit("CLOSED \(d)")
            for b in orderedTitles() {
                for c in b.copies {
                    if c.state == "LOANED" && c.due == d {
                        c.due = open(d)
                        emit("MOVED \(b.isbn) copy \(c.number) \(c.owner!.id) due \(c.due)")
                    } else if c.state == "HOLD" && c.expiry == d {
                        c.expiry = open(d)
                        emit("MOVED \(b.isbn) copy \(c.number) \(c.owner!.id) until \(c.expiry)")
                    }
                }
            }
        case "ADDBOOK":
            let isbn = try normalize(t[1])
            let name = t.dropFirst(4).joined(separator:" ")
            let existing = titles[isbn]
            try failIf(existing != nil && existing!.name != name,"title mismatch")
            let count = Int(t[2])!
            let price = parseMoney(t[3])
            let b = existing ?? Title(isbn,name,price)
            titles[isbn] = b
            b.price = price
            var added: [Copy] = []
            for _ in 0..<count {
                let c = Copy(b,b.copies.count+1)
                b.copies.append(c)
                copies.append(c)
                added.append(c)
            }
            emit("ADDBOOK \(isbn) added \(count) total \(b.holdings())")
            for c in added { release(c) }
        case "ADDMEMBER":
            try failIf(members[t[1]] != nil,"duplicate member")
            try failIf(t[2] != "STUDENT" && t[2] != "STAFF","unknown type")
            let m = Member(t[1],t[2],t.dropFirst(3).joined(separator:" "))
            members[m.id] = m
            emit("ADDMEMBER \(m.id) \(m.type) loans \(m.limit) days \(m.period)")
        case "WITHDRAW":
            let b = try book(t[1])
            let n = Int(t[2])!
            try failIf(n < 1 || n > b.copies.count,"unknown copy")
            let c = b.copies[n-1]
            try failIf(c.state != "AVAILABLE","copy not available")
            c.state = "WITHDRAWN"
            emit("WITHDRAW \(b.isbn) copy \(n) total \(b.holdings())")
        case "BORROW":
            let m = try member(t[1])
            let b = try book(t[2])
            try failIf(closed.contains(day),"library closed")
            try failIf(m.loans[b.isbn] != nil,"already borrowed")
            try failIf(m.blocked(),"member blocked")
            try failIf(m.loans.values.contains { $0.due < day },"overdue loans")
            try failIf(m.loans.count >= m.limit,"loan limit")
            guard let c = m.holds[b.isbn] ?? b.copies.first(where:{ $0.state == "AVAILABLE" }) else {
                throw Fault.reason(b.count("HOLD") > 0 ? "all copies on hold" : "no copy available")
            }
            m.holds.removeValue(forKey:b.isbn)
            c.state = "LOANED"
            c.owner = m
            c.loanDay = day
            c.due = open(day+m.period)
            c.renewals = 0
            m.loans[b.isbn] = c
            b.borrowed += 1
            borrowed += 1
            emit("BORROW \(m.id) \(b.isbn) copy \(c.number) due \(c.due)")
        case "RETURN":
            let m = try member(t[1])
            let b = try book(t[2])
            let c = try loan(m,b)
            let (l,f) = endLoan(c,false)
            returned += 1
            emit("RETURN \(m.id) \(b.isbn) copy \(c.number) late \(l) fine \(money(f)) balance \(money(m.balance()))")
            release(c)
        case "RENEW":
            let m = try member(t[1])
            let c = try loan(m,book(t[2]))
            try failIf(m.blocked(),"member blocked")
            if let reason = renewalReason(c) { throw Fault.reason(reason) }
            renew(c)
        case "RENEWALL":
            let m = try member(t[1])
            try failIf(m.loans.isEmpty,"no loans")
            try failIf(m.blocked(),"member blocked")
            var done = 0
            var skipped = 0
            for isbn in m.loans.keys.sorted() {
                let c = m.loans[isbn]!
                if let reason = renewalReason(c) {
                    emit("SKIP \(c.title.isbn) \(reason)")
                    skipped += 1
                } else {
                    renew(c)
                    done += 1
                }
            }
            emit("RENEWALL \(m.id) renewed \(done) skipped \(skipped)")
        case "RESERVE":
            let m = try member(t[1])
            let b = try book(t[2])
            try failIf(m.loans[b.isbn] != nil,"already borrowed")
            try failIf(b.queue.contains { $0 === m } || m.holds[b.isbn] != nil,"already reserved")
            try failIf(m.blocked(),"member blocked")
            try failIf(m.reservations() >= m.reservationLimit,"reservation limit")
            try failIf(b.holdings() == 0,"no copies")
            try failIf(b.count("AVAILABLE") > 0,"copy available")
            b.queue.append(m)
            m.queued += 1
            let p = b.queue.count
            let dues = b.copies.filter { $0.state == "LOANED" }.map { $0.due }.sorted()
            let estimate = p <= dues.count ? String(dues[p-1]) : "none"
            emit("RESERVE \(m.id) \(b.isbn) position \(p) estimate \(estimate)")
        case "CANCEL":
            let m = try member(t[1])
            let b = try book(t[2])
            let p = b.queue.firstIndex { $0 === m }
            let c = m.holds[b.isbn]
            try failIf(p == nil && c == nil,"not reserved")
            if let p {
                b.queue.remove(at:p)
                m.queued -= 1
                emit("CANCEL \(m.id) \(b.isbn) queue")
            } else {
                m.holds.removeValue(forKey:b.isbn)
                emit("CANCEL \(m.id) \(b.isbn) hold copy \(c!.number)")
                release(c!)
            }
        case "LOST":
            let m = try member(t[1])
            try loss(loan(m,book(t[2])),"LOST")
        case "PAYFINE":
            let m = try member(t[1])
            try failIf(m.balance() == 0,"no fines")
            let amount = parseMoney(t[2])
            var rest = amount
            var details: [String] = []
            for (i,item) in m.items.enumerated() {
                if rest == 0 { break }
                let applied = min(rest,item.unpaid)
                if applied == 0 { continue }
                rest -= applied
                item.unpaid -= applied
                details.append("ITEM \(i+1) \(item.kind) paid \(money(applied)) remaining \(money(item.unpaid))")
            }
            paid += amount-rest
            emit("PAYFINE \(m.id) paid \(money(amount-rest)) change \(money(rest)) balance \(money(m.balance()))")
            output.append(contentsOf:details)
        case "WAIVE":
            let m = try member(t[1])
            let n = Int(t[2])!
            try failIf(n < 1 || n > m.items.count,"unknown item")
            let item = m.items[n-1]
            try failIf(item.unpaid == 0,"item settled")
            let amount = item.unpaid
            item.unpaid = 0
            waived += amount
            emit("WAIVE \(m.id) item \(n) \(item.kind) amount \(money(amount)) balance \(money(m.balance()))")
        case "FINES":
            let m = try member(t[1])
            emit("FINES \(m.id) items \(m.items.filter { $0.unpaid > 0 }.count) balance \(money(m.balance()))")
            for (i,item) in m.items.enumerated() where item.unpaid > 0 {
                emit("\(i+1) day \(item.day) \(item.kind) \(item.isbn) amount \(money(item.amount)) remaining \(money(item.unpaid))")
            }
        case "SEARCH":
            let keyword = lower(t.dropFirst().joined(separator:" "))
            let found = titles.values.filter { lower($0.name).contains(keyword) }.sorted {
                let a = lower($0.name)
                let b = lower($1.name)
                return a == b ? $0.isbn < $1.isbn : a < b
            }
            emit("SEARCH \(found.count)")
            for b in found { emit("\(b.isbn) \(b.count("AVAILABLE"))/\(b.holdings()) \(b.name)") }
        case "OVERDUE":
            let found = copies.filter { $0.state == "LOANED" && $0.due < day }.sorted {
                if $0.due != $1.due { return $0.due < $1.due }
                if $0.owner!.id != $1.owner!.id { return $0.owner!.id < $1.owner!.id }
                return $0.title.isbn < $1.title.isbn
            }
            emit("OVERDUE \(found.count)")
            for c in found { emit("\(c.owner!.id) \(c.title.isbn) copy \(c.number) due \(c.due) late \(late(c)) fine \(money(fine(c)))") }
        case "NOTICES":
            var notices: [String] = []
            for m in orderedMembers() {
                let loans = orderedLoans(m)
                for c in loans where c.due < day { notices.append("OVERDUE \(m.id) \(c.title.isbn) due \(c.due)") }
                for c in loans where c.due >= day && c.due <= day+2 { notices.append("DUESOON \(m.id) \(c.title.isbn) due \(c.due)") }
                for c in orderedHolds(m) { notices.append("PICKUP \(m.id) \(c.title.isbn) until \(c.expiry)") }
            }
            emit("NOTICES \(notices.count)")
            output.append(contentsOf:notices)
        case "MEMBER": try showMember(member(t[1]))
        case "MEMBERS":
            emit("MEMBERS \(members.count)")
            for m in orderedMembers() {
                emit("\(m.id) \(m.type) loans \(m.loans.count) reservations \(m.reservations()) balance \(money(m.balance())) \(m.status())")
            }
        case "BOOK":
            let b = try book(t[1])
            emit("BOOK \(b.isbn) \(b.name)")
            emit("PRICE \(money(b.price)) copies \(b.holdings()) borrowed \(b.borrowed)")
            for c in b.copies {
                let detail: String
                if c.state == "LOANED" { detail = " \(c.owner!.id) due \(c.due)" }
                else if c.state == "HOLD" { detail = " \(c.owner!.id) until \(c.expiry)" }
                else { detail = "" }
                emit("COPY \(c.number) \(c.state)\(detail)")
            }
            emit("QUEUE \(b.queue.count)"+(b.queue.isEmpty ? "" : " "+b.queue.map { $0.id }.joined(separator:" ")))
        case "INVENTORY":
            let a = copies.filter { $0.state == "AVAILABLE" }.count
            let l = copies.filter { $0.state == "LOANED" }.count
            let h = copies.filter { $0.state == "HOLD" }.count
            let x = copies.filter { $0.state == "LOST" }.count
            let w = copies.filter { $0.state == "WITHDRAWN" }.count
            emit("INVENTORY titles \(titles.count) copies \(a+l+h) available \(a) loaned \(l) hold \(h) lost \(x) withdrawn \(w)")
            for b in orderedTitles() {
                emit("\(b.isbn) copies \(b.holdings()) available \(b.count("AVAILABLE")) loaned \(b.count("LOANED")) hold \(b.count("HOLD")) queue \(b.queue.count)")
            }
        case "HISTORY":
            let m = try member(t[1])
            emit("HISTORY \(m.id) \(m.history.count)")
            output.append(contentsOf:m.history)
        case "STATS":
            let active = members.values.reduce(0) { $0+$1.loans.count }
            let outstanding = members.values.reduce(0) { $0+$1.balance() }
            emit("STATS day \(day) titles \(titles.count) members \(members.count) closed \(closed.count)")
            emit("LOANS borrowed \(borrowed) returned \(returned) renewed \(renewed) lost \(lost) active \(active)")
            emit("MONEY fines \(money(fines)) fees \(money(fees)) charges \(money(charges)) paid \(money(paid)) waived \(money(waived)) outstanding \(money(outstanding))")
            let top = titles.values.filter { $0.borrowed > 0 }.sorted {
                $0.borrowed == $1.borrowed ? $0.isbn < $1.isbn : $0.borrowed > $1.borrowed
            }.prefix(3)
            for (i,b) in top.enumerated() { emit("TOP \(i+1) \(b.isbn) \(b.borrowed) \(b.name)") }
        default: break
        }
    }
    func process(_ line: String) -> [String] {
        output = []
        do { try execute(line) }
        catch Fault.reason(let reason) { output.append("ERROR "+reason) }
        catch { fatalError("Unexpected error") }
        return output
    }
}
let library = Library()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    for line in library.process(readLine()!) { print(line) }
}
