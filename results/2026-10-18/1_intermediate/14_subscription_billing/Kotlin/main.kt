import java.io.BufferedReader
import java.io.InputStreamReader

private class CommandError(message: String) : RuntimeException(message)

private fun fail(message: String): Nothing = throw CommandError(message)

private fun cents(text: String): Long {
    val parts = text.split(".")
    return parts[0].toLong() * 100 + parts[1].toLong()
}

private fun money(amount: Long): String {
    val absolute = kotlin.math.abs(amount)
    return (if (amount < 0) "-" else "") +
        (absolute / 100).toString() + "." + (absolute % 100).toString().padStart(2, '0')
}

private fun signedMoney(amount: Long): String =
    (if (amount > 0) "+" else "") + money(amount)

private fun percentage(basisPoints: Int): String = money(basisPoints.toLong()) + "%"

private data class Tier(val upper: Long?, val unitPrice: Long, val flatFee: Long)

private class Plan(
    val name: String,
    val price: Long,
    val cycle: String
) {
    val length: Int = when (cycle) {
        "WEEKLY" -> 7
        "MONTHLY" -> 30
        else -> 360
    }
    var trial = 0
    var setup = 0L
    var perSeat = false
    var mode: String? = null
    val tiers = mutableListOf<Tier>()

    fun fee(seats: Int): Long = if (perSeat) price * seats else price

    fun usageCharge(units: Long): Long {
        var total = 0L
        var lower = 0L
        for ((index, tier) in tiers.withIndex()) {
            val last = index == tiers.lastIndex
            if (mode == "VOLUME") {
                if (last || tier.upper == null || units <= tier.upper) {
                    return units * tier.unitPrice + tier.flatFee
                }
            } else {
                if (units <= lower) break
                val end = if (last || tier.upper == null) units else minOf(units, tier.upper)
                total += (end - lower) * tier.unitPrice + tier.flatFee
                if (last || tier.upper == null) break
                lower = tier.upper
            }
        }
        return total
    }
}

private data class BalanceRecord(
    val day: Int,
    val description: String,
    val amount: Long,
    val balance: Long
)

private class Customer(val name: String, val region: String) {
    var method = "OK"
    var balance = 0L
    val log = mutableListOf<BalanceRecord>()
    val subscriptions = mutableListOf<Subscription>()
    val invoices = mutableListOf<Invoice>()
}

private class Coupon(
    val name: String,
    val kind: String,
    val value: Long,
    val applications: Int?,
    val maximum: Int?
) {
    var redemptions = 0
}

private class Subscription(
    val number: Int,
    val customer: Customer,
    var plan: Plan,
    var seats: Int,
    var coupon: Coupon?
) {
    var state = "NONE"
    var start: Int? = null
    var end: Int? = null
    var trialEnd: Int? = null
    var pauseStart: Int? = null
    var pending: Pair<Plan, Int>? = null
    var cancelEnd = false
    var cancelOn: Int? = null
    var canceledOn: Int? = null
    var remaining: Int? = coupon?.applications
    var usage = 0L
    val invoices = mutableListOf<Invoice>()

    fun fee(): Long = plan.fee(seats)
    fun period(): String = "$start-$end"
}

private typealias BillItem = Pair<String, Long>

private data class Totals(
    val subtotal: Long,
    val discount: Long,
    val tax: Long,
    val total: Long,
    val credit: Long,
    val due: Long
)

private class Invoice(
    val number: Int,
    val subscription: Subscription,
    val day: Int,
    val kind: String,
    val items: List<BillItem>,
    totals: Totals
) {
    val customer: Customer = subscription.customer
    val subtotal = totals.subtotal
    val discount = totals.discount
    val tax = totals.tax
    val total = totals.total
    val credit = totals.credit
    val due = totals.due
    var paid = 0L
    var refunded = 0L
    var outstanding = due
    var attempts = 0
    val retries = mutableListOf<Int>()

    fun state(): String = if (outstanding != 0L) "OPEN" else "PAID"
}

private data class StateEvent(
    val day: Int,
    val number: Int,
    val previous: String,
    val current: String
)

