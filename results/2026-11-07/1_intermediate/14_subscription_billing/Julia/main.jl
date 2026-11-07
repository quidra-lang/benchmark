using Printf

struct BillingError <: Exception
    message::String
end
Base.showerror(io::IO, error::BillingError) = print(io, error.message)
fail(message::String) = throw(BillingError(message))

const PERIOD_LENGTHS = Dict("WEEKLY" => 7, "MONTHLY" => 30, "YEARLY" => 360)
const ITEMS = Vector{Tuple{String,Int}}

cents(text::String) = let parts = split(text, '.')
    parse(Int, parts[1]) * 100 + parse(Int, parts[2])
end

function money(value::Int)
    absolute = abs(value)
    (value < 0 ? "-" : "") * @sprintf("%d.%02d", div(absolute, 100), mod(absolute, 100))
end

signed_money(value::Int) = (value > 0 ? "+" : "") * money(value)
percentage(value::Int) = money(value) * "%"

mutable struct Plan
    name::String
    price::Int
    cycle::String
    length::Int
    trial::Int
    setup::Int
    per_seat::Bool
    mode::Union{Nothing,String}
    tiers::Vector{Tuple{Union{Nothing,Int},Int,Int}}
end

function Plan(name::String, price::Int, cycle::String)
    Plan(name, price, cycle, PERIOD_LENGTHS[cycle], 0, 0, false, nothing,
         Tuple{Union{Nothing,Int},Int,Int}[])
end

fee(plan::Plan, seats::Int) = plan.price * (plan.per_seat ? seats : 1)

function usage_charge(plan::Plan, units::Int)
    total, lower = 0, 0
    for (index, (upper, unit_price, flat)) in enumerate(plan.tiers)
        last = index == length(plan.tiers)
        if plan.mode == "VOLUME"
            if last || upper === nothing || units <= upper
                return units * unit_price + flat
            end
        else
            units <= lower && break
            finish = last || upper === nothing ? units : min(units, upper)
            total += (finish - lower) * unit_price + flat
            if last || upper === nothing
                break
            end
            lower = upper
        end
    end
    total
end

mutable struct Customer
    name::String
    region::String
    method::String
    balance::Int
    log::Vector{Tuple{Int,String,Int,Int}}
    subscriptions::Vector{Int}
    invoices::Vector{Int}
end

Customer(name::String, region::String) =
    Customer(name, region, "OK", 0, Tuple{Int,String,Int,Int}[], Int[], Int[])

mutable struct Coupon
    name::String
    kind::String
    value::Int
    applications::Union{Nothing,Int}
    maximum::Union{Nothing,Int}
    redemptions::Int
end

mutable struct Subscription
    number::Int
    customer::String
    plan::String
    seats::Int
    state::String
    start::Int
    finish::Int
    trial_end::Int
    pause_start::Int
    pending::Union{Nothing,Tuple{String,Int}}
    cancel_end::Bool
    cancel_on::Int
    canceled_on::Int
    coupon::Union{Nothing,String}
    remaining::Union{Nothing,Int}
    usage::Int
    invoices::Vector{Int}
end

function Subscription(number::Int, customer::String, plan::String,
                      seats::Int, coupon::Union{Nothing,String},
                      remaining::Union{Nothing,Int})
    Subscription(number, customer, plan, seats, "NONE", 0, 0, 0, 0, nothing,
                 false, 0, 0, coupon, remaining, 0, Int[])
end

period(subscription::Subscription) = "$(subscription.start)-$(subscription.finish)"

mutable struct Invoice
    number::Int
    subscription::Int
    customer::String
    day::Int
    kind::String
    items::ITEMS
    subtotal::Int
    discount::Int
    tax::Int
    total::Int
    credit::Int
    due::Int
    paid::Int
    refunded::Int
    outstanding::Int
    attempts::Int
    retries::Vector{Int}
end

invoice_state(invoice::Invoice) = invoice.outstanding == 0 ? "PAID" : "OPEN"

mutable struct Billing
    day::Int
    plans::Dict{String,Plan}
    taxes::Dict{String,Int}
    customers::Dict{String,Customer}
    coupons::Dict{String,Coupon}
    subscriptions::Vector{Subscription}
    invoices::Vector{Invoice}
    events::Vector{Tuple{Int,Int,String,String}}
    output::Vector{String}
