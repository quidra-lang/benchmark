local V = {}
V.UNINITIALIZED = { kind = "uninitialized", numeric = 0 }
function V.number(value) return { kind = "number", numeric = value } end
function V.string(value) return { kind = "string", text = value } end
local function whitespace(ch) return ch == " " or ch == "\t" or ch == "\n" end
local function digit(ch) return ch ~= "" and ch >= "0" and ch <= "9" end
function V.numeric_prefix(text)
    local index, sign, value = 1, 1, 0
    while index <= #text and whitespace(text:sub(index, index)) do index = index + 1 end
    if text:sub(index, index) == "-" then sign, index = -1, index + 1
    elseif text:sub(index, index) == "+" then index = index + 1 end
    while digit(text:sub(index, index)) do value, index = value * 10 + text:byte(index) - 48, index + 1 end
    return sign * value
end
function V.input(text)
    local first, last = 1, #text
    while first <= last and whitespace(text:sub(first, first)) do first = first + 1 end
    while last >= first and whitespace(text:sub(last, last)) do last = last - 1 end
    local index = first
    if text:sub(index, index) == "+" or text:sub(index, index) == "-" then index = index + 1 end
    local numeric = index <= last
    for i = index, last do if not digit(text:sub(i, i)) then numeric = false; break end end
    return numeric and { kind = "strnum", text = text, numeric = V.numeric_prefix(text) } or V.string(text)
end
function V.to_number(value)
    if value.kind == "string" then return V.numeric_prefix(value.text) end
    return value.numeric
end
function V.to_string(value)
    if value.kind == "number" then return tostring(value.numeric)
    elseif value.kind == "uninitialized" then return "" end
    return value.text
end
function V.truth(value)
    if value.kind == "string" then return value.text ~= "" end
    return value.numeric ~= 0
end
function V.compare(first, second)
    local a, b
    if first.kind ~= "string" and second.kind ~= "string" then a, b = V.to_number(first), V.to_number(second)
    else a, b = V.to_string(first), V.to_string(second) end
    return a < b and -1 or (a > b and 1 or 0)
end
function V.integer_key(text)
    if text == "0" then return 0 end
    local first = text:sub(1, 1) == "-" and 2 or 1
    if text:sub(first, first) < "1" or text:sub(first, first) > "9" then return nil end
    for i = first + 1, #text do if not digit(text:sub(i, i)) then return nil end end
    return tonumber(text)
end
function V.key_less(a, b)
    local x, y = V.integer_key(a), V.integer_key(b)
    if x ~= nil and y ~= nil then return x < y elseif x ~= nil then return true elseif y ~= nil then return false end
    return a < b
end
function V.split(text, separator)
    local pieces = {}
    if text == "" then return pieces end
    if separator == "" then for i = 1, #text do pieces[#pieces + 1] = text:sub(i, i) end
    elseif separator == " " then
        local start
        for i = 1, #text do
            if whitespace(text:sub(i, i)) then
                if start then pieces[#pieces + 1], start = text:sub(start, i - 1), nil end
            elseif not start then start = i end
        end
        if start then pieces[#pieces + 1] = text:sub(start) end
    else
        local start = 1
        while true do
            local at = text:find(separator, start, true)
            if not at then pieces[#pieces + 1] = text:sub(start); break end
            pieces[#pieces + 1], start = text:sub(start, at - 1), at + #separator
        end
    end
    return pieces
end
local R = {}
R.__index = R
function V.record(special) return setmetatable({ special = special, zero = V.string(""), fields = {} }, R) end
function R:set(text)
    self.zero, self.fields = V.input(text), {}
    for i, piece in ipairs(V.split(text, V.to_string(self.special("FS")))) do self.fields[i] = V.input(piece) end
end
function R:read(index)
    if index == 0 then return self.zero end
    return self.fields[index] or V.UNINITIALIZED
end
function R:rebuild()
    local parts = {}
    for i, field in ipairs(self.fields) do parts[i] = V.to_string(field) end
    self.zero = V.input(table.concat(parts, V.to_string(self.special("OFS"))))
end
function R:write(index, value)
    if index == 0 then self:set(V.to_string(value)); return end
    for i = #self.fields + 1, index do self.fields[i] = V.string("") end
    self.fields[index] = value
    self:rebuild()
end
function R:resize(size)
    for i = #self.fields, size + 1, -1 do self.fields[i] = nil end
    for i = #self.fields + 1, size do self.fields[i] = V.string("") end
    self:rebuild()
end
function V.quoted(text)
    local parts, escapes = { '"' }, { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" }
    for i = 1, #text do
        local ch, code = text:sub(i, i), text:byte(i)
        parts[#parts + 1] = escapes[ch] or (code >= 32 and code <= 126 and ch or string.format("\\%03o", code))
    end
    parts[#parts + 1] = '"'
    return table.concat(parts)
end
function V.describe(value)
    if value.kind == "number" then return tostring(value.numeric)
    elseif value.kind == "uninitialized" then return "(uninitialized)" end
    return V.quoted(value.text) .. (value.kind == "strnum" and " (strnum)" or "")
end
return V
