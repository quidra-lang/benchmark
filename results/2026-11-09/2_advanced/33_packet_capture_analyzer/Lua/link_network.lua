local M = {}
local Layer = {}
Layer.__index = Layer
function M.layer()
    return setmetatable({fields = {}, remaining = ""}, Layer)
end
function Layer:set(name, value)
    self.fields[name] = {value}
end
function Layer:add(name, value)
    self.fields[name] = self.fields[name] or {}
    local values = self.fields[name]
    values[#values + 1] = value
end
function Layer:forward(name, payload)
    self.next_layer, self.payload = name, payload
end
function M.integer(data, offset, size)
    local result = 0
    for i = offset + 1, offset + size do
        result = result * 256 + data:byte(i)
    end
    return result
end
function M.bytes(value, size)
    local result = {}
    for i = size, 1, -1 do
        result[i], value = string.char(value % 256), value // 256
    end
    return table.concat(result)
end
function M.checksum(data)
    local total = 0
    for i = 1, #data, 2 do
        total = total + data:byte(i) * 256 + (data:byte(i + 1) or 0)
    end
    while total > 65535 do
        total = total % 65536 + total // 65536
    end
    return total == 65535 and "good" or "bad"
end
function M.mac(value)
    local bytes, parts = M.bytes(value, 6), {}
    for i = 1, 6 do
        parts[i] = string.format("%02x", bytes:byte(i))
    end
    return table.concat(parts, ":")
end
function M.ipv4(value)
    local bytes, parts = M.bytes(value, 4), {}
    for i = 1, 4 do
        parts[i] = bytes:byte(i)
    end
    return table.concat(parts, ".")
end
function M.ethernet(data)
    if #data < 14 then
        error("eth: truncated", 0)
    end
    local layer, kind = M.layer(), M.integer(data, 12, 2)
    layer:set("eth.dst", M.integer(data, 0, 6))
    layer:set("eth.src", M.integer(data, 6, 6))
    layer:set("eth.type", kind)
    if kind == 2054 then
        layer:forward("arp", data:sub(15))
    elseif kind == 2048 then
        layer:forward("ip", data:sub(15))
    else
        layer.remaining = data:sub(15)
    end
    return layer
end
function M.arp(data)
    if #data < 28 then
        error("arp: truncated", 0)
    end
    if M.integer(data, 0, 2) ~= 1 or M.integer(data, 2, 2) ~= 2048 or data:byte(5) ~= 6 or data:byte(6) ~= 4 then
        error("arp: unsupported format", 0)
    end
    local layer = M.layer()
    for _, item in ipairs({{"opcode", 6, 2}, {"src.hw", 8, 6}, {"src.ip", 14, 4}, {"dst.hw", 18, 6}, {"dst.ip", 24, 4}}) do
        layer:set("arp." .. item[1], M.integer(data, item[2], item[3]))
    end
    return layer
end
function M.ipv4_layer(data)
    if #data < 20 then
        error("ip: truncated header", 0)
    end
    local version, header = data:byte(1) // 16, data:byte(1) % 16 * 4
    if version ~= 4 then
        error("ip: bad version " .. version, 0)
    end
    if header < 20 then
        error("ip: bad header length " .. header, 0)
    end
    if #data < header then
        error("ip: truncated header", 0)
    end
    local total = M.integer(data, 2, 2)
    if total < header then
        error("ip: bad total length " .. total, 0)
    end
    if total > #data then
        error(string.format("ip: truncated (total length %d, available %d)", total, #data), 0)
    end
    local flags, protocol, layer = M.integer(data, 6, 2), data:byte(10), M.layer()
    layer:set("ip.hdr_len", header)
    layer:set("ip.tos", data:byte(2))
    layer:set("ip.len", total)
    layer:set("ip.id", M.integer(data, 4, 2))
    layer:set("ip.flags.df", flags // 16384 % 2)
    layer:set("ip.flags.mf", flags // 8192 % 2)
    layer:set("ip.frag_offset", flags % 8192 * 8)
    layer:set("ip.ttl", data:byte(9))
    layer:set("ip.proto", protocol)
    layer:set("ip.checksum", M.integer(data, 10, 2))
    layer:set("ip.checksum.status", M.checksum(data:sub(1, header)))
    layer:set("ip.src", M.integer(data, 12, 4))
    layer:set("ip.dst", M.integer(data, 16, 4))
    local payload = data:sub(header + 1, total)
    if flags // 8192 % 2 == 1 or flags % 8192 ~= 0 then
        layer:set("ip.fragment", true)
        layer.remaining = payload
    else
        local next_layer = ({[1] = "icmp", [17] = "udp", [6] = "tcp"})[protocol]
        if next_layer then
            layer:forward(next_layer, payload)
        else
            layer.remaining = payload
        end
    end
    return layer
end
return M