end

Billing() = Billing(1, Dict{String,Plan}(), Dict{String,Int}(),
                    Dict{String,Customer}(), Dict{String,Coupon}(),
                    Subscription[], Invoice[], Tuple{Int,Int,String,String}[], String[])

emit!(billing::Billing, parts...) = push!(billing.output, join(string.(parts), " "))
indented!(billing::Billing, parts...) =
    push!(billing.output, "  " * join(string.(parts), " "))
notice!(billing::Billing, parts...) = indented!(billing, "day", billing.day, parts...)

function require_plan(billing::Billing, name::String)
    haskey(billing.plans, name) || fail("unknown plan " * name)
    billing.plans[name]
end

function require_customer(billing::Billing, name::String)
    haskey(billing.customers, name) || fail("unknown customer " * name)
    billing.customers[name]
end

function redeemable_coupon(billing::Billing, name::String)
    haskey(billing.coupons, name) || fail("unknown coupon " * name)
    coupon = billing.coupons[name]
    if coupon.maximum !== nothing && coupon.redemptions == coupon.maximum
        fail("coupon exhausted " * name)
    end
    coupon
end

function require_sub(billing::Billing, text::String, allowed::Vararg{String})
    id = parse(Int, text)
    1 <= id <= length(billing.subscriptions) || fail("unknown sub " * text)
    sub = billing.subscriptions[id]
    if !isempty(allowed) && !(sub.state in allowed)
        fail("invalid state $text $(sub.state)")
    end
    sub
end

function require_invoice(billing::Billing, text::String)
    id = parse(Int, text)
    1 <= id <= length(billing.invoices) || fail("unknown invoice " * text)
    billing.invoices[id]
end

function balance_change!(billing::Billing, customer::Customer, change::Int, description::String)
    change == 0 && return
    customer.balance += change
    push!(customer.log, (billing.day, description, change, customer.balance))
end

function change_state!(billing::Billing, sub::Subscription, state::String)
    old = sub.state
    if old == "PAST_DUE"
        for id in sub.invoices
            empty!(billing.invoices[id].retries)
        end
    end
    sub.state = state
    notice!(billing, "sub", sub.number, old, "->", state)
    push!(billing.events, (billing.day, sub.number, old, state))
end

function period_item(plan::Plan, seats::Int, start::Int)
    ("charge $(plan.name) seats $seats $start-$(start + plan.length)", fee(plan, seats))
end

function opening_items(billing::Billing, sub::Subscription, start::Int)
    plan = billing.plans[sub.plan]
    items = ITEMS([period_item(plan, sub.seats, start)])
    if plan.setup > 0
        push!(items, ("setup " * plan.name, plan.setup))
    end
    items
end

function usage_items!(billing::Billing, sub::Subscription; close::Bool=false)
    plan = billing.plans[sub.plan]
    if plan.mode === nothing || sub.usage == 0
        return ITEMS()
    end
    units = sub.usage
    items = ITEMS([("usage $(plan.name) $units units", usage_charge(plan, units))])
    close && (sub.usage = 0)
    items
end

coupon_usable(sub::Subscription, subtotal::Int) =
    subtotal > 0 && sub.coupon !== nothing &&
    (sub.remaining === nothing || sub.remaining > 0)

function invoice_totals(billing::Billing, sub::Subscription, items::ITEMS)
    subtotal = sum(amount for (_, amount) in items; init=0)
    discount = 0
    if coupon_usable(sub, subtotal)
        coupon = billing.coupons[sub.coupon]
        discount = coupon.kind == "PERCENT" ?
                   div(subtotal * coupon.value, 10000) : min(subtotal, coupon.value)
    end
    customer = billing.customers[sub.customer]
    tax = div((subtotal - discount) * get(billing.taxes, customer.region, 0), 10000)
    total = subtotal - discount + tax
    credit = min(customer.balance, total)
    (subtotal, discount, tax, total, credit, total - credit)
end

