using Printf

const NAMES = ["RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"]
const PARAMETERS = Dict("FIXED" => 1, "PASS" => 0, "BASESTOCK" => 1,
    "MINMAX" => 2, "MOVAVG" => 2, "SMOOTH" => 2, "STERMAN" => 4)
const MODES = Dict("ORDERS" => "order", "INV" => "inventory", "BACK" => "backlog")

struct CommandError <: Exception
    message::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.message)
fail(message::String) = throw(CommandError(message))

money(value::Integer) = string(div(value, 100), ".", lpad(string(mod(value, 100)), 2, '0'))

function decimal(numerator::Integer, denominator::Integer, places::Int)
    scale = 10^places
    value = fld(numerator * scale, denominator)
    string(fld(value, scale), ".", lpad(string(mod(value, scale)), places, '0'))
end

variation(values) = length(values) * sum(v^2 for v in values) - sum(values)^2

struct Policy
    name::String
    args::Vector{Int}
    display::String
end

function parse_policy(tokens::Vector{String})
    name = tokens[1]
    haskey(PARAMETERS, name) || fail("unknown policy " * name)
    count = PARAMETERS[name]
    length(tokens) - 1 == count || fail("$name needs $count parameters")
    args = [parse(Int, name == "STERMAN" && i <= 3 ?
                      replace(text, "." => "") : text)
            for (i, text) in enumerate(tokens[2:end])]
    valid = if name == "FIXED"
        0 <= args[1] <= 1000
    elseif name == "PASS"
        true
    elseif name == "BASESTOCK"
        0 <= args[1] <= 10000
    elseif name == "MINMAX"
        0 <= args[1] < args[2] <= 10000
    elseif name == "MOVAVG"
        1 <= args[1] <= 52 && 0 <= args[2] <= 10000
    elseif name == "SMOOTH"
        1 <= args[1] <= 10 && 0 <= args[2] <= 10000
    else
        all(0 <= x <= 100 for x in args[1:3]) && 0 <= args[4] <= 10000
    end
    valid || fail("invalid parameter for " * name)
    Policy(name, args, join(tokens, " "))
end

struct Initial
    inventory::Int
    quantity::Int
    shipping::Int
    orders::Int
    holding::Int
    backlog::Int
    policy::Policy
end

function read_initial(tokens::Vector{String})
    Initial(parse.(Int, tokens[2:7])..., parse_policy(tokens[8:end]))
end

mutable struct Stage
    inventory::Int
    backlog::Int
    shipping::Vector{Int}
    orders::Vector{Int}
    policy::Policy
    expected::Int
    holding::Int
    backlog_rate::Int
    lot::Int
    capacity::Union{Nothing,Int}
    records::Vector{Dict{String,Int}}
end

Stage(initial::Initial) = Stage(
    initial.inventory, 0, fill(initial.quantity, initial.shipping),
    fill(initial.quantity, initial.orders), initial.policy, 100 * initial.quantity,
    initial.holding, initial.backlog, 1, nothing, Dict{String,Int}[]
)

mutable struct Simulation
    initials::Vector{Initial}
    week::Int
    demands::Vector{Int}
    stages::Vector{Stage}
    plant_backlog::Int
    plant_capacity::Union{Nothing,Int}
    plant_records::Vector{Dict{String,Int}}
    visibility::String
end

Simulation(initials::Vector{Initial}, demands::Vector{Int}) =
    Simulation(initials, 0, copy(demands), Stage.(initials), 0, nothing,
               Dict{String,Int}[], "OFF")

function signal(s::Simulation, index::Int, week::Int, current=nothing)
    if s.visibility == "ON"
        return s.demands[week]
    end
    if current !== nothing && week == s.week + 1
        return current[index]
    end
    s.stages[index].records[week]["incoming"]
end

function set_policy!(s::Simulation, index::Int, policy::Policy)
    stage = s.stages[index]
    stage.policy = policy
    if policy.name == "STERMAN"
        stage.expected = 100 * (s.week == 0 ?
            s.initials[index].quantity : signal(s, index, s.week))
    end
end

