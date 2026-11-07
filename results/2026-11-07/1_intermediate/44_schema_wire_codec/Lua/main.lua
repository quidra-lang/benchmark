local CodecError = {}
local function fail(message)
    error(setmetatable({ message = message }, CodecError), 0)
end
local function input_line()
    return (io.read("*l"):gsub("\r$", ""))
end
local function words(source)
    local result = {}
    for word in source:gmatch("[^ ]+") do result[#result + 1] = word end
    return result
end
local function rest(source, count)
    local position = 1
    for _ = 1, count do position = source:find(" ", position, true) + 1 end
    return source:sub(position)
end
local function digit(character)
    return character:match("^[0-9]$") ~= nil
end
local function letter(character)
    return character:match("^[A-Za-z]$") ~= nil
end
local function valid_hex(source)
    return #source % 2 == 0 and not source:find("[^0-9a-f]")
end
local function hex_bytes(source)
    local result = {}
    for i = 1, #source, 2 do result[#result + 1] = string.char(tonumber(source:sub(i, i + 1), 16)) end
    return table.concat(result)
end
local function hex_text(source, empty_mark)
    if source == "" and empty_mark then return "-" end
    local result = {}
    for i = 1, #source do result[i] = string.format("%02x", source:byte(i)) end
    return table.concat(result)
end
local function zigzag(value)
    if value >= 0 then return 2 * value end
    return -2 * value - 1
end
local function varint(value)
    local result = {}
    while value >= 128 do
        result[#result + 1] = string.char(value % 128 + 128)
        value = value // 128
    end
    result[#result + 1] = string.char(value)
    return table.concat(result)
end
local wire_names = { [0] = "varint", [1] = "i64", [2] = "len", [5] = "i32" }

local Type = {}
Type.__index = Type
function Type.new(name, kind, wire, minimum, maximum)
    return setmetatable({
        name = name, kind = kind, wire = wire, minimum = minimum, maximum = maximum,
        fields = {}, by_name = {}, by_number = {}, members = {}, numbers = {}, enum_order = {},
    }, Type)
end
function Type:in_range(value)
    return not self.minimum or (value >= self.minimum and value <= self.maximum)
end
local function load_schema()
    local types = {}
    local scalars = {
        { "uint32", 0, 0, 4294967295 }, { "uint64", 0, 0, 9007199254740991 },
        { "sint32", 0, -2147483648, 2147483647 }, { "sint64", 0, -4503599627370496, 4503599627370495 },
        { "bool", 0 }, { "fixed32", 5, 0, 4294967295 },
        { "sfixed32", 5, -2147483648, 2147483647 }, { "fixed64", 1, 0, 9007199254740991 },
        { "string", 2 }, { "bytes", 2 },
    }
    for _, scalar in ipairs(scalars) do
        types[scalar[1]] = Type.new(scalar[1], scalar[1], scalar[2], scalar[3], scalar[4])
    end
    local current
    while true do
        local line = input_line()
        if line == "END SCHEMA" then break end
        local args = words(line)
        if args[1] == "ENUM" or args[1] == "MESSAGE" then
            current = Type.new(args[2], args[1] == "ENUM" and "enum" or "message", args[1] == "ENUM" and 0 or 2)
            types[current.name] = current
        elseif args[1] == "VALUE" then
            local number = tonumber(args[3], 10)
            current.members[number] = args[2]
            current.numbers[args[2]] = number
            current.enum_order[#current.enum_order + 1] = number
        elseif args[1] == "FIELD" then
            local field = {
                number = tonumber(args[2], 10), type_name = args[3], name = args[4],
                required = args[5] == "REQUIRED", repeated = args[5] == "REPEATED",
                packed = args[6] == "PACKED", group = args[5] == "ONEOF" and args[6] or nil,
            }
            current.fields[#current.fields + 1] = field
            current.by_number[field.number], current.by_name[field.name] = field, field
        end
    end
    for _, value_type in pairs(types) do
        table.sort(value_type.fields, function(a, b) return a.number < b.number end)
        table.sort(value_type.enum_order)
        for _, field in ipairs(value_type.fields) do field.type = types[field.type_name] end
    end
    return types
end

local Message = {}
Message.__index = Message
function Message.new(value_type)
    return setmetatable({ type = value_type, fields = {}, unknown = {} }, Message)
end
function Message:values(field)
    return self.fields[field.number] or {}
end
function Message:choose(field)
    if not field.group then return end
    for _, other in ipairs(self.type.fields) do
        if other ~= field and other.group == field.group then self.fields[other.number] = nil end
    end
end
function Message:apply(field, values)
    if #values == 0 then return end
    self:choose(field)
    local old = self:values(field)
    if field.repeated then
        for _, value in ipairs(values) do old[#old + 1] = value end
        self.fields[field.number] = old
    elseif field.type.kind == "message" and #old > 0 then old[1]:merge(values[1])
    else self.fields[field.number] = values end
end
function Message:merge(source)
    for _, field in ipairs(self.type.fields) do self:apply(field, source:values(field)) end
    for _, unknown in ipairs(source.unknown) do self.unknown[#self.unknown + 1] = unknown end
end

local function quote(value, json)
    local result = { '"' }
    local escapes = { [34] = '\\"', [92] = '\\\\', [10] = '\\n', [9] = '\\t' }
    for i = 1, #value do
        local byte = value:byte(i)
        if escapes[byte] then result[#result + 1] = escapes[byte]
        elseif byte >= 32 and byte <= 126 then result[#result + 1] = value:sub(i, i)
        else result[#result + 1] = (json and "\\u00" or "\\x") .. string.format("%02x", byte) end
    end
    result[#result + 1] = '"'
    return table.concat(result)
end
local function base64(value)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = {}
    for i = 1, #value, 3 do
        local number = value:byte(i) * 65536 + (value:byte(i + 1) or 0) * 256 + (value:byte(i + 2) or 0)
        local indices = { number // 262144, number // 4096 % 64, number // 64 % 64, number % 64 }
        for j = 1, 4 do
            if j > 2 and i + j - 2 > #value then result[#result + 1] = "="
            else result[#result + 1] = alphabet:sub(indices[j] + 1, indices[j] + 1) end
        end
    end
    return table.concat(result)
end
local value_text, message_text
local function sequence_text(value_type, values, json)
    local parts = {}
    for i, value in ipairs(values) do parts[i] = value_text(value_type, value, json) end
    return "[" .. table.concat(parts, json and "," or ", ") .. "]"
end
value_text = function(value_type, value, json)
    local kind = value_type.kind
    if kind == "message" then return message_text(value, json) end
    if kind == "bool" then return value and "true" or "false" end
    if kind == "enum" then return json and quote(value_type.members[value]) or value_type.members[value] end
    if kind == "string" then return quote(value, json) end
    if kind == "bytes" then return json and quote(base64(value)) or "<" .. hex_text(value) .. ">" end
    if json and (kind == "uint64" or kind == "sint64" or kind == "fixed64") then return quote(tostring(value)) end
    return tostring(value)
end
message_text = function(message, json)
    local parts = {}
    for _, field in ipairs(message.type.fields) do
        local values = message:values(field)
        if #values > 0 then
            local key = field.name
            if json then key = quote((key:gsub("_([a-z0-9])", string.upper))) end
            local value = field.repeated and sequence_text(field.type, values, json) or value_text(field.type, values[1], json)
            parts[#parts + 1] = key .. (json and ":" or ": ") .. value
        end
    end
    return "{" .. table.concat(parts, json and "," or ", ") .. "}"
end
local function raw_text(unknown)
    if unknown.wire == 0 then return tostring(unknown.value) end
    return "<" .. hex_text(unknown.value) .. ">"
end
local function text_contents(message, depth, lines)
    local indent = string.rep(" ", depth * 2)
    for _, field in ipairs(message.type.fields) do
        for _, value in ipairs(message:values(field)) do
            if field.type.kind == "message" then
                lines[#lines + 1] = indent .. field.name .. " {"
                text_contents(value, depth + 1, lines)
                lines[#lines + 1] = indent .. "}"
            else lines[#lines + 1] = indent .. field.name .. ": " .. value_text(field.type, value) end
        end
    end
    for _, unknown in ipairs(message.unknown) do
        lines[#lines + 1] = indent .. unknown.number .. ": " .. wire_names[unknown.wire] .. " " .. raw_text(unknown)
    end
end
local function text_message(message)
    local lines = { message.type.name .. " {" }
    text_contents(message, 1, lines)
    lines[#lines + 1] = "}"
    return lines
end

local encode
local function encode_value(value_type, value)
    if value_type.wire == 2 then
        local payload = value_type.kind == "message" and encode(value) or value
        return varint(#payload) .. payload
    end
    if value_type.wire == 0 then
        if value_type.kind == "sint32" or value_type.kind == "sint64" then value = zigzag(value)
        elseif value_type.kind == "bool" then value = value and 1 or 0 end
        return varint(value)
    end
    if value < 0 then value = value + 4294967296 end
    local result = {}
    for i = 1, value_type.wire == 1 and 8 or 4 do
        result[i] = string.char(value % 256)
        value = value // 256
    end
    return table.concat(result)
end
local function encode_field(field, values)
    if #values == 0 then return "" end
    local parts = {}
    for i, value in ipairs(values) do
        local bytes = encode_value(field.type, value)
        parts[i] = field.packed and bytes or varint(field.number * 8 + field.type.wire) .. bytes
    end
    local bytes = table.concat(parts)
    if field.packed then return varint(field.number * 8 + 2) .. varint(#bytes) .. bytes end
    return bytes
end
encode = function(message)
    local parts = {}
    for _, field in ipairs(message.type.fields) do parts[#parts + 1] = encode_field(field, message:values(field)) end
    for _, unknown in ipairs(message.unknown) do
        local bytes = unknown.value
        if unknown.wire == 0 then bytes = varint(bytes)
        elseif unknown.wire == 2 then bytes = varint(#bytes) .. bytes end
        parts[#parts + 1] = varint(unknown.number * 8 + unknown.wire) .. bytes
    end
    return table.concat(parts)
end

local Reader = {}
Reader.__index = Reader
function Reader.new(data, position, finish)
    return setmetatable({ data = data, position = position, finish = finish }, Reader)
end
function Reader:varint()
    local start, value = self.position, 0
    for i = 0, 7 do
        if self.position >= self.finish then fail("truncated varint at byte " .. start) end
        local byte = self.data:byte(self.position + 1)
        self.position = self.position + 1
        value = value | ((byte & 127) << (7 * i))
        if byte < 128 then
            if value > 9007199254740991 then fail("varint too large at byte " .. start) end
            return value
        end
    end
    fail("varint too long at byte " .. start)
end
function Reader:read(wire)
    local start = self.position
    if wire == 0 then return { value = self:varint(), position = start, payload = start } end
    local length
    if wire == 2 then length = self:varint() else length = wire == 1 and 8 or 4 end
    local payload = self.position
    if length > self.finish - payload then
        fail((wire == 2 and "length past end" or "truncated " .. wire_names[wire]) .. " at byte " .. start)
    end
    self.position = payload + length
    return { value = self.data:sub(payload + 1, payload + length), position = start, payload = payload }
end

local function token_shape(token)
    if token.kind == "{" then return "message" end
    if token.kind == "[" then return "list" end
    if token.kind == "name" then
        return (token.value == "true" or token.value == "false") and "boolean" or "name"
    end
    if token.kind == "integer" or token.kind == "string" or token.kind == "bytes" then return token.kind end
    return ""
end
local function literal_error(reason, column)
    fail(reason .. " at column " .. column)
end
local Literal = {}
Literal.__index = Literal
function Literal.new(source)
    local tokens, i = {}, 1
    while i <= #source do
        local character, column = source:sub(i, i), i
        if character == " " then i = i + 1
        elseif ("{}[]:,"):find(character, 1, true) then
            tokens[#tokens + 1] = { kind = character, column = column }
            i = i + 1
        elseif character == '"' then
            i = i + 1
            local bytes = {}
            while i <= #source and source:sub(i, i) ~= '"' do
                character = source:sub(i, i)
                i = i + 1
                if character == "\\" then
                    local escape = source:sub(i, i)
                    i = i + 1
                    if escape == '"' or escape == "\\" then character = escape
                    elseif escape == "n" then character = "\n"
                    elseif escape == "t" then character = "\t"
                    elseif escape == "x" and source:sub(i, i + 1):match("^[0-7][0-9a-f]$") then
                        character = string.char(tonumber(source:sub(i, i + 1), 16))
                        i = i + 2
                    else literal_error("syntax error", column) end
                end
                bytes[#bytes + 1] = character
            end
            if i > #source then literal_error("syntax error", column) end
            i = i + 1
            tokens[#tokens + 1] = { kind = "string", value = table.concat(bytes), column = column }
        elseif character == "<" then
            local finish = source:find(">", i + 1, true)
            if not finish then literal_error("syntax error", column) end
            local hex = source:sub(i + 1, finish - 1)
            if not valid_hex(hex) then literal_error("syntax error", column) end
            tokens[#tokens + 1] = { kind = "bytes", value = hex_bytes(hex), column = column }
            i = finish + 1
        elseif character == "-" or digit(character) then
            local start = i
            if character == "-" then i = i + 1 end
            local digits = i
            while i <= #source and digit(source:sub(i, i)) do i = i + 1 end
            if i == digits then literal_error("syntax error", column) end
            tokens[#tokens + 1] = { kind = "integer", value = tonumber(source:sub(start, i - 1), 10), column = column }
        elseif character == "_" or letter(character) then
            local start = i
            i = i + 1
            while i <= #source and source:sub(i, i):match("^[A-Za-z0-9_]$") do i = i + 1 end
            tokens[#tokens + 1] = { kind = "name", value = source:sub(start, i - 1), column = column }
        else literal_error("syntax error", column) end
    end
    tokens[#tokens + 1] = { kind = "end", column = #source + 1 }
    return setmetatable({ tokens = tokens, position = 1 }, Literal)
end
function Literal:expect(kind)
    local token = self.tokens[self.position]
    if token.kind ~= kind then literal_error("syntax error", token.column) end
    self.position = self.position + 1
    return token
end
function Literal:finish()
    self:expect("end")
end
function Literal:message(value_type)
    self:expect("{")
    local message, seen, groups = Message.new(value_type), {}, {}
    if self.tokens[self.position].kind ~= "}" then
        while true do
            local token = self.tokens[self.position]
            if token.kind ~= "name" then literal_error("syntax error", token.column) end
            local field = value_type.by_name[token.value]
            if not field then literal_error("unknown field", token.column) end
            if seen[field.number] then literal_error("duplicate field", token.column) end
            if field.group and groups[field.group] then literal_error("oneof conflict", token.column) end
            seen[field.number] = true
            if field.group then groups[field.group] = true end
            self.position = self.position + 1
            self:expect(":")
            message.fields[field.number] = self:field_value(field)
            if self.tokens[self.position].kind ~= "," then break end
            self.position = self.position + 1
        end
    end
    local closing = self:expect("}")
    for _, field in ipairs(value_type.fields) do
        if field.required and not seen[field.number] then literal_error("missing required field " .. field.name, closing.column) end
    end
    return message
end
function Literal:field_value(field)
    if not field.repeated then return { self:element(field.type) } end
    local token = self.tokens[self.position]
    if token_shape(token) == "" then literal_error("syntax error", token.column) end
    if token_shape(token) ~= "list" then literal_error("type mismatch", token.column) end
    self.position = self.position + 1
    local values = {}
    if self.tokens[self.position].kind ~= "]" then
        values[#values + 1] = self:element(field.type)
        while self.tokens[self.position].kind == "," do
            self.position = self.position + 1
            values[#values + 1] = self:element(field.type)
        end
    end
    self:expect("]")
    return values
end
function Literal:element(value_type)
    local token, kind = self.tokens[self.position], value_type.kind
    local shape = "integer"
    if kind == "bool" then shape = "boolean"
    elseif kind == "string" or kind == "bytes" then shape = kind
    elseif kind == "enum" then shape = "name"
    elseif kind == "message" then shape = "message" end
    if token_shape(token) == "" then literal_error("syntax error", token.column) end
    if token_shape(token) ~= shape then literal_error("type mismatch", token.column) end
    if shape == "message" then return self:message(value_type) end
    self.position = self.position + 1
    if shape == "integer" and not value_type:in_range(token.value) then literal_error("out of range", token.column) end
    if shape == "boolean" then return token.value == "true" end
    if shape == "name" then
        local number = value_type.numbers[token.value]
        if number == nil then literal_error("unknown enum value", token.column) end
        return number
    end
    return token.value
end

local function convert(value_type, raw)
    local kind = value_type.kind
    if kind == "string" or kind == "bytes" then
        if kind == "string" then
            for i = 1, #raw.value do
                if raw.value:byte(i) >= 128 then fail("invalid string at byte " .. (raw.payload + i - 1)) end
            end
        end
        return raw.value
    end
    local number = raw.value
    if value_type.wire ~= 0 then
        if kind == "fixed64" and (raw.value:byte(8) ~= 0 or raw.value:byte(7) >= 32) then
            fail("value out of range at byte " .. raw.position)
        end
        number = 0
        for i = #raw.value, 1, -1 do number = number * 256 + raw.value:byte(i) end
    end
    if kind == "sint32" or kind == "sint64" then
        if number % 2 == 0 then number = number // 2 else number = -(number // 2) - 1 end
    elseif kind == "sfixed32" and number >= 2147483648 then number = number - 4294967296 end
    if not value_type:in_range(number) or (kind == "bool" and number > 1) then
        fail("value out of range at byte " .. raw.position)
    end
    if kind == "enum" and not value_type.members[number] then fail("unknown enum number at byte " .. raw.position) end
    if kind == "bool" then return number == 1 end
    return number
end
local function read_message(value_type, reader, lines, depth)
    local message = Message.new(value_type)
    while reader.position < reader.finish do
        local offset = reader.position
        local tag = reader:varint()
        local number, wire = tag // 8, tag % 8
        if number == 0 then fail("invalid field number at byte " .. offset) end
        if not wire_names[wire] then fail("invalid wire type at byte " .. offset) end
        local field = value_type.by_number[number]
        local packed = field and field.repeated and field.type.wire ~= 2 and wire == 2
        if field and wire ~= field.type.wire and not packed then fail("wire type mismatch at byte " .. offset) end
        local raw = reader:read(wire)
        local header = string.rep(" ", 2 * depth) .. offset .. " " .. number .. " " ..
            (field and field.name or "?") .. " " .. wire_names[wire]
        if wire == 2 then header = header .. " " .. #raw.value end
        if not field then
            local unknown = { number = number, wire = wire, value = raw.value }
            if lines then lines[#lines + 1] = header .. " " .. raw_text(unknown)
            else message.unknown[#message.unknown + 1] = unknown end
        else
            local values = {}
            if field.type.kind == "message" then
                if lines then lines[#lines + 1] = header end
                local child = Reader.new(reader.data, raw.payload, raw.payload + #raw.value)
                values[1] = read_message(field.type, child, lines, depth + 1)
            elseif packed then
                local elements = Reader.new(reader.data, raw.payload, raw.payload + #raw.value)
                header = header .. " packed"
                while elements.position < elements.finish do
                    local value = convert(field.type, elements:read(field.type.wire))
                    values[#values + 1] = value
                    if lines then header = header .. " " .. value_text(field.type, value) end
                end
                if lines then lines[#lines + 1] = header end
            else
                values[1] = convert(field.type, raw)
                if lines then lines[#lines + 1] = header .. " " .. value_text(field.type, values[1]) end
            end
            if not lines then message:apply(field, values) end
        end
    end
    return message
end
local function required(message, prefix)
    for _, field in ipairs(message.type.fields) do
        local values, path = message:values(field), prefix .. field.name
        if field.required and #values == 0 then fail("missing required field " .. path) end
        if field.type.kind == "message" then
            for i, child in ipairs(values) do
                required(child, path .. (field.repeated and "[" .. (i - 1) .. "]" or "") .. ".")
            end
        end
    end
end
local function decode(value_type, bytes, explanation)
    local message = read_message(value_type, Reader.new(bytes, 0, #bytes), explanation, 0)
    if not explanation then required(message, "")
    elseif #bytes == 0 then explanation[#explanation + 1] = "(empty)" end
    return message
end
local function decode_side(value_type, bytes, side)
    local ok, result = pcall(decode, value_type, bytes)
    if ok then return result end
    if getmetatable(result) == CodecError then fail(result.message .. " in " .. side) end
    error(result, 0)
end
local function parse_path(value_type, source)
    local parts, result = {}, {}
    for part in (source .. "."):gmatch("(.-)%.") do parts[#parts + 1] = part end
    for i, part in ipairs(parts) do
        local name, digits = part:match("^([a-z][a-z0-9_]*)%[([0-9]+)%]$")
        if not name then name = part end
        if digits and #digits > 6 then fail("invalid path") end
        local field = value_type.by_name[name]
        local index = digits and tonumber(digits, 10) or nil
        if not field or (index ~= nil and not field.repeated) then fail("invalid path") end
        if i < #parts and (field.type.kind ~= "message" or (field.repeated and index == nil)) then fail("invalid path") end
        result[#result + 1] = { field = field, index = index, whole = field.repeated and index == nil }
        value_type = field.type
    end
    return result
end
local function get_path(message, path)
    local current = message
    for step, segment in ipairs(path) do
        local values = current and current:values(segment.field) or {}
        local index = (segment.index or 0) + 1
        if step == #path then
            if segment.whole then return sequence_text(segment.field.type, values) end
            if index <= #values then return value_text(segment.field.type, values[index]) end
            return "(none)"
        end
        current = values[index]
    end
end
local function edit_path(message, path, replacement)
    local current = message
    for i = 1, #path - 1 do
        local segment = path[i]
        local values, index = current:values(segment.field), (segment.index or 0) + 1
        if index > #values then
            if replacement == nil then return end
            if segment.index ~= nil then fail("index out of range") end
            current:choose(segment.field)
            values = { Message.new(segment.field.type) }
            current.fields[segment.field.number] = values
        end
        current = values[index]
    end
    local last = path[#path]
    if last.index ~= nil then
        local values, index = current:values(last.field), last.index + 1
        if index > #values then
            if replacement ~= nil then fail("index out of range") end
        else
            if replacement == nil then table.remove(values, index) else values[index] = replacement[1] end
            current.fields[last.field.number] = values
        end
    else
        if replacement ~= nil then current:choose(last.field) end
        current.fields[last.field.number] = replacement
    end
end
local function differences(a, b, prefix, lines)
    for _, field in ipairs(a.type.fields) do
        local x, y = a:values(field), b:values(field)
        for i = 1, math.max(#x, #y) do
            local path = prefix .. field.name .. (field.repeated and "[" .. (i - 1) .. "]" or "")
            if i <= #x and i <= #y and field.type.kind == "message" then
                differences(x[i], y[i], path .. ".", lines)
            elseif i > #x or i > #y or x[i] ~= y[i] then
                local old = i <= #x and value_text(field.type, x[i]) or "(none)"
                local new = i <= #y and value_text(field.type, y[i]) or "(none)"
                lines[#lines + 1] = path .. ": " .. old .. " -> " .. new
            end
        end
    end
end
local function schema_fields(value_type, chain, depth, lines)
    for _, field in ipairs(value_type.fields) do
        local kind = ""
        if field.required then kind = "required "
        elseif field.packed then kind = "repeated packed "
        elseif field.repeated then kind = "repeated "
        elseif field.group then kind = "oneof " .. field.group .. " " end
        local line = string.rep(" ", 2 * depth) .. field.number .. " " .. field.name .. ": " .. kind .. field.type.name
        if field.type.kind == "enum" then
            local members = {}
            for _, number in ipairs(field.type.enum_order) do members[#members + 1] = field.type.members[number] .. "=" .. number end
            line = line .. " (" .. table.concat(members, ", ") .. ")"
        end
        local recursive = field.type.kind == "message" and chain[field.type]
        lines[#lines + 1] = line .. (recursive and " (recursive)" or "")
        if field.type.kind == "message" and not recursive then
            chain[field.type] = true
            schema_fields(field.type, chain, depth + 1, lines)
            chain[field.type] = nil
        end
    end
end
local function parse_hex(source)
    if source == "-" then return "" end
    if source == "" or not valid_hex(source) then fail("invalid hex") end
    return hex_bytes(source)
end
local arities = {
    VARINT = 2, ZIGZAG = 2, SCHEMA = 2, ENCODE = 3, SIZE = 3, DECODE = 3, LITERAL = 3,
    JSON = 3, CANON = 3, EXPLAIN = 3, GET = 4, CLEAR = 4, MERGE = 4, DIFF = 4, PATCH = 5,
}
local function execute(types, source)
    local args = words(source)
    local command = args[1]
    local minimum = arities[command]
    if not minimum then fail("unknown command") end
    local flexible = command == "ENCODE" or command == "SIZE" or command == "PATCH"
    if #args < minimum or (not flexible and #args ~= minimum) then fail("wrong number of arguments") end
    if command == "VARINT" or command == "ZIGZAG" then
        local digits = args[2]:gsub("^%-", "")
        if #digits > 18 or not digits:match("^[0-9]+$") then fail("invalid number") end
        local number = tonumber(args[2], 10)
        local valid
        if command == "VARINT" then valid = number >= 0 and number <= 9007199254740991
        else valid = number >= -4503599627370496 and number <= 4503599627370495 end
        if not valid then fail("invalid number") end
        local value = command == "ZIGZAG" and zigzag(number) or number
        return { (command == "ZIGZAG" and value .. " " or "") .. hex_text(varint(value), true) }
    end
    local value_type = types[args[2]]
    if not value_type or value_type.kind ~= "message" then fail("unknown message type") end
    local data, second, path = "", "", nil
    if command ~= "SCHEMA" and command ~= "ENCODE" and command ~= "SIZE" then data = parse_hex(args[3]) end
    if command == "MERGE" or command == "DIFF" then second = parse_hex(args[4]) end
    if command == "GET" or command == "PATCH" or command == "CLEAR" then path = parse_path(value_type, args[4]) end
    if command == "SCHEMA" then
        local lines = { value_type.name }
        schema_fields(value_type, { [value_type] = true }, 1, lines)
        return lines
    end
    if command == "ENCODE" or command == "SIZE" then
        local literal = Literal.new(rest(source, 2))
        local message = literal:message(value_type)
        literal:finish()
        local encoded = encode(message)
        if command == "ENCODE" then return { hex_text(encoded, true) } end
        local line = tostring(#encoded)
        for _, field in ipairs(value_type.fields) do
            local values = message:values(field)
            if #values > 0 then line = line .. " " .. field.name .. "=" .. #encode_field(field, values) end
        end
        return { line }
    end
    if command == "EXPLAIN" then
        local lines = {}
        decode(value_type, data, lines)
        return lines
    end
    if command == "MERGE" then return text_message(decode(value_type, data .. second)) end
    if command == "DIFF" then
        local a = decode_side(value_type, data, "first")
        local b = decode_side(value_type, second, "second")
        local lines = {}
        differences(a, b, "", lines)
        if #lines == 0 then lines[1] = "SAME" end
        return lines
    end
    local message = decode(value_type, data)
    if command == "DECODE" then return text_message(message) end
    if command == "LITERAL" or command == "JSON" then return { message_text(message, command == "JSON") } end
    if command == "GET" then return { get_path(message, path) } end
    if command == "PATCH" then
        local literal, last = Literal.new(rest(source, 4)), path[#path]
        local replacement
        if last.whole then replacement = literal:field_value(last.field) else replacement = { literal:element(last.field.type) } end
        literal:finish()
        edit_path(message, path, replacement)
        required(message, "")
    elseif command == "CLEAR" then
        edit_path(message, path, nil)
        required(message, "")
    end
    return { hex_text(encode(message), true) }
end

local types = load_schema()
local count = tonumber(input_line(), 10)
for _ = 1, count do
    local ok, result = pcall(execute, types, input_line())
    if not ok then
        if getmetatable(result) ~= CodecError then error(result, 0) end
        result = { "ERROR " .. result.message }
    end
    for _, line in ipairs(result) do io.write(line, "\n") end
end
