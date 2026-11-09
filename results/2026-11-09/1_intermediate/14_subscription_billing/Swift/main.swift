import Foundation

private enum BillingError: Error {
    case invalid(String)
}

private func fail(_ reason: String) -> BillingError {
    .invalid(reason)
}

private func cents(_ text: String) -> Int {
    let parts = text.split(separator: ".")
    return Int(parts[0])! * 100 + Int(parts[1])!
}

private func money(_ value: Int) -> String {
    let absolute = abs(value)
    return (value < 0 ? "-" : "") +
        "\(absolute / 100)." + String(format: "%02d", absolute % 100)
}

private func signedMoney(_ value: Int) -> String {
    (value > 0 ? "+" : "") + money(value)
}

private func percentage(_ basisPoints: Int) -> String {
    money(basisPoints) + "%"
}

private struct Tier {
    let upper: Int?
    let unitPrice: Int
    let flatFee: Int
}

private final class Plan {
    let name: String
    let price: Int
    let cycle: String
    let length: Int
    var trial = 0
    var setup = 0
    var perSeat = false
    var mode: String?
    var tiers: [Tier] = []

    init(name: String, price: Int, cycle: String) {
        self.name = name
        self.price = price
        self.cycle = cycle
        switch cycle {
        case "WEEKLY": length = 7
        case "MONTHLY": length = 30
        default: length = 360
        }
    }

    func fee(_ seats: Int) -> Int {
        perSeat ? price * seats : price
    }

    func usageCharge(_ units: Int) -> Int {
        var total = 0
        var lower = 0
        for (index, tier) in tiers.enumerated() {
            let last = index == tiers.count - 1
            if mode == "VOLUME" {
                if last || tier.upper == nil || units <= tier.upper! {
                    return units * tier.unitPrice + tier.flatFee
                }
            } else {
                if units <= lower { break }
                let end = last || tier.upper == nil ? units : min(units, tier.upper!)
                total += (end - lower) * tier.unitPrice + tier.flatFee
                if last || tier.upper == nil { break }
                lower = tier.upper!
            }
        }
        return total
    }
}

private struct BalanceRecord {
    let day: Int
    let description: String
    let change: Int
    let balance: Int
}

private final class Customer {
    let name: String
    let region: String
    var method = "OK"
    var balance = 0
    var log: [BalanceRecord] = []
    var subscriptions: [Subscription] = []
    var invoices: [Invoice] = []

    init(name: String, region: String) {
        self.name = name
        self.region = region
    }
}

private final class Coupon {
    let name: String
    let kind: String
    let value: Int
    let applications: Int?
    let maximum: Int?
    var redemptions = 0

    init(name: String, kind: String, value: Int, applications: Int?, maximum: Int?) {
        self.name = name
        self.kind = kind
        self.value = value
        self.applications = applications
        self.maximum = maximum
    }
}

private final class Subscription {
    let number: Int
    let customer: Customer
    var plan: Plan
    var seats: Int
    var state = "NONE"
    var start: Int?
    var end: Int?
    var trialEnd: Int?
    var pauseStart: Int?
    var pending: (Plan, Int)?
    var cancelEnd = false
    var cancelOn: Int?
    var canceledOn: Int?
    var coupon: Coupon?
    var remaining: Int?
    var usage = 0
    var invoices: [Invoice] = []

    init(number: Int, customer: Customer, plan: Plan, seats: Int, coupon: Coupon?) {
        self.number = number
        self.customer = customer
        self.plan = plan
        self.seats = seats
        self.coupon = coupon
        remaining = coupon?.applications
    }

    func fee() -> Int { plan.fee(seats) }

    func period() -> String { "\(start!)-\(end!)" }
}

private struct BillItem {
    let description: String
    let amount: Int
}

private struct Totals {
    let subtotal: Int
    let discount: Int
    let tax: Int
    let total: Int
    let credit: Int
    let due: Int
}

private final class Invoice {
    let number: Int
    let subscription: Subscription
    let customer: Customer
    let day: Int
    let kind: String
    let items: [BillItem]
    let subtotal: Int
    let discount: Int
    let tax: Int
    let total: Int
    let credit: Int
    let due: Int
    var paid = 0
    var refunded = 0
    var outstanding: Int
    var attempts = 0
    var retries: [Int] = []

