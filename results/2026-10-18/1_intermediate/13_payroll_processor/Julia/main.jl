using Printf

const RATE_SETTINGS = Set([
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
])
const SETTING_ORDER = [
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP",
    "SSBASE", "ADDBASE", "UIBASE", "RETIRECAP", "ALLOWANCE", "NIGHT"
]
const INITIAL_SETTINGS = Dict{String, Int64}(
    "STATE" => 500, "SUPP" => 2200, "SSRATE" => 620,
    "MEDRATE" => 145, "ADDMED" => 90, "UIRATE" => 270,
    "MATCH" => 5000, "MATCHMAX" => 600, "GARNCAP" => 2500,
    "SSBASE" => 16860000, "ADDBASE" => 20000000,
    "UIBASE" => 700000, "RETIRECAP" => 2300000,
    "ALLOWANCE" => 15000, "NIGHT" => 100
)
const FIELDS = [
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement",
    "health", "federal", "supplemental", "state", "social", "medicare",
    "garnishment", "net", "employer_social", "employer_medicare",
    "unemployment", "match", "employer", "W", "Y", "F", "J"
]
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

struct CommandError <: Exception
    message::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.message)
fail(reason::String) = throw(CommandError(reason))

cents(text::String) = begin
    whole, fraction = split(text, '.')
    parse(Int64, whole) * 100 + parse(Int64, fraction)
end

money(value::Integer) = @sprintf("%d.%02d", div(value, 100), mod(value, 100))
rate_text(value::Integer) = money(value) * "%"
duration(value::Integer) = @sprintf("%d:%02d", div(value, 60), mod(value, 60))
clock(value::Integer) = @sprintf("%02d:%02d", div(value, 60), mod(value, 60))
weekday(day::Int) = WEEKDAYS[mod(day - 1, 7) + 1]
period_of(day::Int) = div(day - 1, 14) + 1
empty_totals() = Dict(field => Int64(0) for field in FIELDS)

function sum_stubs(stubs)
    total = empty_totals()
    for stub in stubs, field in FIELDS
        total[field] += stub[field]
    end
    total
end

function progressive(brackets::Dict{Int64, Int64}, amount::Int64)
    limits = sort(collect(keys(brackets)))
    numerator = Int64(0)
    for (i, lower) in enumerate(limits)
        lower >= amount && break
        upper = i < length(limits) ? limits[i+1] : amount
        numerator += brackets[lower] * (min(amount, upper) - lower)
    end
    div(numerator, 10000)
end

mutable struct Garnishment
    rate::Int64
    balance::Int64
end

mutable struct Employee
    id::Int
    department::String
    kind::String
    base::Int64
    active::Bool
    retirement::Int64
    health::Int64
    allowances::Int
    extra::Int64
    garnishments::Vector{Garnishment}
    bonus::Int64
    pto_balance::Int64
    shifts::Dict{Int, Vector{Tuple{Int, Int}}}
    pto::Dict{Int, Int}
    leave::Set{Int}
    sales::Dict{Int, Int64}
    stubs::Dict{Int, Tuple{Dict{String, Int64}, String}}
    ytd::Dict{String, Int64}
    periods::Int
end

Employee(id::Int, department::String, kind::String, base::Int64) = Employee(
    id, department, kind, base, true, 0, 0, 0, 0,
    Garnishment[], 0, 0,
    Dict{Int, Vector{Tuple{Int, Int}}}(),
    Dict{Int, Int}(), Set{Int}(), Dict{Int, Int64}(),
    Dict{Int, Tuple{Dict{String, Int64}, String}}(), empty_totals(), 0
)

garnishment_balance(employee::Employee) =
    sum(order.balance for order in employee.garnishments; init=Int64(0))

mutable struct Payroll
    settings::Dict{String, Int64}
    brackets::Dict{Int64, Int64}
    tiers::Dict{Int64, Int64}
    holidays::Set{Int}
    employees::Dict{Int, Employee}
    closed::Int
    output::Vector{String}
end

