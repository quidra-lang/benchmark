include("items.jl")
include("bom.jl")
include("lot_sizing.jl")
include("capacity.jl")
include("costing.jl")
include("report.jl")

using .Report: money, percent

struct ScheduleRow
    item::String
    week::Int
    quantity::Int
    line::Int
end

struct Inquiry
    id::String
    item::String
    quantity::Int
    week::Int
    line::Int
end

struct Demand
    item::String
    kind::Symbol
    week::Int
    quantity::Int
    orderid::String
    line::Int
    parent::String
    parentnumber::Int
end

Demand(item, kind, week, quantity; orderid="", line=0, parent="", parentnumber=0) = Demand(item, kind, week, quantity, orderid, line, parent, parentnumber)
demandkey(demand) = (demand.week, demand.kind == :MPS ? 0 : demand.kind == :ORDER ? 1 : 2, demand.line, demand.parent, demand.parentnumber)
rootkey(demand) = (demand.item, demand.kind == :MPS ? 0 : demand.kind == :ORDER ? 1 : 2, demand.week, demand.orderid)

function demandtext(demand)
    demand.kind == :SAFETY && return "SAFETY $(demand.item)"
    demand.kind == :MPS && return "MPS $(demand.item) week $(demand.week)"
    demand.kind == :ORDER && return "ORDER $(demand.orderid) $(demand.item) week $(demand.week)"
    return "$(demand.parent) order $(demand.parentnumber) week $(demand.week)"
end

struct PlannedOrder
    item::String
    number::Int
    receipt::Int
    quantity::Int
    original::Int
    release::Int
end

struct Allocation
    demand::Demand
    share::Int
end

mutable struct Supply
    kind::Symbol
    week::Int
    quantity::Int
    line::Int
    order::Union{Nothing,PlannedOrder}
    remaining::Int
    allocations::Vector{Allocation}
    roots::Vector{Demand}
end

Supply(kind, week, quantity; line=0, order=nothing) = Supply(kind, week, quantity, line, order, quantity, Allocation[], Demand[])
supplykey(supply) = (supply.week, supply.kind == :STOCK ? 0 : supply.kind == :RECEIPT ? 1 : 2, supply.line)

mutable struct ItemPlan
    item::Items.Item
    receipts::Vector{Int}
    demands::Vector{Demand}
    gross::Vector{Int}
    onhand::Vector{Int}
    net::Vector{Int}
    plannedreceipts::Vector{Int}
    plannedreleases::Vector{Int}
    orders::Vector{PlannedOrder}
    supplies::Vector{Supply}
    ordersupplies::Vector{Supply}
end

ItemPlan(item, horizon, receipts) = ItemPlan(item, receipts, Demand[], zeros(Int, horizon), zeros(Int, horizon), zeros(Int, horizon), zeros(Int, horizon), zeros(Int, horizon), PlannedOrder[], Supply[], Supply[])
pastdue(plan) = sum((order.quantity for order in plan.orders if order.original < 1); init=0)

struct Plan
    items::Dict{String,ItemPlan}
    loads::Dict{String,Vector{Int}}
    overloads::Dict{String,Vector{Int}}
end

mutable struct Promise
    inquiry::Inquiry
    week::Int
    materialweek::Int
    reason::String
end

struct PlanningData
    horizon::Int
    peg::Vector{String}
    treequantity::Int
    items::Dict{String,Items.Item}
    graph::Bom.Graph
    centers::Dict{String,Capacity.Center}
    routings::Dict{String,Vector{Capacity.Operation}}
    mps::Vector{Demand}
    receipts::Dict{String,Vector{ScheduleRow}}
    scheduled::Dict{String,Vector{Int}}
    inquiries::Vector{Inquiry}
    codes::Dict{String,Int}
    cumulative::Dict{String,Int}
    order::Vector{String}
    centerorder::Vector{String}
    errors::Vector{String}
end

rows(name) = [(number, String.(split(line, ','))) for (number, line) in enumerate(readlines(joinpath("input", name))) if number > 1]

function scheduleerror(item, week, quantity, items, horizon)
    !haskey(items, item) && return "unknown item $item"
    !(1 <= week <= horizon) && return "week $week outside horizon"
    quantity < 1 && return "bad quantity $quantity"
    return ""
