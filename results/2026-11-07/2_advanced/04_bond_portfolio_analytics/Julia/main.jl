include("dates_calendar.jl")
include("daycount.jl")
include("schedule.jl")
include("pricing.jl")
include("curve.jl")

const DC = DatesCalendar
const TYPES = ("FIXED", "ZERO", "AMORT", "FRN")
const FREQUENCIES = (1, 2, 4, 12)
const BUSINESS_RULES = ("FOLLOWING", "MODIFIED_FOLLOWING", "PRECEDING", "UNADJUSTED")
const BUCKETS = ("0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+")

struct InputFault <: Exception
    message::String
end

fail(message) = throw(InputFault(message))
rounded(numerator, denominator) = (2 * numerator + denominator) ÷ (2 * denominator)
thousandths(text) = parse(Int, replace(text, "." => ""))
hundredths(value) = (value < 0 ? "-" : "") * string(abs(value) ÷ 100) * "." * lpad(string(abs(value) % 100), 2, '0')

function decimals(value, digits)
    scale = 1
    for _ in 1:digits
        scale *= 10
    end
    magnitude = value < 0 ? -value : value
    integer = trunc(Int, magnitude * scale + 0.5)
    return (value < 0 && integer != 0 ? "-" : "") * string(integer ÷ scale) * "." * lpad(string(integer % scale), digits, '0')
end

percent(value) = decimals(value * 100, 4)
amount(value) = decimals(value / 100, 2)
rows(name) = [(number, String.(split(line, ','))) for (number, line) in enumerate(readlines(joinpath("input", name))) if number > 1]
record!(errors, file, number, key, fault) = push!(errors, "$file:$number: $key: $(fault.message)")

mutable struct Options
    eom::Bool
    long::Bool
    lag::Union{Nothing,Int}
    cap::Union{Nothing,Int}
    floor::Union{Nothing,Int}
    sinks::Vector{Tuple{String,Int}}
    calls::Vector{Tuple{String,Int}}
end

Options() = Options(false, false, nothing, nothing, nothing, Tuple{String,Int}[], Tuple{String,Int}[])

struct Period
    number::Int
    start::Int
    finish::Int
    payment::Int
    numerator::Int
    denominator::Int
    rate::Int
    opening::Int
    coupon::Int
    principal::Int
end

cashflow(period) = period.coupon + period.principal

mutable struct Bond
    code::String
    kind::String
    issue::Int
    maturity::Int
    coupon::Int
    frequency::Int
    daycount::String
    bdc::String
    face::Int
    options::Options
    schedule::Vector{Int}
    sinks::Dict{Int,Int}
    calls::Vector{Tuple{Int,Int}}
    periods::Vector{Period}
end

function parseoptions(kind, text)
    options = Options()
    seen = Set{String}()
    allowed = kind == "FIXED" ? ("EOM", "LONG", "CALL") : kind == "AMORT" ? ("EOM", "LONG", "SINK") : kind == "FRN" ? ("EOM", "LONG", "LAG", "CAP", "FLOOR") : ("EOM", "LONG")
    for item in text == "-" ? String[] : split(text, ';')
        pieces = split(item, '='; limit=2)
        key = String(pieces[1])
        (key ∉ allowed || key in seen && key ∉ ("SINK", "CALL")) && fail("invalid option")
        push!(seen, key)
        value = length(pieces) == 2 ? String(pieces[2]) : ""
        if key == "EOM"
            options.eom = true
        elseif key == "LONG"
            options.long = true
        elseif key == "LAG"
            options.lag = parse(Int, value)
        elseif key == "CAP"
            options.cap = parse(Int, value)
        elseif key == "FLOOR"
            options.floor = parse(Int, value)
        else
            date, number = String.(split(value, ':'))
            push!(key == "SINK" ? options.sinks : options.calls, (date, key == "SINK" ? parse(Int, number) : thousandths(number)))
        end
    end
    if kind == "FRN"
        cap = isnothing(options.cap) ? 1200 : options.cap
        (isnothing(options.lag) || !(1 <= options.lag <= 5) || cap > 1200 || !isnothing(options.floor) && options.floor > cap) && fail("invalid option")
    end
    return options
end

function scheduledays(items, schedule, message)
    days = Int[]
    for (text, _) in items
        !DC.valid(text) && fail(message)
        day = DC.parsedate(text)
        (day ∉ schedule[2:end - 1] || !isempty(days) && day <= last(days)) && fail(message)
        push!(days, day)
    end
    return days
