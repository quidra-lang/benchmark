local V = require("values_fields")
local B = {}
function B.fail(position, message) error({ category = "runtime", position = position, message = message }, 0) end
local function digit(ch) return ch ~= "" and ch >= "0" and ch <= "9" end
function B.format(arguments, position)
    local fmt, pieces, index, argument_index = V.to_string(arguments[1]), {}, 1, 2
    while index <= #fmt do
        local ch = fmt:sub(index, index)
        if ch ~= "%" then pieces[#pieces + 1], index = ch, index + 1
        elseif fmt:sub(index + 1, index + 1) == "%" then pieces[#pieces + 1], index = "%", index + 2
        else
            index = index + 1
            local flags = {}
            while fmt:sub(index, index) == "-" or fmt:sub(index, index) == "0" do flags[fmt:sub(index, index)], index = true, index + 1 end
            local start = index
            while digit(fmt:sub(index, index)) do index = index + 1 end
            local width = index > start and tonumber(fmt:sub(start, index - 1)) or 0
            local precision = false
            if fmt:sub(index, index) == "." then
                index, start = index + 1, index + 1
                while digit(fmt:sub(index, index)) do index = index + 1 end
                precision = index > start and tonumber(fmt:sub(start, index - 1)) or 0
            end
            local conversion = fmt:sub(index, index)
            if conversion == "" or not ({ d = true, i = true, s = true, c = true, x = true, o = true })[conversion] then B.fail(position, "invalid format") end
            index = index + 1
            local value = arguments[argument_index]
            if not value then B.fail(position, "not enough arguments") end
            argument_index = argument_index + 1
            local numeric = conversion == "d" or conversion == "i" or conversion == "x" or conversion == "o"
            local body
            if numeric then
                local integer = V.to_number(value)
                local digits = string.format("%" .. ((conversion == "d" or conversion == "i") and "d" or conversion), math.abs(integer))
                if precision ~= false then
                    if precision == 0 and integer == 0 then digits = ""
                    elseif #digits < precision then digits = string.rep("0", precision - #digits) .. digits end
                end
                body = (integer < 0 and "-" or "") .. digits
            elseif conversion == "s" then
                body = V.to_string(value)
                if precision ~= false then body = body:sub(1, precision) end
            else
                if value.kind == "number" or value.kind == "strnum" then
                    local code = V.to_number(value)
                    if code ~= 10 and (code < 32 or code > 126) then B.fail(position, "invalid character code") end
                    body = string.char(code)
                else body = V.to_string(value):sub(1, 1) end
            end
            local missing = width - #body
            if missing > 0 then
                if flags["-"] then body = body .. string.rep(" ", missing)
                elseif numeric and flags["0"] and precision == false then
                    if body:sub(1, 1) == "-" then body = "-" .. string.rep("0", missing) .. body:sub(2)
                    else body = string.rep("0", missing) .. body end
                else body = string.rep(" ", missing) .. body end
            end
            pieces[#pieces + 1] = body
        end
    end
    return table.concat(pieces)
end
function B.invoke(name, arguments, position)
    if name == "sprintf" then return V.string(B.format(arguments, position))
    elseif name == "int" then return V.number(V.to_number(arguments[1])) end
    local text = V.to_string(arguments[1])
    if name == "substr" then
        local start = V.to_number(arguments[2])
        local ending = arguments[3] and start + V.to_number(arguments[3]) or #text + 1
        start, ending = math.max(start, 1), math.min(ending, #text + 1)
        return V.string(ending > start and text:sub(start, ending - 1) or "")
    elseif name == "index" then
        local sought = V.to_string(arguments[2])
        return V.number(sought ~= "" and (text:find(sought, 1, true) or 0) or 0)
    end
    local parts = {}
    for i = 1, #text do
        local code = text:byte(i)
        if name == "toupper" and code >= 97 and code <= 122 then code = code - 32
        elseif name == "tolower" and code >= 65 and code <= 90 then code = code + 32 end
        parts[#parts + 1] = string.char(code)
    end
    return V.string(table.concat(parts))
end
return B
