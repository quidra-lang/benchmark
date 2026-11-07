local period_lengths = {WEEKLY = 7, MONTHLY = 30, YEARLY = 360}

local function cents(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end

local function money(value)
    local sign = value < 0 and "-" or ""
    local absolute = math.abs(value)
    return sign .. string.format("%d.%02d", absolute // 100, absolute % 100)
end

local function signed_money(value)
    return (value > 0 and "+" or "") .. money(value)
end

local function percentage(bp)
    return money(bp) .. "%"
end

local function error_command(reason)
    error({reason = reason}, 0)
end

local function contains(items, item)
    for _, value in ipairs(items) do
        if value == item then return true end
    end
    return false
end

local function fee(plan, seats)
    return plan.price * (plan.per_seat and seats or 1)
end

local function usage_charge(plan, units)
    local total = 0
    local lower = 0
    for index, tier in ipairs(plan.tiers) do
        local last = index == #plan.tiers
        if plan.mode == "VOLUME" then
            if last or tier.upper == nil or units <= tier.upper then
                return units * tier.unit + tier.flat
            end
        else
            if units <= lower then break end
            local upper = (last or tier.upper == nil) and units or tier.upper
            total = total + (math.min(units, upper) - lower) * tier.unit + tier.flat
            if last or tier.upper == nil then break end
            lower = tier.upper
        end
    end
    return total
end

local Billing = {}
Billing.__index = Billing

function Billing.new()
    return setmetatable({
        day = 1,
        plans = {}, taxes = {}, customers = {}, coupons = {},
        subscriptions = {}, invoices = {}, events = {}, output = {}
    }, Billing)
end

function Billing:emit(...)
    local parts = {...}
    for i, value in ipairs(parts) do
        parts[i] = tostring(value)
    end
    self.output[#self.output + 1] = table.concat(parts, " ")
end

function Billing:indented(...)
    local parts = {...}
    for i, value in ipairs(parts) do
        parts[i] = tostring(value)
    end
    self.output[#self.output + 1] = "  " .. table.concat(parts, " ")
end

function Billing:notice(...)
    self:indented("day", self.day, ...)
end

function Billing:plan(name)
    local plan = self.plans[name]
    if not plan then error_command("unknown plan " .. name) end
    return plan
end

function Billing:customer(name)
    local customer = self.customers[name]
    if not customer then error_command("unknown customer " .. name) end
    return customer
end

function Billing:redeemable_coupon(name)
    local coupon = self.coupons[name]
    if not coupon then error_command("unknown coupon " .. name) end
    if coupon.maximum and coupon.redemptions == coupon.maximum then
        error_command("coupon exhausted " .. name)
    end
    return coupon
end

function Billing:subscription(text, allowed)
    local number = tonumber(text)
    local subscription = self.subscriptions[number]
    if not subscription then error_command("unknown sub " .. text) end
    if allowed and not contains(allowed, subscription.state) then
        error_command("invalid state " .. text .. " " .. subscription.state)
    end
    return subscription
end

function Billing:invoice(text)
    local invoice = self.invoices[tonumber(text)]
    if not invoice then error_command("unknown invoice " .. text) end
    return invoice
end

function Billing:balance_change(customer, change, description)
    if change ~= 0 then
        customer.balance = customer.balance + change
        customer.log[#customer.log + 1] = {
            day = self.day, description = description,
            change = change, balance = customer.balance
        }
    end
end

function Billing:change_state(subscription, state)
    local old = subscription.state
    if old == "PAST_DUE" then
        for _, invoice in ipairs(subscription.invoices) do
            invoice.retries = {}
        end
    end
    subscription.state = state
    self:notice("sub", subscription.number, old, "->", state)
    self.events[#self.events + 1] = {
        day = self.day, number = subscription.number, old = old, new = state
    }
end

local function period_item(plan, seats, start)
    return {
        description = "charge " .. plan.name .. " seats " .. seats .. " " ..
                      start .. "-" .. (start + plan.length),
        amount = fee(plan, seats)
    }
end

local function opening_items(subscription, start)
    local plan = subscription.plan
    local items = {period_item(plan, subscription.seats, start)}
    if plan.setup ~= 0 then
        items[#items + 1] = {description = "setup " .. plan.name, amount = plan.setup}
    end
    return items
end

local function usage_items(subscription, close)
    local plan = subscription.plan
    if not plan.mode or subscription.usage == 0 then return {} end
    local units = subscription.usage
    local item = {
        description = "usage " .. plan.name .. " " .. units .. " units",
        amount = usage_charge(plan, units)
    }
    if close then subscription.usage = 0 end
    return {item}
end

local function coupon_usable(subscription, subtotal)
    return subtotal > 0 and subscription.coupon ~= nil and
           (subscription.remaining == nil or subscription.remaining > 0)
end

function Billing:invoice_totals(subscription, items)
    local subtotal = 0
    for _, item in ipairs(items) do subtotal = subtotal + item.amount end
    local discount = 0
    if coupon_usable(subscription, subtotal) then
        local coupon = subscription.coupon
        if coupon.kind == "PERCENT" then
            discount = (subtotal * coupon.value) // 10000
        else
            discount = math.min(subtotal, coupon.value)
        end
    end
    local tax = ((subtotal - discount) * (self.taxes[subscription.customer.region] or 0)) // 10000
    local total = subtotal - discount + tax
    local credit = math.min(subscription.customer.balance, total)
    return {subtotal, discount, tax, total, credit, total - credit}
end

function Billing:issue(subscription, kind, items)
    local totals = self:invoice_totals(subscription, items)
    local invoice = {
        number = #self.invoices + 1, subscription = subscription,
        customer = subscription.customer, day = self.day, kind = kind, items = items,
        subtotal = totals[1], discount = totals[2], tax = totals[3],
        total = totals[4], credit = totals[5], due = totals[6],
        paid = 0, refunded = 0, outstanding = totals[6], attempts = 0, retries = {}
    }
    if coupon_usable(subscription, invoice.subtotal) and subscription.remaining ~= nil then
        subscription.remaining = subscription.remaining - 1
    end
    self.invoices[#self.invoices + 1] = invoice
    subscription.invoices[#subscription.invoices + 1] = invoice
    subscription.customer.invoices[#subscription.customer.invoices + 1] = invoice
    self:balance_change(subscription.customer, -invoice.credit, "applied invoice " .. invoice.number)

    local result
    if invoice.due == 0 then
        result = "PAID"
    elseif subscription.state == "UNPAID" then
        result = "OPEN"
    else
        invoice.attempts = 1
        if subscription.customer.method == "OK" then
            invoice.paid = invoice.due
            invoice.outstanding = 0
            result = "PAID"
        else
            result = "FAILED"
        end
    end
    self:notice("invoice", invoice.number, "sub", subscription.number,
                kind, "total", money(invoice.total), "credit", money(invoice.credit),
                "due", money(invoice.due), result)
    if result == "FAILED" then
        if subscription.state == "ACTIVE" then
            self:change_state(subscription, "PAST_DUE")
        end
        if subscription.state == "PAST_DUE" then
            invoice.retries = {self.day + 3, self.day + 5, self.day + 7}
        end
    end
end

function Billing:payment_complete(invoice)
    invoice.retries = {}
    local subscription = invoice.subscription
    if subscription.state == "PAST_DUE" or subscription.state == "UNPAID" then
        for _, other in ipairs(subscription.invoices) do
            if other.outstanding ~= 0 then return end
        end
        subscription.cancel_on = nil
        self:change_state(subscription, "ACTIVE")
    end
end

function Billing:cancel_subscription(subscription)
    self:change_state(subscription, "CANCELED")
    subscription.canceled_on = self.day
    subscription.pending = nil
    subscription.cancel_end = false
    subscription.cancel_on = nil
    local items = usage_items(subscription, true)
    if #items > 0 then
        self:issue(subscription, "final", items)
    end
end

function Billing:retry(invoice)
    table.remove(invoice.retries, 1)
    invoice.attempts = invoice.attempts + 1
    local retry_number = invoice.attempts - 1
    if invoice.customer.method == "OK" then
        invoice.paid = invoice.paid + invoice.outstanding
        invoice.outstanding = 0
        self:notice("retry", retry_number, "invoice", invoice.number, "PAID")
        self:payment_complete(invoice)
    else
        self:notice("retry", retry_number, "invoice", invoice.number, "FAILED")
        if #invoice.retries == 0 then
            self:change_state(invoice.subscription, "UNPAID")
            invoice.subscription.cancel_on = self.day + 14
        end
    end
end

function Billing:advance_subscription(subscription)
    if subscription.state == "PAUSED" or subscription.state == "CANCELED" then return end
    for _, invoice in ipairs(subscription.invoices) do
        if #invoice.retries > 0 and invoice.retries[1] == self.day then
            self:retry(invoice)
        end
    end
    if subscription.state == "UNPAID" and subscription.cancel_on == self.day then
        self:cancel_subscription(subscription)
    end
    if subscription.state == "TRIALING" and subscription.trial_end == self.day then
        if subscription.cancel_end then
            self:cancel_subscription(subscription)
        else
            self:change_state(subscription, "ACTIVE")
            subscription.start = self.day
            subscription.finish = self.day + subscription.plan.length
            self:issue(subscription, "first", opening_items(subscription, self.day))
        end
    end
    if contains({"ACTIVE", "PAST_DUE", "UNPAID"}, subscription.state) and
       subscription.finish == self.day then
        if subscription.cancel_end then
            self:cancel_subscription(subscription)
        else
            local items = usage_items(subscription, true)
            if subscription.pending then
                local plan, seats = subscription.pending[1], subscription.pending[2]
                self:notice("sub", subscription.number, subscription.plan.name,
                            "seats", subscription.seats, "->", plan.name, "seats", seats)
                subscription.plan, subscription.seats = plan, seats
                subscription.pending = nil
            end
            subscription.start = self.day
            subscription.finish = self.day + subscription.plan.length
            items[#items + 1] = period_item(subscription.plan, subscription.seats, self.day)
            self:issue(subscription, "renewal", items)
        end
    end
end

function Billing:cmd_plan(args)
    local name, amount, cycle = args[1], args[2], args[3]
    if self.plans[name] then error_command("duplicate plan " .. name) end
    local plan = {
        name = name, price = cents(amount), cycle = cycle,
        length = period_lengths[cycle], trial = 0, setup = 0,
        per_seat = false, mode = nil, tiers = {}
    }
    local i = 4
    while i <= #args do
        local option = args[i]
        if option == "TRIAL" then
            plan.trial = tonumber(args[i + 1])
            i = i + 2
        elseif option == "SETUP" then
            plan.setup = cents(args[i + 1])
            i = i + 2
        else
            if option == "PERSEAT" then plan.per_seat = true
            else plan.mode = option end
            i = i + 1
        end
    end
    self.plans[name] = plan
    local line = {"PLAN", name, cycle, amount}
    if plan.trial ~= 0 then line[#line + 1] = "trial"; line[#line + 1] = plan.trial end
    if plan.setup ~= 0 then line[#line + 1] = "setup"; line[#line + 1] = money(plan.setup) end
    if plan.per_seat then line[#line + 1] = "perseat" end
    if plan.mode then line[#line + 1] = plan.mode:lower() end
    self:emit(table.unpack(line))
end

function Billing:cmd_tier(args)
    local name, limit, unit, flat = table.unpack(args)
    local plan = self:plan(name)
    if not plan.mode then error_command("not metered " .. name) end
    local upper = limit ~= "INF" and tonumber(limit) or nil
    if #plan.tiers > 0 then
        local previous = plan.tiers[#plan.tiers].upper
        if previous == nil or (upper ~= nil and upper <= previous) then
            error_command("tier order " .. name)
        end
    end
    plan.tiers[#plan.tiers + 1] = {
        upper = upper, unit = cents(unit), flat = cents(flat)
    }
    self:emit("TIER", name, #plan.tiers, "upto", limit, "unit", unit, "flat", flat)
end

function Billing:cmd_tax(args)
    local region, bp = args[1], tonumber(args[2])
    self.taxes[region] = bp
    self:emit("TAX", region, percentage(bp))
end

function Billing:cmd_customer(args)
    local name, region = args[1], args[2]
    if self.customers[name] then error_command("duplicate customer " .. name) end
    self.customers[name] = {
        name = name, region = region, method = "OK", balance = 0,
        log = {}, subscriptions = {}, invoices = {}
    }
    self:emit("CUSTOMER", name, "region", region)
end

function Billing:cmd_coupon(args)
    local name, kind, value, application = args[1], args[2], args[3], args[4]
    if self.coupons[name] then error_command("duplicate coupon " .. name) end
    local applications = application == "ONCE" and 1 or nil
    local i = 5
    if application == "REPEATING" then
        applications = tonumber(args[5])
        i = 6
    end
    local maximum = i <= #args and tonumber(args[i + 1]) or nil
    local numeric = kind == "PERCENT" and tonumber(value) or cents(value)
    local coupon = {
        name = name, kind = kind, value = numeric, applications = applications,
        maximum = maximum, redemptions = 0
    }
    self.coupons[name] = coupon
    local shown = kind == "PERCENT" and percentage(numeric) or money(numeric)
    local line = {"COUPON", name, kind:lower(), shown, application:lower()}
    if application == "REPEATING" then line[#line + 1] = applications end
    if maximum then line[#line + 1] = "max"; line[#line + 1] = maximum end
    self:emit(table.unpack(line))
end

function Billing:cmd_paymethod(args)
    local customer = self:customer(args[1])
    customer.method = args[2]
    self:emit("PAYMETHOD", args[1], args[2])
end

function Billing:cmd_credit(args)
    local customer = self:customer(args[1])
    local value = cents(args[2])
    if value == 0 then error_command("invalid amount") end
    self:balance_change(customer, value, "grant")
    self:emit("CREDIT", args[1], "amount", args[2], "balance", money(customer.balance))
end

function Billing:cmd_day(args)
    local target = tonumber(args[1])
    if target <= self.day then error_command("invalid day " .. args[1]) end
    self:emit("DAY", target)
    for day = self.day + 1, target do
        self.day = day
        for _, subscription in ipairs(self.subscriptions) do
            self:advance_subscription(subscription)
        end
    end
end

function Billing:cmd_subscribe(args)
    local name, plan_name = args[1], args[2]
    local customer = self:customer(name)
    local plan = self:plan(plan_name)
    local seats, has_seats, coupon_name = 1, false, nil
    for i = 3, #args, 2 do
        if args[i] == "SEATS" then
            seats = tonumber(args[i + 1])
            has_seats = true
        else
            coupon_name = args[i + 1]
        end
    end
    if has_seats and not plan.per_seat then error_command("not per-seat " .. plan_name) end
    if seats == 0 then error_command("invalid seats") end
    local coupon = coupon_name and self:redeemable_coupon(coupon_name) or nil
    local subscription = {
        number = #self.subscriptions + 1, customer = customer, plan = plan,
        seats = seats, state = "NONE", start = nil, finish = nil,
        trial_end = nil, pause_start = nil, pending = nil,
        cancel_end = false, cancel_on = nil, canceled_on = nil,
        coupon = coupon, remaining = coupon and coupon.applications or nil,
        usage = 0, invoices = {}
    }
    if coupon then coupon.redemptions = coupon.redemptions + 1 end
    self.subscriptions[#self.subscriptions + 1] = subscription
    customer.subscriptions[#customer.subscriptions + 1] = subscription
    local line = {"SUBSCRIBE", "sub", subscription.number, name, plan_name, "seats", seats}
    if coupon then line[#line + 1] = "coupon"; line[#line + 1] = coupon.name end
    self:emit(table.unpack(line))
    if plan.trial > 0 then
        subscription.trial_end = self.day + plan.trial
        self:change_state(subscription, "TRIALING")
    else
        self:change_state(subscription, "ACTIVE")
        subscription.start = self.day
        subscription.finish = self.day + plan.length
        self:issue(subscription, "first", opening_items(subscription, self.day))
    end
end

function Billing:cmd_change(args)
    local text, kind, value = args[1], args[2], args[3]
    local subscription = self:subscription(text, {"ACTIVE", "TRIALING"})
    local old_plan, old_seats = subscription.plan, subscription.seats
    local plan, seats
    if kind == "PLAN" then
        plan = self:plan(value)
        seats = plan.per_seat and old_seats or 1
    else
        plan = old_plan
        if not plan.per_seat then error_command("not per-seat " .. plan.name) end
        seats = tonumber(value)
        if seats == 0 then error_command("invalid seats") end
    end
    if plan == old_plan and seats == old_seats then error_command("no change " .. text) end
    local head = {"CHANGE", "sub", subscription.number, old_plan.name, "seats",
                  old_seats, "->", plan.name, "seats", seats}
    subscription.pending = nil
    local upgrade = fee(plan, seats) * old_plan.length > fee(old_plan, old_seats) * plan.length
    if subscription.state == "TRIALING" then
        subscription.plan, subscription.seats = plan, seats
        head[#head + 1] = "now"
        self:emit(table.unpack(head))
    elseif upgrade then
        head[#head + 1] = "now"
        self:emit(table.unpack(head))
        local days = subscription.finish - self.day
        local items = usage_items(subscription, true)
        items[#items + 1] = {
            description = "unused " .. old_plan.name .. " seats " .. old_seats ..
                          " " .. days .. " days",
            amount = -(fee(old_plan, old_seats) * days // old_plan.length)
        }
        items[#items + 1] = {
            description = "remaining " .. plan.name .. " seats " .. seats ..
                          " " .. days .. " days",
            amount = fee(plan, seats) * days // plan.length
        }
        subscription.plan, subscription.seats = plan, seats
        self:issue(subscription, "upgrade", items)
    else
        subscription.pending = {plan, seats}
        head[#head + 1] = "at"
        head[#head + 1] = subscription.finish
        self:emit(table.unpack(head))
    end
end

function Billing:cmd_pause(args)
    local subscription = self:subscription(args[1], {"ACTIVE"})
    self:emit("PAUSE", "sub", subscription.number)
    subscription.pause_start = self.day
    self:change_state(subscription, "PAUSED")
end

function Billing:cmd_resume(args)
    local subscription = self:subscription(args[1], {"PAUSED"})
    local elapsed = self.day - subscription.pause_start
    subscription.finish = subscription.finish + elapsed
    subscription.pause_start = nil
    self:emit("RESUME", "sub", subscription.number, "shift", elapsed, "period",
              subscription.start .. "-" .. subscription.finish)
    self:change_state(subscription, "ACTIVE")
end

function Billing:cmd_cancel(args)
    local text, when = args[1], args[2]
    local subscription = self:subscription(text)
    if when == "END" then
        if not contains({"ACTIVE", "TRIALING"}, subscription.state) then
            error_command("invalid state " .. text .. " " .. subscription.state)
        end
        if subscription.cancel_end then error_command("already canceling " .. text) end
        subscription.cancel_end = true
        local day = subscription.state == "TRIALING" and
                    subscription.trial_end or subscription.finish
        self:emit("CANCEL", "sub", subscription.number, "end", day)
    else
        if subscription.state == "CANCELED" then
            error_command("invalid state " .. text .. " " .. subscription.state)
        end
        local refund = 0
        if subscription.state == "ACTIVE" or subscription.state == "PAUSED" then
            local start = subscription.state == "ACTIVE" and self.day or subscription.pause_start
            refund = fee(subscription.plan, subscription.seats) *
                     (subscription.finish - start) // subscription.plan.length
        end
        self:balance_change(subscription.customer, refund, "cancel sub " .. subscription.number)
        self:emit("CANCEL", "sub", subscription.number, "now", "credit", money(refund))
        self:cancel_subscription(subscription)
    end
end

function Billing:cmd_usage(args)
    local subscription = self:subscription(args[1], {"ACTIVE", "PAST_DUE"})
    if not subscription.plan.mode then
        error_command("not metered " .. subscription.plan.name)
    end
    local quantity = tonumber(args[2])
    if quantity == 0 then error_command("invalid units") end
    subscription.usage = subscription.usage + quantity
    self:emit("USAGE", "sub", subscription.number, "units",
              quantity, "total", subscription.usage)
end

function Billing:cmd_apply(args)
    local text, name = args[1], args[2]
    local subscription = self:subscription(text)
    if subscription.state == "CANCELED" then
        error_command("invalid state " .. text .. " " .. subscription.state)
    end
    local coupon = self:redeemable_coupon(name)
    coupon.redemptions = coupon.redemptions + 1
    subscription.coupon = coupon
    subscription.remaining = coupon.applications
    self:emit("APPLY", "sub", subscription.number, "coupon", name)
end

function Billing:cmd_pay(args)
    local text = args[1]
    local invoice = self:invoice(text)
    if invoice.outstanding == 0 then error_command("already paid " .. text) end
    self:emit("PAY", "invoice", invoice.number, "amount", money(invoice.outstanding))
    invoice.paid = invoice.paid + invoice.outstanding
    invoice.outstanding = 0
    self:payment_complete(invoice)
end

function Billing:cmd_refund(args)
    local text, amount = args[1], args[2]
    local invoice = self:invoice(text)
    local value = cents(amount)
    if value == 0 then error_command("invalid amount") end
    local maximum = invoice.total - invoice.refunded
    if value > maximum then
        error_command("refund exceeds " .. text .. " " .. money(maximum))
    end
    local applied = math.min(value, invoice.outstanding)
    invoice.refunded = invoice.refunded + value
    invoice.outstanding = invoice.outstanding - applied
    self:balance_change(invoice.customer, value - applied, "refund invoice " .. invoice.number)
    self:emit("REFUND", "invoice", invoice.number, "amount", amount,
              "applied", money(applied), "balance", money(invoice.customer.balance))
    if applied > 0 and invoice.outstanding == 0 then self:payment_complete(invoice) end
end

function Billing:emit_items(items)
    for _, item in ipairs(items) do
        self:indented(item.description, money(item.amount))
    end
end

function Billing:emit_totals(totals)
    self:indented("subtotal", money(totals[1]), "discount", money(totals[2]),
                  "tax", money(totals[3]), "total", money(totals[4]))
end

function Billing:cmd_invoice(args)
    local invoice = self:invoice(args[1])
    self:emit("INVOICE", invoice.number, "sub", invoice.subscription.number,
              invoice.customer.name, "day", invoice.day, invoice.kind,
              invoice.outstanding == 0 and "PAID" or "OPEN")
    self:emit_items(invoice.items)
    self:emit_totals({invoice.subtotal, invoice.discount, invoice.tax, invoice.total})
    self:indented("credit", money(invoice.credit), "due", money(invoice.due),
                  "paid", money(invoice.paid), "refunded", money(invoice.refunded),
                  "outstanding", money(invoice.outstanding))
end

function Billing:cmd_sub(args)
    local subscription = self:subscription(args[1])
    local state = subscription.state
    self:emit("SUB", subscription.number, subscription.customer.name,
              subscription.plan.name, "seats", subscription.seats, state)
    if state == "TRIALING" then
        self:indented("trial until", subscription.trial_end)
    end
    if contains({"ACTIVE", "PAST_DUE", "UNPAID", "PAUSED"}, state) then
        self:indented("period", subscription.start .. "-" .. subscription.finish)
    end
    if state == "PAUSED" then self:indented("paused since", subscription.pause_start) end
    if subscription.pending then
        self:indented("pending", subscription.pending[1].name,
                      "seats", subscription.pending[2])
    end
    if subscription.cancel_end then self:indented("cancel at end") end
    if subscription.cancel_on then self:indented("cancel on", subscription.cancel_on) end
    if state == "CANCELED" then self:indented("canceled on", subscription.canceled_on) end
    if subscription.coupon then
        if subscription.remaining == nil then
            self:indented("coupon", subscription.coupon.name, "forever")
        elseif subscription.remaining > 0 then
            self:indented("coupon", subscription.coupon.name, "left", subscription.remaining)
        end
    end
    if subscription.plan.mode and state ~= "CANCELED" then
        self:indented("usage", subscription.usage)
    end
    local open = {}
    for _, invoice in ipairs(subscription.invoices) do
        if invoice.outstanding > 0 then open[#open + 1] = invoice.number end
    end
    if #open > 0 then
        local parts = {"open"}
        for _, number in ipairs(open) do parts[#parts + 1] = number end
        self:indented(table.unpack(parts))
    end
end

function Billing:cmd_preview(args)
    local subscription = self:subscription(args[1],
        {"TRIALING", "ACTIVE", "PAST_DUE", "UNPAID"})
    local day = subscription.state == "TRIALING" and subscription.trial_end or
                subscription.finish
    local kind, items
    if subscription.cancel_end then
        kind = "final"
        items = subscription.state == "TRIALING" and {} or usage_items(subscription)
    elseif subscription.state == "TRIALING" then
        kind = "first"
        items = opening_items(subscription, day)
    else
        kind = "renewal"
        local plan = subscription.pending and subscription.pending[1] or subscription.plan
        local seats = subscription.pending and subscription.pending[2] or subscription.seats
        items = usage_items(subscription)
        items[#items + 1] = period_item(plan, seats, day)
    end
    self:emit("PREVIEW", "sub", subscription.number, "day", day, kind)
    if #items == 0 then
        self:indented("(none)")
        return
    end
    self:emit_items(items)
    local totals = self:invoice_totals(subscription, items)
    self:emit_totals(totals)
    self:indented("credit", money(totals[5]), "due", money(totals[6]))
end

function Billing:cmd_statement(args)
    local customer = self:customer(args[1])
    self:emit("STATEMENT", customer.name, "region", customer.region,
              "tax", percentage(self.taxes[customer.region] or 0),
              "method", customer.method, "balance", money(customer.balance))
    for _, subscription in ipairs(customer.subscriptions) do
        self:indented("sub", subscription.number, subscription.plan.name,
                      subscription.state)
    end
    local outstanding = 0
    for _, invoice in ipairs(customer.invoices) do
        self:indented("invoice", invoice.number, "day", invoice.day,
                      "sub", invoice.subscription.number, invoice.kind,
                      "total", money(invoice.total), "outstanding", money(invoice.outstanding))
        outstanding = outstanding + invoice.outstanding
    end
    self:indented("outstanding", money(outstanding))
end

function Billing:cmd_ledger(args)
    local customer = self:customer(args[1])
    self:emit("LEDGER", customer.name, "balance", money(customer.balance))
    if #customer.log == 0 then self:indented("(none)") end
    for _, entry in ipairs(customer.log) do
        self:indented("day", entry.day, entry.description, signed_money(entry.change),
                      "balance", money(entry.balance))
    end
end

function Billing:cmd_mrr()
    local by_plan = {}
    for _, subscription in ipairs(self.subscriptions) do
        if subscription.state == "ACTIVE" or subscription.state == "PAST_DUE" then
            local price = fee(subscription.plan, subscription.seats)
            local cycle = subscription.plan.cycle
            local monthly = cycle == "MONTHLY" and price or
                            (cycle == "YEARLY" and price // 12 or price * 30 // 7)
            local name = subscription.plan.name
            local row = by_plan[name]
            if not row then row = {0, 0}; by_plan[name] = row end
            row[1] = row[1] + 1
            row[2] = row[2] + monthly
        end
    end
    local names = {}
    for name in pairs(by_plan) do names[#names + 1] = name end
    table.sort(names)
    self:emit("MRR")
    local count, total = 0, 0
    for _, name in ipairs(names) do
        local row = by_plan[name]
        self:indented(name, "subs", row[1], "mrr", money(row[2]))
        count, total = count + row[1], total + row[2]
    end
    self:indented("total subs", count, "mrr", money(total))
end

local function aging_parts(amounts)
    local total = amounts[1] + amounts[2] + amounts[3]
    return "0-30", money(amounts[1]), "31-60", money(amounts[2]),
           "61+", money(amounts[3]), "sum", money(total)
end

function Billing:cmd_aging()
    local by_customer = {}
    local totals = {0, 0, 0}
    for _, invoice in ipairs(self.invoices) do
        if invoice.outstanding ~= 0 then
            local age = self.day - invoice.day
            local bucket = age <= 30 and 1 or (age <= 60 and 2 or 3)
            local name = invoice.customer.name
            if not by_customer[name] then by_customer[name] = {0, 0, 0} end
            by_customer[name][bucket] = by_customer[name][bucket] + invoice.outstanding
            totals[bucket] = totals[bucket] + invoice.outstanding
        end
    end
    local names = {}
    for name in pairs(by_customer) do names[#names + 1] = name end
    table.sort(names)
    self:emit("AGING", "day", self.day)
    for _, name in ipairs(names) do
        self:indented(name, aging_parts(by_customer[name]))
    end
    self:indented("total", aging_parts(totals))
end

function Billing:cmd_dunning()
    self:emit("DUNNING")
    local found = false
    for _, invoice in ipairs(self.invoices) do
        if #invoice.retries > 0 then
            found = true
            self:indented("invoice", invoice.number, "sub", invoice.subscription.number,
                          invoice.customer.name, "outstanding", money(invoice.outstanding),
                          "attempts", invoice.attempts, "next", invoice.retries[1])
        end
    end
    if not found then self:indented("(none)") end
end

function Billing:cmd_revenue()
    local subtotal, discount, tax, total, credit, paid, refunded, outstanding =
        0, 0, 0, 0, 0, 0, 0, 0
    for _, invoice in ipairs(self.invoices) do
        subtotal = subtotal + invoice.subtotal
        discount = discount + invoice.discount
        tax = tax + invoice.tax
        total = total + invoice.total
        credit = credit + invoice.credit
        paid = paid + invoice.paid
        refunded = refunded + invoice.refunded
        outstanding = outstanding + invoice.outstanding
    end
    local balances = 0
    for _, customer in pairs(self.customers) do balances = balances + customer.balance end
    self:emit("REVENUE")
    self:indented("invoices", #self.invoices, "subtotal", money(subtotal),
                  "discount", money(discount), "tax", money(tax), "total", money(total))
    self:indented("credit", money(credit), "paid", money(paid),
                  "refunded", money(refunded), "outstanding", money(outstanding),
                  "balances", money(balances))
end

function Billing:cmd_events(args)
    local selected = #args > 0 and self:subscription(args[1]).number or nil
    if selected then self:emit("EVENTS", "sub", selected)
    else self:emit("EVENTS") end
    local found = false
    for _, event in ipairs(self.events) do
        if selected == nil or event.number == selected then
            found = true
            self:indented("day", event.day, "sub", event.number,
                          event.old, "->", event.new)
        end
    end
    if not found then self:indented("(none)") end
end

local handlers = {
    PLAN = Billing.cmd_plan,
    TIER = Billing.cmd_tier,
    TAX = Billing.cmd_tax,
    CUSTOMER = Billing.cmd_customer,
    COUPON = Billing.cmd_coupon,
    PAYMETHOD = Billing.cmd_paymethod,
    CREDIT = Billing.cmd_credit,
    DAY = Billing.cmd_day,
    SUBSCRIBE = Billing.cmd_subscribe,
    CHANGE = Billing.cmd_change,
    PAUSE = Billing.cmd_pause,
    RESUME = Billing.cmd_resume,
    CANCEL = Billing.cmd_cancel,
    USAGE = Billing.cmd_usage,
    APPLY = Billing.cmd_apply,
    PAY = Billing.cmd_pay,
    REFUND = Billing.cmd_refund,
    INVOICE = Billing.cmd_invoice,
    SUB = Billing.cmd_sub,
    PREVIEW = Billing.cmd_preview,
    STATEMENT = Billing.cmd_statement,
    LEDGER = Billing.cmd_ledger,
    MRR = Billing.cmd_mrr,
    AGING = Billing.cmd_aging,
    DUNNING = Billing.cmd_dunning,
    REVENUE = Billing.cmd_revenue,
    EVENTS = Billing.cmd_events
}

function Billing:execute(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    local command = table.remove(words, 1)
    local ok, reason = pcall(function() handlers[command](self, words) end)
    if not ok then
        if type(reason) == "table" and reason.reason then
            self:emit("ERROR", reason.reason)
        else
            error(reason)
        end
    end
end

local number_of_commands = tonumber(io.read("*l"))
local billing = Billing.new()
for _ = 1, number_of_commands do
    billing:execute(io.read("*l"))
end
if #billing.output > 0 then
    io.write(table.concat(billing.output, "\n"), "\n")
end