private class BillingService {
    private var day = 1
    private val plans = mutableMapOf<String, Plan>()
    private val taxRates = mutableMapOf<String, Int>()
    private val customers = mutableMapOf<String, Customer>()
    private val coupons = mutableMapOf<String, Coupon>()
    private val subscriptions = mutableListOf<Subscription>()
    private val invoices = mutableListOf<Invoice>()
    private val events = mutableListOf<StateEvent>()
    val output = mutableListOf<String>()

    private fun emit(vararg parts: Any) {
        output.add(parts.joinToString(" ") { it.toString() })
    }

    private fun detail(vararg parts: Any) {
        output.add("  " + parts.joinToString(" ") { it.toString() })
    }

    private fun notice(vararg parts: Any) {
        detail("day", day, *parts)
    }

    private fun plan(name: String): Plan =
        plans[name] ?: fail("unknown plan $name")

    private fun customer(name: String): Customer =
        customers[name] ?: fail("unknown customer $name")

    private fun redeemableCoupon(name: String): Coupon {
        val coupon = coupons[name] ?: fail("unknown coupon $name")
        if (coupon.maximum != null && coupon.redemptions == coupon.maximum) {
            fail("coupon exhausted $name")
        }
        return coupon
    }

    private fun subscription(text: String, allowed: Set<String>? = null): Subscription {
        val index = text.toInt()
        if (index !in 1..subscriptions.size) fail("unknown sub $text")
        val subscription = subscriptions[index - 1]
        if (allowed != null && subscription.state !in allowed) {
            fail("invalid state $text ${subscription.state}")
        }
        return subscription
    }

    private fun invoice(text: String): Invoice {
        val index = text.toInt()
        if (index !in 1..invoices.size) fail("unknown invoice $text")
        return invoices[index - 1]
    }

    private fun balanceChange(customer: Customer, change: Long, description: String) {
        if (change != 0L) {
            customer.balance += change
            customer.log.add(BalanceRecord(day, description, change, customer.balance))
        }
    }

    private fun changeState(subscription: Subscription, state: String) {
        val old = subscription.state
        if (old == "PAST_DUE") {
            subscription.invoices.forEach { it.retries.clear() }
        }
        subscription.state = state
        notice("sub", subscription.number, old, "->", state)
        events.add(StateEvent(day, subscription.number, old, state))
    }

    private fun periodItem(plan: Plan, seats: Int, start: Int): BillItem =
        "charge ${plan.name} seats $seats $start-${start + plan.length}" to plan.fee(seats)

    private fun openingItems(subscription: Subscription, start: Int): MutableList<BillItem> {
        val items = mutableListOf(periodItem(subscription.plan, subscription.seats, start))
        if (subscription.plan.setup != 0L) {
            items.add("setup ${subscription.plan.name}" to subscription.plan.setup)
        }
        return items
    }

    private fun usageItems(subscription: Subscription, close: Boolean = false): MutableList<BillItem> {
        if (subscription.plan.mode == null || subscription.usage == 0L) {
            return mutableListOf()
        }
        val units = subscription.usage
        val result = mutableListOf(
            "usage ${subscription.plan.name} $units units" to subscription.plan.usageCharge(units)
        )
        if (close) subscription.usage = 0L
        return result
    }

    private fun couponUsable(subscription: Subscription, subtotal: Long): Boolean =
        subtotal > 0L && subscription.coupon != null &&
        (subscription.remaining == null || subscription.remaining!! > 0)

    private fun invoiceTotals(subscription: Subscription, items: List<BillItem>): Totals {
        val subtotal = items.sumOf { it.second }
        var discount = 0L
        if (couponUsable(subscription, subtotal)) {
            val coupon = subscription.coupon!!
            discount = if (coupon.kind == "PERCENT") {
                subtotal * coupon.value / 10000
            } else {
                minOf(subtotal, coupon.value)
            }
        }
        val tax = (subtotal - discount) * (taxRates[subscription.customer.region] ?: 0) / 10000
        val total = subtotal - discount + tax
        val credit = minOf(subscription.customer.balance, total)
        return Totals(subtotal, discount, tax, total, credit, total - credit)
    }

