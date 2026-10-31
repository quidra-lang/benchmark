typealias Cents = Int64

struct CommandError: Error {
    let message: String
    init(_ message: String) {
        self.message = message
    }
}

enum AccountType: String, CaseIterable, Sendable {
    case asset = "ASSET", liability = "LIABILITY", equity = "EQUITY"
    case revenue = "REVENUE", expense = "EXPENSE", contraAsset = "CONTRA_ASSET"
    var sign: Cents {
        self == .asset || self == .expense ? 1 : -1
    }
    var group: AccountType {
        self == .contraAsset ? .asset : self
    }
    var isIncome: Bool {
        self == .revenue || self == .expense
    }
}

enum Category: String, Sendable {
    case journal, recurring, reversal, closing, reopen, depreciation, interest, writeoff
}

enum Side: String, Sendable {
    case debit = "DR", credit = "CR"
    var opposite: Side {
        self == .debit ? .credit : .debit
    }
}

func padded(_ value: Int, _ width: Int = 2) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

func money(_ value: Cents) -> String {
    let magnitude = value < 0 ? -value : value
    return "\(value < 0 ? "-" : "")\(magnitude / 100).\(padded(Int(magnitude % 100)))"
}

func parseMoney(_ text: String) -> Cents {
    let parts = text.split(separator: ".")
    return Cents(parts[0])! * 100 + Cents(parts[1])!
}

struct BookDate: Sendable {
    static let lastNumber = 36524
    static let monthLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    let year: Int
    let month: Int
    let day: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        return monthLengths[month - 1] + (month == 2 && leap ? 1 : 0)
    }

    static func parse(_ text: String) throws -> BookDate {
        let parts = text.split(separator: "-").map { Int($0)! }
        let year = parts[0], month = parts[1], day = parts[2]
        guard (2000...2099).contains(year), (1...12).contains(month),
              day >= 1, day <= daysInMonth(year, month)
        else {
            throw CommandError("invalid date \(text)")
        }
        return BookDate(year, month, day)
    }

    var number: Int {
        let previous = year - 1
        var result = 365 * (year - 2000) + previous / 4 - 1999 / 4
            - previous / 100 + 1999 / 100 + previous / 400 - 1999 / 400
        for month in 1..<self.month {
            result += Self.daysInMonth(year, month)
        }
        return result + day - 1
    }

    var text: String {
        "\(padded(year, 4))-\(padded(month))-\(padded(day))"
    }

    func addingMonths(_ count: Int) -> BookDate {
        let offset = month - 1 + count
        let year = self.year + offset / 12, month = offset % 12 + 1
        return BookDate(year, month, min(day, Self.daysInMonth(year, month)))
    }
}

func checkedRange(_ first: String, _ last: String) throws -> (BookDate, BookDate) {
    let start = try BookDate.parse(first)
    let end = try BookDate.parse(last)
    if start.number > end.number {
        throw CommandError("invalid range \(first) \(last)")
    }
    return (start, end)
}

final class Account {
    let code: String
    let type: AccountType
    let name: String
    var active = true

    init(_ code: String, _ type: AccountType, _ name: String) {
        self.code = code
        self.type = type
        self.name = name
    }
}

struct Line {
    let side: Side
    let code: String
    let amount: Cents
    let partner: String?

    init(_ side: Side, _ code: String, _ amount: Cents, _ partner: String? = nil) {
        self.side = side
        self.code = code
        self.amount = amount
        self.partner = partner
    }

    var difference: Cents {
        side == .debit ? amount : -amount
    }
    var reversed: Line {
        Line(side.opposite, code, amount, partner)
    }
}

func lineTotal(_ lines: [Line], _ side: Side = .debit) -> Cents {
    lines.reduce(0) { $0 + ($1.side == side ? $1.amount : 0) }
}

final class Entry {
    let id: String
    let date: BookDate
    let category: Category
    let memo: String
    let lines: [Line]
    let sequence: Int
    var reversedBy: String?
    var reverses: String?

    init(_ id: String, _ date: BookDate, _ category: Category, _ memo: String, _ lines: [Line], _ sequence: Int) {
        self.id = id
        self.date = date
        self.category = category
        self.memo = memo
        self.lines = lines
        self.sequence = sequence
    }
}

final class Template {
    let memo: String
    let lines: [Line]
    var uses = 0
    init(_ memo: String, _ lines: [Line]) {
        self.memo = memo
        self.lines = lines
    }
}

