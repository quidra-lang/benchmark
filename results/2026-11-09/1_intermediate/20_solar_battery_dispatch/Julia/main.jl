using Printf

const SETTING_NAMES = split("CAPACITY INITIAL CHARGE DISCHARGE CEFF DEFF RESERVE COST EXPORT FEEDIN FIXED DEMAND PVSCALE")
const SETTING_RANGES = Dict(zip(SETTING_NAMES, [(1, 100000), (0, 100), (1, 20000),
    (1, 20000), (1, 100), (1, 100), (0, 100), (0, 100000), (0, 100000),
    (0, 10000), (0, 100000), (0, 100000), (0, 300)]))
const FLOW_NAMES = split("PV>LOAD PV>BATTERY PV>GRID PV>CURTAIL BATTERY>LOAD BATTERY>GRID GRID>LOAD GRID>BATTERY")
const STRATEGY_RANGES = Dict("TOU" => (1, 100), "PEAKSHAVE" => (0, 100000), "BACKUP" => (0, 100))
const REPORTS = Set(split("DAILY BILL SAVINGS BYPERIOD DAYTYPE PROFILE FLOWS SELFSUFF CYCLES USAGE HISTOGRAM"))

struct CommandError <: Exception
    message::String
end
fail(message) = throw(CommandError(message))
number(text) = parse(Int, text)
money(value) = @sprintf("%s%d.%02d", value < 0 ? "-" : "", div(abs(value), 100), mod(abs(value), 100))
percentage(a, b) = money(b == 0 ? 0 : div(10000 * a, b))
decimal(a, b, places) = string(div(a * 10^places, b) ÷ 10^places, ".",
    lpad(mod(div(a * 10^places, b), 10^places), places, '0'))
bar(width) = "|" * repeat("#", width) * repeat(".", 20 - width) * "|"
row(values, widths) = println(join(lpad(string(value), width) for (value, width) in zip(values, widths)))

struct Strategy
    name::String
    parameter::Int
end
notation(strategy) = strategy.name * (haskey(STRATEGY_RANGES, strategy.name) ? " $(strategy.parameter)" : "")

struct InputHour
    day::Int
    hour::Int
    period::Int
    load::Int
    pv::Int
end

struct Dataset
    periods::Vector{String}
    hours::Vector{InputHour}
    daynames::Vector{String}
    weekends::BitVector
end

struct HourRecord
    day::Int
    hour::Int
    period::Int
    load::Int
    pv::Int
    charge::Int
    discharge::Int
    drawn::Int
    soc::Int
    imported::Int
    exported::Int
    curtailed::Int
    shortfall::Int
    loss::Int
    flows::NTuple{8, Int}
    cost::Int
    income::Int
end

struct Result
    strategy::Strategy
    settings::Dict{String, Int}
    prices::Vector{Int}
    records::Vector{HourRecord}
    starting::Int
    reserve::Int
    peak::Int
    demand::Int
    bill::Int
end

total(records, field) = sum((getfield(record, field) for record in records); init=0)
netcost(records) = total(records, :cost) - total(records, :income)
sufficiency(result) = percentage(max(0, total(result.records, :load) - total(result.records, :imported)), total(result.records, :load))
dayrecords(result, day) = @view result.records[(day - 1) * 24 + 1:day * 24]

