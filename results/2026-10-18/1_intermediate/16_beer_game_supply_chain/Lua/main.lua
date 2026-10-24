local stage_names = {"RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"}
local policy_parameters = {
    FIXED = 1, PASS = 0, BASESTOCK = 1, MINMAX = 2,
    MOVAVG = 2, SMOOTH = 2, STERMAN = 4
}

local function fail(message)
    error({game_error = message}, 0)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, element in pairs(value) do result[key] = copy(element) end
    return result
end

local function list_copy(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end

local function sum(values)
    local result = 0
    for _, value in ipairs(values) do result = result + value end
    return result
end

local function money(value)
    return string.format("%d.%02d", value // 100, value % 100)
end

local function decimal(numerator, denominator, places)
    local whole = numerator // denominator
    local remainder = numerator % denominator
    local digits = {}
    for _ = 1, places do
        remainder = remainder * 10
        local digit = remainder // denominator
        digits[#digits + 1] = tostring(digit)
        remainder = remainder % denominator
    end
    return tostring(whole) .. "." .. table.concat(digits)
end

local function variation(values)
    local squares = 0
    for _, value in ipairs(values) do squares = squares + value * value end
    local total = sum(values)
    return #values * squares - total * total
end

local function tokens(line)
    local result = {}
    for word in line:gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function slice(values, first, last)
    local result = {}
    for i = first, last or #values do result[#result + 1] = values[i] end
    return result
end

local function stage_index(name)
    for i, stage in ipairs(stage_names) do
        if stage == name then return i end
    end
    fail("unknown stage " .. name)
end

local function target(name)
    if name == "ALL" then return {1, 2, 3, 4} end
    return {stage_index(name)}
end

local function parse_policy(words)
    local name = words[1]
    local count = policy_parameters[name]
    if count == nil then fail("unknown policy " .. name) end
    if #words - 1 ~= count then
        fail(name .. " needs " .. count .. " parameters")
    end
    local args = {}
    for i = 1, count do
        local token = words[i + 1]
        if name == "STERMAN" and i <= 3 then token = token:gsub("%.", "") end
        args[i] = tonumber(token)
    end
    local valid
    if name == "FIXED" then
        valid = 0 <= args[1] and args[1] <= 1000
    elseif name == "PASS" then
        valid = true
    elseif name == "BASESTOCK" then
        valid = 0 <= args[1] and args[1] <= 10000
    elseif name == "MINMAX" then
        valid = 0 <= args[1] and args[1] < args[2] and args[2] <= 10000
    elseif name == "MOVAVG" then
        valid = 1 <= args[1] and args[1] <= 52 and
                0 <= args[2] and args[2] <= 10000
    elseif name == "SMOOTH" then
        valid = 1 <= args[1] and args[1] <= 10 and
                0 <= args[2] and args[2] <= 10000
    else
        valid = 0 <= args[1] and args[1] <= 100 and
                0 <= args[2] and args[2] <= 100 and
                0 <= args[3] and args[3] <= 100 and
                0 <= args[4] and args[4] <= 10000
    end
    if not valid then fail("invalid parameter for " .. name) end
    return {name = name, args = args, text = table.concat(words, " ")}
end

local function new_stage(initial)
    local shipping, orders = {}, {}
    for i = 1, initial.shipping do shipping[i] = initial.quantity end
    for i = 1, initial.orders do orders[i] = initial.quantity end
    return {
        inventory = initial.inventory, backlog = 0,
        shipping = shipping, orders = orders,
        policy = copy(initial.policy), expected = 100 * initial.quantity,
        holding = initial.holding, backlog_rate = initial.backlog,
        lot = 1, capacity = nil, records = {}
    }
end

local function new_simulation(initials, demands)
    local stages = {}
    for i = 1, 4 do stages[i] = new_stage(initials[i]) end
    return {
        initials = initials, week = 0, demands = list_copy(demands),
        stages = stages, plant_backlog = 0, plant_capacity = nil,
        plant_records = {}, visibility = "OFF"
    }
end

local function signal(sim, index, week, current)
    if sim.visibility == "ON" then return sim.demands[week] end
    if current and week == sim.week + 1 then return current[index] end
    return sim.stages[index].records[week].incoming
end

local function set_policy(sim, index, policy)
    local stage = sim.stages[index]
    stage.policy = copy(policy)
    if policy.name == "STERMAN" then
        local previous = sim.week > 0 and
                         signal(sim, index, sim.week) or sim.initials[index].quantity
        stage.expected = 100 * previous
    end
end

local function positions(sim)
    local supply, position = {}, {}
    for index, stage in ipairs(sim.stages) do
        local upstream = index < 4 and sim.stages[index + 1].backlog or sim.plant_backlog
        local line = sum(stage.orders) + upstream + sum(stage.shipping)
        supply[index] = line
        position[index] = stage.inventory + line - stage.backlog
    end
    return supply, position
end

local function policy_order(sim, index, incoming, line, position)
    local stage = sim.stages[index]
    local name, args = stage.policy.name, stage.policy.args
    local week = sim.week + 1
    local demand = signal(sim, index, week, incoming)
    if name == "FIXED" then
        return args[1]
    elseif name == "PASS" then
        return incoming[index]
    elseif name == "BASESTOCK" then
        return math.max(0, args[1] - position)
    elseif name == "MINMAX" then
        return position <= args[1] and args[2] - position or 0
    elseif name == "MOVAVG" then
        local count = math.min(args[1], week)
        local demand_sum = 0
        for u = week - count + 1, week do
            demand_sum = demand_sum + signal(sim, index, u, incoming)
        end
        local forecast = demand_sum // count
        local initial = sim.initials[index]
        local delay = initial.shipping + initial.orders
        return math.max(0, args[2] + forecast * delay - position)
    elseif name == "SMOOTH" then
        return math.max(0, demand + (args[2] - position) // args[1])
    end
    local theta, alpha, beta, target = table.unpack(args)
    stage.expected = (100 * theta * demand +
                      (100 - theta) * stage.expected) // 100
    local net = stage.inventory - stage.backlog
    return math.max(0,
        (100 * stage.expected + alpha * (100 * (target - net) - beta * line)) // 10000)
end

local function step(sim)
    local received = {}
    for index, stage in ipairs(sim.stages) do
        local quantity = table.remove(stage.shipping, 1)
        stage.inventory = stage.inventory + quantity
        received[index] = quantity
    end
    local incoming = {
        sim.demands[sim.week + 1],
        sim.stages[1].orders[1], sim.stages[2].orders[1],
        sim.stages[3].orders[1]
    }
    local plant_incoming = sim.stages[4].orders[1]
    for _, stage in ipairs(sim.stages) do table.remove(stage.orders, 1) end

    local records = {}
    for index, stage in ipairs(sim.stages) do
        local before = stage.backlog
        local requested = before + incoming[index]
        local shipped = math.min(stage.inventory, requested)
        if stage.capacity ~= nil then shipped = math.min(shipped, stage.capacity) end
        stage.inventory = stage.inventory - shipped
        stage.backlog = requested - shipped
        if index > 1 then
            local shipping = sim.stages[index - 1].shipping
            shipping[#shipping + 1] = shipped
        end
        records[index] = {
            received = received[index], incoming = incoming[index],
            shipped = shipped, before = before,
            ontime = math.min(math.max(0, shipped - before), incoming[index]),
            inventory = stage.inventory, backlog = stage.backlog
        }
    end

    local requested = sim.plant_backlog + plant_incoming
    local produced = sim.plant_capacity == nil and requested or
                     math.min(requested, sim.plant_capacity)
    sim.plant_backlog = requested - produced
    sim.stages[4].shipping[#sim.stages[4].shipping + 1] = produced

    local supply, position = positions(sim)
    local ordered = {}
    for index = 1, 4 do
        ordered[index] = policy_order(sim, index, incoming, supply[index], position[index])
    end
    for index, stage in ipairs(sim.stages) do
        local quantity = (ordered[index] + stage.lot - 1) // stage.lot * stage.lot
        stage.orders[#stage.orders + 1] = quantity
        local record = records[index]
        record.order = quantity
        record.holding = stage.holding * stage.inventory
        record.backlog_cost = stage.backlog_rate * stage.backlog
        record.cost = record.holding + record.backlog_cost
        stage.records[#stage.records + 1] = record
    end
    sim.plant_records[#sim.plant_records + 1] = {
        incoming = plant_incoming, produced = produced, backlog = sim.plant_backlog
    }
    sim.week = sim.week + 1
    return records
end

local function records_sum(records, field)
    local result = 0
    for _, record in ipairs(records) do result = result + record[field] end
    return result
end

local function records_values(records, field)
    local values = {}
    for _, record in ipairs(records) do values[#values + 1] = record[field] end
    return values
end

local function costs(sim)
    local result = {}
    for i, stage in ipairs(sim.stages) do
        result[i] = records_sum(stage.records, "cost")
    end
    return result
end

local initials = {}
for index = 1, 4 do
    local words = tokens(io.read("*l"))
    initials[index] = {
        inventory = tonumber(words[2]), quantity = tonumber(words[3]),
        shipping = tonumber(words[4]), orders = tonumber(words[5]),
        holding = tonumber(words[6]), backlog = tonumber(words[7]),
        policy = parse_policy(slice(words, 8))
    }
end

local base, sim, snapshots, output = {}, nil, {}, {}

local function initialize(demands)
    if demands ~= nil then base = list_copy(demands) end
    sim = new_simulation(initials, base)
end
initialize()

local function emit(...)
    local values = {...}
    for i, value in ipairs(values) do values[i] = tostring(value) end
    output[#output + 1] = table.concat(values, " ")
end

local function require_weeks()
    if sim.week == 0 then fail("no weeks simulated") end
end

local function range_check(arguments, limit)
    if #arguments == 0 then return 1, limit end
    local first, last = tonumber(arguments[1]), tonumber(arguments[2])
    if first < 1 or first > last or last > limit then
        fail("bad range " .. arguments[1] .. " " .. arguments[2])
    end
    return first, last
end

local function mode_check(mode)
    if mode ~= "ORDERS" and mode ~= "INV" and mode ~= "BACK" and mode ~= "NET" then
        fail("unknown mode " .. mode)
    end
end

local function values_for(index, mode)
    local result = {}
    for _, record in ipairs(sim.stages[index].records) do
        if mode == "ORDERS" then
            result[#result + 1] = record.order
        elseif mode == "INV" then
            result[#result + 1] = record.inventory
        elseif mode == "BACK" then
            result[#result + 1] = record.backlog
        else
            result[#result + 1] = record.inventory - record.backlog
        end
    end
    return result
end

local function trial(policies)
    local result = new_simulation(initials, sim.demands)
    result.visibility = sim.visibility
    result.plant_capacity = sim.plant_capacity
    for index, stage in ipairs(result.stages) do
        local previous = sim.stages[index]
        stage.lot = previous.lot
        stage.capacity = previous.capacity
        stage.holding = previous.holding
        stage.backlog_rate = previous.backlog_rate
        set_policy(result, index, policies[index])
    end
    while result.week < #result.demands do step(result) end
    return result
end

local function demand(values)
    initialize(values)
    local smallest, largest = values[1], values[1]
    for _, value in ipairs(values) do
        smallest = math.min(smallest, value)
        largest = math.max(largest, value)
    end
    emit("DEMAND", "weeks", #values, "total", sum(values),
         "min", smallest, "max", largest)
end

local function generate(args)
    local weeks, baseline, spread, seed =
        tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local changes = {}
    for i = 5, #args, 3 do
        local change = {
            kind = args[i], week = tonumber(args[i + 1]), amount = tonumber(args[i + 2])
        }
        if change.week < 1 or change.week > weeks then
            fail("week " .. change.week .. " outside horizon")
        end
        changes[#changes + 1] = change
    end
    local levels = {}
    for t = 1, weeks do
        local level = baseline
        for _, change in ipairs(changes) do
            if change.kind == "STEP" and t >= change.week then
                level = level + change.amount
            elseif change.kind == "PULSE" and t == change.week then
                level = level + change.amount
            elseif change.kind == "RAMP" and t >= change.week then
                level = level + change.amount * (t - change.week + 1)
            end
        end
        if level < 0 then fail("negative level at week " .. t) end
        levels[t] = level
    end
    local values = {}
    for _, level in ipairs(levels) do
        seed = 48271 * seed % 2147483647
        values[#values + 1] = level + seed % spread
    end
    demand(values)
end

local function show_status()
    emit("STATUS", "week", sim.week, "of", #sim.demands)
    local supply, position = positions(sim)
    for index, stage in ipairs(sim.stages) do
        local text = stage_names[index] .. " inv " .. stage.inventory ..
            " back " .. stage.backlog ..
            " transit " .. table.concat(stage.shipping, ",") ..
            " pending " .. table.concat(stage.orders, ",") ..
            " supply " .. supply[index] ..
            " position " .. position[index] .. " policy " .. stage.policy.text
        if stage.policy.name == "STERMAN" then
            text = text .. " expect " .. money(stage.expected)
        end
        emit(text)
    end
    emit("PLANT", "back", sim.plant_backlog)
end

local function show_week(week)
    emit("WEEK", week, "demand", sim.demands[week])
    for index, stage in ipairs(sim.stages) do
        local record = stage.records[week]
        emit(stage_names[index], "recv", record.received, "in", record.incoming,
             "ship", record.shipped, "inv", record.inventory,
             "back", record.backlog, "order", record.order, "cost", money(record.cost))
    end
    local plant = sim.plant_records[week]
    emit("PLANT", "in", plant.incoming, "made", plant.produced, "back", plant.backlog)
end

local function right(value, width)
    return string.format("%" .. width .. "s", tostring(value))
end

local function show_table(index, first, last)
    emit("TABLE", stage_names[index], first .. "-" .. last)
    local labels = {"week", "in", "ship", "recv", "inv", "back", "order", "cost"}
    local widths = {4, 6, 6, 6, 6, 6, 6, 9}
    local fields = {}
    for i, label in ipairs(labels) do fields[i] = right(label, widths[i]) end
    emit(table.concat(fields, " "))
    for week = first, last do
        local record = sim.stages[index].records[week]
        local values = {
            week, record.incoming, record.shipped, record.received,
            record.inventory, record.backlog, record.order, money(record.cost)
        }
        for i, value in ipairs(values) do fields[i] = right(value, widths[i]) end
        emit(table.concat(fields, " "))
    end
end

local function show_costs()
    emit("COSTS", "week", sim.week)
    local total_holding, total_backlog = 0, 0
    for index, stage in ipairs(sim.stages) do
        local holding = records_sum(stage.records, "holding")
        local backlog = records_sum(stage.records, "backlog_cost")
        total_holding = total_holding + holding
        total_backlog = total_backlog + backlog
        emit(stage_names[index], "holding", money(holding),
             "backlog", money(backlog), "total", money(holding + backlog))
    end
    emit("TOTAL", "holding", money(total_holding),
         "backlog", money(total_backlog), "total", money(total_holding + total_backlog))
end

local function fill_text(records)
    local ordered = records_sum(records, "incoming")
    local ontime = records_sum(records, "ontime")
    local fill = ordered == 0 and "n/a" or decimal(ontime * 100, ordered, 2) .. "%"
    return ordered, ontime, fill
end

local function bullwhip()
    local n = sim.week
    local demands = slice(sim.demands, 1, n)
    local demand_var = variation(demands)
    emit("BULLWHIP", "weeks", "1-" .. n, "demand",
         "mean", decimal(sum(demands), n, 4),
         "var", decimal(demand_var, n * n, 4))
    local previous = demand_var
    for index, stage in ipairs(sim.stages) do
        local orders = records_values(stage.records, "order")
        local current = variation(orders)
        emit(stage_names[index], "mean", decimal(sum(orders), n, 4),
             "var", decimal(current, n * n, 4),
             "ratio", demand_var == 0 and "n/a" or decimal(current, demand_var, 4),
             "step", previous == 0 and "n/a" or decimal(current, previous, 4))
        previous = current
    end
end

local function peaks()
    emit("PEAKS", "weeks", "1-" .. sim.week)
    for index, stage in ipairs(sim.stages) do
        local max_inventory, max_backlog = 0, 0
        local inventory_week, backlog_week = 0, 0
        local longest, run, start, best_start, best_last = 0, 0, 0, 0, 0
        for week, record in ipairs(stage.records) do
            if record.inventory > max_inventory then
                max_inventory, inventory_week = record.inventory, week
            end
            if record.backlog > max_backlog then
                max_backlog, backlog_week = record.backlog, week
            end
            if record.backlog > 0 then
                if run == 0 then start = week end
                run = run + 1
                if run > longest then
                    longest, best_start, best_last = run, start, week
                end
            else
                run = 0
            end
        end
        local stockout = longest == 0 and "0" or
            (longest .. " weeks " .. best_start .. "-" .. best_last)
        emit(stage_names[index], "max_inv", max_inventory,
             "week", inventory_week == 0 and "-" or inventory_week,
             "max_back", max_backlog,
             "week", backlog_week == 0 and "-" or backlog_week,
             "longest_stockout", stockout)
    end
end

local function leadtime(index)
    local stage = sim.stages[index]
    local initial = initials[index]
    local nominal = initial.shipping + initial.orders
    local cumulative, received = {}, 0
    for i, record in ipairs(stage.records) do
        received = received + record.received
        cumulative[i] = received - nominal * initial.quantity
    end
    local ordered, count, leads = 0, 0, {}
    for t, record in ipairs(stage.records) do
        ordered = ordered + record.order
        if record.order > 0 then
            count = count + 1
            for u = t + 1, #stage.records do
                if cumulative[u] >= ordered then
                    leads[#leads + 1] = u - t
                    break
                end
            end
        end
    end
    local smallest, average, largest = "-", "-", "-"
    if #leads > 0 then
        smallest, largest = math.min(table.unpack(leads)), math.max(table.unpack(leads))
        average = decimal(sum(leads), #leads, 2)
    end
    emit("LEADTIME", stage_names[index], "nominal", nominal,
         "orders", count, "completed", #leads, "open", count - #leads,
         "min", smallest, "avg", average, "max", largest)
end

local function values_for(index, mode)
    local result = {}
    for _, record in ipairs(sim.stages[index].records) do
        if mode == "ORDERS" then
            result[#result + 1] = record.order
        elseif mode == "INV" then
            result[#result + 1] = record.inventory
        elseif mode == "BACK" then
            result[#result + 1] = record.backlog
        else
            result[#result + 1] = record.inventory - record.backlog
        end
    end
    return result
end

local function mode_check(mode)
    if mode ~= "ORDERS" and mode ~= "INV" and mode ~= "BACK" and mode ~= "NET" then
        fail("unknown mode " .. mode)
    end
end

local function plot(index, mode, first, last)
    local values = slice(values_for(index, mode), first, last)
    local smallest, largest = math.min(table.unpack(values)), math.max(table.unpack(values))
    if mode == "NET" then
        emit("PLOT", stage_names[index], mode, first .. "-" .. last,
             "min", smallest, "max", largest)
        local scale = 0
        for _, value in ipairs(values) do scale = math.max(scale, math.abs(value)) end
        for i, value in ipairs(values) do
            local length = scale > 0 and math.floor(math.abs(value) * 25 / scale) or 0
            local left = value < 0 and
                string.rep(" ", 25 - length) .. string.rep("-", length) or
                string.rep(" ", 25)
            local right_bar = value > 0 and string.rep("+", length) or ""
            emit(string.format("%3d %s|%s %d", first + i - 1, left, right_bar, value))
        end
    else
        emit("PLOT", stage_names[index], mode, first .. "-" .. last, "max", largest)
        for i, value in ipairs(values) do
            local length = largest > 0 and math.floor(value * 50 / largest) or 0
            emit(string.format("%3d |%s %d",
                 first + i - 1, string.rep("#", length), value))
        end
    end
end

local function histogram(index, mode, width)
    local bins = {}
    local smallest, largest
    for _, value in ipairs(values_for(index, mode)) do
        local bucket = value // width
        bins[bucket] = (bins[bucket] or 0) + 1
        smallest = smallest and math.min(smallest, bucket) or bucket
        largest = largest and math.max(largest, bucket) or bucket
    end
    emit("HISTOGRAM", stage_names[index], mode, "width", width,
         "weeks", "1-" .. sim.week)
    for bucket = smallest, largest do
        local count = bins[bucket] or 0
        local text = (bucket * width) .. ".." .. (bucket * width + width - 1) ..
                     " " .. count
        if count > 0 then text = text .. " " .. string.rep("*", count) end
        emit(text)
    end
end

local function command(name, args)
    if name == "DEMAND" then
        local values = {}
        for i, word in ipairs(args) do values[i] = tonumber(word) end
        demand(values)
    elseif name == "GENERATE" then
        generate(args)
    elseif name == "RUN" then
        if sim.week == #sim.demands then
            fail("horizon reached at week " .. #sim.demands)
        end
        local first = sim.week + 1
        local count = math.min(tonumber(args[1]), #sim.demands - sim.week)
        local cost = 0
        for _ = 1, count do
            local records = step(sim)
            for index, record in ipairs(records) do
                cost = cost + record.cost
                if record.before == 0 and record.backlog > 0 then
                    emit("STOCKOUT", stage_names[index], "week", sim.week,
                         "backlog", record.backlog)
                elseif record.before > 0 and record.backlog == 0 then
                    emit("RECOVER", stage_names[index], "week", sim.week)
                end
            end
        end
        emit("RUN", first .. "-" .. sim.week, "demand",
             sum(slice(sim.demands, first, sim.week)), "cost", money(cost))
        if sim.week == #sim.demands then emit("HORIZON", sim.week) end
    elseif name == "RESET" then
        initialize()
        emit("RESET", "week", 0)
    elseif name == "SAVE" then
        snapshots[args[1]] = copy(sim)
        emit("SAVE", args[1], "week", sim.week)
    elseif name == "LOAD" then
        if not snapshots[args[1]] then fail("no snapshot " .. args[1]) end
        sim = copy(snapshots[args[1]])
        emit("LOAD", args[1], "week", sim.week)
    elseif name == "SET" then
        local indices = target(args[1])
        local policy = parse_policy(slice(args, 2))
        for _, index in ipairs(indices) do set_policy(sim, index, policy) end
        emit("SET", args[1], policy.text)
    elseif name == "BATCH" then
        local index = stage_index(args[1])
        local lot = tonumber(args[2])
        if lot < 1 or lot > 100 then fail("invalid batch size " .. args[2]) end
        sim.stages[index].lot = lot
        emit("BATCH", args[1], lot)
    elseif name == "CAPACITY" then
        local index
        if args[1] ~= "PLANT" then index = stage_index(args[1]) end
        local capacity = args[2] == "OFF" and nil or tonumber(args[2])
        if capacity and capacity > 10000 then fail("invalid capacity " .. args[2]) end
        if index == nil then sim.plant_capacity = capacity
        else sim.stages[index].capacity = capacity end
        emit("CAPACITY", args[1], args[2])
    elseif name == "COST" then
        local index = stage_index(args[1])
        local holding, backlog = tonumber(args[2]), tonumber(args[3])
        if holding > 1000 or backlog > 1000 then fail("invalid cost") end
        sim.stages[index].holding = holding
        sim.stages[index].backlog_rate = backlog
        emit("COST", args[1], "holding", holding, "backlog", backlog)
    elseif name == "VISIBILITY" then
        if args[1] ~= "ON" and args[1] ~= "OFF" then
            fail("unknown visibility " .. args[1])
        end
        sim.visibility = args[1]
        emit("VISIBILITY", args[1])
    elseif name == "SHOCK" then
        local week, value = tonumber(args[1]), tonumber(args[2])
        if week < 1 or week > #sim.demands then
            fail("week " .. args[1] .. " outside horizon")
        end
        if week <= sim.week then fail("week " .. args[1] .. " already simulated") end
        local old = sim.demands[week]
        sim.demands[week] = value
        emit("SHOCK", "week", week, old, "->", value)
    elseif name == "STATUS" then
        show_status()
    elseif name == "SETTINGS" then
        emit("SETTINGS")
        for index, stage in ipairs(sim.stages) do
            local initial = initials[index]
            emit(stage_names[index], "holding", stage.holding,
                 "backlog", stage.backlog_rate, "batch", stage.lot,
                 "capacity", stage.capacity == nil and "OFF" or stage.capacity,
                 "delays", initial.shipping, initial.orders)
        end
        emit("PLANT", "capacity", sim.plant_capacity == nil and "OFF" or sim.plant_capacity)
        emit("VISIBILITY", sim.visibility)
    elseif name == "WEEK" then
        require_weeks()
        local week = tonumber(args[1])
        if week < 1 or week > sim.week then fail("bad week " .. args[1]) end
        show_week(week)
    elseif name == "TABLE" then
        local index = stage_index(args[1])
        require_weeks()
        local first, last = range_check(slice(args, 2), sim.week)
        show_table(index, first, last)
    elseif name == "CHAIN" then
        require_weeks()
        local first, last = range_check(args, sim.week)
        emit("CHAIN", first .. "-" .. last)
        local header = {right("week", 4), right("demand", 6)}
        for _, stage in ipairs(stage_names) do header[#header + 1] = right(stage, 11) end
        emit(table.concat(header, " "))
        for week = first, last do
            local line = {right(week, 4), right(sim.demands[week], 6)}
            for _, stage in ipairs(sim.stages) do
                line[#line + 1] = right(stage.records[week].order, 11)
            end
            emit(table.concat(line, " "))
        end
    elseif name == "DEMANDS" then
        local first, last = range_check(args, #sim.demands)
        local values = slice(sim.demands, first, last)
        emit("DEMANDS", first .. "-" .. last, "total", sum(values),
             "min", math.min(table.unpack(values)),
             "max", math.max(table.unpack(values)))
        emit(table.concat(values, " "))
    elseif name == "COSTS" then
        show_costs()
    elseif name == "SUMMARY" then
        require_weeks()
        emit("SUMMARY", "weeks", "1-" .. sim.week)
        for index, stage in ipairs(sim.stages) do
            local inventories = records_values(stage.records, "inventory")
            local backlogs = records_values(stage.records, "backlog")
            local orders = records_values(stage.records, "order")
            local zero_weeks = 0
            for _, quantity in ipairs(orders) do
                if quantity == 0 then zero_weeks = zero_weeks + 1 end
            end
            emit(stage_names[index],
                 "avg_inv", decimal(sum(inventories), sim.week, 2),
                 "avg_back", decimal(sum(backlogs), sim.week, 2),
                 "orders", sum(orders),
                 "min", math.min(table.unpack(orders)),
                 "max", math.max(table.unpack(orders)),
                 "zero_weeks", zero_weeks)
        end
    elseif name == "BALANCE" then
        emit("BALANCE", "week", sim.week)
        local initial_goods, produced, delivered, stock, transit = 0, 0, 0, 0, 0
        for index, stage in ipairs(sim.stages) do
            local initial = initials[index]
            local received = records_sum(stage.records, "received")
            local shipped = records_sum(stage.records, "shipped")
            emit(stage_names[index], "start", initial.inventory,
                 "received", received, "shipped", shipped,
                 "end", stage.inventory, "owed", stage.backlog)
            initial_goods = initial_goods + initial.inventory +
                            initial.quantity * initial.shipping
            if index == 1 then delivered = shipped end
            stock = stock + stage.inventory
            transit = transit + sum(stage.shipping)
        end
        produced = records_sum(sim.plant_records, "produced")
        emit("SYSTEM", "initial", initial_goods,
             "produced", produced, "delivered", delivered,
             "stock", stock, "transit", transit)
    elseif name == "FILLRATE" then
        require_weeks()
        emit("FILLRATE", "weeks", "1-" .. sim.week)
        for index, stage in ipairs(sim.stages) do
            local ordered, ontime, fill = fill_text(stage.records)
            local stockouts = 0
            for _, record in ipairs(stage.records) do
                if record.backlog > 0 then stockouts = stockouts + 1 end
            end
            emit(stage_names[index], "fill", fill, "ontime", ontime,
                 "ordered", ordered, "stockout_weeks", stockouts,
                 "service", decimal((sim.week - stockouts) * 100, sim.week, 2) .. "%")
        end
    elseif name == "BULLWHIP" then
        require_weeks()
        bullwhip()
    elseif name == "PEAKS" then
        require_weeks()
        peaks()
    elseif name == "LEADTIME" then
        local index = stage_index(args[1])
        require_weeks()
        leadtime(index)
    elseif name == "PLOT" or name == "HISTOGRAM" then
        local index = stage_index(args[1])
        mode_check(args[2])
        local width
        if name == "HISTOGRAM" then
            width = tonumber(args[3])
            if width < 1 or width > 100 then fail("invalid width " .. args[3]) end
        end
        require_weeks()
        if name == "PLOT" then
            local first, last = range_check(slice(args, 3), sim.week)
            plot(index, args[2], first, last)
        else
            histogram(index, args[2], width)
        end
    elseif name == "COMPARE" then
        local policies = {}
        local start = 1
        for endpoint = 1, #args + 1 do
            if endpoint > #args or args[endpoint] == "/" then
                policies[#policies + 1] = parse_policy(slice(args, start, endpoint - 1))
                start = endpoint + 1
            end
        end
        local rows = {}
        for i, policy in ipairs(policies) do
            local result = trial({policy, policy, policy, policy})
            local cost = sum(costs(result))
            local _, _, fill = fill_text(result.stages[1].records)
            local demand_var = variation(result.demands)
            local factory_var = variation(records_values(result.stages[4].records, "order"))
            local ratio = demand_var == 0 and "n/a" or
                          decimal(factory_var, demand_var, 4)
            rows[#rows + 1] = {
                cost = cost, index = i, policy = policy.text,
                fill = fill, ratio = ratio
            }
        end
        table.sort(rows, function(a, b)
            if a.cost ~= b.cost then return a.cost < b.cost end
            return a.index < b.index
        end)
        emit("COMPARE", #policies, "weeks", #sim.demands)
        for rank, row in ipairs(rows) do
            emit(rank, row.policy, "total", money(row.cost),
                 "fill", row.fill, "bullwhip", row.ratio)
        end
    elseif name == "OPTIMIZE" then
        local indices = target(args[1])
        local low, high = tonumber(args[2]), tonumber(args[3])
        if low > high then fail("bad range " .. args[2] .. " " .. args[3]) end
        if high - low > 200 then fail("range too large") end
        local best_cost, best_total, best_target
        for value = low, high do
            local policies = {}
            for i, stage in ipairs(sim.stages) do policies[i] = stage.policy end
            local replacement = {
                name = "BASESTOCK", args = {value},
                text = "BASESTOCK " .. value
            }
            for _, index in ipairs(indices) do policies[index] = replacement end
            local result = trial(policies)
            local stage_costs = costs(result)
            local objective = 0
            for _, index in ipairs(indices) do
                objective = objective + stage_costs[index]
            end
            if not best_cost or objective < best_cost then
                best_cost, best_target, best_total =
                    objective, value, sum(stage_costs)
            end
        end
        emit("OPTIMIZE", args[1], "BASESTOCK", best_target,
             "cost", money(best_cost), "total", money(best_total))
    else
        fail("unknown command " .. name)
    end
end

while true do
    local line = io.read("*l")
    if not line or line == "END" then break end
    local words = tokens(line)
    local cmd = words[1]
    local args = slice(words, 2)
    local ok, result = pcall(command, cmd, args)
    if not ok then
        if type(result) == "table" and result.game_error then
            emit("ERROR", result.game_error)
        else
            error(result)
        end
    end
end

if #output > 0 then io.write(table.concat(output, "\n"), "\n") end