function issue!(billing::Billing, sub::Subscription, kind::String, items::ITEMS)
    subtotal, discount, tax, total, credit, due = invoice_totals(billing, sub, items)
    number = length(billing.invoices) + 1
    invoice = Invoice(number, sub.number, sub.customer, billing.day, kind, items,
                      subtotal, discount, tax, total, credit, due,
                      0, 0, due, 0, Int[])
    if coupon_usable(sub, subtotal) && sub.remaining !== nothing
        sub.remaining -= 1
    end
    push!(billing.invoices, invoice)
    push!(sub.invoices, number)
    customer = billing.customers[sub.customer]
    push!(customer.invoices, number)
    balance_change!(billing, customer, -credit, "applied invoice $number")
    result = "PAID"
    if due == 0
        result = "PAID"
    elseif sub.state == "UNPAID"
        result = "OPEN"
    else
        invoice.attempts = 1
        if customer.method == "OK"
            invoice.paid = due
            invoice.outstanding = 0
            result = "PAID"
        else
            result = "FAILED"
        end
    end
    notice!(billing, "invoice", number, "sub", sub.number, kind, "total", money(total),
            "credit", money(credit), "due", money(due), result)
    if result == "FAILED"
        if sub.state == "ACTIVE"
            change_state!(billing, sub, "PAST_DUE")
        end
        if sub.state == "PAST_DUE"
            append!(invoice.retries, (billing.day + 3, billing.day + 5, billing.day + 7))
        end
    end
end

function payment_complete!(billing::Billing, invoice::Invoice)
    empty!(invoice.retries)
    sub = billing.subscriptions[invoice.subscription]
    if sub.state in ("PAST_DUE", "UNPAID") &&
       all(billing.invoices[id].outstanding == 0 for id in sub.invoices)
        sub.cancel_on = 0
        change_state!(billing, sub, "ACTIVE")
    end
end

function cancel_subscription!(billing::Billing, sub::Subscription)
    change_state!(billing, sub, "CANCELED")
    sub.canceled_on = billing.day
    sub.pending = nothing
    sub.cancel_end = false
    sub.cancel_on = 0
    items = usage_items!(billing, sub; close=true)
    !isempty(items) && issue!(billing, sub, "final", items)
end

function retry!(billing::Billing, invoice::Invoice)
    popfirst!(invoice.retries)
    invoice.attempts += 1
    attempt = invoice.attempts - 1
    customer = billing.customers[invoice.customer]
    if customer.method == "OK"
        invoice.paid += invoice.outstanding
        invoice.outstanding = 0
        notice!(billing, "retry", attempt, "invoice", invoice.number, "PAID")
        payment_complete!(billing, invoice)
    else
        notice!(billing, "retry", attempt, "invoice", invoice.number, "FAILED")
        if isempty(invoice.retries)
            sub = billing.subscriptions[invoice.subscription]
            change_state!(billing, sub, "UNPAID")
            sub.cancel_on = billing.day + 14
        end
    end
end

function advance_subscription!(billing::Billing, sub::Subscription)
    sub.state in ("PAUSED", "CANCELED") && return
    for id in sub.invoices
        invoice = billing.invoices[id]
        if !isempty(invoice.retries) && first(invoice.retries) == billing.day
            retry!(billing, invoice)
        end
    end
    if sub.state == "UNPAID" && sub.cancel_on == billing.day
        cancel_subscription!(billing, sub)
    end
    if sub.state == "TRIALING" && sub.trial_end == billing.day
        if sub.cancel_end
            cancel_subscription!(billing, sub)
        else
            change_state!(billing, sub, "ACTIVE")
            sub.start = billing.day
            sub.finish = billing.day + billing.plans[sub.plan].length
            issue!(billing, sub, "first", opening_items(billing, sub, billing.day))
        end
    end
    if sub.state in ("ACTIVE", "PAST_DUE", "UNPAID") && sub.finish == billing.day
        if sub.cancel_end
            cancel_subscription!(billing, sub)
        else
            items = usage_items!(billing, sub; close=true)
            if sub.pending !== nothing
                plan, seats = sub.pending
                notice!(billing, "sub", sub.number, sub.plan, "seats", sub.seats,
                        "->", plan, "seats", seats)
                sub.plan, sub.seats = plan, seats
                sub.pending = nothing
            end
            sub.start = billing.day
            sub.finish = billing.day + billing.plans[sub.plan].length
            push!(items, period_item(billing.plans[sub.plan], sub.seats, billing.day))
            issue!(billing, sub, "renewal", items)
        end
    end