    private fun issue(subscription: Subscription, kind: String, items: List<BillItem>) {
        val totals = invoiceTotals(subscription, items)
        val invoice = Invoice(invoices.size + 1, subscription, day, kind, items.toList(), totals)
        if (couponUsable(subscription, invoice.subtotal) && subscription.remaining != null) {
            subscription.remaining = subscription.remaining!! - 1
        }
        invoices.add(invoice)
        subscription.invoices.add(invoice)
        subscription.customer.invoices.add(invoice)
        balanceChange(subscription.customer, -invoice.credit, "applied invoice ${invoice.number}")

        val result: String
        if (invoice.due == 0L) {
            result = "PAID"
        } else if (subscription.state == "UNPAID") {
            result = "OPEN"
        } else {
            invoice.attempts = 1
            if (subscription.customer.method == "OK") {
                invoice.paid = invoice.due
                invoice.outstanding = 0L
                result = "PAID"
            } else {
                result = "FAILED"
            }
        }

        notice(
            "invoice", invoice.number, "sub", subscription.number, kind,
            "total", money(invoice.total), "credit", money(invoice.credit),
            "due", money(invoice.due), result
        )
        if (result == "FAILED") {
            if (subscription.state == "ACTIVE") changeState(subscription, "PAST_DUE")
            if (subscription.state == "PAST_DUE") {
                invoice.retries.addAll(listOf(day + 3, day + 5, day + 7))
            }
        }
    }

    private fun paymentComplete(invoice: Invoice) {
        invoice.retries.clear()
        val subscription = invoice.subscription
        if (subscription.state in setOf("PAST_DUE", "UNPAID") &&
            subscription.invoices.all { it.outstanding == 0L }) {
            subscription.cancelOn = null
            changeState(subscription, "ACTIVE")
        }
    }

    private fun cancelSubscription(subscription: Subscription) {
        changeState(subscription, "CANCELED")
        subscription.canceledOn = day
        subscription.pending = null
        subscription.cancelEnd = false
        subscription.cancelOn = null
        val items = usageItems(subscription, close = true)
        if (items.isNotEmpty()) issue(subscription, "final", items)
    }

    private fun retry(invoice: Invoice) {
        invoice.retries.removeAt(0)
        invoice.attempts++
        val number = invoice.attempts - 1
        if (invoice.customer.method == "OK") {
            invoice.paid += invoice.outstanding
            invoice.outstanding = 0L
            notice("retry", number, "invoice", invoice.number, "PAID")
            paymentComplete(invoice)
        } else {
            notice("retry", number, "invoice", invoice.number, "FAILED")
            if (invoice.retries.isEmpty()) {
                changeState(invoice.subscription, "UNPAID")
                invoice.subscription.cancelOn = day + 14
            }
        }
    }

    private fun advanceSubscription(subscription: Subscription) {
        if (subscription.state in setOf("PAUSED", "CANCELED")) return

        for (invoice in subscription.invoices.toList()) {
            if (invoice.retries.firstOrNull() == day) retry(invoice)
        }
        if (subscription.state == "UNPAID" && subscription.cancelOn == day) {
            cancelSubscription(subscription)
        }
        if (subscription.state == "TRIALING" && subscription.trialEnd == day) {
            if (subscription.cancelEnd) {
                cancelSubscription(subscription)
            } else {
                changeState(subscription, "ACTIVE")
                subscription.start = day
                subscription.end = day + subscription.plan.length
                issue(subscription, "first", openingItems(subscription, day))
            }
        }
        if (subscription.state in setOf("ACTIVE", "PAST_DUE", "UNPAID") &&
            subscription.end == day) {
            if (subscription.cancelEnd) {
                cancelSubscription(subscription)
            } else {
                val items = usageItems(subscription, close = true)
                val pending = subscription.pending
                if (pending != null) {
                    val (plan, seats) = pending
                    notice(
                        "sub", subscription.number, subscription.plan.name, "seats",
                        subscription.seats, "->", plan.name, "seats", seats
                    )
                    subscription.plan = plan
                    subscription.seats = seats
                    subscription.pending = null
                }
                subscription.start = day
                subscription.end = day + subscription.plan.length
                items.add(periodItem(subscription.plan, subscription.seats, day))
                issue(subscription, "renewal", items)
            }
        }
    }

