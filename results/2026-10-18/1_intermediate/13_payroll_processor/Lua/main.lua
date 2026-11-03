local rate_settings = {
    STATE = true, SUPP = true, SSRATE = true, MEDRATE = true,
    ADDMED = true, UIRATE = true, MATCH = true, MATCHMAX = true,
    GARNCAP = true
}
local setting_order = {
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP",
    "SSBASE", "ADDBASE", "UIBASE", "RETIRECAP", "ALLOWANCE", "NIGHT"
}
local initial_settings = {
    STATE = 500, SUPP = 2200, SSRATE = 620, MEDRATE = 145,
    ADDMED = 90, UIRATE = 270, MATCH = 5000, MATCHMAX = 600,
    GARNCAP = 2500, SSBASE = 16860000, ADDBASE = 20000000,
    UIBASE = 700000, RETIRECAP = 2300000, ALLOWANCE = 15000,
    NIGHT = 100
}
local fields = {
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment",
    "net", "employer_social", "employer_medicare", "unemployment", "match",
    "employer", "W", "Y", "F", "J"
}
local weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

local function cents(text)
    local whole, fraction = text:match("^(%d+)%.(%d%d)$")
    return tonumber(whole) * 100 + tonumber(fraction)
end

local function money(value)
    return string.format("%d.%02d", value // 100, value % 100)
end

local function rate_text(value)
    return money(value) .. "%"
end

local function duration(value)
    return string.format("%d:%02d", value // 60, value % 60)
end

local function clock(value)
    return string.format("%02d:%02d", value // 60, value % 60)
end

local function weekday(day)
    return weekdays[(day - 1) % 7 + 1]
end

local function period_of(day)
    return (day - 1) // 14 + 1
end

local function empty_totals()
    local totals = {}
    for _, field in ipairs(fields) do totals[field] = 0 end
    return totals
end

local function sum_stubs(stubs)
    local totals = empty_totals()
    for _, stub in ipairs(stubs) do
        for _, field in ipairs(fields) do
            totals[field] = totals[field] + stub[field]
        end
    end
    return totals
end

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function progressive(brackets, amount)
    local limits = sorted_keys(brackets)
    local numerator = 0
    for i, lower in ipairs(limits) do
        if lower >= amount then break end
        local upper = limits[i + 1] or amount
        numerator = numerator + brackets[lower] * (math.min(amount, upper) - lower)
    end
    return numerator // 10000
end

local function new_employee(id, department, kind, base)
    return {
        id = id, department = department, kind = kind, base = base,
        active = true, retirement = 0, health = 0, allowances = 0, extra = 0,
        garnishments = {}, bonus = 0, pto_balance = 0,
        shifts = {}, pto = {}, leave = {}, sales = {}, stubs = {},
        ytd = empty_totals(), periods = 0
    }
end

local function garnish_balance(employee)
    local total = 0
    for _, order in ipairs(employee.garnishments) do total = total + order[2] end
    return total
end

local function new_payroll()
    local settings = {}
    for key, value in pairs(initial_settings) do settings[key] = value end
    return {
        settings = settings, brackets = {}, tiers = {},
        holidays = {}, employees = {}, closed = 0, output = {}
    }
end

local function emit(payroll, indent, ...)
    local args = {...}
    for i, value in ipairs(args) do args[i] = tostring(value) end
    payroll.output[#payroll.output + 1] = string.rep(" ", indent) .. table.concat(args, " ")
end

local function fail(reason)
    error({payroll_error = reason}, 0)
end

local function employee_of(payroll, text, active, kind)
    local id = tonumber(text)
    local employee = payroll.employees[id]
    if not employee then fail("unknown employee " .. text) end
    if active and not employee.active then fail("terminated employee " .. text) end
    if kind and employee.kind ~= kind then fail("not " .. kind:lower() .. " " .. text) end
    return employee
end

local function day_check(payroll, text)
    local day = tonumber(text)
    if day < 1 or day > 364 then fail("invalid day " .. text) end
    local period = period_of(day)
    if period <= payroll.closed then fail("period closed " .. period) end
    return day
end

local function period_check(text)
    local period = tonumber(text)
    if period < 1 or period > 26 then fail("invalid period " .. text) end
    return period
end

local function rate_check(text)
    local value = cents(text)
    if value > 10000 then fail("invalid rate " .. text) end
    return value
end

local function amount_check(text)
    local value = cents(text)
    if value == 0 then fail("invalid amount") end
    return value
end

local function time_check(text)
    local hours, minutes = text:match("^(%d%d):(%d%d)$")
    hours, minutes = tonumber(hours), tonumber(minutes)
    if hours > 23 or minutes > 59 then fail("invalid time " .. text) end
    return hours * 60 + minutes
end

local function daily(payroll, employee, day)
    local shifts = employee.shifts[day] or {}
    local worked, night = 0, 0
    for _, shift in ipairs(shifts) do
        local first, last = shift[1], shift[2]
        worked = worked + last - first
        night = night + math.max(0, math.min(last, 360) - first) +
                        math.max(0, last - math.max(first, 1320))
    end
    local pto = employee.pto[day] or 0
    local regular, overtime, double
    if day % 7 == 0 or payroll.holidays[day] then
        regular, overtime, double = 0, 0, worked
    else
        regular = math.min(worked, 480)
        overtime = math.min(math.max(worked - 480, 0), 240)
        double = math.max(worked - 720, 0)
    end
    return worked, regular, overtime, double, night, pto
end

local function weekly(payroll, employee, week)
    local totals = {0, 0, 0, 0, 0}
    for day = 7 * week - 6, 7 * week do
        local _, regular, overtime, double, night, pto = daily(payroll, employee, day)
        local parts = {regular, overtime, double, night, pto}
        for i = 1, 5 do totals[i] = totals[i] + parts[i] end
    end
    local weekly_ot = math.max(0, totals[1] - 2400)
    totals[1] = totals[1] - weekly_ot
    totals[2] = totals[2] + weekly_ot
    return totals, weekly_ot
end

local function breakdown(payroll, employee, period)
    local first = weekly(payroll, employee, 2 * period - 1)
    local second = weekly(payroll, employee, 2 * period)
    local totals = {}
    for i = 1, 5 do totals[i] = first[i] + second[i] end
    return totals
end

local function calculate(payroll, employee, period)
    local stub = empty_totals()
    local settings, ytd = payroll.settings, employee.ytd
    if employee.kind == "HOURLY" then
        local values = breakdown(payroll, employee, period)
        for i, field in ipairs({"R", "O", "D", "N", "P"}) do stub[field] = values[i] end
        local weighted = 2 * (stub.R + stub.P) + 3 * stub.O + 4 * stub.D
        stub.earnings = (weighted * employee.base + 2 * stub.N * settings.NIGHT) // 120
    elseif employee.kind == "SALARIED" then
        if employee.active then
            stub.salary = employee.base // 26
            for day in pairs(employee.leave) do
                if period_of(day) == period and not payroll.holidays[day] then
                    stub.leave = stub.leave + 1
                end
            end
            stub.deduction = stub.leave * (employee.base // 260)
            stub.earnings = stub.salary - stub.deduction
        end
    else
        stub.sales = employee.sales[period] or 0
        stub.commission = progressive(payroll.tiers, stub.sales)
        stub.earnings = stub.commission + (employee.active and employee.base or 0)
    end

    stub.bonus = employee.bonus
    local gross = stub.earnings + stub.bonus
    if gross == 0 then return nil end
    stub.gross = gross
    local remaining = gross

    local function deduct(field, amount)
        stub[field] = math.min(amount, remaining)
        remaining = remaining - stub[field]
    end

    local retirement_room = math.max(0, settings.RETIRECAP - ytd.retirement)
    deduct("retirement", math.min(gross * employee.retirement // 10000, retirement_room))
    deduct("health", employee.health)
    stub.W = remaining
    local taxable = math.max(0, stub.earnings - stub.retirement - stub.health)
    local allowance_taxable = math.max(0, taxable - employee.allowances * settings.ALLOWANCE)
    deduct("federal", progressive(payroll.brackets, allowance_taxable) + employee.extra)
    deduct("supplemental", (stub.W - taxable) * settings.SUPP // 10000)
    deduct("state", stub.W * settings.STATE // 10000)

    local medicare_wages = gross - stub.health
    local social_wages = math.min(medicare_wages, math.max(0, settings.SSBASE - ytd.Y))
    local additional = math.max(0, math.min(medicare_wages,
                           ytd.F + medicare_wages - settings.ADDBASE))
    stub.F, stub.Y = medicare_wages, social_wages
    deduct("social", social_wages * settings.SSRATE // 10000)
    deduct("medicare", medicare_wages * settings.MEDRATE // 10000 +
                      additional * settings.ADDMED // 10000)

    local disposable = remaining
    local cap = disposable * settings.GARNCAP // 10000
    local balances = {}
    local garnishment = 0
    for _, order in ipairs(employee.garnishments) do
        local rate, balance = order[1], order[2]
        local taken = math.min(disposable * rate // 10000, balance, cap - garnishment)
        garnishment = garnishment + taken
        balances[#balances + 1] = balance - taken
    end
    stub.garnishment = garnishment
    stub.garnishment_balance = 0
    for _, balance in ipairs(balances) do
        stub.garnishment_balance = stub.garnishment_balance + balance
    end
    stub.net = remaining - garnishment
    stub.employer_social = social_wages * settings.SSRATE // 10000
    stub.employer_medicare = medicare_wages * settings.MEDRATE // 10000
    stub.J = math.min(medicare_wages, math.max(0, settings.UIBASE - ytd.J))
    stub.unemployment = stub.J * settings.UIRATE // 10000
    local match_eligible = math.min(stub.retirement, gross * settings.MATCHMAX // 10000)
    stub.match = match_eligible * settings.MATCH // 10000
    stub.employer = stub.employer_social + stub.employer_medicare +
                    stub.unemployment + stub.match
    if employee.kind == "HOURLY" then
        stub.accrued = math.min(960 - employee.pto_balance,
                               (stub.R + stub.O + stub.D) // 20)
    end
    stub.pto_balance = employee.pto_balance + stub.accrued
    return stub, balances
end

local function hours_parts(values)
    local parts = {}
    local names = {"reg", "ot", "dbl", "night", "pto"}
    for i = 1, 5 do
        parts[#parts + 1] = names[i]
        parts[#parts + 1] = duration(values[i])
    end
    return parts
end

local function stub_block(payroll, employee, stub, indent)
    if employee.kind == "HOURLY" then
        local values = {}
        for _, field in ipairs({"R", "O", "D", "N", "P"}) do
            values[#values + 1] = stub[field]
        end
        emit(payroll, indent, "hours", table.unpack(hours_parts(values)))
        emit(payroll, indent, "pto", "accrued", duration(stub.accrued),
             "balance", duration(stub.pto_balance))
    elseif employee.kind == "SALARIED" then
        emit(payroll, indent, "salary", money(stub.salary), "leave", stub.leave,
             "deduction", money(stub.deduction))
    else
        emit(payroll, indent, "sales", money(stub.sales),
             "commission", money(stub.commission))
    end
    for _, field in ipairs({
        "earnings", "bonus", "gross", "retirement", "health",
        "federal", "supplemental", "state", "social", "medicare"
    }) do
        emit(payroll, indent, field == "social" and "social-security" or field,
             money(stub[field]))
    end
    emit(payroll, indent, "garnishment", money(stub.garnishment),
         "balance", money(stub.garnishment_balance))
    emit(payroll, indent, "net", money(stub.net))
    emit(payroll, indent, "employer", "social-security", money(stub.employer_social),
         "medicare", money(stub.employer_medicare),
         "unemployment", money(stub.unemployment), "match", money(stub.match))
end

local function print_stub(payroll, employee, period, stub, department)
    emit(payroll, 2, "STUB", employee.id, department, employee.kind, "period", period)
    stub_block(payroll, employee, stub, 4)
end

local function show_hours(payroll, employee, period)
    emit(payroll, 0, "HOURS", employee.id, "period", period)
    local found = false
    for day = 14 * period - 13, 14 * period do
        local shifts = employee.shifts[day] or {}
        if #shifts > 0 or employee.pto[day] then
            local sorted = {}
            for _, shift in ipairs(shifts) do sorted[#sorted + 1] = shift end
            table.sort(sorted, function(a, b) return a[1] < b[1] end)
            local worked, regular, overtime, double, night, pto = daily(payroll, employee, day)
            local parts = {"day", day, weekday(day)}
            if payroll.holidays[day] then parts[#parts + 1] = "holiday" end
            for _, shift in ipairs(sorted) do
                parts[#parts + 1] = clock(shift[1]) .. "-" .. clock(shift[2])
            end
            parts[#parts + 1] = "total"
            parts[#parts + 1] = duration(worked)
            local more = hours_parts({regular, overtime, double, night, pto})
            for _, part in ipairs(more) do parts[#parts + 1] = part end
            emit(payroll, 2, table.unpack(parts))
            found = true
        end
    end
    if not found then emit(payroll, 2, "(none)") end
    for _, week in ipairs({2 * period - 1, 2 * period}) do
        local values, overtime = weekly(payroll, employee, week)
        local parts = {"week", week}
        for _, item in ipairs(hours_parts(values)) do parts[#parts + 1] = item end
        parts[#parts + 1] = "weekly-ot"
        parts[#parts + 1] = duration(overtime)
        emit(payroll, 2, table.unpack(parts))
    end
    emit(payroll, 2, "total", table.unpack(hours_parts(breakdown(payroll, employee, period))))
end

local function run(payroll, period)
    payroll.closed = period
    emit(payroll, 0, "RUN", period, "days", (14 * period - 13) .. "-" .. (14 * period))
    local paid, skipped, stubs = 0, 0, {}
    for _, id in ipairs(sorted_keys(payroll.employees)) do
        local employee = payroll.employees[id]
        local stub, balances = calculate(payroll, employee, period)
        if not stub then
            if employee.active then skipped = skipped + 1 end
        else
            print_stub(payroll, employee, period, stub, employee.department)
            employee.bonus = 0
            employee.pto_balance = stub.pto_balance
            for i, balance in ipairs(balances) do employee.garnishments[i][2] = balance end
            for _, field in ipairs(fields) do
                employee.ytd[field] = employee.ytd[field] + stub[field]
            end
            employee.periods = employee.periods + 1
            employee.stubs[period] = {stub = stub, department = employee.department}
            stubs[#stubs + 1] = stub
            paid = paid + 1
        end
    end
    local total = sum_stubs(stubs)
    emit(payroll, 2, "TOTAL", "paid", paid, "skipped", skipped,
         "gross", money(total.gross), "deductions", money(total.gross - total.net),
         "net", money(total.net), "employer", money(total.employer))
end

local function journal(payroll, period)
    local stubs = {}
    for _, employee in pairs(payroll.employees) do
        if employee.stubs[period] then
            stubs[#stubs + 1] = employee.stubs[period].stub
        end
    end
    local total = sum_stubs(stubs)
    local rows = {
        {"debit", "wages", total.gross},
        {"debit", "employer-tax", total.employer_social + total.employer_medicare + total.unemployment},
        {"debit", "retirement-match", total.match},
        {"credit", "retirement", total.retirement + total.match},
        {"credit", "health", total.health},
        {"credit", "federal", total.federal + total.supplemental},
        {"credit", "state", total.state},
        {"credit", "fica", total.social + total.medicare + total.employer_social + total.employer_medicare},
        {"credit", "unemployment", total.unemployment},
        {"credit", "garnishment", total.garnishment},
        {"credit", "net-pay", total.net}
    }
    emit(payroll, 0, "JOURNAL", period, "stubs", #stubs)
    local debit, credit = 0, 0
    for _, row in ipairs(rows) do
        emit(payroll, 2, row[1], row[2], money(row[3]))
        if row[1] == "debit" then debit = debit + row[3]
        else credit = credit + row[3] end
    end
    emit(payroll, 2, "total", "debit", money(debit), "credit", money(credit))
end

local function report_line(payroll, department, stubs)
    local total = sum_stubs(stubs)
    local taxes = total.federal + total.supplemental +
                  total.state + total.social + total.medicare
    emit(payroll, 2, department, "stubs", #stubs, "gross", money(total.gross),
         "pretax", money(total.retirement + total.health), "taxes", money(taxes),
         "garnishment", money(total.garnishment), "net", money(total.net),
         "employer", money(total.employer))
end

local function execute_command(payroll, command, a)
    if command == "SET" then
        local name = a[1]
        if not payroll.settings[name] then fail("unknown setting " .. name) end
        local value = rate_settings[name] and rate_check(a[2]) or cents(a[2])
        local format = rate_settings[name] and rate_text or money
        local previous = payroll.settings[name]
        payroll.settings[name] = value
        emit(payroll, 0, "SET", name, format(previous), "->", format(value))
    elseif command == "BRACKET" or command == "TIER" then
        local rate = rate_check(a[2])
        local tab = command == "BRACKET" and payroll.brackets or payroll.tiers
        local lower = cents(a[1])
        local action = tab[lower] and "replaced" or "added"
        tab[lower] = rate
        emit(payroll, 0, command, money(lower), rate_text(rate), action)
    elseif command == "EMP" then
        local id = tonumber(a[1])
        if payroll.employees[id] then fail("duplicate employee " .. a[1]) end
        local base = amount_check(a[4])
        payroll.employees[id] = new_employee(id, a[2], a[3], base)
        emit(payroll, 0, "EMP", id, a[2], a[3], money(base))
    elseif command == "RATE" or command == "DEPT" or command == "BENEFIT" or
           command == "W4" or command == "GARNISH" or command == "TERM" or
           command == "BONUS" then
        local employee = employee_of(payroll, a[1], true)
        if command == "RATE" then
            local base = amount_check(a[2])
            local previous = employee.base
            employee.base = base
            emit(payroll, 0, "RATE", employee.id, money(previous), "->", money(base))
        elseif command == "DEPT" then
            if a[2] == employee.department then fail("same department " .. a[2]) end
            local previous = employee.department
            employee.department = a[2]
            emit(payroll, 0, "DEPT", employee.id, previous, "->", a[2])
        elseif command == "BENEFIT" then
            employee.retirement = rate_check(a[2])
            employee.health = cents(a[3])
            emit(payroll, 0, "BENEFIT", employee.id, "retirement",
                 rate_text(employee.retirement), "health", money(employee.health))
        elseif command == "W4" then
            employee.allowances = tonumber(a[2])
            employee.extra = cents(a[3])
            emit(payroll, 0, "W4", employee.id, "allowances", employee.allowances,
                 "extra", money(employee.extra))
        elseif command == "GARNISH" then
            local rate = rate_check(a[2])
            local balance = amount_check(a[3])
            employee.garnishments[#employee.garnishments + 1] = {rate, balance}
            emit(payroll, 0, "GARNISH", employee.id, "order", #employee.garnishments,
                 rate_text(rate), "balance", money(balance))
        elseif command == "TERM" then
            employee.active = false
            emit(payroll, 0, "TERM", employee.id)
        else
            local amount = amount_check(a[2])
            employee.bonus = employee.bonus + amount
            emit(payroll, 0, "BONUS", employee.id, money(amount),
                 "pending", money(employee.bonus))
        end
    elseif command == "HOLIDAY" then
        local day = day_check(payroll, a[1])
        if payroll.holidays[day] then fail("duplicate holiday " .. a[1]) end
        payroll.holidays[day] = true
        emit(payroll, 0, "HOLIDAY", day, weekday(day))
    elseif command == "TIME" or command == "UNTIME" or command == "PTO" or
           command == "LEAVE" or command == "SALES" then
        local kind = command == "LEAVE" and "SALARIED" or
                     command == "SALES" and "COMMISSION" or "HOURLY"
        local employee = employee_of(payroll, a[1], true, kind)
        local day = day_check(payroll, a[2])
        if command == "TIME" then
            local start_time, end_time = time_check(a[3]), time_check(a[4])
            if start_time >= end_time then fail("invalid shift " .. a[3] .. "-" .. a[4]) end
            local shifts = employee.shifts[day] or {}
            table.sort(shifts, function(x, y) return x[1] < y[1] end)
            local total = 0
            for _, shift in ipairs(shifts) do
                if start_time < shift[2] and shift[1] < end_time then
                    fail("overlapping shift " .. clock(shift[1]) .. "-" .. clock(shift[2]))
                end
                total = total + shift[2] - shift[1]
            end
            if total + end_time - start_time > 960 then
                fail("daily limit " .. a[1] .. " " .. a[2])
            end
            shifts[#shifts + 1] = {start_time, end_time}
            employee.shifts[day] = shifts
            emit(payroll, 0, "TIME", employee.id, "day", day,
                 clock(start_time) .. "-" .. clock(end_time), duration(end_time - start_time))
        elseif command == "UNTIME" then
            local start_time = time_check(a[3])
            local shifts = employee.shifts[day] or {}
            local found
            for i, shift in ipairs(shifts) do
                if shift[1] == start_time then found = i; break end
            end
            if not found then fail("no shift " .. a[1] .. " " .. a[2] .. " " .. a[3]) end
            local shift = table.remove(shifts, found)
            emit(payroll, 0, "UNTIME", employee.id, "day", day,
                 clock(shift[1]) .. "-" .. clock(shift[2]))
        elseif command == "PTO" then
            local hour, minute = a[3]:match("^(%d%d):(%d%d)$")
            hour, minute = tonumber(hour), tonumber(minute)
            local length = hour * 60 + minute
            if minute > 59 or length < 1 or length > 480 then
                fail("invalid duration " .. a[3])
            end
            if employee.pto[day] then fail("duplicate pto " .. a[1] .. " " .. a[2]) end
            if length > employee.pto_balance then
                fail("insufficient pto " .. a[1] .. " " .. duration(employee.pto_balance))
            end
            employee.pto[day] = length
            employee.pto_balance = employee.pto_balance - length
            emit(payroll, 0, "PTO", employee.id, "day", day, duration(length),
                 "balance", duration(employee.pto_balance))
        elseif command == "LEAVE" then
            if day % 7 == 0 or day % 7 == 6 or payroll.holidays[day] then
                fail("not workday " .. a[2])
            end
            if employee.leave[day] then fail("duplicate leave " .. a[1] .. " " .. a[2]) end
            employee.leave[day] = true
            emit(payroll, 0, "LEAVE", employee.id, "day", day, weekday(day))
        else
            local amount = amount_check(a[3])
            local period = period_of(day)
            employee.sales[period] = (employee.sales[period] or 0) + amount
            emit(payroll, 0, "SALES", employee.id, "day", day, money(amount),
                 "period", period, "total", money(employee.sales[period]))
        end
    elseif command == "HOURS" then
        local employee = employee_of(payroll, a[1], false, "HOURLY")
        show_hours(payroll, employee, period_check(a[2]))
    elseif command == "RUN" then
        local period = tonumber(a[1])
        if period ~= payroll.closed + 1 or period > 26 then
            fail("invalid period " .. a[1])
        end
        run(payroll, period)
    elseif command == "PREVIEW" then
        local employee = employee_of(payroll, a[1])
        local period = payroll.closed + 1
        local stub = calculate(payroll, employee, period)
        emit(payroll, 0, "PREVIEW", employee.id, "period", period)
        if not stub then
            emit(payroll, 2, "no pay")
        else
            print_stub(payroll, employee, period, stub, employee.department)
        end
    elseif command == "REPRINT" then
        local employee = employee_of(payroll, a[1])
        local period = period_check(a[2])
        if not employee.stubs[period] then fail("no stub " .. a[1] .. " " .. a[2]) end
        local entry = employee.stubs[period]
        emit(payroll, 0, "REPRINT", employee.id, period)
        print_stub(payroll, employee, period, entry.stub, entry.department)
    elseif command == "YTD" then
        local employee = employee_of(payroll, a[1])
        emit(payroll, 0, "YTD", employee.id, employee.department, employee.kind,
             employee.active and "active" or "terminated", "periods", employee.periods)
        local totals = {}
        for key, value in pairs(employee.ytd) do totals[key] = value end
        totals.pto_balance = employee.pto_balance
        totals.garnishment_balance = garnish_balance(employee)
        stub_block(payroll, employee, totals, 2)
        emit(payroll, 2, "wages", "federal", money(totals.W),
             "social-security", money(totals.Y),
             "medicare", money(totals.F), "unemployment", money(totals.J))
        emit(payroll, 2, "retirement-room",
             money(math.max(0, payroll.settings.RETIRECAP - totals.retirement)),
             "pending-bonus", money(employee.bonus))
    elseif command == "JOURNAL" then
        local period = tonumber(a[1])
        if period < 1 or period > payroll.closed then fail("no run " .. a[1]) end
        journal(payroll, period)
    elseif command == "REPORT" then
        local departments, all_stubs = {}, {}
        for _, employee in pairs(payroll.employees) do
            for _, entry in pairs(employee.stubs) do
                local name = entry.department
                if not departments[name] then departments[name] = {} end
                departments[name][#departments[name] + 1] = entry.stub
                all_stubs[#all_stubs + 1] = entry.stub
            end
        end
        emit(payroll, 0, "REPORT", "period", payroll.closed)
        for _, name in ipairs(sorted_keys(departments)) do
            report_line(payroll, name, departments[name])
        end
        report_line(payroll, "total", all_stubs)
    elseif command == "TOP" then
        local k = tonumber(a[1])
        local employees = {}
        for _, employee in pairs(payroll.employees) do
            if employee.periods > 0 then employees[#employees + 1] = employee end
        end
        table.sort(employees, function(x, y)
            if x.ytd.gross ~= y.ytd.gross then return x.ytd.gross > y.ytd.gross end
            return x.id < y.id
        end)
        emit(payroll, 0, "TOP", k)
        for i = 1, math.min(k, #employees) do
            local employee = employees[i]
            emit(payroll, 2, i, employee.id, employee.department,
                 "gross", money(employee.ytd.gross), "net", money(employee.ytd.net))
        end
        if #employees == 0 then emit(payroll, 2, "(none)") end
    elseif command == "EMPLOYEES" then
        emit(payroll, 0, "EMPLOYEES")
        local ids = sorted_keys(payroll.employees)
        for _, id in ipairs(ids) do
            local employee = payroll.employees[id]
            emit(payroll, 2, id, employee.department, employee.kind,
                 money(employee.base), employee.active and "active" or "terminated",
                 "retirement", rate_text(employee.retirement), "health", money(employee.health),
                 "allowances", employee.allowances, "extra", money(employee.extra),
                 "bonus", money(employee.bonus))
            for i, order in ipairs(employee.garnishments) do
                emit(payroll, 4, "garnish", i, rate_text(order[1]), "balance", money(order[2]))
            end
        end
        if #ids == 0 then emit(payroll, 2, "(none)") end
    elseif command == "CONFIG" then
        emit(payroll, 0, "CONFIG")
        for _, name in ipairs(setting_order) do
            local value = payroll.settings[name]
            emit(payroll, 2, name, rate_settings[name] and rate_text(value) or money(value))
        end
        for _, entry in ipairs({
            {"bracket", payroll.brackets}, {"tier", payroll.tiers}
        }) do
            for _, lower in ipairs(sorted_keys(entry[2])) do
                emit(payroll, 2, entry[1], money(lower), rate_text(entry[2][lower]))
            end
        end
    end
end

local payroll = new_payroll()
local count = tonumber(io.read("*l"))
for _ = 1, count do
    local line = io.read("*l")
    local words = {}
    for token in line:gmatch("%S+") do words[#words + 1] = token end
    local command = words[1]
    local args = {}
    for i = 2, #words do args[#args + 1] = words[i] end
    local ok, reason = pcall(execute_command, payroll, command, args)
    if not ok then
        if type(reason) == "table" and reason.payroll_error then
            emit(payroll, 0, "ERROR", reason.payroll_error)
        else
            error(reason)
        end
    end
end
io.write(table.concat(payroll.output, "\n"), "\n")