function positions(s::Simulation)
    supply, position = Int[], Int[]
    for (index, stage) in enumerate(s.stages)
        upstream = index < 4 ? s.stages[index+1].backlog : s.plant_backlog
        line = sum(stage.orders) + upstream + sum(stage.shipping)
        push!(supply, line)
        push!(position, stage.inventory + line - stage.backlog)
    end
    return supply, position
end

function policy_order!(s::Simulation, index::Int, incoming, line::Int, position::Int)
    stage = s.stages[index]
    name, args = stage.policy.name, stage.policy.args
    week = s.week + 1
    observed = signal(s, index, week, incoming)
    if name == "FIXED"
        return args[1]
    elseif name == "PASS"
        return incoming[index]
    elseif name == "BASESTOCK"
        return max(0, args[1] - position)
    elseif name == "MINMAX"
        return position <= args[1] ? args[2] - position : 0
    elseif name == "MOVAVG"
        k, target = args
        count = min(k, week)
        forecast = fld(sum(signal(s, index, u, incoming)
            for u in week-count+1:week), count)
        delay = s.initials[index].shipping + s.initials[index].orders
        return max(0, target + forecast * delay - position)
    elseif name == "SMOOTH"
        k, target = args
        return max(0, observed + fld(target - position, k))
    else
        theta, alpha, beta, target = args
        stage.expected = fld(100 * theta * observed +
            (100 - theta) * stage.expected, 100)
        net = stage.inventory - stage.backlog
        return max(0, fld(100 * stage.expected +
            alpha * (100 * (target - net) - beta * line), 10000))
    end
end

function step!(s::Simulation)
    received = Int[]
    for stage in s.stages
        quantity = popfirst!(stage.shipping)
        stage.inventory += quantity
        push!(received, quantity)
    end
    incoming = [s.demands[s.week + 1]]
    append!(incoming, (popfirst!(s.stages[index].orders) for index in 1:3))
    plant_incoming = popfirst!(s.stages[4].orders)
    records = Dict{String,Int}[]
    for (index, stage) in enumerate(s.stages)
        before = stage.backlog
        requested = before + incoming[index]
        shipped = min(stage.inventory, requested)
        if stage.capacity !== nothing
            shipped = min(shipped, stage.capacity)
        end
        stage.inventory -= shipped
        stage.backlog = requested - shipped
        if index > 1
            push!(s.stages[index-1].shipping, shipped)
        end
        push!(records, Dict(
            "received" => received[index], "incoming" => incoming[index],
            "shipped" => shipped, "before" => before,
            "ontime" => min(max(0, shipped - before), incoming[index]),
            "inventory" => stage.inventory, "backlog" => stage.backlog,
        ))
    end
    requested = s.plant_backlog + plant_incoming
    produced = s.plant_capacity === nothing ?
        requested : min(requested, s.plant_capacity)
    s.plant_backlog = requested - produced
    push!(s.stages[4].shipping, produced)
    supply, position = positions(s)
    for (index, stage) in enumerate(s.stages)
        order = policy_order!(s, index, incoming, supply[index], position[index])
        quantity = cld(order, stage.lot) * stage.lot
        push!(stage.orders, quantity)
        record = records[index]
        record["order"] = quantity
        record["holding"] = stage.holding * stage.inventory
        record["backlog_cost"] = stage.backlog_rate * stage.backlog
        record["cost"] = record["holding"] + record["backlog_cost"]
        push!(stage.records, record)
    end
    push!(s.plant_records, Dict(
        "incoming" => plant_incoming, "produced" => produced,
        "backlog" => s.plant_backlog,
    ))
    s.week += 1
    records
end

costs(s::Simulation) = [sum(r["cost"] for r in stage.records) for stage in s.stages]

mutable struct Game
    initials::Vector{Initial}
    base::Vector{Int}
    simulation::Simulation
    snapshots::Dict{String,Simulation}
    output::Vector{String}
end

function Game(settings::Vector{Vector{String}})
    initials = read_initial.(settings)
    Game(initials, Int[], Simulation(initials, Int[]),
         Dict{String,Simulation}(), String[])
end

emit!(g::Game, parts...) = push!(g.output, join(string.(parts), " "))

function stage_index(name::String)
    index = findfirst(==(name), NAMES)
    index === nothing && fail("unknown stage " * name)
    index
end