enum DraftKind {
    case journal(String), template
    var name: String {
        if case .journal = self {
            return "journal"
        }
        return "template"
    }
    var isJournal: Bool {
        if case .journal = self {
            return true
        }
        return false
    }
}

final class Draft {
    let kind: DraftKind
    let key: String
    let memo: String
    var lines: [Line] = []
    init(_ kind: DraftKind, _ key: String, _ memo: String) {
        self.kind = kind
        self.key = key
        self.memo = memo
    }
}

struct CloseRecord { let date: BookDate
    let entry: Entry?
}

struct Totals {
    var debit: Cents = 0
    var credit: Cents = 0
    var difference: Cents {
        debit - credit
    }
    mutating func add(_ line: Line) {
        if line.side == .debit {
            debit += line.amount
        } else {
            credit += line.amount
        }
    }
}

final class OpenItem {
    let entry: Entry
    let original: Cents
    var remaining: Cents
    init(_ entry: Entry, _ original: Cents, _ remaining: Cents) {
        self.entry = entry
        self.original = original
        self.remaining = remaining
    }
}

final class Settlement {
    var items: [OpenItem] = []
    var head = 0
    var unapplied: Cents = 0
    var openItems: ArraySlice<OpenItem> {
        items.dropFirst(head)
    }
}

final class Books {
    var accounts: [String: Account] = [:]
    var entries: [Entry] = []
    var entryIds: [String: Entry] = [:]
    var templates: [String: Template] = [:]
    var draft: Draft?
    var closes: [CloseRecord] = []
    var closeCount = 0, depreciationCount = 0, interestCount = 0, writeoffCount = 0
    var output: [String] = []

    func emit(_ line: String) {
        output.append(line)
    }
    var codes: [String] {
        accounts.keys.sorted()
    }
    var closed: String {
        closes.last?.date.text ?? "none"
    }

    func account(_ code: String, _ type: AccountType? = nil) throws -> Account {
        guard let result = accounts[code] else {
            throw CommandError("unknown account \(code)")
        }
        if let type, result.type != type {
            throw CommandError("wrong type \(code) \(type.rawValue)")
        }
        return result
    }

    func entry(_ id: String) throws -> Entry {
        guard let result = entryIds[id] else {
            throw CommandError("unknown entry \(id)")
        }
        return result
    }

    func active(_ codes: [String]) throws {
        for code in codes where !accounts[code]!.active {
            throw CommandError("inactive account \(code)")
        }
    }

    func checkClosed(_ date: BookDate) throws {
        if let record = closes.last,
           date.number <= record.date.number
        {
            throw CommandError("period closed \(date.text)")
        }
    }

    func ancestors(_ code: String) -> [String] {
        (1..<code.count).compactMap { length in
            let prefix = String(code.prefix(length))
            return accounts[prefix] == nil ? nil : prefix
        }
    }

    func parent(_ code: String) -> String {
        ancestors(code).last ?? "none"
    }
    func top(_ code: String) -> String {
        ancestors(code).first ?? code
    }

    func ordered(_ first: Int = 0, _ last: Int = BookDate.lastNumber) -> [Entry] {
        entries.filter { first <= $0.date.number && $0.date.number <= last }.sorted {
            $0.date.number == $1.date.number ? $0.sequence < $1.sequence : $0.date.number < $1.date.number
        }
    }

    func aggregate(_ first: Int = 0, _ last: Int = BookDate.lastNumber, operating: Bool = false) -> [String: Totals] {
        var totals: [String: Totals] = [:]
        for entry in entries {
            if entry.date.number < first || entry.date.number > last ||
                operating && (entry.category == .closing || entry.category == .reopen)
            {
                continue
            }
            for line in entry.lines {
                totals[line.code, default: Totals()].add(line)
            }
        }
        return totals
    }

    func balance(_ code: String, _ last: Int = BookDate.lastNumber) -> Cents {
        var difference: Cents = 0
        for entry in entries where entry.date.number <= last {
            for line in entry.lines where line.code == code {
                difference += line.difference
            }
        }
        return difference * accounts[code]!.type.sign
    }

