local network = require("link_network")
local M = {}
local names = {[1] = "A", [2] = "NS", [5] = "CNAME", [6] = "SOA", [12] = "PTR", [15] = "MX", [16] = "TXT", [28] = "AAAA"}
function M.type_name(value)
    return names[value] or "TYPE" .. value
end
function M.rcode_name(value)
    return ({"NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused"})[value + 1] or "RCODE" .. value
end
local function label_text(data)
    local result = {}
    for i = 1, #data do
        local value = data:byte(i)
        result[i] = value >= 33 and value <= 126 and value ~= 46 and value ~= 92 and string.char(value) or string.format("\\%03d", value)
    end
    return table.concat(result)
end
local function ipv6(data)
    local groups, texts, start, length, index = {}, {}, nil, 1, 1
    for i = 1, 8 do
        groups[i] = network.integer(data, 2 * (i - 1), 2)
        texts[i] = string.format("%x", groups[i])
    end
    while index <= 8 do
        if groups[index] ~= 0 then
            index = index + 1
        else
            local last = index
            while last <= 8 and groups[last] == 0 do
                last = last + 1
            end
            if last - index > length then
                start, length = index, last - index
            end
            index = last
        end
    end
    if not start then
        return table.concat(texts, ":")
    end
    return table.concat(texts, ":", 1, start - 1) .. "::" .. table.concat(texts, ":", start + length, 8)
end
local Reader = {}
Reader.__index = Reader
function Reader:chunk(position, size)
    if position + size > #self.data then
        error("dns: truncated", 0)
    end
    return self.data:sub(position + 1, position + size)
end
function Reader:integer(position, size)
    return network.integer(self:chunk(position, size), 0, size)
end
function Reader:name(position)
    local labels, pointers, after = {}, 0, nil
    while true do
        local size = self:integer(position, 1)
        if size == 0 then
            after = after or position + 1
            break
        elseif size >= 192 then
            local low = self:integer(position + 1, 1)
            after, pointers = after or position + 2, pointers + 1
            if pointers > 16 then
                error("dns: compression loop", 0)
            end
            position = (size - 192) * 256 + low
            if position >= #self.data then
                error("dns: pointer out of range", 0)
            end
        elseif size >= 64 then
            error("dns: bad label type", 0)
        else
            labels[#labels + 1] = label_text(self:chunk(position + 1, size))
            position = position + size + 1
        end
    end
    return #labels > 0 and table.concat(labels, ".") or "<root>", after
end
function Reader:rdata(kind, start, size)
    if kind == 1 then
        return network.ipv4(self:integer(start, 4)), start + 4
    end
    if kind == 28 then
        return ipv6(self:chunk(start, 16)), start + 16
    end
    if kind == 2 or kind == 5 or kind == 12 then
        return self:name(start)
    end
    if kind == 15 then
        local preference = self:integer(start, 2)
        local name, after = self:name(start + 2)
        return preference .. " " .. name, after
    end
    if kind == 6 then
        local primary, after = self:name(start)
        local mailbox
        mailbox, after = self:name(after)
        local parts = {primary, mailbox}
        for _ = 1, 5 do
            parts[#parts + 1] = self:integer(after, 4)
            after = after + 4
        end
        return table.concat(parts, " "), after
    end
    return size .. " bytes", start + size
end
function Reader:record(position, section, layer)
    local name, after = self:name(position)
    local fixed = self:chunk(after, 10)
    local kind, class, ttl, size = network.integer(fixed, 0, 2), network.integer(fixed, 2, 2), network.integer(fixed, 4, 4), network.integer(fixed, 8, 2)
    local start = after + 10
    self:chunk(start, size)
    local body, finish = self:rdata(kind, start, size)
    if finish ~= start + size then
        error("dns: bad rdata length", 0)
    end
    local class_name = class == 1 and "IN" or "CLASS" .. class
    layer:add(section, table.concat({name, M.type_name(kind), class_name, ttl, body}, " "))
    if section == "dns.answer" then
        layer.answers[#layer.answers + 1] = M.type_name(kind) .. " " .. body
        if kind == 1 then
            layer:add("dns.a", self:integer(start, 4))
        end
    end
    return start + size
end
function M.dissect(data)
    local reader, layer = setmetatable({data = data}, Reader), network.layer()
    reader:chunk(0, 12)
    local flags, counts = reader:integer(2, 2), {}
    layer:set("dns.id", reader:integer(0, 2))
    layer:set("dns.flags", flags)
    layer:set("dns.flags.response", flags // 32768 % 2)
    layer:set("dns.flags.opcode", flags // 2048 % 16)
    layer:set("dns.flags.rcode", flags % 16)
    for i, name in ipairs({"queries", "answers", "auth_rr", "add_rr"}) do
        counts[i] = reader:integer(2 + 2 * i, 2)
        layer:set("dns.count." .. name, counts[i])
    end
    local position = 12
    for _ = 1, counts[1] do
        local name
        name, position = reader:name(position)
        local tail = reader:chunk(position, 4)
        layer:add("dns.qry.name", name)
        layer:add("dns.qry.type", network.integer(tail, 0, 2))
        position = position + 4
    end
    layer.answers = {}
    for i, section in ipairs({"dns.answer", "dns.authority", "dns.additional"}) do
        for _ = 1, counts[i + 1] do
            position = reader:record(position, section, layer)
        end
    end
    return layer
end
return M
