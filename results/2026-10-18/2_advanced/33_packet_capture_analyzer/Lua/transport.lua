local network = require("link_network")
local M = {}
local integer, layer = network.integer, network.layer
local function pseudo(source, destination, protocol, size)
    return network.bytes(source, 4) .. network.bytes(destination, 4) .. string.char(0, protocol) .. network.bytes(size, 2)
end
function M.icmp(data)
    if #data < 8 then
        error("icmp: truncated", 0)
    end
    local result, kind = layer(), data:byte(1)
    result:set("icmp.type", kind)
    result:set("icmp.code", data:byte(2))
    result:set("icmp.checksum", integer(data, 2, 2))
    result:set("icmp.checksum.status", network.checksum(data))
    if kind == 0 or kind == 8 then
        result:set("icmp.id", integer(data, 4, 2))
        result:set("icmp.seq", integer(data, 6, 2))
    end
    result.remaining = data:sub(9)
    return result
end
function M.udp(data, source, destination)
    if #data < 8 then
        error("udp: truncated", 0)
    end
    local size = integer(data, 4, 2)
    if size < 8 or size > #data then
        error("udp: bad length " .. size, 0)
    end
    local result, first, second, checksum = layer(), integer(data, 0, 2), integer(data, 2, 2), integer(data, 6, 2)
    result:set("udp.srcport", first)
    result:set("udp.dstport", second)
    result:set("udp.length", size)
    result:set("udp.checksum", checksum)
    result:set("udp.checksum.status", checksum == 0 and "none" or network.checksum(pseudo(source, destination, 17, size) .. data:sub(1, size)))
    if first == 53 or second == 53 then
        result:forward("dns", data:sub(9, size))
    else
        result.remaining = data:sub(9, size)
    end
    return result
end
local option_lengths = {[2] = {[4] = true}, [3] = {[3] = true}, [4] = {[2] = true}, [5] = {[10] = true, [18] = true, [26] = true, [34] = true}, [8] = {[10] = true}}
local function options(data, result)
    local index = 1
    while index <= #data do
        local kind = data:byte(index)
        if kind == 0 then
            result:add("tcp.option", "EOL")
            return
        end
        if kind == 1 then
            result:add("tcp.option", "NOP")
            index = index + 1
        else
            local size = data:byte(index + 1) or 0
            if size < 2 or index + size - 1 > #data or option_lengths[kind] and not option_lengths[kind][size] then
                result:set("tcp.options.malformed", true)
                return
            end
            local body, text = data:sub(index + 2, index + size - 1), "kind " .. kind .. " len " .. size
            if kind == 2 then
                local value = integer(body, 0, 2)
                result:set("tcp.options.mss", value)
                text = "MSS " .. value
            elseif kind == 3 then
                result:set("tcp.options.wscale", body:byte(1))
                text = "WS " .. body:byte(1)
            elseif kind == 4 then
                text = "SACK_PERM"
            elseif kind == 5 then
                local pieces = {"SACK"}
                for offset = 0, #body - 1, 8 do
                    pieces[#pieces + 1] = " " .. integer(body, offset, 4) .. "-" .. integer(body, offset + 4, 4)
                end
                text = table.concat(pieces)
            elseif kind == 8 then
                text = "TS " .. integer(body, 0, 4) .. " " .. integer(body, 4, 4)
            end
            result:add("tcp.option", text)
            index = index + size
        end
    end
end
function M.tcp(data, source, destination)
    if #data < 20 then
        error("tcp: truncated header", 0)
    end
    local header = data:byte(13) // 16 * 4
    if header < 20 then
        error("tcp: bad header length " .. header, 0)
    end
    if header > #data then
        error("tcp: truncated header", 0)
    end
    local result, flags = layer(), data:byte(14)
    result:set("tcp.srcport", integer(data, 0, 2))
    result:set("tcp.dstport", integer(data, 2, 2))
    result:set("tcp.seq_raw", integer(data, 4, 4))
    result:set("tcp.hdr_len", header)
    result:set("tcp.flags", flags)
    local bit = 1
    for _, name in ipairs({"fin", "syn", "rst", "psh", "ack", "urg"}) do
        result:set("tcp.flags." .. name, flags // bit % 2)
        bit = bit * 2
    end
    result:set("tcp.window", integer(data, 14, 2))
    result:set("tcp.checksum", integer(data, 16, 2))
    result:set("tcp.checksum.status", network.checksum(pseudo(source, destination, 6, #data) .. data))
    result:set("tcp.urgent", integer(data, 18, 2))
    result:set("tcp.len", #data - header)
    if flags // 16 % 2 == 1 then
        result:set("tcp.ack_raw", integer(data, 8, 4))
    end
    options(data:sub(21, header), result)
    result.remaining = data:sub(header + 1)
    return result
end
return M