target(name::String) = name == "ALL" ? collect(1:4) : [stage_index(name)]

function require_weeks(g::Game)
    g.simulation.week > 0 || fail("no weeks simulated")
end

function range_check(args::Vector{String}, limit::Int)
    isempty(args) && return (1, limit)
    first, last = parse.(Int, args)
    1 <= first <= last <= limit || fail("bad range $(args[1]) $(args[2])")
    return (first, last)
end

function mode_check(mode::String)
    mode in ("ORDERS", "INV", "BACK", "NET") ||
        fail("unknown mode " * mode)
end

function values(g::Game, index::Int, mode::String)
    records = g.simulation.stages[index].records
    if mode == "NET"
        return [r["inventory"] - r["backlog"] for r in records]
    end
    [r[MODES[mode]] for r in records]
end

function initialize!(g::Game, demands=nothing)
    if demands !== nothing
        g.base = copy(demands)
    end
    g.simulation = Simulation(g.initials, g.base)
end

function trial(g::Game, policies::Vector{Policy})
    current = g.simulation
    alternative = Simulation(g.initials, current.demands)
    alternative.visibility = current.visibility
    alternative.plant_capacity = current.plant_capacity
    for index in 1:4
        stage, previous = alternative.stages[index], current.stages[index]
        stage.lot = previous.lot
        stage.capacity = previous.capacity
        stage.holding = previous.holding
        stage.backlog_rate = previous.backlog_rate
        set_policy!(alternative, index, policies[index])
    end
    while alternative.week < length(alternative.demands)
        step!(alternative)
    end
    alternative
end

function demand!(g::Game, amounts::Vector{Int})
    initialize!(g, amounts)
    emit!(g, "DEMAND weeks", length(amounts),
          "total", sum(amounts), "min", minimum(amounts),
          "max", maximum(amounts))
end

function generate!(g::Game, args::Vector{String})
    weeks, base, spread, seed = parse.(Int, args[1:4])
    changes = [(args[i], parse(Int, args[i+1]), parse(Int, args[i+2]))
               for i in 5:3:length(args)]
    for (_, week, _) in changes
        1 <= week <= weeks || fail("week $week outside horizon")
    end
    levels = Int[]
    for week in 1:weeks
        level = base
        for (kind, start, amount) in changes
            if kind == "STEP" && week >= start
                level += amount
            elseif kind == "PULSE" && week == start
                level += amount
            elseif kind == "RAMP" && week >= start
                level += amount * (week - start + 1)
            end
        end
        level >= 0 || fail("negative level at week $week")
        push!(levels, level)
    end
    amounts = Int[]
    for level in levels
        seed = mod(48271 * seed, 2147483647)
        push!(amounts, level + mod(seed, spread))
    end
    demand!(g, amounts)
end

function show_status!(g::Game)
    s = g.simulation
    emit!(g, "STATUS week", s.week, "of", length(s.demands))
    supply, position = positions(s)
    for (index, stage) in enumerate(s.stages)
        text = "$(NAMES[index]) inv $(stage.inventory) back $(stage.backlog)" *
            " transit $(join(stage.shipping, ",")) pending $(join(stage.orders, ","))" *
            " supply $(supply[index]) position $(position[index])" *
            " policy $(stage.policy.display)"
        if stage.policy.name == "STERMAN"
            text *= " expect $(money(stage.expected))"
        end
        emit!(g, text)
    end
    emit!(g, "PLANT back", s.plant_backlog)
end

function show_week!(g::Game, week::Int)
    s = g.simulation
    emit!(g, "WEEK", week, "demand", s.demands[week])
    for (index, stage) in enumerate(s.stages)
        r = stage.records[week]
        emit!(g, NAMES[index], "recv", r["received"], "in", r["incoming"],
              "ship", r["shipped"], "inv", r["inventory"],
              "back", r["backlog"], "order", r["order"],
              "cost", money(r["cost"]))
    end
    r = s.plant_records[week]
    emit!(g, "PLANT in", r["incoming"], "made", r["produced"], "back", r["backlog"])
end