Payroll() = Payroll(
    copy(INITIAL_SETTINGS), Dict{Int64, Int64}(), Dict{Int64, Int64}(),
    Set{Int}(), Dict{Int, Employee}(), 0, String[]
)

emit!(payroll::Payroll, indent::Int, parts...) =
    push!(payroll.output, repeat(" ", indent) * join(string.(parts), " "))

function employee_of(payroll::Payroll, text::String; active=false, kind=nothing)
    id = parse(Int, text)
    haskey(payroll.employees, id) || fail("unknown employee " * text)
    employee = payroll.employees[id]
    active && !employee.active && fail("terminated employee " * text)
    kind !== nothing && employee.kind != kind && fail("not " * lowercase(kind) * " " * text)
    employee
end

function day_check(payroll::Payroll, text::String)
    day = parse(Int, text)
    1 <= day <= 364 || fail("invalid day " * text)
    period = period_of(day)
    period <= payroll.closed && fail("period closed $period")
    day
end

function period_check(text::String)
    period = parse(Int, text)
    1 <= period <= 26 || fail("invalid period " * text)
    period
end

function rate_check(text::String)
    value = cents(text)
    value <= 10000 || fail("invalid rate " * text)
    value
end

function amount_check(text::String)
    value = cents(text)
    value > 0 || fail("invalid amount")
    value
end

function time_check(text::String)
    hours, minutes = parse.(Int, split(text, ':'))
    hours <= 23 && minutes <= 59 || fail("invalid time " * text)
    60 * hours + minutes
end

function daily(payroll::Payroll, employee::Employee, day::Int)
    worked = 0
    night = 0
    for (start_time, end_time) in get(employee.shifts, day, Tuple{Int, Int}[])
        worked += end_time - start_time
        night += max(0, min(end_time, 360) - start_time)
        night += max(0, end_time - max(start_time, 1320))
    end
    pto = get(employee.pto, day, 0)
    if day % 7 == 0 || day in payroll.holidays
        return worked, Int64[0, 0, worked, night, pto]
    end
    regular = min(worked, 480)
    overtime = min(max(worked - 480, 0), 240)
    double = max(worked - 720, 0)
    worked, Int64[regular, overtime, double, night, pto]
end

function weekly(payroll::Payroll, employee::Employee, week::Int)
    totals = zeros(Int64, 5)
    for day in (7 * week - 6):(7 * week)
        _, values = daily(payroll, employee, day)
        totals .+= values
    end
    extra = max(0, totals[1] - 2400)
    totals[1] -= extra
    totals[2] += extra
    totals, extra
end

function breakdown(payroll::Payroll, employee::Employee, period::Int)
    first, _ = weekly(payroll, employee, 2 * period - 1)
    second, _ = weekly(payroll, employee, 2 * period)
    first .+ second
end