function read_data()
    tokens() = split(readline())
    battery = number.(tokens()[2:end])
    grid = number.(tokens()[2:end])
    settings = Dict{String, Int}(zip(SETTING_NAMES, vcat(battery, grid, 100)))
    count = number(tokens()[2])
    periods = String[]
    prices = Int[]
    for _ in 1:count
        fields = tokens()
        push!(periods, fields[1])
        push!(prices, number(fields[2]))
    end
    period_index = Dict(name => i for (i, name) in enumerate(periods))
    divisions = Vector{Int}[]
    for _ in 1:2
        fields = tokens()
        hours = zeros(Int, 24)
        for i in 2:2:length(fields)
            first = number(fields[i])
            last = i + 2 <= length(fields) ? number(fields[i + 2]) - 1 : 23
            hours[first + 1:last + 1] .= period_index[fields[i + 1]]
        end
        push!(divisions, hours)
    end
    count = number(tokens()[2])
    profiles = Dict{Tuple{String, String}, Vector{Int}}()
    for _ in 1:count
        fields = tokens()
        profiles[(fields[1], fields[2])] = number.(fields[3:end])
    end
    days = number(tokens()[2])
    loads = zeros(Int, 24, days)
    generation = zeros(Int, 24, days)
    for day in 1:days
        fields = tokens()
        loads[:, day] = div.(profiles[("LOAD", fields[1])] .* number(fields[2]), 100)
        generation[:, day] = div.(profiles[("PV", fields[3])] .* number(fields[4]), 100)
    end
    holidays = Set(number.(tokens()[3:end]))
    count = number(tokens()[2])
    for _ in 1:count
        day, hour, load, pv = number.(tokens())
        loads[hour + 1, day] = load
        generation[hour + 1, day] = pv
    end
    weekdays = split("MON TUE WED THU FRI SAT SUN")
    daynames = [day in holidays ? "HOL" : String(weekdays[mod(day - 1, 7) + 1]) for day in 1:days]
    weekends = BitVector([day in holidays || mod(day - 1, 7) >= 5 for day in 1:days])
    hours = [InputHour(day, hour, divisions[weekends[day] ? 2 : 1][hour + 1],
                       loads[hour + 1, day], generation[hour + 1, day])
             for day in 1:days for hour in 0:23]
    Dataset(periods, hours, daynames, weekends), settings, prices
end

function simulate(data, strategy, settings, prices; outage=nothing)
    capacity = settings["CAPACITY"]
    ceff, deff = settings["CEFF"], settings["DEFF"]
    reserve_pct = strategy.name == "BACKUP" ? max(settings["RESERVE"], strategy.parameter) : settings["RESERVE"]
    reserve = div(capacity * reserve_pct, 100)
    starting = soc = div(capacity * settings["INITIAL"], 100)
    low, high = argmin(prices), argmax(prices)
    arbitrage = strategy.name == "EXPORTPEAK" && settings["FEEDIN"] > prices[low]
    records = HourRecord[]
    for input in data.hours
        pv = div(input.pv * settings["PVSCALE"], 100)
        direct = min(input.load, pv)
        surplus, deficit = pv - direct, input.load - direct
        x1 = min(surplus, settings["CHARGE"], cld(100 * (capacity - soc), ceff))
        stored1 = div(x1 * ceff, 100)
        soc += stored1
        surplus -= x1
        disconnected = outage !== nothing && input.day == outage[1] && outage[2] <= input.hour <= outage[3]
        target = deficit
        if !disconnected
            if strategy.name == "TOU"
                target = input.period == high ? deficit : 0
            elseif strategy.name == "PEAKSHAVE"
                target = max(0, deficit - strategy.parameter)
            elseif strategy.name == "EXPORTPEAK" && arbitrage && input.period == low && low != high
                target = 0
            end
        end
        lower = disconnected ? 0 : reserve
        y1 = min(cld(100 * target, deff), settings["DISCHARGE"], max(0, soc - lower))
        d1 = div(y1 * deff, 100)
        soc -= y1
        deficit -= d1
        x2 = y2 = d2 = stored2 = 0
        if disconnected
            grid = export_pv = 0
            shortfall, curtailed = deficit, surplus
        else
            grid, shortfall = deficit, 0
            export_pv = min(surplus, settings["EXPORT"])
            curtailed = surplus - export_pv
            headroom = settings["CHARGE"] - x1
            charge_target = nothing
            if strategy.name == "TOU" && input.period == low && low != high
                charge_target = div(capacity * strategy.parameter, 100)
            elseif strategy.name == "PEAKSHAVE" && input.period == low
                charge_target = capacity
                headroom = min(headroom, max(0, strategy.parameter - grid))
            elseif strategy.name == "BACKUP" && input.period == low
                charge_target = reserve
            elseif strategy.name == "EXPORTPEAK" && arbitrage && input.period == low && low != high
                charge_target = capacity
            end
            if charge_target !== nothing
                x2 = min(headroom, cld(100 * max(0, charge_target - soc), ceff))
                stored2 = div(x2 * ceff, 100)
                soc += stored2
            end
            if strategy.name == "EXPORTPEAK" && arbitrage && input.period == high && x1 == 0
                y2 = min(cld(100 * (settings["EXPORT"] - export_pv), deff),
                         settings["DISCHARGE"] - y1, max(0, soc - reserve))
                d2 = div(y2 * deff, 100)
                soc -= y2
            end
        end
        imported, exported = grid + x2, export_pv + d2
        loss = x1 - stored1 + x2 - stored2 + y1 - d1 + y2 - d2
        flows = (direct, x1, export_pv, curtailed, d1, d2, grid, x2)
        push!(records, HourRecord(input.day, input.hour, input.period, input.load, pv,
            x1 + x2, d1 + d2, y1 + y2, soc, imported, exported, curtailed, shortfall,
            loss, flows, div(imported * prices[input.period], 100000),
            div(exported * settings["FEEDIN"], 100000)))
    end
    peak = maximum(record.imported for record in records)
    demand = div(peak * settings["DEMAND"], 1000)
    bill = netcost(records) + settings["FIXED"] + demand
    Result(strategy, copy(settings), copy(prices), records, starting, reserve, peak, demand, bill)
