import Foundation

let categories = ["received","returned","adjusted-in","adjusted-out","shipped","written-down","expired","recalled"]
enum Fault: Error { case reason(String) }
func error(_ condition: Bool, _ reason: String) throws {
    if condition { throw Fault.reason(reason) }
}
func parseMoney(_ s: String) -> Int {
    Int(s.replacingOccurrences(of:".",with:""))!
}
func money(_ n: Int) -> String {
    String(format:"%@%ld.%02ld",locale:Locale(identifier:"en_US_POSIX"),n < 0 ? "-" : "",abs(n)/100,abs(n)%100)
}
func signed(_ n: Int) -> String { (n > 0 ? "+" : "")+String(n) }
func signedMoney(_ n: Int) -> String { (n > 0 ? "+" : "")+money(n) }
func margin(_ profit: Int, _ revenue: Int) -> String {
    if revenue == 0 { return "n/a" }
    let q = abs(profit)*1000/revenue
    return (profit < 0 && q > 0 ? "-" : "")+"\(q/10).\(q%10)%"
}
struct Card {
    let day: Int
    let kind: String
    let warehouse: String
    let quantity: Int
    let value: Int
}
final class Item {
    let code: String
    var level: Int
    var name: String
    var lastCost: Int?
    var cards: [Card] = []
    init(_ code: String, _ level: Int, _ name: String) {
        self.code = code
        self.level = level
        self.name = name
    }
}
final class Warehouse {
    let code: String
    var stock: [String:[Int:Stock]] = [:]
    init(_ code: String) { self.code = code }
}
final class Lot {
    let number: Int
    let item: Item
    let day: Int
    let initialQuantity: Int
    let initialCost: Int
    let warehouse: String
    let kind: String
    var removed = 0
    init(_ number: Int, _ item: Item, _ day: Int, _ quantity: Int, _ cost: Int, _ warehouse: String, _ kind: String) {
        self.number = number
        self.item = item
        self.day = day
        initialQuantity = quantity
        initialCost = cost
        self.warehouse = warehouse
        self.kind = kind
    }
}
final class Stock {
    let lot: Lot
    var quantity: Int
    var cost: Int
    init(_ lot: Lot, _ quantity: Int, _ cost: Int) {
        self.lot = lot
        self.quantity = quantity
        self.cost = cost
    }
    var value: Int { quantity*cost }
}
struct Part {
    let lot: Lot
    let quantity: Int
    let cost: Int
}
struct Issue {
    let parts: [Part]
    let cost: Int
}
final class Order {
    let number: Int
    let warehouse: Warehouse
    let item: Item
    let day: Int
    let price: Int
    let ordered: Int
    var shipped = 0
    var backorder: Int
    var cancelled = 0
    var returned = 0
    var revenue = 0
    var cogs = 0
    var parts: [Part] = []
    init(_ number: Int, _ warehouse: Warehouse, _ item: Item, _ day: Int, _ quantity: Int, _ price: Int) {
        self.number = number
        self.warehouse = warehouse
        self.item = item
        self.day = day
        ordered = quantity
        backorder = quantity
        self.price = price
    }
}
final class Inventory {
    var day = 1
    var warehouses: [String:Warehouse] = [:]
    var items: [String:Item] = [:]
    var lots: [Lot] = []
    var orders: [Order] = []
    var totals = Array(repeating:[0,0],count:8)
    var output: [String] = []
    var sortedWarehouses: [Warehouse] { warehouses.keys.sorted().map { warehouses[$0]! } }
    var sortedItems: [Item] { items.keys.sorted().map { items[$0]! } }
    func warehouse(_ code: String) throws -> Warehouse {
        guard let w = warehouses[code] else { throw Fault.reason("unknown warehouse "+code) }
        return w
    }
    func item(_ code: String) throws -> Item {
        guard let s = items[code] else { throw Fault.reason("unknown item "+code) }
        return s
    }
    func order(_ raw: String) throws -> Order {
        let n = Int(raw)!
        try error(n < 1 || n > orders.count,"unknown order "+raw)
        return orders[n-1]
    }
    func lookupLot(_ raw: String) throws -> Lot {
        let n = Int(raw)!
        try error(n < 1 || n > lots.count,"unknown lot "+raw)
        return lots[n-1]
    }
    func stock(_ w: Warehouse, _ s: Item) -> [Stock] { w.stock[s.code].map { Array($0.values) } ?? [] }
    func fifo(_ w: Warehouse, _ s: Item) -> [Stock] {
        stock(w,s).sorted { $0.lot.day == $1.lot.day ? $0.lot.number < $1.lot.number : $0.lot.day < $1.lot.day }
    }
    func onhand(_ w: Warehouse, _ s: Item) -> Int { stock(w,s).reduce(0) { $0+$1.quantity } }
    func stockValue(_ w: Warehouse, _ s: Item) -> Int { stock(w,s).reduce(0) { $0+$1.value } }
    func onhand(_ s: Item) -> Int { warehouses.values.reduce(0) { $0+onhand($1,s) } }
    func backorder(_ s: Item) -> Int { orders.filter { $0.item === s }.reduce(0) { $0+$1.backorder } }
    func target(_ s: Item, _ selected: Warehouse?) -> [Stock] {
        sortedWarehouses.filter { selected == nil || $0 === selected! }.flatMap { stock($0,s) }
    }
    func card(_ s: Item, _ kind: String, _ w: Warehouse, _ q: Int, _ v: Int) {
        s.cards.append(Card(day:day,kind:kind,warehouse:w.code,quantity:q,value:v))
    }
    func total(_ category: Int, _ q: Int, _ value: Int) {
        totals[category][0] += q
        totals[category][1] += value
    }
    func add(_ w: Warehouse, _ s: Item, _ lot: Lot, _ q: Int, _ cost: Int) {
        if let old = w.stock[s.code]?[lot.number] { old.quantity += q }
        else { w.stock[s.code,default:[:]][lot.number] = Stock(lot,q,cost) }
    }
    func create(_ w: Warehouse, _ s: Item, _ q: Int, _ cost: Int, _ date: Int, _ kind: String) -> Lot {
        let lot = Lot(lots.count+1,s,date,q,cost,w.code,kind)
        lots.append(lot)
        add(w,s,lot,q,cost)
        return lot
    }
    func issue(_ w: Warehouse, _ s: Item, _ quantity: Int, _ removed: Bool) -> Issue {
        var parts: [Part] = []
        var left = quantity
        var cost = 0
        for a in fifo(w,s) {
            if left == 0 { break }
            let q = min(left,a.quantity)
            parts.append(Part(lot:a.lot,quantity:q,cost:a.cost))
            cost += q*a.cost
            a.quantity -= q
            left -= q
            if removed { a.lot.removed += q }
            if a.quantity == 0 { w.stock[s.code]?.removeValue(forKey:a.lot.number) }
        }
        return Issue(parts:parts,cost:cost)
    }
    func fill(_ o: Order, _ q: Int, _ kind: String) -> Issue {
        let issued = issue(o.warehouse,o.item,q,false)
        o.shipped += q
        o.backorder -= q
        o.revenue += q*o.price
        o.cogs += issued.cost
        o.parts.append(contentsOf:issued.parts)
        if q > 0 {
            total(4,q,issued.cost)
            card(o.item,kind,o.warehouse,-q,-issued.cost)
        }
        return issued
    }
    func allocate(_ w: Warehouse, _ s: Item) {
        var available = onhand(w,s)
        for o in orders {
            if available == 0 { break }
            if o.warehouse === w && o.item === s && o.backorder > 0 {
                let q = min(available,o.backorder)
                let issued = fill(o,q,"fill")
                available -= q
                output.append("  FILL order \(o.number) qty \(q) revenue \(money(q*o.price)) cogs \(money(issued.cost)) profit \(money(q*o.price-issued.cost)) backorder \(o.backorder)")
            }
        }
    }
    func insufficient(_ w: Warehouse, _ s: Item, _ q: Int) throws {
        let h = onhand(w,s)
        try error(h < q,"insufficient stock \(w.code) \(s.code) \(h)")
    }
    func sales(_ s: Item?) -> [Int] {
        let selected = orders.filter { s == nil || $0.item === s! }
        return [selected.reduce(0) { $0+$1.shipped-$1.returned },selected.reduce(0) { $0+$1.revenue },selected.reduce(0) { $0+$1.cogs },selected.count]
    }
    func salesLine(_ label: String, _ a: [Int]) -> String {
        "  \(label) sold \(a[0]) revenue \(money(a[1])) cogs \(money(a[2])) profit \(money(a[1]-a[2])) margin \(margin(a[1]-a[2],a[1]))"
    }
    func buckets(_ label: String, _ a: [Int], _ monetary: Bool) -> String {
        let labels = ["0-30","31-60","61-90","91+"]
        return "  "+label+(0..<4).map { " \(labels[$0]) "+(monetary ? money(a[$0]) : String(a[$0])) }.joined()
    }
    func stockCommand(_ t: [String]) throws {
        let w = try warehouse(t[1])
        let s = try item(t[2])
        let q = Int(t[0] == "ADJUST" ? String(t[3].dropFirst()) : t[3])!
        if t[0] != "COUNT" { try error(q == 0,"invalid quantity") }
        let h = onhand(w,s)
        switch t[0] {
        case "RECEIVE":
            let date = Int(t[5])!
            let cost = parseMoney(t[4])
            try error(date > day,"future day "+t[5])
            let lot = create(w,s,q,cost,date,"receive")
            s.lastCost = cost
            total(0,q,q*cost)
            card(s,"receive",w,q,q*cost)
            output.append("RECEIVE \(w.code) \(s.code) lot \(lot.number) qty \(q) cost \(money(cost)) day \(date) value \(money(q*cost))")
            allocate(w,s)
        case "SHIP":
            let o = Order(orders.count+1,w,s,day,q,parseMoney(t[4]))
            orders.append(o)
            let f = min(q,h)
            let issued = fill(o,f,"ship")
            output.append("SHIP order \(o.number) \(w.code) \(s.code) shipped \(f) revenue \(money(o.revenue)) cogs \(money(issued.cost)) profit \(money(o.revenue-issued.cost)) backorder \(o.backorder)")
        case "ADJUST":
            if t[3].first == "+" {
                let cost = parseMoney(t[4])
                let lot = create(w,s,q,cost,day,"adjust")
                total(2,q,q*cost)
                card(s,"adjust",w,q,q*cost)
                output.append("ADJUST \(w.code) \(s.code) +\(q) lot \(lot.number) value \(money(q*cost))")
                allocate(w,s)
            } else {
                try insufficient(w,s,q)
                let issued = issue(w,s,q,true)
                total(3,q,issued.cost)
                card(s,"adjust",w,-q,-issued.cost)
                output.append("ADJUST \(w.code) \(s.code) -\(q) value \(money(issued.cost))")
            }
        case "COUNT":
            if q == h { output.append("COUNT \(w.code) \(s.code) qty \(q) ok") }
            else if q < h {
                let issued = issue(w,s,h-q,true)
                total(3,h-q,issued.cost)
                card(s,"count",w,q-h,-issued.cost)
                output.append("COUNT \(w.code) \(s.code) qty \(h) -> \(q) shortage \(h-q) value \(money(issued.cost))")
            } else {
                let cost = s.lastCost ?? 0
                let lot = create(w,s,q-h,cost,day,"count")
                total(2,q-h,(q-h)*cost)
                card(s,"count",w,q-h,(q-h)*cost)
                output.append("COUNT \(w.code) \(s.code) qty \(h) -> \(q) surplus \(q-h) lot \(lot.number) value \(money((q-h)*cost))")
                allocate(w,s)
            }
        default: break
        }
    }
    func execute(_ t: [String]) throws {
        switch t[0] {
        case "DAY":
            let d = Int(t[1])!
            try error(d <= day,"invalid day "+t[1])
            day = d
            output.append("DAY \(day)")
        case "WAREHOUSE":
            try error(warehouses[t[1]] != nil,"duplicate warehouse "+t[1])
            warehouses[t[1]] = Warehouse(t[1])
            output.append("WAREHOUSE "+t[1])
        case "ITEM":
            let existing = items[t[1]]
            let s = existing ?? Item(t[1],Int(t[2])!,t[3])
            s.level = Int(t[2])!
            s.name = t[3]
            items[s.code] = s
            output.append("ITEM \(s.code)"+(existing == nil ? " added " : " updated ")+"\(s.name) level \(s.level)")
        case "RECEIVE", "SHIP", "ADJUST", "COUNT": try stockCommand(t)
        case "CANCEL":
            let o = try order(t[1])
            try error(o.backorder == 0,"no backorder "+t[1])
            o.cancelled += o.backorder
            o.backorder = 0
            output.append("CANCEL order \(o.number) qty \(o.cancelled)")
        case "TRANSFER":
            let a = try warehouse(t[1])
            let b = try warehouse(t[2])
            try error(a === b,"same warehouse "+t[1])
            let s = try item(t[3])
            let q = Int(t[4])!
            try error(q == 0,"invalid quantity")
            try insufficient(a,s,q)
            let issued = issue(a,s,q,false)
            for p in issued.parts { add(b,s,p.lot,p.quantity,p.cost) }
            card(s,"transfer-out",a,-q,-issued.cost)
            card(s,"transfer-in",b,q,issued.cost)
            output.append("TRANSFER \(a.code) -> \(b.code) \(s.code) qty \(q) value \(money(issued.cost)) lots \(issued.parts.count)")
            allocate(b,s)
        case "RETURN":
            let o = try order(t[1])
            let q = Int(t[2])!
            let cost = parseMoney(t[3])
            try error(q == 0,"invalid quantity")
            try error(q > o.shipped-o.returned,"return exceeds shipped \(t[1]) \(o.shipped-o.returned)")
            let lot = create(o.warehouse,o.item,q,cost,day,"return")
            o.returned += q
            o.revenue -= q*o.price
            o.cogs -= q*cost
            total(1,q,q*cost)
            card(o.item,"return",o.warehouse,q,q*cost)
            output.append("RETURN order \(o.number) \(o.warehouse.code) \(o.item.code) qty \(q) lot \(lot.number) refund \(money(q*o.price)) value \(money(q*cost))")
            allocate(o.warehouse,o.item)
        case "MARKET":
            let s = try item(t[1])
            let price = parseMoney(t[2])
            var quantity = 0
            var loss = 0
            var count = 0
            for w in sortedWarehouses {
                var subtotal = 0
                for a in stock(w,s) where a.cost > price {
                    subtotal += a.quantity*(a.cost-price)
                    quantity += a.quantity
                    count += 1
                    a.cost = price
                }
                if subtotal > 0 { card(s,"writedown",w,0,-subtotal) }
                loss += subtotal
            }
            total(5,quantity,loss)
            output.append("MARKET \(s.code) price \(money(price)) lots \(count) qty \(quantity) loss \(money(loss))")
        case "RECALL":
            let lot = try lookupLot(t[1])
            let held = sortedWarehouses.compactMap { w in stock(w,lot.item).first { $0.lot === lot }.map { (w,$0) } }
            try error(held.isEmpty,"nothing to recall "+t[1])
            let quantity = held.reduce(0) { $0+$1.1.quantity }
            let value = held.reduce(0) { $0+$1.1.value }
            for (w,a) in held {
                card(lot.item,"recall",w,-a.quantity,-a.value)
                w.stock[lot.item.code]?.removeValue(forKey:lot.number)
            }
            lot.removed += quantity
            total(7,quantity,value)
            output.append("RECALL lot \(lot.number) \(lot.item.code) qty \(quantity) value \(money(value))")
            for (w,a) in held { output.append("  \(w.code) qty \(a.quantity) value \(money(a.value))") }
        case "EXPIRE":
            let age = Int(t[1])!
            var quantity = 0
            var value = 0
            output.append("EXPIRE \(age)")
            for s in sortedItems {
                for w in sortedWarehouses {
                    let expired = stock(w,s).filter { day-$0.lot.day > age }
                    if expired.isEmpty { continue }
                    let q = expired.reduce(0) { $0+$1.quantity }
                    let v = expired.reduce(0) { $0+$1.value }
                    for a in expired {
                        a.lot.removed += a.quantity
                        w.stock[s.code]?.removeValue(forKey:a.lot.number)
                    }
                    total(6,q,v)
                    card(s,"expire",w,-q,-v)
                    output.append("  \(s.code) \(w.code) lots \(expired.count) qty \(q) value \(money(v))")
                    quantity += q
                    value += v
                }
            }
            output.append("  total qty \(quantity) value \(money(value))")
        case "VALUE", "AGING":
            let selected = try t.count == 2 ? warehouse(t[1]) : nil
            if t[0] == "VALUE" {
                output.append("VALUE"+(selected.map { " "+$0.code } ?? ""))
                var quantity = 0
                var value = 0
                for s in sortedItems {
                    let stock = target(s,selected)
                    let q = stock.reduce(0) { $0+$1.quantity }
                    let v = stock.reduce(0) { $0+$1.value }
                    if q == 0 { continue }
                    output.append("  \(s.code) qty \(q) value \(money(v)) avg \(money(v/q))")
                    if selected == nil {
                        for w in sortedWarehouses where onhand(w,s) > 0 { output.append("    \(w.code) qty \(onhand(w,s)) value \(money(stockValue(w,s)))") }
                    }
                    quantity += q
                    value += v
                }
                output.append("  total qty \(quantity) value \(money(value))")
            } else {
                output.append("AGING"+(selected.map { " "+$0.code } ?? "")+" day \(day)")
                var quantities = Array(repeating:0,count:4)
                var values = Array(repeating:0,count:4)
                for s in sortedItems {
                    var q = Array(repeating:0,count:4)
                    for a in target(s,selected) {
                        let age = day-a.lot.day
                        let b = age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3
                        q[b] += a.quantity
                        quantities[b] += a.quantity
                        values[b] += a.value
                    }
                    if q.reduce(0,+) > 0 { output.append(buckets(s.code,q,false)) }
                }
                output.append(buckets("total",quantities,false))
                output.append(buckets("value",values,true))
            }
        case "LOTS":
            let w = try warehouse(t[1])
            let s = try item(t[2])
            output.append("LOTS \(w.code) \(s.code)")
            for a in fifo(w,s) { output.append("  lot \(a.lot.number) day \(a.lot.day) qty \(a.quantity) cost \(money(a.cost)) value \(money(a.value)) age \(day-a.lot.day)") }
            for o in orders where o.warehouse === w && o.item === s && o.backorder > 0 { output.append("  backorder order \(o.number) qty \(o.backorder)") }
        case "REORDER", "ITEMS":
            output.append(t[0])
            for s in sortedItems {
                let h = onhand(s)
                let b = backorder(s)
                if t[0] == "ITEMS" { output.append("  \(s.code) \(s.name) level \(s.level) onhand \(h) backorder \(b) cost "+(s.lastCost.map(money) ?? "none")) }
                else if h-b <= s.level { output.append("  \(s.code) \(s.name) onhand \(h) backorder \(b) level \(s.level)") }
            }
        case "MARGIN", "TOP":
            let summaries = Dictionary(uniqueKeysWithValues:sortedItems.map { ($0.code,sales($0)) }).filter { $0.value[3] > 0 }
            if t[0] == "MARGIN" {
                output.append("MARGIN")
                for s in sortedItems where summaries[s.code] != nil { output.append(salesLine(s.code,summaries[s.code]!)) }
                output.append(salesLine("total",sales(nil)))
            } else {
                let k = Int(t[1])!
                output.append("TOP \(k)")
                let ranked = summaries.keys.sorted { a,b in
                    let x = summaries[a]!
                    let y = summaries[b]!
                    if x[1]-x[2] != y[1]-y[2] { return x[1]-x[2] > y[1]-y[2] }
                    return x[1] == y[1] ? a < b : x[1] > y[1]
                }.prefix(k)
                for (i,code) in ranked.enumerated() {
                    let a = summaries[code]!
                    output.append("  \(i+1) \(code) profit \(money(a[1]-a[2])) revenue \(money(a[1])) margin \(margin(a[1]-a[2],a[1]))")
                }
            }
        case "BACKORDERS":
            output.append("BACKORDERS")
            for o in orders where o.backorder > 0 { output.append("  order \(o.number) \(o.warehouse.code) \(o.item.code) qty \(o.backorder) day \(o.day) price \(money(o.price))") }
        case "ORDER":
            let o = try order(t[1])
            output.append("ORDER \(o.number) \(o.warehouse.code) \(o.item.code) day \(o.day) price \(money(o.price))")
            output.append("  ordered \(o.ordered) shipped \(o.shipped) backorder \(o.backorder) cancelled \(o.cancelled) returned \(o.returned)")
            for p in o.parts { output.append("  lot \(p.lot.number) qty \(p.quantity) cost \(money(p.cost))") }
            output.append("  revenue \(money(o.revenue)) cogs \(money(o.cogs)) profit \(money(o.revenue-o.cogs))")
        case "TRACE":
            let lot = try lookupLot(t[1])
            output.append("TRACE lot \(lot.number) \(lot.item.code) \(lot.kind) \(lot.warehouse) day \(lot.day) qty \(lot.initialQuantity) cost \(money(lot.initialCost))")
            for w in sortedWarehouses {
                for a in stock(w,lot.item) where a.lot === lot { output.append("  held \(w.code) qty \(a.quantity) cost \(money(a.cost))") }
            }
            for o in orders {
                let q = o.parts.filter { $0.lot === lot }.reduce(0) { $0+$1.quantity }
                if q > 0 { output.append("  order \(o.number) qty \(q)") }
            }
            if lot.removed > 0 { output.append("  removed qty \(lot.removed)") }
        case "CARD":
            let s = try item(t[1])
            output.append("CARD \(s.code) \(s.name)")
            var quantity = 0
            var value = 0
            for c in s.cards {
                quantity += c.quantity
                value += c.value
                output.append("  day \(c.day) \(c.kind) \(c.warehouse) \(signed(c.quantity)) \(signedMoney(c.value)) balance \(quantity) \(money(value))")
            }
        case "STATUS":
            output.append("STATUS")
            for w in sortedWarehouses {
                let q = items.values.reduce(0) { $0+onhand(w,$1) }
                let v = items.values.reduce(0) { $0+stockValue(w,$1) }
                let skus = items.values.filter { onhand(w,$0) > 0 }.count
                let b = orders.filter { $0.warehouse === w }.reduce(0) { $0+$1.backorder }
                output.append("  \(w.code) skus \(skus) qty \(q) value \(money(v)) backorder \(b)")
            }
        case "SUMMARY":
            output.append("SUMMARY")
            for i in 0..<8 { output.append("  \(categories[i]) qty \(totals[i][0]) value \(money(totals[i][1]))") }
            let q = items.values.reduce(0) { $0+onhand($1) }
            let v = items.values.reduce(0) { a,s in a+warehouses.values.reduce(0) { $0+stockValue($1,s) } }
            output.append("  on-hand qty \(q) value \(money(v))")
            output.append("  orders \(orders.count) open \(orders.filter { $0.backorder > 0 }.count) backorder \(orders.reduce(0) { $0+$1.backorder })")
        default: break
        }
        if output.count == 1 && ["LOTS","REORDER","ITEMS","TOP","BACKORDERS","CARD","STATUS"].contains(t[0]) { output.append("  (none)") }
    }
    func process(_ line: String) -> [String] {
        output = []
        do { try execute(line.split(separator:" ").map(String.init)) }
        catch Fault.reason(let reason) { output.append("ERROR "+reason) }
        catch { fatalError("Unexpected error") }
        return output
    }
}
let inventory = Inventory()
let commandCount = Int(readLine()!)!
for _ in 0..<commandCount {
    for line in inventory.process(readLine()!) { print(line) }
}