end

function readschedule(name, items, horizon, errors, uniqueweeks)
    result = ScheduleRow[]
    seen = Set{Tuple{String,Int}}()
    for (number, fields) in rows(name)
        item, week, quantity = fields[1], parse(Int, fields[2]), parse(Int, fields[3])
        message = scheduleerror(item, week, quantity, items, horizon)
        isempty(message) && uniqueweeks && (item, week) in seen && (message = "duplicate $item week $week")
        if isempty(message)
            push!(result, ScheduleRow(item, week, quantity, number))
            push!(seen, (item, week))
        else
            push!(errors, "$name line $number: $message")
        end
    end
    return result
end

function PlanningData()
    horizon, treequantity, peg = 0, 0, String[]
    for line in readlines("input/params.txt")
        words = String.(split(line, ' '))
        if words[1] == "horizon"
            horizon = parse(Int, words[2])
        elseif words[1] == "peg"
            peg = words[2:end]
        else
            treequantity = parse(Int, words[2])
        end
    end
    errors = String[]
    items = Items.load("input/items.csv", errors)
    graph = Bom.load("input/bom.csv", items, errors)
    centers = Capacity.centers("input/workcenters.csv", errors)
    routings = Capacity.routings("input/routings.csv", items, centers, graph, errors)
    mpsrows = readschedule("mps.csv", items, horizon, errors, true)
    receipts = readschedule("receipts.csv", items, horizon, errors, false)
    inquiries = Inquiry[]
    for (number, fields) in rows("orders.csv")
        id, item, quantity, week = fields[1], fields[2], parse(Int, fields[3]), parse(Int, fields[4])
        message = any(inquiry -> inquiry.id == id, inquiries) ? "duplicate order $id" : scheduleerror(item, week, quantity, items, horizon)
        if isempty(message)
            push!(inquiries, Inquiry(id, item, quantity, week, number))
        else
            push!(errors, "orders.csv line $number: $message")
        end
    end
    codes = Bom.codes(graph, items)
    cumulative = Bom.cumulative(graph, items)
    order = sort!(collect(keys(items)); by=id -> (codes[id], id))
    centerorder = sort!(collect(keys(centers)))
    receiptmap = Dict(id => ScheduleRow[] for id in keys(items))
    scheduled = Dict(id => zeros(Int, horizon) for id in keys(items))
    for row in sort!(receipts; by=row -> (row.week, row.line))
        push!(receiptmap[row.item], row)
        scheduled[row.item][row.week] += row.quantity
    end
    mps = [Demand(row.item, :MPS, row.week, row.quantity) for row in mpsrows]
    return PlanningData(horizon, peg, treequantity, items, graph, centers, routings, mps, receiptmap, scheduled, inquiries, codes, cumulative, order, centerorder, errors)
end

function runmrp(data, inquiries)
    plans = Dict(id => ItemPlan(data.items[id], data.horizon, data.scheduled[id]) for id in data.order)
    for demand in [data.mps; inquiries]
        push!(plans[demand.item].demands, demand)
    end
    for id in data.order
        plan, item = plans[id], data.items[id]
        for demand in plan.demands
            plan.gross[demand.week] += demand.quantity
        end
        projected = item.onhand
        for week in 1:data.horizon
            available = projected + plan.receipts[week] - plan.gross[week]
            projected = available
            if available < item.safety
                quantity = LotSizing.quantity(item, week, available, plan.receipts, plan.gross, data.horizon)
                release = week - item.lead
                order = PlannedOrder(id, length(plan.orders) + 1, week, quantity, release, max(1, release))
                push!(plan.orders, order)
                plan.net[week] = item.safety - available
                plan.plannedreceipts[week] = quantity
                plan.plannedreleases[order.release] += quantity
                projected += quantity
            end
            plan.onhand[week] = projected
        end
        for order in plan.orders, edge in data.graph.children[id]
            push!(plans[edge.child].demands, Demand(edge.child, :DEPENDENT, order.release, Bom.need(edge, order.quantity); parent=id, parentnumber=order.number))
        end
    end
    loads = Dict(id => zeros(Int, data.horizon) for id in data.centerorder)
    for id in data.order
        operations = data.routings[id]
        for order in plans[id].orders, (index, operation) in enumerate(operations)
            week = Capacity.operationweek(order.receipt, data.items[id].lead, index - 1, length(operations))
            loads[operation.center][week] += Capacity.minutes(operation, order.quantity)
        end
    end
    overloads = Dict(id => [max(0, load - data.centers[id].available) for load in loads[id]] for id in data.centerorder)
    return Plan(plans, loads, overloads)