function table_display!(g::Game, index::Int, first::Int, last::Int)
    emit!(g, "TABLE", NAMES[index], "$first-$last")
    labels = ["week", "in", "ship", "recv", "inv", "back", "order", "cost"]
    widths = [4, 6, 6, 6, 6, 6, 6, 9]
    emit!(g, join((lpad(label, width) for (label, width) in zip(labels, widths)), " "))
    for week in first:last
        r = g.simulation.stages[index].records[week]
        entries = [week, r["incoming"], r["shipped"], r["received"],
                   r["inventory"], r["backlog"], r["order"], money(r["cost"])]
        emit!(g, join((lpad(string(value), width)
                       for (value, width) in zip(entries, widths)), " "))
    end
end

function show_costs!(g::Game)
    s = g.simulation
    emit!(g, "COSTS week", s.week)
    all_holding, all_backlog = 0, 0
    for (index, stage) in enumerate(s.stages)
        holding = sum(r["holding"] for r in stage.records)
        backlog = sum(r["backlog_cost"] for r in stage.records)
        all_holding += holding
        all_backlog += backlog
        emit!(g, NAMES[index], "holding", money(holding),
              "backlog", money(backlog), "total", money(holding + backlog))
    end
    emit!(g, "TOTAL holding", money(all_holding), "backlog", money(all_backlog),
          "total", money(all_holding + all_backlog))
end

function fill_text(records)
    ordered = sum(r["incoming"] for r in records)
    ontime = sum(r["ontime"] for r in records)
    fill = ordered == 0 ? "n/a" : decimal(ontime * 100, ordered, 2) * "%"
    return ordered, ontime, fill
end

function bullwhip!(g::Game)
    s = g.simulation
    n = s.week
    demands = s.demands[1:n]
    demand_var = variation(demands)
    emit!(g, "BULLWHIP weeks 1-$n demand mean",
          decimal(sum(demands), n, 4), "var",
          decimal(demand_var, n*n, 4))
    previous = demand_var
    for (index, stage) in enumerate(s.stages)
        orders = [r["order"] for r in stage.records]
        v = variation(orders)
        emit!(g, NAMES[index], "mean", decimal(sum(orders), n, 4),
              "var", decimal(v, n*n, 4),
              "ratio", demand_var == 0 ? "n/a" : decimal(v, demand_var, 4),
              "step", previous == 0 ? "n/a" : decimal(v, previous, 4))
        previous = v
    end
end

function peaks!(g::Game)
    s = g.simulation
    emit!(g, "PEAKS weeks 1-$(s.week)")
    for (index, stage) in enumerate(s.stages)
        inventories = [r["inventory"] for r in stage.records]
        backlogs = [r["backlog"] for r in stage.records]
        max_inventory, max_backlog = maximum(inventories), maximum(backlogs)
        longest, run, start, best_start, best_end = 0, 0, 0, 0, 0
        for (week, backlog) in enumerate(backlogs)
            if backlog > 0
                if run == 0
                    start = week
                end
                run += 1
                if run > longest
                    longest, best_start, best_end = run, start, week
                end
            else
                run = 0
            end
        end
        inventory_week = max_inventory == 0 ? "-" : string(findfirst(==(max_inventory), inventories))
        backlog_week = max_backlog == 0 ? "-" : string(findfirst(==(max_backlog), backlogs))
        stockout = longest > 0 ? "$longest weeks $best_start-$best_end" : "0"
        emit!(g, NAMES[index], "max_inv", max_inventory, "week", inventory_week,
              "max_back", max_backlog, "week", backlog_week,
              "longest_stockout", stockout)
    end
end

function leadtime!(g::Game, index::Int)
    s = g.simulation
    stage, initial = s.stages[index], g.initials[index]
    nominal = initial.shipping + initial.orders
    cumulative = cumsum([r["received"] for r in stage.records]) .-
        nominal * initial.quantity
    ordered, count = 0, 0
    leads = Int[]
    for (t, record) in enumerate(stage.records)
        ordered += record["order"]
        if record["order"] == 0
            continue
        end
        count += 1
        for u in t+1:length(stage.records)
            if cumulative[u] >= ordered
                push!(leads, u - t)
                break
            end
        end
    end
    emit!(g, "LEADTIME", NAMES[index], "nominal", nominal, "orders", count,
          "completed", length(leads), "open", count - length(leads),
          "min", isempty(leads) ? "-" : string(minimum(leads)),
          "avg", isempty(leads) ? "-" : decimal(sum(leads), length(leads), 2),
          "max", isempty(leads) ? "-" : string(maximum(leads)))
