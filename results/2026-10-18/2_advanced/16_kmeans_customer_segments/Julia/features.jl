const FEATURE_NAMES = ("recency", "frequency", "monetary", "basket", "categories", "tenure")
const SQRT_FEATURES = (false, true, true, true, false, false)

struct Customer
    id::String
    orders::Vector{Order}
    recency::Int
    frequency::Int
    spend::Int
    basket::Float64
    categories::Int
    tenure::Int
    category_spend::Dict{String,Int}
end

function Customer(id, orders, day)
    spend = sum(order.net for order in orders)
    category_spend = Dict{String,Int}()
    for order in orders, row in order.rows
        category_spend[row.category] = get(category_spend, row.category, 0) + row.amount
    end
    Customer(id, orders, day - maximum(order.day for order in orders), length(orders), spend, (spend / 100) / length(orders),
        count(>(0), values(category_spend)), day - minimum(order.day for order in orders), category_spend)
end

raw_values(customer) = Float64[customer.recency, customer.frequency, customer.spend / 100, customer.basket, customer.categories, customer.tenure]
transformed(customer) = [root ? sqrt(value) : value for (value, root) in zip(raw_values(customer), SQRT_FEATURES)]

function eligible_customers(orders, day)
    grouped = orders_by_customer([order for order in orders if order.net > 0])
    [Customer(id, grouped[id], day) for id in sort(collect(keys(grouped)))]
end

ordered_sum(values) = foldl(+, values; init=0.0)
mean(values) = ordered_sum(values) / length(values)

function sample_sd(values)
    average = mean(values)
    sqrt(ordered_sum((value - average) * (value - average) for value in values) / (length(values) - 1))
end

function standardization(rows)
    columns = [[row[feature] for row in rows] for feature in eachindex(FEATURE_NAMES)]
    mean.(columns), sample_sd.(columns)
end

standardize(values, means, sds) = [sd == 0 ? 0.0 : (value - average) / sd for (value, average, sd) in zip(values, means, sds)]
correlation(points, first, second) = ordered_sum(point[first] * point[second] for point in points) / (length(points) - 1)
