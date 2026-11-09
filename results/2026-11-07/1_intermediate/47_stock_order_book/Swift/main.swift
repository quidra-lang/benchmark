import Foundation
struct CommandError: Error {
    let reason: String
}
func require(_ good: Bool, _ reason: String) throws {
    if !good {
        throw CommandError(reason: reason)
    }
}
func decimal(_ x: Int) -> String {
    "\(x / 100)." + String(format: "%02d", x % 100)
}
func opposite(_ side: String) -> String {
    side == "BUY" ? "SELL" : "BUY"
}
final class Order {
    let id: String, trader: String, kind: String, side: String
    var condition = "", status = "OPEN"
    var price: Int?, trigger: Int?, peak: Int?
    var quantity: Int, remaining: Int, visible = 0, filled = 0, value = 0, priority = 0, number = 0
    var history = ["ACCEPT"]
    init(_ id: String, _ trader: String, _ kind: String, _ side: String, _ quantity: Int) {
        self.id = id
        self.trader = trader
        self.kind = kind
        self.side = side
        self.quantity = quantity
        remaining = quantity
    }
    var active: Bool {
        resting || status == "PENDING"
    }
    var resting: Bool {
        status == "OPEN" || status == "PARTIAL"
    }
    func matches(_ p: Int) -> Bool {
        guard let price else {
            return true
        }
        return side == "BUY" ? p <= price : p >= price
    }
    func triggered(_ p: Int) -> Bool {
        side == "BUY" ? p >= trigger! : p <= trigger!
    }
    var line: String {
        "ORDER \(id) \(status) \(filled)/\(quantity)"
    }
    var details: String {
        var text = "\(id) \(trader) \(kind) \(side) \(price.map(String.init) ?? "-") \(status) \(filled)/\(quantity) avg \(filled == 0 ? "-" : decimal(value * 100 / filled))"
        if let trigger {
            text += " trigger \(trigger)"
        }
        return text
    }
    func fill(_ n: Int, _ p: Int, _ q: Int) {
        remaining -= q
        filled += q
        value += p * q
        history.append("FILL \(n) \(p) \(q)")
    }
}
final class Trader {
    let name: String
    var bought = 0, sold = 0, cash = 0, fees = 0
    var limit: Int?
    init(_ name: String) {
        self.name = name
    }
    var net: Int {
        bought - sold
    }
    var volume: Int {
        bought + sold
    }
    func pnl(_ p: Int) -> Int {
        cash + net * p
    }
    func position(_ p: Int) -> String {
        "POSITION \(name) bought \(bought) sold \(sold) net \(net) cash \(cash) fees \(fees) pnl \(pnl(p))"
    }
}
struct Trade {
    let number: Int, price: Int, quantity: Int, buy: Order, sell: Order, taker: String, buyFee: Int, sellFee: Int
    var line: String {
        "TRADE \(number) \(price) \(quantity) \(buy.id) \(buy.trader) \(sell.id) \(sell.trader)"
    }
}
struct Level {
    let price: Int
    var quantity: Int, count: Int
}
final class Engine {
    var orders: [String: Order] = [:], traders: [String: Trader] = [:]
    var book: [Order] = [], pending: [Order] = [], trades: [Trade] = [], output: [String] = []
    var maker = 0, taker = 0, band = 0, tick = 1, lot = 1, priority = 0, halted = false
    var mark: Int {
        trades.last?.price ?? 0
    }
    func register(_ name: String) -> Trader {
        if traders[name] == nil {
            traders[name] = Trader(name)
        }
        return traders[name]!
    }
    func trader(_ name: String) throws -> Trader {
        try require(traders[name] != nil, "unknown trader")
        return traders[name]!
    }
    func order(_ id: String) throws -> Order {
        try require(orders[id] != nil, "unknown order")
        return orders[id]!
    }
    func active(_ name: String) -> [Order] {
        orders.values.filter {
            $0.trader == name && $0.active
        }
        .sorted {
            $0.number < $1.number
        }
    }
    func exposure(_ name: String, _ side: String, _ exclude: Order? = nil) -> Int {
        (side == "BUY" ? traders[name]!.net : -traders[name]!.net) + active(name).filter {
            $0.side == side && $0 !== exclude
        }
        .reduce(0) {
            $0 + $1.remaining
        }
    }
    func risk(_ name: String, _ side: String, _ q: Int, _ exclude: Order? = nil) throws {
        if let limit = traders[name]?.limit {
            try require(exposure(name, side, exclude) + q <= limit, "risk limit")
        }
    }
    func checkBand(_ p: Int) throws {
        try require(band == 0 || trades.isEmpty || abs(p - mark) <= band, "outside band")
    }
    func sorted(_ side: String) -> [Order] {
        book.filter {
            $0.side == side
        }
        .sorted {
            a, b in a.price == b.price ? a.priority < b.priority : (side == "BUY" ? a.price! > b.price! : a.price! < b.price!)
        }
    }
    func best(_ side: String) -> Order? {
        sorted(side).first
    }
    func levels(_ side: String) -> [Level] {
        var result: [Level] = []
        for o in sorted(side) {
            if result.last?.price != o.price! {
                result.append(Level(price: o.price!, quantity: 0, count: 0))
            }
            result[result.count - 1].quantity += o.visible
            result[result.count - 1].count += 1
        }
        return result
    }
    func remove(_ o: Order) {
        book.removeAll {
            $0 === o
        }
    }
    func match(_ x: Order) {
        while x.remaining > 0 {
            guard let y = best(opposite(x.side)), x.matches(y.price!) else {
                break
            }
            if x.trader == y.trader {
                output.append("STP \(y.id) \(y.remaining)")
                y.history.append("STP \(y.remaining)")
                remove(y)
                y.remaining = 0
                y.status = "CANCELLED"
                continue
            }
            let q = min(x.remaining, y.visible), p = y.price!, buy = x.side == "BUY" ? x : y, sell = x.side == "SELL" ? x : y
            let bf = q * (buy === x ? taker : maker), sf = q * (sell === x ? taker : maker)
            let t = Trade(number: trades.count + 1, price: p, quantity: q, buy: buy, sell: sell, taker: x.id, buyFee: bf, sellFee: sf)
            trades.append(t)
            x.fill(t.number, p, q)
            y.fill(t.number, p, q)
            y.visible -= q
            let b = traders[buy.trader]!, s = traders[sell.trader]!
            b.bought += q
            b.cash -= p * q + bf
            b.fees += bf
            s.sold += q
            s.cash += p * q - sf
            s.fees += sf
            output.append(t.line)
            if y.remaining == 0 {
                remove(y)
                y.status = "FILLED"
            } else {
                y.status = "PARTIAL"
                if y.visible == 0 {
                    priority += 1
                    y.priority = priority
                    y.visible = min(y.peak!, y.remaining)
                    y.history.append("REFRESH \(y.visible) \(y.remaining - y.visible)")
                    output.append("REFRESH \(y.id) \(y.visible) \(y.remaining - y.visible)")
                }
            }
        }
    }
    func post(_ o: Order, _ forceRest: Bool = false) {
        if o.remaining == 0 {
            o.status = "FILLED"
        } else if forceRest || o.kind == "ICEBERG" || o.kind == "STOPLIMIT" || (o.kind == "LIMIT" && o.condition != "IOC") {
            priority += 1
            o.priority = priority
            o.visible = min(o.peak ?? o.remaining, o.remaining)
            o.status = o.filled == 0 ? "OPEN" : "PARTIAL"
            book.append(o)
            o.history.append("REST \(o.price!) \(o.visible)")
        } else {
            o.history.append("EXPIRE \(o.remaining)")
            o.remaining = 0
            o.status = "CANCELLED"
        }
        output.append(o.line)
    }
    func trigger() {
        while !trades.isEmpty {
            let selected = pending.filter {
                $0.triggered(mark)
            }
            .sorted {
                $0.number < $1.number
            }
            if selected.isEmpty {
                break
            }
            let ids = Set(selected.map {
                $0.id
            })
            pending.removeAll {
                ids.contains($0.id)
            }
            for o in selected {
                output.append("TRIGGER \(o.id)")
                o.history.append("TRIGGER")
                match(o)
                post(o)
            }
        }
    }
    func cancel(_ o: Order) {
        remove(o)
        pending.removeAll {
            $0 === o
        }
        o.history.append("CANCEL \(o.remaining)")
        o.remaining = 0
        o.status = "CANCELLED"
        output.append(o.line)
    }
    func bars(_ ts: [Trade]) -> String {
        "open \(ts.first!.price) high \(ts.map(\.price).max()!) low \(ts.map(\.price).min()!) close \(ts.last!.price) volume \(ts.reduce(0) { $0 + $1.quantity })"
    }
    func command(_ w: [String]) throws {
        let c = w[0]
        func num(_ i: Int) -> Int {
            Int(w[i])!
        }
        if ["LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG"].contains(c) {
            let o = Order(w[1], w[2], c, w[3], num(c == "MARKET" ? 4 : c == "STOPLIMIT" ? 6 : 5))
            if c == "LIMIT" || c == "ICEBERG" {
                o.price = num(4)
            }
            if c == "STOP" || c == "STOPLIMIT" {
                o.trigger = num(4)
            }
            if c == "STOPLIMIT" {
                o.price = num(5)
            }
            if c == "ICEBERG" {
                o.peak = num(6)
            }
            if c == "LIMIT" && w.count == 7 {
                o.condition = w[6]
            }
            let prices = [o.price, o.trigger].compactMap {
                $0
            }
            try require(!halted, "halted")
            try require(orders[o.id] == nil, "duplicate id")
            try require(prices.allSatisfy {
                $0 != 0
            }, "invalid price")
            try require(o.quantity != 0, "invalid quantity")
            try require(prices.allSatisfy {
                $0 % tick == 0
            }, "invalid tick")
            try require(o.quantity % lot == 0, "invalid lot")
            if let k = o.peak {
                try require(k > 0 && k <= o.quantity && k % lot == 0, "invalid peak")
            }
            if o.trigger != nil {
                try require(trades.isEmpty || !o.triggered(mark), "invalid trigger")
            }
            if let p = o.price {
                try checkBand(p)
            }
            try risk(o.trader, o.side, o.quantity)
            if o.condition == "POSTONLY", let b = best(opposite(o.side)) {
                try require(!o.matches(b.price!), "would cross")
            }
            if o.condition == "FOK" {
                try require(sorted(opposite(o.side)).filter {
                    $0.trader != o.trader && o.matches($0.price!)
                }
                .reduce(0) {
                    $0 + $1.remaining
                }
                >= o.quantity, "unfillable")
            }
            _ = register(o.trader)
            o.number = orders.count + 1
            orders[o.id] = o
            if o.trigger != nil {
                o.status = "PENDING"
                pending.append(o)
                output.append(o.line)
            } else {
                if o.condition != "POSTONLY" {
                    match(o)
                }
                post(o)
                trigger()
            }
            return
        }
        switch c {
            case "CANCEL": let o = try order(w[1])
            try require(o.active, "not open")
            cancel(o)
            case "REPLACE":
            try require(!halted, "halted")
            let o = try order(w[1])
            try require(o.resting, "not open")
            let p = num(2), q = num(3), moved = p != o.price!
            try require(p > 0, "invalid price")
            try require(q > 0, "invalid quantity")
            try require(!moved || p % tick == 0, "invalid tick")
            try require(q % lot == 0, "invalid lot")
            try require(moved || q != o.remaining, "no change")
            if moved {
                try checkBand(p)
            }
            if q > o.remaining {
                try risk(o.trader, o.side, q, o)
            }
            o.quantity = o.filled + q
            if !moved && q < o.remaining {
                o.remaining = q
                o.visible = min(o.visible, q)
                o.history.append("REPLACE \(p) \(q) kept")
                output.append("REPLACE \(o.id) kept")
                output.append(o.line)
            } else {
                remove(o)
                o.price = p
                o.remaining = q
                o.history.append("REPLACE \(p) \(q) lost")
                output.append("REPLACE \(o.id) lost")
                match(o)
                post(o, true)
                trigger()
            }
            case "CANCELALL": _ = try trader(w[1])
            let os = active(w[1])
            output.append("CANCELALL \(w[1]) \(os.count)")
            for o in os {
                cancel(o)
            }
            case "HALT": try require(!halted, "already halted")
            halted = true
            output.append(c)
            case "RESUME": try require(halted, "not halted")
            halted = false
            output.append(c)
            case "RISK": register(w[1]).limit = num(2)
            output.append("RISK \(w[1]) \(w[2]) exposure buy \(exposure(w[1], "BUY")) sell \(exposure(w[1], "SELL"))")
            case "FEE": try require(num(1) + num(2) >= 0, "invalid fee")
            maker = num(1)
            taker = num(2)
            output.append("FEE maker \(maker) taker \(taker)")
            case "BAND": band = num(1)
            output.append("BAND \(band)")
            case "TICK", "LOT": try require(num(1) > 0, "invalid size")
            if c == "TICK" {
                tick = num(1)
            } else {
                lot = num(1)
            }
            output.append("\(c) \(w[1])")
            case "BOOK":
            let n = num(1)
            try require(n > 0, "invalid depth")
            let bids = levels("BUY"), asks = levels("SELL")
            output.append("BOOK bids \(bids.count) asks \(asks.count)")
            for l in asks.prefix(n).reversed() {
                output.append("ASK \(l.price) \(l.quantity) \(l.count)")
            }
            for l in bids.prefix(n) {
                output.append("BID \(l.price) \(l.quantity) \(l.count)")
            }
            case "ORDERS": _ = try trader(w[1])
            let os = active(w[1])
            output.append("ORDERS \(w[1]) \(os.count)")
            output += os.map(\.details)
            case "STATUS": output.append("STATUS " + (try order(w[1])).details)
            case "HISTORY": let o = try order(w[1])
            output.append("HISTORY \(o.id) \(o.history.count)")
            output += o.history
            case "POSITION": output.append((try trader(w[1])).position(mark))
            case "FILLS":
            let name = w[1]
            _ = try trader(name)
            let ts = trades.filter {
                $0.buy.trader == name || $0.sell.trader == name
            }
            output.append("FILLS \(name) \(ts.count)")
            var net = 0
            for t in ts {
                let buy = t.buy.trader == name, id = buy ? t.buy.id : t.sell.id
                net += buy ? t.quantity : -t.quantity
                output.append("\(t.number) \(buy ? "BUY" : "SELL") \(t.price) \(t.quantity) \(id) \(t.taker == id ? "TAKER" : "MAKER") fee \(buy ? t.buyFee : t.sellFee) net \(net)")
            }
            case "LAST": output.append(trades.last.map {
                "LAST \($0.price) \($0.quantity)"
            }
            ?? "LAST none")
            case "VWAP":
            let v = trades.reduce(0) {
                $0 + $1.quantity
            }, a = trades.reduce(0) {
                $0 + $1.quantity * $1.price
            }
            output.append(trades.isEmpty ? "VWAP none" : "VWAP \(decimal(a * 100 / v)) volume \(v) trades \(trades.count)")
            case "SPREAD":
            let b = best("BUY"), a = best("SELL")
            var line = "SPREAD bid \(b?.price.map(String.init) ?? "none") ask \(a?.price.map(String.init) ?? "none")"
            if let bp = b?.price, let ap = a?.price {
                let sum = bp + ap
                line += " spread \(ap - bp) mid \(sum / 2).\(sum % 2 == 0 ? 0 : 5)"
            }
            output.append(line)
            case "IMPACT":
            let q = num(2)
            try require(q > 0, "invalid quantity")
            let ls = levels(opposite(w[1]))
            var rem = q, cost = 0, worst = 0, used = 0
            for l in ls {
                if rem == 0 {
                    break
                }
                let u = min(rem, l.quantity)
                rem -= u
                cost += u * l.price
                worst = l.price
                used += 1
            }
            output.append(rem > 0 ? "IMPACT \(w[1]) \(q) insufficient \(ls.reduce(0) { $0 + $1.quantity })" : "IMPACT \(w[1]) \(q) avg \(decimal(cost * 100 / q)) worst \(worst) levels \(used)")
            case "TRADES": let k = num(1)
            try require(k > 0, "invalid count")
            output.append("TRADES \(min(k, trades.count)) of \(trades.count)")
            output += trades.suffix(k).map(\.line)
            case "BARS": let k = num(1)
            try require(k > 0, "invalid count")
            output.append("BARS \((trades.count + k - 1) / k)")
            for i in stride(from: 0, to: trades.count, by: k) {
                output.append("\(i / k + 1) \(bars(Array(trades[i..<min(i + k, trades.count)])))")
            }
            case "RANK":
            let ts = traders.values.sorted {
                a, b in a.pnl(mark) != b.pnl(mark) ? a.pnl(mark) > b.pnl(mark) : a.volume != b.volume ? a.volume > b.volume : a.name < b.name
            }
            output.append("RANK \(ts.count)")
            for (i, t) in ts.enumerated() {
                output.append("\(i + 1) \(t.name) pnl \(t.pnl(mark)) volume \(t.volume)")
            }
            case "FLOW": let b = trades.filter {
                $0.taker == $0.buy.id
            }
            .reduce(0) {
                $0 + $1.quantity
            }, s = trades.filter {
                $0.taker == $0.sell.id
            }
            .reduce(0) {
                $0 + $1.quantity
            }
            output.append("FLOW buy \(b) sell \(s) net \(b - s)")
            case "SUMMARY":
            if trades.isEmpty {
                output.append("SUMMARY trades 0")
            } else {
                output.append("SUMMARY trades \(trades.count) volume \(trades.reduce(0) { $0 + $1.quantity }) open \(trades.first!.price) high \(trades.map(\.price).max()!) low \(trades.map(\.price).min()!) close \(mark) fees \(trades.reduce(0) { $0 + $1.buyFee + $1.sellFee })")
            }
            for name in traders.keys.sorted() {
                output.append(traders[name]!.position(mark))
            }
            default: break
        }
    }
    func execute(_ line: String) {
        let w = line.split(separator: " ").map(String.init)
        do {
            try command(w)
        } catch let e as CommandError {
            output.append((["LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG", "CANCEL", "REPLACE"].contains(w[0]) ? "REJECT \(w[1]) " : "ERROR ") + e.reason)
        } catch {
            fatalError("Unexpected error")
        }
    }
}
let n = Int(readLine()!)!, engine = Engine()
for _ in 0..<n {
    engine.execute(readLine()!)
}
print(engine.output.joined(separator: "\n"))
