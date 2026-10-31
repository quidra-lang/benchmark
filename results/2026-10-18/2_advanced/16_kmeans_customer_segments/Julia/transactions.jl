struct Params
    reference_day::Int
    snapshot_day::Int
    outcome_days::Int
    k_min::Int
    k_max::Int
    methods::Vector{String}
    restarts::Int
    max_iterations::Int
    seed::Int
    subsamples::Int
    subsample_percent::Int
    outlier_sd::Float64
    overdue_factor::Int
    order_bins::Vector{Int}
    top_categories::Int
    top_customers::Int
    period_days::Int
    periods::Int
end

struct Transaction
    customer::String
    day::Int
    order_id::String
    category::String
    amount::Int
end

struct TransactionData
    row_count::Int
    duplicates::Int
    free::Int
    valid_rows::Vector{Transaction}
    customers::Set{String}
end

mutable struct Order
    id::String
    customer::String
    day::Int
    net::Int
    rows::Vector{Transaction}
end

function read_params(path)
    entries = Dict(fields[1] => fields[2:end] for fields in split.(readlines(path)))
    integer(key) = parse(Int, entries[key][1])
    Params(integer("REFERENCE_DAY"), integer("SNAPSHOT_DAY"), integer("OUTCOME_DAYS"), parse.(Int, entries["K_RANGE"])...,
        String.(entries["METHODS"]), integer("RESTARTS"), integer("MAX_ITERATIONS"), integer("SEED"), integer("SUBSAMPLES"),
        integer("SUBSAMPLE_PERCENT"), parse(Float64, entries["OUTLIER_SD"][1]), integer("OVERDUE_FACTOR"), parse.(Int, entries["ORDER_BINS"]),
        integer("TOP_CATEGORIES"), integer("TOP_CUSTOMERS"), integer("PERIOD_DAYS"), integer("PERIODS"))
end

function read_transactions(path)
    rows = readlines(path)[2:end]
    seen, customers = Set{String}(), Set{String}()
    valid = Transaction[]
    duplicates = free = 0
    for line in rows
        id, day, order, category, amount = split(line, ',')
        row = Transaction(id, parse(Int, day), order, category, parse(Int, amount))
        push!(customers, id)
        if line in seen
            duplicates += 1
        elseif row.amount == 0
            free += 1
        else
            push!(valid, row)
        end
        push!(seen, line)
    end
    TransactionData(length(rows), duplicates, free, valid, customers)
end

function group_orders(rows, first_day, last_day)
    orders, positions = Order[], Dict{String,Int}()
    for row in rows
        first_day <= row.day <= last_day || continue
        if !haskey(positions, row.order_id)
            positions[row.order_id] = length(orders) + 1
            push!(orders, Order(row.order_id, row.customer, row.day, 0, Transaction[]))
        end
        order = orders[positions[row.order_id]]
        order.day = min(order.day, row.day)
        order.net += row.amount
        push!(order.rows, row)
    end
    orders
end

function orders_by_customer(orders)
    grouped = Dict{String,Vector{Order}}()
    for order in orders
        push!(get!(grouped, order.customer, Order[]), order)
    end
    grouped
end