    func dailySum(_ code: String, _ first: Int, _ last: Int) -> Cents {
        var changes = [Cents](repeating: 0, count: last - first + 1)
        var running: Cents = 0, sum: Cents = 0
        let sign = accounts[code]!.type.sign
        for entry in entries where entry.date.number <= last {
            for line in entry.lines where line.code == code {
                let change = sign * line.difference
                if entry.date.number < first {
                    running += change
                } else {
                    changes[entry.date.number - first] += change
                }
            }
        }
        for change in changes {
            running += change
            sum += running
        }
        return sum
    }

    @discardableResult
    func post(_ id: String, _ date: BookDate, _ category: Category, _ memo: String, _ lines: [Line]) -> Entry {
        let posted = Entry(id, date, category, memo, lines, entries.count + 1)
        entries.append(posted)
        entryIds[id] = posted
        return posted
    }

    func reverse(_ original: Entry, _ date: BookDate, _ category: Category, _ memo: String) -> Entry {
        let posted = post(original.id + "-R", date, category, memo, original.lines.map(\.reversed))
        original.reversedBy = posted.id
        posted.reverses = original.id
        return posted
    }

    func settlements(_ code: String, _ last: Int) -> [String: Settlement] {
        var result: [String: Settlement] = [:]
        let sign = accounts[code]!.type.sign
        for entry in ordered(0, last) {
            for line in entry.lines where line.code == code {
                guard let partner = line.partner else {
                    continue
                }
                let settled = result[partner] ?? Settlement()
                result[partner] = settled
                let value = sign * line.difference
                if value > 0 {
                    let applied = min(value, settled.unapplied)
                    settled.unapplied -= applied
                    if value > applied {
                        settled.items.append(OpenItem(entry, value, value - applied))
                    }
                } else {
                    var remaining = -value
                    while remaining > 0 && settled.head < settled.items.count {
                        let item = settled.items[settled.head]
                        let applied = min(remaining, item.remaining)
                        remaining -= applied
                        item.remaining -= applied
                        if item.remaining == 0 {
                            settled.head += 1
                        }
                    }
                    settled.unapplied += remaining
                }
            }
        }
        return result
    }

    func open(_ kind: DraftKind, _ key: String, _ memo: String) {
        if let draft {
            emit("DISCARD \(draft.key) lines \(draft.lines.count)")
        }
        draft = Draft(kind, key, memo)
    }

    func postDraft() throws {
        guard let block = draft else {
            throw CommandError("no open entry")
        }
        draft = nil
        var date: BookDate?
        switch block.kind {
        case .journal(let token):
            if entryIds[block.key] != nil {
                throw CommandError("duplicate entry \(block.key)")
            }
            date = try BookDate.parse(token)
            try checkClosed(date!)
        case .template:
            if templates[block.key] != nil {
                throw CommandError("duplicate template \(block.key)")
            }
        }
        if block.lines.count < 2 {
            throw CommandError("too few lines \(block.key)")
        }
        for line in block.lines {
            let found = try account(line.code)
            if block.kind.isJournal && !found.active {
                throw CommandError("inactive account \(line.code)")
            }
            if line.amount == 0 {
                throw CommandError("zero amount \(line.code)")
            }
        }
        let debit = lineTotal(block.lines), credit = lineTotal(block.lines, .credit)
        if debit !=
            credit
        {
            throw CommandError("unbalanced \(block.key) debit \(money(debit)) credit \(money(credit))")
        }
        if block.kind.isJournal {
            let posted = post(block.key, date!, .journal, block.memo, block.lines)
            emit("POST \(posted.id) \(posted.date.text) lines \(posted.lines.count) amount \(money(debit))")
        } else {
            templates[block.key] = Template(block.memo, block.lines)
            emit("TEMPLATE \(block.key) lines \(block.lines.count) amount \(money(debit))")
        }
    }

    func close(_ date: BookDate, _ equity: String) throws {
        try checkClosed(date)
        _ = try account(equity, .equity)
        try active([equity])
        let totals = aggregate(0, date.number)
        let targets = codes.filter { accounts[$0]!.type.isIncome && (totals[$0]?.difference ?? 0) != 0 }
        try active(targets)
        var lines: [Line] = []
        var income: Cents = 0
        for code in targets {
            let value = totals[code]!.difference
            lines.append(Line(value < 0 ? .debit : .credit, code, abs(value)))
            income -= value
        }
        if income != 0 {
            lines.append(Line(income < 0 ? .debit : .credit, equity, abs(income)))
        }
        closeCount += 1
        let entry = lines.isEmpty ? nil : post("CLOSE-\(closeCount)", date, .closing, "closing", lines)
        closes.append(CloseRecord(date: date, entry: entry))
        if let entry {
            emit("CLOSE \(date.text) entry \(entry.id) lines \(lines.count) net income \(money(income))")
        } else {
            emit("CLOSE \(date.text) no entry")
        }
    }