end

function cmd_plan!(billing::Billing, a::Vector{String})
    name, amount, cycle = a[1:3]
    haskey(billing.plans, name) && fail("duplicate plan " * name)
    plan = Plan(name, cents(amount), cycle)
    i = 4
    while i <= length(a)
        option = a[i]
        if option == "TRIAL"
            plan.trial = parse(Int, a[i+1])
            i += 2
        elseif option == "SETUP"
            plan.setup = cents(a[i+1])
            i += 2
        else
            if option == "PERSEAT"
                plan.per_seat = true
            else
                plan.mode = option
            end
            i += 1
        end
    end
    billing.plans[name] = plan
    parts = Any["PLAN", name, cycle, amount]
    plan.trial > 0 && append!(parts, ("trial", plan.trial))
    plan.setup > 0 && append!(parts, ("setup", money(plan.setup)))
    plan.per_seat && push!(parts, "perseat")
    plan.mode !== nothing && push!(parts, lowercase(plan.mode))
    emit!(billing, parts...)
end

function cmd_tier!(billing::Billing, a::Vector{String})
    name, limit, unit, flat = a
    plan = require_plan(billing, name)
    plan.mode === nothing && fail("not metered " * name)
    upper = limit == "INF" ? nothing : parse(Int, limit)
    if !isempty(plan.tiers)
        previous = last(plan.tiers)[1]
        if previous === nothing || (upper !== nothing && upper <= previous)
            fail("tier order " * name)
        end
    end
    push!(plan.tiers, (upper, cents(unit), cents(flat)))
    emit!(billing, "TIER", name, length(plan.tiers), "upto", limit, "unit", unit, "flat", flat)
end

function cmd_tax!(billing::Billing, a::Vector{String})
    region, text = a
    bp = parse(Int, text)
    billing.taxes[region] = bp
    emit!(billing, "TAX", region, percentage(bp))
end

function cmd_customer!(billing::Billing, a::Vector{String})
    name, region = a
    haskey(billing.customers, name) && fail("duplicate customer " * name)
    billing.customers[name] = Customer(name, region)
    emit!(billing, "CUSTOMER", name, "region", region)
end

function cmd_coupon!(billing::Billing, a::Vector{String})
    name, kind, value, application = a[1:4]
    haskey(billing.coupons, name) && fail("duplicate coupon " * name)
    applications = application == "ONCE" ? 1 : nothing
    index = 5
    if application == "REPEATING"
        applications = parse(Int, a[5])
        index = 6
    end
    maximum = index <= length(a) ? parse(Int, a[index+1]) : nothing
    numeric = kind == "PERCENT" ? parse(Int, value) : cents(value)
    coupon = Coupon(name, kind, numeric, applications, maximum, 0)
    billing.coupons[name] = coupon
    shown = kind == "PERCENT" ? percentage(numeric) : money(numeric)
    parts = Any["COUPON", name, lowercase(kind), shown, lowercase(application)]
    application == "REPEATING" && push!(parts, applications)
    maximum !== nothing && append!(parts, ("max", maximum))
    emit!(billing, parts...)
end

function cmd_paymethod!(billing::Billing, a::Vector{String})
    customer = require_customer(billing, a[1])
    customer.method = a[2]
    emit!(billing, "PAYMETHOD", a[1], a[2])
end

function cmd_credit!(billing::Billing, a::Vector{String})
    customer = require_customer(billing, a[1])
    value = cents(a[2])
    value == 0 && fail("invalid amount")
    balance_change!(billing, customer, value, "grant")
    emit!(billing, "CREDIT", a[1], "amount", a[2], "balance", money(customer.balance))
end

function cmd_day!(billing::Billing, a::Vector{String})
    target = parse(Int, a[1])
    target <= billing.day && fail("invalid day " * a[1])
    emit!(billing, "DAY", target)
    for current in (billing.day+1):target
        billing.day = current
        for sub in billing.subscriptions
            advance_subscription!(billing, sub)
        end
    end
end

