import sys


PERIOD_LENGTHS = {"WEEKLY": 7, "MONTHLY": 30, "YEARLY": 360}


class CommandError(Exception):
    pass


def cents(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    sign = "-" if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 100}.{value % 100:02d}"


def signed_money(value):
    return ("+" if value > 0 else "") + money(value)


def percentage(basis_points):
    return money(basis_points) + "%"


class Plan:
    def __init__(self, name, price, cycle):
        self.name = name
        self.price = price
        self.cycle = cycle
        self.length = PERIOD_LENGTHS[cycle]
        self.trial = 0
        self.setup = 0
        self.per_seat = False
        self.mode = None
        self.tiers = []

    def fee(self, seats):
        return self.price * seats if self.per_seat else self.price

    def usage_charge(self, units):
        total = 0
        lower = 0
        for index, (upper, unit_price, flat_fee) in enumerate(self.tiers):
            last = index == len(self.tiers) - 1
            if self.mode == "VOLUME":
                if last or upper is None or units <= upper:
                    return units * unit_price + flat_fee
            else:
                if units <= lower:
                    break
                end = units if last or upper is None else min(units, upper)
                total += (end - lower) * unit_price + flat_fee
                if last or upper is None:
                    break
                lower = upper
        return total


class Customer:
    def __init__(self, name, region):
        self.name = name
        self.region = region
        self.method = "OK"
        self.balance = 0
        self.log = []
        self.subscriptions = []
        self.invoices = []


class Coupon:
    def __init__(self, name, kind, value, applications, maximum):
        self.name = name
        self.kind = kind
        self.value = value
        self.applications = applications
        self.maximum = maximum
        self.redemptions = 0


class Subscription:
    def __init__(self, number, customer, plan, seats, coupon):
        self.number = number
        self.customer = customer
        self.plan = plan
        self.seats = seats
        self.state = "NONE"
        self.start = None
        self.end = None
        self.trial_end = None
        self.pause_start = None
        self.pending = None
        self.cancel_end = False
        self.cancel_on = None
        self.canceled_on = None
        self.coupon = coupon
        self.remaining = None if coupon is None else coupon.applications
        self.usage = 0
        self.invoices = []

    def fee(self):
        return self.plan.fee(self.seats)

    def period(self):
        return f"{self.start}-{self.end}"


class Invoice:
    def __init__(self, number, subscription, day, kind, items, totals):
        self.number = number
        self.subscription = subscription
        self.customer = subscription.customer
        self.day = day
        self.kind = kind
        self.items = items
        self.subtotal, self.discount, self.tax, self.total, self.credit, self.due = totals
        self.paid = 0
        self.refunded = 0
        self.outstanding = self.due
        self.attempts = 0
        self.retries = []

    def state(self):
        return "OPEN" if self.outstanding else "PAID"