end

function capacityreason(data, current, trial)
    for center in data.centerorder, week in 1:data.horizon
        if trial.overloads[center][week] > current.overloads[center][week]
            return "$center week $week"
        end
    end
    return ""
end

function promiseinquiries(data, base)
    current = base
    promised, promises = Demand[], Promise[]
    for inquiry in data.inquiries
        promise = Promise(inquiry, 0, 0, "")
        for week in inquiry.week:data.horizon
            demand = Demand(inquiry.item, :ORDER, week, inquiry.quantity; orderid=inquiry.id, line=inquiry.line)
            trial = runmrp(data, [promised; demand])
            reason = ""
            for id in data.order
                if pastdue(trial.items[id]) > pastdue(current.items[id])
                    reason = id
                    break
                end
            end
            if isempty(reason)
                promise.materialweek == 0 && (promise.materialweek = week)
                reason = capacityreason(data, current, trial)
            end
            if isempty(reason)
                promise.week = week
                push!(promised, demand)
                current = trial
                break
            end
            week == inquiry.week && (promise.reason = reason)
        end
        push!(promises, promise)
    end
    return promises, current
end

parentsupply(plan, demand) = plan.items[demand.parent].ordersupplies[demand.parentnumber]

function pegplan!(data, plan)
    for id in data.order
        itemplan, item = plan.items[id], data.items[id]
        demands = sort(itemplan.demands; by=demandkey)
        item.safety > 0 && pushfirst!(demands, Demand(id, :SAFETY, 0, item.safety))
        supplies = Supply[]
        item.onhand > 0 && push!(supplies, Supply(:STOCK, 0, item.onhand))
        for receipt in data.receipts[id]
            push!(supplies, Supply(:RECEIPT, receipt.week, receipt.quantity; line=receipt.line))
        end
        for order in itemplan.orders
            push!(supplies, Supply(:ORDER, order.receipt, order.quantity; order=order))
        end
        sort!(supplies; by=supplykey)
        index = 1
        for demand in demands
            remaining = demand.quantity
            while remaining > 0
                while supplies[index].remaining == 0
                    index += 1
                end
                supply = supplies[index]
                share = min(remaining, supply.remaining)
                push!(supply.allocations, Allocation(demand, share))
                remaining -= share
                supply.remaining -= share
            end
        end
        itemplan.supplies = supplies
        itemplan.ordersupplies = filter(supply -> supply.kind == :ORDER, supplies)
        for supply in itemplan.ordersupplies
            roots = Dict{Tuple{String,Int,Int,String},Demand}()
            for allocation in supply.allocations
                demand = allocation.demand
                if demand.kind == :DEPENDENT
                    for root in parentsupply(plan, demand).roots
                        roots[rootkey(root)] = root
                    end
                else
                    roots[rootkey(demand)] = demand
                end
            end
            supply.roots = [roots[key] for key in sort!(collect(keys(roots)))]
        end
    end
end

depthlabel(depth) = repeat(".", depth) * string(depth)

function gridlines(data, plan)
    output = String[]
    for id in data.order
        itemplan, item = plan.items[id], data.items[id]
        push!(output, "ITEM $id LLC $(data.codes[id]) LT $(item.lead) LOT $(Items.label(item)) SS $(item.safety) OH $(item.onhand) $(item.description)")
        for (label, values) in (("WEEK", 1:data.horizon), ("GROSS", itemplan.gross), ("RECEIPTS", itemplan.receipts), ("ON_HAND", itemplan.onhand), ("NET", itemplan.net), ("PLAN_RCPT", itemplan.plannedreceipts), ("PLAN_REL", itemplan.plannedreleases))
            push!(output, Report.table(label, values, 6))
        end
        push!(output, "TOTAL gross $(sum(itemplan.gross)) receipts $(sum(itemplan.receipts)) planned $(sum(itemplan.plannedreceipts)) orders $(length(itemplan.orders)) ending $(last(itemplan.onhand))")
    end
    return output