end

baseline(data, settings, prices) = simulate(data, Strategy("SELF", 0), merge(settings, Dict("CAPACITY" => 0)), prices)

function strategies(tokens)
    result = Strategy[]
    i = 1
    while i <= length(tokens)
        name = tokens[i]
        i += 1
        parameter = 0
        if haskey(STRATEGY_RANGES, name)
            i <= length(tokens) || fail("missing parameter for $name")
            parameter = number(tokens[i])
            i += 1
            low, high = STRATEGY_RANGES[name]
            low <= parameter <= high || fail("invalid parameter for $name")
        elseif name != "SELF" && name != "EXPORTPEAK"
            fail("unknown strategy $name")
        end
        push!(result, Strategy(String(name), parameter))
    end
    result
end

function one_strategy(tokens)
    choices = strategies(tokens)
    length(choices) == 1 || fail("wrong number of arguments")
    only(choices)
end

arguments(args, count) = length(args) == count || fail("wrong number of arguments")
function valid_day(text, data)
    day = number(text)
    1 <= day <= length(data.daynames) || fail("invalid day")
    day
end
function parameter_range(name)
    haskey(SETTING_RANGES, name) || fail("unknown parameter $name")
    SETTING_RANGES[name]
end
function values_range(args, bounds)
    low, high, step = number.(args)
    bounds[1] <= low <= high <= bounds[2] && step >= 1 && div(high - low, step) + 1 <= 20 || fail("invalid range")
    low:step:high
end

function configure(data, settings, prices)
    println("BATTERY capacity $(settings["CAPACITY"]) initial $(settings["INITIAL"]) charge $(settings["CHARGE"]) discharge $(settings["DISCHARGE"]) ceff $(settings["CEFF"]) deff $(settings["DEFF"]) reserve $(settings["RESERVE"]) cost $(settings["COST"])")
    println("GRID export $(settings["EXPORT"]) feedin $(settings["FEEDIN"]) fixed $(settings["FIXED"]) demand $(settings["DEMAND"])")
    println("SOLAR pvscale $(settings["PVSCALE"])")
    tariff = join(("$name $price" for (name, price) in zip(data.periods, prices)), " ")
    println("TARIFF $tariff cheapest $(data.periods[argmin(prices)]) peak $(data.periods[argmax(prices)])")
end

function hourly(data, result, day)
    println("HOURLY day $day $(data.daynames[day]) strategy $(notation(result.strategy))")
    println("hour   load     pv charge  disch    soc import export   curt")
    records = dayrecords(result, day)
    for r in records
        row((r.hour, r.load, r.pv, r.charge, r.discharge, r.soc, r.imported, r.exported, r.curtailed), (4, 7, 7, 7, 7, 7, 7, 7, 7))
    end
    row(("sum", total(records, :load), total(records, :pv), total(records, :charge), total(records, :discharge), "",
         total(records, :imported), total(records, :exported), total(records, :curtailed)), (4, 7, 7, 7, 7, 7, 7, 7, 7))
end

function daily(data, result)
    println("DAILY strategy $(notation(result.strategy))")
    println("day name    load      pv  import  export    curt     soc      cost")
    for day in eachindex(data.daynames)
        records = dayrecords(result, day)
        row((day, data.daynames[day], total(records, :load), total(records, :pv),
             total(records, :imported), total(records, :exported), total(records, :curtailed),
             last(records).soc, money(netcost(records))), (3, 5, 8, 8, 8, 8, 8, 8, 10))
    end
    r = result.records
    println("TOTAL load $(total(r, :load)) pv $(total(r, :pv)) import $(total(r, :imported)) export $(total(r, :exported)) curtailed $(total(r, :curtailed)) cost $(money(netcost(r)))")
