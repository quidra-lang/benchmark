local M = {}
function M.normalize(values)
    local total, result = 0.0, {}
    for _, value in ipairs(values) do total = total + value end
    for i, value in ipairs(values) do result[i] = value / total end
    return result
end
function M.model(name, template, initial, transition, emission)
    local result = {name = name, states = template.states, symbols = template.symbols, missing = template.missing,
        initial = M.normalize(initial), transition = {}, emission = {}}
    for i, row in ipairs(transition) do result.transition[i] = M.normalize(row) end
    for i, row in ipairs(emission) do result.emission[i] = M.normalize(row) end
    return result
end
local function read_tokens(name)
    local input = assert(io.open("input/" .. name, "r"))
    local result = {}
    for line in input:lines() do
        local fields = {}
        for word in line:gmatch("%S+") do fields[#fields + 1] = word end
        result[#result + 1] = fields
    end
    input:close()
    return result
end
local function numbers(row, start)
    local result = {}
    for i = start, #row do result[#result + 1] = tonumber(row[i]) end
    return result
end
function M.read()
    local rows = read_tokens("model.txt")
    local states, symbols = {}, {}
    for i = 2, #rows[1] do states[#states + 1] = rows[1][i] end
    for i = 2, #rows[2] do symbols[#symbols + 1] = rows[2][i] end
    local template = {states = states, symbols = symbols, missing = rows[3][2]}
    local transition, emission = {}, {}
    for i = 1, #states do
        transition[i] = numbers(rows[4 + i], 3)
        emission[i] = numbers(rows[4 + #states + i], 3)
    end
    return M.model("INITIAL", template, numbers(rows[4], 2), transition, emission),
        read_tokens("sequences.txt"), read_tokens("labeled.txt"), read_tokens("params.txt")
end
function M.real(value, places)
    if value == nil then return "-" end
    places = places or 4
    local scale = math.tointeger(10 ^ places)
    local rounded = math.floor(math.abs(value) * scale + 0.5)
    local sign = value < 0 and rounded ~= 0 and "-" or ""
    return sign .. string.format("%d.%0" .. places .. "d", rounded // scale, rounded % scale)
end
function M.values(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = M.real(value) end
    return table.concat(result, " ")
end
function M.model_lines(model)
    local result = {"MODEL " .. model.name, "STATES " .. table.concat(model.states, " "),
        "SYMBOLS " .. table.concat(model.symbols, " "), "MISSING " .. model.missing, "INITIAL " .. M.values(model.initial)}
    for i, row in ipairs(model.transition) do result[#result + 1] = "TRANSITION " .. model.states[i] .. " " .. M.values(row) end
    for i, row in ipairs(model.emission) do result[#result + 1] = "EMISSION " .. model.states[i] .. " " .. M.values(row) end
    return result
end
function M.write(name, rows)
    local output = assert(io.open("output/" .. name, "w"))
    output:write(table.concat(rows, "\n"), "\n")
    output:close()
end
return M