end

function whereused!(output, graph, id, depth, extension)
    for edge in graph.parents[id]
        ext = extension * edge.quantity
        push!(output, "$(depthlabel(depth)) $(edge.parent) qty $(edge.quantity) ext $ext")
        whereused!(output, graph, edge.parent, depth + 1, ext)
    end
end

function allocationlines!(output, plan, supply, depth)
    for allocation in supply.allocations
        demand = allocation.demand
        push!(output, repeat(" ", depth * 2) * "ALLOC $(allocation.share) $(demandtext(demand))")
        if supply.kind == :ORDER && demand.kind == :DEPENDENT
            allocationlines!(output, plan, parentsupply(plan, demand), depth + 1)
        end
    end
end

function pegginglines(data, plan)
    output = String[]
    for id in data.peg
        itemplan = plan.items[id]
        push!(output, "PEG $id orders $(length(itemplan.orders))")
        whereused!(output, data.graph, id, 1, 1)
        for kind in (:STOCK, :RECEIPT, :ORDER), supply in itemplan.supplies
            supply.kind != kind && continue
            if kind == :STOCK
                push!(output, "STOCK quantity $(supply.quantity)")
            elseif kind == :RECEIPT
                push!(output, "RECEIPT line $(supply.line) week $(supply.week) quantity $(supply.quantity)")
            else
                order = supply.order
                push!(output, "ORDER $(order.number) receipt $(order.receipt) release $(order.release) quantity $(order.quantity)")
            end
            allocationlines!(output, plan, supply, 1)
            supply.remaining > 0 && push!(output, "  EXCESS $(supply.remaining)")
            append!(output, ["  ROOT $(demandtext(root))" for root in supply.roots])
        end
    end
    return output
end

function explosion!(output, totals, data, id, gross, extension, depth)
    for edge in data.graph.children[id]
        child = data.items[edge.child]
        ext, needed = extension * edge.quantity, Bom.need(edge, gross)
        totals[edge.child] = get(totals, edge.child, 0) + needed
        push!(output, "$(depthlabel(depth)) $(edge.child) qty $(edge.quantity) scrap $(edge.scrap) ext $ext gross $needed lt $(child.lead) cum $(data.cumulative[edge.child]) $(child.description)")
        explosion!(output, totals, data, edge.child, needed, ext, depth + 1)
    end
end

function bomlines(data)
    output = String[]
    for id in sort!(collect(keys(data.items)))
        (!Bom.manufactured(data.graph, id) || !isempty(data.graph.parents[id])) && continue
        item = data.items[id]
        push!(output, "TREE $id quantity $(data.treequantity)", "0 $id ext 1 gross $(data.treequantity) lt $(item.lead) cum $(data.cumulative[id]) $(item.description)")
        totals = Dict{String,Int}()
        explosion!(output, totals, data, id, data.treequantity, 1, 1)
        for child in sort!(collect(keys(totals)))
            push!(output, "SUM $child $(totals[child])")
        end
        path, current = [id], id
        while Bom.manufactured(data.graph, current)
            children = data.graph.children[current]
            best = first(children)
            for edge in children
                data.cumulative[edge.child] > data.cumulative[best.child] && (best = edge)
            end
            current = best.child
            push!(path, current)
        end
        push!(output, "CRITICAL $(join(path, " -> ")) cum $(data.cumulative[id])")
    end
    return output
end

function costlines(data, plan, costs)
    usages = Dict(id => sum(plan.items[id].gross) for id in data.order)
    values = Dict(id => usages[id] * costs[id].total for id in data.order)
    classes = Costing.abc(values)
    output = ["item,material,labor,total,usage,value,class"]
    for id in sort!(collect(keys(data.items)))
        cost = costs[id]
        push!(output, "$id,$(money(cost.material)),$(money(cost.labor)),$(money(cost.total)),$(usages[id]),$(money(values[id])),$(classes[id])")
    end
    return output
end