function cmd_subscribe!(billing::Billing, a::Vector{String})
    name, plan_name = a[1:2]
    customer = require_customer(billing, name)
    plan = require_plan(billing, plan_name)
    seats, has_seats = 1, false
    coupon_name = nothing
    for i in 3:2:length(a)
        if a[i] == "SEATS"
            seats = parse(Int, a[i+1])
            has_seats = true
        else
            coupon_name = a[i+1]
        end
    end
    has_seats && !plan.per_seat && fail("not per-seat " * plan_name)
    seats == 0 && fail("invalid seats")
    coupon = coupon_name === nothing ? nothing : redeemable_coupon(billing, coupon_name)
    remaining = coupon === nothing ? nothing : coupon.applications
    sub = Subscription(length(billing.subscriptions)+1, name, plan_name, seats,
                       coupon_name, remaining)
    coupon !== nothing && (coupon.redemptions += 1)
    push!(billing.subscriptions, sub)
    push!(customer.subscriptions, sub.number)
    parts = Any["SUBSCRIBE", "sub", sub.number, name, plan_name, "seats", seats]
    coupon !== nothing && append!(parts, ("coupon", coupon.name))
    emit!(billing, parts...)
    if plan.trial > 0
        sub.trial_end = billing.day + plan.trial
        change_state!(billing, sub, "TRIALING")
    else
        change_state!(billing, sub, "ACTIVE")
        sub.start = billing.day
        sub.finish = billing.day + plan.length
        issue!(billing, sub, "first", opening_items(billing, sub, billing.day))
    end
end

function cmd_change!(billing::Billing, a::Vector{String})
    text, kind, value = a
    sub = require_sub(billing, text, "ACTIVE", "TRIALING")
    old_plan, old_seats = billing.plans[sub.plan], sub.seats
    plan, seats = old_plan, old_seats
    if kind == "PLAN"
        plan = require_plan(billing, value)
        seats = plan.per_seat ? old_seats : 1
    else
        old_plan.per_seat || fail("not per-seat " * old_plan.name)
        seats = parse(Int, value)
        seats == 0 && fail("invalid seats")
    end
    plan === old_plan && seats == old_seats && fail("no change " * text)
    head = Any["CHANGE", "sub", sub.number, old_plan.name, "seats", old_seats,
               "->", plan.name, "seats", seats]
    sub.pending = nothing
    upgrade = fee(plan, seats) * old_plan.length > fee(old_plan, old_seats) * plan.length
    if sub.state == "TRIALING"
        sub.plan, sub.seats = plan.name, seats
        emit!(billing, head..., "now")
    elseif upgrade
        emit!(billing, head..., "now")
        days = sub.finish - billing.day
        items = usage_items!(billing, sub; close=true)
        push!(items, ("unused $(old_plan.name) seats $old_seats $days days",
                      -div(fee(old_plan, old_seats)*days, old_plan.length)))
        push!(items, ("remaining $(plan.name) seats $seats $days days",
                      div(fee(plan, seats)*days, plan.length)))
        sub.plan, sub.seats = plan.name, seats
        issue!(billing, sub, "upgrade", items)
    else
        sub.pending = (plan.name, seats)
        emit!(billing, head..., "at", sub.finish)
    end
end

function cmd_pause!(billing::Billing, a::Vector{String})
    sub = require_sub(billing, a[1], "ACTIVE")
    emit!(billing, "PAUSE", "sub", sub.number)
    sub.pause_start = billing.day
    change_state!(billing, sub, "PAUSED")
end

function cmd_resume!(billing::Billing, a::Vector{String})
    sub = require_sub(billing, a[1], "PAUSED")
    elapsed = billing.day - sub.pause_start
    sub.finish += elapsed
    sub.pause_start = 0
    emit!(billing, "RESUME", "sub", sub.number, "shift", elapsed, "period", period(sub))
    change_state!(billing, sub, "ACTIVE")
end

function cmd_cancel!(billing::Billing, a::Vector{String})
    text, when = a
    sub = require_sub(billing, text)
    if when == "END"
        sub.state in ("ACTIVE", "TRIALING") || fail("invalid state $text $(sub.state)")
        sub.cancel_end && fail("already canceling " * text)
        sub.cancel_end = true
        until = sub.state == "TRIALING" ? sub.trial_end : sub.finish
        emit!(billing, "CANCEL", "sub", sub.number, "end", until)
    else
        sub.state == "CANCELED" && fail("invalid state $text $(sub.state)")
        refund = 0
        if sub.state in ("ACTIVE", "PAUSED")
            start = sub.state == "ACTIVE" ? billing.day : sub.pause_start
            plan = billing.plans[sub.plan]
            refund = div(fee(plan, sub.seats)*(sub.finish - start), plan.length)
        end
        balance_change!(billing, billing.customers[sub.customer], refund,
                        "cancel sub $(sub.number)")
        emit!(billing, "CANCEL", "sub", sub.number, "now", "credit", money(refund))
        cancel_subscription!(billing, sub)
    end
