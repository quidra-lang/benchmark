import kotlin.math.abs
import kotlin.math.min

private val categories = listOf("received","returned","adjusted-in","adjusted-out","shipped","written-down","expired","recalled")
private class Fault(reason: String) : RuntimeException(reason)
private fun error(condition: Boolean, reason: String) { if (condition) throw Fault(reason) }
private fun parseMoney(s: String): Long {
    return s.replace(".","").toLong()
}
private fun money(n: Long) = (if (n < 0) "-" else "")+"${abs(n)/100}.${(abs(n)%100).toString().padStart(2,'0')}"
private fun signed(n: Long) = (if (n > 0) "+" else "")+n
private fun signedMoney(n: Long) = (if (n > 0) "+" else "")+money(n)
private fun margin(profit: Long, revenue: Long): String {
    if (revenue == 0L) return "n/a"
    val q = abs(profit)*1000/revenue
    return (if (profit < 0 && q > 0) "-" else "")+"${q/10}.${q%10}%"
}
private data class Card(val day: Long, val kind: String, val warehouse: String, val quantity: Long, val value: Long)
private class Item(val code: String, var level: Long, var name: String) {
    var lastCost: Long? = null
    val cards = mutableListOf<Card>()
}
private class Warehouse(val code: String) {
    val stock = mutableMapOf<String,MutableMap<Int,Stock>>()
}
private class Lot(val number: Int, val item: Item, val day: Long, val initialQuantity: Long,
    val initialCost: Long, val warehouse: String, val kind: String) {
    var removed = 0L
}
private class Stock(val lot: Lot, var quantity: Long, var cost: Long) {
    fun value() = quantity*cost
}
private data class Part(val lot: Lot, val quantity: Long, val cost: Long)
private data class Issue(val parts: List<Part>, val cost: Long)
private class Order(val number: Int, val warehouse: Warehouse, val item: Item, val day: Long, val ordered: Long, val price: Long) {
    var shipped = 0L
    var backorder = ordered
    var cancelled = 0L
    var returned = 0L
    var revenue = 0L
    var cogs = 0L
    val parts = mutableListOf<Part>()
}
private class Inventory {
    var day = 1L
    val warehouses = sortedMapOf<String,Warehouse>()
    val items = sortedMapOf<String,Item>()
    val lots = mutableListOf<Lot>()
    val orders = mutableListOf<Order>()
    val totals = Array(8) { LongArray(2) }
    var output = mutableListOf<String>()
    fun warehouse(code: String) = warehouses[code] ?: throw Fault("unknown warehouse $code")
    fun item(code: String) = items[code] ?: throw Fault("unknown item $code")
    fun order(raw: String): Order {
        val n = raw.toLong()
        error(n < 1 || n > orders.size,"unknown order $raw")
        return orders[n.toInt()-1]
    }
    fun lot(raw: String): Lot {
        val n = raw.toLong()
        error(n < 1 || n > lots.size,"unknown lot $raw")
        return lots[n.toInt()-1]
    }
    fun stock(w: Warehouse, s: Item) = w.stock[s.code]?.values?.toList() ?: emptyList()
    fun fifo(w: Warehouse, s: Item) = stock(w,s).sortedWith(compareBy<Stock> { it.lot.day }.thenBy { it.lot.number })
    fun onhand(w: Warehouse, s: Item) = stock(w,s).sumOf { it.quantity }
    fun value(w: Warehouse, s: Item) = stock(w,s).sumOf { it.value() }
    fun onhand(s: Item) = warehouses.values.sumOf { onhand(it,s) }
    fun backorder(s: Item) = orders.filter { it.item === s }.sumOf { it.backorder }
    fun target(s: Item, selected: Warehouse?) = warehouses.values.filter { selected == null || it === selected }.flatMap { stock(it,s) }
    fun card(s: Item, kind: String, w: Warehouse, q: Long, v: Long) { s.cards.add(Card(day,kind,w.code,q,v)) }
    fun total(category: Int, q: Long, value: Long) {
        totals[category][0] += q
        totals[category][1] += value
    }
    fun add(w: Warehouse, s: Item, lot: Lot, q: Long, cost: Long) {
        val map = w.stock.getOrPut(s.code) { mutableMapOf() }
        val old = map[lot.number]
        if (old == null) map[lot.number] = Stock(lot,q,cost) else old.quantity += q
    }
    fun create(w: Warehouse, s: Item, q: Long, cost: Long, date: Long, kind: String): Lot {
        val lot = Lot(lots.size+1,s,date,q,cost,w.code,kind)
        lots.add(lot)
        add(w,s,lot,q,cost)
        return lot
    }
    fun issue(w: Warehouse, s: Item, quantity: Long, removed: Boolean): Issue {
        val parts = mutableListOf<Part>()
        var left = quantity
        var cost = 0L
        for (a in fifo(w,s)) {
            if (left == 0L) break
            val q = min(left,a.quantity)
            parts.add(Part(a.lot,q,a.cost))
            cost += q*a.cost
            a.quantity -= q
            left -= q
            if (removed) a.lot.removed += q
            if (a.quantity == 0L) w.stock.getValue(s.code).remove(a.lot.number)
        }
        return Issue(parts,cost)
    }
    fun fill(o: Order, q: Long, kind: String): Issue {
        val issued = issue(o.warehouse,o.item,q,false)
        o.shipped += q
        o.backorder -= q
        o.revenue += q*o.price
        o.cogs += issued.cost
        o.parts.addAll(issued.parts)
        if (q > 0) {
            total(4,q,issued.cost)
            card(o.item,kind,o.warehouse,-q,-issued.cost)
        }
        return issued
    }
    fun allocate(w: Warehouse, s: Item) {
        var available = onhand(w,s)
        for (o in orders) {
            if (available == 0L) break
            if (o.warehouse === w && o.item === s && o.backorder > 0) {
                val q = min(available,o.backorder)
                val issued = fill(o,q,"fill")
                available -= q
                output.add("  FILL order ${o.number} qty $q revenue ${money(q*o.price)} cogs ${money(issued.cost)} profit ${money(q*o.price-issued.cost)} backorder ${o.backorder}")
            }
        }
    }
    fun insufficient(w: Warehouse, s: Item, q: Long) {
        val h = onhand(w,s)
        error(h < q,"insufficient stock ${w.code} ${s.code} $h")
    }
    fun sales(s: Item?): LongArray {
        val selected = orders.filter { s == null || it.item === s }
        return longArrayOf(selected.sumOf { it.shipped-it.returned },selected.sumOf { it.revenue },
            selected.sumOf { it.cogs },selected.size.toLong())
    }
    fun salesLine(label: String, a: LongArray) = "  $label sold ${a[0]} revenue ${money(a[1])} cogs ${money(a[2])} profit ${money(a[1]-a[2])} margin ${margin(a[1]-a[2],a[1])}"
    fun buckets(label: String, a: LongArray, monetary: Boolean): String {
        val labels = listOf("0-30","31-60","61-90","91+")
        return "  $label"+(0..3).joinToString("") { " ${labels[it]} "+(if (monetary) money(a[it]) else a[it].toString()) }
    }
    fun stockCommand(t: List<String>) {
        val w = warehouse(t[1])
        val s = item(t[2])
        val q = (if (t[0] == "ADJUST") t[3].drop(1) else t[3]).toLong()
        if (t[0] != "COUNT") error(q == 0L,"invalid quantity")
        val h = onhand(w,s)
        when (t[0]) {
            "RECEIVE" -> {
                val date = t[5].toLong()
                val cost = parseMoney(t[4])
                error(date > day,"future day ${t[5]}")
                val lot = create(w,s,q,cost,date,"receive")
                s.lastCost = cost
                total(0,q,q*cost)
                card(s,"receive",w,q,q*cost)
                output.add("RECEIVE ${w.code} ${s.code} lot ${lot.number} qty $q cost ${money(cost)} day $date value ${money(q*cost)}")
                allocate(w,s)
            }
            "SHIP" -> {
                val o = Order(orders.size+1,w,s,day,q,parseMoney(t[4]))
                orders.add(o)
                val f = min(q,h)
                val issued = fill(o,f,"ship")
                output.add("SHIP order ${o.number} ${w.code} ${s.code} shipped $f revenue ${money(o.revenue)} cogs ${money(issued.cost)} profit ${money(o.revenue-issued.cost)} backorder ${o.backorder}")
            }
            "ADJUST" -> {
                if (t[3][0] == '+') {
                    val cost = parseMoney(t[4])
                    val lot = create(w,s,q,cost,day,"adjust")
                    total(2,q,q*cost)
                    card(s,"adjust",w,q,q*cost)
                    output.add("ADJUST ${w.code} ${s.code} +$q lot ${lot.number} value ${money(q*cost)}")
                    allocate(w,s)
                } else {
                    insufficient(w,s,q)
                    val issued = issue(w,s,q,true)
                    total(3,q,issued.cost)
                    card(s,"adjust",w,-q,-issued.cost)
                    output.add("ADJUST ${w.code} ${s.code} -$q value ${money(issued.cost)}")
                }
            }
            "COUNT" -> {
                if (q == h) output.add("COUNT ${w.code} ${s.code} qty $q ok")
                else if (q < h) {
                    val issued = issue(w,s,h-q,true)
                    total(3,h-q,issued.cost)
                    card(s,"count",w,q-h,-issued.cost)
                    output.add("COUNT ${w.code} ${s.code} qty $h -> $q shortage ${h-q} value ${money(issued.cost)}")
                } else {
                    val cost = s.lastCost ?: 0L
                    val lot = create(w,s,q-h,cost,day,"count")
                    total(2,q-h,(q-h)*cost)
                    card(s,"count",w,q-h,(q-h)*cost)
                    output.add("COUNT ${w.code} ${s.code} qty $h -> $q surplus ${q-h} lot ${lot.number} value ${money((q-h)*cost)}")
                    allocate(w,s)
                }
            }
        }
    }
    fun execute(t: List<String>) {
        when (t[0]) {
            "DAY" -> {
                val d = t[1].toLong()
                error(d <= day,"invalid day ${t[1]}")
                day = d
                output.add("DAY $day")
            }
            "WAREHOUSE" -> {
                error(t[1] in warehouses,"duplicate warehouse ${t[1]}")
                warehouses[t[1]] = Warehouse(t[1])
                output.add("WAREHOUSE ${t[1]}")
            }
            "ITEM" -> {
                val existing = items[t[1]]
                val s = existing ?: Item(t[1],t[2].toLong(),t[3])
                s.level = t[2].toLong()
                s.name = t[3]
                items[s.code] = s
                output.add("ITEM ${s.code}"+(if (existing == null) " added " else " updated ")+"${s.name} level ${s.level}")
            }
            "RECEIVE", "SHIP", "ADJUST", "COUNT" -> stockCommand(t)
            "CANCEL" -> {
                val o = order(t[1])
                error(o.backorder == 0L,"no backorder ${t[1]}")
                o.cancelled += o.backorder
                o.backorder = 0
                output.add("CANCEL order ${o.number} qty ${o.cancelled}")
            }
            "TRANSFER" -> {
                val a = warehouse(t[1])
                val b = warehouse(t[2])
                error(a === b,"same warehouse ${t[1]}")
                val s = item(t[3])
                val q = t[4].toLong()
                error(q == 0L,"invalid quantity")
                insufficient(a,s,q)
                val issued = issue(a,s,q,false)
                for (p in issued.parts) add(b,s,p.lot,p.quantity,p.cost)
                card(s,"transfer-out",a,-q,-issued.cost)
                card(s,"transfer-in",b,q,issued.cost)
                output.add("TRANSFER ${a.code} -> ${b.code} ${s.code} qty $q value ${money(issued.cost)} lots ${issued.parts.size}")
                allocate(b,s)
            }
            "RETURN" -> {
                val o = order(t[1])
                val q = t[2].toLong()
                val cost = parseMoney(t[3])
                error(q == 0L,"invalid quantity")
                error(q > o.shipped-o.returned,"return exceeds shipped ${t[1]} ${o.shipped-o.returned}")
                val lot = create(o.warehouse,o.item,q,cost,day,"return")
                o.returned += q
                o.revenue -= q*o.price
                o.cogs -= q*cost
                total(1,q,q*cost)
                card(o.item,"return",o.warehouse,q,q*cost)
                output.add("RETURN order ${o.number} ${o.warehouse.code} ${o.item.code} qty $q lot ${lot.number} refund ${money(q*o.price)} value ${money(q*cost)}")
                allocate(o.warehouse,o.item)
            }
            "MARKET" -> {
                val s = item(t[1])
                val price = parseMoney(t[2])
                var quantity = 0L
                var loss = 0L
                var count = 0
                for (w in warehouses.values) {
                    var subtotal = 0L
                    for (a in stock(w,s)) {
                        if (a.cost > price) {
                            subtotal += a.quantity*(a.cost-price)
                            quantity += a.quantity
                            count++
                            a.cost = price
                        }
                    }
                    if (subtotal > 0) card(s,"writedown",w,0,-subtotal)
                    loss += subtotal
                }
                total(5,quantity,loss)
                output.add("MARKET ${s.code} price ${money(price)} lots $count qty $quantity loss ${money(loss)}")
            }
            "RECALL" -> {
                val lot = lot(t[1])
                val held = warehouses.values.mapNotNull { w -> stock(w,lot.item).firstOrNull { it.lot === lot }?.let { w to it } }
                error(held.isEmpty(),"nothing to recall ${t[1]}")
                val quantity = held.sumOf { it.second.quantity }
                val value = held.sumOf { it.second.value() }
                for ((w,a) in held) {
                    card(lot.item,"recall",w,-a.quantity,-a.value())
                    w.stock.getValue(lot.item.code).remove(lot.number)
                }
                lot.removed += quantity
                total(7,quantity,value)
                output.add("RECALL lot ${lot.number} ${lot.item.code} qty $quantity value ${money(value)}")
                for ((w,a) in held) output.add("  ${w.code} qty ${a.quantity} value ${money(a.value())}")
            }
            "EXPIRE" -> {
                val age = t[1].toLong()
                var quantity = 0L
                var value = 0L
                output.add("EXPIRE $age")
                for (s in items.values) {
                    for (w in warehouses.values) {
                        val expired = stock(w,s).filter { day-it.lot.day > age }
                        if (expired.isEmpty()) continue
                        val q = expired.sumOf { it.quantity }
                        val v = expired.sumOf { it.value() }
                        for (a in expired) {
                            a.lot.removed += a.quantity
                            w.stock.getValue(s.code).remove(a.lot.number)
                        }
                        total(6,q,v)
                        card(s,"expire",w,-q,-v)
                        output.add("  ${s.code} ${w.code} lots ${expired.size} qty $q value ${money(v)}")
                        quantity += q
                        value += v
                    }
                }
                output.add("  total qty $quantity value ${money(value)}")
            }
            "VALUE", "AGING" -> {
                val selected = if (t.size == 2) warehouse(t[1]) else null
                if (t[0] == "VALUE") {
                    output.add("VALUE"+(if (selected == null) "" else " ${selected.code}"))
                    var quantity = 0L
                    var value = 0L
                    for (s in items.values) {
                        val target = target(s,selected)
                        val q = target.sumOf { it.quantity }
                        val v = target.sumOf { it.value() }
                        if (q == 0L) continue
                        output.add("  ${s.code} qty $q value ${money(v)} avg ${money(v/q)}")
                        if (selected == null) {
                            for (w in warehouses.values) if (onhand(w,s) > 0) output.add("    ${w.code} qty ${onhand(w,s)} value ${money(value(w,s))}")
                        }
                        quantity += q
                        value += v
                    }
                    output.add("  total qty $quantity value ${money(value)}")
                } else {
                    output.add("AGING"+(if (selected == null) "" else " ${selected.code}")+" day $day")
                    val quantities = LongArray(4)
                    val values = LongArray(4)
                    for (s in items.values) {
                        val q = LongArray(4)
                        for (a in target(s,selected)) {
                            val age = day-a.lot.day
                            val b = if (age <= 30) 0 else if (age <= 60) 1 else if (age <= 90) 2 else 3
                            q[b] += a.quantity
                            quantities[b] += a.quantity
                            values[b] += a.value()
                        }
                        if (q.sum() > 0) output.add(buckets(s.code,q,false))
                    }
                    output.add(buckets("total",quantities,false))
                    output.add(buckets("value",values,true))
                }
            }
            "LOTS" -> {
                val w = warehouse(t[1])
                val s = item(t[2])
                output.add("LOTS ${w.code} ${s.code}")
                for (a in fifo(w,s)) output.add("  lot ${a.lot.number} day ${a.lot.day} qty ${a.quantity} cost ${money(a.cost)} value ${money(a.value())} age ${day-a.lot.day}")
                for (o in orders) if (o.warehouse === w && o.item === s && o.backorder > 0) output.add("  backorder order ${o.number} qty ${o.backorder}")
            }
            "REORDER", "ITEMS" -> {
                output.add(t[0])
                for (s in items.values) {
                    val h = onhand(s)
                    val b = backorder(s)
                    if (t[0] == "ITEMS") output.add("  ${s.code} ${s.name} level ${s.level} onhand $h backorder $b cost "+(s.lastCost?.let { money(it) } ?: "none"))
                    else if (h-b <= s.level) output.add("  ${s.code} ${s.name} onhand $h backorder $b level ${s.level}")
                }
            }
            "MARGIN", "TOP" -> {
                val summaries = items.values.associateWith { sales(it) }.filterValues { it[3] > 0 }
                if (t[0] == "MARGIN") {
                    output.add("MARGIN")
                    for (s in items.values) if (s in summaries) output.add(salesLine(s.code,summaries.getValue(s)))
                    output.add(salesLine("total",sales(null)))
                } else {
                    val k = t[1].toInt()
                    output.add("TOP $k")
                    val ranked = summaries.keys.sortedWith(compareByDescending<Item> { summaries.getValue(it)[1]-summaries.getValue(it)[2] }
                        .thenByDescending { summaries.getValue(it)[1] }.thenBy { it.code }).take(k)
                    for ((i,s) in ranked.withIndex()) {
                        val a = summaries.getValue(s)
                        output.add("  ${i+1} ${s.code} profit ${money(a[1]-a[2])} revenue ${money(a[1])} margin ${margin(a[1]-a[2],a[1])}")
                    }
                }
            }
            "BACKORDERS" -> {
                output.add("BACKORDERS")
                for (o in orders) if (o.backorder > 0) output.add("  order ${o.number} ${o.warehouse.code} ${o.item.code} qty ${o.backorder} day ${o.day} price ${money(o.price)}")
            }
            "ORDER" -> {
                val o = order(t[1])
                output.add("ORDER ${o.number} ${o.warehouse.code} ${o.item.code} day ${o.day} price ${money(o.price)}")
                output.add("  ordered ${o.ordered} shipped ${o.shipped} backorder ${o.backorder} cancelled ${o.cancelled} returned ${o.returned}")
                for (p in o.parts) output.add("  lot ${p.lot.number} qty ${p.quantity} cost ${money(p.cost)}")
                output.add("  revenue ${money(o.revenue)} cogs ${money(o.cogs)} profit ${money(o.revenue-o.cogs)}")
            }
            "TRACE" -> {
                val lot = lot(t[1])
                output.add("TRACE lot ${lot.number} ${lot.item.code} ${lot.kind} ${lot.warehouse} day ${lot.day} qty ${lot.initialQuantity} cost ${money(lot.initialCost)}")
                for (w in warehouses.values) for (a in stock(w,lot.item)) if (a.lot === lot) output.add("  held ${w.code} qty ${a.quantity} cost ${money(a.cost)}")
                for (o in orders) {
                    val q = o.parts.filter { it.lot === lot }.sumOf { it.quantity }
                    if (q > 0) output.add("  order ${o.number} qty $q")
                }
                if (lot.removed > 0) output.add("  removed qty ${lot.removed}")
            }
            "CARD" -> {
                val s = item(t[1])
                output.add("CARD ${s.code} ${s.name}")
                var quantity = 0L
                var value = 0L
                for (c in s.cards) {
                    quantity += c.quantity
                    value += c.value
                    output.add("  day ${c.day} ${c.kind} ${c.warehouse} ${signed(c.quantity)} ${signedMoney(c.value)} balance $quantity ${money(value)}")
                }
            }
            "STATUS" -> {
                output.add("STATUS")
                for (w in warehouses.values) {
                    val q = items.values.sumOf { onhand(w,it) }
                    val v = items.values.sumOf { value(w,it) }
                    val skus = items.values.count { onhand(w,it) > 0 }
                    val b = orders.filter { it.warehouse === w }.sumOf { it.backorder }
                    output.add("  ${w.code} skus $skus qty $q value ${money(v)} backorder $b")
                }
            }
            "SUMMARY" -> {
                output.add("SUMMARY")
                for (i in 0..7) output.add("  ${categories[i]} qty ${totals[i][0]} value ${money(totals[i][1])}")
                val q = items.values.sumOf { onhand(it) }
                val v = items.values.sumOf { s -> warehouses.values.sumOf { value(it,s) } }
                output.add("  on-hand qty $q value ${money(v)}")
                output.add("  orders ${orders.size} open ${orders.count { it.backorder > 0 }} backorder ${orders.sumOf { it.backorder }}")
            }
        }
        if (output.size == 1 && t[0] in listOf("LOTS","REORDER","ITEMS","TOP","BACKORDERS","CARD","STATUS")) output.add("  (none)")
    }
    fun process(line: String): List<String> {
        output = mutableListOf()
        try { execute(line.split(' ')) }
        catch (f: Fault) { output.add("ERROR ${f.message}") }
        return output
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val inventory = Inventory()
    repeat(input.readLine().toInt()) {
        for (line in inventory.process(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
