local WRONG_TYPE = "WRONGTYPE Operation against a key holding the wrong kind of value"
local NOT_INTEGER = "ERR value is not an integer or out of range"
local OVERFLOW = "ERR increment or decrement would overflow"
local BAD_SYNTAX = "ERR syntax error"
local POSITIVE = "ERR value is out of range, must be positive"
local NO_KEY = "ERR no such key"

local function fail(message) error({ message = message }, 0) end
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function count(values)
    local result = 0
    for _ in pairs(values) do result = result + 1 end
    return result
end
local function upper(text)
    return (text:gsub("[a-z]", function(c) return string.char(c:byte() - 32) end))
end
local function lower(text)
    return (text:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end))
end
local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then return x < y end
    end
    return #a < #b
end
local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, ascii_less)
    return keys
end
local function quote(text) return '"' .. text:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
local function integer_reply(value) return { "(integer) " .. value } end
local function text_reply(value) return { value == nil and "(nil)" or quote(value) } end
local function array_reply(values)
    if #values == 0 then return { "(empty array)" } end
    local width, result = #tostring(#values), {}
    for i, value in ipairs(values) do
        result[i] = string.rep(" ", width - #tostring(i)) .. i .. ") " .. (value == false and "(nil)" or quote(value))
    end
    return result
end
local function number(word, message)
    if word == "0" then return 0 end
    local first = word:sub(1, 1) == "-" and 2 or 1
    local digits = #word - first + 1
    if digits < 1 or digits > 9 or word:byte(first) < 49 or word:byte(first) > 57 then fail(message or NOT_INTEGER) end
    for i = first, #word do
        local byte = word:byte(i)
        if byte < 48 or byte > 57 then fail(message or NOT_INTEGER) end
    end
    return tonumber(word, 10)
end
local function checked_add(value, delta)
    local result = value + delta
    if result < -999999999 or result > 999999999 then fail(OVERFLOW) end
    return result
end
local function interval(length, first, last)
    if first < 0 then first = first + length end
    if last < 0 then last = last + length end
    first, last = math.max(0, first), math.min(length - 1, last)
    if first > last then return 1, 0 end
    return first + 1, last + 1
end
local function slice(values, first, last)
    local result = {}
    for i = first, last do result[#result + 1] = values[i] end
    return result
end
local function split_arguments(line)
    local words, position = {}, 1
    while position <= #line do
        if line:sub(position, position) == " " then
            position = position + 1
        elseif line:sub(position, position) ~= '"' then
            local first = position
            while position <= #line and line:sub(position, position) ~= " " do position = position + 1 end
            words[#words + 1] = line:sub(first, position - 1)
        else
            position = position + 1
            local characters, closed = {}, false
            while position <= #line do
                local character = line:sub(position, position)
                position = position + 1
                if character == '"' then closed = true; break end
                if character == "\\" then
                    character = line:sub(position, position)
                    if character ~= '"' and character ~= "\\" then return nil end
                    position = position + 1
                end
                characters[#characters + 1] = character
            end
            if not closed or (position <= #line and line:sub(position, position) ~= " ") then return nil end
            words[#words + 1] = table.concat(characters)
        end
    end
    return words
end
local function parse_pattern(text)
    local parts, i = {}, 1
    while i <= #text do
        local character = text:sub(i, i)
        if character == "\\" then
            i = i + 1
            if i > #text then fail("ERR invalid pattern") end
            parts[#parts + 1] = { kind = "literal", literal = text:sub(i, i) }
        elseif character == "[" then
            local last = text:find("]", i + 1, true)
            if not last then fail("ERR invalid pattern") end
            local first = i + 1
            local negated = first < last and text:sub(first, first) == "^"
            if negated then first = first + 1 end
            if first == last then fail("ERR invalid pattern") end
            local characters, j = {}, first
            while j < last do
                if j + 2 < last and text:sub(j + 1, j + 1) == "-" then
                    local a, b = text:byte(j), text:byte(j + 2)
                    for code = math.min(a, b), math.max(a, b) do characters[code] = true end
                    j = j + 3
                else
                    characters[text:byte(j)] = true
                    j = j + 1
                end
            end
            parts[#parts + 1] = { kind = "class", characters = characters, negated = negated }
            i = last
        else
            parts[#parts + 1] = { kind = character == "*" and "star" or character == "?" and "any" or "literal", literal = character }
        end
        i = i + 1
    end
    return parts
end
local function matches(parts, text)
    local previous = { true }
    for i = 2, #text + 1 do previous[i] = false end
    for _, part in ipairs(parts) do
        local current = {}
        if part.kind == "star" then
            current[1] = previous[1]
            for i = 1, #text do current[i + 1] = previous[i + 1] or current[i] end
        else
            current[1] = false
            for i = 1, #text do
                local accepts
                if part.kind == "any" then accepts = true
                elseif part.kind == "literal" then accepts = part.literal == text:sub(i, i)
                else accepts = (part.characters[text:byte(i)] ~= nil) ~= part.negated end
                current[i + 1] = previous[i] and accepts
            end
        end
        previous = current
    end
    return previous[#text + 1]
end
local function score_bound(word)
    if word == "-inf" then return { infinity = -1 } end
    if word == "+inf" then return { infinity = 1 } end
    local inclusive = word:sub(1, 1) ~= "("
    return { infinity = 0, inclusive = inclusive, value = number(inclusive and word or word:sub(2), "ERR min or max is not a float") }
end
local function accepts(bound, score, is_lower)
    if bound.infinity ~= 0 then return is_lower == (bound.infinity < 0) end
    if is_lower then return score > bound.value or (bound.inclusive and score == bound.value) end
    return score < bound.value or (bound.inclusive and score == bound.value)
end

local specifications = {}
local function add(group, names, minimum, maximum, parity)
    for name in names:gmatch("%S+") do specifications[name] = { group = group, minimum = minimum, maximum = maximum, parity = parity } end
end
add("text_command", "SET", 2)
add("text_command", "GET INCR DECR STRLEN", 1, 1)
add("text_command", "MSET", 2, nil, 0)
add("text_command", "MGET", 1)
add("text_command", "INCRBY DECRBY APPEND", 2, 2)
add("text_command", "GETRANGE", 3, 3)
add("list_command", "LPUSH RPUSH", 2)
add("list_command", "LPOP RPOP", 1, 2)
add("list_command", "LRANGE LSET LREM LTRIM", 3, 3)
add("list_command", "LLEN", 1, 1)
add("list_command", "LINDEX", 2, 2)
add("list_command", "LINSERT", 4, 4)
add("hash_command", "HSET", 3, nil, 1)
add("hash_command", "HGET HEXISTS", 2, 2)
add("hash_command", "HDEL", 2)
add("hash_command", "HGETALL HLEN HKEYS HVALS", 1, 1)
add("hash_command", "HINCRBY", 3, 3)
add("set_command", "SADD SREM SINTERSTORE SUNIONSTORE SDIFFSTORE", 2)
add("set_command", "SISMEMBER", 2, 2)
add("set_command", "SMEMBERS SCARD", 1, 1)
add("set_command", "SINTER SUNION SDIFF", 1)
add("sorted_set_command", "ZADD", 3, nil, 1)
add("sorted_set_command", "ZSCORE ZRANK", 2, 2)
add("sorted_set_command", "ZINCRBY", 3, 3)
add("sorted_set_command", "ZREM", 2)
add("sorted_set_command", "ZCARD", 1, 1)
add("sorted_set_command", "ZRANGE ZRANGEBYSCORE", 3, 4)
add("key_command", "DEL EXISTS", 1)
add("key_command", "TYPE KEYS TTL PERSIST TICK", 1, 1)
add("key_command", "RENAME RENAMENX", 2, 2)
add("key_command", "EXPIRE", 2, 3)
add("control_command", "TIME DBSIZE FLUSH INFO BEGIN COMMIT ROLLBACK", 0, 0)
add("control_command", "SNAPSHOT RESTORE", 1, 1)

local Store = {}
Store.__index = Store
function Store.new() return setmetatable({ database = {}, transactions = {}, snapshots = {}, time = 0 }, Store) end
function Store:value(key, kind)
    local entry = self.database[key]
    if entry and entry.kind ~= kind then fail(WRONG_TYPE) end
    return entry
end
function Store:put(key, kind, data, expiry) self.database[key] = { kind = kind, data = data, expiry = expiry } end
function Store:update(key, kind, data)
    if kind ~= "string" and next(data) == nil then self.database[key] = nil
    else
        local old = self.database[key]
        self:put(key, kind, data, old and old.expiry)
    end
end
function Store:purge()
    local removed = 0
    for key, entry in pairs(self.database) do
        if entry.expiry and entry.expiry <= self.time then self.database[key] = nil; removed = removed + 1 end
    end
    return removed
end
function Store:execute(words)
    local command = upper(words[1])
    local spec = specifications[command]
    if not spec then fail("ERR unknown command '" .. words[1] .. "'") end
    local args = slice(words, 2, #words)
    if #args < spec.minimum or (spec.maximum and #args > spec.maximum) or (spec.parity and #args % 2 ~= spec.parity) then
        fail("ERR wrong number of arguments for '" .. lower(command) .. "' command")
    end
    return self[spec.group](self, command, args)
end
function Store:text_command(command, args)
    local key = args[1]
    if command == "SET" then
        local options, seconds_word, i = {}, nil, 3
        while i <= #args do
            local option = upper(args[i])
            if not ({ NX = true, XX = true, EX = true, KEEPTTL = true, GET = true })[option] or options[option] then fail(BAD_SYNTAX) end
            options[option] = true
            if option == "EX" then
                i = i + 1
                if i > #args then fail(BAD_SYNTAX) end
                seconds_word = args[i]
            end
            i = i + 1
        end
        if (options.NX and options.XX) or (options.EX and options.KEEPTTL) then fail(BAD_SYNTAX) end
        local seconds = seconds_word and number(seconds_word)
        if seconds and seconds <= 0 then fail("ERR invalid expire time in 'set' command") end
        local old, previous = self.database[key], nil
        if options.GET then
            local value = self:value(key, "string")
            previous = value and value.data
        end
        local changed = not (options.NX and old) and not (options.XX and not old)
        if changed then
            local expiry
            if seconds then expiry = self.time + seconds elseif options.KEEPTTL and old then expiry = old.expiry end
            self:put(key, "string", args[2], expiry)
        end
        if options.GET then return text_reply(previous) end
        return changed and { "OK" } or text_reply(nil)
    end
    if command == "MSET" then
        for i = 1, #args, 2 do self:put(args[i], "string", args[i + 1]) end
        return { "OK" }
    end
    if command == "MGET" then
        local result = {}
        for i, name in ipairs(args) do
            local entry = self.database[name]
            result[i] = entry and entry.kind == "string" and entry.data or false
        end
        return array_reply(result)
    end
    if command == "INCR" or command == "DECR" or command == "INCRBY" or command == "DECRBY" then
        local delta = #args == 2 and number(args[2]) or 1
        if command == "DECR" or command == "DECRBY" then delta = -delta end
        local old = self:value(key, "string")
        local result = checked_add(old and number(old.data) or 0, delta)
        self:update(key, "string", tostring(result))
        return integer_reply(result)
    end
    local first, last = 0, 0
    if command == "GETRANGE" then first = number(args[2]); last = number(args[3]) end
    local old = self:value(key, "string")
    if command == "GET" then return text_reply(old and old.data) end
    local text = old and old.data or ""
    if command == "STRLEN" then return integer_reply(#text) end
    if command == "APPEND" then
        text = text .. args[2]
        self:update(key, "string", text)
        return integer_reply(#text)
    end
    first, last = interval(#text, first, last)
    return text_reply(text:sub(first, last))
end
function Store:list_command(command, args)
    local key, first, last = args[1], 0, 0
    if command == "LPOP" or command == "RPOP" then
        if #args == 2 then first = number(args[2], POSITIVE); if first < 0 then fail(POSITIVE) end end
    elseif command == "LINDEX" or command == "LSET" or command == "LREM" or command == "LRANGE" or command == "LTRIM" then
        first = number(args[2])
        if command == "LRANGE" or command == "LTRIM" then last = number(args[3]) end
    elseif command == "LINSERT" and upper(args[2]) ~= "BEFORE" and upper(args[2]) ~= "AFTER" then fail(BAD_SYNTAX) end
    local old = self:value(key, "list")
    local items = copy(old and old.data or {})
    if command == "LPUSH" or command == "RPUSH" then
        for i = 2, #args do
            if command == "LPUSH" then table.insert(items, 1, args[i]) else items[#items + 1] = args[i] end
        end
        self:update(key, "list", items)
        return integer_reply(#items)
    end
    if command == "LPOP" or command == "RPOP" then
        if not old then return text_reply(nil) end
        local amount, removed = #args == 1 and 1 or math.min(first, #items), {}
        for _ = 1, amount do removed[#removed + 1] = table.remove(items, command == "LPOP" and 1 or #items) end
        self:update(key, "list", items)
        return #args == 1 and text_reply(removed[1]) or array_reply(removed)
    end
    if command == "LLEN" then return integer_reply(#items) end
    if command == "LINDEX" or command == "LSET" then
        local index = (first < 0 and first + #items or first) + 1
        local valid = index >= 1 and index <= #items
        if command == "LINDEX" then return text_reply(valid and items[index] or nil) end
        if not old then fail(NO_KEY) end
        if not valid then fail("ERR index out of range") end
        items[index] = args[3]
        self:update(key, "list", items)
        return { "OK" }
    end
    if command == "LRANGE" or command == "LTRIM" then
        first, last = interval(#items, first, last)
        items = slice(items, first, last)
        if command == "LRANGE" then return array_reply(items) end
        self:update(key, "list", items)
        return { "OK" }
    end
    if command == "LREM" then
        local marked, removed = {}, 0
        local start, stop, step = 1, #items, 1
        if first < 0 then start, stop, step = #items, 1, -1 end
        for i = start, stop, step do
            if items[i] == args[3] and (first == 0 or removed < math.abs(first)) then marked[i] = true; removed = removed + 1 end
        end
        local kept = {}
        for i, value in ipairs(items) do if not marked[i] then kept[#kept + 1] = value end end
        self:update(key, "list", kept)
        return integer_reply(removed)
    end
    if not old then return integer_reply(0) end
    local index
    for i, value in ipairs(items) do if value == args[3] then index = i; break end end
    if not index then return integer_reply(-1) end
    if upper(args[2]) == "AFTER" then index = index + 1 end
    table.insert(items, index, args[4])
    self:update(key, "list", items)
    return integer_reply(#items)
end
function Store:hash_command(command, args)
    local key = args[1]
    local delta = command == "HINCRBY" and number(args[3]) or 0
    local old = self:value(key, "hash")
    local fields = copy(old and old.data or {})
    if command == "HSET" then
        local added = 0
        for i = 2, #args, 2 do
            if fields[args[i]] == nil then added = added + 1 end
            fields[args[i]] = args[i + 1]
        end
        self:update(key, "hash", fields)
        return integer_reply(added)
    end
    if command == "HGET" then return text_reply(fields[args[2]]) end
    if command == "HEXISTS" then return integer_reply(fields[args[2]] ~= nil and 1 or 0) end
    if command == "HLEN" then return integer_reply(count(fields)) end
    if command == "HDEL" then
        local removed = 0
        for i = 2, #args do if fields[args[i]] ~= nil then fields[args[i]] = nil; removed = removed + 1 end end
        self:update(key, "hash", fields)
        return integer_reply(removed)
    end
    if command == "HINCRBY" then
        local field = args[2]
        local value = fields[field] and number(fields[field], "ERR hash value is not an integer") or 0
        local result = checked_add(value, delta)
        fields[field] = tostring(result)
        self:update(key, "hash", fields)
        return integer_reply(result)
    end
    local result = {}
    for _, field in ipairs(sorted_keys(fields)) do
        if command ~= "HVALS" then result[#result + 1] = field end
        if command ~= "HKEYS" then result[#result + 1] = fields[field] end
    end
    return array_reply(result)
end
function Store:key_command(command, args)
    if command == "DEL" or command == "EXISTS" then
        local found = 0
        for _, key in ipairs(args) do
            if self.database[key] then
                found = found + 1
                if command == "DEL" then self.database[key] = nil end
            end
        end
        return integer_reply(found)
    end
    if command == "KEYS" then
        local pattern, keys = parse_pattern(args[1]), {}
        for key in pairs(self.database) do if matches(pattern, key) then keys[#keys + 1] = key end end
        table.sort(keys, ascii_less)
        return array_reply(keys)
    end
    if command == "TICK" then
        local amount = number(args[1])
        if amount <= 0 then fail(POSITIVE) end
        self.time = self.time + amount
        return integer_reply(self:purge())
    end
    local key = args[1]
    local entry = self.database[key]
    if command == "TYPE" then return { entry and entry.kind or "none" } end
    if command == "TTL" then
        if not entry then return integer_reply(-2) end
        return integer_reply(entry.expiry and entry.expiry - self.time or -1)
    end
    if command == "PERSIST" then
        if not entry or not entry.expiry then return integer_reply(0) end
        self:put(key, entry.kind, entry.data)
        return integer_reply(1)
    end
    if command == "RENAME" or command == "RENAMENX" then
        if not entry then fail(NO_KEY) end
        local destination = args[2]
        if command == "RENAMENX" and self.database[destination] then return integer_reply(0) end
        if key ~= destination then self.database[destination] = entry; self.database[key] = nil end
        return command == "RENAME" and { "OK" } or integer_reply(1)
    end
    local condition = #args == 3 and upper(args[3]) or ""
    if #args == 3 and not ({ NX = true, XX = true, GT = true, LT = true })[condition] then fail("ERR Unsupported option " .. args[3]) end
    local seconds = number(args[2])
    if not entry then return integer_reply(0) end
    local expiry, old = self.time + seconds, entry.expiry
    if (condition == "NX" and old ~= nil) or (condition == "XX" and old == nil)
        or (condition == "GT" and (old == nil or expiry <= old)) or (condition == "LT" and old ~= nil and expiry >= old) then
        return integer_reply(0)
    end
    if seconds <= 0 then self.database[key] = nil else self:put(key, entry.kind, entry.data, expiry) end
    return integer_reply(1)
end
function Store:control_command(command, args)
    if command == "TIME" then return integer_reply(self.time) end
    if command == "DBSIZE" then return integer_reply(count(self.database)) end
    if command == "FLUSH" then self.database = {}; return { "OK" } end
    if command == "INFO" then
        local counts = { string = 0, list = 0, hash = 0, set = 0, zset = 0 }
        local expires = 0
        for _, entry in pairs(self.database) do
            counts[entry.kind] = counts[entry.kind] + 1
            if entry.expiry then expires = expires + 1 end
        end
        return { "keys=" .. count(self.database) .. ",expires=" .. expires .. ",string=" .. counts.string
            .. ",list=" .. counts.list .. ",hash=" .. counts.hash .. ",set=" .. counts.set .. ",zset=" .. counts.zset
            .. ",time=" .. self.time .. ",depth=" .. #self.transactions .. ",snapshots=" .. count(self.snapshots) }
    end
    if command == "BEGIN" then self.transactions[#self.transactions + 1] = copy(self.database); return { "OK" } end
    if command == "COMMIT" or command == "ROLLBACK" then
        if #self.transactions == 0 then fail("ERR no transaction") end
        local saved = table.remove(self.transactions)
        if command == "ROLLBACK" then self.database = copy(saved); self:purge() end
        return { "OK" }
    end
    local name = args[1]
    if command == "SNAPSHOT" then self.snapshots[name] = copy(self.database); return { "OK" } end
    if not self.snapshots[name] then fail("ERR no such snapshot") end
    self.database = copy(self.snapshots[name])
    self:purge()
    return { "OK" }
end

function Store:set_command(command, args)
    local storing = command:sub(-5) == "STORE"
    local operation = command:sub(1, 6)
    local members
    if operation == "SINTER" or operation == "SUNION" or operation:sub(1, 5) == "SDIFF" then
        local sources = {}
        for i = storing and 2 or 1, #args do
            local value = self:value(args[i], "set")
            sources[#sources + 1] = value and value.data or {}
        end
        members = copy(sources[1])
        for i = 2, #sources do
            if operation == "SUNION" then
                for member in pairs(sources[i]) do members[member] = true end
            else
                for member in pairs(members) do
                    if (operation == "SINTER" and not sources[i][member]) or (operation ~= "SINTER" and sources[i][member]) then
                        members[member] = nil
                    end
                end
            end
        end
        if storing then
            if next(members) then self:put(args[1], "set", members) else self.database[args[1]] = nil end
            return integer_reply(count(members))
        end
    else
        local key = args[1]
        local value = self:value(key, "set")
        members = copy(value and value.data or {})
        if command == "SADD" or command == "SREM" then
            local changed = 0
            for i = 2, #args do
                local member = args[i]
                if command == "SADD" and not members[member] then members[member] = true; changed = changed + 1
                elseif command == "SREM" and members[member] then members[member] = nil; changed = changed + 1 end
            end
            self:update(key, "set", members)
            return integer_reply(changed)
        end
        if command == "SISMEMBER" then return integer_reply(members[args[2]] and 1 or 0) end
        if command == "SCARD" then return integer_reply(count(members)) end
    end
    return array_reply(sorted_keys(members))
end
function Store:sorted_set_command(command, args)
    local key, numbers = args[1], {}
    local low, high
    local with_scores = #args == 4 and (command == "ZRANGE" or command == "ZRANGEBYSCORE")
    if with_scores and upper(args[4]) ~= "WITHSCORES" then fail(BAD_SYNTAX) end
    if command == "ZADD" then
        for i = 2, #args, 2 do numbers[#numbers + 1] = number(args[i]) end
    elseif command == "ZINCRBY" then numbers[1] = number(args[2])
    elseif command == "ZRANGE" then numbers[1] = number(args[2]); numbers[2] = number(args[3])
    elseif command == "ZRANGEBYSCORE" then low = score_bound(args[2]); high = score_bound(args[3]) end
    local old = self:value(key, "zset")
    local scores = copy(old and old.data or {})
    if command == "ZADD" then
        local added = 0
        for i, value in ipairs(numbers) do
            local member = args[2 * i + 1]
            if scores[member] == nil then added = added + 1 end
            scores[member] = value
        end
        self:update(key, "zset", scores)
        return integer_reply(added)
    end
    if command == "ZSCORE" then
        local value = scores[args[2]]
        return text_reply(value ~= nil and tostring(value) or nil)
    end
    if command == "ZINCRBY" then
        local member = args[3]
        local result = checked_add(scores[member] or 0, numbers[1])
        scores[member] = result
        self:update(key, "zset", scores)
        return text_reply(tostring(result))
    end
    if command == "ZREM" then
        local removed = 0
        for i = 2, #args do if scores[args[i]] ~= nil then scores[args[i]] = nil; removed = removed + 1 end end
        self:update(key, "zset", scores)
        return integer_reply(removed)
    end
    if command == "ZCARD" then return integer_reply(count(scores)) end
    local members = sorted_keys(scores)
    table.sort(members, function(a, b)
        if scores[a] ~= scores[b] then return scores[a] < scores[b] end
        return ascii_less(a, b)
    end)
    if command == "ZRANK" then
        for i, member in ipairs(members) do if member == args[2] then return integer_reply(i - 1) end end
        return text_reply(nil)
    end
    if command == "ZRANGE" then
        local first, last = interval(#members, numbers[1], numbers[2])
        members = slice(members, first, last)
    else
        local selected = {}
        for _, member in ipairs(members) do
            if accepts(low, scores[member], true) and accepts(high, scores[member], false) then selected[#selected + 1] = member end
        end
        members = selected
    end
    local result = {}
    for _, member in ipairs(members) do
        result[#result + 1] = member
        if with_scores then result[#result + 1] = tostring(scores[member]) end
    end
    return array_reply(result)
end

local store = Store.new()
local command_count = tonumber(io.read("*l"), 10)
for _ = 1, command_count do
    local line = io.read("*l"):gsub("\r$", "")
    local words = split_arguments(line)
    local output
    if not words then output = { "Invalid argument(s)" }
    else
        local ok, result = pcall(function() return store:execute(words) end)
        output = ok and result or { "(error) " .. result.message }
    end
    for _, row in ipairs(output) do io.write(row, "\n") end
end