end

function bill(data, result)
    println("BILL strategy $(notation(result.strategy)) days $(length(data.daynames))")
    for (i, name) in enumerate(data.periods)
        records = filter(r -> r.period == i, result.records)
        println("IMPORT $name $(total(records, :imported)) Wh $(money(total(records, :cost)))")
    end
    println("EXPORT $(total(result.records, :exported)) Wh $(money(-total(result.records, :income)))")
    println("FIXED $(money(result.settings["FIXED"]))")
    println("DEMAND $(result.peak) Wh $(money(result.demand))")
    println("TOTAL $(money(result.bill))")
end

function savings(data, result)
    original = baseline(data, result.settings, result.prices)
    println("SAVINGS strategy $(notation(result.strategy))")
    entries = [(name, total(filter(r -> r.period == i, original.records), :cost),
                      total(filter(r -> r.period == i, result.records), :cost)) for (i, name) in enumerate(data.periods)]
    append!(entries, [("EXPORT", -total(original.records, :income), -total(result.records, :income)),
                      ("DEMAND", original.demand, result.demand), ("TOTAL", original.bill, result.bill)])
    for (name, before, after) in entries
        println("$name $(money(before)) -> $(money(after)) saving $(money(before - after))")
    end
end

function grouped_reports(command, data, result)
    println("$command strategy $(notation(result.strategy))")
    if command == "BYPERIOD"
        for (i, name) in enumerate(data.periods)
            r = filter(r -> r.period == i, result.records)
            println("$name hours $(length(r)) load $(total(r, :load)) pv $(total(r, :pv)) charge $(total(r, :charge)) discharge $(total(r, :discharge)) import $(total(r, :imported)) export $(total(r, :exported))")
        end
    else
        for (name, weekend) in (("WEEKDAY", false), ("WEEKEND", true))
            days = count(==(weekend), data.weekends)
            r = filter(r -> data.weekends[r.day] == weekend, result.records)
            println("$name days $days load $(div(total(r, :load), days)) pv $(div(total(r, :pv), days)) import $(div(total(r, :imported), days)) export $(div(total(r, :exported), days)) cost $(money(div(netcost(r), days)))")
        end
    end
end

function usage(result)
    r = result.records
    charging = count(x -> x.charge > 0, r)
    discharging = count(x -> x.drawn > 0, r)
    idle = count(x -> x.charge == 0 && x.drawn == 0, r)
    full = count(x -> x.soc == result.settings["CAPACITY"], r)
    low = count(x -> x.soc <= result.reserve, r)
    current = longest = start = 0
    for (i, record) in enumerate(r)
        current = record.soc <= result.reserve ? current + 1 : 0
        if current > longest
            longest, start = current, i - current + 1
        end
    end
    print("USAGE charging $charging discharging $discharging idle $idle full $full low $low longest $longest")
    longest > 0 && print(" from day $(r[start].day) hour $(r[start].hour)")
    println()
end

function report(command, data, result)
    r = result.records
    strategy = notation(result.strategy)
    if command == "DAILY"
        daily(data, result)
    elseif command == "BILL"
        bill(data, result)
    elseif command == "SAVINGS"
        savings(data, result)
    elseif command == "BYPERIOD" || command == "DAYTYPE"
        grouped_reports(command, data, result)
    elseif command == "PROFILE"
        days = length(data.daynames)
        println("PROFILE strategy $strategy days $days")
        println("hour   load     pv import export    soc")
        for hour in 0:23
            records = @view r[hour + 1:24:end]
            row((hour, (div(total(records, field), days) for field in (:load, :pv, :imported, :exported, :soc))...), (4, 7, 7, 7, 7, 7))
        end
    elseif command == "FLOWS"
        println("FLOWS strategy $strategy")
        for (i, name) in enumerate(FLOW_NAMES)
            println("$name $(sum(record.flows[i] for record in r))")
        end
        println("LOSSES $(total(r, :loss))")
        println("STORED $(last(r).soc - result.starting)")
    elseif command == "SELFSUFF"
        consumed = sum(record.flows[1] + record.flows[2] for record in r)
        println("SELFSUFF sufficiency $(sufficiency(result))% consumption $(percentage(consumed, total(r, :pv)))%")
    elseif command == "CYCLES"
        drawn, capacity = total(r, :drawn), result.settings["CAPACITY"]
        divisor = gcd(drawn, capacity)
        println("CYCLES $(div(drawn, divisor))/$(div(capacity, divisor)) $(decimal(drawn, capacity, 3)) drawn $drawn losses $(total(r, :loss))")
    elseif command == "USAGE"
        usage(result)
    elseif command == "HISTOGRAM"
        println("HISTOGRAM strategy $strategy")
        bands = zeros(Int, 10)
        for record in r
            bands[min(9, div(10 * record.soc, result.settings["CAPACITY"])) + 1] += 1
        end
        for i in 0:9
            println(lpad(10 * i, 3), "% ", bar(div(20 * bands[i + 1], length(r))), " ", bands[i + 1])
        end
    end