    init(number: Int, subscription: Subscription, day: Int,
         kind: String, items: [BillItem], totals: Totals) {
        self.number = number
        self.subscription = subscription
        customer = subscription.customer
        self.day = day
        self.kind = kind
        self.items = items
        subtotal = totals.subtotal
        discount = totals.discount
        tax = totals.tax
        total = totals.total
        credit = totals.credit
        due = totals.due
        outstanding = totals.due
    }

    func state() -> String { outstanding == 0 ? "PAID" : "OPEN" }
}

private struct StateEvent {
    let day: Int
    let number: Int
    let old: String
    let new: String
}

private final class BillingService {
    private var day = 1
    private var plans: [String: Plan] = [:]
    private var taxRates: [String: Int] = [:]
    private var customers: [String: Customer] = [:]
    private var coupons: [String: Coupon] = [:]
    private var subscriptions: [Subscription] = []
    private var invoices: [Invoice] = []
    private var events: [StateEvent] = []
    private(set) var output: [String] = []

    private func line(_ parts: [Any], indent: Int = 0) {
        output.append(String(repeating: " ", count: indent) +
                      parts.map { String(describing: $0) }.joined(separator: " "))
    }

    private func emit(_ parts: Any...) {
        line(parts)
    }

    private func detail(_ parts: Any...) {
        line(parts, indent: 2)
    }

    private func notice(_ parts: Any...) {
        line(["day", day] + parts, indent: 2)
    }

    private func plan(_ name: String) throws -> Plan {
        guard let result = plans[name] else { throw fail("unknown plan \(name)") }
        return result
    }

    private func customer(_ name: String) throws -> Customer {
        guard let result = customers[name] else { throw fail("unknown customer \(name)") }
        return result
    }

    private func redeemableCoupon(_ name: String) throws -> Coupon {
        guard let coupon = coupons[name] else { throw fail("unknown coupon \(name)") }
        if let maximum = coupon.maximum, coupon.redemptions == maximum {
            throw fail("coupon exhausted \(name)")
        }
        return coupon
    }

    private func subscription(_ text: String, allowed: Set<String>? = nil) throws -> Subscription {
        let number = Int(text)!
        guard (1...subscriptions.count).contains(number) else {
            throw fail("unknown sub \(text)")
        }
        let result = subscriptions[number - 1]
        if let allowed, !allowed.contains(result.state) {
            throw fail("invalid state \(text) \(result.state)")
        }
        return result
    }

    private func invoice(_ text: String) throws -> Invoice {
        let number = Int(text)!
        guard (1...invoices.count).contains(number) else {
            throw fail("unknown invoice \(text)")
        }
        return invoices[number - 1]
    }

    private func balanceChange(_ customer: Customer, by change: Int, description: String) {
        if change != 0 {
            customer.balance += change
            customer.log.append(BalanceRecord(
                day: day, description: description, change: change, balance: customer.balance
            ))
        }
    }

    private func changeState(_ subscription: Subscription, to state: String) {
        let old = subscription.state
        if old == "PAST_DUE" {
            for invoice in subscription.invoices { invoice.retries.removeAll() }
        }
        subscription.state = state
        notice("sub", subscription.number, old, "->", state)
        events.append(StateEvent(day: day, number: subscription.number, old: old, new: state))
    }

    private func periodItem(_ plan: Plan, seats: Int, start: Int) -> BillItem {
        BillItem(
            description: "charge \(plan.name) seats \(seats) \(start)-\(start + plan.length)",
            amount: plan.fee(seats)
        )
    }

    private func openingItems(_ subscription: Subscription, start: Int) -> [BillItem] {
        var result = [periodItem(subscription.plan, seats: subscription.seats, start: start)]
        if subscription.plan.setup != 0 {
            result.append(BillItem(
                description: "setup \(subscription.plan.name)",
                amount: subscription.plan.setup
            ))
        }
        return result
    }

    private func usageItems(_ subscription: Subscription, close: Bool = false) -> [BillItem] {
        if subscription.plan.mode == nil || subscription.usage == 0 { return [] }
        let units = subscription.usage
        let result = [BillItem(
            description: "usage \(subscription.plan.name) \(units) units",
            amount: subscription.plan.usageCharge(units)
        )]
        if close { subscription.usage = 0 }
        return result
    }

    private func couponUsable(_ subscription: Subscription, subtotal: Int) -> Bool {
        subtotal > 0 && subscription.coupon != nil &&
        (subscription.remaining == nil || subscription.remaining! > 0)
    }

