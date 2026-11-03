local M = {}

function M.lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end

function M.split(text, separator)
    local fields, start = {}, 1
    while true do
        local position = text:find(separator, start, true)
        fields[#fields + 1] = text:sub(start, position and position - 1 or #text)
        if not position then return fields end
        start = position + #separator
    end
end

function M.params(path)
    local settings = {}
    for _, line in ipairs(M.lines(path)) do
        local fields = M.split(line, " ")
        local key = table.remove(fields, 1)
        if key == "METHODS" then settings[key] = fields
        elseif key == "K_RANGE" or key == "ORDER_BINS" then
            for i, value in ipairs(fields) do fields[i] = tonumber(value) end
            settings[key] = fields
        else settings[key] = tonumber(fields[1]) end
    end
    return settings
end

function M.read(path)
    local data = {rows = {}, customers = {}, count = 0, duplicates = 0, zero = 0}
    local seen = {}
    for i, text in ipairs(M.lines(path)) do
        if i > 1 then
            local fields = M.split(text, ",")
            local row = {customer = fields[1], day = tonumber(fields[2]), order = fields[3], category = fields[4], amount = tonumber(fields[5])}
            data.count = data.count + 1
            data.customers[row.customer] = true
            if seen[text] then data.duplicates = data.duplicates + 1
            elseif row.amount == 0 then data.zero = data.zero + 1
            else data.rows[#data.rows + 1] = row end
            seen[text] = true
        end
    end
    return data
end

function M.orders(rows, first, last)
    local orders, by_id = {}, {}
    for _, row in ipairs(rows) do
        if first <= row.day and row.day <= last then
            local order = by_id[row.order]
            if not order then
                order = {id = row.order, customer = row.customer, day = row.day, net = 0, rows = {}}
                by_id[row.order] = order
                orders[#orders + 1] = order
            end
            order.day = math.min(order.day, row.day)
            order.net = order.net + row.amount
            order.rows[#order.rows + 1] = row
        end
    end
    return orders
end

function M.by_customer(orders)
    local groups = {}
    for _, order in ipairs(orders) do
        groups[order.customer] = groups[order.customer] or {}
        table.insert(groups[order.customer], order)
    end
    return groups
end

return M