end

function parsebond(fields, seen, calendar, fixings)
    code, kind, issue_text, maturity_text, coupon_text, frequency_text, convention, bdc, face_text, option_text = fields
    code in seen && fail("duplicate id")
    kind ∉ TYPES && fail("unknown type")
    (!DC.valid(issue_text) || !DC.valid(maturity_text)) && fail("invalid date")
    issue, maturity = DC.parsedate(issue_text), DC.parsedate(maturity_text)
    maturity <= issue && fail("maturity not after issue")
    coupon, frequency, face = parse(Int, coupon_text), parse(Int, frequency_text), parse(Int, face_text)
    frequency ∉ FREQUENCIES && fail("invalid frequency")
    convention ∉ Daycount.CONVENTIONS && fail("unknown day count")
    bdc ∉ BUSINESS_RULES && fail("unknown business day rule")
    (face % 100000 != 0 || face > 10000000) && fail("invalid face")
    (coupon > 1200 || kind == "ZERO" && coupon != 0) && fail("invalid coupon")
    options = parseoptions(kind, option_text)
    dates = Schedule.build(issue, maturity, frequency, options.eom, options.long)
    sinkdays = scheduledays(options.sinks, dates, "invalid sinking fund")
    total = 0
    for (_, cents) in options.sinks
        cents == 0 && fail("invalid sinking fund")
        total += cents
    end
    kind == "AMORT" && (total == 0 || total >= face) && fail("invalid sinking fund")
    sinks = Dict(day => value for (day, (_, value)) in zip(sinkdays, options.sinks))
    calldays = scheduledays(options.calls, dates, "invalid call schedule")
    any(entry -> !(100000 <= last(entry) <= 110000), options.calls) && fail("invalid call schedule")
    calls = [(day, value) for (day, (_, value)) in zip(calldays, options.calls)]
    periods = Period[]
    opening = face
    for i in 2:length(dates)
        start, finish = dates[i - 1], dates[i]
        rate = kind == "ZERO" ? 0 : coupon
        if kind == "FRN"
            fixing = DC.move(calendar, DC.adjust(calendar, start, bdc), -options.lag)
            found = findlast(entry -> first(entry) <= fixing, fixings)
            isnothing(found) && fail("missing fixing")
            rate = last(fixings[found]) + coupon
            !isnothing(options.floor) && (rate = max(rate, options.floor))
            !isnothing(options.cap) && (rate = min(rate, options.cap))
        end
        n, m = Daycount.fraction(convention, start, finish)
        principal = i == length(dates) ? opening : get(sinks, finish, 0)
        interest = rounded(opening * rate * n, 10000 * m)
        push!(periods, Period(i - 1, start, finish, DC.adjust(calendar, finish, bdc), n, m, rate, opening, interest, principal))
        opening -= principal
    end
    return Bond(code, kind, issue, maturity, coupon, frequency, convention, bdc, face, options, dates, sinks, calls, periods)
end

mutable struct Valuation
    bond::Bond
    clean::Int
    remaining::Vector{Period}
    cashflows::Vector{Period}
    flows::Vector{Tuple{Int,Float64}}
    outstanding::Int
    accrued::Float64
    accruedamount::Int
    cleanamount::Int
    unitvalue::Int
    target::Float64
    fraction::Float64
    pricer::Pricing.YieldPricer
    ytm::Float64
    ytw::Float64
    risk::Pricing.Risk
    workout::Int
    wal::Float64
    nextpayment::Int
    curveclean::Float64
    zspread::Float64
end

function Valuation(bond, clean, settlement)
    index = findfirst(period -> period.finish > settlement, bond.periods)
    remaining = bond.periods[index:end]
    current = first(remaining)
    outstanding = current.opening
    n, m = Daycount.fraction(bond.daycount, current.start, settlement)
    accrued = current.rate * n / (100 * m)
    accruedamount = rounded(outstanding * current.rate * n, 10000 * m)
    cleanamount = rounded(outstanding * clean, 100000)
    target = clean / 1000 + accrued
    n, m = Daycount.fraction(bond.daycount, settlement, current.finish)
    fraction = bond.frequency * n / m
    cashflows = filter(period -> cashflow(period) >= 1, remaining)
    flows = [(period.payment - settlement, Float64(cashflow(period))) for period in cashflows]
    pricer = Pricing.YieldPricer(cashflow.(remaining), fraction, bond.frequency, outstanding)
    return Valuation(bond, clean, remaining, cashflows, flows, outstanding, accrued, accruedamount, cleanamount,
        cleanamount + accruedamount, target, fraction, pricer, 0.0, 0.0, Pricing.Risk(0, 0, 0, 0), bond.maturity, 0.0, first(cashflows).payment, 0.0, 0.0)