function exceptionlines(data, plan)
    messages = String[]
    for id in data.order
        item, itemplan = data.items[id], plan.items[id]
        item.onhand < item.safety && push!(messages, "BELOW_SAFETY $id on hand $(item.onhand) safety $(item.safety)")
        for order in itemplan.orders
            if order.original < 1
                push!(messages, "PAST_DUE $id order $(order.number) receipt $(order.receipt) release $(order.original) late $(1 - order.original) quantity $(order.quantity)")
            elseif order.original == 1
                push!(messages, "RELEASE $id order $(order.number) receipt $(order.receipt) quantity $(order.quantity)")
            end
        end
        balances = item.onhand .- cumsum(itemplan.gross)
        covered = 0
        for receipt in data.receipts[id]
            needweek = findfirst(balance -> balance + covered < item.safety, balances)
            text = "$id receipt line $(receipt.line) week $(receipt.week) quantity $(receipt.quantity)"
            if isnothing(needweek)
                push!(messages, "CANCEL $text")
            elseif needweek < receipt.week
                push!(messages, "EXPEDITE $text to $needweek")
            elseif needweek > receipt.week
                push!(messages, "DEFER $text to $needweek")
            end
            covered += receipt.quantity
        end
        Bom.manufactured(data.graph, id) && isempty(data.routings[id]) && push!(messages, "NO_ROUTING $id")
        sum(itemplan.gross) == 0 && item.onhand > 0 && push!(messages, "NO_DEMAND $id on hand $(item.onhand)")
    end
    for center in data.centerorder, week in 1:data.horizon
        plan.overloads[center][week] > 0 && push!(messages, "OVERLOAD $center week $week load $(plan.loads[center][week]) available $(data.centers[center].available)")
    end
    output = ["ERROR $error" for error in data.errors]
    append!(output, messages)
    kinds = ("BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER", "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD")
    counts = ["$(lowercase(kind)) $(count(message -> first(split(message, ' ')) == kind, messages))" for kind in kinds]
    push!(output, "SUMMARY errors $(length(data.errors)) $(join(counts, " "))")
    return output
end

function capacitylines(data, plan)
    output = String[]
    totals = Dict(id => sum(plan.loads[id]) for id in data.centerorder)
    for id in data.centerorder
        center = data.centers[id]
        loads, overloads = plan.loads[id], plan.overloads[id]
        leveled = Capacity.level(loads, center.available)
        peak = totals[id] > 0 ? argmax(loads) : 0
        push!(output, "CENTER $id minutes $(center.minutes) efficiency $(center.efficiency) available $(center.available) $(center.description)")
        for (label, values) in (("WEEK", 1:data.horizon), ("LOAD", loads), ("UTIL", [percent(load, center.available) for load in loads]), ("OVER", overloads), ("LEVELED", leveled))
            push!(output, Report.table(label, values, 7))
        end
        push!(output, "TOTAL load $(totals[id]) available $(center.available * data.horizon) utilization $(percent(totals[id], center.available * data.horizon)) overloaded $(count(>(0), overloads)) peak $peak backlog $(max(0, leveled[1] - center.available))")
    end
    ranked = sort(data.centerorder; lt=(a, b) -> totals[a] * data.centers[b].available > totals[b] * data.centers[a].available || totals[a] * data.centers[b].available == totals[b] * data.centers[a].available && a < b)
    for (rank, id) in enumerate(ranked)
        push!(output, "RANK $rank $id load $(totals[id]) utilization $(percent(totals[id], data.centers[id].available * data.horizon))")
    end
    return output
end

