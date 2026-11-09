local M = {names = {"recency", "frequency", "monetary", "basket", "categories", "tenure"}}

function M.root(feature) return feature >= 2 and feature <= 4 end

function M.transform(values)
    local transformed = {}
    for i, value in ipairs(values) do transformed[i] = M.root(i) and math.sqrt(value) or value + 0.0 end
    return transformed
end

function M.customers(orders, day)
    local groups, ids = {}, {}
    for _, order in ipairs(orders) do
        if order.net > 0 then
            if not groups[order.customer] then groups[order.customer] = {}; ids[#ids + 1] = order.customer end
            table.insert(groups[order.customer], order)
        end
    end
    table.sort(ids)
    local customers = {}
    for _, id in ipairs(ids) do
        local purchases, category_spend = groups[id], {}
        local first, last, spend = purchases[1].day, purchases[1].day, 0
        for _, order in ipairs(purchases) do
            first, last, spend = math.min(first, order.day), math.max(last, order.day), spend + order.net
            for _, row in ipairs(order.rows) do category_spend[row.category] = (category_spend[row.category] or 0) + row.amount end
        end
        local categories = 0
        for _, amount in pairs(category_spend) do if amount > 0 then categories = categories + 1 end end
        local monetary = spend / 100
        local raw = {day - last, #purchases, monetary, monetary / #purchases, categories, day - first}
        customers[#customers + 1] = {id = id, orders = purchases, spend = spend, category_spend = category_spend, raw = raw, transformed = M.transform(raw)}
    end
    return customers
end

function M.sum(values)
    local total = 0.0
    for _, value in ipairs(values) do total = total + value end
    return total
end

function M.mean(values) return M.sum(values) / #values end

function M.sd(values)
    local center, total = M.mean(values), 0.0
    for _, value in ipairs(values) do local delta = value - center; total = total + delta * delta end
    return math.sqrt(total / (#values - 1))
end

function M.scaling(customers)
    local scaling = {}
    for feature = 1, 6 do
        local raw, transformed = {}, {}
        for i, customer in ipairs(customers) do raw[i], transformed[i] = customer.raw[feature], customer.transformed[feature] end
        scaling[feature] = {raw_mean = M.mean(raw), raw_sd = M.sd(raw), mean = M.mean(transformed), sd = M.sd(transformed)}
    end
    return scaling
end

function M.standardize(values, scaling)
    local point = {}
    for i, value in ipairs(values) do point[i] = scaling[i].sd == 0 and 0.0 or (value - scaling[i].mean) / scaling[i].sd end
    return point
end

function M.correlation(points, first, second)
    local total = 0.0
    for _, point in ipairs(points) do total = total + point[first] * point[second] end
    return total / (#points - 1)
end

return M
