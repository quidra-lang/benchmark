import kotlin.math.abs
import kotlin.math.min
private class Rejection(message: String) : RuntimeException(message)
private fun reject(bad: Boolean, reason: String) {
    if (bad) throw Rejection(reason)
}
private fun decimal(n: Long) = "${n / 100}.${(n % 100).toString().padStart(2, '0')}"
private class Order(val id: String, val trader: String, val type: String, val side: String, var quantity: Long) {
    var condition = ""
    var status = "OPEN"
    var price = 0L
    var trigger = 0L
    var peak = 0L
    var left = quantity
    var visible = 0L
    var filled = 0L
    var value = 0L
    var priority = 0L
    val history = mutableListOf("ACCEPT")
    fun resting() = status == "OPEN" || status == "PARTIAL"
    fun active() = resting() || status == "PENDING"
    fun matches(p: Long) = price == 0L || if (side == "BUY") p <= price else p >= price
    fun triggered(p: Long) = if (side == "BUY") p >= trigger else p <= trigger
    fun line() = "ORDER $id $status $filled/$quantity"
    fun details(): String = "$id $trader $type $side ${if (price == 0L) "-" else price} $status $filled/$quantity avg ${if (filled == 0L) "-" else decimal(value * 100 / filled)}" + if (trigger == 0L) "" else " trigger $trigger"
    fun fill(number: Int, p: Long, q: Long) {
        left -= q
        filled += q
        value += p * q
        history.add("FILL $number $p $q")
    }
}
private class Trader(val name: String) {
    var bought = 0L
    var sold = 0L
    var cash = 0L
    var fees = 0L
    var limit: Long? = null
    fun net() = bought - sold
    fun volume() = bought + sold
    fun pnl(mark: Long) = cash + net() * mark
    fun position(mark: Long) = "POSITION $name bought $bought sold $sold net ${net()} cash $cash fees $fees pnl ${pnl(mark)}"
}
private data class Trade(val number: Int, val price: Long, val quantity: Long, val buy: Order, val sell: Order, val taker: Order, val buyFee: Long, val sellFee: Long) {
    fun line() = "TRADE $number $price $quantity ${buy.id} ${buy.trader} ${sell.id} ${sell.trader}"
}
private class Level(val price: Long, var quantity: Long = 0, var count: Int = 0)
private class Engine {
    val orders = linkedMapOf<String, Order>()
    val traders = sortedMapOf<String, Trader>()
    val pending = mutableListOf<Order>()
    val buys = mutableListOf<Order>()
    val sells = mutableListOf<Order>()
    val trades = mutableListOf<Trade>()
    val output = StringBuilder()
    var makerFee = 0L
    var takerFee = 0L
    var band = 0L
    var tick = 1L
    var lot = 1L
    var priority = 0L
    var halted = false
    fun emit(vararg parts: Any) {
        output.append(parts.joinToString(" ")).append('\n')
    }
    fun book(side: String) = if (side == "BUY") buys else sells
    fun opposite(side: String) = if (side == "BUY") sells else buys
    fun comparator(side: String): Comparator<Order> = compareBy<Order> {
        if (side == "BUY") -it.price else it.price
    }.thenBy {
        it.priority
    }
    fun best(book: List<Order>) = book.minWithOrNull(comparator(if (book === buys) "BUY" else "SELL"))
    fun last() = trades.lastOrNull()?.price ?: 0L
    fun register(name: String) = traders.getOrPut(name) {
        Trader(name)
    }
    fun trader(name: String): Trader {
        reject(name !in traders, "unknown trader")
        return traders.getValue(name)
    }
    fun order(id: String): Order {
        reject(id !in orders, "unknown order")
        return orders.getValue(id)
    }
    fun active(name: String) = orders.values.filter {
        it.trader == name && it.active()
    }
    fun exposure(name: String, side: String, excluded: Order? = null): Long = (if (side == "BUY") traders.getValue(name).net() else -traders.getValue(name).net()) + active(name).filter {
        it !== excluded && it.side == side
    }.sumOf {
        it.left
    }
    fun risk(name: String, side: String, q: Long, excluded: Order? = null) {
        val limit = traders[name]?.limit ?: return
        reject(exposure(name, side, excluded) + q > limit, "risk limit")
    }
    fun band(p: Long) {
        reject(band > 0 && last() != 0L && abs(p - last()) > band, "outside band")
    }
    fun match(x: Order) {
        val b = opposite(x.side)
        while (x.left > 0) {
            val y = best(b) ?: break
            if (!x.matches(y.price)) break
            if (x.trader == y.trader) {
                emit("STP", y.id, y.left)
                y.history.add("STP ${y.left}")
                b.remove(y)
                y.left = 0
                y.status = "CANCELLED"
                continue
            }
            val q = min(x.left, y.visible)
            val p = y.price
            val buy = if (x.side == "BUY") x else y
            val sell = if (buy === x) y else x
            val xf = q * takerFee
            val yf = q * makerFee
            val t = Trade(trades.size + 1, p, q, buy, sell, x, if (buy === x) xf else yf, if (sell === x) xf else yf)
            trades.add(t)
            x.fill(t.number, p, q)
            y.fill(t.number, p, q)
            y.visible -= q
            val bt = traders.getValue(buy.trader)
            val st = traders.getValue(sell.trader)
            bt.bought += q
            bt.cash -= p * q + t.buyFee
            bt.fees += t.buyFee
            st.sold += q
            st.cash += p * q - t.sellFee
            st.fees += t.sellFee
            emit(t.line())
            if (y.left == 0L) {
                b.remove(y)
                y.status = "FILLED"
            }
            else {
                y.status = "PARTIAL"
                if (y.visible == 0L) {
                    y.priority = ++priority
                    y.visible = min(y.peak, y.left)
                    y.history.add("REFRESH ${y.visible} ${y.left - y.visible}")
                    emit("REFRESH", y.id, y.visible, y.left - y.visible)
                }
            }
        }
    }
    fun post(o: Order, forceRest: Boolean = false) {
        if (o.left == 0L) o.status = "FILLED"
        else if (forceRest || o.type in listOf("ICEBERG", "STOPLIMIT") || o.type == "LIMIT" && o.condition != "IOC") {
            o.priority = ++priority
            o.visible = if (o.peak == 0L) o.left else min(o.peak, o.left)
            book(o.side).add(o)
            o.status = if (o.filled > 0) "PARTIAL" else "OPEN"
            o.history.add("REST ${o.price} ${o.visible}")
        } else {
            o.history.add("EXPIRE ${o.left}")
            o.left = 0
            o.status = "CANCELLED"
        }
        emit(o.line())
    }
    fun trigger() {
        while (trades.isNotEmpty()) {
            val p = last()
            val batch = pending.filter {
                it.triggered(p)
            }
            if (batch.isEmpty()) return
            pending.removeAll(batch.toSet())
            for (o in batch) {
                emit("TRIGGER", o.id)
                o.history.add("TRIGGER")
                match(o)
                post(o)
            }
        }
    }
    fun cancel(o: Order) {
        if (o.status == "PENDING") pending.remove(o) else book(o.side).remove(o)
        o.history.add("CANCEL ${o.left}")
        o.left = 0
        o.status = "CANCELLED"
        emit(o.line())
    }
    fun newOrder(a: List<String>) {
        val kind = a[0]
        val market = kind == "MARKET"
        val stop = kind == "STOP"
        val sl = kind == "STOPLIMIT"
        val ice = kind == "ICEBERG"
        val p = if (market || stop) 0L else a[if (sl) 5 else 4].toLong()
        val tr = if (stop || sl) a[4].toLong() else 0L
        val q = a[if (market) 4 else if (sl) 6 else 5].toLong()
        val o = Order(a[1], a[2], kind, a[3], q)
        o.price = p
        o.trigger = tr
        if (ice) o.peak = a[6].toLong()
        if (kind == "LIMIT" && a.size == 7) o.condition = a[6]
        reject(halted, "halted")
        reject(o.id in orders, "duplicate id")
        reject(!market && !stop && p == 0L || (stop || sl) && tr == 0L, "invalid price")
        reject(q == 0L, "invalid quantity")
        reject(p % tick != 0L || tr % tick != 0L, "invalid tick")
        reject(q % lot != 0L, "invalid lot")
        if (ice) reject(o.peak == 0L || o.peak > q || o.peak % lot != 0L, "invalid peak")
        if (stop || sl) reject(last() != 0L && o.triggered(last()), "invalid trigger")
        if (p != 0L) band(p)
        risk(o.trader, o.side, q)
        val b = best(opposite(o.side))
        if (o.condition == "POSTONLY") reject(b != null && o.matches(b.price), "would cross")
        if (o.condition == "FOK") reject(opposite(o.side).filter {
            it.trader != o.trader && o.matches(it.price)
        }.sumOf {
            it.left
        }
        < q, "unfillable")
        register(o.trader)
        orders[o.id] = o
        if (stop || sl) {
            o.status = "PENDING"
            pending.add(o)
            emit(o.line())
        }
        else {
            if (o.condition != "POSTONLY") match(o)
            post(o)
            trigger()
        }
    }
    fun levels(side: String): List<Level> {
        val result = mutableListOf<Level>()
        for (o in book(side).sortedWith(comparator(side))) {
            if (result.lastOrNull()?.price != o.price) result.add(Level(o.price))
            result.last().quantity += o.visible
            result.last().count++
        }
        return result
    }
    fun positive(text: String, reason: String): Long {
        val n = text.toLong()
        reject(n == 0L, reason)
        return n
    }
    fun bar(ts: List<Trade>) = "open ${ts.first().price} high ${ts.maxOf { it.price }} low ${ts.minOf { it.price }} close ${ts.last().price} volume ${ts.sumOf { it.quantity }}"
    fun execute(line: String) {
        val a = line.split(' ')
        val c = a[0]
        try {
            when (c) {
                "LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG" -> newOrder(a)
                "CANCEL" -> {
                    val o = order(a[1])
                    reject(!o.active(), "not open")
                    cancel(o)
                }
                "REPLACE" -> {
                    reject(halted, "halted")
                    val o = order(a[1])
                    reject(!o.resting(), "not open")
                    val p = a[2].toLong()
                    val q = a[3].toLong()
                    val moved = p != o.price
                    reject(p == 0L, "invalid price")
                    reject(q == 0L, "invalid quantity")
                    reject(moved && p % tick != 0L, "invalid tick")
                    reject(q % lot != 0L, "invalid lot")
                    reject(!moved && q == o.left, "no change")
                    if (moved) band(p)
                    if (q > o.left) risk(o.trader, o.side, q, o)
                    o.quantity = o.filled + q
                    val kept = !moved && q < o.left
                    o.history.add("REPLACE $p $q ${if (kept) "kept" else "lost"}")
                    emit("REPLACE", o.id, if (kept) "kept" else "lost")
                    if (kept) {
                        o.left = q
                        o.visible = min(o.visible, q)
                        emit(o.line())
                    }
                    else {
                        book(o.side).remove(o)
                        o.price = p
                        o.left = q
                        match(o)
                        post(o, true)
                        trigger()
                    }
                }
                "CANCELALL" -> {
                    trader(a[1])
                    val xs = active(a[1])
                    emit(c, a[1], xs.size)
                    xs.forEach {
                        cancel(it)
                    }
                }
                "HALT" -> {
                    reject(halted, "already halted")
                    halted = true
                    emit(c)
                }
                "RESUME" -> {
                    reject(!halted, "not halted")
                    halted = false
                    emit(c)
                }
                "RISK" -> {
                    register(a[1]).limit = a[2].toLong()
                    emit(c, a[1], a[2], "exposure buy", exposure(a[1], "BUY"), "sell", exposure(a[1], "SELL"))
                }
                "FEE" -> {
                    val m = a[1].toLong()
                    val t = a[2].toLong()
                    reject(m + t < 0, "invalid fee")
                    makerFee = m
                    takerFee = t
                    emit("FEE maker", m, "taker", t)
                }
                "BAND" -> {
                    band = a[1].toLong()
                    emit(c, band)
                }
                "TICK", "LOT" -> {
                    val v = positive(a[1], "invalid size")
                    if (c == "TICK") tick = v else lot = v
                    emit(c, v)
                }
                "BOOK" -> {
                    val n = positive(a[1], "invalid depth").toInt()
                    val bids = levels("BUY")
                    val asks = levels("SELL")
                    emit("BOOK bids", bids.size, "asks", asks.size)
                    for (l in asks.take(n).reversed()) emit("ASK", l.price, l.quantity, l.count)
                    for (l in bids.take(n)) emit("BID", l.price, l.quantity, l.count)
                }
                "ORDERS" -> {
                    trader(a[1])
                    val xs = active(a[1])
                    emit(c, a[1], xs.size)
                    xs.forEach {
                        emit(it.details())
                    }
                }
                "STATUS" -> emit(c, order(a[1]).details())
                "HISTORY" -> {
                    val o = order(a[1])
                    emit(c, o.id, o.history.size)
                    o.history.forEach {
                        emit(it)
                    }
                }
                "POSITION" -> emit(trader(a[1]).position(last()))
                "FILLS" -> {
                    trader(a[1])
                    val ts = trades.filter {
                        it.buy.trader == a[1] || it.sell.trader == a[1]
                    }
                    emit(c, a[1], ts.size)
                    var net = 0L
                    for (t in ts) {
                        val buy = t.buy.trader == a[1]
                        val o = if (buy) t.buy else t.sell
                        net += if (buy) t.quantity else -t.quantity
                        emit(t.number, o.side, t.price, t.quantity, o.id, if (t.taker === o) "TAKER" else "MAKER", "fee", if (buy) t.buyFee else t.sellFee, "net", net)
                    }
                }
                "LAST" -> if (trades.isEmpty()) emit(c, "none") else emit(c, last(), trades.last().quantity)
                "VWAP" -> if (trades.isEmpty()) emit(c, "none") else {
                    val v = trades.sumOf {
                        it.quantity
                    }
                    emit(c, decimal(trades.sumOf {
                        it.price * it.quantity
                    } * 100 / v), "volume", v, "trades", trades.size)
                }
                "SPREAD" -> {
                    val b = best(buys)
                    val s = best(sells)
                    if (b == null || s == null) emit("SPREAD bid", b?.price ?: "none", "ask", s?.price ?: "none") else {
                        val sum = b.price + s.price
                        emit("SPREAD bid", b.price, "ask", s.price, "spread", s.price - b.price, "mid", "${sum / 2}.${if (sum % 2 == 0L) 0 else 5}")
                    }
                }
                "IMPACT" -> {
                    val q = positive(a[2], "invalid quantity")
                    var left = q
                    var cost = 0L
                    var worst = 0L
                    var used = 0
                    val ls = levels(if (a[1] == "BUY") "SELL" else "BUY")
                    for (l in ls) if (left > 0) {
                        val u = min(left, l.quantity)
                        left -= u
                        cost += u * l.price
                        worst = l.price
                        used++
                    }
                    if (left > 0) emit(c, a[1], q, "insufficient", ls.sumOf {
                        it.quantity
                    }) else emit(c, a[1], q, "avg", decimal(cost * 100 / q), "worst", worst, "levels", used)
                }
                "TRADES" -> {
                    val n = positive(a[1], "invalid count").toInt()
                    val ts = trades.takeLast(min(n, trades.size))
                    emit(c, ts.size, "of", trades.size)
                    ts.forEach {
                        emit(it.line())
                    }
                }
                "BARS" -> {
                    val k = positive(a[1], "invalid count").toInt()
                    val groups = trades.chunked(k)
                    emit(c, groups.size)
                    groups.forEachIndexed {
                        i, ts -> emit(i + 1, bar(ts))
                    }
                }
                "RANK" -> {
                    val ts = traders.values.sortedWith(compareByDescending<Trader> {
                        it.pnl(last())
                    }.thenByDescending {
                        it.volume()
                    }.thenBy {
                        it.name
                    })
                    emit(c, ts.size)
                    ts.forEachIndexed {
                        i, t -> emit(i + 1, t.name, "pnl", t.pnl(last()), "volume", t.volume())
                    }
                }
                "FLOW" -> {
                    val buy = trades.filter {
                        it.taker === it.buy
                    }.sumOf {
                        it.quantity
                    }
                    val sell = trades.filter {
                        it.taker === it.sell
                    }.sumOf {
                        it.quantity
                    }
                    emit("FLOW buy", buy, "sell", sell, "net", buy - sell)
                }
                "SUMMARY" -> {
                    if (trades.isEmpty()) emit("SUMMARY trades 0") else emit("SUMMARY trades", trades.size, "volume", trades.sumOf {
                        it.quantity
                    }, bar(trades).substringBeforeLast(" volume"), "fees", trades.sumOf {
                        it.buyFee + it.sellFee
                    })
                    traders.values.forEach {
                        emit(it.position(last()))
                    }
                }
            }
        } catch (e: Rejection) {
            if (c in listOf("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG", "CANCEL", "REPLACE")) emit("REJECT", a[1], e.message!!) else emit("ERROR", e.message!!)
        }
    }
}
fun main() {
    val reader = System.`in`.bufferedReader()
    val engine = Engine()
    repeat(reader.readLine().toInt()) {
        engine.execute(reader.readLine())
    }
    print(engine.output)
}
