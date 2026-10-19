local SETTING_NAMES = {
    "CAPACITY", "INITIAL", "CHARGE", "DISCHARGE", "CEFF", "DEFF", "RESERVE", "COST",
    "EXPORT", "FEEDIN", "FIXED", "DEMAND", "PVSCALE"
}
local SETTING_RANGES = {
    CAPACITY = {1, 100000}, INITIAL = {0, 100}, CHARGE = {1, 20000},
    DISCHARGE = {1, 20000}, CEFF = {1, 100}, DEFF = {1, 100},
    RESERVE = {0, 100}, COST = {0, 100000}, EXPORT = {0, 100000},
    FEEDIN = {0, 10000}, FIXED = {0, 100000}, DEMAND = {0, 100000},
    PVSCALE = {0, 300}
}
local STRATEGY_RANGES = {TOU = {1, 100}, PEAKSHAVE = {0, 100000}, BACKUP = {0, 100}}
local FLOW_NAMES = {
    "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
    "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"
}
local TOTAL_FIELDS = {
    "load", "pv", "charge", "discharge", "imported", "exported",
    "curtailed", "drawn", "loss", "shortfall", "import_cost", "export_income"
}
local DAY_NAMES = {"MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"}

local function split(line)
    local values = {}
    for word in line:gmatch("%S+") do values[#values + 1] = word end
    return values
end

local function copy(values)
    local result = {}
    for name, value in pairs(values) do result[name] = value end
    return result
end

local function number(x) return tonumber(x) end
local function floor(x, y) return x // y end
local function ceiling(x, y) return (x + y - 1) // y end
local function min(...) return math.min(...) end
local function max(...) return math.max(...) end

local function money(amount)
    local absolute = math.abs(amount)
    return (amount < 0 and "-" or "") .. tostring(absolute // 100)
        .. "." .. string.format("%02d", absolute % 100)
end

local function percentage(numerator, denominator)
    local value = denominator ~= 0 and floor(10000 * numerator, denominator) or 0
    return tostring(value // 100) .. "." .. string.format("%02d", value % 100)
end

local function truncate_divide(value, divisor)
    if value < 0 then return -((-value) // divisor) end
    return value // divisor
end

local function row(values, widths)
    local pieces = {}
    for index, value in ipairs(values) do
        pieces[index] = string.format("%" .. widths[index] .. "s", tostring(value))
    end
    return table.concat(pieces)
end

local function bar(width)
    return "|" .. string.rep("#", width) .. string.rep(".", 20 - width) .. "|"
end

local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

local function fail(reason)
    error({reason = reason}, 0)
end

local function require_count(args, expected)
    if #args ~= expected then fail("wrong number of arguments") end
end

local function strategy_text(strategy)
    return strategy.parameter == nil and strategy.name
        or (strategy.name .. " " .. strategy.parameter)
end

local function tariff_extremes(prices, names)
    local cheapest, peak = names[1], names[1]
    for _, name in ipairs(names) do
        if prices[name] < prices[cheapest] then cheapest = name end
        if prices[name] > prices[peak] then peak = name end
    end
    return cheapest, peak
end

local function parse_strategies(args)
    local strategies = {}
    local index = 1
    while index <= #args do
        local name = args[index]
        index = index + 1
        if name == "SELF" or name == "EXPORTPEAK" then
            strategies[#strategies + 1] = {name = name}
        else
            local range = STRATEGY_RANGES[name]
            if not range then fail("unknown strategy " .. name) end
            if index > #args then fail("missing parameter for " .. name) end
            local parameter = number(args[index])
            index = index + 1
            if parameter < range[1] or parameter > range[2] then
                fail("invalid parameter for " .. name)
            end
            strategies[#strategies + 1] = {name = name, parameter = parameter}
        end
    end
    return strategies
end

local function one_strategy(args)
    local strategies = parse_strategies(args)
    require_count(strategies, 1)
    return strategies[1]
end

local function checked_range(low, high, step, bounds)
    if low < bounds[1] or high > bounds[2] or high < low or step < 1
            or floor(high - low, step) + 1 > 20 then
        fail("invalid range")
    end
    local values = {}
    for value = low, high, step do values[#values + 1] = value end
    return values
end

local function read_period_hours(args)
    local hours = {}
    for i = 1, #args, 2 do
        local start = number(args[i])
        local finish = i + 2 <= #args and number(args[i + 2]) or 24
        for hour = start, finish - 1 do hours[#hours + 1] = args[i + 1] end
    end
    return hours
end

local function read_input()
    local function line() return split(io.read("*l")) end
    local data = {}
    local battery = line()
    local grid = line()
    local settings = {}
    for i = 1, 8 do settings[SETTING_NAMES[i]] = number(battery[i + 1]) end
    for i = 9, 12 do settings[SETTING_NAMES[i]] = number(grid[i - 7]) end
    settings.PVSCALE = 100
    data.initial_settings = settings

    local period_count = number(line()[2])
    data.period_names = {}
    data.initial_prices = {}
    for _ = 1, period_count do
        local args = line()
        local name = args[1]
        data.period_names[#data.period_names + 1] = name
        data.initial_prices[name] = number(args[2])
    end
    local weekday = line()
    local weekend = line()
    table.remove(weekday, 1)
    table.remove(weekend, 1)
    weekday = read_period_hours(weekday)
    weekend = read_period_hours(weekend)

    local profile_count = number(line()[2])
    local profiles = {}
    for _ = 1, profile_count do
        local args = line()
        local values = {}
        for i = 3, #args do values[#values + 1] = number(args[i]) end
        profiles[args[1] .. "/" .. args[2]] = values
    end
    data.day_count = number(line()[2])
    data.loads = {}
    data.base_pv = {}
    for _ = 1, data.day_count do
        local args = line()
        local load_values = profiles["LOAD/" .. args[1]]
        local pv_values = profiles["PV/" .. args[3]]
        local load_percent, pv_percent = number(args[2]), number(args[4])
        for hour = 1, 24 do
            data.loads[#data.loads + 1] = floor(load_values[hour] * load_percent, 100)
            data.base_pv[#data.base_pv + 1] = floor(pv_values[hour] * pv_percent, 100)
        end
    end
    local holiday_tokens = line()
    local holidays = {}
    for i = 3, #holiday_tokens do holidays[number(holiday_tokens[i])] = true end
    local overrides = number(line()[2])
    for _ = 1, overrides do
        local args = line()
        local index = (number(args[1]) - 1) * 24 + number(args[2]) + 1
        data.loads[index] = number(args[3])
        data.base_pv[index] = number(args[4])
    end
    data.day_names = {}
    data.weekend_days = {}
    data.periods = {}
    for day = 1, data.day_count do
        local holiday = not not holidays[day]
        local weekend_day = holiday or (day - 1) % 7 >= 5
        data.day_names[day] = holiday and "HOL" or DAY_NAMES[(day - 1) % 7 + 1]
        data.weekend_days[day] = weekend_day
        local schedule = weekend_day and weekend or weekday
        for hour = 1, 24 do data.periods[#data.periods + 1] = schedule[hour] end
    end
    return data
end

local function hour_record(index, period, load, pv, soc, flows, drawn, shortfall, loss, price, feedin)
    local record = {
        index = index - 1, day = floor(index - 1, 24) + 1, hour = (index - 1) % 24,
        period = period, load = load, pv = pv, soc = soc, flows = flows,
        charge = flows[2] + flows[8], discharge = flows[5] + flows[6],
        imported = flows[7] + flows[8], exported = flows[3] + flows[6],
        curtailed = flows[4], drawn = drawn, shortfall = shortfall, loss = loss
    }
    record.import_cost = floor(record.imported * price, 100000)
    record.export_income = floor(record.exported * feedin, 100000)
    record.net_cost = record.import_cost - record.export_income
    return record
end

local function totals(records)
    local result = {count = #records, flows = {}}
    for _, field in ipairs(TOTAL_FIELDS) do result[field] = 0 end
    for index = 1, #FLOW_NAMES do result.flows[index] = 0 end
    for _, record in ipairs(records) do
        for _, field in ipairs(TOTAL_FIELDS) do result[field] = result[field] + record[field] end
        for index, value in ipairs(record.flows) do
            result.flows[index] = result.flows[index] + value
        end
    end
    result.net_cost = result.import_cost - result.export_income
    return result
end

local function simulation_result(strategy, settings, prices, data, start_soc, reserve, records)
    local result = {
        strategy = strategy, settings = copy(settings), prices = copy(prices),
        start_soc = start_soc, reserve = reserve, hours = records,
        days = {}, daily = {}, by_period = {}
    }
    for i = 1, #records, 24 do
        local daily = {}
        for j = i, i + 23 do daily[#daily + 1] = records[j] end
        result.days[#result.days + 1] = daily
        result.daily[#result.daily + 1] = totals(daily)
    end
    for _, period in ipairs(data.period_names) do
        local subset = {}
        for _, record in ipairs(records) do
            if record.period == period then subset[#subset + 1] = record end
        end
        result.by_period[period] = totals(subset)
    end
    result.total = totals(records)
    result.peak = 0
    for _, record in ipairs(records) do result.peak = max(result.peak, record.imported) end
    result.demand_charge = floor(result.peak * settings.DEMAND, 1000)
    result.bill = result.total.net_cost + settings.FIXED + result.demand_charge
    result.end_soc = records[#records].soc
    result.sufficiency = percentage(max(0, result.total.load - result.total.imported), result.total.load)
    return result
end

local function simulate(data, strategy, settings, prices, outage)
    local name, parameter = strategy.name, strategy.parameter
    local capacity, ceff, deff = settings.CAPACITY, settings.CEFF, settings.DEFF
    local reserve_percent = name == "BACKUP" and max(settings.RESERVE, parameter) or settings.RESERVE
    local reserve = floor(capacity * reserve_percent, 100)
    local start_soc = floor(capacity * settings.INITIAL, 100)
    local soc = start_soc
    local cheapest, peak = tariff_extremes(prices, data.period_names)
    local arbitrage = name == "EXPORTPEAK" and settings.FEEDIN > prices[cheapest]
    local records = {}

    local function discharge_target(deficit, period)
        if name == "TOU" then return period == peak and deficit or 0 end
        if name == "PEAKSHAVE" then return max(0, deficit - parameter) end
        if arbitrage and period == cheapest and period ~= peak then return 0 end
        return deficit
    end

    local function grid_charge(period, pv_charge, grid_load)
        local headroom = settings.CHARGE - pv_charge
        local target = nil
        if name == "TOU" and period == cheapest and period ~= peak then
            target = floor(capacity * parameter, 100)
        elseif name == "PEAKSHAVE" and period == cheapest then
            target = capacity
            headroom = min(headroom, max(0, parameter - grid_load))
        elseif name == "BACKUP" and period == cheapest then
            target = reserve
        elseif arbitrage and period == cheapest and period ~= peak then
            target = capacity
        end
        if target == nil then return 0 end
        local amount = min(headroom, ceiling(100 * max(0, target - soc), ceff))
        soc = soc + floor(amount * ceff, 100)
        return amount
    end

    for index = 1, #data.loads do
        local load = data.loads[index]
        local pv = floor(data.base_pv[index] * settings.PVSCALE, 100)
        local period = data.periods[index]
        local direct = min(load, pv)
        local surplus, deficit = pv - direct, load - direct
        local pv_charge = min(surplus, settings.CHARGE, ceiling(100 * (capacity - soc), ceff))
        soc = soc + floor(pv_charge * ceff, 100)
        surplus = surplus - pv_charge
        local is_outage = outage ~= nil and outage[1] <= index and index <= outage[2]
        local target = is_outage and deficit or discharge_target(deficit, period)
        local lower_bound = is_outage and 0 or reserve
        local load_drawn = min(ceiling(100 * target, deff), settings.DISCHARGE, max(0, soc - lower_bound))
        local load_discharge = floor(load_drawn * deff, 100)
        soc = soc - load_drawn
        deficit = deficit - load_discharge
        local grid_load, shortfall, pv_export, curtailed, additional_charge
        local export_drawn, battery_export = 0, 0
        if is_outage then
            grid_load, shortfall, pv_export, curtailed, additional_charge = 0, deficit, 0, surplus, 0
        else
            grid_load, shortfall = deficit, 0
            pv_export = min(surplus, settings.EXPORT)
            curtailed = surplus - pv_export
            additional_charge = grid_charge(period, pv_charge, grid_load)
            if arbitrage and period == peak and pv_charge == 0 then
                export_drawn = min(ceiling(100 * (settings.EXPORT - pv_export), deff),
                    settings.DISCHARGE - load_drawn, max(0, soc - reserve))
                battery_export = floor(export_drawn * deff, 100)
                soc = soc - export_drawn
            end
        end
        local loss = pv_charge - floor(pv_charge * ceff, 100)
            + additional_charge - floor(additional_charge * ceff, 100)
            + load_drawn - load_discharge + export_drawn - battery_export
        local flows = {direct, pv_charge, pv_export, curtailed, load_discharge,
            battery_export, grid_load, additional_charge}
        records[#records + 1] = hour_record(index, period, load, pv, soc, flows,
            load_drawn + export_drawn, shortfall, loss, prices[period], settings.FEEDIN)
    end
    return simulation_result(strategy, settings, prices, data, start_soc, reserve, records)
end

local Desk = {}
Desk.__index = Desk

function Desk.new(data)
    return setmetatable({
        data = data, settings = copy(data.initial_settings),
        prices = copy(data.initial_prices), current = nil
    }, Desk)
end

function Desk:require_result()
    if self.current == nil then fail("no run") end
    return self.current
end

function Desk:checked_day(token)
    local day = number(token)
    if day < 1 or day > self.data.day_count then fail("invalid day") end
    return day
end

function Desk:result_without_arguments(args)
    require_count(args, 0)
    return self:require_result()
end

function Desk:result_for_day(args)
    require_count(args, 1)
    local day = self:checked_day(args[1])
    return day, self:require_result()
end

function Desk:simulate(strategy, settings, prices, outage)
    return simulate(self.data, strategy, settings or self.settings, prices or self.prices, outage)
end

function Desk:baseline(settings, prices)
    local without_battery = copy(settings)
    without_battery.CAPACITY = 0
    return self:simulate({name = "SELF"}, without_battery, prices)
end

function Desk:run(args)
    local strategy = one_strategy(args)
    local result = self:simulate(strategy)
    self.current = result
    local total = result.total
    return {"RUN " .. strategy_text(strategy) .. " bill " .. money(result.bill)
        .. " import " .. total.imported .. " export " .. total.exported
        .. " soc " .. result.end_soc}
end

function Desk:set_value(args)
    require_count(args, 2)
    local item, token = args[1], args[2]
    local bounds = SETTING_RANGES[item]
    if bounds == nil then fail("unknown parameter " .. item) end
    local value = number(token)
    if value < bounds[1] or value > bounds[2] then fail("invalid value for " .. item) end
    local previous = self.settings[item]
    self.settings[item] = value
    return {"SET " .. item .. " " .. previous .. " -> " .. value}
end

function Desk:price(args)
    require_count(args, 2)
    local period, token = args[1], args[2]
    if self.prices[period] == nil then fail("unknown period " .. period) end
    local value = number(token)
    if value < 0 or value > 10000 then fail("invalid value for " .. period) end
    local previous = self.prices[period]
    self.prices[period] = value
    local cheapest, peak = tariff_extremes(self.prices, self.data.period_names)
    return {"PRICE " .. period .. " " .. previous .. " -> " .. value
        .. " cheapest " .. cheapest .. " peak " .. peak}
end

function Desk:reset(args)
    require_count(args, 0)
    self.settings = copy(self.data.initial_settings)
    self.prices = copy(self.data.initial_prices)
    return {"RESET"}
end

function Desk:config(args)
    require_count(args, 0)
    local battery, grid, tariff = {}, {}, {}
    for i = 1, 8 do
        local name = SETTING_NAMES[i]
        battery[#battery + 1] = name:lower() .. " " .. self.settings[name]
    end
    for i = 9, 12 do
        local name = SETTING_NAMES[i]
        grid[#grid + 1] = name:lower() .. " " .. self.settings[name]
    end
    for _, name in ipairs(self.data.period_names) do
        tariff[#tariff + 1] = name .. " " .. self.prices[name]
    end
    local cheapest, peak = tariff_extremes(self.prices, self.data.period_names)
    return {"BATTERY " .. table.concat(battery, " "), "GRID " .. table.concat(grid, " "),
        "SOLAR pvscale " .. self.settings.PVSCALE,
        "TARIFF " .. table.concat(tariff, " ") .. " cheapest " .. cheapest .. " peak " .. peak}
end

function Desk:no_battery(args)
    require_count(args, 0)
    local result = self:baseline(self.settings, self.prices)
    local total = result.total
    return {"NOBATTERY bill " .. money(result.bill) .. " import " .. total.imported
        .. " export " .. total.exported .. " curtailed " .. total.curtailed
        .. " peak " .. result.peak}
end

function Desk:compare(args)
    local strategies = parse_strategies(args)
    if #strategies == 0 then fail("wrong number of arguments") end
    local baseline = self:baseline(self.settings, self.prices)
    local trials = {}
    for i, strategy in ipairs(strategies) do
        trials[#trials + 1] = {result = self:simulate(strategy), index = i}
    end
    table.sort(trials, function(a, b)
        if a.result.bill ~= b.result.bill then return a.result.bill < b.result.bill end
        return a.index < b.index
    end)
    local output = {"COMPARE baseline " .. money(baseline.bill)}
    for index, item in ipairs(trials) do
        local result = item.result
        output[#output + 1] = index .. ". " .. strategy_text(result.strategy)
            .. " bill " .. money(result.bill) .. " saving " .. money(baseline.bill - result.bill)
            .. " sufficiency " .. result.sufficiency .. "%"
    end
    return output
end

function Desk:size(args)
    require_count(args, 3)
    local capacities = checked_range(number(args[1]), number(args[2]), number(args[3]), SETTING_RANGES.CAPACITY)
    local baseline = self:baseline(self.settings, self.prices)
    local output, best = {}, nil
    for _, capacity in ipairs(capacities) do
        local settings = copy(self.settings)
        settings.CAPACITY = capacity
        local result = self:simulate({name = "SELF"}, settings)
        local saving = baseline.bill - result.bill
        local cost = floor(capacity * settings.COST, 1000)
        local payback = "never"
        if saving > 0 then
            local tenths = floor(10 * cost, saving)
            payback = tostring(tenths // 10) .. "." .. tostring(tenths % 10)
            if best == nil or cost * best.saving < best.cost * saving then
                best = {capacity = capacity, cost = cost, saving = saving}
            end
        end
        output[#output + 1] = "SIZE " .. capacity .. " bill " .. money(result.bill)
            .. " saving " .. money(saving) .. " cost " .. money(cost) .. " payback " .. payback
    end
    output[#output + 1] = "BEST " .. (best and best.capacity or "none")
    return output
end

function Desk:sweep(args)
    if #args < 5 then fail("wrong number of arguments") end
    local item = args[1]
    local bounds = SETTING_RANGES[item]
    if not bounds then fail("unknown parameter " .. item) end
    local values = checked_range(number(args[2]), number(args[3]), number(args[4]), bounds)
    local rest = {}
    for i = 5, #args do rest[#rest + 1] = args[i] end
    local strategy = one_strategy(rest)
    local output, best = {}, nil
    for _, value in ipairs(values) do
        local settings = copy(self.settings)
        settings[item] = value
        local result = self:simulate(strategy, settings)
        local baseline = self:baseline(settings, self.prices)
        if best == nil or result.bill < best.bill then best = {value = value, bill = result.bill} end
        output[#output + 1] = "SWEEP " .. item .. " " .. value .. " bill " .. money(result.bill)
            .. " saving " .. money(baseline.bill - result.bill)
            .. " sufficiency " .. result.sufficiency .. "%"
    end
    output[#output + 1] = "BEST " .. best.value
    return output
end

function Desk:outage(args)
    require_count(args, 3)
    local day = self:checked_day(args[1])
    local start_hour, end_hour = number(args[2]), number(args[3])
    if start_hour < 0 or end_hour > 23 or start_hour > end_hour then fail("invalid hours") end
    local current = self:require_result()
    local first = (day - 1) * 24 + start_hour + 1
    local last = (day - 1) * 24 + end_hour + 1
    local result = self:simulate(current.strategy, current.settings, current.prices, {first, last})
    local before = first > 1 and result.hours[first - 1].soc or result.start_soc
    local output = {"OUTAGE day " .. day .. " hours " .. start_hour .. "-" .. end_hour
        .. " strategy " .. strategy_text(result.strategy) .. " soc " .. before,
        "hour   load     pv  disch    soc  short   curt"}
    local records = {}
    for i = first, last do
        local record = result.hours[i]
        records[#records + 1] = record
        output[#output + 1] = row({record.hour, record.load, record.pv, record.discharge,
            record.soc, record.shortfall, record.curtailed}, {4, 7, 7, 7, 7, 7, 7})
    end
    local total = totals(records)
    local served = total.load > 0 and percentage(total.load - total.shortfall, total.load) or "100.00"
    output[#output + 1] = "TOTAL load " .. total.load .. " unserved " .. total.shortfall
        .. " served " .. served .. "% bill " .. money(result.bill)
    return output
end

function Desk:diff(args)
    if #args < 2 then fail("wrong number of arguments") end
    local day = self:checked_day(args[1])
    local remaining = {}
    for i = 2, #args do remaining[#remaining + 1] = args[i] end
    local strategy = one_strategy(remaining)
    local current = self:require_result()
    local comparison = self:simulate(strategy, current.settings, current.prices)
    local output = {"DIFF day " .. day .. " " .. self.data.day_names[day] .. " "
        .. strategy_text(current.strategy) .. " vs " .. strategy_text(strategy),
        "hour   imp1   imp2   exp1   exp2   soc1   soc2"}
    local before, after = current.days[day], comparison.days[day]
    for i = 1, 24 do
        local a, b = before[i], after[i]
        output[#output + 1] = row({a.hour, a.imported, b.imported, a.exported,
            b.exported, a.soc, b.soc}, {4, 7, 7, 7, 7, 7, 7})
    end
    local cost1, cost2 = current.daily[day].net_cost, comparison.daily[day].net_cost
    output[#output + 1] = "TOTAL cost1 " .. money(cost1) .. " cost2 " .. money(cost2)
        .. " difference " .. money(cost2 - cost1)
    return output
end

function Desk:hourly(args)
    local day, result = self:result_for_day(args)
    local output = {"HOURLY day " .. day .. " " .. self.data.day_names[day]
        .. " strategy " .. strategy_text(result.strategy),
        "hour   load     pv charge  disch    soc import export   curt"}
    local widths = {4, 7, 7, 7, 7, 7, 7, 7, 7}
    for _, record in ipairs(result.days[day]) do
        output[#output + 1] = row({record.hour, record.load, record.pv, record.charge,
            record.discharge, record.soc, record.imported, record.exported, record.curtailed}, widths)
    end
    local total = result.daily[day]
    output[#output + 1] = row({"sum", total.load, total.pv, total.charge,
        total.discharge, "", total.imported, total.exported, total.curtailed}, widths)
    return output
end

function Desk:daily(args)
    local result = self:result_without_arguments(args)
    local output = {"DAILY strategy " .. strategy_text(result.strategy),
        "day name    load      pv  import  export    curt     soc      cost"}
    for day, total in ipairs(result.daily) do
        output[#output + 1] = row({day, self.data.day_names[day], total.load, total.pv,
            total.imported, total.exported, total.curtailed, result.days[day][24].soc,
            money(total.net_cost)}, {3, 5, 8, 8, 8, 8, 8, 8, 10})
    end
    local total = result.total
    output[#output + 1] = "TOTAL load " .. total.load .. " pv " .. total.pv
        .. " import " .. total.imported .. " export " .. total.exported
        .. " curtailed " .. total.curtailed .. " cost " .. money(total.net_cost)
    return output
end

function Desk:bill(args)
    local result = self:result_without_arguments(args)
    local output = {"BILL strategy " .. strategy_text(result.strategy)
        .. " days " .. self.data.day_count}
    for _, period in ipairs(self.data.period_names) do
        local total = result.by_period[period]
        output[#output + 1] = "IMPORT " .. period .. " " .. total.imported
            .. " Wh " .. money(total.import_cost)
    end
    local total = result.total
    output[#output + 1] = "EXPORT " .. total.exported .. " Wh " .. money(-total.export_income)
    output[#output + 1] = "FIXED " .. money(result.settings.FIXED)
    output[#output + 1] = "DEMAND " .. result.peak .. " Wh " .. money(result.demand_charge)
    output[#output + 1] = "TOTAL " .. money(result.bill)
    return output
end

function Desk:savings(args)
    local result = self:result_without_arguments(args)
    local baseline = self:baseline(result.settings, result.prices)
    local pairs = {}
    for _, period in ipairs(self.data.period_names) do
        pairs[#pairs + 1] = {period, baseline.by_period[period].import_cost,
            result.by_period[period].import_cost}
    end
    pairs[#pairs + 1] = {"EXPORT", -baseline.total.export_income, -result.total.export_income}
    pairs[#pairs + 1] = {"DEMAND", baseline.demand_charge, result.demand_charge}
    pairs[#pairs + 1] = {"TOTAL", baseline.bill, result.bill}
    local output = {"SAVINGS strategy " .. strategy_text(result.strategy)}
    for _, pair in ipairs(pairs) do
        local name, before, after = pair[1], pair[2], pair[3]
        output[#output + 1] = name .. " " .. money(before) .. " -> " .. money(after)
            .. " saving " .. money(before - after)
    end
    return output
end

function Desk:by_period(args)
    local result = self:result_without_arguments(args)
    local output = {"BYPERIOD strategy " .. strategy_text(result.strategy)}
    for _, period in ipairs(self.data.period_names) do
        local total = result.by_period[period]
        output[#output + 1] = period .. " hours " .. total.count .. " load " .. total.load
            .. " pv " .. total.pv .. " charge " .. total.charge
            .. " discharge " .. total.discharge .. " import " .. total.imported
            .. " export " .. total.exported
    end
    return output
end

function Desk:day_type(args)
    local result = self:result_without_arguments(args)
    local output = {"DAYTYPE strategy " .. strategy_text(result.strategy)}
    for _, spec in ipairs({{"WEEKDAY", false}, {"WEEKEND", true}}) do
        local label, weekend = spec[1], spec[2]
        local day_count, records = 0, {}
        for day, flag in ipairs(self.data.weekend_days) do
            if flag == weekend then
                day_count = day_count + 1
                for _, record in ipairs(result.days[day]) do records[#records + 1] = record end
            end
        end
        local total = totals(records)
        output[#output + 1] = label .. " days " .. day_count
            .. " load " .. floor(total.load, day_count)
            .. " pv " .. floor(total.pv, day_count)
            .. " import " .. floor(total.imported, day_count)
            .. " export " .. floor(total.exported, day_count)
            .. " cost " .. money(truncate_divide(total.net_cost, day_count))
    end
    return output
end

function Desk:peaks(args)
    require_count(args, 1)
    local amount = number(args[1])
    if amount < 1 then fail("invalid count") end
    local result = self:require_result()
    local records = {}
    for _, record in ipairs(result.hours) do
        if record.imported > 0 then records[#records + 1] = record end
    end
    table.sort(records, function(a, b)
        if a.imported ~= b.imported then return a.imported > b.imported end
        return a.index < b.index
    end)
    local output = {"PEAKS strategy " .. strategy_text(result.strategy)}
    for index = 1, min(amount, #records) do
        local record = records[index]
        output[#output + 1] = index .. ". day " .. record.day .. " hour " .. record.hour
            .. " " .. record.period .. " import " .. record.imported
            .. " load " .. record.load .. " soc " .. record.soc
    end
    if #records == 0 then output[#output + 1] = "none" end
    return output
end

function Desk:profile(args)
    local result = self:result_without_arguments(args)
    local output = {"PROFILE strategy " .. strategy_text(result.strategy)
        .. " days " .. self.data.day_count, "hour   load     pv import export    soc"}
    for hour = 0, 23 do
        local sums = {load = 0, pv = 0, imported = 0, exported = 0, soc = 0}
        for day = 0, self.data.day_count - 1 do
            local record = result.hours[day * 24 + hour + 1]
            for field in pairs(sums) do sums[field] = sums[field] + record[field] end
        end
        output[#output + 1] = row({hour, floor(sums.load, self.data.day_count),
            floor(sums.pv, self.data.day_count), floor(sums.imported, self.data.day_count),
            floor(sums.exported, self.data.day_count), floor(sums.soc, self.data.day_count)},
            {4, 7, 7, 7, 7, 7})
    end
    return output
end

function Desk:flows(args)
    local result = self:result_without_arguments(args)
    local output = {"FLOWS strategy " .. strategy_text(result.strategy)}
    for index, name in ipairs(FLOW_NAMES) do
        output[#output + 1] = name .. " " .. result.total.flows[index]
    end
    output[#output + 1] = "LOSSES " .. result.total.loss
    output[#output + 1] = "STORED " .. (result.end_soc - result.start_soc)
    return output
end

function Desk:self_suff(args)
    local result = self:result_without_arguments(args)
    local flows = result.total.flows
    return {"SELFSUFF sufficiency " .. result.sufficiency .. "% consumption "
        .. percentage(flows[1] + flows[2], result.total.pv) .. "%"}
end

function Desk:cycles(args)
    local result = self:result_without_arguments(args)
    local drawn = result.total.drawn
    local capacity = result.settings.CAPACITY
    local common = gcd(drawn, capacity)
    local numerator, denominator = floor(drawn, common), floor(capacity, common)
    local thousandths = floor(1000 * drawn, capacity)
    local decimal = tostring(thousandths // 1000) .. "." .. string.format("%03d", thousandths % 1000)
    return {"CYCLES " .. numerator .. "/" .. denominator .. " " .. decimal
        .. " drawn " .. drawn .. " losses " .. result.total.loss}
end

function Desk:usage(args)
    local result = self:result_without_arguments(args)
    local hours = result.hours
    local charging, discharging, idle, full = 0, 0, 0, 0
    local low, run_length, longest, first = 0, 0, 0, nil
    for i, record in ipairs(hours) do
        if record.charge > 0 then charging = charging + 1 end
        if record.drawn > 0 then discharging = discharging + 1 end
        if record.charge == 0 and record.drawn == 0 then idle = idle + 1 end
        if record.soc == result.settings.CAPACITY then full = full + 1 end
        if record.soc <= result.reserve then
            low = low + 1
            run_length = run_length + 1
            if run_length > longest then
                longest = run_length
                first = hours[i - run_length + 1]
            end
        else
            run_length = 0
        end
    end
    local text = "USAGE charging " .. charging .. " discharging " .. discharging
        .. " idle " .. idle .. " full " .. full .. " low " .. low .. " longest " .. longest
    if first then text = text .. " from day " .. first.day .. " hour " .. first.hour end
    return {text}
end

function Desk:histogram(args)
    local result = self:result_without_arguments(args)
    local bands = {}
    for index = 1, 10 do bands[index] = 0 end
    for _, record in ipairs(result.hours) do
        local band = min(9, floor(10 * record.soc, result.settings.CAPACITY))
        bands[band + 1] = bands[band + 1] + 1
    end
    local output = {"HISTOGRAM strategy " .. strategy_text(result.strategy)}
    for index = 1, 10 do
        local amount = bands[index]
        local width = floor(20 * amount, #result.hours)
        output[#output + 1] = string.format("%3d", 10 * (index - 1))
            .. "% " .. bar(width) .. " " .. amount
    end
    return output
end

function Desk:chart(args)
    local day, result = self:result_for_day(args)
    local capacity = result.settings.CAPACITY
    local output = {"CHART day " .. day .. " " .. self.data.day_names[day]
        .. " strategy " .. strategy_text(result.strategy)}
    for _, record in ipairs(result.days[day]) do
        local width = floor(20 * record.soc, capacity)
        output[#output + 1] = string.format("%2d", record.hour)
            .. " " .. bar(width) .. " " .. percentage(record.soc, capacity) .. "%"
    end
    return output
end

local HANDLERS = {
    RUN = "run", SET = "set_value", PRICE = "price", RESET = "reset", CONFIG = "config",
    NOBATTERY = "no_battery", COMPARE = "compare", SIZE = "size", SWEEP = "sweep",
    OUTAGE = "outage", DIFF = "diff", HOURLY = "hourly", DAILY = "daily", BILL = "bill",
    SAVINGS = "savings", BYPERIOD = "by_period", DAYTYPE = "day_type", PEAKS = "peaks",
    PROFILE = "profile", FLOWS = "flows", SELFSUFF = "self_suff", CYCLES = "cycles",
    USAGE = "usage", HISTOGRAM = "histogram", CHART = "chart"
}

function Desk:execute(tokens)
    local command = tokens[1]
    local handler = HANDLERS[command]
    if handler == nil then return {"ERROR unknown command " .. command} end
    local args = {}
    for i = 2, #tokens do args[#args + 1] = tokens[i] end
    local success, output = pcall(self[handler], self, args)
    if success then return output end
    if type(output) ~= "table" or output.reason == nil then error(output, 0) end
    return {"ERROR " .. output.reason}
end

local data = read_input()
local desk = Desk.new(data)
local output = {}
while true do
    local line = io.read("*l")
    if not line then break end
    local tokens = split(line)
    if tokens[1] == "END" then break end
    local lines = desk:execute(tokens)
    for _, result in ipairs(lines) do output[#output + 1] = result end
end
if #output > 0 then io.write(table.concat(output, "\n"), "\n") end