    func section(
        _ heading: String,
        _ types: Set<AccountType>,
        _ sign: Cents,
        _ totals: [String: Totals],
        earnings: Cents? = nil
    ) -> Cents {
        var groups: [String: [(String, Cents)]] = [:]
        var total = earnings ?? 0
        for code in codes where types.contains(accounts[code]!.type) {
            let value = sign * (totals[code]?.difference ?? 0)
            groups[top(code), default: []].append((code, value))
            total += value
        }
        emit("  \(heading) \(money(total))")
        for root in groups.keys.sorted() {
            let group = groups[root]!
            if !group.contains(where: { $0.1 != 0 }) {
                continue
            }
            let subtotal = group.reduce(0) { $0 + $1.1 }
            emit("    \(root) \(accounts[root]!.name) \(money(subtotal))")
            for (code, value) in group
                where value != 0
            {
                emit("      \(code) \(accounts[code]!.name) \(money(value))")
            }
        }
        if let earnings {
            emit("    current earnings \(money(earnings))")
        }
        return total
    }

    func ledger(_ code: String, _ first: BookDate, _ last: BookDate) {
        let found = accounts[code]!
        var running = balance(code, first.number - 1)
        var debit: Cents = 0, credit: Cents = 0
        emit("LEDGER \(code) \(found.name) \(first.text) \(last.text)")
        emit("  opening \(money(running))")
        for entry in ordered(first.number, last.number) {
            for line in entry.lines where line.code == code {
                running += found.type.sign * line.difference
                if line.side == .debit {
                    debit += line.amount
                } else {
                    credit += line.amount
                }
                emit(
                    "  \(entry.date.text) \(entry.id) \(line.side.rawValue) \(money(line.amount)) balance \(money(running)) \(entry.memo)"
                )
            }
        }
        let days = last.number - first.number + 1
        emit(
            "  ending \(money(running)) debits \(money(debit)) credits \(money(credit)) days \(days) average \(money(dailySum(code, first.number, last.number) / Cents(days)))"
        )
    }

    func agingLine(_ partner: String, _ amounts: [Cents]) {
        let balance = amounts.prefix(4).reduce(0, +) - amounts[4]
        emit(
            "  \(partner) 0-30 \(money(amounts[0])) 31-60 \(money(amounts[1])) 61-90 \(money(amounts[2])) 91+ \(money(amounts[3])) unapplied \(money(amounts[4])) balance \(money(balance))"
        )
    }