    private fun commandPlan(a: List<String>) {
        val name = a[0]
        val amount = a[1]
        val cycle = a[2]
        if (plans.containsKey(name)) fail("duplicate plan $name")
        val plan = Plan(name, cents(amount), cycle)
        var index = 3
        while (index < a.size) {
            when (a[index]) {
                "TRIAL" -> {
                    plan.trial = a[index + 1].toInt()
                    index += 2
                }
                "SETUP" -> {
                    plan.setup = cents(a[index + 1])
                    index += 2
                }
                "PERSEAT" -> {
                    plan.perSeat = true
                    index++
                }
                else -> {
                    plan.mode = a[index]
                    index++
                }
            }
        }
        plans[name] = plan
        var line = "PLAN $name $cycle $amount"
        if (plan.trial != 0) line += " trial ${plan.trial}"
        if (plan.setup != 0L) line += " setup ${money(plan.setup)}"
        if (plan.perSeat) line += " perseat"
        if (plan.mode != null) line += " ${plan.mode!!.lowercase()}"
        emit(line)
    }

    private fun commandTier(a: List<String>) {
        val name = a[0]
        val plan = plan(name)
        if (plan.mode == null) fail("not metered $name")
        val upper: Long? = if (a[1] == "INF") null else a[1].toLong()
        if (plan.tiers.isNotEmpty()) {
            val previous = plan.tiers.last().upper
            if (previous == null || (upper != null && upper <= previous)) {
                fail("tier order $name")
            }
        }
        plan.tiers.add(Tier(upper, cents(a[2]), cents(a[3])))
        emit("TIER", name, plan.tiers.size, "upto", a[1], "unit", a[2], "flat", a[3])
    }

    private fun commandTax(a: List<String>) {
        val rate = a[1].toInt()
        taxRates[a[0]] = rate
        emit("TAX", a[0], percentage(rate))
    }

    private fun commandCustomer(a: List<String>) {
        val name = a[0]
        if (customers.containsKey(name)) fail("duplicate customer $name")
        customers[name] = Customer(name, a[1])
        emit("CUSTOMER", name, "region", a[1])
    }

    private fun commandCoupon(a: List<String>) {
        val name = a[0]
        val kind = a[1]
        val application = a[3]
        if (coupons.containsKey(name)) fail("duplicate coupon $name")
        var applications: Int? = if (application == "ONCE") 1 else null
        var index = 4
        if (application == "REPEATING") {
            applications = a[index].toInt()
            index++
        }
        val maximum: Int? = if (index < a.size) a[index + 1].toInt() else null
        val numericValue = if (kind == "PERCENT") a[2].toLong() else cents(a[2])
        val coupon = Coupon(name, kind, numericValue, applications, maximum)
        coupons[name] = coupon
        val shownValue = if (kind == "PERCENT") percentage(numericValue.toInt()) else money(numericValue)
        var line = "COUPON $name ${kind.lowercase()} $shownValue ${application.lowercase()}"
        if (application == "REPEATING") line += " $applications"
        if (maximum != null) line += " max $maximum"
        emit(line)
    }

    private fun commandPayMethod(a: List<String>) {
        val customer = customer(a[0])
        customer.method = a[1]
        emit("PAYMETHOD", a[0], a[1])
    }

    private fun commandCredit(a: List<String>) {
        val customer = customer(a[0])
        val value = cents(a[1])
        if (value == 0L) fail("invalid amount")
        balanceChange(customer, value, "grant")
        emit("CREDIT", a[0], "amount", a[1], "balance", money(customer.balance))
    }

    private fun commandDay(a: List<String>) {
        val target = a[0].toInt()
        if (target <= day) fail("invalid day ${a[0]}")
        emit("DAY", target)
        for (nextDay in day + 1..target) {
            day = nextDay
            for (subscription in subscriptions) advanceSubscription(subscription)
        }
    }