end

function analyze!(value, curve, settlement)
    value.ytm = Pricing.solve(value.pricer, value.target)
    value.risk = Pricing.risk(value.pricer, value.ytm)
    value.ytw = value.ytm
    for (day, price) in value.bond.calls
        day <= settlement && continue
        flows = Int[]
        for period in value.remaining
            push!(flows, period.coupon)
            if period.finish == day
                flows[end] += rounded(period.opening * price, 100000)
                break
            end
        end
        rate = Pricing.solve(Pricing.YieldPricer(flows, value.fraction, value.bond.frequency, value.outstanding), value.target)
        if rate < value.ytw
            value.ytw, value.workout = rate, day
        end
    end
    principal_days = 0
    for period in value.cashflows
        principal_days += period.principal * (period.payment - settlement)
    end
    value.wal = principal_days / (365 * value.outstanding)
    value.curveclean = Curve.presentvalue(curve, value.flows) * 100 / value.outstanding - value.accrued
    value.zspread = Curve.zspread(curve, value.flows, value.unitvalue)
end

mutable struct Position
    valuation::Valuation
    units::Int
    book::Int
end

market(position) = position.units * position.valuation.unitvalue
positionface(position) = position.units * position.valuation.bond.face
outstanding(position) = position.units * position.valuation.outstanding
gain(position) = position.units * position.valuation.cleanamount - position.book
dv01(position) = position.valuation.risk.dv01 * position.units * position.valuation.outstanding / 10000
positionpv(position, curve) = position.units * Curve.presentvalue(curve, position.valuation.flows, position.valuation.zspread)
bucket(days) = days < 365 ? 1 : days < 1095 ? 2 : days < 1825 ? 3 : days < 3650 ? 4 : 5

struct Scenario
    name::String
    deltas::Vector{Float64}
end

function inputdata()
    valuation, settlement_days = 0, 0
    scenario_lines = Tuple{Int,String,Vector{Int}}[]
    limits = Vector{String}[]
    for (number, line) in enumerate(readlines("input/params.txt"))
        fields = String.(split(line, ' '))
        if fields[1] == "valuation_date"
            valuation = DC.parsedate(fields[2])
        elseif fields[1] == "settlement_days"
            settlement_days = parse(Int, fields[2])
        elseif fields[1] == "scenario"
            push!(scenario_lines, (number, fields[2], parse.(Int, fields[3:end])))
        else
            push!(limits, fields[2:end])
        end
    end
    calendar = DC.Calendar(Set(DC.parsedate.(readlines("input/calendar.txt"))))
    settlement = DC.move(calendar, valuation, settlement_days)
    fixings = [(DC.parsedate(fields[1]), parse(Int, fields[2])) for (_, fields) in rows("fixings.csv")]
    errors = String[]
    pillars, seen = Curve.Pillar[], Set{String}()
    for (number, fields) in rows("curve_quotes.csv")
        try
            fields[1] in seen && fail("duplicate pillar")
            !DC.valid(fields[1]) && fail("invalid date")
            maturity = DC.parsedate(fields[1])
            maturity <= settlement && fail("pillar not after settlement")
            frequency = parse(Int, fields[3])
            frequency ∉ FREQUENCIES && fail("invalid frequency")
            push!(pillars, Curve.Pillar(maturity, parse(Int, fields[2]), frequency))
        catch fault
            fault isa InputFault || rethrow()
            record!(errors, "curve_quotes.csv", number, fields[1], fault)
        end
        push!(seen, fields[1])
    end
    sort!(pillars; by=pillar -> pillar.maturity)
    scenarios = Scenario[]
    empty!(seen)
    for (number, name, shifts) in scenario_lines
        if name in seen
            record!(errors, "params.txt", number, name, InputFault("duplicate scenario"))
        elseif length(shifts) != length(pillars)
            record!(errors, "params.txt", number, name, InputFault("wrong number of shifts"))
        else
            push!(scenarios, Scenario(name, shifts .* 0.0001))
        end
        push!(seen, name)
    end
    bonds = Dict{String,Bond}()
    empty!(seen)
    for (number, fields) in rows("bonds.csv")
        try
            bond = parsebond(fields, seen, calendar, fixings)
            bonds[bond.code] = bond
        catch fault
            fault isa InputFault || rethrow()
            record!(errors, "bonds.csv", number, fields[1], fault)
        end
        push!(seen, fields[1])
    end
    values = Dict{String,Valuation}()
    empty!(seen)
    for (number, fields) in rows("prices.csv")
        code = fields[1]
        try
            !haskey(bonds, code) && fail("unknown bond")
            code in seen && fail("duplicate price")
            bond = bonds[code]
            !(bond.issue <= settlement < bond.maturity) && fail("not outstanding")
            value = Valuation(bond, thousandths(fields[2]), settlement)
            !(Pricing.dirty(value.pricer, 0.0) > value.target > Pricing.dirty(value.pricer, 1.0)) && fail("yield out of range")
            values[code] = value
        catch fault
            fault isa InputFault || rethrow()
            record!(errors, "prices.csv", number, code, fault)
        end
        push!(seen, code)
    end
    positions = Dict{Tuple{String,String},Position}()
    for (number, fields) in rows("holdings.csv")
        name, code = fields[1:2]
        try
            !haskey(bonds, code) && fail("unknown bond")
            !haskey(values, code) && fail("no price")
            face = parse(Int, fields[3])
            face % bonds[code].face != 0 && fail("invalid face")
            units = face ÷ bonds[code].face
            position = get!(positions, (name, code)) do
                Position(values[code], 0, 0)
            end
            position.units += units
            position.book += rounded(units * values[code].outstanding * thousandths(fields[4]), 100000)
        catch fault
            fault isa InputFault || rethrow()
            record!(errors, "holdings.csv", number, code, fault)
        end
    end
    return (; valuation, settlement, pillars, scenarios, bonds, values, positions, errors, limits)