end

function plot!(g::Game, index::Int, mode::String, first::Int, last::Int)
    displayed = values(g, index, mode)[first:last]
    maximum_value = maximum(displayed)
    if mode == "NET"
        minimum_value = minimum(displayed)
        emit!(g, "PLOT", NAMES[index], mode, "$first-$last",
              "min", minimum_value, "max", maximum_value)
        scale = maximum(abs.(displayed))
        for (week, value) in enumerate(displayed)
            length_ = scale == 0 ? 0 : fld(abs(value) * 25, scale)
            left = value < 0 ?
                repeat(" ", 25 - length_) * repeat("-", length_) : repeat(" ", 25)
            right = value > 0 ? repeat("+", length_) : ""
            emit!(g, "$(lpad(string(first + week - 1), 3)) $left|$right $value")
        end
    else
        emit!(g, "PLOT", NAMES[index], mode, "$first-$last", "max", maximum_value)
        for (week, value) in enumerate(displayed)
            length_ = maximum_value == 0 ? 0 : fld(value * 50, maximum_value)
            emit!(g, "$(lpad(string(first + week - 1), 3)) |$(repeat("#", length_)) $value")
        end
    end
end

function command!(g::Game, command::String, args::Vector{String})
    s = g.simulation
    if command == "DEMAND"
        demand!(g, parse.(Int, args))
    elseif command == "GENERATE"
        generate!(g, args)
    elseif command == "RUN"
        s.week < length(s.demands) ||
            fail("horizon reached at week $(length(s.demands))")
        first = s.week + 1
        count = min(parse(Int, args[1]), length(s.demands) - s.week)
        cost = 0
        for _ in 1:count
            records = step!(s)
            for (index, r) in enumerate(records)
                cost += r["cost"]
                if r["before"] == 0 && r["backlog"] > 0
                    emit!(g, "STOCKOUT", NAMES[index], "week", s.week,
                          "backlog", r["backlog"])
                elseif r["before"] > 0 && r["backlog"] == 0
                    emit!(g, "RECOVER", NAMES[index], "week", s.week)
                end
            end
        end
        emit!(g, "RUN $first-$(s.week) demand",
              sum(s.demands[first:s.week]), "cost", money(cost))
        if s.week == length(s.demands)
            emit!(g, "HORIZON", s.week)
        end
    elseif command == "RESET"
        initialize!(g)
        emit!(g, "RESET week 0")
    elseif command == "SAVE"
        g.snapshots[args[1]] = deepcopy(s)
        emit!(g, "SAVE", args[1], "week", s.week)
    elseif command == "LOAD"
        haskey(g.snapshots, args[1]) || fail("no snapshot " * args[1])
        g.simulation = deepcopy(g.snapshots[args[1]])
        emit!(g, "LOAD", args[1], "week", g.simulation.week)
    elseif command == "SET"
        indices = target(args[1])
        policy = parse_policy(args[2:end])
        for index in indices
            set_policy!(s, index, policy)
        end
        emit!(g, "SET", args[1], policy.display)
    elseif command == "BATCH"
        index = stage_index(args[1])
        lot = parse(Int, args[2])
        1 <= lot <= 100 || fail("invalid batch size " * args[2])
        s.stages[index].lot = lot
        emit!(g, "BATCH", args[1], lot)
    elseif command == "CAPACITY"
        index = args[1] == "PLANT" ? nothing : stage_index(args[1])
        capacity = args[2] == "OFF" ? nothing : parse(Int, args[2])
        if capacity !== nothing && capacity > 10000
            fail("invalid capacity " * args[2])
        end
        if index === nothing
            s.plant_capacity = capacity
        else
            s.stages[index].capacity = capacity
        end
        emit!(g, "CAPACITY", args...)
    elseif command == "COST"
        index = stage_index(args[1])
        holding, backlog = parse.(Int, args[2:3])
        holding <= 1000 && backlog <= 1000 || fail("invalid cost")
        s.stages[index].holding = holding
        s.stages[index].backlog_rate = backlog
        emit!(g, "COST", args[1], "holding", holding, "backlog", backlog)
    elseif command == "VISIBILITY"
        args[1] in ("ON", "OFF") || fail("unknown visibility " * args[1])
        s.visibility = args[1]
        emit!(g, "VISIBILITY", args[1])
    elseif command == "SHOCK"
        week, amount = parse.(Int, args)
        1 <= week <= length(s.demands) ||
            fail("week $(args[1]) outside horizon")
        week > s.week || fail("week $(args[1]) already simulated")
        before = s.demands[week]
        s.demands[week] = amount
        emit!(g, "SHOCK week", week, before, "->", amount)
    elseif command == "STATUS"
        show_status!(g)
    elseif command == "SETTINGS"
        emit!(g, "SETTINGS")
        for (index, stage) in enumerate(s.stages)
            initial = g.initials[index]
            emit!(g, NAMES[index], "holding", stage.holding,
                  "backlog", stage.backlog_rate, "batch", stage.lot,
                  "capacity", stage.capacity === nothing ? "OFF" : stage.capacity,
                  "delays", initial.shipping, initial.orders)
        end
        emit!(g, "PLANT capacity", s.plant_capacity === nothing ? "OFF" : s.plant_capacity)
        emit!(g, "VISIBILITY", s.visibility)
    elseif command == "WEEK"
        require_weeks(g)
        week = parse(Int, args[1])
        1 <= week <= s.week || fail("bad week " * args[1])
        show_week!(g, week)
    elseif command == "TABLE"
        index = stage_index(args[1])
        require_weeks(g)
        first, last = range_check(args[2:end], s.week)
        table_display!(g, index, first, last)
    elseif command == "CHAIN"
        require_weeks(g)
        first, last = range_check(args, s.week)
        emit!(g, "CHAIN $first-$last")
        emit!(g, "$(lpad("week", 4)) $(lpad("demand", 6)) " *
                 join(lpad.(NAMES, 11), " "))
        for week in first:last
            orders = [r.records[week]["order"] for r in s.stages]
            emit!(g, "$(lpad(string(week), 4)) $(lpad(string(s.demands[week]), 6)) " *
                join((lpad(string(v), 11) for v in orders), " "))
        end
    elseif command == "DEMANDS"
        first, last = range_check(args, length(s.demands))
        amounts = s.demands[first:last]
        emit!(g, "DEMANDS $first-$last total", sum(amounts),
              "min", minimum(amounts), "max", maximum(amounts))
        emit!(g, join(amounts, " "))
    elseif command == "COSTS"
        show_costs!(g)
    elseif command == "SUMMARY"
        require_weeks(g)
        emit!(g, "SUMMARY weeks 1-$(s.week)")
        for (index, stage) in enumerate(s.stages)
            r = stage.records
            orders = [v["order"] for v in r]
            emit!(g, NAMES[index],
                  "avg_inv", decimal(sum(v["inventory"] for v in r), s.week, 2),
                  "avg_back", decimal(sum(v["backlog"] for v in r), s.week, 2),
                  "orders", sum(orders), "min", minimum(orders),
                  "max", maximum(orders), "zero_weeks", count(==(0), orders))
        end
    elseif command == "BALANCE"
        emit!(g, "BALANCE week", s.week)
        for (index, stage) in enumerate(s.stages)
            emit!(g, NAMES[index], "start", g.initials[index].inventory,
                  "received", sum(r["received"] for r in stage.records),
                  "shipped", sum(r["shipped"] for r in stage.records),
                  "end", stage.inventory, "owed", stage.backlog)
        end
        initial_goods = sum(i.inventory + i.quantity * i.shipping for i in g.initials)
        emit!(g, "SYSTEM initial", initial_goods,
              "produced", sum(r["produced"] for r in s.plant_records),
              "delivered", sum(r["shipped"] for r in s.stages[1].records),
              "stock", sum(stage.inventory for stage in s.stages),
              "transit", sum(sum(stage.shipping) for stage in s.stages))
    elseif command == "FILLRATE"
        require_weeks(g)
        emit!(g, "FILLRATE weeks 1-$(s.week)")
        for (index, stage) in enumerate(s.stages)
            ordered, ontime, fill = fill_text(stage.records)
            stockouts = count(r -> r["backlog"] > 0, stage.records)
            emit!(g, NAMES[index], "fill", fill, "ontime", ontime,
                  "ordered", ordered, "stockout_weeks", stockouts,
                  "service", decimal((s.week - stockouts) * 100, s.week, 2) * "%")
        end
    elseif command == "BULLWHIP"
        require_weeks(g)
        bullwhip!(g)
    elseif command == "PEAKS"
        require_weeks(g)
        peaks!(g)
    elseif command == "LEADTIME"
        index = stage_index(args[1])
        require_weeks(g)
        leadtime!(g, index)
    elseif command in ("PLOT", "HISTOGRAM")
        index = stage_index(args[1])
        mode_check(args[2])
        if command == "HISTOGRAM"
            width = parse(Int, args[3])
            1 <= width <= 100 || fail("invalid width " * args[3])
        end
        require_weeks(g)
        if command == "PLOT"
            first, last = range_check(args[3:end], s.week)
            plot!(g, index, args[2], first, last)
        else
            counts = Dict{Int,Int}()
            for value in values(g, index, args[2])
                bucket = fld(value, width)
                counts[bucket] = get(counts, bucket, 0) + 1
            end
            emit!(g, "HISTOGRAM", args[1], args[2], "width", width,
                  "weeks 1-$(s.week)")
            for bucket in minimum(keys(counts)):maximum(keys(counts))
                n = get(counts, bucket, 0)
                emit!(g, "$(bucket*width)..$(bucket*width+width-1) $n" *
                    (n == 0 ? "" : " " * repeat("*", n)))
            end
        end
    elseif command == "COMPARE"
        policies = Policy[]
        first = 1
        for last in 1:(length(args)+1)
            if last > length(args) || args[last] == "/"
                push!(policies, parse_policy(args[first:last-1]))
                first = last + 1
            end
        end
        rows = Tuple{Int,Int,String,String,String}[]
        for (index, policy) in enumerate(policies)
            simulated = trial(g, fill(policy, 4))
            objective = sum(costs(simulated))
            _, _, fill = fill_text(simulated.stages[1].records)
            demand_var = variation(simulated.demands)
            factory_var = variation([r["order"] for r in simulated.stages[4].records])
            ratio = demand_var == 0 ? "n/a" : decimal(factory_var, demand_var, 4)
            push!(rows, (objective, index, policy.display, fill, ratio))
        end
        emit!(g, "COMPARE", length(policies), "weeks", length(s.demands))
        for (rank, row) in enumerate(sort(rows))
            cost, _, policy, fill, ratio = row
            emit!(g, rank, policy, "total", money(cost), "fill", fill,
                  "bullwhip", ratio)
        end
    elseif command == "OPTIMIZE"
        indices = target(args[1])
        low, high = parse.(Int, args[2:3])
        low <= high || fail("bad range $(args[2]) $(args[3])")
        high - low <= 200 || fail("range too large")
        best = nothing
        for level in low:high
            policies = [stage.policy for stage in s.stages]
            for index in indices
                policies[index] = Policy("BASESTOCK", [level], "BASESTOCK $level")
            end
            simulated = trial(g, policies)
            costs_ = costs(simulated)
            candidate = (sum(costs_[indices]), level, sum(costs_))
            if best === nothing || candidate[1] < best[1] ||
               (candidate[1] == best[1] && candidate[2] < best[2])
                best = candidate
            end
        end
        emit!(g, "OPTIMIZE", args[1], "BASESTOCK", best[2],
              "cost", money(best[1]), "total", money(best[3]))
    else
        fail("unknown command " * command)
    end
end

function execute!(g::Game, line::String)
    fields = String.(split(line))
    command = fields[1]
    try
        command!(g, command, fields[2:end])
    catch error
        if error isa CommandError
            emit!(g, "ERROR", error.message)
        else
            rethrow()
        end
    end
end

function main()
    settings = [String.(split(readline(stdin))) for _ in 1:4]
    game = Game(settings)
    for line in eachline(stdin)
        line == "END" && break
        execute!(game, line)
    end
    if !isempty(game.output)
        println(join(game.output, "\n"))
    end
end

main()
