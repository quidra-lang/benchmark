const CATEGORIES = (
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled"
)

cents(text::String) = parse(Int, replace(text, "." => ""))

function money(amount::Int)
    magnitude = abs(amount)
    return (amount < 0 ? "-" : "") * string(div(magnitude, 100)) *
        "." * lpad(string(mod(magnitude, 100)), 2, '0')
end

signed_quantity(quantity::Int) = (quantity > 0 ? "+" : "") * string(quantity)
signed_money(amount::Int) = (amount > 0 ? "+" : "") * money(amount)

function margin(profit::Int, revenue::Int)
    revenue == 0 && return "n/a"
    tenths = div(abs(profit) * 1000, revenue)
    return (profit < 0 && tenths > 0 ? "-" : "") *
        string(div(tenths, 10)) * "." * string(mod(tenths, 10)) * "%"
end

struct CommandError <: Exception
    reason::String
end

fail(reason::String) = throw(CommandError(reason))

struct CardEntry
    day::Int
    kind::String
    warehouse::String
    quantity::Int
    value::Int
end

mutable struct Item
    code::String
    name::String
    level::Int
    last_cost::Union{Nothing, Int}
    card::Vector{CardEntry}
end

mutable struct Lot
    number::Int
    item::String
    warehouse::String
    kind::String
    day::Int
    initial_quantity::Int
    initial_cost::Int
    removed::Int
end

mutable struct StockLot
    lot::Lot
    quantity::Int
    cost::Int
end

struct Part
    lot::Lot
    quantity::Int
    cost::Int
end

mutable struct Order
    number::Int
    warehouse::String
    item::String
    day::Int
    price::Int
    ordered::Int
    shipped::Int
    backorder::Int
    cancelled::Int
    returned::Int
    revenue::Int
    cogs::Int
    issues::Vector{Part}
end

mutable struct Total
    quantity::Int
    value::Int
end

mutable struct Inventory
    day::Int
    stock::Dict{String, Dict{String, Dict{Int, StockLot}}}
    items::Dict{String, Item}
    lots::Vector{Lot}
    orders::Vector{Order}
    totals::Dict{String, Total}
    output::Vector{String}
end

function Inventory()
    totals = Dict(category => Total(0, 0) for category in CATEGORIES)
    return Inventory(1, Dict{String, Dict{String, Dict{Int, StockLot}}}(),
        Dict{String, Item}(), Lot[], Order[], totals, String[])
end

function emit!(inv::Inventory, indent::Int, parts...)
    push!(inv.output, repeat(" ", indent) * join(string.(parts), " "))
end

ordered_names(entries) = sort(collect(keys(entries)))
sum_quantity(stocks) = sum((stock.quantity for stock in stocks); init=0)
sum_value(stocks) = sum((stock.quantity * stock.cost for stock in stocks); init=0)

function warehouse(inv::Inventory, code::String)
    haskey(inv.stock, code) || fail("unknown warehouse " * code)
    return code
end

function item(inv::Inventory, code::String)
    haskey(inv.items, code) || fail("unknown item " * code)
    return inv.items[code]
end

function pair(inv::Inventory, w::String, code::String)
    warehouse(inv, w)
    return item(inv, code)
end

function lookup_order(inv::Inventory, text::String)
    number = parse(Int, text)
    1 <= number <= length(inv.orders) || fail("unknown order " * text)
    return inv.orders[number]
end

function lookup_lot(inv::Inventory, text::String)
    number = parse(Int, text)
    1 <= number <= length(inv.lots) || fail("unknown lot " * text)
    return inv.lots[number]
end

function require_quantity(quantity::Int)
    quantity != 0 || fail("invalid quantity")
end

function holdings(inv::Inventory, w::String, code::String)
    return get(inv.stock[w], code, Dict{Int, StockLot}())
end

stocks(inv::Inventory, w::String, code::String) = collect(values(holdings(inv, w, code)))

function fifo(inv::Inventory, w::String, code::String)
    return sort!(stocks(inv, w, code), by = s -> (s.lot.day, s.lot.number))
end

quantity(inv::Inventory, w::String, code::String) = sum_quantity(values(holdings(inv, w, code)))

function total_quantity(inv::Inventory, code::String)
    return sum((quantity(inv, w, code) for w in keys(inv.stock)); init=0)
end

function backorder(inv::Inventory, code::String)
    return sum((o.backorder for o in inv.orders if o.item == code); init=0)