function promiselines(data, promises, base, final)
    output = String[]
    ontime, late, rejected = 0, 0, 0
    for promise in promises
        inquiry = promise.inquiry
        head = "ORDER $(inquiry.id) $(inquiry.item) quantity $(inquiry.quantity) requested $(inquiry.week)"
        material = promise.materialweek == 0 ? "none" : string(promise.materialweek)
        if promise.week == 0
            rejected += 1
            push!(output, "$head rejected material $material reason $(promise.reason)")
            continue
        elseif promise.week == inquiry.week
            ontime += 1
            push!(output, "$head promised $(promise.week)")
        else
            late += 1
            push!(output, "$head promised $(promise.week) late $(promise.week - inquiry.week) material $material reason $(promise.reason)")
        end
        for id in data.order, supply in final.items[id].ordersupplies
            if any(root -> root.kind == :ORDER && root.orderid == inquiry.id, supply.roots)
                order = supply.order
                push!(output, "  SUPPLY $id order $(order.number) receipt $(order.receipt) release $(order.release) quantity $(order.quantity)")
            end
        end
    end
    for id in data.order
        before, after = base.items[id], final.items[id]
        changed = findfirst(i -> before.plannedreceipts[i] != after.plannedreceipts[i], 1:data.horizon)
        if !isnothing(changed)
            push!(output, "CHANGE $id from $changed planned $(sum(before.plannedreceipts)) -> $(sum(after.plannedreceipts)) orders $(length(before.orders)) -> $(length(after.orders))")
        end
    end
    push!(output, "SUMMARY orders $(length(promises)) on_time $ontime late $late rejected $rejected")
    return output
end

function releaselines(data, plan)
    orders = [order for id in data.order for order in plan.items[id].orders if order.release == 1]
    sort!(orders; by=order -> (order.original, order.item, order.number))
    available = Dict(id => data.items[id].onhand + data.scheduled[id][1] for id in data.order)
    output = String[]
    made, readycount, bought, purchase = 0, 0, 0, 0
    for order in orders
        id, item = order.item, data.items[order.item]
        late = order.original < 1 ? " late $(1 - order.original)" : ""
        head = "$id order $(order.number) receipt $(order.receipt) quantity $(order.quantity)$late"
        if !Bom.manufactured(data.graph, id)
            value = order.quantity * item.material
            bought += 1
            purchase += value
            push!(output, "BUY $head value $(money(value))")
            continue
        end
        made += 1
        children = data.graph.children[id]
        needs = [Bom.need(edge, order.quantity) for edge in children]
        ready = all(needed <= available[edge.child] for (edge, needed) in zip(children, needs))
        ready && (readycount += 1)
        push!(output, "MAKE $head $(ready ? "READY" : "SHORT")")
        for (edge, needed) in zip(children, needs)
            have = available[edge.child]
            push!(output, "  PICK $(edge.child) need $needed available $have short $(max(0, needed - have))")
        end
        if ready
            for (edge, needed) in zip(children, needs)
                available[edge.child] -= needed
            end
        end
        operations = data.routings[id]
        for (index, operation) in enumerate(operations)
            week = Capacity.operationweek(order.receipt, item.lead, index - 1, length(operations))
            push!(output, "  OPERATION $(operation.number) $(operation.center) week $week minutes $(Capacity.minutes(operation, order.quantity))")
        end
    end
    push!(output, "SUMMARY make $made ready $readycount short $(made - readycount) buy $bought value $(money(purchase))")
    return output
end

function valuelines(data, plan, costs)
    output = ["week,inventory,purchases,labor"]
    for week in 1:data.horizon
        inventory, purchases, labor = 0, 0, 0
        for id in data.order
            itemplan, item = plan.items[id], data.items[id]
            inventory += itemplan.onhand[week] * costs[id].total
            if Bom.manufactured(data.graph, id)
                labor += itemplan.plannedreleases[week] * item.labor
            else
                purchases += itemplan.plannedreleases[week] * item.material
            end
        end
        push!(output, "$week,$(money(inventory)),$(money(purchases)),$(money(labor))")
    end
    return output
end

function main()
    data = PlanningData()
    base = runmrp(data, Demand[])
    promises, final = promiseinquiries(data, base)
    pegplan!(data, final)
    costs = Costing.rollup(data.items, data.graph, data.order)
    Report.writefile("mrp_grid.txt", gridlines(data, final))
    Report.writefile("pegging.txt", pegginglines(data, final))
    Report.writefile("bom_tree.txt", bomlines(data))
    Report.writefile("cost_rollup.csv", costlines(data, final, costs))
    Report.writefile("exceptions.txt", exceptionlines(data, final))
    Report.writefile("capacity.txt", capacitylines(data, final))
    Report.writefile("promises.txt", promiselines(data, promises, base, final))
    Report.writefile("releases.txt", releaselines(data, final))
    Report.writefile("value_plan.csv", valuelines(data, final, costs))
end

main()
