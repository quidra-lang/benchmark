local P = {}
P.kinds = { "copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print" }
function P.copy(value)
    local result = {}
    for key, item in pairs(value) do result[key] = item end
    return result
end
function P.function_copy(fn)
    local code = {}
    for i, line in ipairs(fn.code) do code[i] = line end
    return { name = fn.name, parameters = fn.parameters, code = code, temporary_serial = 0, preheader_serial = 0 }
end
function P.fields(instruction)
    local kind = instruction.kind
    if kind == "bin" or kind == "if" or kind == "store" then return { "a", "b" } end
    if kind == "copy" or kind == "load" or kind == "param" or kind == "print" or kind == "return" and instruction.a ~= nil then return { "a" } end
    return {}
end
function P.used(instruction)
    local result = {}
    for _, field in ipairs(P.fields(instruction)) do
        local value = instruction[field]
        if type(value) == "string" then result[#result + 1] = value end
    end
    return result
end
function P.expression(instruction)
    if instruction.kind == "bin" then return tostring(instruction.a) .. instruction.operation .. tostring(instruction.b)
    elseif instruction.kind == "load" then return instruction.name .. "[" .. tostring(instruction.a) .. "]" end
end
function P.calculate(operator, a, b)
    if operator == "+" then return a + b elseif operator == "-" then return a - b elseif operator == "*" then return a * b end
    if operator == "/" or operator == "%" then
        local quotient = math.abs(a) // math.abs(b)
        if (a < 0) ~= (b < 0) then quotient = -quotient end
        return operator == "/" and quotient or a - b * quotient
    end
    local result
    if operator == "<" then result = a < b elseif operator == "<=" then result = a <= b
    elseif operator == ">" then result = a > b elseif operator == ">=" then result = a >= b
    elseif operator == "==" then result = a == b else result = a ~= b end
    return result and 1 or 0
end
function P.string(instruction)
    local kind, a, b = instruction.kind, tostring(instruction.a), tostring(instruction.b)
    if kind == "copy" then return instruction.destination .. " = " .. a
    elseif kind == "bin" then return instruction.destination .. " = " .. a .. " " .. instruction.operation .. " " .. b
    elseif kind == "load" then return instruction.destination .. " = " .. instruction.name .. "[" .. a .. "]"
    elseif kind == "store" then return instruction.name .. "[" .. a .. "] = " .. b
    elseif kind == "goto" then return "goto " .. instruction.name
    elseif kind == "if" then return "if " .. a .. " " .. instruction.operation .. " " .. b .. " goto " .. instruction.name
    elseif kind == "call" then return (instruction.destination and instruction.destination .. " = " or "") .. "call " .. instruction.name .. " " .. instruction.count
    elseif kind == "read" then return "read " .. instruction.destination
    elseif kind == "return" and instruction.a == nil then return "return" end
    return kind .. " " .. a
end
function P.function_lines(fn)
    local result = { "func " .. fn.name .. (#fn.parameters > 0 and " " .. table.concat(fn.parameters, " ") or "") }
    for _, line in ipairs(fn.code) do result[#result + 1] = type(line) == "string" and line .. ":" or "    " .. P.string(line) end
    result[#result + 1] = "end"
    return result
end
function P.program_lines(program)
    local result = {}
    for _, array in ipairs(program.arrays) do result[#result + 1] = "array " .. array[1] .. " " .. array[2] end
    for _, fn in ipairs(program.functions) do
        if #result > 0 then result[#result + 1] = "" end
        for _, line in ipairs(P.function_lines(fn)) do result[#result + 1] = line end
    end
    return result
end
local function operand(word)
    local first = word:byte(1)
    return (first == 45 or first >= 48 and first <= 57) and assert(math.tointeger(tonumber(word))) or word
end
local function array(word)
    local name, index = word:match("^([^%[]+)%[(.*)%]$")
    return name, operand(index)
end
local function instruction(words)
    local first, value = words[1], {}
    if first == "goto" then value.kind, value.name = "goto", words[2]
    elseif first == "if" then value.kind, value.a, value.operation, value.b, value.name = "if", operand(words[2]), words[3], operand(words[4]), words[6]
    elseif first == "param" or first == "print" then value.kind, value.a = first, operand(words[2])
    elseif first == "return" then value.kind, value.a = first, words[2] and operand(words[2]) or nil
    elseif first == "read" then value.kind, value.destination = first, words[2]
    elseif first == "call" then value.kind, value.name, value.count = first, words[2], tonumber(words[3])
    elseif first:find("[", 1, true) then value.kind, value.name, value.a, value.b = "store", array(first); value.b = operand(words[3])
    elseif words[3] == "call" then value.kind, value.destination, value.name, value.count = "call", first, words[4], tonumber(words[5])
    elseif #words == 5 then value.kind, value.destination, value.a, value.operation, value.b = "bin", first, operand(words[3]), words[4], operand(words[5])
    elseif words[3]:find("[", 1, true) then value.kind, value.destination = "load", first; value.name, value.a = array(words[3])
    else value.kind, value.destination, value.a = "copy", first, operand(words[3]) end
    return value
end
function P.read(path)
    local result, current = { arrays = {}, functions = {} }
    for line in io.lines(path) do
        local words = {}
        for word in line:gmatch("[^ ]+") do words[#words + 1] = word end
        if #words > 0 and words[1]:sub(1, 1) ~= "#" then
            if words[1] == "array" then result.arrays[#result.arrays + 1] = { words[2], tonumber(words[3]) }
            elseif words[1] == "func" then
                local parameters = {}
                for i = 3, #words do parameters[#parameters + 1] = words[i] end
                current = { name = words[2], parameters = parameters, code = {}, temporary_serial = 0, preheader_serial = 0 }
                result.functions[#result.functions + 1] = current
            elseif words[1] == "end" then current = nil
            elseif #words == 1 and words[1]:sub(-1) == ":" then current.code[#current.code + 1] = words[1]:sub(1, -2)
            else current.code[#current.code + 1] = instruction(words) end
        end
    end
    return result
end
return P
