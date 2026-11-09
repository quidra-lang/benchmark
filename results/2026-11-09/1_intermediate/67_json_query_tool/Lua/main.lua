local function fail(reason)
    error({ reason = reason }, 0)
end
local function json_fail(position, reason)
    error({ position = position, reason = reason }, 0)
end
local function node(kind, scalar)
    return { kind = kind, scalar = scalar, keys = {}, items = {} }
end
local function find(v, key)
    for i, k in ipairs(v.keys) do
        if k == key then
            return i
        end
    end
end
local function copy(v)
    local result = node(v.kind, v.scalar)
    for i, k in ipairs(v.keys) do
        result.keys[i] = k
    end
    for i, item in ipairs(v.items) do
        result.items[i] = copy(item)
    end
    return result
end
local function size(v)
    local count, depth = 1, 1
    for _, item in ipairs(v.items) do
        local n, d = size(item)
        count, depth = count + n, math.max(depth, d + 1)
    end
    return count, depth
end
local function identifier(s)
    return s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end
local function integer_notation(s)
    if s == "0" then
        return true
    end
    local digits = s:gsub("^-", "")
    return #digits >= 1 and #digits <= 9 and digits:match("^[1-9][0-9]*$") ~= nil
end
local function quote(s, mark)
    local out = { mark }
    local escapes = { ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == mark then
            out[#out + 1] = "\\" .. c
        elseif escapes[c] then
            out[#out + 1] = escapes[c]
        elseif c:byte() < 32 or c:byte() == 127 then
            out[#out + 1] = string.format("\\u%04x", c:byte())
        else
            out[#out + 1] = c
        end
    end
    out[#out + 1] = mark
    return table.concat(out)
end
local function compact(v)
    if v.kind == "null" then
        return "null"
    end
    if v.kind == "number" then
        return string.format("%.0f", v.scalar)
    end
    if v.kind == "boolean" then
        return v.scalar and "true" or "false"
    end
    if v.kind == "string" then
        return quote(v.scalar, '"')
    end
    local parts = {}
    for i, item in ipairs(v.items) do
        parts[i] = compact(item)
        if v.kind == "object" then
            parts[i] = quote(v.keys[i], '"') .. ":" .. parts[i]
        end
    end
    return (v.kind == "array" and "[" or "{") .. table.concat(parts, ",") .. (v.kind == "array" and "]" or "}")
end
local function pretty(v, indent)
    if #v.items == 0 then
        return compact(v)
    end
    local inner, parts = indent .. "  ", {}
    for i, item in ipairs(v.items) do
        local label = v.kind == "object" and quote(v.keys[i], '"') .. ": " or ""
        parts[i] = inner .. label .. pretty(item, inner)
    end
    return (v.kind == "array" and "[" or "{") .. "\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. (v.kind == "array" and "]" or "}")
end
local function equal(a, b)
    if a.kind ~= b.kind then
        return false
    end
    if a.kind ~= "array" and a.kind ~= "object" then
        return a.scalar == b.scalar
    end
    if #a.items ~= #b.items then
        return false
    end
    for i, item in ipairs(a.items) do
        local j = i
        if a.kind == "object" then
            j = find(b, a.keys[i])
        end
        if not j or not equal(item, b.items[j]) then
            return false
        end
    end
    return true
end
local Reader = {}
Reader.__index = Reader
function Reader.new(text)
    return setmetatable({ text = text, pos = 1 }, Reader)
end
function Reader:peek()
    return self.text:sub(self.pos, self.pos)
end
function Reader:skip()
    while self:peek() == " " or self:peek() == "\n" do
        self.pos = self.pos + 1
    end
end
function Reader:require(c, reason)
    if self.pos > #self.text then
        json_fail(self.pos, "unexpected end of input")
    end
    if self:peek() ~= c then
        json_fail(self.pos, reason)
    end
end
function Reader:string(mark)
    self.pos = self.pos + 1
    local out = {}
    local escapes = { [mark] = mark, ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
    while true do
        local c = self:peek()
        if c == "" or c == "\n" then
            json_fail(self.pos, "unterminated string")
        end
        if c == mark then
            self.pos = self.pos + 1
            return table.concat(out)
        end
        if c ~= "\\" then
            out[#out + 1] = c
            self.pos = self.pos + 1
        else
            local start = self.pos
            self.pos = self.pos + 1
            local escape = self:peek()
            if escape == "" or escape == "\n" then
                json_fail(self.pos, "unterminated string")
            end
            if escape == "u" then
                local digits = self.text:sub(start + 2, start + 5)
                if #digits ~= 4 or not digits:match("^%x%x%x%x$") then
                    json_fail(start, "bad unicode escape")
                end
                local n = tonumber(digits, 16)
                if n > 127 then
                    json_fail(start, "non-ascii escape")
                end
                out[#out + 1], self.pos = string.char(n), start + 6
            elseif escapes[escape] then
                out[#out + 1] = escapes[escape]
                self.pos = self.pos + 1
            else
                json_fail(start, "invalid escape '\\" .. escape .. "'")
            end
        end
    end
end
function Reader:container_end(close, reason)
    self:skip()
    if self:peek() == close then
        self.pos = self.pos + 1
        return true
    end
    self:require(",", reason)
    self.pos = self.pos + 1
    self:skip()
    if self:peek() == close then
        json_fail(self.pos, "trailing comma")
    end
    return false
end
function Reader:value()
    self:skip()
    local c = self:peek()
    if c == "" then
        json_fail(self.pos, "unexpected end of input")
    end
    if c == '"' then
        return node("string", self:string('"'))
    end
    if c == "{" or c == "[" then
        local v = node(c == "{" and "object" or "array")
        local close, reason = c == "{" and "}" or "]", c == "{" and "expected ',' or '}'" or "expected ',' or ']'"
        self.pos = self.pos + 1
        self:skip()
        if self:peek() == close then
            self.pos = self.pos + 1
            return v
        end
        while true do
            if v.kind == "object" then
                self:skip()
                self:require('"', "expected key")
                local start = self.pos
                local key = self:string('"')
                if find(v, key) then
                    json_fail(start, "duplicate key " .. quote(key, '"'))
                end
                self:skip()
                self:require(":", "expected ':'")
                self.pos = self.pos + 1
                v.keys[#v.keys + 1] = key
            end
            v.items[#v.items + 1] = self:value()
            if self:container_end(close, reason) then
                return v
            end
        end
    end
    if c == "-" or c:match("^[0-9]$") then
        local start, negative = self.pos, c == "-"
        if negative then
            self.pos = self.pos + 1
        end
        local first = self.pos
        while self:peek():match("^[0-9]$") do
            self.pos = self.pos + 1
        end
        local digits = self.text:sub(first, self.pos - 1)
        if digits == "" then
            json_fail(start, "invalid number")
        end
        if #digits >= 2 and digits:sub(1, 1) == "0" then
            json_fail(first, "leading zero")
        end
        if self:peek() == "." then
            json_fail(self.pos, "fraction not allowed")
        end
        if self:peek() == "e" or self:peek() == "E" then
            json_fail(self.pos, "exponent not allowed")
        end
        if #digits >= 10 then
            json_fail(start, "number out of range")
        end
        return node("number", negative and -tonumber(digits) or tonumber(digits))
    end
    if c:match("^[A-Za-z]$") then
        local start = self.pos
        while self:peek():match("^[A-Za-z]$") do
            self.pos = self.pos + 1
        end
        local word = self.text:sub(start, self.pos - 1)
        if word == "null" then
            return node("null")
        end
        if word == "true" or word == "false" then
            return node("boolean", word == "true")
        end
        json_fail(start, "invalid literal '" .. word .. "'")
    end
    json_fail(self.pos, "unexpected character '" .. c .. "'")
end
local function parse_json(text)
    local reader = Reader.new(text)
    local value = reader:value()
    reader:skip()
    if reader.pos <= #text then
        json_fail(reader.pos, "trailing characters")
    end
    return value
end
local function parse_path(text, field)
    local p = Reader.new(text)
    local reason = field and "bad field" or "bad path"
    local function bad()
        fail(reason)
    end
    local function name()
        local s = p.text:match("^([A-Za-z_][A-Za-z0-9_]*)", p.pos)
        if not s then
            bad()
        end
        p.pos = p.pos + #s
        return s
    end
    local function selection()
        if p:peek() == "'" then
            local ok, key = pcall(Reader.string, p, "'")
            if not ok or p:peek() ~= "]" then
                bad()
            end
            p.pos = p.pos + 1
            return { kind = "key", key = key }
        end
        local close = p.text:find("]", p.pos, true)
        if not close then
            bad()
        end
        local s = p.text:sub(p.pos, close - 1)
        p.pos = close + 1
        if s == "*" then
            return { kind = "all" }
        end
        if integer_notation(s) then
            return { kind = "index", index = tonumber(s) }
        end
        local colon = s:find(":", 1, true)
        if not colon then
            bad()
        end
        local a, b = s:sub(1, colon - 1), s:sub(colon + 1)
        if a ~= "" and not integer_notation(a) or b ~= "" and not integer_notation(b) then
            bad()
        end
        return { kind = "slice", start = a ~= "" and tonumber(a) or nil, stop = b ~= "" and tonumber(b) or nil }
    end
    if p:peek() ~= (field and "@" or "$") then
        bad()
    end
    p.pos = p.pos + 1
    local out = {}
    while p.pos <= #text do
        local s, descendant
        if p:peek() == "[" then
            p.pos = p.pos + 1
            s = selection()
        else
            if p:peek() ~= "." then
                bad()
            end
            p.pos = p.pos + 1
            descendant = not field and p:peek() == "."
            if descendant then
                p.pos = p.pos + 1
            end
            if not field and p:peek() == "*" then
                p.pos = p.pos + 1
                s = { kind = "all" }
            elseif descendant and p:peek() == "[" then
                p.pos = p.pos + 1
                s = selection()
            else
                s = { kind = "key", key = name() }
            end
        end
        s.descendant = descendant or false
        if field and s.kind ~= "key" and s.kind ~= "index" then
            bad()
        end
        out[#out + 1] = s
    end
    return out
end
local function parse_key(text)
    if identifier(text) then
        return text
    end
    if text:sub(1, 1) == "'" then
        local p = Reader.new(text)
        local ok, key = pcall(Reader.string, p, "'")
        if ok and p.pos == #text + 1 then
            return key
        end
    end
    fail("bad key")
end
local function child(match, position)
    local steps = {}
    for i, step in ipairs(match.steps) do
        steps[i] = step
    end
    steps[#steps + 1] = { position = position, key = match.node.kind == "object" and match.node.keys[position] or nil }
    return { node = match.node.items[position], steps = steps }
end
local function location(match)
    local out = { "$" }
    for _, step in ipairs(match.steps) do
        if step.key == nil then
            out[#out + 1] = "[" .. (step.position - 1) .. "]"
        elseif identifier(step.key) then
            out[#out + 1] = "." .. step.key
        else
            out[#out + 1] = "[" .. quote(step.key, "'") .. "]"
        end
    end
    return table.concat(out)
end
local function position(v, s)
    if s.kind == "key" then
        if v.kind == "object" then
            return find(v, s.key)
        end
        return nil
    end
    if v.kind ~= "array" then
        return nil
    end
    local i = s.index
    if i < 0 then
        i = i + #v.items
    end
    if i >= 0 and i < #v.items then
        return i + 1
    end
end
local function select_value(match, s, out)
    local v = match.node
    if s.kind == "all" then
        for i in ipairs(v.items) do
            out[#out + 1] = child(match, i)
        end
    elseif s.kind == "slice" then
        if v.kind ~= "array" then
            return
        end
        local function clamp(i)
            if i < 0 then
                i = i + #v.items
            end
            return math.max(0, math.min(#v.items, i))
        end
        local a = s.start == nil and 0 or clamp(s.start)
        local b = s.stop == nil and #v.items or clamp(s.stop)
        for i = a + 1, b do
            out[#out + 1] = child(match, i)
        end
    else
        local i = position(v, s)
        if i then
            out[#out + 1] = child(match, i)
        end
    end
end
local function preorder(match, visit)
    visit(match)
    for i in ipairs(match.node.items) do
        preorder(child(match, i), visit)
    end
end
local function apply_segment(matches, s)
    local out = {}
    for _, match in ipairs(matches) do
        if s.descendant then
            preorder(match, function(m)
                select_value(m, s, out)
            end)
        else
            select_value(match, s, out)
        end
    end
    return out
end
local function evaluate(root, path)
    local matches = { { node = root, steps = {} } }
    for _, s in ipairs(path) do
        matches = apply_segment(matches, s)
    end
    return matches
end
local function field_value(v, path)
    for _, s in ipairs(path) do
        local i = position(v, s)
        if not i then
            return nil
        end
        v = v.items[i]
    end
    return v
end
local function compare(a, b)
    local function rank(v)
        if not v then
            return 3
        end
        return ({ null = 0, number = 1, string = 2 })[v.kind] or 3
    end
    local x, y = rank(a), rank(b)
    if x ~= y then
        return x < y and -1 or 1
    end
    if x == 1 or x == 2 then
        if a.scalar < b.scalar then
            return -1
        elseif a.scalar > b.scalar then
            return 1
        end
    end
    return 0
end
local function holds(operator, value, reference)
    if operator == "EXISTS" then
        return value ~= nil
    end
    if operator == "==" or operator == "!=" then
        local same = value ~= nil and equal(value, reference)
        return operator == "==" and same or operator == "!=" and not same
    end
    if not value or value.kind ~= reference.kind or value.kind ~= "number" and value.kind ~= "string" then
        return false
    end
    local c = compare(value, reference)
    if operator == "<" then
        return c < 0
    elseif operator == "<=" then
        return c <= 0
    elseif operator == ">" then
        return c > 0
    else
        return c >= 0
    end
end
local function order(a, b)
    for i = 1, math.min(#a.steps, #b.steps) do
        if a.steps[i].position ~= b.steps[i].position then
            return a.steps[i].position < b.steps[i].position and -1 or 1
        end
    end
    if #a.steps == #b.steps then
        return 0
    end
    return #a.steps < #b.steps and -1 or 1
end
local function targets(matches)
    local sorted = {}
    for i, m in ipairs(matches) do
        sorted[i] = m
    end
    table.sort(sorted, function(a, b)
        return order(a, b) > 0
    end)
    local out = {}
    for _, m in ipairs(sorted) do
        if #out == 0 or order(out[#out], m) ~= 0 then
            out[#out + 1] = m
        end
    end
    return out
end
local function resolve(root, steps, count)
    for i = 1, count or #steps do
        root = root.items[steps[i].position]
    end
    return root
end
local function merge(target, patch)
    for i, key in ipairs(patch.keys) do
        local j = find(target, key)
        if not j then
            target.keys[#target.keys + 1] = key
            target.items[#target.items + 1] = copy(patch.items[i])
        elseif target.items[j].kind == "object" and patch.items[i].kind == "object" then
            merge(target.items[j], patch.items[i])
        else
            target.items[j] = copy(patch.items[i])
        end
    end
end
local function split(s, separator, limit)
    local out, at = {}, 1
    while not limit or #out + 1 < limit do
        local p = s:find(separator, at, true)
        if not p then
            break
        end
        out[#out + 1] = s:sub(at, p - 1)
        at = p + #separator
    end
    out[#out + 1] = s:sub(at)
    return out
end
local document, history = node("null"), {}
local function commit(value)
    history[#history + 1], document = document, value
end
local function require_kind(matches, kind, message)
    for _, match in ipairs(matches) do
        if match.node.kind ~= kind then
            fail(message .. " at " .. location(match))
        end
    end
end
local function load(body)
    local text = table.concat(body, "\n")
    local ok, result = pcall(parse_json, text)
    if not ok then
        local before = text:sub(1, result.position - 1)
        local _, line = before:gsub("\n", "")
        local last = 0
        for p in before:gmatch("()\n") do
            last = p
        end
        print("PARSE ERROR line " .. (line + 1) .. " col " .. (result.position - last) .. ": " .. result.reason)
        return
    end
    commit(result)
    local count, depth = size(result)
    print("LOADED nodes=" .. count .. " depth=" .. depth)
end
local function execute(line)
    local command, argument = line:match("^([^ ]+) ?(.*)$")
    local has_argument = line:find(" ", 1, true) ~= nil
    local known = { GET = true, COMPACT = true, PRETTY = true, TYPE = true, LENGTH = true, KEYS = true, FLATTEN = true, COUNT = true, SUM = true, MIN = true, MAX = true, AVG = true, FILTER = true, SET = true, DELETE = true, INSERT = true, MERGE = true, SORT = true, RENAME = true, UNDO = true }
    if not known[command] then
        fail("unknown command '" .. command .. "'")
    end
    local args = has_argument and split(argument, " ") or {}
    local function shape(minimum, maximum)
        if #args < minimum or #args > maximum then
            fail("bad arguments")
        end
    end
    if command == "UNDO" then
        shape(0, 0)
        if #history == 0 then
            fail("nothing to undo")
        end
        document = table.remove(history)
        print("UNDO " .. #history)
        return
    end
    if command == "SET" or command == "MERGE" or command == "INSERT" then
        local n = command == "INSERT" and 3 or 2
        args = split(argument, " ", n)
        if not has_argument or #args ~= n then
            fail("bad arguments")
        end
    elseif command == "FILTER" then
        args = split(argument, " ", 4)
        if not has_argument or #args < 3 or args[3] == "EXISTS" and #args == 4 or args[3] ~= "EXISTS" and #args == 3 then
            fail("bad arguments")
        end
    elseif command == "SORT" then
        shape(1, 3)
        if #args == 3 and (args[2] == "DESC" or args[3] ~= "DESC") then
            fail("bad arguments")
        end
    else
        local minimum, maximum = 1, 1
        if command == "COMPACT" or command == "PRETTY" or command == "FLATTEN" then
            minimum = 0
        end
        if command == "RENAME" then
            minimum, maximum = 2, 2
        end
        shape(minimum, maximum)
    end
    local path = parse_path(args[1] or "$", false)
    local field, patch, index, new_key, operator, descending = nil, nil, nil, nil, nil, false
    if command == "FILTER" then
        field = parse_path(args[2], true)
        operator = args[3]
        if operator ~= "==" and operator ~= "!=" and operator ~= "<" and operator ~= "<=" and operator ~= ">" and operator ~= ">=" and operator ~= "EXISTS" then
            fail("bad operator")
        end
        if operator ~= "EXISTS" then
            patch = parse_json(args[4])
        end
    elseif command == "SET" or command == "MERGE" then
        patch = parse_json(args[2])
    elseif command == "INSERT" then
        if not integer_notation(args[2]) then
            fail("bad index")
        end
        index = tonumber(args[2])
        patch = parse_json(args[3])
    elseif command == "SORT" then
        local field_text = "@"
        if #args > 1 then
            descending = args[#args] == "DESC"
            if args[2] ~= "DESC" then
                field_text = args[2]
            end
        end
        field = parse_path(field_text, true)
    elseif command == "RENAME" then
        new_key = parse_key(args[2])
    end
    if command == "DELETE" and #path == 0 then
        fail("cannot delete root")
    end
    if command == "MERGE" and patch.kind ~= "object" then
        fail("merge value is not an object")
    end
    local matches = evaluate(document, path)
    if command == "LENGTH" then
        for _, m in ipairs(matches) do
            if m.node.kind ~= "object" and m.node.kind ~= "array" and m.node.kind ~= "string" then
                fail("no length at " .. location(m))
            end
        end
    end
    if command == "KEYS" or command == "MERGE" then
        require_kind(matches, "object", "not an object")
    end
    if command == "FILTER" or command == "INSERT" or command == "SORT" then
        require_kind(matches, "array", "not an array")
    end
    if command == "INSERT" then
        for _, m in ipairs(matches) do
            if index < -#m.node.items - 1 or index > #m.node.items then
                fail("index out of range at " .. location(m))
            end
        end
    end
    if command == "RENAME" then
        for _, m in ipairs(matches) do
            if #m.steps == 0 or m.steps[#m.steps].key == nil then
                fail("not a member at " .. location(m))
            end
        end
    end
    if command == "COUNT" then
        print("COUNT " .. #matches)
        return
    end
    if command == "SUM" or command == "MIN" or command == "MAX" or command == "AVG" then
        local total, minimum, maximum, count = 0, nil, nil, 0
        for _, m in ipairs(matches) do
            if m.node.kind == "number" then
                local n = m.node.scalar
                total, count = total + n, count + 1
                minimum = minimum == nil and n or math.min(minimum, n)
                maximum = maximum == nil and n or math.max(maximum, n)
            end
        end
        local text = "null"
        if command == "SUM" then
            text = string.format("%.0f", total)
        elseif command == "MIN" and count > 0 then
            text = string.format("%.0f", minimum)
        elseif command == "MAX" and count > 0 then
            text = string.format("%.0f", maximum)
        elseif command == "AVG" and count > 0 then
            local q = (math.abs(total) * 200 + count) // (2 * count)
            text = string.format("%s%d.%02d", total < 0 and q >= 1 and "-" or "", q // 100, q % 100)
        end
        print(command .. " " .. text)
        return
    end
    local modifying = command == "SET" or command == "DELETE" or command == "INSERT" or command == "MERGE" or command == "SORT" or command == "RENAME"
    if modifying then
        if command == "SET" and #path == 0 then
            commit(copy(patch))
            print("SET 1")
            return
        end
        if command == "SET" then
            local prefix = {}
            for i = 1, #path - 1 do
                prefix[i] = path[i]
            end
            local last = path[#path]
            matches = {}
            for _, parent in ipairs(evaluate(document, prefix)) do
                if last.kind == "key" and not last.descendant and parent.node.kind == "object" then
                    local i = find(parent.node, last.key) or #parent.node.items + 1
                    local steps = {}
                    for j, s in ipairs(parent.steps) do
                        steps[j] = s
                    end
                    steps[#steps + 1] = { key = last.key, position = i }
                    matches[#matches + 1] = { steps = steps }
                else
                    for _, m in ipairs(apply_segment({ parent }, last)) do
                        matches[#matches + 1] = m
                    end
                end
            end
        end
        local selected, changed = targets(matches), copy(document)
        for _, target in ipairs(selected) do
            if command == "SET" or command == "DELETE" or command == "RENAME" then
                local parent = resolve(changed, target.steps, #target.steps - 1)
                local i = target.steps[#target.steps].position
                if command == "SET" then
                    if i > #parent.items then
                        parent.keys[i] = target.steps[#target.steps].key
                    end
                    parent.items[i] = copy(patch)
                elseif command == "DELETE" then
                    table.remove(parent.items, i)
                    if parent.kind == "object" then
                        table.remove(parent.keys, i)
                    end
                else
                    if parent.keys[i] ~= new_key and find(parent, new_key) then
                        fail("key exists at " .. location(target))
                    end
                    parent.keys[i] = new_key
                end
            else
                local v = resolve(changed, target.steps)
                if command == "INSERT" then
                    local j = index >= 0 and index or #v.items + 1 + index
                    table.insert(v.items, j + 1, copy(patch))
                elseif command == "MERGE" then
                    merge(v, patch)
                else
                    local entries = {}
                    for i, item in ipairs(v.items) do
                        entries[i] = { value = item, key = field_value(item, field), index = i }
                    end
                    table.sort(entries, function(a, b)
                        local c = compare(a.key, b.key)
                        if c == 0 then
                            return a.index < b.index
                        end
                        return descending and c > 0 or not descending and c < 0
                    end)
                    for i, entry in ipairs(entries) do
                        v.items[i] = entry.value
                    end
                end
            end
        end
        commit(changed)
        print(command .. " " .. #selected)
        return
    end
    local emitted = false
    for _, m in ipairs(matches) do
        if command == "GET" then
            print(location(m) .. " = " .. compact(m.node))
        elseif command == "COMPACT" then
            print(compact(m.node))
        elseif command == "PRETTY" then
            print(pretty(m.node, ""))
        elseif command == "TYPE" then
            print(location(m) .. " " .. m.node.kind)
        elseif command == "LENGTH" then
            print(location(m) .. " " .. (m.node.kind == "string" and #m.node.scalar or #m.node.items))
        elseif command == "KEYS" then
            local parts = {}
            for i, k in ipairs(m.node.keys) do
                parts[i] = quote(k, '"')
            end
            print(location(m) .. " [" .. table.concat(parts, ",") .. "]")
        elseif command == "FLATTEN" then
            preorder(m, function(leaf)
                if #leaf.node.items == 0 then
                    print(location(leaf) .. " = " .. compact(leaf.node))
                end
            end)
        elseif command == "FILTER" then
            for i in ipairs(m.node.items) do
                local element = child(m, i)
                if holds(operator, field_value(element.node, field), patch) then
                    print(location(element) .. " = " .. compact(element.node))
                    emitted = true
                end
            end
        end
        if command ~= "FILTER" then
            emitted = true
        end
    end
    if not emitted then
        print("no match")
    end
end
local lines = {}
for line in io.lines() do
    lines[#lines + 1] = line
end
local pos = 1
local function read_block()
    local body = {}
    while lines[pos] ~= "%%" do
        body[#body + 1] = lines[pos]
        pos = pos + 1
    end
    pos = pos + 1
    load(body)
end
read_block()
while lines[pos] ~= "END" do
    local line = lines[pos]
    pos = pos + 1
    if line == "LOAD" then
        read_block()
    else
        local ok, err = pcall(execute, line)
        if not ok then
            if err.position then
                print("PARSE ERROR col " .. err.position .. ": " .. err.reason)
            else
                print("ERROR " .. err.reason)
            end
        end
    end
end
