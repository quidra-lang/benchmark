local M = {}
local Packet = {}
Packet.__index = Packet
function Packet:set(name, value)
    self.fields[name] = {value}
end
function Packet:add(name, value)
    local values = self.fields[name] or {}
    values[#values + 1] = value
    self.fields[name] = values
end
function Packet:values(name)
    return self.fields[name] or {}
end
function Packet:value(name)
    return self.fields[name] and self.fields[name][1]
end
function Packet:exists(name)
    return self.fields[name] ~= nil
end
function M.read_lines(path)
    local file, result = assert(io.open(path)), {}
    for line in file:lines() do
        result[#result + 1] = line
    end
    file:close()
    return result
end
local function read_data(packet, lines)
    local pieces, count = {}, 0
    for _, row in ipairs(lines) do
        local offset, body = row.text:match("^([0-9a-f][0-9a-f][0-9a-f][0-9a-f])  (.+)$")
        local valid = body ~= nil and #body >= 2 and #body <= 47 and (#body + 1) % 3 == 0
        local bytes = {}
        if valid then
            for i = 1, #body, 3 do
                local value = body:sub(i, i + 1)
                if not value:match("^[0-9a-f][0-9a-f]$") or i + 2 <= #body and body:sub(i + 2, i + 2) ~= " " then
                    valid = false
                    break
                end
                bytes[#bytes + 1] = string.char(tonumber(value, 16))
            end
        end
        if not valid then
            packet.error = "dump: bad line " .. row.number
            return
        end
        if tonumber(offset, 16) ~= count then
            packet.error = "dump: offset mismatch at line " .. row.number
            return
        end
        local piece = table.concat(bytes)
        pieces[#pieces + 1], count = piece, count + #piece
    end
    if count ~= packet.length then
        packet.error = string.format("dump: length mismatch (header %d, data %d)", packet.length, count)
        return
    end
    packet.data = table.concat(pieces)
end
function M.read_capture(path)
    local packets, groups = {}, {}
    for number, line in ipairs(M.read_lines(path)) do
        if line:sub(1, 7) == "PACKET " then
            local id, time, length = line:match("^PACKET (%d+) (%d+) (%d+)$")
            packets[#packets + 1] = setmetatable({number = tonumber(id), time = tonumber(time), length = tonumber(length), data = "", fields = {}, layers = {}, remaining = ""}, Packet)
            groups[#groups + 1] = {}
        elseif line ~= "" then
            local group = groups[#groups]
            group[#group + 1] = {number = number, text = line}
        end
    end
    for i, packet in ipairs(packets) do
        read_data(packet, groups[i])
    end
    return packets
end
function M.hex_dump(data)
    local result = {}
    for offset = 0, #data - 1, 16 do
        local hex, characters = {}, {}
        for i = offset + 1, math.min(offset + 16, #data) do
            local value = data:byte(i)
            hex[#hex + 1] = string.format("%02x", value)
            characters[#characters + 1] = value >= 32 and value <= 126 and string.char(value) or "."
        end
        result[#result + 1] = string.format("%04x  %-47s  |%s|", offset, table.concat(hex, " "), table.concat(characters))
    end
    return result
end
return M