end

function outage_report(data, result, day, first, last_hour)
    alternate = simulate(data, result.strategy, result.settings, result.prices; outage=(day, first, last_hour))
    begin_index = (day - 1) * 24 + first + 1
    before = begin_index == 1 ? alternate.starting : alternate.records[begin_index - 1].soc
    println("OUTAGE day $day hours $first-$last_hour strategy $(notation(result.strategy)) soc $before")
    println("hour   load     pv  disch    soc  short   curt")
    records = @view alternate.records[begin_index:(day - 1) * 24 + last_hour + 1]
    for r in records
        row((r.hour, r.load, r.pv, r.discharge, r.soc, r.shortfall, r.curtailed), (4, 7, 7, 7, 7, 7, 7))
    end
    load, shortfall = total(records, :load), total(records, :shortfall)
    served = load == 0 ? "100.00" : percentage(load - shortfall, load)
    println("TOTAL load $load unserved $shortfall served $served% bill $(money(alternate.bill))")
end

function difference(data, result, day, strategy)
    alternate = simulate(data, strategy, result.settings, result.prices)
    println("DIFF day $day $(data.daynames[day]) $(notation(result.strategy)) vs $(notation(strategy))")
    println("hour   imp1   imp2   exp1   exp2   soc1   soc2")
    left, right = dayrecords(result, day), dayrecords(alternate, day)
    for (a, b) in zip(left, right)
        row((a.hour, a.imported, b.imported, a.exported, b.exported, a.soc, b.soc), (4, 7, 7, 7, 7, 7, 7))
    end
    cost1, cost2 = netcost(left), netcost(right)
    println("TOTAL cost1 $(money(cost1)) cost2 $(money(cost2)) difference $(money(cost2 - cost1))")
end

function comparisons(command, args, data, settings, prices)
    if command == "COMPARE"
        choices = strategies(args)
        isempty(choices) && fail("wrong number of arguments")
        base = baseline(data, settings, prices).bill
        results = [simulate(data, strategy, settings, prices) for strategy in choices]
        println("COMPARE baseline $(money(base))")
        order = sortperm(eachindex(results); by=i -> (results[i].bill, i))
        for (rank, i) in enumerate(order)
            result = results[i]
            println("$rank. $(notation(result.strategy)) bill $(money(result.bill)) saving $(money(base - result.bill)) sufficiency $(sufficiency(result))%")
        end
    elseif command == "SIZE"
        arguments(args, 3)
        values = values_range(args, (1, 100000))
        base = baseline(data, settings, prices).bill
        best = nothing
        for capacity in values
            result = simulate(data, Strategy("SELF", 0), merge(settings, Dict("CAPACITY" => capacity)), prices)
            saving = base - result.bill
            cost = div(capacity * settings["COST"], 1000)
            payback = saving > 0 ? decimal(cost, saving, 1) : "never"
            println("SIZE $capacity bill $(money(result.bill)) saving $(money(saving)) cost $(money(cost)) payback $payback")
            if saving > 0 && (best === nothing || cost * best[3] < best[2] * saving)
                best = (capacity, cost, saving)
            end
        end
        println("BEST ", best === nothing ? "none" : string(best[1]))
    else
        length(args) >= 5 || fail("wrong number of arguments")
        item = args[1]
        bounds = parameter_range(item)
        values = values_range(args[2:4], bounds)
        strategy = one_strategy(args[5:end])
        best = nothing
        for value in values
            changed = merge(settings, Dict(String(item) => value))
            result = simulate(data, strategy, changed, prices)
            base = baseline(data, changed, prices).bill
            println("SWEEP $item $value bill $(money(result.bill)) saving $(money(base - result.bill)) sufficiency $(sufficiency(result))%")
            if best === nothing || result.bill < best[2]
                best = (value, result.bill)
            end
        end
        println("BEST $(best[1])")
    end
