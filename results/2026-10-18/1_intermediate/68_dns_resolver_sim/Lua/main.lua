local TYPES = { "A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA" }
local KINDS = { "ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT" }
local function bad(format, ...)
    error(string.format(format, ...), 0)
end
local function index_of(xs, value)
    for i, x in ipairs(xs) do
        if x == value then
            return i
        end
    end
end
local function split(s, separator)
    local out, at = {}, 1
    while true do
        local p = s:find(separator, at, true)
        if not p then
            out[#out + 1] = s:sub(at)
            return out
        end
        out[#out + 1] = s:sub(at, p - 1)
        at = p + #separator
    end
end
local function integer_word(s)
    return #s >= 1 and #s <= 9 and (s == "0" or s:match("^[1-9][0-9]*$") ~= nil)
end
local function labels(name)
    return name == "." and {} or split(name:sub(1, -2), ".")
end
local function below(name, ancestor)
    return ancestor == "." or name == ancestor or name:sub(-#ancestor - 1) == "." .. ancestor
end
local function name_compare(a, b)
    local x, y = labels(a), labels(b)
    local i, j = #x, #y
    while i > 0 and j > 0 do
        if x[i] ~= y[j] then
            return x[i] < y[j] and -1 or 1
        end
        i, j = i - 1, j - 1
    end
    if #x == #y then
        return 0
    end
    return #x < #y and -1 or 1
end
local function ancestors(name)
    local out = { name }
    while name ~= "." do
        name = name:sub(name:find(".", 1, true) + 1)
        if name == "" then
            name = "."
        end
        out[#out + 1] = name
    end
    return out
end
local function parse_name(word, origin, wildcard)
    if origin and word == "@" then
        return origin
    end
    if word == "." then
        return "."
    end
    local absolute = word:sub(-1) == "."
    local text = absolute and word:sub(1, -2) or word
    for i, label in ipairs(split(text, ".")) do
        if not (wildcard and i == 1 and label == "*") then
            if #label < 1 or #label > 63 or label:sub(1, 1) == "-" or label:sub(-1) == "-" or not label:match("^[A-Za-z0-9%-]+$") then
                bad("bad name %s", word)
            end
        end
    end
    local name = text:lower() .. "."
    if origin and origin ~= "." and not absolute then
        name = name .. origin
    end
    return name
end
local function parse_ipv4(s)
    local fields = split(s, ".")
    if #fields ~= 4 then
        bad("bad address %s", s)
    end
    local a = 0
    for _, p in ipairs(fields) do
        if #p > 3 or not integer_word(p) or tonumber(p) > 255 then
            bad("bad address %s", s)
        end
        a = a * 256 + tonumber(p)
    end
    return a
end
local function ipv4(a)
    return string.format("%d.%d.%d.%d", (a >> 24) & 255, (a >> 16) & 255, (a >> 8) & 255, a & 255)
end
local function parse_ipv6(s)
    local delimiter = s:find("::", 1, true)
    local function parse(text)
        if text == "" then
            return {}
        end
        local out = {}
        for _, group in ipairs(split(text, ":")) do
            if #group < 1 or #group > 4 or not group:match("^%x+$") then
                bad("bad address %s", s)
            end
            out[#out + 1] = tonumber(group, 16)
        end
        return out
    end
    local a = parse(delimiter and s:sub(1, delimiter - 1) or s)
    if not delimiter then
        if #a ~= 8 then
            bad("bad address %s", s)
        end
        return a
    end
    local b = parse(s:sub(delimiter + 2))
    if #a + #b > 7 then
        bad("bad address %s", s)
    end
    local out = {}
    for _, n in ipairs(a) do
        out[#out + 1] = n
    end
    for _ = 1, 8 - #a - #b do
        out[#out + 1] = 0
    end
    for _, n in ipairs(b) do
        out[#out + 1] = n
    end
    return out
end
local function ipv6(a)
    local best, length, i = nil, 0, 1
    while i <= 8 do
        if a[i] ~= 0 then
            i = i + 1
        else
            local j = i
            while j <= 8 and a[j] == 0 do
                j = j + 1
            end
            if j - i >= 2 and j - i > length then
                best, length = i, j - i
            end
            i = j
        end
    end
    local groups = {}
    for j, n in ipairs(a) do
        groups[j] = string.format("%x", n)
    end
    if not best then
        return table.concat(groups, ":")
    end
    local first, last = {}, {}
    for j = 1, best - 1 do
        first[#first + 1] = groups[j]
    end
    for j = best + length, 8 do
        last[#last + 1] = groups[j]
    end
    return table.concat(first, ":") .. "::" .. table.concat(last, ":")
end
local function parse_ttl(s)
    if integer_word(s) then
        local n = tonumber(s)
        if n >= 1 and n <= 604800 then
            return n
        end
        bad("bad ttl %s", s)
    end
    local multipliers, total, previous, pos = { 604800, 86400, 3600, 60, 1 }, 0, 0, 1
    while pos <= #s do
        local digits = s:match("^([0-9]+)", pos)
        if not digits or #digits > 3 or not integer_word(digits) then
            bad("bad ttl %s", s)
        end
        pos = pos + #digits
        local unit = ("wdhms"):find(s:sub(pos, pos):lower(), 1, true)
        if pos > #s or not unit or unit <= previous then
            bad("bad ttl %s", s)
        end
        total, previous, pos = total + tonumber(digits) * multipliers[unit], unit, pos + 1
    end
    if total < 1 or total > 604800 then
        bad("bad ttl %s", s)
    end
    return total
end
local function record_text(r)
    return string.format("%s %d %s %s", r.owner, r.ttl, r.kind, r.data)
end
local function data_compare(a, b)
    if a.kind == "A" then
        if a.address == b.address then
            return 0
        end
        return a.address < b.address and -1 or 1
    elseif a.kind == "AAAA" then
        for i = 1, 8 do
            if a.address6[i] ~= b.address6[i] then
                return a.address6[i] < b.address6[i] and -1 or 1
            end
        end
        return 0
    elseif a.kind == "NS" or a.kind == "CNAME" or a.kind == "PTR" then
        return name_compare(a.target, b.target)
    elseif a.kind == "MX" then
        if a.preference ~= b.preference then
            return a.preference < b.preference and -1 or 1
        end
        return name_compare(a.target, b.target)
    else
        if a.data == b.data then
            return 0
        end
        return a.data < b.data and -1 or 1
    end
end
local function sorted_records(records)
    local out = {}
    for i, r in ipairs(records) do
        out[i] = r
    end
    table.sort(out, function(a, b)
        local c = name_compare(a.owner, b.owner)
        if c ~= 0 then
            return c < 0
        end
        if a.kind ~= b.kind then
            return index_of(TYPES, a.kind) < index_of(TYPES, b.kind)
        end
        return data_compare(a, b) < 0
    end)
    return out
end
local function records_at(zone, owner, kind)
    local out = {}
    for _, r in ipairs(zone.records) do
        if r.owner == owner and (not kind or r.kind == kind) then
            out[#out + 1] = r
        end
    end
    return sorted_records(out)
end
local function exists(zone, name)
    for _, r in ipairs(zone.records) do
        if below(r.owner, name) then
            return true
        end
    end
    return false
end
local function soa(zone)
    for _, r in ipairs(zone.records) do
        if r.kind == "SOA" then
            return r
        end
    end
end
local function with_ttl(records, ttl)
    local out = {}
    for i, r in ipairs(records) do
        local rec = {}
        for k, v in pairs(r) do
            rec[k] = v
        end
        rec.ttl = ttl
        out[i] = rec
    end
    return out
end
local function description(response)
    if response.kind == "REFERRAL" then
        return "REFERRAL " .. response.referral
    end
    if response.kind == "CNAME" then
        return "CNAME " .. response.answer[1].target
    end
    return response.kind
end
local function cache_key(name, kind)
    return name .. "\0" .. kind
end
local Resolver = {}
Resolver.__index = Resolver
function Resolver.new()
    return setmetatable({ roots = {}, zones = {}, down = {}, cache = {}, settings = { MINTTL = 1, MAXTTL = 86400, NEGTTL = 3600 }, stats = {}, resolutions = { 0, 0, 0, 0 }, hits = 0, clock = 0 }, Resolver)
end
function Resolver:zone_line(words, line)
    if words[1] == "ROOT" then
        local pending, seen = {}, {}
        for _, a in ipairs(self.roots) do
            seen[a] = true
        end
        for i = 2, #words do
            local a = parse_ipv4(words[i])
            if seen[a] then
                bad("duplicate root %s", words[i])
            end
            seen[a] = true
            pending[#pending + 1] = a
        end
        for _, a in ipairs(pending) do
            self.roots[#self.roots + 1] = a
        end
        return
    end
    if words[1] == "ZONE" then
        self.current = nil
        local origin = parse_name(words[2], nil, false)
        local server = parse_ipv4(words[3])
        for _, z in ipairs(self.zones) do
            if z.origin == origin and z.server == server then
                bad("duplicate zone %s at %s", origin, words[3])
            end
        end
        self.current = { origin = origin, server = server, line = line, records = {} }
        self.zones[#self.zones + 1] = self.current
        return
    end
    local z = self.current
    if not z then
        bad("no current zone")
    end
    local owner = parse_name(words[1], z.origin, true)
    if not below(owner, z.origin) then
        bad("out of zone %s", owner)
    end
    local ttl = parse_ttl(words[2])
    local kind, fields = words[3], {}
    for i = 4, #words do
        fields[#fields + 1] = words[i]
    end
    if not index_of(TYPES, kind) then
        bad("bad type %s", kind)
    end
    local required = kind == "MX" and 2 or kind == "SOA" and 7 or 1
    if kind ~= "TXT" and #fields ~= required then
        bad("wrong field count")
    end
    local rec = { owner = owner, ttl = ttl, kind = kind }
    if kind == "A" then
        rec.address = parse_ipv4(fields[1])
        rec.data = ipv4(rec.address)
    elseif kind == "AAAA" then
        rec.address6 = parse_ipv6(fields[1])
        rec.data = ipv6(rec.address6)
    elseif kind == "NS" or kind == "CNAME" or kind == "PTR" then
        rec.target = parse_name(fields[1], z.origin, false)
        rec.data = rec.target
    elseif kind == "MX" then
        if not integer_word(fields[1]) or tonumber(fields[1]) > 65535 then
            bad("bad preference %s", fields[1])
        end
        rec.preference = tonumber(fields[1])
        rec.target = parse_name(fields[2], z.origin, false)
        rec.data = rec.preference .. " " .. rec.target
    elseif kind == "TXT" then
        rec.data = table.concat(fields, " ")
        if #rec.data < 2 or rec.data:sub(1, 1) ~= '"' or rec.data:sub(-1) ~= '"' or rec.data:sub(2, -2):find('"', 1, true) then
            bad("bad text %s", rec.data)
        end
    else
        local data = {}
        data[1] = parse_name(fields[1], z.origin, false)
        data[2] = parse_name(fields[2], z.origin, false)
        for i = 3, 6 do
            if not integer_word(fields[i]) then
                bad("bad number %s", fields[i])
            end
            data[i] = fields[i]
        end
        if not integer_word(fields[7]) or tonumber(fields[7]) < 1 or tonumber(fields[7]) > 86400 then
            bad("bad minimum %s", fields[7])
        end
        data[7], rec.minimum = fields[7], tonumber(fields[7])
        rec.data = table.concat(data, " ")
    end
    if kind == "NS" and owner:sub(1, 2) == "*." then
        bad("ns at wildcard")
    end
    if kind == "SOA" and owner ~= z.origin then
        bad("soa not at origin")
    end
    if kind == "SOA" and soa(z) then
        bad("duplicate soa")
    end
    for _, old in ipairs(z.records) do
        if old.owner == owner and old.kind == kind and old.data == rec.data then
            bad("duplicate record")
        end
    end
    for _, old in ipairs(z.records) do
        if old.owner == owner and (kind == "CNAME" or old.kind == "CNAME") then
            bad("cname conflict %s", owner)
        end
    end
    z.records[#z.records + 1] = rec
end
function Resolver:finish_zones()
    local kept, count = {}, 0
    for _, z in ipairs(self.zones) do
        if not soa(z) then
            print(string.format("error line %d: zone %s at %s has no soa", z.line, z.origin, ipv4(z.server)))
        else
            kept[#kept + 1] = z
            count = count + #z.records
            print(string.format("zone %s at %s records=%d", z.origin, ipv4(z.server), #z.records))
        end
    end
    self.zones, self.current = kept, nil
    print(string.format("loaded roots=%d zones=%d records=%d", #self.roots, #self.zones, count))
end
function Resolver:known(server)
    for _, z in ipairs(self.zones) do
        if z.server == server then
            return true
        end
    end
    return false
end
function Resolver:authoritative(server, name, kind, cut)
    if self.down[server] or not self:known(server) then
        return { kind = "TIMEOUT" }
    end
    local z
    for _, candidate in ipairs(self.zones) do
        if candidate.server == server and below(name, candidate.origin) and (not z or #labels(candidate.origin) > #labels(z.origin)) then
            z = candidate
        end
    end
    if not z or #labels(z.origin) < #labels(cut) then
        return { kind = "LAME" }
    end
    local chain = ancestors(name)
    for i = #chain, 1, -1 do
        local d = chain[i]
        if d ~= z.origin and below(d, z.origin) then
            local ns = records_at(z, d, "NS")
            if #ns > 0 then
                local additional = {}
                for _, rec in ipairs(ns) do
                    for _, a in ipairs(records_at(z, rec.target, "A")) do
                        additional[#additional + 1] = a
                    end
                end
                return { kind = "REFERRAL", referral = d, authority = ns, additional = additional }
            end
        end
    end
    local records = records_at(z, name)
    if #records == 0 then
        if exists(z, name) then
            return { kind = "NODATA", authority = { soa(z) } }
        end
        local wildcard = ""
        for i = 2, #chain do
            if exists(z, chain[i]) then
                wildcard = chain[i] == "." and "*." or "*." .. chain[i]
                break
            end
        end
        records = records_at(z, wildcard)
        if #records == 0 then
            return { kind = "NXDOMAIN", authority = { soa(z) } }
        end
    end
    local answers = {}
    for _, rec in ipairs(records) do
        if rec.kind == kind then
            local cloned = with_ttl({ rec }, rec.ttl)[1]
            cloned.owner = name
            answers[#answers + 1] = cloned
        end
    end
    if #answers > 0 then
        return { kind = "ANSWER", answer = sorted_records(answers) }
    end
    if kind ~= "CNAME" then
        for _, rec in ipairs(records) do
            if rec.kind == "CNAME" then
                local cloned = with_ttl({ rec }, rec.ttl)[1]
                cloned.owner = name
                return { kind = "CNAME", answer = { cloned } }
            end
        end
    end
    return { kind = "NODATA", authority = { soa(z) } }
end
function Resolver:ask(server, name, kind, cut)
    local answer = self:authoritative(server, name, kind, cut)
    if not self.stats[server] then
        self.stats[server] = { 0, 0, 0, 0, 0, 0, 0 }
    end
    local i = index_of(KINDS, answer.kind)
    self.stats[server][i] = self.stats[server][i] + 1
    return answer
end
function Resolver:trace(depth, format, ...)
    print((" "):rep(2 * (depth + 1)) .. string.format(format, ...))
end
function Resolver:store(records)
    local ttl = records[1].ttl
    for _, rec in ipairs(records) do
        ttl = math.min(ttl, rec.ttl)
    end
    ttl = math.min(math.max(ttl, self.settings.MINTTL), self.settings.MAXTTL)
    local first = records[1]
    self.cache[cache_key(first.owner, first.kind)] = { name = first.owner, type = first.kind, kind = "POS", records = sorted_records(records), expiry = self.clock + ttl }
    return ttl
end
function Resolver:query_servers(name, kind, cut, names, roots, depth, resolving)
    local function query(a)
        local response = self:ask(a, name, kind, cut)
        self:trace(depth, "ASK %s %s %s -> %s", ipv4(a), name, kind, description(response))
        if response.kind ~= "LAME" and response.kind ~= "TIMEOUT" then
            return response
        end
    end
    if roots then
        for _, a in ipairs(self.roots) do
            local response = query(a)
            if response then
                return response
            end
        end
        return nil
    end
    local ordered = {}
    for i, host in ipairs(names) do
        ordered[i] = host
    end
    table.sort(ordered, function(a, b)
        return name_compare(a, b) < 0
    end)
    for _, host in ipairs(ordered) do
        local addresses, key = {}, cache_key(host, "A")
        local cached = self.cache[key]
        if cached and cached.kind == "POS" then
            for _, rec in ipairs(cached.records) do
                addresses[rec.address] = true
            end
        else
            local loop = false
            for _, pair in ipairs(resolving) do
                if pair == key then
                    loop = true
                    break
                end
            end
            if loop then
                self:trace(depth, "GLUELESS %s -> LOOP", host)
            else
                self:trace(depth, "GLUELESS %s", host)
                local response = self:resolve(host, "A", depth + 1, resolving)
                if response.status == "NOERROR" then
                    for _, rec in ipairs(response.answer) do
                        if rec.kind == "A" then
                            addresses[rec.address] = true
                        end
                    end
                end
            end
        end
        local sorted = {}
        for a in pairs(addresses) do
            sorted[#sorted + 1] = a
        end
        table.sort(sorted)
        for _, a in ipairs(sorted) do
            local response = query(a)
            if response then
                return response
            end
        end
    end
end
function Resolver:lookup(name, kind, depth, resolving)
    local key = cache_key(name, kind)
    local cached = self.cache[key]
    if cached then
        self.hits = self.hits + 1
        local response = { kind = cached.kind }
        if cached.kind == "POS" then
            response.kind, response.answer = "ANSWER", with_ttl(cached.records, cached.expiry - self.clock)
        end
        self:trace(depth, "CACHE HIT %s %s -> %s", name, kind, response.kind)
        return response
    end
    for _, entry in pairs(self.cache) do
        if entry.kind == "NXDOMAIN" and below(name, entry.name) then
            self.hits = self.hits + 1
            self:trace(depth, "CACHE HIT %s %s -> NXDOMAIN", name, kind)
            return { kind = "NXDOMAIN" }
        end
    end
    cached = kind ~= "CNAME" and self.cache[cache_key(name, "CNAME")] or nil
    if cached and cached.kind == "POS" then
        self.hits = self.hits + 1
        local records = with_ttl(cached.records, cached.expiry - self.clock)
        self:trace(depth, "CACHE HIT %s %s -> CNAME %s", name, kind, records[1].target)
        return { kind = "CNAME", answer = records }
    end
    local cut, names, roots = ".", {}, true
    for _, ancestor in ipairs(ancestors(name)) do
        cached = self.cache[cache_key(ancestor, "NS")]
        if cached and cached.kind == "POS" then
            cut, roots = ancestor, false
            for _, rec in ipairs(cached.records) do
                names[#names + 1] = rec.target
            end
            self.hits = self.hits + 1
            self:trace(depth, "CACHE HIT %s %s -> REFERRAL %s", name, kind, cut)
            break
        end
    end
    while true do
        local response = self:query_servers(name, kind, cut, names, roots, depth, resolving)
        if not response then
            return { kind = "SERVFAIL no server for " .. cut }
        end
        if response.kind == "REFERRAL" then
            self:store(response.authority)
            local grouped = {}
            for _, rec in ipairs(response.additional) do
                if not grouped[rec.owner] then
                    grouped[rec.owner] = {}
                end
                grouped[rec.owner][#grouped[rec.owner] + 1] = rec
            end
            for _, records in pairs(grouped) do
                self:store(records)
            end
            cut, names, roots = response.referral, {}, false
            for _, rec in ipairs(response.authority) do
                names[#names + 1] = rec.target
            end
        elseif response.kind == "ANSWER" or response.kind == "CNAME" then
            response.answer = with_ttl(response.answer, self:store(response.answer))
            return response
        else
            local record = response.authority[1]
            local ttl = math.min(record.ttl, record.minimum, self.settings.NEGTTL)
            self.cache[key] = { name = name, type = kind, kind = response.kind, expiry = self.clock + ttl }
            return response
        end
    end
end
function Resolver:resolve(name, kind, depth, resolving)
    local active = {}
    for i, pair in ipairs(resolving or {}) do
        active[i] = pair
    end
    active[#active + 1] = cache_key(name, kind)
    local chain, seen, current = {}, { [name] = true }, name
    local status, answer
    while true do
        local response = self:lookup(current, kind, depth, active)
        if response.kind == "CNAME" then
            local rec = response.answer[1]
            chain[#chain + 1] = rec
            if seen[rec.target] then
                status = "SERVFAIL cname loop"
                break
            end
            if #chain == 9 then
                status = "SERVFAIL cname chain too long"
                break
            end
            seen[rec.target], current = true, rec.target
        elseif response.kind == "ANSWER" then
            status, answer = "NOERROR", chain
            for _, rec in ipairs(response.answer) do
                answer[#answer + 1] = rec
            end
            break
        elseif response.kind == "NODATA" or response.kind == "NXDOMAIN" then
            status, answer = response.kind, chain
            break
        else
            status = response.kind
            break
        end
    end
    local index = index_of({ "NOERROR", "NODATA", "NXDOMAIN" }, status) or 4
    self.resolutions[index] = self.resolutions[index] + 1
    return { status = status, answer = answer or {} }
end
function Resolver:emit_result(response)
    for _, rec in ipairs(response.answer) do
        print("answer " .. record_text(rec))
    end
    print("status " .. response.status)
end
function Resolver:address_resolution(host, prefix)
    local a = self:resolve(host, "A", 0, {})
    local aaaa = self:resolve(host, "AAAA", 0, {})
    local addresses = {}
    for _, response in ipairs({ a, aaaa }) do
        if response.status == "NOERROR" then
            for _, rec in ipairs(response.answer) do
                if rec.kind == "A" or rec.kind == "AAAA" then
                    addresses[#addresses + 1] = rec.data
                end
            end
        end
    end
    print(prefix .. " -> " .. (#addresses == 0 and "no address" or table.concat(addresses, " ")))
end
function Resolver:command(w)
    local command = w[1]
    if command == "RESOLVE" or command == "MX" then
        local name = parse_name(w[2], nil, true)
        local kind = command == "MX" and "MX" or w[3]
        if not index_of(TYPES, kind) then
            bad("bad type %s", kind)
        end
        print(command == "MX" and "mx " .. name or "resolve " .. name .. " " .. kind)
        local response = self:resolve(name, kind, 0, {})
        self:emit_result(response)
        if command == "MX" then
            if response.status == "NOERROR" then
                for _, rec in ipairs(response.answer) do
                    if rec.kind == "MX" then
                        local prefix = "exchange " .. rec.preference .. " " .. rec.target
                        if rec.target == "." then
                            print(prefix .. " -> null")
                        else
                            self:address_resolution(rec.target, prefix)
                        end
                    end
                end
            elseif response.status == "NODATA" then
                local host = name
                for _, rec in ipairs(response.answer) do
                    if rec.kind == "CNAME" then
                        host = rec.target
                    end
                end
                self:address_resolution(host, "implicit " .. host)
            end
        end
    elseif command == "REVERSE" then
        local text, name
        if w[2]:find(":", 1, true) then
            local a = parse_ipv6(w[2])
            text = ipv6(a)
            local digits = {}
            for _, n in ipairs(a) do
                digits[#digits + 1] = string.format("%04x", n)
            end
            digits = table.concat(digits)
            local parts = {}
            for i = #digits, 1, -1 do
                parts[#parts + 1] = digits:sub(i, i)
            end
            name = table.concat(parts, ".") .. ".ip6.arpa."
        else
            local a = parse_ipv4(w[2])
            text = ipv4(a)
            local fields = split(text, ".")
            name = fields[4] .. "." .. fields[3] .. "." .. fields[2] .. "." .. fields[1] .. ".in-addr.arpa."
        end
        print("reverse " .. text .. " " .. name)
        self:emit_result(self:resolve(name, "PTR", 0, {}))
    elseif command == "QUERY" or command == "DUMP" then
        local server = parse_ipv4(w[2])
        local name = parse_name(w[3], nil, command == "QUERY")
        if command == "QUERY" then
            if not index_of(TYPES, w[4]) then
                bad("bad type %s", w[4])
            end
            local response = self:ask(server, name, w[4], ".")
            print(string.format("query %s %s %s -> %s", ipv4(server), name, w[4], description(response)))
            for _, group in ipairs({ { "answer", response.answer or {} }, { "authority", response.authority or {} }, { "additional", response.additional or {} } }) do
                for _, rec in ipairs(group[2]) do
                    print(group[1] .. " " .. record_text(rec))
                end
            end
        elseif self.down[server] or not self:known(server) then
            print("dump " .. ipv4(server) .. " " .. name .. " -> TIMEOUT")
        else
            for _, z in ipairs(self.zones) do
                if z.server == server and z.origin == name then
                    print(string.format("dump %s %s records=%d", ipv4(server), name, #z.records))
                    for _, rec in ipairs(sorted_records(z.records)) do
                        print("  " .. record_text(rec))
                    end
                    return
                end
            end
            print("dump " .. ipv4(server) .. " " .. name .. " -> REFUSED")
        end
    elseif command == "DOWN" or command == "UP" then
        local server = parse_ipv4(w[2])
        if command == "DOWN" then
            if self.down[server] then
                bad("server %s already down", w[2])
            end
            self.down[server] = true
            print("down " .. ipv4(server))
        else
            if not self.down[server] then
                bad("server %s not down", w[2])
            end
            self.down[server] = nil
            print("up " .. ipv4(server))
        end
    elseif command == "SET" then
        local key = w[2]
        if self.settings[key] == nil then
            bad("bad setting %s", key)
        end
        if not integer_word(w[3]) or tonumber(w[3]) < 1 or tonumber(w[3]) > 604800 then
            bad("bad value %s", w[3])
        end
        local n, minimum, maximum = tonumber(w[3]), self.settings.MINTTL, self.settings.MAXTTL
        if key == "MINTTL" then
            minimum = n
        elseif key == "MAXTTL" then
            maximum = n
        end
        if minimum > maximum then
            bad("minttl above maxttl")
        end
        self.settings[key] = n
        print("set " .. key .. "=" .. n)
    elseif command == "TIME" then
        if not integer_word(w[2]) or tonumber(w[2]) < 1 or tonumber(w[2]) > 1000000 then
            bad("bad time %s", w[2])
        end
        self.clock = self.clock + tonumber(w[2])
        local expired = 0
        for key, entry in pairs(self.cache) do
            if entry.expiry <= self.clock then
                self.cache[key] = nil
                expired = expired + 1
            end
        end
        print(string.format("time now=%d expired=%d", self.clock, expired))
    elseif command == "CACHE" or command == "FLUSH" then
        local ancestor = w[2] and parse_name(w[2], nil, false) or "."
        local selected = {}
        for key, entry in pairs(self.cache) do
            if below(entry.name, ancestor) then
                selected[#selected + 1] = { key = key, entry = entry }
            end
        end
        table.sort(selected, function(a, b)
            local c = name_compare(a.entry.name, b.entry.name)
            if c ~= 0 then
                return c < 0
            end
            return index_of(TYPES, a.entry.type) < index_of(TYPES, b.entry.type)
        end)
        if command == "FLUSH" then
            for _, item in ipairs(selected) do
                self.cache[item.key] = nil
            end
            print("flush removed=" .. #selected)
        else
            print("cache entries=" .. #selected)
            for _, item in ipairs(selected) do
                local entry = item.entry
                if entry.kind == "POS" then
                    for _, rec in ipairs(with_ttl(entry.records, entry.expiry - self.clock)) do
                        print("  " .. record_text(rec))
                    end
                else
                    print(string.format("  %s %d %s %s", entry.name, entry.expiry - self.clock, entry.type, entry.kind))
                end
            end
        end
    elseif command == "STATS" then
        local servers, total = {}, 0
        for server, stats in pairs(self.stats) do
            servers[#servers + 1] = server
            for _, n in ipairs(stats) do
                total = total + n
            end
        end
        table.sort(servers)
        print(string.format("stats queries=%d hits=%d", total, self.hits))
        for _, server in ipairs(servers) do
            local stats, sent = self.stats[server], 0
            for _, n in ipairs(stats) do
                sent = sent + n
            end
            local parts = { string.format("  %s sent=%d", ipv4(server), sent) }
            for i, kind in ipairs(KINDS) do
                parts[#parts + 1] = kind:lower() .. "=" .. stats[i]
            end
            print(table.concat(parts, " "))
        end
        print(string.format("resolutions noerror=%d nodata=%d nxdomain=%d servfail=%d", self.resolutions[1], self.resolutions[2], self.resolutions[3], self.resolutions[4]))
    end
end
local lines = {}
for line in io.lines() do
    lines[#lines + 1] = line
end
local resolver, pos = Resolver.new(), 1
while lines[pos] ~= "END ZONES" do
    local ok, err = pcall(Resolver.zone_line, resolver, split(lines[pos], " "), pos)
    if not ok then
        print("error line " .. pos .. ": " .. err)
    end
    pos = pos + 1
end
resolver:finish_zones()
pos = pos + 1
while lines[pos] ~= "END" do
    local ok, err = pcall(Resolver.command, resolver, split(lines[pos], " "))
    if not ok then
        print("error line " .. pos .. ": " .. err)
    end
    pos = pos + 1
end