function calculate(payroll::Payroll, employee::Employee, period::Int)
    stub = empty_totals()
    settings = payroll.settings
    ytd = employee.ytd

    if employee.kind == "HOURLY"
        values = breakdown(payroll, employee, period)
        for (field, value) in zip(("R", "O", "D", "N", "P"), values)
            stub[field] = value
        end
        weighted = 2 * (stub["R"] + stub["P"]) + 3 * stub["O"] + 4 * stub["D"]
        stub["earnings"] = div(weighted * employee.base + 2 * stub["N"] * settings["NIGHT"], 120)
    elseif employee.kind == "SALARIED"
        if employee.active
            stub["salary"] = div(employee.base, 26)
            stub["leave"] = count(day -> period_of(day) == period &&
                                         !(day in payroll.holidays), employee.leave)
            stub["deduction"] = stub["leave"] * div(employee.base, 260)
            stub["earnings"] = stub["salary"] - stub["deduction"]
        end
    else
        stub["sales"] = get(employee.sales, period, Int64(0))
        stub["commission"] = progressive(payroll.tiers, stub["sales"])
        stub["earnings"] = stub["commission"] + (employee.active ? employee.base : 0)
    end

    stub["bonus"] = employee.bonus
    gross = stub["earnings"] + stub["bonus"]
    gross == 0 && return nothing
    stub["gross"] = gross
    remaining = gross

    function deduct!(field::String, amount::Int64)
        stub[field] = min(amount, remaining)
        remaining -= stub[field]
    end

    retirement_room = max(0, settings["RETIRECAP"] - ytd["retirement"])
    deduct!("retirement", min(div(gross * employee.retirement, 10000), retirement_room))
    deduct!("health", employee.health)
    stub["W"] = remaining

    base_taxable = max(0, stub["earnings"] - stub["retirement"] - stub["health"])
    allowance_taxable = max(0, base_taxable - employee.allowances * settings["ALLOWANCE"])
    deduct!("federal", progressive(payroll.brackets, allowance_taxable) + employee.extra)
    deduct!("supplemental", div((stub["W"] - base_taxable) * settings["SUPP"], 10000))
    deduct!("state", div(stub["W"] * settings["STATE"], 10000))

    medicare_wages = gross - stub["health"]
    social_wages = min(medicare_wages, max(0, settings["SSBASE"] - ytd["Y"]))
    additional = max(0, min(medicare_wages, ytd["F"] + medicare_wages - settings["ADDBASE"]))
    stub["F"] = medicare_wages
    stub["Y"] = social_wages
    deduct!("social", div(social_wages * settings["SSRATE"], 10000))
    deduct!("medicare",
            div(medicare_wages * settings["MEDRATE"], 10000) +
            div(additional * settings["ADDMED"], 10000))

    disposable = remaining
    cap = div(disposable * settings["GARNCAP"], 10000)
    balances = Int64[]
    garnishment = Int64(0)
    for order in employee.garnishments
        taken = min(div(disposable * order.rate, 10000), order.balance, cap - garnishment)
        garnishment += taken
        push!(balances, order.balance - taken)
    end
    stub["garnishment"] = garnishment
    stub["garnishment_balance"] = sum(balances; init=Int64(0))
    stub["net"] = remaining - garnishment

    stub["employer_social"] = div(social_wages * settings["SSRATE"], 10000)
    stub["employer_medicare"] = div(medicare_wages * settings["MEDRATE"], 10000)
    stub["J"] = min(medicare_wages, max(0, settings["UIBASE"] - ytd["J"]))
    stub["unemployment"] = div(stub["J"] * settings["UIRATE"], 10000)
    match_eligible = min(stub["retirement"], div(gross * settings["MATCHMAX"], 10000))
    stub["match"] = div(match_eligible * settings["MATCH"], 10000)
    stub["employer"] = sum(stub[field] for field in (
        "employer_social", "employer_medicare", "unemployment", "match"
    ))

    if employee.kind == "HOURLY"
        stub["accrued"] = min(960 - employee.pto_balance,
                              div(stub["R"] + stub["O"] + stub["D"], 20))
    end
    stub["pto_balance"] = employee.pto_balance + stub["accrued"]
    stub, balances
end

function hours_parts(values)
    parts = Any[]
    for (label, value) in zip(("reg", "ot", "dbl", "night", "pto"), values)
        append!(parts, (label, duration(value)))
    end
    parts
end

function stub_block!(payroll::Payroll, employee::Employee,
                     stub::Dict{String, Int64}, indent::Int)
    if employee.kind == "HOURLY"
        values = [stub[field] for field in ("R", "O", "D", "N", "P")]
        emit!(payroll, indent, "hours", hours_parts(values)...)
        emit!(payroll, indent, "pto", "accrued", duration(stub["accrued"]),
              "balance", duration(stub["pto_balance"]))
    elseif employee.kind == "SALARIED"
        emit!(payroll, indent, "salary", money(stub["salary"]), "leave", stub["leave"],
              "deduction", money(stub["deduction"]))
    else
        emit!(payroll, indent, "sales", money(stub["sales"]),
              "commission", money(stub["commission"]))
    end

    for field in ("earnings", "bonus", "gross", "retirement", "health",
                  "federal", "supplemental", "state", "social", "medicare")
        label = field == "social" ? "social-security" : field
        emit!(payroll, indent, label, money(stub[field]))
    end
    emit!(payroll, indent, "garnishment", money(stub["garnishment"]),
          "balance", money(stub["garnishment_balance"]))
    emit!(payroll, indent, "net", money(stub["net"]))
    emit!(payroll, indent, "employer", "social-security", money(stub["employer_social"]),
          "medicare", money(stub["employer_medicare"]),
          "unemployment", money(stub["unemployment"]),
          "match", money(stub["match"]))