    private fun commandSubscribe(a: List<String>) {
        val customer = customer(a[0])
        val plan = plan(a[1])
        var seats = 1
        var hasSeats = false
        var couponName: String? = null
        var index = 2
        while (index < a.size) {
            if (a[index] == "SEATS") {
                seats = a[index + 1].toInt()
                hasSeats = true
            } else {
                couponName = a[index + 1]
            }
            index += 2
        }
        if (hasSeats && !plan.perSeat) fail("not per-seat ${plan.name}")
        if (seats == 0) fail("invalid seats")
        val coupon = if (couponName == null) null else redeemableCoupon(couponName)
        val subscription = Subscription(subscriptions.size + 1, customer, plan, seats, coupon)
        if (coupon != null) coupon.redemptions++
        subscriptions.add(subscription)
        customer.subscriptions.add(subscription)
        var line = "SUBSCRIBE sub ${subscription.number} ${customer.name} ${plan.name} seats $seats"
        if (coupon != null) line += " coupon ${coupon.name}"
        emit(line)
        if (plan.trial != 0) {
            subscription.trialEnd = day + plan.trial
            changeState(subscription, "TRIALING")
        } else {
            changeState(subscription, "ACTIVE")
            subscription.start = day
            subscription.end = day + plan.length
            issue(subscription, "first", openingItems(subscription, day))
        }
    }

    private fun commandChange(a: List<String>) {
        val subscription = subscription(a[0], setOf("ACTIVE", "TRIALING"))
        val plan: Plan
        val seats: Int
        if (a[1] == "PLAN") {
            plan = plan(a[2])
            seats = if (plan.perSeat) subscription.seats else 1
        } else {
            plan = subscription.plan
            if (!plan.perSeat) fail("not per-seat ${plan.name}")
            seats = a[2].toInt()
            if (seats == 0) fail("invalid seats")
        }
        if (plan === subscription.plan && seats == subscription.seats) {
            fail("no change ${a[0]}")
        }
        val oldPlan = subscription.plan
        val oldSeats = subscription.seats
        val head = "CHANGE sub ${subscription.number} ${oldPlan.name} seats $oldSeats -> ${plan.name} seats $seats"
        subscription.pending = null
        val upgrade = plan.fee(seats) * oldPlan.length > oldPlan.fee(oldSeats) * plan.length
        if (subscription.state == "TRIALING") {
            subscription.plan = plan
            subscription.seats = seats
            emit("$head now")
        } else if (upgrade) {
            emit("$head now")
            val days = subscription.end!! - day
            val items = usageItems(subscription, close = true)
            items.add("unused ${oldPlan.name} seats $oldSeats $days days" to
                      -(oldPlan.fee(oldSeats) * days / oldPlan.length))
            items.add("remaining ${plan.name} seats $seats $days days" to
                      (plan.fee(seats) * days / plan.length))
            subscription.plan = plan
            subscription.seats = seats
            issue(subscription, "upgrade", items)
        } else {
            subscription.pending = plan to seats
            emit("$head at ${subscription.end}")
        }
    }

    private fun commandPause(a: List<String>) {
        val subscription = subscription(a[0], setOf("ACTIVE"))
        emit("PAUSE", "sub", subscription.number)
        subscription.pauseStart = day
        changeState(subscription, "PAUSED")
    }

    private fun commandResume(a: List<String>) {
        val subscription = subscription(a[0], setOf("PAUSED"))
        val elapsed = day - subscription.pauseStart!!
        subscription.end = subscription.end!! + elapsed
        subscription.pauseStart = null
        emit("RESUME", "sub", subscription.number, "shift", elapsed, "period", subscription.period())
        changeState(subscription, "ACTIVE")
    }

