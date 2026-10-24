local categories = {
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled"
}

local function cents(text)
    return tonumber((text:gsub("%.", "")))
end

local function money(amount)
    local sign = amount < 0 and "-" or ""
    local value = math.abs(amount)
    return string.format("%s%d.%02d", sign, value // 100, value % 100)
end

local function signed_quantity(q)
    return (q > 0 and "+" or "") .. q
end

local function signed_money(value)
    return (value > 0 and "+" or "") .. money(value)
end

local function margin(profit, revenue)
    if revenue == 0 then return "n/a" end
    local tenths = math.abs(profit) * 1000 // revenue
    return string.format("%s%d.%d%%", profit < 0 and tenths > 0 and "-" or "",
        tenths // 10, tenths % 10)
end

local function sorted_keys(entries)
    local keys = {}
    for key in pairs(entries) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function sum_quantity(stocks)
    local q = 0
    for _, stock in pairs(stocks) do q = q + stock.quantity end
    return q
end

local function sum_value(stocks)
    local value = 0
    for _, stock in pairs(stocks) do
        value = value + stock.quantity * stock.cost
    end
    return value
end

local function fail(reason)
    error({reason = reason}, 0)
end

local Inventory = {}
Inventory.__index = Inventory

function Inventory.new()
    local totals = {}
    for _, name in ipairs(categories) do
        totals[name] = {quantity = 0, value = 0}
    end
    return setmetatable({
        day = 1, stock = {}, items = {}, lots = {}, orders = {},
        totals = totals, output = {}
    }, Inventory)
end

function Inventory:emit(indent, ...)
    local parts = {...}
    for i, part in ipairs(parts) do parts[i] = tostring(part) end
    self.output[#self.output + 1] = string.rep(" ", indent) .. table.concat(parts, " ")
end

function Inventory:warehouse(code)
    if not self.stock[code] then fail("unknown warehouse " .. code) end
    return code
end

function Inventory:item(code)
    if not self.items[code] then fail("unknown item " .. code) end
    return self.items[code]
end

function Inventory:pair(warehouse, code)
    self:warehouse(warehouse)
    return self:item(code)
end

function Inventory:order(number)
    number = tonumber(number)
    if number < 1 or number > #self.orders then
        fail("unknown order " .. number)
    end
    return self.orders[number]
end

function Inventory:lot(number)
    number = tonumber(number)
    if number < 1 or number > #self.lots then
        fail("unknown lot " .. number)
    end
    return self.lots[number]
end

function Inventory:require_quantity(q)
    if q == 0 then fail("invalid quantity") end
end

function Inventory:holdings(warehouse, code)
    return self.stock[warehouse][code] or {}
end

function Inventory:stocks(warehouse, code)
    local stocks = {}
    for _, stock in pairs(self:holdings(warehouse, code)) do
        stocks[#stocks + 1] = stock
    end
    return stocks
end

function Inventory:fifo(warehouse, code)
    local stocks = self:stocks(warehouse, code)
    table.sort(stocks, function(a, b)
        if a.lot.day ~= b.lot.day then return a.lot.day < b.lot.day end
        return a.lot.number < b.lot.number
    end)
    return stocks
end

function Inventory:quantity(warehouse, code)
    return sum_quantity(self:holdings(warehouse, code))
end

function Inventory:total_quantity(code)
    local result = 0
    for warehouse in pairs(self.stock) do
        result = result + self:quantity(warehouse, code)
    end
    return result
end

function Inventory:backorder(code)
    local result = 0
    for _, order in ipairs(self.orders) do
        if order.item == code then result = result + order.backorder end
    end
    return result
end

function Inventory:all_stocks()
    local result = {}
    for warehouse in pairs(self.stock) do
        for code in pairs(self.stock[warehouse]) do
            for _, stock in pairs(self.stock[warehouse][code]) do
                result[#result + 1] = stock
            end
        end
    end
    return result
end

function Inventory:require_stock(warehouse, code, quantity)
    local held = self:quantity(warehouse, code)
    if held < quantity then
        fail("insufficient stock " .. warehouse .. " " .. code .. " " .. held)
    end
end

function Inventory:card_entry(code, kind, warehouse, quantity, value)
    local entries = self.items[code].card
    entries[#entries + 1] = {
        day = self.day, kind = kind, warehouse = warehouse,
        quantity = quantity, value = value
    }
end

function Inventory:accumulate(category, quantity, value)
    local entry = self.totals[category]
    entry.quantity = entry.quantity + quantity
    entry.value = entry.value + value
end

function Inventory:add_stock(warehouse, lot, quantity, cost)
    if not self.stock[warehouse][lot.item] then
        self.stock[warehouse][lot.item] = {}
    end
    local holdings = self.stock[warehouse][lot.item]
    if holdings[lot.number] then
        holdings[lot.number].quantity = holdings[lot.number].quantity + quantity
    else
        holdings[lot.number] = {lot = lot, quantity = quantity, cost = cost}
    end
end

function Inventory:create_lot(warehouse, code, day, quantity, cost, kind)
    local lot = {
        number = #self.lots + 1, item = code, day = day,
        initial_quantity = quantity, initial_cost = cost,
        warehouse = warehouse, kind = kind, removed = 0
    }
    self.lots[#self.lots + 1] = lot
    self:add_stock(warehouse, lot, quantity, cost)
    return lot
end

function Inventory:issue(warehouse, code, quantity)
    local parts, cost = {}, 0
    for _, stock in ipairs(self:fifo(warehouse, code)) do
        if quantity == 0 then break end
        local taken = math.min(quantity, stock.quantity)
        parts[#parts + 1] = {lot = stock.lot, quantity = taken, cost = stock.cost}
        cost = cost + taken * stock.cost
        stock.quantity = stock.quantity - taken
        quantity = quantity - taken
        if stock.quantity == 0 then
            self.stock[warehouse][code][stock.lot.number] = nil
        end
    end
    return parts, cost
end

function Inventory:fulfil(order, quantity, kind)
    if quantity == 0 then return 0 end
    local parts, cost = self:issue(order.warehouse, order.item, quantity)
    order.shipped = order.shipped + quantity
    order.backorder = order.backorder - quantity
    order.revenue = order.revenue + quantity * order.price
    order.cogs = order.cogs + cost
    for _, part in ipairs(parts) do
        order.issues[#order.issues + 1] = part
    end
    self:accumulate("shipped", quantity, cost)
    self:card_entry(order.item, kind, order.warehouse, -quantity, -cost)
    return cost
end

function Inventory:allocate(warehouse, code)
    local available = self:quantity(warehouse, code)
    for _, order in ipairs(self.orders) do
        if available == 0 then break end
        if order.warehouse == warehouse and order.item == code and order.backorder > 0 then
            local q = math.min(available, order.backorder)
            local cost = self:fulfil(order, q, "fill")
            local revenue = q * order.price
            available = available - q
            self:emit(2, "FILL", "order", order.number, "qty", q,
                "revenue", money(revenue), "cogs", money(cost),
                "profit", money(revenue - cost), "backorder", order.backorder)
        end
    end
end

function Inventory:remove_parts(parts)
    for _, part in ipairs(parts) do
        part.lot.removed = part.lot.removed + part.quantity
    end
end

function Inventory:sales()
    local rows = {}
    for _, order in ipairs(self.orders) do
        local row = rows[order.item]
        if not row then
            row = {quantity = 0, revenue = 0, cogs = 0}
            rows[order.item] = row
        end
        row.quantity = row.quantity + order.shipped - order.returned
        row.revenue = row.revenue + order.revenue
        row.cogs = row.cogs + order.cogs
    end
    return rows
end

function Inventory:margin_line(label, row)
    local profit = row.revenue - row.cogs
    self:emit(2, label, "sold", row.quantity, "revenue", money(row.revenue),
        "cogs", money(row.cogs), "profit", money(profit),
        "margin", margin(profit, row.revenue))
end

function Inventory:aging_line(label, buckets, monetary)
    local labels = {"0-30", "31-60", "61-90", "91+"}
    local parts = {label}
    for i = 1, 4 do
        parts[#parts + 1] = labels[i]
        parts[#parts + 1] = monetary and money(buckets[i]) or tostring(buckets[i])
    end
    self:emit(2, table.unpack(parts))
end

function Inventory:command(cmd, a)
    if cmd == "DAY" then
        local day = tonumber(a[1])
        if day <= self.day then fail("invalid day " .. a[1]) end
        self.day = day
        self:emit(0, "DAY", day)

    elseif cmd == "WAREHOUSE" then
        local warehouse = a[1]
        if self.stock[warehouse] then fail("duplicate warehouse " .. warehouse) end
        self.stock[warehouse] = {}
        self:emit(0, "WAREHOUSE", warehouse)

    elseif cmd == "ITEM" then
        local code, level, name = a[1], tonumber(a[2]), a[3]
        local item = self.items[code]
        local action
        if item then
            item.level, item.name = level, name
            action = "updated"
        else
            self.items[code] = {code = code, level = level, name = name, card = {}}
            action = "added"
        end
        self:emit(0, "ITEM", code, action, name, "level", level)

    elseif cmd == "RECEIVE" then
        local warehouse, code = a[1], a[2]
        local item = self:pair(warehouse, code)
        local q, cost, day = tonumber(a[3]), cents(a[4]), tonumber(a[5])
        self:require_quantity(q)
        if day > self.day then fail("future day " .. a[5]) end
        local lot = self:create_lot(warehouse, code, day, q, cost, "receive")
        item.last_cost = cost
        self:accumulate("received", q, q * cost)
        self:card_entry(code, "receive", warehouse, q, q * cost)
        self:emit(0, "RECEIVE", warehouse, code, "lot", lot.number,
            "qty", q, "cost", money(cost), "day", day, "value", money(q * cost))
        self:allocate(warehouse, code)

    elseif cmd == "SHIP" then
        local warehouse, code = a[1], a[2]
        self:pair(warehouse, code)
        local q = tonumber(a[3])
        self:require_quantity(q)
        local order = {
            number = #self.orders + 1, warehouse = warehouse, item = code,
            day = self.day, price = cents(a[4]), ordered = q, shipped = 0,
            backorder = q, cancelled = 0, returned = 0, revenue = 0, cogs = 0,
            issues = {}
        }
        self.orders[#self.orders + 1] = order
        local shipped = math.min(q, self:quantity(warehouse, code))
        local cost = self:fulfil(order, shipped, "ship")
        self:emit(0, "SHIP", "order", order.number, warehouse, code, "shipped",
            shipped, "revenue", money(order.revenue), "cogs", money(cost),
            "profit", money(order.revenue - cost), "backorder", order.backorder)

    elseif cmd == "CANCEL" then
        local order = self:order(a[1])
        if order.backorder == 0 then fail("no backorder " .. a[1]) end
        order.cancelled = order.cancelled + order.backorder
        order.backorder = 0
        self:emit(0, "CANCEL", "order", order.number, "qty", order.cancelled)

    elseif cmd == "TRANSFER" then
        local source, destination, code = a[1], a[2], a[3]
        self:warehouse(source)
        self:warehouse(destination)
        if source == destination then fail("same warehouse " .. source) end
        self:item(code)
        local q = tonumber(a[4])
        self:require_quantity(q)
        self:require_stock(source, code, q)
        local parts, cost = self:issue(source, code, q)
        for _, part in ipairs(parts) do
            self:add_stock(destination, part.lot, part.quantity, part.cost)
        end
        self:card_entry(code, "transfer-out", source, -q, -cost)
        self:card_entry(code, "transfer-in", destination, q, cost)
        self:emit(0, "TRANSFER", source, "->", destination, code,
            "qty", q, "value", money(cost), "lots", #parts)
        self:allocate(destination, code)

    elseif cmd == "ADJUST" then
        local warehouse, code, change = a[1], a[2], a[3]
        self:pair(warehouse, code)
        local q = tonumber(change:sub(2))
        self:require_quantity(q)
        if change:sub(1, 1) == "+" then
            local cost = cents(a[4])
            local lot = self:create_lot(warehouse, code, self.day, q, cost, "adjust")
            self:accumulate("adjusted-in", q, q * cost)
            self:card_entry(code, "adjust", warehouse, q, q * cost)
            self:emit(0, "ADJUST", warehouse, code, "+" .. q,
                "lot", lot.number, "value", money(q * cost))
            self:allocate(warehouse, code)
        else
            self:require_stock(warehouse, code, q)
            local parts, cost = self:issue(warehouse, code, q)
            self:remove_parts(parts)
            self:accumulate("adjusted-out", q, cost)
            self:card_entry(code, "adjust", warehouse, -q, -cost)
            self:emit(0, "ADJUST", warehouse, code, "-" .. q, "value", money(cost))
        end

    elseif cmd == "RETURN" then
        local order = self:order(a[1])
        local q, cost = tonumber(a[2]), cents(a[3])
        self:require_quantity(q)
        local available = order.shipped - order.returned
        if q > available then
            fail("return exceeds shipped " .. a[1] .. " " .. available)
        end
        local lot = self:create_lot(order.warehouse, order.item, self.day, q, cost, "return")
        local refund = q * order.price
        order.returned = order.returned + q
        order.revenue = order.revenue - refund
        order.cogs = order.cogs - q * cost
        self:accumulate("returned", q, q * cost)
        self:card_entry(order.item, "return", order.warehouse, q, q * cost)
        self:emit(0, "RETURN", "order", order.number, order.warehouse, order.item,
            "qty", q, "lot", lot.number, "refund", money(refund), "value", money(q * cost))
        self:allocate(order.warehouse, order.item)

    elseif cmd == "COUNT" then
        local warehouse, code = a[1], a[2]
        local item = self:pair(warehouse, code)
        local actual, held = tonumber(a[3]), self:quantity(warehouse, code)
        if actual == held then
            self:emit(0, "COUNT", warehouse, code, "qty", actual, "ok")
        elseif actual < held then
            local q = held - actual
            local parts, cost = self:issue(warehouse, code, q)
            self:remove_parts(parts)
            self:accumulate("adjusted-out", q, cost)
            self:card_entry(code, "count", warehouse, -q, -cost)
            self:emit(0, "COUNT", warehouse, code, "qty", held, "->", actual,
                "shortage", q, "value", money(cost))
        else
            local q = actual - held
            local cost = item.last_cost or 0
            local lot = self:create_lot(warehouse, code, self.day, q, cost, "count")
            self:accumulate("adjusted-in", q, q * cost)
            self:card_entry(code, "count", warehouse, q, q * cost)
            self:emit(0, "COUNT", warehouse, code, "qty", held, "->", actual,
                "surplus", q, "lot", lot.number, "value", money(q * cost))
            self:allocate(warehouse, code)
        end

    elseif cmd == "MARKET" then
        local code = a[1]
        self:item(code)
        local price = cents(a[2])
        local changed, q, loss = 0, 0, 0
        for _, warehouse in ipairs(sorted_keys(self.stock)) do
            local warehouse_loss = 0
            for _, stock in pairs(self:holdings(warehouse, code)) do
                if stock.cost > price then
                    warehouse_loss = warehouse_loss + stock.quantity * (stock.cost - price)
                    changed = changed + 1
                    q = q + stock.quantity
                    stock.cost = price
                end
            end
            if warehouse_loss > 0 then
                self:card_entry(code, "writedown", warehouse, 0, -warehouse_loss)
            end
            loss = loss + warehouse_loss
        end
        self:accumulate("written-down", q, loss)
        self:emit(0, "MARKET", code, "price", money(price), "lots",
            changed, "qty", q, "loss", money(loss))

    elseif cmd == "RECALL" then
        local lot = self:lot(a[1])
        local held = {}
        for _, warehouse in ipairs(sorted_keys(self.stock)) do
            local stock = self:holdings(warehouse, lot.item)[lot.number]
            if stock then held[#held + 1] = {warehouse = warehouse, stock = stock} end
        end
        if #held == 0 then fail("nothing to recall " .. a[1]) end
        local q, value = 0, 0
        for _, entry in ipairs(held) do
            local stock = entry.stock
            q = q + stock.quantity
            value = value + stock.quantity * stock.cost
            self.stock[entry.warehouse][lot.item][lot.number] = nil
            self:card_entry(lot.item, "recall", entry.warehouse,
                -stock.quantity, -stock.quantity * stock.cost)
        end
        lot.removed = lot.removed + q
        self:accumulate("recalled", q, value)
        self:emit(0, "RECALL", "lot", lot.number, lot.item, "qty", q, "value", money(value))
        for _, entry in ipairs(held) do
            self:emit(2, entry.warehouse, "qty", entry.stock.quantity,
                "value", money(entry.stock.quantity * entry.stock.cost))
        end

    elseif cmd == "EXPIRE" then
        local days = tonumber(a[1])
        self:emit(0, "EXPIRE", days)
        local total_q, total_value = 0, 0
        for _, code in ipairs(sorted_keys(self.items)) do
            for _, warehouse in ipairs(sorted_keys(self.stock)) do
                local expired = {}
                for _, stock in pairs(self:holdings(warehouse, code)) do
                    if self.day - stock.lot.day > days then
                        expired[#expired + 1] = stock
                    end
                end
                if #expired > 0 then
                    local q, value = sum_quantity(expired), sum_value(expired)
                    for _, stock in ipairs(expired) do
                        stock.lot.removed = stock.lot.removed + stock.quantity
                        self.stock[warehouse][code][stock.lot.number] = nil
                    end
                    self:accumulate("expired", q, value)
                    self:card_entry(code, "expire", warehouse, -q, -value)
                    total_q, total_value = total_q + q, total_value + value
                    self:emit(2, code, warehouse, "lots", #expired, "qty", q, "value", money(value))
                end
            end
        end
        self:emit(2, "total", "qty", total_q, "value", money(total_value))

    elseif cmd == "VALUE" or cmd == "AGING" then
        local warehouses = #a > 0 and {self:warehouse(a[1])} or sorted_keys(self.stock)
        if cmd == "VALUE" then
            self:emit(0, "VALUE", table.unpack(a))
        else
            self:emit(0, "AGING", table.unpack(a))
            -- The report header includes the reference day.
            self.output[#self.output] = self.output[#self.output] .. " day " .. self.day
        end
        local total_q, total_value = 0, 0
        local bucket_q, bucket_v = {0, 0, 0, 0}, {0, 0, 0, 0}
        for _, code in ipairs(sorted_keys(self.items)) do
            local stocks, rows = {}, {}
            for _, warehouse in ipairs(warehouses) do
                local current = self:stocks(warehouse, code)
                rows[#rows + 1] = {warehouse = warehouse, stocks = current}
                for _, stock in ipairs(current) do stocks[#stocks + 1] = stock end
            end
            local q = sum_quantity(stocks)
            if q > 0 then
                local value = sum_value(stocks)
                if cmd == "VALUE" then
                    self:emit(2, code, "qty", q, "value", money(value), "avg", money(value // q))
                    if #a == 0 then
                        for _, entry in ipairs(rows) do
                            local warehouse_q = sum_quantity(entry.stocks)
                            if warehouse_q > 0 then
                                self:emit(4, entry.warehouse, "qty", warehouse_q,
                                    "value", money(sum_value(entry.stocks)))
                            end
                        end
                    end
                else
                    local item_buckets = {0, 0, 0, 0}
                    for _, stock in ipairs(stocks) do
                        local age = self.day - stock.lot.day
                        local bucket = age <= 30 and 1 or (age <= 60 and 2 or (age <= 90 and 3 or 4))
                        item_buckets[bucket] = item_buckets[bucket] + stock.quantity
                        bucket_q[bucket] = bucket_q[bucket] + stock.quantity
                        bucket_v[bucket] = bucket_v[bucket] + stock.quantity * stock.cost
                    end
                    self:aging_line(code, item_buckets, false)
                end
                total_q, total_value = total_q + q, total_value + value
            end
        end
        if cmd == "VALUE" then
            self:emit(2, "total", "qty", total_q, "value", money(total_value))
        else
            self:aging_line("total", bucket_q, false)
            self:aging_line("value", bucket_v, true)
        end

    elseif cmd == "LOTS" then
        local warehouse, code = a[1], a[2]
        self:pair(warehouse, code)
        self:emit(0, "LOTS", warehouse, code)
        local stocks, orders = self:fifo(warehouse, code), {}
        for _, order in ipairs(self.orders) do
            if order.warehouse == warehouse and order.item == code and order.backorder > 0 then
                orders[#orders + 1] = order
            end
        end
        for _, stock in ipairs(stocks) do
            self:emit(2, "lot", stock.lot.number, "day", stock.lot.day,
                "qty", stock.quantity, "cost", money(stock.cost),
                "value", money(stock.quantity * stock.cost), "age", self.day - stock.lot.day)
        end
        for _, order in ipairs(orders) do
            self:emit(2, "backorder", "order", order.number, "qty", order.backorder)
        end
        if #stocks == 0 and #orders == 0 then self:emit(2, "(none)") end

    elseif cmd == "REORDER" or cmd == "ITEMS" then
        self:emit(0, cmd)
        local found = false
        for _, code in ipairs(sorted_keys(self.items)) do
            local item = self.items[code]
            local q, backorder = self:total_quantity(code), self:backorder(code)
            if cmd == "ITEMS" then
                self:emit(2, code, item.name, "level", item.level, "onhand", q,
                    "backorder", backorder, "cost", item.last_cost and money(item.last_cost) or "none")
                found = true
            elseif q - backorder <= item.level then
                self:emit(2, code, item.name, "onhand", q,
                    "backorder", backorder, "level", item.level)
                found = true
            end
        end
        if not found then self:emit(2, "(none)") end

    elseif cmd == "MARGIN" or cmd == "TOP" then
        local rows = self:sales()
        if cmd == "MARGIN" then
            self:emit(0, "MARGIN")
            local total = {quantity = 0, revenue = 0, cogs = 0}
            for _, code in ipairs(sorted_keys(rows)) do
                local row = rows[code]
                self:margin_line(code, row)
                total.quantity = total.quantity + row.quantity
                total.revenue = total.revenue + row.revenue
                total.cogs = total.cogs + row.cogs
            end
            self:margin_line("total", total)
        else
            local k = tonumber(a[1])
            self:emit(0, "TOP", k)
            local codes = sorted_keys(rows)
            table.sort(codes, function(a, b)
                local x, y = rows[a], rows[b]
                local px, py = x.revenue - x.cogs, y.revenue - y.cogs
                if px ~= py then return px > py end
                if x.revenue ~= y.revenue then return x.revenue > y.revenue end
                return a < b
            end)
            for i = 1, math.min(k, #codes) do
                local row = rows[codes[i]]
                local profit = row.revenue - row.cogs
                self:emit(2, i, codes[i], "profit", money(profit),
                    "revenue", money(row.revenue), "margin", margin(profit, row.revenue))
            end
            if #codes == 0 then self:emit(2, "(none)") end
        end

    elseif cmd == "BACKORDERS" then
        self:emit(0, "BACKORDERS")
        local found = false
        for _, order in ipairs(self.orders) do
            if order.backorder > 0 then
                self:emit(2, "order", order.number, order.warehouse, order.item,
                    "qty", order.backorder, "day", order.day, "price", money(order.price))
                found = true
            end
        end
        if not found then self:emit(2, "(none)") end

    elseif cmd == "ORDER" then
        local order = self:order(a[1])
        self:emit(0, "ORDER", order.number, order.warehouse, order.item,
            "day", order.day, "price", money(order.price))
        self:emit(2, "ordered", order.ordered, "shipped", order.shipped,
            "backorder", order.backorder, "cancelled", order.cancelled, "returned", order.returned)
        for _, part in ipairs(order.issues) do
            self:emit(2, "lot", part.lot.number, "qty", part.quantity, "cost", money(part.cost))
        end
        self:emit(2, "revenue", money(order.revenue), "cogs", money(order.cogs),
            "profit", money(order.revenue - order.cogs))

    elseif cmd == "TRACE" then
        local lot = self:lot(a[1])
        self:emit(0, "TRACE", "lot", lot.number, lot.item, lot.kind, lot.warehouse,
            "day", lot.day, "qty", lot.initial_quantity, "cost", money(lot.initial_cost))
        for _, warehouse in ipairs(sorted_keys(self.stock)) do
            local stock = self:holdings(warehouse, lot.item)[lot.number]
            if stock then
                self:emit(2, "held", warehouse, "qty", stock.quantity, "cost", money(stock.cost))
            end
        end
        for _, order in ipairs(self.orders) do
            local q = 0
            for _, part in ipairs(order.issues) do
                if part.lot.number == lot.number then q = q + part.quantity end
            end
            if q > 0 then self:emit(2, "order", order.number, "qty", q) end
        end
        if lot.removed > 0 then self:emit(2, "removed", "qty", lot.removed) end

    elseif cmd == "CARD" then
        local item = self:item(a[1])
        self:emit(0, "CARD", item.code, item.name)
        local q, value = 0, 0
        for _, entry in ipairs(item.card) do
            q, value = q + entry.quantity, value + entry.value
            self:emit(2, "day", entry.day, entry.kind, entry.warehouse,
                signed_quantity(entry.quantity), signed_money(entry.value),
                "balance", q, money(value))
        end
        if #item.card == 0 then self:emit(2, "(none)") end

    elseif cmd == "STATUS" then
        self:emit(0, "STATUS")
        for _, warehouse in ipairs(sorted_keys(self.stock)) do
            local stocks, skus, backorder = {}, 0, 0
            for _, item_stocks in pairs(self.stock[warehouse]) do
                if next(item_stocks) then skus = skus + 1 end
                for _, stock in pairs(item_stocks) do stocks[#stocks + 1] = stock end
            end
            for _, order in ipairs(self.orders) do
                if order.warehouse == warehouse then
                    backorder = backorder + order.backorder
                end
            end
            self:emit(2, warehouse, "skus", skus, "qty", sum_quantity(stocks),
                "value", money(sum_value(stocks)), "backorder", backorder)
        end
        if not next(self.stock) then self:emit(2, "(none)") end

    elseif cmd == "SUMMARY" then
        self:emit(0, "SUMMARY")
        for _, category in ipairs(categories) do
            local total = self.totals[category]
            self:emit(2, category, "qty", total.quantity, "value", money(total.value))
        end
        local stocks = self:all_stocks()
        self:emit(2, "on-hand", "qty", sum_quantity(stocks), "value", money(sum_value(stocks)))
        local open, backorder = 0, 0
        for _, order in ipairs(self.orders) do
            if order.backorder > 0 then open = open + 1 end
            backorder = backorder + order.backorder
        end
        self:emit(2, "orders", #self.orders, "open", open, "backorder", backorder)
    end
end

function Inventory:execute(line)
    local tokens = {}
    for token in line:gmatch("%S+") do tokens[#tokens + 1] = token end
    local cmd = table.remove(tokens, 1)
    local ok, err = pcall(self.command, self, cmd, tokens)
    if not ok then
        if type(err) == "table" and err.reason then
            self:emit(0, "ERROR", err.reason)
        else
            error(err, 0)
        end
    end
end

local n = tonumber(io.read("*l"))
local inventory = Inventory.new()
for _ = 1, n do inventory:execute(io.read("*l")) end
io.write(table.concat(inventory.output, "\n"), "\n")