end

function print_stub!(payroll::Payroll, employee::Employee, period::Int,
                     stub::Dict{String, Int64}, department::String)
    emit!(payroll, 2, "STUB", employee.id, department, employee.kind, "period", period)
    stub_block!(payroll, employee, stub, 4)
end

function show_hours!(payroll::Payroll, employee::Employee, period::Int)
    emit!(payroll, 0, "HOURS", employee.id, "period", period)
    found = false
    for day in (14 * period - 13):(14 * period)
        shifts = sort(get(employee.shifts, day, Tuple{Int, Int}[]))
        isempty(shifts) && !haskey(employee.pto, day) && continue
        worked, values = daily(payroll, employee, day)
        parts = Any["day", day, weekday(day)]
        day in payroll.holidays && push!(parts, "holiday")
        for (first, last) in shifts
            push!(parts, clock(first) * "-" * clock(last))
        end
        append!(parts, ("total", duration(worked)))
        append!(parts, hours_parts(values))
        emit!(payroll, 2, parts...)
        found = true
    end
    !found && emit!(payroll, 2, "(none)")
    for week in (2 * period - 1, 2 * period)
        values, overtime = weekly(payroll, employee, week)
        emit!(payroll, 2, "week", week, hours_parts(values)...,
              "weekly-ot", duration(overtime))
    end
    emit!(payroll, 2, "total", hours_parts(breakdown(payroll, employee, period))...)
end

function run!(payroll::Payroll, period::Int)
    payroll.closed = period
    emit!(payroll, 0, "RUN", period, "days", "$(14*period-13)-$(14*period)")
    paid, skipped = 0, 0
    stubs = Dict{String, Int64}[]
    for id in sort(collect(keys(payroll.employees)))
        employee = payroll.employees[id]
        result = calculate(payroll, employee, period)
        if result === nothing
            skipped += employee.active
            continue
        end
        stub, balances = result
        print_stub!(payroll, employee, period, stub, employee.department)
        employee.bonus = 0
        employee.pto_balance = stub["pto_balance"]
        for (order, balance) in zip(employee.garnishments, balances)
            order.balance = balance
        end
        for field in FIELDS
            employee.ytd[field] += stub[field]
        end
        employee.periods += 1
        employee.stubs[period] = (stub, employee.department)
        push!(stubs, stub)
        paid += 1
    end
    total = sum_stubs(stubs)
    emit!(payroll, 2, "TOTAL", "paid", paid, "skipped", skipped,
          "gross", money(total["gross"]),
          "deductions", money(total["gross"] - total["net"]),
          "net", money(total["net"]), "employer", money(total["employer"]))
end

function journal!(payroll::Payroll, period::Int)
    stubs = [employee.stubs[period][1] for employee in values(payroll.employees)
             if haskey(employee.stubs, period)]
    totals = sum_stubs(stubs)
    rows = [
        ("debit", "wages", totals["gross"]),
        ("debit", "employer-tax", totals["employer_social"] +
             totals["employer_medicare"] + totals["unemployment"]),
        ("debit", "retirement-match", totals["match"]),
        ("credit", "retirement", totals["retirement"] + totals["match"]),
        ("credit", "health", totals["health"]),
        ("credit", "federal", totals["federal"] + totals["supplemental"]),
        ("credit", "state", totals["state"]),
        ("credit", "fica", totals["social"] + totals["medicare"] +
             totals["employer_social"] + totals["employer_medicare"]),
        ("credit", "unemployment", totals["unemployment"]),
        ("credit", "garnishment", totals["garnishment"]),
        ("credit", "net-pay", totals["net"])
    ]
    emit!(payroll, 0, "JOURNAL", period, "stubs", length(stubs))
    for (side, label, amount) in rows
        emit!(payroll, 2, side, label, money(amount))
    end
    emit!(payroll, 2, "total",
          "debit", money(sum(amount for (side, _, amount) in rows if side == "debit")),
          "credit", money(sum(amount for (side, _, amount) in rows if side == "credit")))
