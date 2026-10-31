local M = {}
local function split(text, delimiter)
    local values = {}
    for value in (text .. delimiter):gmatch("(.-)" .. delimiter) do
        values[#values + 1] = value
    end
    return values
end
local function rows(name)
    local handle = assert(io.open("input/" .. name, "rb"))
    handle:read("l")
    local result = {}
    for line in handle:lines() do
        result[#result + 1] = split(line, ",")
    end
    handle:close()
    return result
end
function M.read_inputs()
    local series, named, events, inventory, settings = {}, {}, {}, {}, {}
    for _, row in ipairs(rows("series.csv")) do
        local record = named[row[1]]
        if not record then
            record = {name = row[1], periods = {}, raw = {}}
            series[#series + 1], named[row[1]], events[row[1]] = record, record, {}
        end
        record.periods[#record.periods + 1] = row[2]
        if row[3] == "NA" then
            record.raw[#record.raw + 1] = false
        else
            record.raw[#record.raw + 1] = tonumber(row[3])
        end
    end
    for _, row in ipairs(rows("events.csv")) do
        events[row[1]][row[2]] = row[3]
    end
    for _, row in ipairs(rows("inventory.csv")) do
        inventory[row[1]] = {on_hand = tonumber(row[2]), lead_time = tonumber(row[3]), review = tonumber(row[4]), service = tonumber(row[5])}
    end
    for line in io.lines("input/params.txt") do
        local fields, values = split(line, " "), {}
        for i = 2, #fields do
            values[#values + 1] = tonumber(fields[i])
        end
        if ({alpha = true, beta = true, gamma = true, phi = true, interval = true, ljung_box = true})[fields[1]] then
            settings[fields[1]] = values
        else
            settings[fields[1]] = values[1]
        end
    end
    return series, events, inventory, settings
end
function M.next_month(period)
    local year, month = period:match("^(%d+)%-(%d+)$")
    year, month = tonumber(year), tonumber(month)
    year, month = year + month // 12, month % 12 + 1
    return string.format("%04d-%02d", year, month)
end
function M.real(value)
    if value == nil or value == false then
        return "NA"
    end
    local text = string.format("%.4f", value)
    return text == "-0.0000" and "0.0000" or text
end
function M.write_lines(name, lines)
    local handle = assert(io.open("output/" .. name, "wb"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
end
return M