    func execute(_ words: [String]) throws {
        switch words[0] {
        case "ACCOUNT":
            let code = words[1]
            if accounts[code] != nil {
                throw CommandError("duplicate account \(code)")
            }
            let type = AccountType(rawValue: words[2])!
            for other in codes
                where (code.hasPrefix(other) || other.hasPrefix(code)) && type.group != accounts[other]!.type.group
            {
                throw CommandError("class mismatch \(code) \(other)")
            }
            accounts[code] = Account(code, type, words[3])
            emit("ACCOUNT \(code) \(type.rawValue) \(words[3]) parent \(parent(code))")
        case "DEACTIVATE":
            let found = try account(words[1])
            if !found.active {
                throw CommandError("already inactive \(found.code)")
            }
            let value = balance(found.code)
            if value != 0 {
                throw CommandError("nonzero balance \(found.code) \(money(value))")
            }
            found.active = false
            emit("DEACTIVATE \(found.code) \(found.name)")
        case "JOURNAL":
            open(.journal(words[2]), words[1], words[3])
        case "TEMPLATE":
            open(.template, words[1], words[2])
        case "DR", "CR":
            guard let draft else {
                throw CommandError("no open entry")
            }
            draft.lines.append(Line(
                Side(rawValue: words[0])!,
                words[1],
                parseMoney(words[2]),
                words.count == 4 ? words[3] : nil
            ))
        case "POST":
            try postDraft()
        case "DRAFT":
            guard let draft else {
                throw CommandError("no open entry")
            }
            let debit = lineTotal(draft.lines), credit = lineTotal(draft.lines, .credit)
            emit(
                "DRAFT \(draft.kind.name) \(draft.key) lines \(draft.lines.count) debit \(money(debit)) credit \(money(credit)) difference \(money(debit - credit))"
            )
        case "REVERSE":
            let original = try entry(words[1])
            if [.reversal, .closing, .reopen]
                .contains(original.category)
            {
                throw CommandError("cannot reverse \(original.id)")
            }
            if original.reversedBy != nil {
                throw CommandError("already reversed \(original.id)")
            }
            let date = try BookDate.parse(words[2])
            if date.number < original.date
                .number
            {
                throw CommandError("reverse before entry \(original.id) \(original.date.text)")
            }
            try checkClosed(date)
            try active(original.lines.map(\.code))
            let posted = reverse(original, date, .reversal, original.memo)
            emit("REVERSE \(original.id) entry \(posted.id) \(date.text) amount \(money(lineTotal(posted.lines)))")
        case "RECUR":
            guard let template = templates[words[1]] else {
                throw CommandError("unknown template \(words[1])")
            }
            let date = try BookDate.parse(words[2])
            let count = Int(words[3])!
            if count == 0 {
                throw CommandError("invalid count")
            }
            try checkClosed(date)
            try active(template.lines.map(\.code))
            emit("RECUR \(words[1]) count \(count)")
            for month in 0..<count {
                template.uses += 1
                let posted = post(
                    "\(words[1])-\(template.uses)",
                    date.addingMonths(month),
                    .recurring,
                    template.memo,
                    template.lines
                )
                emit(
                    "  POST \(posted.id) \(posted.date.text) lines \(posted.lines.count) amount \(money(lineTotal(posted.lines)))"
                )
            }
        case "DEPRECIATE":
            let date = try BookDate.parse(words[1])
            try checkClosed(date)
            _ = try account(words[2], .asset)
            _ = try account(words[3], .contraAsset)
            _ = try account(words[4], .expense)
            try active([words[3], words[4]])
            let cost = balance(words[2], date.number), accumulated = balance(words[3], date.number)
            let amount = cost > 0 ? min(cost / Cents(words[5])!, cost - accumulated) : 0
            if amount <= 0 {
                throw CommandError("nothing to depreciate \(words[2])")
            }
            depreciationCount += 1
            let posted = post(
                "DEP-\(depreciationCount)",
                date,
                .depreciation,
                "depreciation",
                [Line(.debit, words[4], amount), Line(.credit, words[3], amount)]
            )
            emit(
                "DEPRECIATE \(words[2]) entry \(posted.id) \(date.text) amount \(money(amount)) accumulated \(money(accumulated + amount)) book \(money(cost - accumulated - amount))"
            )
        case "INTEREST":
            let found = try account(words[1])
            if found.type != .asset && found
                .type != .liability
            {
                throw CommandError("not interest bearing \(found.code)")
            }
            _ = try account(words[2], found.type == .asset ? .revenue : .expense)
            let (first, last) = try checkedRange(words[3], words[4])
            try checkClosed(last)
            try active([words[1], words[2]])
            let sum = dailySum(found.code, first.number, last.number)
            let amount = sum * Cents(words[5])! / 3650000
            if amount <= 0 {
                throw CommandError("no interest \(found.code)")
            }
            interestCount += 1
            let asset = found.type == .asset
            let posted = post("INT-\(interestCount)", last, .interest, "interest",
                              [
                                  Line(.debit, asset ? words[1] : words[2], amount),
                                  Line(.credit, asset ? words[2] : words[1], amount)
                              ])
            let days = last.number - first.number + 1
            emit(
                "INTEREST \(found.code) entry \(posted.id) \(last.text) days \(days) average \(money(sum / Cents(days))) amount \(money(amount))"
            )
        case "WRITEOFF":
            let date = try BookDate.parse(words[1])
            try checkClosed(date)
            _ = try account(words[2], .asset)
            _ = try account(words[3], .expense)
            try active([words[2], words[3]])
            let age = Int(words[4])!
            let groups = settlements(words[2], date.number)
            var targets: [(String, Cents)] = []
            var total: Cents = 0
            for partner in groups.keys.sorted() {
                let amount = groups[partner]!.openItems.filter { date.number - $0.entry.date.number > age }
                    .reduce(0) { $0 + $1.remaining }
                if amount > 0 {
                    targets.append((partner, amount))
                    total += amount
                }
            }
            if total == 0 {
                throw CommandError("nothing to write off \(words[2])")
            }
            let lines = [Line(.debit, words[3], total)] + targets.map { Line(.credit, words[2], $0.1, $0.0) }
            writeoffCount += 1
            let posted = post("WO-\(writeoffCount)", date, .writeoff, "writeoff", lines)
            emit(
                "WRITEOFF \(words[2]) entry \(posted.id) \(date.text) partners \(targets.count) amount \(money(total))"
            )
            for (partner, amount) in targets {
                emit("  \(partner) \(money(amount))")
            }
        case "CLOSE":
            try close(BookDate.parse(words[1]), words[2])
        case "REOPEN":
            guard let record = closes.last else {
                throw CommandError("nothing to reopen")
            }
            var result = "no entry"
            if let original = record.entry {
                try active(original.lines.map(\.code))
                result = "entry " + reverse(original, record.date, .reopen, "reopen").id
            }
            closes.removeLast()
            emit("REOPEN \(record.date.text) \(result) closed \(closed)")
        case "LEDGER":
            _ = try account(words[1])
            let (first, last) = try checkedRange(words[2], words[3])
            ledger(words[1], first, last)
        case "ACTIVITY":
            let found = try account(words[1])
            let year = Int(words[2])!
            var debit: Cents = 0, credit: Cents = 0
            emit("ACTIVITY \(found.code) \(found.name) \(year)")
            for month in 1...12 {
                let first = BookDate(year, month, 1).number
                let last = BookDate(year, month, BookDate.daysInMonth(year, month)).number
                let total = aggregate(first, last)[found.code] ?? Totals()
                debit += total.debit
                credit += total.credit
                emit(
                    "  \(padded(year, 4))-\(padded(month)) debit \(money(total.debit)) credit \(money(total.credit)) balance \(money(balance(found.code, last)))"
                )
            }
            emit("  total debit \(money(debit)) credit \(money(credit))")
        case "TRIAL":
            let date = try BookDate.parse(words[1])
            let totals = aggregate(0, date.number)
            var debit: Cents = 0, credit: Cents = 0
            emit("TRIAL \(date.text)")
            for code in codes {
                let value = totals[code]?.difference ?? 0
                if value == 0 {
                    continue
                }
                if value > 0 {
                    debit += value
                } else {
                    credit -= value
                }
                emit("  \(code) \(accounts[code]!.name) \(value > 0 ? "debit" : "credit") \(money(abs(value)))")
            }
            emit("  total debit \(money(debit)) credit \(money(credit))")
        case "INCOME":
            let (first, last) = try checkedRange(words[1], words[2])
            let totals = aggregate(first.number, last.number, operating: true)
            emit("INCOME \(first.text) \(last.text)")
            let revenue = section("REVENUE", [.revenue], -1, totals)
            let expense = section("EXPENSE", [.expense], 1, totals)
            emit("  NET INCOME \(money(revenue - expense))")
        case "BALANCE":
            let date = try BookDate.parse(words[1])
            let totals = aggregate(0, date.number)
            let earnings = -codes.filter { accounts[$0]!.type.isIncome }
                .reduce(Cents(0)) { $0 + (totals[$1]?.difference ?? 0) }
            emit("BALANCE \(date.text)")
            let assets = section("ASSETS", [.asset, .contraAsset], 1, totals)
            let liabilities = section("LIABILITIES", [.liability], -1, totals)
            let equity = section("EQUITY", [.equity], -1, totals, earnings: earnings)
            emit(assets == liabilities + equity ? "  check ok" :
                "  check mismatch \(money(assets - liabilities - equity))")
        case "ROLLUP":
            let date = try BookDate.parse(words[2])
            let targets = codes.filter { $0.hasPrefix(words[1]) }
            emit("ROLLUP \(words[1]) \(date.text)")
            if targets.isEmpty {
                emit("  (none)")
                return
            }
            let totals = aggregate(0, date.number)
            var debit: Cents = 0, credit: Cents = 0
            for code in targets {
                let depth = targets.filter { $0 != code && code.hasPrefix($0) }.count
                let subtotal = targets.filter { $0.hasPrefix(code) }
                    .reduce(Cents(0)) { $0 + (totals[$1]?.difference ?? 0) }
                let own = totals[code] ?? Totals()
                let sign = accounts[code]!.type.sign
                let indent = String(repeating: " ", count: 2 * (1 + depth))
                emit(
                    "\(indent)\(code) \(accounts[code]!.name) own \(money(sign * own.difference)) total \(money(sign * subtotal))"
                )
                debit += own.debit
                credit += own.credit
            }
            emit("  postings debit \(money(debit)) credit \(money(credit))")
        case "AGING":
            let found = try account(words[1])
            let date = try BookDate.parse(words[2])
            let groups = settlements(found.code, date.number)
            var total = [Cents](repeating: 0, count: 5)
            emit("AGING \(found.code) \(found.name) \(date.text)")
            for partner in groups.keys.sorted() {
                let settled = groups[partner]!
                if settled.openItems.isEmpty && settled.unapplied == 0 {
                    continue
                }
                var amounts = [Cents](repeating: 0, count: 5)
                for item in settled.openItems {
                    let age = date.number - item.entry.date.number
                    amounts[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += item.remaining
                }
                amounts[4] = settled.unapplied
                for i in 0..<5 {
                    total[i] += amounts[i]
                }
                agingLine(partner, amounts)
            }
            agingLine("total", total)
        case "ITEMS":
            let found = try account(words[1])
            let date = try BookDate.parse(words[3])
            let settled = settlements(found.code, date.number)[words[2]] ?? Settlement()
            var balance = -settled.unapplied
            emit("ITEMS \(found.code) \(found.name) \(words[2]) \(date.text)")
            for item in settled.openItems {
                emit(
                    "  \(item.entry.date.text) \(item.entry.id) amount \(money(item.original)) open \(money(item.remaining)) age \(date.number - item.entry.date.number)"
                )
                balance += item.remaining
            }
            emit("  unapplied \(money(settled.unapplied)) balance \(money(balance))")
        case "ENTRY":
            let found = try entry(words[1])
            emit("ENTRY \(found.id) \(found.date.text) \(found.category.rawValue) \(found.memo)")
            for line in found.lines {
                let suffix = line.partner.map { " " + $0 } ?? ""
                emit("  \(line.side.rawValue) \(line.code) \(accounts[line.code]!.name) \(money(line.amount))\(suffix)")
            }
            emit("  total \(money(lineTotal(found.lines)))")
            if let reverses = found.reverses {
                emit("  reverses \(reverses)")
            }
            if let reversedBy = found.reversedBy {
                emit("  reversed by \(reversedBy)")
            }
        case "DAYBOOK":
            let (first, last) = try checkedRange(words[1], words[2])
            let selected = ordered(first.number, last.number)
            var total: Cents = 0
            emit("DAYBOOK \(first.text) \(last.text)")
            for entry in selected {
                let amount = lineTotal(entry.lines)
                emit("  \(entry.date.text) \(entry.id) \(entry.category.rawValue) \(money(amount)) \(entry.memo)")
                total += amount
            }
            emit("  total entries \(selected.count) amount \(money(total))")
        case "ACCOUNTS":
            let totals = aggregate()
            emit("ACCOUNTS")
            for code in codes {
                let found = accounts[code]!
                emit(
                    "  \(code) \(found.type.rawValue) \(found.name) parent \(parent(code)) balance \(money(found.type.sign * (totals[code]?.difference ?? 0))) \(found.active ? "active" : "inactive")"
                )
            }
            if accounts.isEmpty {
                emit("  (none)")
            }
        case "TEMPLATES":
            emit("TEMPLATES")
            for name in templates.keys.sorted() {
                let template = templates[name]!
                emit(
                    "  \(name) \(template.memo) lines \(template.lines.count) amount \(money(lineTotal(template.lines))) used \(template.uses)"
                )
            }
            if templates.isEmpty {
                emit("  (none)")
            }
        case "STATUS":
            let inactive = accounts.values.filter { !$0.active }.count
            emit(
                "STATUS accounts \(accounts.count) inactive \(inactive) entries \(entries.count) templates \(templates.count) closed \(closed) open \(draft?.key ?? "none")"
            )
        default:
            preconditionFailure("unexpected command")
        }
    }
}

let count = Int(readLine()!)!
let books = Books()
for _ in 0..<count {
    let words = readLine()!.split(separator: " ").map(String.init)
    do {
        try books.execute(words)
    } catch let error as CommandError {
        books.emit("ERROR \(error.message)")
    }
}
if !books.output.isEmpty {
    print(books.output.joined(separator: "\n"))
}
