local Q = require("rational")
local M = {}
local reserved = { bounds = true, integer = true, binary = true, free = true, inf = true }
local function name(word)
    return word and word:match("^[a-z][a-z0-9_]*$") and not reserved[word]
end
local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do result[#result + 1] = word end
    return result
end
local function expression(items, first, last)
    local terms, pos, sign = {}, first, 1
    if items[pos] == "-" then sign, pos = -1, pos + 1 end
    while pos <= last do
        local coefficient, variable = Q.read(items[pos]), false
        if coefficient then
            if pos + 1 > last or not name(items[pos + 1]) then return false end
            variable, pos = items[pos + 1], pos + 2
        elseif name(items[pos]) then
            coefficient, variable, pos = Q.one, items[pos], pos + 1
        else return false end
        terms[#terms + 1] = { variable, sign * coefficient }
        if pos > last then return terms end
        if items[pos] ~= "+" and items[pos] ~= "-" then return false end
        sign, pos = items[pos] == "+" and 1 or -1, pos + 1
    end
    return false
end
local function named(items, last)
    if last < 2 then return false end
    local label = items[1]:match("^(.*):$")
    if not name(label) then return false end
    local terms = expression(items, 2, last)
    return terms and { name = label, terms = terms } or false
end
local function constraint(items, line)
    local n = #items
    if n < 4 or (items[n - 1] ~= "<=" and items[n - 1] ~= ">=" and items[n - 1] ~= "=") then return false end
    local rhs, result = Q.read(items[n], true), named(items, n - 2)
    if not rhs or not result then return false end
    result.rhs, result.comparison, result.line = rhs, items[n - 1], line
    return result
end
local function bound(items, line)
    local n = #items
    if n == 2 and name(items[1]) and items[2] == "free" then
        return { line = line, name = items[1], kind = "both", lower = false, upper = false }
    elseif n == 3 and name(items[1]) then
        local value, op = Q.read(items[3], true), items[2]
        if op == ">=" and (value or items[3] == "-inf") then
            return { line = line, name = items[1], kind = "lower", lower = value, upper = false }
        elseif op == "<=" and (value or items[3] == "inf") then
            return { line = line, name = items[1], kind = "upper", lower = false, upper = value }
        elseif op == "=" and value then
            return { line = line, name = items[1], kind = "both", lower = value, upper = value }
        end
    elseif n == 5 and items[2] == "<=" and items[4] == "<=" and name(items[3]) then
        local lower, upper = Q.read(items[1], true), Q.read(items[5], true)
        if (lower or items[1] == "-inf") and (upper or items[5] == "inf") then
            return { line = line, name = items[3], kind = "both", lower = lower, upper = upper }
        end
    end
    return false
end
local function block(model_name, body, ending)
    local result = { name = model_name, constraints = {}, bounds = {}, integers = {}, binaries = {} }
    local state = "A"
    for _, record in ipairs(body) do
        local line, text = record[1], record[2]
        local items, accepted = words(text), false
        if state == "A" and (text == "maximize" or text == "minimize") then
            result.direction, state, accepted = text, "B", true
        elseif state == "B" then
            local item = named(items, #items)
            if item then result.objective, state, accepted = item.terms, "C", true end
        elseif state == "C" and text == "subject to" then state, accepted = "D", true
        elseif state == "D" or state == "E" then
            local transitions = { bounds = "F", integer = "G", binary = "H" }
            if state == "E" and transitions[text] then state, accepted = transitions[text], true
            else
                local item = constraint(items, line)
                if item then result.constraints[#result.constraints + 1], state, accepted = item, "E", true end
            end
        elseif state == "F" then
            if text == "integer" or text == "binary" then state, accepted = text == "integer" and "G" or "H", true
            else
                local item = bound(items, line)
                if item then result.bounds[#result.bounds + 1], accepted = item, true end
            end
        elseif state == "G" or state == "H" then
            if state == "G" and text == "binary" then state, accepted = "H", true
            else
                accepted = true
                for _, word in ipairs(items) do if not name(word) then accepted = false; break end end
                if accepted then
                    local target = state == "G" and result.integers or result.binaries
                    target[#target + 1] = { line, items }
                end
            end
        end
        if not accepted then result.error = { line, "syntax error" }; return result end
    end
    if state == "A" or state == "B" or state == "C" or state == "D" then result.error = { ending, "syntax error" } end
    return result
end
function M.models()
    local result, model_name, body, line_number = {}, false, {}, 0
    for text in io.lines("input/models.lp") do
        line_number = line_number + 1
        if text ~= "" and text:sub(1, 1) ~= "#" then
            if not model_name then model_name, body = text:match("^model (.+)$"), {}
            elseif text == "end" then
                result[#result + 1] = block(model_name, body, line_number)
                model_name = false
            else body[#body + 1] = { line_number, text } end
        end
    end
    return result
end
function M.settings()
    local result = { logs = {}, limits = {} }
    local index = 0
    for text in io.lines("input/params.txt") do
        index = index + 1
        local items = words(text)
        if index == 1 then result.level = tonumber(items[2])
        elseif index == 2 then result.limit = tonumber(items[2])
        elseif #items > 0 then
            local target = items[1] == "log" and result.logs or result.limits
            target[items[2]] = tonumber(items[3])
        end
    end
    return result
end
return M