end

function cmd_usage!(billing::Billing, a::Vector{String})
    sub = require_sub(billing, a[1], "ACTIVE", "PAST_DUE")
    billing.plans[sub.plan].mode === nothing && fail("not metered " * sub.plan)
    units = parse(Int, a[2])
    units == 0 && fail("invalid units")
    sub.usage += units
    emit!(billing, "USAGE", "sub", sub.number, "units", units, "total", sub.usage)
end

function cmd_apply!(billing::Billing, a::Vector{String})
    text, name = a
    sub = require_sub(billing, text)
    sub.state == "CANCELED" && fail("invalid state $text $(sub.state)")
    coupon = redeemable_coupon(billing, name)
    coupon.redemptions += 1
    sub.coupon = name
    sub.remaining = coupon.applications
    emit!(billing, "APPLY", "sub", sub.number, "coupon", name)
end

function cmd_pay!(billing::Billing, a::Vector{String})
    text = a[1]
    invoice = require_invoice(billing, text)
    invoice.outstanding == 0 && fail("already paid " * text)
    emit!(billing, "PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
    invoice.paid += invoice.outstanding
    invoice.outstanding = 0
    payment_complete!(billing, invoice)
end

function cmd_refund!(billing::Billing, a::Vector{String})
    text, amount = a
    invoice = require_invoice(billing, text)
    value = cents(amount)
    value == 0 && fail("invalid amount")
    maximum = invoice.total - invoice.refunded
    value > maximum && fail("refund exceeds $text $(money(maximum))")
    applied = min(value, invoice.outstanding)
    invoice.refunded += value
    invoice.outstanding -= applied
    customer = billing.customers[invoice.customer]
    balance_change!(billing, customer, value - applied, "refund invoice $(invoice.number)")
    emit!(billing, "REFUND", "invoice", invoice.number, "amount", amount,
          "applied", money(applied), "balance", money(customer.balance))
    applied > 0 && invoice.outstanding == 0 && payment_complete!(billing, invoice)
end

function emit_items!(billing::Billing, items::ITEMS)
    for (description, amount) in items
        indented!(billing, description, money(amount))
    end
end

function emit_totals!(billing::Billing, subtotal::Int, discount::Int, tax::Int, total::Int)
    indented!(billing, "subtotal", money(subtotal), "discount", money(discount),
              "tax", money(tax), "total", money(total))
end

function cmd_invoice!(billing::Billing, a::Vector{String})
    invoice = require_invoice(billing, a[1])
    emit!(billing, "INVOICE", invoice.number, "sub", invoice.subscription,
          invoice.customer, "day", invoice.day, invoice.kind, invoice_state(invoice))
    emit_items!(billing, invoice.items)
    emit_totals!(billing, invoice.subtotal, invoice.discount, invoice.tax, invoice.total)
    indented!(billing, "credit", money(invoice.credit), "due", money(invoice.due),
              "paid", money(invoice.paid), "refunded", money(invoice.refunded),
              "outstanding", money(invoice.outstanding))
end

function cmd_sub!(billing::Billing, a::Vector{String})
    sub = require_sub(billing, a[1])
    emit!(billing, "SUB", sub.number, sub.customer, sub.plan, "seats", sub.seats, sub.state)
    if sub.state == "TRIALING"
        indented!(billing, "trial until", sub.trial_end)
    end
    if sub.state in ("ACTIVE", "PAST_DUE", "UNPAID", "PAUSED")
        indented!(billing, "period", period(sub))
    end
    if sub.state == "PAUSED"
        indented!(billing, "paused since", sub.pause_start)
    end
    if sub.pending !== nothing
        plan, seats = sub.pending
        indented!(billing, "pending", plan, "seats", seats)
    end
    sub.cancel_end && indented!(billing, "cancel at end")
    sub.cancel_on != 0 && indented!(billing, "cancel on", sub.cancel_on)
    sub.state == "CANCELED" && indented!(billing, "canceled on", sub.canceled_on)
    if sub.coupon !== nothing
        if sub.remaining === nothing
            indented!(billing, "coupon", sub.coupon, "forever")
        elseif sub.remaining > 0
            indented!(billing, "coupon", sub.coupon, "left", sub.remaining)
        end
    end
    if billing.plans[sub.plan].mode !== nothing && sub.state != "CANCELED"
        indented!(billing, "usage", sub.usage)
    end
    open = [id for id in sub.invoices if billing.invoices[id].outstanding > 0]
    !isempty(open) && indented!(billing, "open", join(open, " "))
end

function cmd_preview!(billing::Billing, a::Vector{String})
    sub = require_sub(billing, a[1], "TRIALING", "ACTIVE", "PAST_DUE", "UNPAID")
    day = sub.state == "TRIALING" ? sub.trial_end : sub.finish
    items = ITEMS()
    kind = "renewal"
    if sub.cancel_end
        kind = "final"
        items = sub.state == "TRIALING" ? ITEMS() : usage_items!(billing, sub)
    elseif sub.state == "TRIALING"
        kind = "first"
        items = opening_items(billing, sub, day)
    else
        plan, seats = sub.pending === nothing ? (sub.plan, sub.seats) : sub.pending
        items = usage_items!(billing, sub)
        push!(items, period_item(billing.plans[plan], seats, day))
    end
    emit!(billing, "PREVIEW", "sub", sub.number, "day", day, kind)
    if isempty(items)
        indented!(billing, "(none)")
        return
    end
    emit_items!(billing, items)
    subtotal, discount, tax, total, credit, due = invoice_totals(billing, sub, items)
    emit_totals!(billing, subtotal, discount, tax, total)
    indented!(billing, "credit", money(credit), "due", money(due))
end

function cmd_statement!(billing::Billing, a::Vector{String})
    customer = require_customer(billing, a[1])
    emit!(billing, "STATEMENT", customer.name, "region", customer.region,
          "tax", percentage(get(billing.taxes, customer.region, 0)),
          "method", customer.method, "balance", money(customer.balance))
    for id in customer.subscriptions
        sub = billing.subscriptions[id]
        indented!(billing, "sub", sub.number, sub.plan, sub.state)
    end
    outstanding = 0
    for id in customer.invoices
        invoice = billing.invoices[id]
        indented!(billing, "invoice", id, "day", invoice.day, "sub", invoice.subscription,
                  invoice.kind, "total", money(invoice.total),
                  "outstanding", money(invoice.outstanding))
        outstanding += invoice.outstanding
    end
    indented!(billing, "outstanding", money(outstanding))
end

function cmd_ledger!(billing::Billing, a::Vector{String})
    customer = require_customer(billing, a[1])
    emit!(billing, "LEDGER", customer.name, "balance", money(customer.balance))
    if isempty(customer.log)
        indented!(billing, "(none)")
    end
    for (day, description, change, balance) in customer.log
        indented!(billing, "day", day, description, signed_money(change),
                  "balance", money(balance))
    end
end

function cmd_mrr!(billing::Billing, a::Vector{String})
    rows = Dict{String,Tuple{Int,Int}}()
    for sub in billing.subscriptions
        sub.state in ("ACTIVE", "PAST_DUE") || continue
        plan = billing.plans[sub.plan]
        amount = fee(plan, sub.seats)
        monthly = plan.cycle == "MONTHLY" ? amount :
                  plan.cycle == "YEARLY" ? div(amount, 12) : div(amount * 30, 7)
        count, total = get(rows, plan.name, (0, 0))
        rows[plan.name] = (count + 1, total + monthly)
    end
    emit!(billing, "MRR")
    count, total = 0, 0
    for name in sort(collect(keys(rows)))
        subscriptions, monthly = rows[name]
        indented!(billing, name, "subs", subscriptions, "mrr", money(monthly))
        count += subscriptions
        total += monthly
    end
    indented!(billing, "total subs", count, "mrr", money(total))
end

function aging_parts(amounts)
    ("0-30", money(amounts[1]), "31-60", money(amounts[2]),
     "61+", money(amounts[3]), "sum", money(sum(amounts)))
end

function cmd_aging!(billing::Billing, a::Vector{String})
    rows = Dict{String,Vector{Int}}()
    totals = zeros(Int, 3)
    for invoice in billing.invoices
        invoice.outstanding == 0 && continue
        age = billing.day - invoice.day
        bucket = age <= 30 ? 1 : age <= 60 ? 2 : 3
        amounts = get!(rows, invoice.customer, zeros(Int, 3))
        amounts[bucket] += invoice.outstanding
        totals[bucket] += invoice.outstanding
    end
    emit!(billing, "AGING", "day", billing.day)
    for name in sort(collect(keys(rows)))
        indented!(billing, name, aging_parts(rows[name])...)
    end
    indented!(billing, "total", aging_parts(totals)...)
end

function cmd_dunning!(billing::Billing, a::Vector{String})
    emit!(billing, "DUNNING")
    found = false
    for invoice in billing.invoices
        if !isempty(invoice.retries)
            found = true
            indented!(billing, "invoice", invoice.number, "sub", invoice.subscription,
                      invoice.customer, "outstanding", money(invoice.outstanding),
                      "attempts", invoice.attempts, "next", first(invoice.retries))
        end
    end
    !found && indented!(billing, "(none)")
end

function cmd_revenue!(billing::Billing, a::Vector{String})
    invoices = billing.invoices
    emit!(billing, "REVENUE")
    indented!(billing, "invoices", length(invoices),
              "subtotal", money(sum(x.subtotal for x in invoices; init=0)),
              "discount", money(sum(x.discount for x in invoices; init=0)),
              "tax", money(sum(x.tax for x in invoices; init=0)),
              "total", money(sum(x.total for x in invoices; init=0)))
    indented!(billing, "credit", money(sum(x.credit for x in invoices; init=0)),
              "paid", money(sum(x.paid for x in invoices; init=0)),
              "refunded", money(sum(x.refunded for x in invoices; init=0)),
              "outstanding", money(sum(x.outstanding for x in invoices; init=0)),
              "balances", money(sum(c.balance for c in values(billing.customers); init=0)))
end

function cmd_events!(billing::Billing, a::Vector{String})
    selected = isempty(a) ? nothing : require_sub(billing, a[1]).number
    if selected === nothing
        emit!(billing, "EVENTS")
    else
        emit!(billing, "EVENTS", "sub", selected)
    end
    found = false
    for (day, number, old, new) in billing.events
        if selected === nothing || number == selected
            found = true
            indented!(billing, "day", day, "sub", number, old, "->", new)
        end
    end
    !found && indented!(billing, "(none)")
end

const COMMANDS = Dict{String,Function}(
    "PLAN" => cmd_plan!, "TIER" => cmd_tier!, "TAX" => cmd_tax!,
    "CUSTOMER" => cmd_customer!, "COUPON" => cmd_coupon!,
    "PAYMETHOD" => cmd_paymethod!, "CREDIT" => cmd_credit!,
    "DAY" => cmd_day!, "SUBSCRIBE" => cmd_subscribe!,
    "CHANGE" => cmd_change!, "PAUSE" => cmd_pause!, "RESUME" => cmd_resume!,
    "CANCEL" => cmd_cancel!, "USAGE" => cmd_usage!, "APPLY" => cmd_apply!,
    "PAY" => cmd_pay!, "REFUND" => cmd_refund!, "INVOICE" => cmd_invoice!,
    "SUB" => cmd_sub!, "PREVIEW" => cmd_preview!, "STATEMENT" => cmd_statement!,
    "LEDGER" => cmd_ledger!, "MRR" => cmd_mrr!, "AGING" => cmd_aging!,
    "DUNNING" => cmd_dunning!, "REVENUE" => cmd_revenue!, "EVENTS" => cmd_events!
)

function execute!(billing::Billing, line::String)
    words = String.(split(line))
    command = words[1]
    try
        COMMANDS[command](billing, words[2:end])
    catch error
        if error isa BillingError
            emit!(billing, "ERROR", error.message)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    billing = Billing()
    for _ in 1:count
        execute!(billing, readline(stdin))
    end
    for line in billing.output
        println(line)
    end
end

main()