    private fun commandCancel(a: List<String>) {
        val subscription = subscription(a[0])
        if (a[1] == "END") {
            if (subscription.state !in setOf("ACTIVE", "TRIALING")) {
                fail("invalid state ${a[0]} ${subscription.state}")
            }
            if (subscription.cancelEnd) fail("already canceling ${a[0]}")
            subscription.cancelEnd = true
            val at = if (subscription.state == "TRIALING") subscription.trialEnd else subscription.end
            emit("CANCEL", "sub", subscription.number, "end", at!!)
        } else {
            if (subscription.state == "CANCELED") {
                fail("invalid state ${a[0]} ${subscription.state}")
            }
            var refund = 0L
            if (subscription.state in setOf("ACTIVE", "PAUSED")) {
                val start = if (subscription.state == "ACTIVE") day else subscription.pauseStart!!
                refund = subscription.fee() * (subscription.end!! - start) / subscription.plan.length
            }
            balanceChange(subscription.customer, refund, "cancel sub ${subscription.number}")
            emit("CANCEL", "sub", subscription.number, "now", "credit", money(refund))
            cancelSubscription(subscription)
        }
    }

    private fun commandUsage(a: List<String>) {
        val subscription = subscription(a[0], setOf("ACTIVE", "PAST_DUE"))
        if (subscription.plan.mode == null) fail("not metered ${subscription.plan.name}")
        val quantity = a[1].toLong()
        if (quantity == 0L) fail("invalid units")
        subscription.usage += quantity
        emit("USAGE", "sub", subscription.number, "units", quantity, "total", subscription.usage)
    }

    private fun commandApply(a: List<String>) {
        val subscription = subscription(a[0])
        if (subscription.state == "CANCELED") {
            fail("invalid state ${a[0]} ${subscription.state}")
        }
        val coupon = redeemableCoupon(a[1])
        coupon.redemptions++
        subscription.coupon = coupon
        subscription.remaining = coupon.applications
        emit("APPLY", "sub", subscription.number, "coupon", coupon.name)
    }