class BillingService:
    def __init__(self):
        self.day = 1
        self.plans = {}
        self.tax_rates = {}
        self.customers = {}
        self.coupons = {}
        self.subscriptions = []
        self.invoices = []
        self.events = []
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def notice(self, *parts):
        self.emit("day", self.day, *parts, indent=2)

    def plan(self, name):
        if name not in self.plans:
            raise CommandError(f"unknown plan {name}")
        return self.plans[name]

    def customer(self, name):
        if name not in self.customers:
            raise CommandError(f"unknown customer {name}")
        return self.customers[name]

    def redeemable_coupon(self, name):
        if name not in self.coupons:
            raise CommandError(f"unknown coupon {name}")
        coupon = self.coupons[name]
        if coupon.maximum is not None and coupon.redemptions == coupon.maximum:
            raise CommandError(f"coupon exhausted {name}")
        return coupon

    def subscription(self, text, allowed=None):
        number = int(text)
        if not 1 <= number <= len(self.subscriptions):
            raise CommandError(f"unknown sub {text}")
        subscription = self.subscriptions[number - 1]
        if allowed is not None and subscription.state not in allowed:
            raise CommandError(f"invalid state {text} {subscription.state}")
        return subscription

    def invoice(self, text):
        number = int(text)
        if not 1 <= number <= len(self.invoices):
            raise CommandError(f"unknown invoice {text}")
        return self.invoices[number - 1]

    def balance_change(self, customer, change, description):
        if change:
            customer.balance += change
            customer.log.append((self.day, description, change, customer.balance))

    def change_state(self, subscription, state):
        old = subscription.state
        if old == "PAST_DUE":
            for invoice in subscription.invoices:
                invoice.retries.clear()
        subscription.state = state
        self.notice("sub", subscription.number, old, "->", state)
        self.events.append((self.day, subscription.number, old, state))

    def period_item(self, plan, seats, start):
        description = f"charge {plan.name} seats {seats} {start}-{start + plan.length}"
        return description, plan.fee(seats)

    def opening_items(self, subscription, start):
        plan = subscription.plan
        items = [self.period_item(plan, subscription.seats, start)]
        if plan.setup:
            items.append((f"setup {plan.name}", plan.setup))
        return items

    def usage_items(self, subscription, close=False):
        if subscription.plan.mode is None or subscription.usage == 0:
            return []
        units = subscription.usage
        item = f"usage {subscription.plan.name} {units} units", subscription.plan.usage_charge(units)
        if close:
            subscription.usage = 0
        return [item]

    def coupon_usable(self, subscription, subtotal):
        return subtotal > 0 and subscription.coupon is not None and (subscription.remaining is None or subscription.remaining > 0)

    def invoice_totals(self, subscription, items):
        subtotal = sum(amount for _, amount in items)
        discount = 0
        if self.coupon_usable(subscription, subtotal):
            coupon = subscription.coupon
            discount = subtotal * coupon.value // 10000 if coupon.kind == "PERCENT" else min(subtotal, coupon.value)
        tax = (subtotal - discount) * self.tax_rates.get(subscription.customer.region, 0) // 10000
        total = subtotal - discount + tax
        credit = min(subscription.customer.balance, total)
        return subtotal, discount, tax, total, credit, total - credit

    def issue(self, subscription, kind, items):
        totals = self.invoice_totals(subscription, items)
        invoice = Invoice(len(self.invoices) + 1, subscription, self.day, kind, items, totals)
        if self.coupon_usable(subscription, invoice.subtotal) and subscription.remaining is not None:
            subscription.remaining -= 1
        self.invoices.append(invoice)
        subscription.invoices.append(invoice)
        subscription.customer.invoices.append(invoice)
        self.balance_change(subscription.customer, -invoice.credit, f"applied invoice {invoice.number}")
        if invoice.due == 0:
            result = "PAID"
        elif subscription.state == "UNPAID":
            result = "OPEN"
        else:
            invoice.attempts = 1
            if subscription.customer.method == "OK":
                invoice.paid = invoice.due
                invoice.outstanding = 0
                result = "PAID"
            else:
                result = "FAILED"
        self.notice(
            "invoice", invoice.number, "sub", subscription.number, kind, "total", money(invoice.total),
            "credit", money(invoice.credit), "due", money(invoice.due), result,
        )
        if result == "FAILED":
            if subscription.state == "ACTIVE":
                self.change_state(subscription, "PAST_DUE")
            if subscription.state == "PAST_DUE":
                invoice.retries = [self.day + offset for offset in (3, 5, 7)]

    def payment_complete(self, invoice):
        invoice.retries.clear()
        subscription = invoice.subscription
        if subscription.state in ("PAST_DUE", "UNPAID") and all(i.outstanding == 0 for i in subscription.invoices):
            subscription.cancel_on = None
            self.change_state(subscription, "ACTIVE")

    def cancel_subscription(self, subscription):
        self.change_state(subscription, "CANCELED")
        subscription.canceled_on = self.day
        subscription.pending = None
        subscription.cancel_end = False
        subscription.cancel_on = None
        items = self.usage_items(subscription, close=True)
        if items:
            self.issue(subscription, "final", items)

    def retry(self, invoice):
        invoice.retries.pop(0)
        invoice.attempts += 1
        retry_number = invoice.attempts - 1
        if invoice.customer.method == "OK":
            invoice.paid += invoice.outstanding
            invoice.outstanding = 0
            self.notice("retry", retry_number, "invoice", invoice.number, "PAID")
            self.payment_complete(invoice)
        else:
            self.notice("retry", retry_number, "invoice", invoice.number, "FAILED")
            if not invoice.retries:
                self.change_state(invoice.subscription, "UNPAID")
                invoice.subscription.cancel_on = self.day + 14

    def advance_subscription(self, subscription):
        if subscription.state in ("PAUSED", "CANCELED"):
            return
        for invoice in subscription.invoices:
            if invoice.retries and invoice.retries[0] == self.day:
                self.retry(invoice)
        if subscription.state == "UNPAID" and subscription.cancel_on == self.day:
            self.cancel_subscription(subscription)
        if subscription.state == "TRIALING" and subscription.trial_end == self.day:
            if subscription.cancel_end:
                self.cancel_subscription(subscription)
            else:
                self.change_state(subscription, "ACTIVE")
                subscription.start = self.day
                subscription.end = self.day + subscription.plan.length
                self.issue(subscription, "first", self.opening_items(subscription, self.day))
        if subscription.state in ("ACTIVE", "PAST_DUE", "UNPAID") and subscription.end == self.day:
            if subscription.cancel_end:
                self.cancel_subscription(subscription)
            else:
                items = self.usage_items(subscription, close=True)
                if subscription.pending is not None:
                    plan, seats = subscription.pending
                    self.notice(
                        "sub", subscription.number, subscription.plan.name, "seats", subscription.seats,
                        "->", plan.name, "seats", seats,
                    )
                    subscription.plan = plan
                    subscription.seats = seats
                    subscription.pending = None
                subscription.start = self.day
                subscription.end = self.day + subscription.plan.length
                items.append(self.period_item(subscription.plan, subscription.seats, self.day))
                self.issue(subscription, "renewal", items)

    def cmd_plan(self, name, amount, cycle, *options):
        if name in self.plans:
            raise CommandError(f"duplicate plan {name}")
        plan = Plan(name, cents(amount), cycle)
        index = 0
        while index < len(options):
            option = options[index]
            if option == "TRIAL":
                plan.trial = int(options[index + 1])
                index += 2
            elif option == "SETUP":
                plan.setup = cents(options[index + 1])
                index += 2
            else:
                if option == "PERSEAT":
                    plan.per_seat = True
                else:
                    plan.mode = option
                index += 1
        self.plans[name] = plan
        parts = ["PLAN", name, cycle, amount]
        if plan.trial:
            parts.extend(("trial", plan.trial))
        if plan.setup:
            parts.extend(("setup", money(plan.setup)))
        if plan.per_seat:
            parts.append("perseat")
        if plan.mode is not None:
            parts.append(plan.mode.lower())
        self.emit(*parts)

    def cmd_tier(self, name, limit, unit, flat):
        plan = self.plan(name)
        if plan.mode is None:
            raise CommandError(f"not metered {name}")
        upper = None if limit == "INF" else int(limit)
        if plan.tiers:
            previous = plan.tiers[-1][0]
            if previous is None or (upper is not None and upper <= previous):
                raise CommandError(f"tier order {name}")
        plan.tiers.append((upper, cents(unit), cents(flat)))
        self.emit("TIER", name, len(plan.tiers), "upto", limit, "unit", unit, "flat", flat)

    def cmd_tax(self, region, basis_points):
        self.tax_rates[region] = int(basis_points)
        self.emit("TAX", region, percentage(int(basis_points)))

    def cmd_customer(self, name, region):
        if name in self.customers:
            raise CommandError(f"duplicate customer {name}")
        self.customers[name] = Customer(name, region)
        self.emit("CUSTOMER", name, "region", region)

    def cmd_coupon(self, name, kind, value, application, *options):
        if name in self.coupons:
            raise CommandError(f"duplicate coupon {name}")
        applications = 1 if application == "ONCE" else None
        index = 0
        if application == "REPEATING":
            applications = int(options[0])
            index = 1
        maximum = int(options[index + 1]) if index < len(options) else None
        numeric_value = int(value) if kind == "PERCENT" else cents(value)
        coupon = Coupon(name, kind, numeric_value, applications, maximum)
        self.coupons[name] = coupon
        shown_value = percentage(numeric_value) if kind == "PERCENT" else money(numeric_value)
        parts = ["COUPON", name, kind.lower(), shown_value, application.lower()]
        if application == "REPEATING":
            parts.append(applications)
        if maximum is not None:
            parts.extend(("max", maximum))
        self.emit(*parts)

    def cmd_paymethod(self, name, method):
        customer = self.customer(name)
        customer.method = method
        self.emit("PAYMETHOD", name, method)

    def cmd_credit(self, name, amount):
        customer = self.customer(name)
        value = cents(amount)
        if value == 0:
            raise CommandError("invalid amount")
        self.balance_change(customer, value, "grant")
        self.emit("CREDIT", name, "amount", amount, "balance", money(customer.balance))

    def cmd_day(self, text):
        target = int(text)
        if target <= self.day:
            raise CommandError(f"invalid day {text}")
        self.emit("DAY", target)
        for day in range(self.day + 1, target + 1):
            self.day = day
            for subscription in self.subscriptions:
                self.advance_subscription(subscription)

    def cmd_subscribe(self, name, plan_name, *options):
        customer = self.customer(name)
        plan = self.plan(plan_name)
        seats = 1
        has_seats = False
        coupon_name = None
        for index in range(0, len(options), 2):
            if options[index] == "SEATS":
                seats = int(options[index + 1])
                has_seats = True
            else:
                coupon_name = options[index + 1]
        if has_seats and not plan.per_seat:
            raise CommandError(f"not per-seat {plan_name}")
        if seats == 0:
            raise CommandError("invalid seats")
        coupon = None if coupon_name is None else self.redeemable_coupon(coupon_name)
        subscription = Subscription(len(self.subscriptions) + 1, customer, plan, seats, coupon)
        if coupon is not None:
            coupon.redemptions += 1
        self.subscriptions.append(subscription)
        customer.subscriptions.append(subscription)
        parts = ["SUBSCRIBE", "sub", subscription.number, name, plan_name, "seats", seats]
        if coupon is not None:
            parts.extend(("coupon", coupon.name))
        self.emit(*parts)
        if plan.trial:
            subscription.trial_end = self.day + plan.trial
            self.change_state(subscription, "TRIALING")
        else:
            self.change_state(subscription, "ACTIVE")
            subscription.start = self.day
            subscription.end = self.day + plan.length
            self.issue(subscription, "first", self.opening_items(subscription, self.day))

    def cmd_change(self, text, kind, value):
        subscription = self.subscription(text, ("ACTIVE", "TRIALING"))
        if kind == "PLAN":
            plan = self.plan(value)
            seats = subscription.seats if plan.per_seat else 1
        else:
            plan = subscription.plan
            if not plan.per_seat:
                raise CommandError(f"not per-seat {plan.name}")
            seats = int(value)
            if seats == 0:
                raise CommandError("invalid seats")
        if plan is subscription.plan and seats == subscription.seats:
            raise CommandError(f"no change {text}")
        old_plan, old_seats = subscription.plan, subscription.seats
        head = ["CHANGE", "sub", subscription.number, old_plan.name, "seats", old_seats, "->", plan.name, "seats", seats]
        subscription.pending = None
        upgrade = plan.fee(seats) * old_plan.length > old_plan.fee(old_seats) * plan.length
        if subscription.state == "TRIALING":
            subscription.plan, subscription.seats = plan, seats
            self.emit(*head, "now")
        elif upgrade:
            self.emit(*head, "now")
            days = subscription.end - self.day
            items = self.usage_items(subscription, close=True)
            items.append((f"unused {old_plan.name} seats {old_seats} {days} days", -(old_plan.fee(old_seats) * days // old_plan.length)))
            items.append((f"remaining {plan.name} seats {seats} {days} days", plan.fee(seats) * days // plan.length))
            subscription.plan, subscription.seats = plan, seats
            self.issue(subscription, "upgrade", items)
        else:
            subscription.pending = plan, seats
            self.emit(*head, "at", subscription.end)

    def cmd_pause(self, text):
        subscription = self.subscription(text, ("ACTIVE",))
        self.emit("PAUSE", "sub", subscription.number)
        subscription.pause_start = self.day
        self.change_state(subscription, "PAUSED")

    def cmd_resume(self, text):
        subscription = self.subscription(text, ("PAUSED",))
        elapsed = self.day - subscription.pause_start
        subscription.end += elapsed
        subscription.pause_start = None
        self.emit("RESUME", "sub", subscription.number, "shift", elapsed, "period", subscription.period())
        self.change_state(subscription, "ACTIVE")

    def cmd_cancel(self, text, when):
        subscription = self.subscription(text)
        if when == "END":
            if subscription.state not in ("ACTIVE", "TRIALING"):
                raise CommandError(f"invalid state {text} {subscription.state}")
            if subscription.cancel_end:
                raise CommandError(f"already canceling {text}")
            subscription.cancel_end = True
            day = subscription.trial_end if subscription.state == "TRIALING" else subscription.end
            self.emit("CANCEL", "sub", subscription.number, "end", day)
        else:
            if subscription.state == "CANCELED":
                raise CommandError(f"invalid state {text} {subscription.state}")
            refund = 0
            if subscription.state in ("ACTIVE", "PAUSED"):
                start = self.day if subscription.state == "ACTIVE" else subscription.pause_start
                refund = subscription.fee() * (subscription.end - start) // subscription.plan.length
            self.balance_change(subscription.customer, refund, f"cancel sub {subscription.number}")
            self.emit("CANCEL", "sub", subscription.number, "now", "credit", money(refund))
            self.cancel_subscription(subscription)

    def cmd_usage(self, text, units):
        subscription = self.subscription(text, ("ACTIVE", "PAST_DUE"))
        if subscription.plan.mode is None:
            raise CommandError(f"not metered {subscription.plan.name}")
        quantity = int(units)
        if quantity == 0:
            raise CommandError("invalid units")
        subscription.usage += quantity
        self.emit("USAGE", "sub", subscription.number, "units", quantity, "total", subscription.usage)

    def cmd_apply(self, text, name):
        subscription = self.subscription(text)
        if subscription.state == "CANCELED":
            raise CommandError(f"invalid state {text} {subscription.state}")
        coupon = self.redeemable_coupon(name)
        coupon.redemptions += 1
        subscription.coupon = coupon
        subscription.remaining = coupon.applications
        self.emit("APPLY", "sub", subscription.number, "coupon", name)

    def cmd_pay(self, text):
        invoice = self.invoice(text)
        if invoice.outstanding == 0:
            raise CommandError(f"already paid {text}")
        self.emit("PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
        invoice.paid += invoice.outstanding
        invoice.outstanding = 0
        self.payment_complete(invoice)

    def cmd_refund(self, text, amount):
        invoice = self.invoice(text)
        value = cents(amount)
        if value == 0:
            raise CommandError("invalid amount")
        maximum = invoice.total - invoice.refunded
        if value > maximum:
            raise CommandError(f"refund exceeds {text} {money(maximum)}")
        applied = min(value, invoice.outstanding)
        invoice.refunded += value
        invoice.outstanding -= applied
        self.balance_change(invoice.customer, value - applied, f"refund invoice {invoice.number}")
        self.emit(
            "REFUND", "invoice", invoice.number, "amount", amount,
            "applied", money(applied), "balance", money(invoice.customer.balance),
        )
        if applied and invoice.outstanding == 0:
            self.payment_complete(invoice)

    def emit_items(self, items):
        for description, amount in items:
            self.emit(description, money(amount), indent=2)

    def emit_totals(self, totals):
        subtotal, discount, tax, total = totals[:4]
        self.emit("subtotal", money(subtotal), "discount", money(discount), "tax", money(tax), "total", money(total), indent=2)

    def cmd_invoice(self, text):
        invoice = self.invoice(text)
        self.emit(
            "INVOICE", invoice.number, "sub", invoice.subscription.number,
            invoice.customer.name, "day", invoice.day, invoice.kind, invoice.state(),
        )
        self.emit_items(invoice.items)
        self.emit_totals((invoice.subtotal, invoice.discount, invoice.tax, invoice.total))
        self.emit(
            "credit", money(invoice.credit), "due", money(invoice.due), "paid", money(invoice.paid),
            "refunded", money(invoice.refunded), "outstanding", money(invoice.outstanding), indent=2,
        )

    def cmd_sub(self, text):
        subscription = self.subscription(text)
        self.emit(
            "SUB", subscription.number, subscription.customer.name, subscription.plan.name,
            "seats", subscription.seats, subscription.state,
        )
        if subscription.state == "TRIALING":
            self.emit("trial until", subscription.trial_end, indent=2)
        if subscription.state in ("ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"):
            self.emit("period", subscription.period(), indent=2)
        if subscription.state == "PAUSED":
            self.emit("paused since", subscription.pause_start, indent=2)
        if subscription.pending is not None:
            plan, seats = subscription.pending
            self.emit("pending", plan.name, "seats", seats, indent=2)
        if subscription.cancel_end:
            self.emit("cancel at end", indent=2)
        if subscription.cancel_on is not None:
            self.emit("cancel on", subscription.cancel_on, indent=2)
        if subscription.state == "CANCELED":
            self.emit("canceled on", subscription.canceled_on, indent=2)
        if subscription.coupon is not None:
            if subscription.remaining is None:
                self.emit("coupon", subscription.coupon.name, "forever", indent=2)
            elif subscription.remaining > 0:
                self.emit("coupon", subscription.coupon.name, "left", subscription.remaining, indent=2)
        if subscription.plan.mode is not None and subscription.state != "CANCELED":
            self.emit("usage", subscription.usage, indent=2)
        open_invoices = [invoice.number for invoice in subscription.invoices if invoice.outstanding]
        if open_invoices:
            self.emit("open", *open_invoices, indent=2)

    def cmd_preview(self, text):
        subscription = self.subscription(text, ("TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"))
        day = subscription.trial_end if subscription.state == "TRIALING" else subscription.end
        if subscription.cancel_end:
            kind = "final"
            items = [] if subscription.state == "TRIALING" else self.usage_items(subscription)
        elif subscription.state == "TRIALING":
            kind = "first"
            items = self.opening_items(subscription, day)
        else:
            kind = "renewal"
            plan, seats = subscription.pending if subscription.pending is not None else (subscription.plan, subscription.seats)
            items = self.usage_items(subscription)
            items.append(self.period_item(plan, seats, day))
        self.emit("PREVIEW", "sub", subscription.number, "day", day, kind)
        if not items:
            self.emit("(none)", indent=2)
            return
        self.emit_items(items)
        totals = self.invoice_totals(subscription, items)
        self.emit_totals(totals)
        self.emit("credit", money(totals[4]), "due", money(totals[5]), indent=2)

    def cmd_statement(self, name):
        customer = self.customer(name)
        self.emit(
            "STATEMENT", name, "region", customer.region, "tax", percentage(self.tax_rates.get(customer.region, 0)),
            "method", customer.method, "balance", money(customer.balance),
        )
        for subscription in customer.subscriptions:
            self.emit("sub", subscription.number, subscription.plan.name, subscription.state, indent=2)
        for invoice in customer.invoices:
            self.emit(
                "invoice", invoice.number, "day", invoice.day, "sub", invoice.subscription.number, invoice.kind,
                "total", money(invoice.total), "outstanding", money(invoice.outstanding), indent=2,
            )
        self.emit("outstanding", money(sum(invoice.outstanding for invoice in customer.invoices)), indent=2)

    def cmd_ledger(self, name):
        customer = self.customer(name)
        self.emit("LEDGER", name, "balance", money(customer.balance))
        for day, description, change, balance in customer.log:
            self.emit("day", day, description, signed_money(change), "balance", money(balance), indent=2)
        if not customer.log:
            self.emit("(none)", indent=2)

    def cmd_mrr(self):
        by_plan = {}
        for subscription in self.subscriptions:
            if subscription.state not in ("ACTIVE", "PAST_DUE"):
                continue
            fee = subscription.fee()
            cycle = subscription.plan.cycle
            monthly = fee if cycle == "MONTHLY" else fee // 12 if cycle == "YEARLY" else fee * 30 // 7
            row = by_plan.setdefault(subscription.plan.name, [0, 0])
            row[0] += 1
            row[1] += monthly
        self.emit("MRR")
        for name in sorted(by_plan):
            count, monthly = by_plan[name]
            self.emit(name, "subs", count, "mrr", money(monthly), indent=2)
        self.emit(
            "total subs", sum(row[0] for row in by_plan.values()),
            "mrr", money(sum(row[1] for row in by_plan.values())), indent=2,
        )

    def aging_parts(self, amounts):
        return "0-30", money(amounts[0]), "31-60", money(amounts[1]), "61+", money(amounts[2]), "sum", money(sum(amounts))

    def cmd_aging(self):
        by_customer = {}
        totals = [0, 0, 0]
        for invoice in self.invoices:
            if invoice.outstanding == 0:
                continue
            age = self.day - invoice.day
            bucket = 0 if age <= 30 else 1 if age <= 60 else 2
            amounts = by_customer.setdefault(invoice.customer.name, [0, 0, 0])
            amounts[bucket] += invoice.outstanding
            totals[bucket] += invoice.outstanding
        self.emit("AGING", "day", self.day)
        for name in sorted(by_customer):
            self.emit(name, *self.aging_parts(by_customer[name]), indent=2)
        self.emit("total", *self.aging_parts(totals), indent=2)

    def cmd_dunning(self):
        self.emit("DUNNING")
        pending = [invoice for invoice in self.invoices if invoice.retries]
        for invoice in pending:
            self.emit(
                "invoice", invoice.number, "sub", invoice.subscription.number, invoice.customer.name,
                "outstanding", money(invoice.outstanding), "attempts", invoice.attempts, "next", invoice.retries[0], indent=2,
            )
        if not pending:
            self.emit("(none)", indent=2)

    def cmd_revenue(self):
        self.emit("REVENUE")
        self.emit(
            "invoices", len(self.invoices), "subtotal", money(sum(i.subtotal for i in self.invoices)),
            "discount", money(sum(i.discount for i in self.invoices)), "tax", money(sum(i.tax for i in self.invoices)),
            "total", money(sum(i.total for i in self.invoices)), indent=2,
        )
        self.emit(
            "credit", money(sum(i.credit for i in self.invoices)), "paid", money(sum(i.paid for i in self.invoices)),
            "refunded", money(sum(i.refunded for i in self.invoices)), "outstanding", money(sum(i.outstanding for i in self.invoices)),
            "balances", money(sum(c.balance for c in self.customers.values())), indent=2,
        )

    def cmd_events(self, *arguments):
        selected = None if not arguments else self.subscription(arguments[0]).number
        if selected is None:
            self.emit("EVENTS")
        else:
            self.emit("EVENTS", "sub", selected)
        matching = [event for event in self.events if selected is None or event[1] == selected]
        for day, number, old, new in matching:
            self.emit("day", day, "sub", number, old, "->", new, indent=2)
        if not matching:
            self.emit("(none)", indent=2)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            getattr(self, "cmd_" + command.lower())(*arguments)
        except CommandError as error:
            self.emit("ERROR", str(error))


def main():
    count = int(sys.stdin.readline())
    service = BillingService()
    for _ in range(count):
        service.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(service.output) + "\n")


if __name__ == "__main__":
    main()