end

function portfolio!(report, scenario_rows, compliance, name, positions, curve, scenarios, limits, settlement)
    totalvalue, totalface, totaloutstanding, totalbook, totalgain, income = 0, 0, 0, 0, 0, 0
    weighted = zeros(4)
    totaldv01 = 0.0
    flows = Tuple{Int,Float64}[]
    ladder = Dict{Int,Tuple{Int,Int}}()
    for position in positions
        value = position.valuation
        mv = market(position)
        totalvalue += mv
        totalface += positionface(position)
        totaloutstanding += outstanding(position)
        totalbook += position.book
        totalgain += gain(position)
        weighted[1] += mv * value.ytm
        weighted[2] += mv * value.risk.modified
        weighted[3] += mv * value.risk.convexity
        weighted[4] += mv * value.zspread
        totaldv01 += dv01(position)
        for period in value.cashflows
            days = period.payment - settlement
            push!(flows, (days, Float64(position.units * cashflow(period))))
            days <= 365 && (income += position.units * period.coupon)
            year = DC.civil(period.payment)[1]
            coupon, principal = get(ladder, year, (0, 0))
            ladder[year] = (coupon + position.units * period.coupon, principal + position.units * period.principal)
        end
    end
    weighted ./= totalvalue
    ytm, modified, convexity, zspread = weighted
    cashyield = Pricing.bisect(rate -> Curve.presentvalue(Curve.ZeroCurve([0], [rate]), flows), 0.0, 1.0, Float64(totalvalue))
    basevalues = [positionpv(position, curve) for position in positions]
    basevalue = 0.0
    for value in basevalues
        basevalue += value
    end
    function presentvalue(deltas)
        shifted = Curve.shifted(curve, deltas)
        total = 0.0
        for position in positions
            total += positionpv(position, shifted)
        end
        return total
    end
    function duration(pillar)
        down, up = zeros(length(curve.rates)), zeros(length(curve.rates))
        for i in eachindex(down)
            if pillar == 0 || pillar == i
                down[i], up[i] = -0.0001, 0.0001
            end
        end
        return (presentvalue(down) - presentvalue(up)) / (2 * 0.0001 * basevalue)
    end
    effective = duration(0)
    krd = [duration(i) for i in eachindex(curve.rates)]
    groupcounts, groupvalues = zeros(Int, 9), zeros(Int, 9)
    groupdurations, groupdv01 = zeros(9), zeros(9)
    push!(report, "portfolio $name")
    for position in positions
        value, bond = position.valuation, position.valuation.bond
        mv = market(position)
        push!(report, "position $(bond.code) face $(hundredths(positionface(position))) outstanding $(hundredths(outstanding(position))) clean $(decimals(value.clean / 1000, 6)) value $(hundredths(mv)) weight $(decimals(mv * 100 / totalvalue, 4)) book $(hundredths(position.book)) gain $(hundredths(gain(position))) ytm $(percent(value.ytm)) modified $(decimals(value.risk.modified, 4)) dv01 $(decimals(dv01(position), 2))")
        for index in (findfirst(==(bond.kind), TYPES), 4 + bucket(bond.maturity - settlement))
            groupcounts[index] += 1
            groupvalues[index] += mv
            groupdurations[index] += mv * value.risk.modified
            groupdv01[index] += dv01(position)
        end
    end
    push!(report, "total positions $(length(positions)) face $(hundredths(totalface)) outstanding $(hundredths(totaloutstanding)) value $(hundredths(totalvalue)) book $(hundredths(totalbook)) gain $(hundredths(totalgain)) income $(hundredths(income))")
    push!(report, "risk ytm $(percent(ytm)) yield $(percent(cashyield)) modified $(decimals(modified, 4)) convexity $(decimals(convexity, 4)) zspread $(percent(zspread)) dv01 $(decimals(totaldv01, 2))")
    push!(report, "curve effective $(decimals(effective, 4)) krd $(join((decimals(value, 4) for value in krd), " "))")
    for index in 1:9
        label, groupname = index <= 4 ? ("type", TYPES[index]) : ("bucket", BUCKETS[index - 4])
        push!(report, "$label $groupname positions $(groupcounts[index]) value $(hundredths(groupvalues[index])) weight $(decimals(groupvalues[index] * 100 / totalvalue, 4)) duration $(decimals(groupdurations[index] / totalvalue, 4)) dv01 $(decimals(groupdv01[index], 2))")
    end
    totalcoupon, totalprincipal = 0, 0
    for year in sort!(collect(keys(ladder)))
        coupon, principal = ladder[year]
        push!(report, "ladder $year coupon $(hundredths(coupon)) principal $(hundredths(principal)) total $(hundredths(coupon + principal))")
        totalcoupon += coupon
        totalprincipal += principal
    end
    push!(report, "ladder total coupon $(hundredths(totalcoupon)) principal $(hundredths(totalprincipal)) total $(hundredths(totalcoupon + totalprincipal))")
    worstname, worstpnl, worstpnls = "", 0.0, Float64[]
    for scenario in [Scenario("BASE", zeros(length(curve.rates))); scenarios]
        shifted = Curve.shifted(curve, scenario.deltas)
        values, pnls, total = Float64[], Float64[], 0.0
        for (i, position) in enumerate(positions)
            value = positionpv(position, shifted)
            pnl = value - basevalues[i]
            push!(values, value)
            push!(pnls, pnl)
            total += value
            push!(scenario_rows, "$name,$(scenario.name),$(position.valuation.bond.code),$(amount(value)),$(amount(pnl))")
        end
        pnl = total - basevalue
        push!(scenario_rows, "$name,$(scenario.name),*,$(amount(total)),$(amount(pnl))")
        if scenario.name != "BASE" && (isempty(worstname) || pnl < worstpnl)
            worstname, worstpnl, worstpnls = scenario.name, pnl, pnls
        end
    end
    if !isempty(worstname)
        order = sortperm(1:length(positions); by=i -> (worstpnls[i], positions[i].valuation.bond.code))
        losers = join(("$(positions[i].valuation.bond.code) $(amount(worstpnls[i]))" for i in Iterators.take(order, 3)), " ")
        push!(report, "stress worst $worstname pnl $(amount(worstpnl)) losers $losers")
    end
    largest = 1
    for i in eachindex(positions)
        market(positions[i]) > market(positions[largest]) && (largest = i)
    end
    breaches = 0
    for words in limits
        kind = words[1]
        breach = false
        if kind == "position_weight"
            limit = parse(Int, words[2])
            position, mv = positions[largest], market(positions[largest])
            content = "$(position.valuation.bond.code) $(decimals(mv * 100 / totalvalue, 4)) limit $(hundredths(limit))"
            breach = mv * 10000 > limit * totalvalue
        elseif kind == "type_weight"
            limit = parse(Int, words[3])
            mv = groupvalues[findfirst(==(words[2]), TYPES)]
            content = "$(words[2]) $(decimals(mv * 100 / totalvalue, 4)) limit $(hundredths(limit))"
            breach = mv * 10000 > limit * totalvalue
        elseif kind == "max_maturity"
            years = parse(Int, words[2])
            count = Base.count(position -> position.valuation.bond.maturity - settlement > 365 * years, positions)
            content = "$(years)Y positions $count"
            breach = count >= 1
        elseif kind == "min_yield"
            limit = parse(Int, words[2])
            content = "$(percent(ytm)) limit $(hundredths(limit))"
            breach = ytm * 10000 < limit
        elseif kind == "duration"
            low, high = parse.(Int, words[2:3])
            content = "$(decimals(modified, 4)) range $(hundredths(low)) $(hundredths(high))"
            breach = modified < low / 100 || modified > high / 100
        else
            limit = parse(Int, words[2])
            content = "$(decimals(totaldv01, 2)) limit $(hundredths(limit))"
            breach = totaldv01 * 100 > limit
        end
        breach && (breaches += 1)
        push!(compliance, "$name $kind $content $(breach ? "BREACH" : "PASS")")
    end
    push!(compliance, "$name breaches $breaches")