    private fun commandPay(a: List<String>) {
        val invoice = invoice(a[0])
        if (invoice.outstanding == 0L) fail("already paid ${a[0]}")
        emit("PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
        invoice.paid += invoice.outstanding
        invoice.outstanding = 0L
        paymentComplete(invoice)
    }

    private fun commandRefund(a: List<String>) {
        val invoice = invoice(a[0])
        val value = cents(a[1])
        if (value == 0L) fail("invalid amount")
        val maximum = invoice.total - invoice.refunded
        if (value > maximum) {
            fail("refund exceeds ${a[0]} ${money(maximum)}")
        }
        val applied = minOf(value, invoice.outstanding)
        invoice.refunded += value
        invoice.outstanding -= applied
        balanceChange(invoice.customer, value - applied, "refund invoice ${invoice.number}")
        emit(
            "REFUND", "invoice", invoice.number, "amount", a[1],
            "applied", money(applied), "balance", money(invoice.customer.balance)
        )
        if (applied != 0L && invoice.outstanding == 0L) paymentComplete(invoice)
    }

    private fun emitItems(items: List<BillItem>) {
        for ((description, amount) in items) detail(description, money(amount))
    }

    private fun emitTotals(totals: Totals) {
        detail(
            "subtotal", money(totals.subtotal), "discount", money(totals.discount),
            "tax", money(totals.tax), "total", money(totals.total)
        )
    }

    private fun commandInvoice(a: List<String>) {
        val invoice = invoice(a[0])
        emit(
            "INVOICE", invoice.number, "sub", invoice.subscription.number,
            invoice.customer.name, "day", invoice.day, invoice.kind, invoice.state()
        )
        emitItems(invoice.items)
        emitTotals(
            Totals(invoice.subtotal, invoice.discount, invoice.tax, invoice.total, invoice.credit, invoice.due)
        )
        detail(
            "credit", money(invoice.credit), "due", money(invoice.due),
            "paid", money(invoice.paid), "refunded", money(invoice.refunded),
            "outstanding", money(invoice.outstanding)
        )
    }

    private fun commandSub(a: List<String>) {
        val subscription = subscription(a[0])
        emit(
            "SUB", subscription.number, subscription.customer.name, subscription.plan.name,
            "seats", subscription.seats, subscription.state
        )
        if (subscription.state == "TRIALING") detail("trial until", subscription.trialEnd!!)
        if (subscription.state in setOf("ACTIVE", "PAST_DUE", "UNPAID", "PAUSED")) {
            detail("period", subscription.period())
        }
        if (subscription.state == "PAUSED") detail("paused since", subscription.pauseStart!!)
        subscription.pending?.let { (plan, seats) ->
            detail("pending", plan.name, "seats", seats)
        }
        if (subscription.cancelEnd) detail("cancel at end")
        subscription.cancelOn?.let { detail("cancel on", it) }
        if (subscription.state == "CANCELED") detail("canceled on", subscription.canceledOn!!)
        subscription.coupon?.let { coupon ->
            if (subscription.remaining == null) {
                detail("coupon", coupon.name, "forever")
            } else if (subscription.remaining!! > 0) {
                detail("coupon", coupon.name, "left", subscription.remaining!!)
            }
        }
        if (subscription.plan.mode != null && subscription.state != "CANCELED") {
            detail("usage", subscription.usage)
        }
        val open = subscription.invoices.filter { it.outstanding != 0L }.map { it.number }
        if (open.isNotEmpty()) detail("open", open.joinToString(" "))
    }

    private fun commandPreview(a: List<String>) {
        val subscription = subscription(a[0], setOf("TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"))
        val date = if (subscription.state == "TRIALING") subscription.trialEnd!! else subscription.end!!
        val kind: String
        val items: MutableList<BillItem>
        if (subscription.cancelEnd) {
            kind = "final"
            items = if (subscription.state == "TRIALING") mutableListOf() else usageItems(subscription)
        } else if (subscription.state == "TRIALING") {
            kind = "first"
            items = openingItems(subscription, date)
        } else {
            kind = "renewal"
            val (plan, seats) = subscription.pending ?: (subscription.plan to subscription.seats)
            items = usageItems(subscription)
            items.add(periodItem(plan, seats, date))
        }
        emit("PREVIEW", "sub", subscription.number, "day", date, kind)
        if (items.isEmpty()) {
            detail("(none)")
            return
        }
        emitItems(items)
        val totals = invoiceTotals(subscription, items)
        emitTotals(totals)
        detail("credit", money(totals.credit), "due", money(totals.due))
    }

    private fun commandStatement(a: List<String>) {
        val customer = customer(a[0])
        emit(
            "STATEMENT", customer.name, "region", customer.region,
            "tax", percentage(taxRates[customer.region] ?: 0),
            "method", customer.method, "balance", money(customer.balance)
        )
        for (subscription in customer.subscriptions) {
            detail("sub", subscription.number, subscription.plan.name, subscription.state)
        }
        for (invoice in customer.invoices) {
            detail(
                "invoice", invoice.number, "day", invoice.day, "sub",
                invoice.subscription.number, invoice.kind, "total", money(invoice.total),
                "outstanding", money(invoice.outstanding)
            )
        }
        detail("outstanding", money(customer.invoices.sumOf { it.outstanding }))
    }

    private fun commandLedger(a: List<String>) {
        val customer = customer(a[0])
        emit("LEDGER", customer.name, "balance", money(customer.balance))
        for (entry in customer.log) {
            detail(
                "day", entry.day, entry.description, signedMoney(entry.amount),
                "balance", money(entry.balance)
            )
        }
        if (customer.log.isEmpty()) detail("(none)")
    }

    private fun commandMrr() {
        val byPlan = mutableMapOf<String, Pair<Int, Long>>()
        for (subscription in subscriptions) {
            if (subscription.state !in setOf("ACTIVE", "PAST_DUE")) continue
            val fee = subscription.fee()
            val monthly = when (subscription.plan.cycle) {
                "MONTHLY" -> fee
                "YEARLY" -> fee / 12
                else -> fee * 30 / 7
            }
            val row = byPlan[subscription.plan.name] ?: (0 to 0L)
            byPlan[subscription.plan.name] = (row.first + 1) to (row.second + monthly)
        }
        emit("MRR")
        for (name in byPlan.keys.sorted()) {
            val (count, monthly) = byPlan.getValue(name)
            detail(name, "subs", count, "mrr", money(monthly))
        }
        detail(
            "total subs", byPlan.values.sumOf { it.first },
            "mrr", money(byPlan.values.sumOf { it.second })
        )
    }

    private fun agingParts(amounts: LongArray): String =
        "0-30 ${money(amounts[0])} 31-60 ${money(amounts[1])} " +
        "61+ ${money(amounts[2])} sum ${money(amounts.sum())}"

    private fun commandAging() {
        val byCustomer = mutableMapOf<String, LongArray>()
        val totals = LongArray(3)
        for (invoice in invoices) {
            if (invoice.outstanding == 0L) continue
            val age = day - invoice.day
            val bucket = if (age <= 30) 0 else if (age <= 60) 1 else 2
            byCustomer.getOrPut(invoice.customer.name) { LongArray(3) }[bucket] += invoice.outstanding
            totals[bucket] += invoice.outstanding
        }
        emit("AGING", "day", day)
        for (name in byCustomer.keys.sorted()) detail(name, agingParts(byCustomer.getValue(name)))
        detail("total", agingParts(totals))
    }

    private fun commandDunning() {
        emit("DUNNING")
        val pending = invoices.filter { it.retries.isNotEmpty() }
        for (invoice in pending) {
            detail(
                "invoice", invoice.number, "sub", invoice.subscription.number,
                invoice.customer.name, "outstanding", money(invoice.outstanding),
                "attempts", invoice.attempts, "next", invoice.retries[0]
            )
        }
        if (pending.isEmpty()) detail("(none)")
    }

    private fun commandRevenue() {
        emit("REVENUE")
        detail(
            "invoices", invoices.size, "subtotal", money(invoices.sumOf { it.subtotal }),
            "discount", money(invoices.sumOf { it.discount }),
            "tax", money(invoices.sumOf { it.tax }),
            "total", money(invoices.sumOf { it.total })
        )
        detail(
            "credit", money(invoices.sumOf { it.credit }),
            "paid", money(invoices.sumOf { it.paid }),
            "refunded", money(invoices.sumOf { it.refunded }),
            "outstanding", money(invoices.sumOf { it.outstanding }),
            "balances", money(customers.values.sumOf { it.balance })
        )
    }

    private fun commandEvents(a: List<String>) {
        val selected = if (a.isEmpty()) null else subscription(a[0]).number
        if (selected == null) emit("EVENTS") else emit("EVENTS", "sub", selected)
        val matching = events.filter { selected == null || it.number == selected }
        for (event in matching) {
            detail("day", event.day, "sub", event.number, event.previous, "->", event.current)
        }
        if (matching.isEmpty()) detail("(none)")
    }

    fun execute(line: String) {
        val words = line.trim().split(" ")
        val args = words.drop(1)
        try {
            when (words[0]) {
                "PLAN" -> commandPlan(args)
                "TIER" -> commandTier(args)
                "TAX" -> commandTax(args)
                "CUSTOMER" -> commandCustomer(args)
                "COUPON" -> commandCoupon(args)
                "PAYMETHOD" -> commandPayMethod(args)
                "CREDIT" -> commandCredit(args)
                "DAY" -> commandDay(args)
                "SUBSCRIBE" -> commandSubscribe(args)
                "CHANGE" -> commandChange(args)
                "PAUSE" -> commandPause(args)
                "RESUME" -> commandResume(args)
                "CANCEL" -> commandCancel(args)
                "USAGE" -> commandUsage(args)
                "APPLY" -> commandApply(args)
                "PAY" -> commandPay(args)
                "REFUND" -> commandRefund(args)
                "INVOICE" -> commandInvoice(args)
                "SUB" -> commandSub(args)
                "PREVIEW" -> commandPreview(args)
                "STATEMENT" -> commandStatement(args)
                "LEDGER" -> commandLedger(args)
                "MRR" -> commandMrr()
                "AGING" -> commandAging()
                "DUNNING" -> commandDunning()
                "REVENUE" -> commandRevenue()
                "EVENTS" -> commandEvents(args)
            }
        } catch (error: CommandError) {
            emit("ERROR", error.message ?: "")
        }
    }
}

fun main() {
    val reader = BufferedReader(InputStreamReader(System.`in`))
    val count = reader.readLine().trim().toInt()
    val service = BillingService()
    repeat(count) {
        service.execute(reader.readLine())
    }
    if (service.output.isNotEmpty()) {
        print(service.output.joinToString("\n", postfix = "\n"))
    }
}