    private func invoiceTotals(_ subscription: Subscription, items: [BillItem]) -> Totals {
        let subtotal = items.reduce(0) { $0 + $1.amount }
        var discount = 0
        if couponUsable(subscription, subtotal: subtotal) {
            let coupon = subscription.coupon!
            discount = coupon.kind == "PERCENT"
                ? subtotal * coupon.value / 10000
                : min(subtotal, coupon.value)
        }
        let tax = (subtotal - discount) *
                  (taxRates[subscription.customer.region] ?? 0) / 10000
        let total = subtotal - discount + tax
        let credit = min(subscription.customer.balance, total)
        return Totals(
            subtotal: subtotal, discount: discount, tax: tax, total: total,
            credit: credit, due: total - credit
        )
    }

    private func issue(_ subscription: Subscription, kind: String, items: [BillItem]) {
        let totals = invoiceTotals(subscription, items: items)
        let invoice = Invoice(
            number: invoices.count + 1, subscription: subscription,
            day: day, kind: kind, items: items, totals: totals
        )
        if couponUsable(subscription, subtotal: invoice.subtotal),
           let remaining = subscription.remaining {
            subscription.remaining = remaining - 1
        }
        invoices.append(invoice)
        subscription.invoices.append(invoice)
        subscription.customer.invoices.append(invoice)
        balanceChange(subscription.customer, by: -invoice.credit,
                      description: "applied invoice \(invoice.number)")

        let result: String
        if invoice.due == 0 {
            result = "PAID"
        } else if subscription.state == "UNPAID" {
            result = "OPEN"
        } else {
            invoice.attempts = 1
            if subscription.customer.method == "OK" {
                invoice.paid = invoice.due
                invoice.outstanding = 0
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
        if result == "FAILED" {
            if subscription.state == "ACTIVE" { changeState(subscription, to: "PAST_DUE") }
            if subscription.state == "PAST_DUE" {
                invoice.retries = [day + 3, day + 5, day + 7]
            }
        }
    }

    private func paymentComplete(_ invoice: Invoice) {
        invoice.retries.removeAll()
        let subscription = invoice.subscription
        if ["PAST_DUE", "UNPAID"].contains(subscription.state) &&
           subscription.invoices.allSatisfy({ $0.outstanding == 0 }) {
            subscription.cancelOn = nil
            changeState(subscription, to: "ACTIVE")
        }
    }

    private func cancelSubscription(_ subscription: Subscription) {
        changeState(subscription, to: "CANCELED")
        subscription.canceledOn = day
        subscription.pending = nil
        subscription.cancelEnd = false
        subscription.cancelOn = nil
        let items = usageItems(subscription, close: true)
        if !items.isEmpty { issue(subscription, kind: "final", items: items) }
    }

    private func retry(_ invoice: Invoice) {
        invoice.retries.removeFirst()
        invoice.attempts += 1
        let number = invoice.attempts - 1
        if invoice.customer.method == "OK" {
            invoice.paid += invoice.outstanding
            invoice.outstanding = 0
            notice("retry", number, "invoice", invoice.number, "PAID")
            paymentComplete(invoice)
        } else {
            notice("retry", number, "invoice", invoice.number, "FAILED")
            if invoice.retries.isEmpty {
                changeState(invoice.subscription, to: "UNPAID")
                invoice.subscription.cancelOn = day + 14
            }
        }
    }

    private func advanceSubscription(_ subscription: Subscription) {
        if ["PAUSED", "CANCELED"].contains(subscription.state) { return }

        for invoice in subscription.invoices {
            if invoice.retries.first == day { retry(invoice) }
        }
        if subscription.state == "UNPAID" && subscription.cancelOn == day {
            cancelSubscription(subscription)
        }
        if subscription.state == "TRIALING" && subscription.trialEnd == day {
            if subscription.cancelEnd {
                cancelSubscription(subscription)
            } else {
                changeState(subscription, to: "ACTIVE")
                subscription.start = day
                subscription.end = day + subscription.plan.length
                issue(subscription, kind: "first",
                      items: openingItems(subscription, start: day))
            }
        }
        if ["ACTIVE", "PAST_DUE", "UNPAID"].contains(subscription.state) &&
           subscription.end == day {
            if subscription.cancelEnd {
                cancelSubscription(subscription)
            } else {
                var items = usageItems(subscription, close: true)
                if let (plan, seats) = subscription.pending {
                    notice(
                        "sub", subscription.number, subscription.plan.name, "seats",
                        subscription.seats, "->", plan.name, "seats", seats
                    )
                    subscription.plan = plan
                    subscription.seats = seats
                    subscription.pending = nil
                }
                subscription.start = day
                subscription.end = day + subscription.plan.length
                items.append(periodItem(subscription.plan, seats: subscription.seats, start: day))
                issue(subscription, kind: "renewal", items: items)
            }
        }
    }

    private func commandPlan(_ a: [String]) throws {
        let name = a[0]
        let amount = a[1]
        let cycle = a[2]
        if plans[name] != nil { throw fail("duplicate plan \(name)") }
        let plan = Plan(name: name, price: cents(amount), cycle: cycle)
        var index = 3
        while index < a.count {
            switch a[index] {
            case "TRIAL":
                plan.trial = Int(a[index + 1])!
                index += 2
            case "SETUP":
                plan.setup = cents(a[index + 1])
                index += 2
            case "PERSEAT":
                plan.perSeat = true
                index += 1
            default:
                plan.mode = a[index]
                index += 1
            }
        }
        plans[name] = plan
        var text = "PLAN \(name) \(cycle) \(amount)"
        if plan.trial != 0 { text += " trial \(plan.trial)" }
        if plan.setup != 0 { text += " setup \(money(plan.setup))" }
        if plan.perSeat { text += " perseat" }
        if let mode = plan.mode { text += " \(mode.lowercased())" }
        emit(text)
    }

    private func commandTier(_ a: [String]) throws {
        let name = a[0]
        let plan = try self.plan(name)
        guard plan.mode != nil else { throw fail("not metered \(name)") }
        let upper = a[1] == "INF" ? nil : Int(a[1])
        if let last = plan.tiers.last {
            if last.upper == nil || (upper != nil && upper! <= last.upper!) {
                throw fail("tier order \(name)")
            }
        }
        plan.tiers.append(Tier(upper: upper, unitPrice: cents(a[2]), flatFee: cents(a[3])))
        emit("TIER", name, plan.tiers.count, "upto", a[1], "unit", a[2], "flat", a[3])
    }

    private func commandTax(_ a: [String]) {
        let rate = Int(a[1])!
        taxRates[a[0]] = rate
        emit("TAX", a[0], percentage(rate))
    }

    private func commandCustomer(_ a: [String]) throws {
        if customers[a[0]] != nil { throw fail("duplicate customer \(a[0])") }
        customers[a[0]] = Customer(name: a[0], region: a[1])
        emit("CUSTOMER", a[0], "region", a[1])
    }

    private func commandCoupon(_ a: [String]) throws {
        let name = a[0]
        let kind = a[1]
        let application = a[3]
        if coupons[name] != nil { throw fail("duplicate coupon \(name)") }
        var applications: Int? = application == "ONCE" ? 1 : nil
        var index = 4
        if application == "REPEATING" {
            applications = Int(a[index])!
            index += 1
        }
        let maximum = index < a.count ? Int(a[index + 1])! : nil
        let value = kind == "PERCENT" ? Int(a[2])! : cents(a[2])
        let coupon = Coupon(
            name: name, kind: kind, value: value,
            applications: applications, maximum: maximum
        )
        coupons[name] = coupon
        let shown = kind == "PERCENT" ? percentage(value) : money(value)
        var text = "COUPON \(name) \(kind.lowercased()) \(shown) \(application.lowercased())"
        if application == "REPEATING" { text += " \(applications!)" }
        if let maximum { text += " max \(maximum)" }
        emit(text)
    }

    private func commandPayMethod(_ a: [String]) throws {
        let customer = try self.customer(a[0])
        customer.method = a[1]
        emit("PAYMETHOD", a[0], a[1])
    }

    private func commandCredit(_ a: [String]) throws {
        let customer = try self.customer(a[0])
        let amount = cents(a[1])
        if amount == 0 { throw fail("invalid amount") }
        balanceChange(customer, by: amount, description: "grant")
        emit("CREDIT", a[0], "amount", a[1], "balance", money(customer.balance))
    }

    private func commandDay(_ a: [String]) throws {
        let target = Int(a[0])!
        if target <= day { throw fail("invalid day \(a[0])") }
        emit("DAY", target)
        for nextDay in day + 1...target {
            day = nextDay
            for subscription in subscriptions { advanceSubscription(subscription) }
        }
    }

    private func commandSubscribe(_ a: [String]) throws {
        let customer = try self.customer(a[0])
        let plan = try self.plan(a[1])
        var seats = 1
        var hasSeats = false
        var couponName: String?
        var index = 2
        while index < a.count {
            if a[index] == "SEATS" {
                seats = Int(a[index + 1])!
                hasSeats = true
            } else {
                couponName = a[index + 1]
            }
            index += 2
        }
        if hasSeats && !plan.perSeat { throw fail("not per-seat \(plan.name)") }
        if seats == 0 { throw fail("invalid seats") }
        let coupon = try couponName.map { try redeemableCoupon($0) }
        let subscription = Subscription(
            number: subscriptions.count + 1, customer: customer,
            plan: plan, seats: seats, coupon: coupon
        )
        coupon?.redemptions += 1
        subscriptions.append(subscription)
        customer.subscriptions.append(subscription)
        var text = "SUBSCRIBE sub \(subscription.number) \(customer.name) \(plan.name) seats \(seats)"
        if let coupon { text += " coupon \(coupon.name)" }
        emit(text)
        if plan.trial != 0 {
            subscription.trialEnd = day + plan.trial
            changeState(subscription, to: "TRIALING")
        } else {
            changeState(subscription, to: "ACTIVE")
            subscription.start = day
            subscription.end = day + plan.length
            issue(subscription, kind: "first", items: openingItems(subscription, start: day))
        }
    }

    private func commandChange(_ a: [String]) throws {
        let subscription = try self.subscription(a[0], allowed: ["ACTIVE", "TRIALING"])
        let newPlan: Plan
        let seats: Int
        if a[1] == "PLAN" {
            newPlan = try self.plan(a[2])
            seats = newPlan.perSeat ? subscription.seats : 1
        } else {
            newPlan = subscription.plan
            if !newPlan.perSeat { throw fail("not per-seat \(newPlan.name)") }
            seats = Int(a[2])!
            if seats == 0 { throw fail("invalid seats") }
        }
        if newPlan === subscription.plan && seats == subscription.seats {
            throw fail("no change \(a[0])")
        }
        let oldPlan = subscription.plan
        let oldSeats = subscription.seats
        let head = "CHANGE sub \(subscription.number) \(oldPlan.name) seats \(oldSeats) -> \(newPlan.name) seats \(seats)"
        subscription.pending = nil
        let upgrade = newPlan.fee(seats) * oldPlan.length >
                      oldPlan.fee(oldSeats) * newPlan.length
        if subscription.state == "TRIALING" {
            subscription.plan = newPlan
            subscription.seats = seats
            emit(head, "now")
        } else if upgrade {
            emit(head, "now")
            let days = subscription.end! - day
            var items = usageItems(subscription, close: true)
            items.append(BillItem(
                description: "unused \(oldPlan.name) seats \(oldSeats) \(days) days",
                amount: -(oldPlan.fee(oldSeats) * days / oldPlan.length)
            ))
            items.append(BillItem(
                description: "remaining \(newPlan.name) seats \(seats) \(days) days",
                amount: newPlan.fee(seats) * days / newPlan.length
            ))
            subscription.plan = newPlan
            subscription.seats = seats
            issue(subscription, kind: "upgrade", items: items)
        } else {
            subscription.pending = (newPlan, seats)
            emit(head, "at", subscription.end!)
        }
    }

    private func commandPause(_ a: [String]) throws {
        let subscription = try self.subscription(a[0], allowed: ["ACTIVE"])
        emit("PAUSE", "sub", subscription.number)
        subscription.pauseStart = day
        changeState(subscription, to: "PAUSED")
    }

    private func commandResume(_ a: [String]) throws {
        let subscription = try self.subscription(a[0], allowed: ["PAUSED"])
        let elapsed = day - subscription.pauseStart!
        subscription.end = subscription.end! + elapsed
        subscription.pauseStart = nil
        emit("RESUME", "sub", subscription.number, "shift", elapsed,
             "period", subscription.period())
        changeState(subscription, to: "ACTIVE")
    }

    private func commandCancel(_ a: [String]) throws {
        let subscription = try self.subscription(a[0])
        if a[1] == "END" {
            if !["ACTIVE", "TRIALING"].contains(subscription.state) {
                throw fail("invalid state \(a[0]) \(subscription.state)")
            }
            if subscription.cancelEnd { throw fail("already canceling \(a[0])") }
            subscription.cancelEnd = true
            let date = subscription.state == "TRIALING" ?
                subscription.trialEnd! : subscription.end!
            emit("CANCEL", "sub", subscription.number, "end", date)
        } else {
            if subscription.state == "CANCELED" {
                throw fail("invalid state \(a[0]) \(subscription.state)")
            }
            var refund = 0
            if ["ACTIVE", "PAUSED"].contains(subscription.state) {
                let first = subscription.state == "ACTIVE" ? day : subscription.pauseStart!
                refund = subscription.fee() * (subscription.end! - first) / subscription.plan.length
            }
            balanceChange(subscription.customer, by: refund,
                          description: "cancel sub \(subscription.number)")
            emit("CANCEL", "sub", subscription.number, "now", "credit", money(refund))
            cancelSubscription(subscription)
        }
    }

    private func commandUsage(_ a: [String]) throws {
        let subscription = try self.subscription(a[0], allowed: ["ACTIVE", "PAST_DUE"])
        guard subscription.plan.mode != nil else {
            throw fail("not metered \(subscription.plan.name)")
        }
        let quantity = Int(a[1])!
        if quantity == 0 { throw fail("invalid units") }
        subscription.usage += quantity
        emit("USAGE", "sub", subscription.number, "units", quantity,
             "total", subscription.usage)
    }

    private func commandApply(_ a: [String]) throws {
        let subscription = try self.subscription(a[0])
        if subscription.state == "CANCELED" {
            throw fail("invalid state \(a[0]) \(subscription.state)")
        }
        let coupon = try redeemableCoupon(a[1])
        coupon.redemptions += 1
        subscription.coupon = coupon
        subscription.remaining = coupon.applications
        emit("APPLY", "sub", subscription.number, "coupon", coupon.name)
    }

    private func commandPay(_ a: [String]) throws {
        let invoice = try self.invoice(a[0])
        if invoice.outstanding == 0 { throw fail("already paid \(a[0])") }
        emit("PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
        invoice.paid += invoice.outstanding
        invoice.outstanding = 0
        paymentComplete(invoice)
    }

    private func commandRefund(_ a: [String]) throws {
        let invoice = try self.invoice(a[0])
        let amount = cents(a[1])
        if amount == 0 { throw fail("invalid amount") }
        let maximum = invoice.total - invoice.refunded
        if amount > maximum {
            throw fail("refund exceeds \(a[0]) \(money(maximum))")
        }
        let applied = min(amount, invoice.outstanding)
        invoice.refunded += amount
        invoice.outstanding -= applied
        balanceChange(invoice.customer, by: amount - applied,
                      description: "refund invoice \(invoice.number)")
        emit(
            "REFUND", "invoice", invoice.number, "amount", a[1], "applied",
            money(applied), "balance", money(invoice.customer.balance)
        )
        if applied != 0 && invoice.outstanding == 0 { paymentComplete(invoice) }
    }

    private func emitItems(_ items: [BillItem]) {
        for item in items { detail(item.description, money(item.amount)) }
    }

    private func emitTotals(_ totals: Totals) {
        detail(
            "subtotal", money(totals.subtotal), "discount", money(totals.discount),
            "tax", money(totals.tax), "total", money(totals.total)
        )
    }

    private func commandInvoice(_ a: [String]) throws {
        let invoice = try self.invoice(a[0])
        emit(
            "INVOICE", invoice.number, "sub", invoice.subscription.number,
            invoice.customer.name, "day", invoice.day, invoice.kind, invoice.state()
        )
        emitItems(invoice.items)
        emitTotals(Totals(
            subtotal: invoice.subtotal, discount: invoice.discount, tax: invoice.tax,
            total: invoice.total, credit: invoice.credit, due: invoice.due
        ))
        detail(
            "credit", money(invoice.credit), "due", money(invoice.due),
            "paid", money(invoice.paid), "refunded", money(invoice.refunded),
            "outstanding", money(invoice.outstanding)
        )
    }

    private func commandSub(_ a: [String]) throws {
        let subscription = try self.subscription(a[0])
        emit(
            "SUB", subscription.number, subscription.customer.name,
            subscription.plan.name, "seats", subscription.seats, subscription.state
        )
        if subscription.state == "TRIALING" {
            detail("trial until", subscription.trialEnd!)
        }
        if ["ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"].contains(subscription.state) {
            detail("period", subscription.period())
        }
        if subscription.state == "PAUSED" {
            detail("paused since", subscription.pauseStart!)
        }
        if let (plan, seats) = subscription.pending {
            detail("pending", plan.name, "seats", seats)
        }
        if subscription.cancelEnd { detail("cancel at end") }
        if let date = subscription.cancelOn { detail("cancel on", date) }
        if subscription.state == "CANCELED" {
            detail("canceled on", subscription.canceledOn!)
        }
        if let coupon = subscription.coupon {
            if subscription.remaining == nil {
                detail("coupon", coupon.name, "forever")
            } else if subscription.remaining! > 0 {
                detail("coupon", coupon.name, "left", subscription.remaining!)
            }
        }
        if subscription.plan.mode != nil && subscription.state != "CANCELED" {
            detail("usage", subscription.usage)
        }
        let open = subscription.invoices.filter { $0.outstanding != 0 }.map { String($0.number) }
        if !open.isEmpty { detail("open", open.joined(separator: " ")) }
    }

    private func commandPreview(_ a: [String]) throws {
        let subscription = try self.subscription(
            a[0], allowed: ["TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"]
        )
        let date = subscription.state == "TRIALING" ?
            subscription.trialEnd! : subscription.end!
        let kind: String
        var items: [BillItem]
        if subscription.cancelEnd {
            kind = "final"
            items = subscription.state == "TRIALING" ? [] : usageItems(subscription)
        } else if subscription.state == "TRIALING" {
            kind = "first"
            items = openingItems(subscription, start: date)
        } else {
            kind = "renewal"
            let (plan, seats) = subscription.pending ?? (subscription.plan, subscription.seats)
            items = usageItems(subscription)
            items.append(periodItem(plan, seats: seats, start: date))
        }
        emit("PREVIEW", "sub", subscription.number, "day", date, kind)
        if items.isEmpty {
            detail("(none)")
            return
        }
        emitItems(items)
        let totals = invoiceTotals(subscription, items: items)
        emitTotals(totals)
        detail("credit", money(totals.credit), "due", money(totals.due))
    }

    private func commandStatement(_ a: [String]) throws {
        let customer = try self.customer(a[0])
        emit(
            "STATEMENT", customer.name, "region", customer.region,
            "tax", percentage(taxRates[customer.region] ?? 0),
            "method", customer.method, "balance", money(customer.balance)
        )
        for subscription in customer.subscriptions {
            detail("sub", subscription.number, subscription.plan.name, subscription.state)
        }
        for invoice in customer.invoices {
            detail(
                "invoice", invoice.number, "day", invoice.day, "sub",
                invoice.subscription.number, invoice.kind, "total", money(invoice.total),
                "outstanding", money(invoice.outstanding)
            )
        }
        detail(
            "outstanding",
            money(customer.invoices.reduce(0) { $0 + $1.outstanding })
        )
    }

    private func commandLedger(_ a: [String]) throws {
        let customer = try self.customer(a[0])
        emit("LEDGER", customer.name, "balance", money(customer.balance))
        for record in customer.log {
            detail(
                "day", record.day, record.description, signedMoney(record.change),
                "balance", money(record.balance)
            )
        }
        if customer.log.isEmpty { detail("(none)") }
    }

    private func commandMRR() {
        var byPlan: [String: (Int, Int)] = [:]
        for subscription in subscriptions {
            guard ["ACTIVE", "PAST_DUE"].contains(subscription.state) else { continue }
            let fee = subscription.fee()
            let monthly: Int
            switch subscription.plan.cycle {
            case "MONTHLY": monthly = fee
            case "YEARLY": monthly = fee / 12
            default: monthly = fee * 30 / 7
            }
            let previous = byPlan[subscription.plan.name] ?? (0, 0)
            byPlan[subscription.plan.name] = (previous.0 + 1, previous.1 + monthly)
        }
        emit("MRR")
        for name in byPlan.keys.sorted() {
            let (count, monthly) = byPlan[name]!
            detail(name, "subs", count, "mrr", money(monthly))
        }
        let count = byPlan.values.reduce(0) { $0 + $1.0 }
        let total = byPlan.values.reduce(0) { $0 + $1.1 }
        detail("total subs", count, "mrr", money(total))
    }

    private func agingParts(_ amounts: [Int]) -> String {
        "0-30 \(money(amounts[0])) 31-60 \(money(amounts[1])) " +
        "61+ \(money(amounts[2])) sum \(money(amounts.reduce(0, +)))"
    }

    private func commandAging() {
        var byCustomer: [String: [Int]] = [:]
        var totals = [0, 0, 0]
        for invoice in invoices where invoice.outstanding != 0 {
            let age = day - invoice.day
            let bucket = age <= 30 ? 0 : (age <= 60 ? 1 : 2)
            var amounts = byCustomer[invoice.customer.name] ?? [0, 0, 0]
            amounts[bucket] += invoice.outstanding
            byCustomer[invoice.customer.name] = amounts
            totals[bucket] += invoice.outstanding
        }
        emit("AGING", "day", day)
        for name in byCustomer.keys.sorted() {
            detail(name, agingParts(byCustomer[name]!))
        }
        detail("total", agingParts(totals))
    }

    private func commandDunning() {
        emit("DUNNING")
        let pending = invoices.filter { !$0.retries.isEmpty }
        for invoice in pending {
            detail(
                "invoice", invoice.number, "sub", invoice.subscription.number,
                invoice.customer.name, "outstanding", money(invoice.outstanding),
                "attempts", invoice.attempts, "next", invoice.retries[0]
            )
        }
        if pending.isEmpty { detail("(none)") }
    }

    private func commandRevenue() {
        emit("REVENUE")
        detail(
            "invoices", invoices.count,
            "subtotal", money(invoices.reduce(0) { $0 + $1.subtotal }),
            "discount", money(invoices.reduce(0) { $0 + $1.discount }),
            "tax", money(invoices.reduce(0) { $0 + $1.tax }),
            "total", money(invoices.reduce(0) { $0 + $1.total })
        )
        detail(
            "credit", money(invoices.reduce(0) { $0 + $1.credit }),
            "paid", money(invoices.reduce(0) { $0 + $1.paid }),
            "refunded", money(invoices.reduce(0) { $0 + $1.refunded }),
            "outstanding", money(invoices.reduce(0) { $0 + $1.outstanding }),
            "balances", money(customers.values.reduce(0) { $0 + $1.balance })
        )
    }

    private func commandEvents(_ a: [String]) throws {
        let selected = try a.isEmpty ? nil : subscription(a[0]).number
        if let selected {
            emit("EVENTS", "sub", selected)
        } else {
            emit("EVENTS")
        }
        let matching = events.filter { selected == nil || $0.number == selected }
        for event in matching {
            detail("day", event.day, "sub", event.number, event.old, "->", event.new)
        }
        if matching.isEmpty { detail("(none)") }
    }

    func execute(_ line: String) {
        let fields = line.split(separator: " ").map(String.init)
        if fields.isEmpty { return }
        let arguments = Array(fields.dropFirst())
        do {
            switch fields[0] {
            case "PLAN": try commandPlan(arguments)
            case "TIER": try commandTier(arguments)
            case "TAX": commandTax(arguments)
            case "CUSTOMER": try commandCustomer(arguments)
            case "COUPON": try commandCoupon(arguments)
            case "PAYMETHOD": try commandPayMethod(arguments)
            case "CREDIT": try commandCredit(arguments)
            case "DAY": try commandDay(arguments)
            case "SUBSCRIBE": try commandSubscribe(arguments)
            case "CHANGE": try commandChange(arguments)
            case "PAUSE": try commandPause(arguments)
            case "RESUME": try commandResume(arguments)
            case "CANCEL": try commandCancel(arguments)
            case "USAGE": try commandUsage(arguments)
            case "APPLY": try commandApply(arguments)
            case "PAY": try commandPay(arguments)
            case "REFUND": try commandRefund(arguments)
            case "INVOICE": try commandInvoice(arguments)
            case "SUB": try commandSub(arguments)
            case "PREVIEW": try commandPreview(arguments)
            case "STATEMENT": try commandStatement(arguments)
            case "LEDGER": try commandLedger(arguments)
            case "MRR": commandMRR()
            case "AGING": commandAging()
            case "DUNNING": commandDunning()
            case "REVENUE": commandRevenue()
            case "EVENTS": try commandEvents(arguments)
            default: break
            }
        } catch BillingError.invalid(let reason) {
            emit("ERROR", reason)
        } catch {
            fatalError("Unexpected error: \(error)")
        }
    }
}

let input = String(
    data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8
)!.split(whereSeparator: \.isNewline)
let count = Int(input[0])!
let billing = BillingService()
for i in 1...count {
    billing.execute(String(input[i]))
}
if !billing.output.isEmpty {
    print(billing.output.joined(separator: "\n"))
}