end

function cashflowlines(bonds)
    output = ["bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"]
    for code in sort!(collect(keys(bonds))), period in bonds[code].periods
        cashflow(period) == 0 && continue
        push!(output, join((code, period.number, DC.formatdate(period.start), DC.formatdate(period.finish), DC.formatdate(period.payment), decimals(period.numerator / period.denominator, 6), period.rate, period.opening, period.coupon, period.principal), ","))
    end
    return output
end

function analyticslines(values)
    output = ["bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"]
    for code in sort!(collect(keys(values)))
        value = values[code]
        push!(output, join((code, decimals(value.clean / 1000, 6), decimals(value.accrued, 6), decimals(value.target, 6), percent(value.ytm), percent(value.ytw), DC.formatdate(value.workout), DC.formatdate(value.nextpayment), decimals(value.wal, 4), decimals(value.risk.macaulay, 4), decimals(value.risk.modified, 4), decimals(value.risk.convexity, 4), decimals(value.risk.dv01, 6), decimals(value.curveclean, 6), percent(value.zspread)), ","))
    end
    return output
end

function curvelines(data, curve)
    output = ["valuation $(DC.formatdate(data.valuation)) settlement $(DC.formatdate(data.settlement))"]
    previous = 0
    for (pillar, days, rate) in zip(data.pillars, curve.days, curve.rates)
        push!(output, "pillar $(DC.formatdate(pillar.maturity)) days $days frequency $(pillar.frequency) par $(hundredths(pillar.coupon)) zero $(percent(rate)) df $(decimals(Curve.discount(curve, days), 6)) forward $(percent(Curve.forward(curve, previous, days)))")
        previous = days
    end
    for year in 1:(last(curve.days) ÷ 365)
        days = 365 * year
        push!(output, "grid $(year)Y days $days zero $(percent(Curve.zerorate(curve, days))) df $(decimals(Curve.discount(curve, days), 6)) forward $(percent(Curve.forward(curve, days - 365, days)))")
    end
    return output
end

function writefile(name, lines)
    open(joinpath("output", name), "w") do file
        for line in lines
            println(file, line)
        end
    end
end

function main()
    data = inputdata()
    curve = Curve.bootstrap(data.settlement, data.pillars)
    for value in Base.values(data.values)
        analyze!(value, curve, data.settlement)
    end
    report, scenarios, compliance = String[], ["portfolio,scenario,bond,value,pnl"], String[]
    names = sort!(unique([first(key) for key in keys(data.positions)]))
    for name in names
        positions = [data.positions[key] for key in sort!(collect(keys(data.positions))) if first(key) == name]
        portfolio!(report, scenarios, compliance, name, positions, curve, data.scenarios, data.limits, data.settlement)
    end
    mkpath("output")
    writefile("errors.txt", data.errors)
    writefile("cashflows.csv", cashflowlines(data.bonds))
    writefile("analytics.csv", analyticslines(data.values))
    writefile("curve.txt", curvelines(data, curve))
    writefile("portfolio.txt", report)
    writefile("scenarios.csv", scenarios)
    writefile("compliance.txt", compliance)
end

main()