end

function all_stocks(inv::Inventory)
    result = StockLot[]
    for warehouse in values(inv.stock)
        for lots in values(warehouse)
            append!(result, values(lots))
        end
    end
    return result
end

function require_stock(inv::Inventory, w::String, code::String, q::Int)
    held = quantity(inv, w, code)
    held >= q || fail("insufficient stock " * w * " " * code * " " * string(held))
end

function card_entry!(inv::Inventory, code::String, kind::String, w::String, q::Int, value::Int)
    push!(inv.items[code].card, CardEntry(inv.day, kind, w, q, value))
end

function accumulate!(inv::Inventory, category::String, q::Int, value::Int)
    total = inv.totals[category]
    total.quantity += q
    total.value += value
end

function add_stock!(inv::Inventory, w::String, lot::Lot, q::Int, cost::Int)
    bucket = get!(inv.stock[w], lot.item) do
        Dict{Int, StockLot}()
    end
    if haskey(bucket, lot.number)
        bucket[lot.number].quantity += q
    else
        bucket[lot.number] = StockLot(lot, q, cost)
    end
end

function create_lot!(inv::Inventory, w::String, code::String,
                     day::Int, q::Int, cost::Int, kind::String)
    lot = Lot(length(inv.lots) + 1, code, w, kind, day, q, cost, 0)
    push!(inv.lots, lot)
    add_stock!(inv, w, lot, q, cost)
    return lot
end

function issue!(inv::Inventory, w::String, code::String, q::Int)
    parts = Part[]
    cost = 0
    for stock in fifo(inv, w, code)
        q == 0 && break
        taken = min(q, stock.quantity)
        push!(parts, Part(stock.lot, taken, stock.cost))
        cost += taken * stock.cost
        stock.quantity -= taken
        q -= taken
        if stock.quantity == 0
            delete!(inv.stock[w][code], stock.lot.number)
        end
    end
    return parts, cost
end

function fulfil!(inv::Inventory, order::Order, q::Int, kind::String)
    q == 0 && return 0
    parts, cost = issue!(inv, order.warehouse, order.item, q)
    order.shipped += q
    order.backorder -= q
    order.revenue += q * order.price
    order.cogs += cost
    append!(order.issues, parts)
    accumulate!(inv, "shipped", q, cost)
    card_entry!(inv, order.item, kind, order.warehouse, -q, -cost)
    return cost
end

function allocate!(inv::Inventory, w::String, code::String)
    available = quantity(inv, w, code)
    for order in inv.orders
        available == 0 && break
        if order.warehouse != w || order.item != code || order.backorder == 0
            continue
        end
        q = min(available, order.backorder)
        cost = fulfil!(inv, order, q, "fill")
        revenue = q * order.price
        available -= q
        emit!(inv, 2, "FILL", "order", order.number, "qty", q, "revenue",
            money(revenue), "cogs", money(cost), "profit", money(revenue - cost),
            "backorder", order.backorder)
    end
end

function remove_parts!(parts::Vector{Part})
    for part in parts
        part.lot.removed += part.quantity
    end
end

function sales(inv::Inventory)
    rows = Dict{String, Total}()
    cogs = Dict{String, Int}()
    for order in inv.orders
        row = get!(rows, order.item) do
            Total(0, 0)
        end
        row.quantity += order.shipped - order.returned
        row.value += order.revenue
        cogs[order.item] = get(cogs, order.item, 0) + order.cogs
    end
    return rows, cogs
end

function margin_line!(inv::Inventory, label::String, sold::Int, revenue::Int, cogs::Int)
    profit = revenue - cogs
    emit!(inv, 2, label, "sold", sold, "revenue", money(revenue), "cogs",
        money(cogs), "profit", money(profit), "margin", margin(profit, revenue))
end

function aging_line!(inv::Inventory, label::String, buckets, monetary::Bool)
    parts = Any[label]
    for (index, name) in enumerate(("0-30", "31-60", "61-90", "91+"))
        push!(parts, name, monetary ? money(buckets[index]) : buckets[index])
    end
    emit!(inv, 2, parts...)
end