end

function main()
    data, settings, prices = read_data()
    initial_settings, initial_prices = copy(settings), copy(prices)
    result = nothing
    for line in eachline()
        fields = split(line)
        command, args = fields[1], fields[2:end]
        command == "END" && break
        try
            if command == "RUN"
                strategy = one_strategy(args)
                result = simulate(data, strategy, settings, prices)
                println("RUN $(notation(strategy)) bill $(money(result.bill)) import $(total(result.records, :imported)) export $(total(result.records, :exported)) soc $(last(result.records).soc)")
            elseif command == "SET"
                arguments(args, 2)
                item = args[1]
                low, high = parameter_range(item)
                value = number(args[2])
                low <= value <= high || fail("invalid value for $item")
                previous = settings[item]
                settings[item] = value
                println("SET $item $previous -> $value")
            elseif command == "PRICE"
                arguments(args, 2)
                index = findfirst(==(args[1]), data.periods)
                index !== nothing || fail("unknown period $(args[1])")
                value = number(args[2])
                0 <= value <= 10000 || fail("invalid value for $(args[1])")
                previous = prices[index]
                prices[index] = value
                println("PRICE $(args[1]) $previous -> $value cheapest $(data.periods[argmin(prices)]) peak $(data.periods[argmax(prices)])")
            elseif command == "RESET"
                arguments(args, 0)
                settings, prices = copy(initial_settings), copy(initial_prices)
                println("RESET")
            elseif command == "CONFIG"
                arguments(args, 0)
                configure(data, settings, prices)
            elseif command == "NOBATTERY"
                arguments(args, 0)
                base = baseline(data, settings, prices)
                r = base.records
                println("NOBATTERY bill $(money(base.bill)) import $(total(r, :imported)) export $(total(r, :exported)) curtailed $(total(r, :curtailed)) peak $(base.peak)")
            elseif command in ("COMPARE", "SIZE", "SWEEP")
                comparisons(command, args, data, settings, prices)
            elseif command == "OUTAGE"
                arguments(args, 3)
                day = valid_day(args[1], data)
                first, last_hour = number.(args[2:3])
                0 <= first <= last_hour <= 23 || fail("invalid hours")
                result !== nothing || fail("no run")
                outage_report(data, result, day, first, last_hour)
            elseif command == "DIFF"
                length(args) >= 2 || fail("wrong number of arguments")
                day = valid_day(args[1], data)
                strategy = one_strategy(args[2:end])
                result !== nothing || fail("no run")
                difference(data, result, day, strategy)
            elseif command == "HOURLY" || command == "CHART"
                arguments(args, 1)
                day = valid_day(args[1], data)
                result !== nothing || fail("no run")
                if command == "HOURLY"
                    hourly(data, result, day)
                else
                    println("CHART day $day $(data.daynames[day]) strategy $(notation(result.strategy))")
                    capacity = result.settings["CAPACITY"]
                    for r in dayrecords(result, day)
                        println(lpad(r.hour, 2), " ", bar(div(20 * r.soc, capacity)), " ", percentage(r.soc, capacity), "%")
                    end
                end
            elseif command == "PEAKS"
                arguments(args, 1)
                count = number(args[1])
                count >= 1 || fail("invalid count")
                result !== nothing || fail("no run")
                println("PEAKS strategy $(notation(result.strategy))")
                selected = filter(r -> r.imported > 0, result.records)
                sort!(selected; by=r -> (-r.imported, r.day, r.hour))
                for (rank, r) in enumerate(Iterators.take(selected, count))
                    println("$rank. day $(r.day) hour $(r.hour) $(data.periods[r.period]) import $(r.imported) load $(r.load) soc $(r.soc)")
                end
                isempty(selected) && println("none")
            elseif command in REPORTS
                arguments(args, 0)
                result !== nothing || fail("no run")
                report(command, data, result)
            else
                fail("unknown command $command")
            end
        catch error
            error isa CommandError || rethrow()
            println("ERROR ", error.message)
        end
    end
end

main()