end

function report_line!(payroll::Payroll, department::String, stubs)
    entries = collect(stubs)
    totals = sum_stubs(entries)
    taxes = sum(totals[field] for field in (
        "federal", "supplemental", "state", "social", "medicare"
    ))
    emit!(payroll, 2, department, "stubs", length(entries),
          "gross", money(totals["gross"]),
          "pretax", money(totals["retirement"] + totals["health"]),
          "taxes", money(taxes), "garnishment", money(totals["garnishment"]),
          "net", money(totals["net"]), "employer", money(totals["employer"]))
end

function command!(payroll::Payroll, command::String, a::Vector{String})
    if command == "SET"
        name = a[1]
        haskey(payroll.settings, name) || fail("unknown setting " * name)
        value = name in RATE_SETTINGS ? rate_check(a[2]) : cents(a[2])
        format = name in RATE_SETTINGS ? rate_text : money
        previous = payroll.settings[name]
        payroll.settings[name] = value
        emit!(payroll, 0, "SET", name, format(previous), "->", format(value))

    elseif command in ("BRACKET", "TIER")
        rate = rate_check(a[2])
        table = command == "BRACKET" ? payroll.brackets : payroll.tiers
        lower = cents(a[1])
        action = haskey(table, lower) ? "replaced" : "added"
        table[lower] = rate
        emit!(payroll, 0, command, money(lower), rate_text(rate), action)

    elseif command == "EMP"
        id = parse(Int, a[1])
        haskey(payroll.employees, id) && fail("duplicate employee " * a[1])
        base = amount_check(a[4])
        payroll.employees[id] = Employee(id, a[2], a[3], base)
        emit!(payroll, 0, "EMP", id, a[2], a[3], money(base))

    elseif command in ("RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS")
        employee = employee_of(payroll, a[1]; active=true)
        if command == "RATE"
            base = amount_check(a[2])
            previous = employee.base
            employee.base = base
            emit!(payroll, 0, "RATE", employee.id, money(previous), "->", money(base))
        elseif command == "DEPT"
            a[2] == employee.department && fail("same department " * a[2])
            previous = employee.department
            employee.department = a[2]
            emit!(payroll, 0, "DEPT", employee.id, previous, "->", a[2])
        elseif command == "BENEFIT"
            rate = rate_check(a[2])
            employee.retirement = rate
            employee.health = cents(a[3])
            emit!(payroll, 0, "BENEFIT", employee.id, "retirement",
                  rate_text(rate), "health", money(employee.health))
        elseif command == "W4"
            employee.allowances = parse(Int, a[2])
            employee.extra = cents(a[3])
            emit!(payroll, 0, "W4", employee.id, "allowances", employee.allowances,
                  "extra", money(employee.extra))
        elseif command == "GARNISH"
            rate = rate_check(a[2])
            amount = amount_check(a[3])
            push!(employee.garnishments, Garnishment(rate, amount))
            emit!(payroll, 0, "GARNISH", employee.id, "order", length(employee.garnishments),
                  rate_text(rate), "balance", money(amount))
        elseif command == "TERM"
            employee.active = false
            emit!(payroll, 0, "TERM", employee.id)
        else
            amount = amount_check(a[2])
            employee.bonus += amount
            emit!(payroll, 0, "BONUS", employee.id, money(amount),
                  "pending", money(employee.bonus))
        end

    elseif command == "HOLIDAY"
        day = day_check(payroll, a[1])
        day in payroll.holidays && fail("duplicate holiday " * a[1])
        push!(payroll.holidays, day)
        emit!(payroll, 0, "HOLIDAY", day, weekday(day))

    elseif command in ("TIME", "UNTIME", "PTO", "LEAVE", "SALES")
        kind = command == "LEAVE" ? "SALARIED" :
               command == "SALES" ? "COMMISSION" : "HOURLY"
        employee = employee_of(payroll, a[1]; active=true, kind=kind)
        day = day_check(payroll, a[2])
        if command == "TIME"
            first = time_check(a[3])
            last = time_check(a[4])
            first < last || fail("invalid shift $(a[3])-$(a[4])")
            shifts = sort(get(employee.shifts, day, Tuple{Int, Int}[]))
            for (previous_first, previous_last) in shifts
                if first < previous_last && previous_first < last
                    fail("overlapping shift $(clock(previous_first))-$(clock(previous_last))")
                end
            end
            sum(last - first for (first, last) in shifts; init=0) + last - first <= 960 ||
                fail("daily limit $(a[1]) $(a[2])")
            push!(get!(employee.shifts, day, Tuple{Int, Int}[]), (first, last))
            emit!(payroll, 0, "TIME", employee.id, "day", day,
                  "$(clock(first))-$(clock(last))", duration(last - first))

        elseif command == "UNTIME"
            start_time = time_check(a[3])
            shifts = get(employee.shifts, day, Tuple{Int, Int}[])
            position = findfirst(shift -> shift[1] == start_time, shifts)
            position === nothing && fail("no shift $(a[1]) $(a[2]) $(a[3])")
            first, last = shifts[position]
            deleteat!(shifts, position)
            emit!(payroll, 0, "UNTIME", employee.id, "day", day,
                  "$(clock(first))-$(clock(last))")

        elseif command == "PTO"
            hours, minutes = parse.(Int, split(a[3], ':'))
            duration_minutes = 60 * hours + minutes
            minutes <= 59 && 1 <= duration_minutes <= 480 ||
                fail("invalid duration " * a[3])
            haskey(employee.pto, day) && fail("duplicate pto $(a[1]) $(a[2])")
            duration_minutes <= employee.pto_balance ||
                fail("insufficient pto $(a[1]) $(duration(employee.pto_balance))")
            employee.pto[day] = duration_minutes
            employee.pto_balance -= duration_minutes
            emit!(payroll, 0, "PTO", employee.id, "day", day,
                  duration(duration_minutes), "balance", duration(employee.pto_balance))

        elseif command == "LEAVE"
            if day % 7 in (0, 6) || day in payroll.holidays
                fail("not workday " * a[2])
            end
            day in employee.leave && fail("duplicate leave $(a[1]) $(a[2])")
            push!(employee.leave, day)
            emit!(payroll, 0, "LEAVE", employee.id, "day", day, weekday(day))

        else
            amount = amount_check(a[3])
            period = period_of(day)
            employee.sales[period] = get(employee.sales, period, Int64(0)) + amount
            emit!(payroll, 0, "SALES", employee.id, "day", day, money(amount),
                  "period", period, "total", money(employee.sales[period]))
        end

    elseif command == "HOURS"
        employee = employee_of(payroll, a[1]; kind="HOURLY")
        show_hours!(payroll, employee, period_check(a[2]))

    elseif command == "RUN"
        period = parse(Int, a[1])
        period == payroll.closed + 1 && period <= 26 ||
            fail("invalid period " * a[1])
        run!(payroll, period)

    elseif command == "PREVIEW"
        employee = employee_of(payroll, a[1])
        period = payroll.closed + 1
        result = calculate(payroll, employee, period)
        emit!(payroll, 0, "PREVIEW", employee.id, "period", period)
        if result === nothing
            emit!(payroll, 2, "no pay")
        else
            print_stub!(payroll, employee, period, result[1], employee.department)
        end

    elseif command == "REPRINT"
        employee = employee_of(payroll, a[1])
        period = period_check(a[2])
        haskey(employee.stubs, period) || fail("no stub $(a[1]) $(a[2])")
        stub, department = employee.stubs[period]
        emit!(payroll, 0, "REPRINT", employee.id, period)
        print_stub!(payroll, employee, period, stub, department)

    elseif command == "YTD"
        employee = employee_of(payroll, a[1])
        emit!(payroll, 0, "YTD", employee.id, employee.department, employee.kind,
              employee.active ? "active" : "terminated", "periods", employee.periods)
        totals = copy(employee.ytd)
        totals["pto_balance"] = employee.pto_balance
        totals["garnishment_balance"] = garnishment_balance(employee)
        stub_block!(payroll, employee, totals, 2)
        emit!(payroll, 2, "wages", "federal", money(totals["W"]),
              "social-security", money(totals["Y"]),
              "medicare", money(totals["F"]), "unemployment", money(totals["J"]))
        emit!(payroll, 2, "retirement-room",
              money(max(0, payroll.settings["RETIRECAP"] - totals["retirement"])),
              "pending-bonus", money(employee.bonus))

    elseif command == "JOURNAL"
        period = parse(Int, a[1])
        1 <= period <= payroll.closed || fail("no run " * a[1])
        journal!(payroll, period)

    elseif command == "REPORT"
        departments = Dict{String, Vector{Dict{String, Int64}}}()
        all_stubs = Dict{String, Int64}[]
        for employee in values(payroll.employees)
            for (stub, department) in values(employee.stubs)
                push!(get!(departments, department, Dict{String, Int64}[]), stub)
                push!(all_stubs, stub)
            end
        end
        emit!(payroll, 0, "REPORT", "period", payroll.closed)
        for department in sort(collect(keys(departments)))
            report_line!(payroll, department, departments[department])
        end
        report_line!(payroll, "total", all_stubs)

    elseif command == "TOP"
        count = parse(Int, a[1])
        ranked = sort([employee for employee in values(payroll.employees)
                       if employee.periods > 0];
                      by=employee -> (-employee.ytd["gross"], employee.id))
        emit!(payroll, 0, "TOP", count)
        for (position, employee) in enumerate(ranked[1:min(count, length(ranked))])
            emit!(payroll, 2, position, employee.id, employee.department,
                  "gross", money(employee.ytd["gross"]), "net", money(employee.ytd["net"]))
        end
        isempty(ranked) && emit!(payroll, 2, "(none)")

    elseif command == "EMPLOYEES"
        emit!(payroll, 0, "EMPLOYEES")
        for id in sort(collect(keys(payroll.employees)))
            employee = payroll.employees[id]
            emit!(payroll, 2, id, employee.department, employee.kind, money(employee.base),
                  employee.active ? "active" : "terminated",
                  "retirement", rate_text(employee.retirement),
                  "health", money(employee.health), "allowances", employee.allowances,
                  "extra", money(employee.extra), "bonus", money(employee.bonus))
            for (position, order) in enumerate(employee.garnishments)
                emit!(payroll, 4, "garnish", position, rate_text(order.rate),
                      "balance", money(order.balance))
            end
        end
        isempty(payroll.employees) && emit!(payroll, 2, "(none)")

    elseif command == "CONFIG"
        emit!(payroll, 0, "CONFIG")
        for name in SETTING_ORDER
            value = payroll.settings[name]
            emit!(payroll, 2, name, name in RATE_SETTINGS ? rate_text(value) : money(value))
        end
        for (label, table) in (("bracket", payroll.brackets), ("tier", payroll.tiers))
            for lower in sort(collect(keys(table)))
                emit!(payroll, 2, label, money(lower), rate_text(table[lower]))
            end
        end
    end
end

function execute!(payroll::Payroll, line::String)
    words = String.(split(line))
    command = first(words)
    try
        command!(payroll, command, words[2:end])
    catch error
        if error isa CommandError
            emit!(payroll, 0, "ERROR", error.message)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    payroll = Payroll()
    for _ in 1:count
        execute!(payroll, readline(stdin))
    end
    println(join(payroll.output, "\n"))
end

main()