function command!(inv::Inventory, cmd::String, a::Vector{String})
    if cmd == "DAY"
        day = parse(Int, a[1])
        day > inv.day || fail("invalid day " * a[1])
        inv.day = day
        emit!(inv, 0, "DAY", day)

    elseif cmd == "WAREHOUSE"
        w = a[1]
        !haskey(inv.stock, w) || fail("duplicate warehouse " * w)
        inv.stock[w] = Dict{String, Dict{Int, StockLot}}()
        emit!(inv, 0, "WAREHOUSE", w)

    elseif cmd == "ITEM"
        code, level, name = a[1], parse(Int, a[2]), a[3]
        action = "added"
        if haskey(inv.items, code)
            entry = inv.items[code]
            entry.level, entry.name = level, name
            action = "updated"
        else
            inv.items[code] = Item(code, name, level, nothing, CardEntry[])
        end
        emit!(inv, 0, "ITEM", code, action, name, "level", level)

    elseif cmd == "RECEIVE"
        w, code = a[1], a[2]
        entry = pair(inv, w, code)
        q, cost, day = parse(Int, a[3]), cents(a[4]), parse(Int, a[5])
        require_quantity(q)
        day <= inv.day || fail("future day " * a[5])
        lot = create_lot!(inv, w, code, day, q, cost, "receive")
        entry.last_cost = cost
        accumulate!(inv, "received", q, q * cost)
        card_entry!(inv, code, "receive", w, q, q * cost)
        emit!(inv, 0, "RECEIVE", w, code, "lot", lot.number, "qty", q,
            "cost", money(cost), "day", day, "value", money(q * cost))
        allocate!(inv, w, code)

    elseif cmd == "SHIP"
        w, code = a[1], a[2]
        pair(inv, w, code)
        q = parse(Int, a[3])
        require_quantity(q)
        order = Order(length(inv.orders) + 1, w, code, inv.day, cents(a[4]), q,
            0, q, 0, 0, 0, 0, Part[])
        push!(inv.orders, order)
        shipped = min(q, quantity(inv, w, code))
        cost = fulfil!(inv, order, shipped, "ship")
        emit!(inv, 0, "SHIP", "order", order.number, w, code, "shipped", shipped,
            "revenue", money(order.revenue), "cogs", money(cost),
            "profit", money(order.revenue - cost), "backorder", order.backorder)

    elseif cmd == "CANCEL"
        order = lookup_order(inv, a[1])
        order.backorder > 0 || fail("no backorder " * a[1])
        order.cancelled += order.backorder
        order.backorder = 0
        emit!(inv, 0, "CANCEL", "order", order.number, "qty", order.cancelled)

    elseif cmd == "TRANSFER"
        source, destination, code = a[1], a[2], a[3]
        warehouse(inv, source)
        warehouse(inv, destination)
        source != destination || fail("same warehouse " * source)
        item(inv, code)
        q = parse(Int, a[4])
        require_quantity(q)
        require_stock(inv, source, code, q)
        parts, cost = issue!(inv, source, code, q)
        for part in parts
            add_stock!(inv, destination, part.lot, part.quantity, part.cost)
        end
        card_entry!(inv, code, "transfer-out", source, -q, -cost)
        card_entry!(inv, code, "transfer-in", destination, q, cost)
        emit!(inv, 0, "TRANSFER", source, "->", destination, code, "qty",
            q, "value", money(cost), "lots", length(parts))
        allocate!(inv, destination, code)

    elseif cmd == "ADJUST"
        w, code, change = a[1], a[2], a[3]
        pair(inv, w, code)
        q = parse(Int, change[2:end])
        require_quantity(q)
        if startswith(change, "+")
            cost = cents(a[4])
            lot = create_lot!(inv, w, code, inv.day, q, cost, "adjust")
            accumulate!(inv, "adjusted-in", q, q * cost)
            card_entry!(inv, code, "adjust", w, q, q * cost)
            emit!(inv, 0, "ADJUST", w, code, "+" * string(q),
                "lot", lot.number, "value", money(q * cost))
            allocate!(inv, w, code)
        else
            require_stock(inv, w, code, q)
            parts, cost = issue!(inv, w, code, q)
            remove_parts!(parts)
            accumulate!(inv, "adjusted-out", q, cost)
            card_entry!(inv, code, "adjust", w, -q, -cost)
            emit!(inv, 0, "ADJUST", w, code, "-" * string(q), "value", money(cost))
        end

    elseif cmd == "RETURN"
        order = lookup_order(inv, a[1])
        q, cost = parse(Int, a[2]), cents(a[3])
        require_quantity(q)
        available = order.shipped - order.returned
        q <= available || fail("return exceeds shipped " * a[1] * " " * string(available))
        lot = create_lot!(inv, order.warehouse, order.item, inv.day, q, cost, "return")
        refund = q * order.price
        order.returned += q
        order.revenue -= refund
        order.cogs -= q * cost
        accumulate!(inv, "returned", q, q * cost)
        card_entry!(inv, order.item, "return", order.warehouse, q, q * cost)
        emit!(inv, 0, "RETURN", "order", order.number, order.warehouse, order.item,
            "qty", q, "lot", lot.number, "refund", money(refund), "value", money(q * cost))
        allocate!(inv, order.warehouse, order.item)

    elseif cmd == "COUNT"
        w, code = a[1], a[2]
        entry = pair(inv, w, code)
        actual, held = parse(Int, a[3]), quantity(inv, w, code)
        if actual == held
            emit!(inv, 0, "COUNT", w, code, "qty", actual, "ok")
        elseif actual < held
            q = held - actual
            parts, cost = issue!(inv, w, code, q)
            remove_parts!(parts)
            accumulate!(inv, "adjusted-out", q, cost)
            card_entry!(inv, code, "count", w, -q, -cost)
            emit!(inv, 0, "COUNT", w, code, "qty", held, "->", actual,
                "shortage", q, "value", money(cost))
        else
            q = actual - held
            cost = isnothing(entry.last_cost) ? 0 : entry.last_cost
            lot = create_lot!(inv, w, code, inv.day, q, cost, "count")
            accumulate!(inv, "adjusted-in", q, q * cost)
            card_entry!(inv, code, "count", w, q, q * cost)
            emit!(inv, 0, "COUNT", w, code, "qty", held, "->", actual,
                "surplus", q, "lot", lot.number, "value", money(q * cost))
            allocate!(inv, w, code)
        end

    elseif cmd == "MARKET"
        item(inv, a[1])
        price = cents(a[2])
        changed, q, loss = 0, 0, 0
        for w in ordered_names(inv.stock)
            warehouse_loss = 0
            for stock in values(holdings(inv, w, a[1]))
                if stock.cost > price
                    warehouse_loss += stock.quantity * (stock.cost - price)
                    changed += 1
                    q += stock.quantity
                    stock.cost = price
                end
            end
            if warehouse_loss > 0
                card_entry!(inv, a[1], "writedown", w, 0, -warehouse_loss)
            end
            loss += warehouse_loss
        end
        accumulate!(inv, "written-down", q, loss)
        emit!(inv, 0, "MARKET", a[1], "price", money(price),
            "lots", changed, "qty", q, "loss", money(loss))

    elseif cmd == "RECALL"
        lot = lookup_lot(inv, a[1])
        held = Tuple{String, StockLot}[]
        for w in ordered_names(inv.stock)
            stock = get(holdings(inv, w, lot.item), lot.number, nothing)
            if !isnothing(stock)
                push!(held, (w, stock))
            end
        end
        isempty(held) && fail("nothing to recall " * a[1])
        q, value = 0, 0
        for (w, stock) in held
            q += stock.quantity
            value += stock.quantity * stock.cost
            delete!(inv.stock[w][lot.item], lot.number)
            card_entry!(inv, lot.item, "recall", w, -stock.quantity, -stock.quantity * stock.cost)
        end
        lot.removed += q
        accumulate!(inv, "recalled", q, value)
        emit!(inv, 0, "RECALL", "lot", lot.number, lot.item, "qty", q, "value", money(value))
        for (w, stock) in held
            emit!(inv, 2, w, "qty", stock.quantity, "value", money(stock.quantity * stock.cost))
        end

    elseif cmd == "EXPIRE"
        days = parse(Int, a[1])
        emit!(inv, 0, "EXPIRE", days)
        total_q, total_value = 0, 0
        for code in ordered_names(inv.items)
            for w in ordered_names(inv.stock)
                expired = filter(stock -> inv.day - stock.lot.day > days, stocks(inv, w, code))
                isempty(expired) && continue
                q, value = sum_quantity(expired), sum_value(expired)
                for stock in expired
                    stock.lot.removed += stock.quantity
                    delete!(inv.stock[w][code], stock.lot.number)
                end
                accumulate!(inv, "expired", q, value)
                card_entry!(inv, code, "expire", w, -q, -value)
                total_q += q
                total_value += value
                emit!(inv, 2, code, w, "lots", length(expired), "qty", q, "value", money(value))
            end
        end
        emit!(inv, 2, "total", "qty", total_q, "value", money(total_value))

    elseif cmd == "VALUE" || cmd == "AGING"
        warehouses = isempty(a) ? ordered_names(inv.stock) : [warehouse(inv, a[1])]
        if cmd == "VALUE"
            emit!(inv, 0, "VALUE", a...)
        else
            emit!(inv, 0, "AGING", a..., "day", inv.day)
        end
        total_q, total_value = 0, 0
        bucket_q, bucket_v = zeros(Int, 4), zeros(Int, 4)
        for code in ordered_names(inv.items)
            rows = [stocks(inv, w, code) for w in warehouses]
            selected = StockLot[]
            for row in rows
                append!(selected, row)
            end
            q = sum_quantity(selected)
            q == 0 && continue
            value = sum_value(selected)
            if cmd == "VALUE"
                emit!(inv, 2, code, "qty", q, "value", money(value), "avg", money(div(value, q)))
                if isempty(a)
                    for (w, row) in zip(warehouses, rows)
                        held = sum_quantity(row)
                        if held > 0
                            emit!(inv, 4, w, "qty", held, "value", money(sum_value(row)))
                        end
                    end
                end
            else
                item_buckets = zeros(Int, 4)
                for stock in selected
                    age = inv.day - stock.lot.day
                    bucket = age <= 30 ? 1 : (age <= 60 ? 2 : (age <= 90 ? 3 : 4))
                    item_buckets[bucket] += stock.quantity
                    bucket_q[bucket] += stock.quantity
                    bucket_v[bucket] += stock.quantity * stock.cost
                end
                aging_line!(inv, code, item_buckets, false)
            end
            total_q += q
            total_value += value
        end
        if cmd == "VALUE"
            emit!(inv, 2, "total", "qty", total_q, "value", money(total_value))
        else
            aging_line!(inv, "total", bucket_q, false)
            aging_line!(inv, "value", bucket_v, true)
        end

    elseif cmd == "LOTS"
        w, code = a[1], a[2]
        pair(inv, w, code)
        emit!(inv, 0, "LOTS", w, code)
        entries = fifo(inv, w, code)
        backorders = filter(o -> o.warehouse == w && o.item == code && o.backorder > 0, inv.orders)
        for stock in entries
            emit!(inv, 2, "lot", stock.lot.number, "day", stock.lot.day, "qty", stock.quantity,
                "cost", money(stock.cost), "value", money(stock.quantity * stock.cost),
                "age", inv.day - stock.lot.day)
        end
        for order in backorders
            emit!(inv, 2, "backorder", "order", order.number, "qty", order.backorder)
        end
        if isempty(entries) && isempty(backorders)
            emit!(inv, 2, "(none)")
        end

    elseif cmd == "REORDER" || cmd == "ITEMS"
        emit!(inv, 0, cmd)
        found = false
        for code in ordered_names(inv.items)
            entry = inv.items[code]
            q, pending = total_quantity(inv, code), backorder(inv, code)
            if cmd == "REORDER"
                q - pending > entry.level && continue
                emit!(inv, 2, code, entry.name, "onhand", q,
                    "backorder", pending, "level", entry.level)
            else
                emit!(inv, 2, code, entry.name, "level", entry.level,
                    "onhand", q, "backorder", pending, "cost",
                    isnothing(entry.last_cost) ? "none" : money(entry.last_cost))
            end
            found = true
        end
        !found && emit!(inv, 2, "(none)")

    elseif cmd == "MARGIN" || cmd == "TOP"
        rows, cogs = sales(inv)
        if cmd == "MARGIN"
            emit!(inv, 0, "MARGIN")
            total_q, revenue, total_cogs = 0, 0, 0
            for code in ordered_names(rows)
                row = rows[code]
                margin_line!(inv, code, row.quantity, row.value, cogs[code])
                total_q += row.quantity
                revenue += row.value
                total_cogs += cogs[code]
            end
            margin_line!(inv, "total", total_q, revenue, total_cogs)
        else
            k = parse(Int, a[1])
            emit!(inv, 0, "TOP", k)
            codes = ordered_names(rows)
            sort!(codes, by = code -> (-(rows[code].value - cogs[code]),
                -rows[code].value, code))
            for (rank, code) in enumerate(codes[1:min(k, length(codes))])
                row = rows[code]
                profit = row.value - cogs[code]
                emit!(inv, 2, rank, code, "profit", money(profit), "revenue",
                    money(row.value), "margin", margin(profit, row.value))
            end
            isempty(codes) && emit!(inv, 2, "(none)")
        end

    elseif cmd == "BACKORDERS"
        emit!(inv, 0, "BACKORDERS")
        open = filter(o -> o.backorder > 0, inv.orders)
        for order in open
            emit!(inv, 2, "order", order.number, order.warehouse, order.item, "qty",
                order.backorder, "day", order.day, "price", money(order.price))
        end
        isempty(open) && emit!(inv, 2, "(none)")

    elseif cmd == "ORDER"
        order = lookup_order(inv, a[1])
        emit!(inv, 0, "ORDER", order.number, order.warehouse, order.item,
            "day", order.day, "price", money(order.price))
        emit!(inv, 2, "ordered", order.ordered, "shipped", order.shipped,
            "backorder", order.backorder, "cancelled", order.cancelled,
            "returned", order.returned)
        for part in order.issues
            emit!(inv, 2, "lot", part.lot.number, "qty", part.quantity, "cost", money(part.cost))
        end
        emit!(inv, 2, "revenue", money(order.revenue), "cogs",
            money(order.cogs), "profit", money(order.revenue - order.cogs))

    elseif cmd == "TRACE"
        lot = lookup_lot(inv, a[1])
        emit!(inv, 0, "TRACE", "lot", lot.number, lot.item, lot.kind, lot.warehouse,
            "day", lot.day, "qty", lot.initial_quantity, "cost", money(lot.initial_cost))
        for w in ordered_names(inv.stock)
            stock = get(holdings(inv, w, lot.item), lot.number, nothing)
            if !isnothing(stock)
                emit!(inv, 2, "held", w, "qty", stock.quantity, "cost", money(stock.cost))
            end
        end
        for order in inv.orders
            q = sum((part.quantity for part in order.issues if part.lot.number == lot.number); init=0)
            q > 0 && emit!(inv, 2, "order", order.number, "qty", q)
        end
        lot.removed > 0 && emit!(inv, 2, "removed", "qty", lot.removed)

    elseif cmd == "CARD"
        entry = item(inv, a[1])
        emit!(inv, 0, "CARD", entry.code, entry.name)
        q, value = 0, 0
        for card in entry.card
            q += card.quantity
            value += card.value
            emit!(inv, 2, "day", card.day, card.kind, card.warehouse,
                signed_quantity(card.quantity), signed_money(card.value),
                "balance", q, money(value))
        end
        isempty(entry.card) && emit!(inv, 2, "(none)")

    elseif cmd == "STATUS"
        emit!(inv, 0, "STATUS")
        for w in ordered_names(inv.stock)
            current = inv.stock[w]
            skus = count(x -> !isempty(x), values(current))
            selected = StockLot[]
            for holdings in values(current)
                append!(selected, values(holdings))
            end
            pending = sum((o.backorder for o in inv.orders if o.warehouse == w); init=0)
            emit!(inv, 2, w, "skus", skus, "qty", sum_quantity(selected),
                "value", money(sum_value(selected)), "backorder", pending)
        end
        isempty(inv.stock) && emit!(inv, 2, "(none)")

    elseif cmd == "SUMMARY"
        emit!(inv, 0, "SUMMARY")
        for category in CATEGORIES
            total = inv.totals[category]
            emit!(inv, 2, category, "qty", total.quantity, "value", money(total.value))
        end
        selected = all_stocks(inv)
        emit!(inv, 2, "on-hand", "qty", sum_quantity(selected), "value", money(sum_value(selected)))
        open = count(o -> o.backorder > 0, inv.orders)
        pending = sum((o.backorder for o in inv.orders); init=0)
        emit!(inv, 2, "orders", length(inv.orders), "open", open, "backorder", pending)
    end
end

function execute!(inv::Inventory, line::String)
    tokens = String.(split(line, ' '))
    cmd, args = tokens[1], tokens[2:end]
    try
        command!(inv, cmd, args)
    catch error
        if error isa CommandError
            emit!(inv, 0, "ERROR", error.reason)
        else
            rethrow()
        end
    end
end

n = parse(Int, readline())
inventory = Inventory()
for _ in 1:n
    execute!(inventory, readline())
end
println(join(inventory.output, "\n"))
