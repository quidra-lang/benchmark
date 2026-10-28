local M = {marks = {"retransmission", "out_of_order", "lost_segment", "duplicate_ack"}}
function M.power2(exponent)
    local value = 1
    for _ = 1, exponent do
        value = value * 2
    end
    return value
end
local function endpoint(address, port)
    return {address = address, port = port}
end
local function endpoint_key(value)
    return value.address .. ":" .. (value.port or "")
end
local function pair_key(a, b)
    local first, second = endpoint_key(a), endpoint_key(b)
    if first > second then
        first, second = second, first
    end
    return first .. "|" .. second
end
local function side(name)
    return {name = name, intervals = {}, packets = 0, payload = 0, marks = {retransmission = 0, out_of_order = 0, lost_segment = 0, duplicate_ack = 0}}
end
local function record_syn(stream, sender, packet)
    sender.isn, sender.mss, sender.wscale = packet:value("tcp.seq_raw"), packet:value("tcp.options.mss"), packet:value("tcp.options.wscale")
    if sender.name == "client" then
        stream.syn = packet.number
    else
        stream.syn_ack = packet.number
    end
end
local Tracker = {}
Tracker.__index = Tracker
function M.tracker()
    return setmetatable({streams = {}, latest = {}, duplicates = {}}, Tracker)
end
function Tracker:track(packet)
    local source = endpoint(packet:value("ip.src"), packet:value("tcp.srcport"))
    local destination = endpoint(packet:value("ip.dst"), packet:value("tcp.dstport"))
    local seq, ack, window, size = packet:value("tcp.seq_raw"), packet:value("tcp.ack_raw"), packet:value("tcp.window"), packet:value("tcp.len")
    local syn, fin, rst, has_ack = packet:value("tcp.flags.syn") == 1, packet:value("tcp.flags.fin") == 1, packet:value("tcp.flags.rst") == 1, packet:value("tcp.flags.ack") == 1
    local key = pair_key(source, destination)
    local stream = self.latest[key]
    if not stream or (stream.state == "CLOSED" or stream.state == "RESET") and syn and not has_ack then
        local state, client, server = "ESTABLISHED", source, destination
        if syn and has_ack then
            state, client, server = "SYN_RECEIVED", destination, source
        elseif syn then
            state = "SYN_SENT"
        end
        stream = {number = #self.streams, client = client, server = server, state = state, history = {{state, packet.number}}, start = packet.time, finish = packet.time, packets = 0, bytes = 0, events = {}, client_side = side("client"), server_side = side("server")}
        if syn then
            record_syn(stream, has_ack and stream.server_side or stream.client_side, packet)
        end
        self.streams[#self.streams + 1], self.latest[key] = stream, stream
    end
    local sender, other = stream.client_side, stream.server_side
    if endpoint_key(source) ~= endpoint_key(stream.client) then
        sender, other = other, sender
    end
    packet:set("tcp.stream", stream.number)
    if sender.base == nil then
        sender.base = seq
    end
    if has_ack and other.base == nil then
        other.base = ack
    end
    local relative = (seq - sender.base) % 4294967296
    packet:set("tcp.seq", relative)
    if has_ack then
        packet:set("tcp.ack", (ack - other.base) % 4294967296)
    end
    local span, mark = size + (syn and 1 or 0) + (fin and 1 or 0), nil
    if span > 0 then
        local interval = relative .. "," .. span
        if sender.expected ~= nil and relative ~= sender.expected then
            if relative > sender.expected then
                mark = "lost_segment"
            elseif sender.intervals[interval] then
                mark = "retransmission"
            elseif packet.time - sender.advanced_at < 3000 then
                mark = "out_of_order"
            else
                mark = "retransmission"
            end
        end
        sender.intervals[interval] = true
        if sender.expected == nil or relative + span > sender.expected then
            sender.expected, sender.advanced_at = relative + span, packet.time
        end
    elseif has_ack and not rst then
        local previous = sender.previous_ack
        if previous and previous.ack == ack and previous.window == window then
            mark, previous.count = "duplicate_ack", previous.count + 1
            self.duplicates[packet.number] = {previous.number, previous.count}
        end
    end
    if has_ack and mark ~= "duplicate_ack" then
        sender.previous_ack = {ack = ack, window = window, number = packet.number, count = 0}
    end
    if mark then
        packet:set("tcp.analysis." .. mark, true)
        sender.marks[mark] = sender.marks[mark] + 1
        stream.events[#stream.events + 1] = {packet.number, sender.name, mark, relative, span}
    end
    local calculated = window
    if stream.client_side.wscale ~= nil and stream.server_side.wscale ~= nil and not syn then
        calculated = window * M.power2(sender.wscale)
    end
    packet:set("tcp.window.calc", calculated)
    local old = stream.state
    if rst then
        if old ~= "CLOSED" and old ~= "RESET" then
            stream.state = "RESET"
        end
    elseif old == "SYN_SENT" and sender.name == "server" and syn and has_ack and ack == (stream.client_side.isn + 1) % 4294967296 then
        stream.state = "SYN_RECEIVED"
        record_syn(stream, stream.server_side, packet)
    elseif old == "SYN_RECEIVED" and sender.name == "client" and has_ack and not syn and ack == (stream.server_side.isn + 1) % 4294967296 then
        stream.state, stream.handshake_ack = "ESTABLISHED", packet.number
    elseif old == "ESTABLISHED" and fin then
        stream.state, stream.closer = "FIN_WAIT", sender.name
    elseif old == "FIN_WAIT" and fin and sender.name ~= stream.closer then
        stream.state, stream.final_ack = "CLOSING", (seq + size + 1) % 4294967296
    elseif old == "CLOSING" and sender.name == stream.closer and has_ack and ack == stream.final_ack then
        stream.state = "CLOSED"
    end
    if stream.state ~= old then
        stream.history[#stream.history + 1] = {stream.state, packet.number}
    end
    sender.packets, sender.payload = sender.packets + 1, sender.payload + size
    stream.packets, stream.bytes, stream.finish = stream.packets + 1, stream.bytes + packet.length, packet.time
end
local function totals(row)
    row.packets = row.packets_a_to_b + row.packets_b_to_a
    row.bytes = row.bytes_a_to_b + row.bytes_b_to_a
end
function M.conversations(packets)
    local result, by_key = {}, {}
    for _, packet in ipairs(packets) do
        if packet:exists("ip.src") then
            local a, b = packet:value("ip.src"), packet:value("ip.dst")
            local views = {{kind = "ipv4", source = endpoint(a), destination = endpoint(b)}}
            if packet:exists("tcp.stream") then
                views[#views + 1] = {kind = "tcp", key = tostring(packet:value("tcp.stream")), source = endpoint(a, packet:value("tcp.srcport")), destination = endpoint(b, packet:value("tcp.dstport"))}
            end
            if packet:exists("udp.srcport") then
                views[#views + 1] = {kind = "udp", source = endpoint(a, packet:value("udp.srcport")), destination = endpoint(b, packet:value("udp.dstport"))}
            end
            for _, view in ipairs(views) do
                local key = view.kind .. "|" .. (view.key or pair_key(view.source, view.destination))
                local row = by_key[key]
                if not row then
                    row = {kind = view.kind, source = view.source, destination = view.destination, first = packet.number, start = packet.time, finish = packet.time, packets_a_to_b = 0, bytes_a_to_b = 0, packets_b_to_a = 0, bytes_b_to_a = 0}
                    result[#result + 1], by_key[key] = row, row
                end
                local direction = endpoint_key(view.source) == endpoint_key(row.source) and "a_to_b" or "b_to_a"
                row["packets_" .. direction] = row["packets_" .. direction] + 1
                row["bytes_" .. direction] = row["bytes_" .. direction] + packet.length
                row.finish = packet.time
                totals(row)
            end
        end
    end
    local kinds = {ipv4 = 1, tcp = 2, udp = 3}
    table.sort(result, function(a, b)
        if a.bytes ~= b.bytes then
            return a.bytes > b.bytes
        end
        if a.packets ~= b.packets then
            return a.packets > b.packets
        end
        if a.kind ~= b.kind then
            return kinds[a.kind] < kinds[b.kind]
        end
        return a.first < b.first
    end)
    return result
end
function M.endpoints(packets)
    local by_ip = {}
    local function entry(address)
        if not by_ip[address] then
            by_ip[address] = {address = address, tx_packets = 0, tx_bytes = 0, rx_packets = 0, rx_bytes = 0}
        end
        return by_ip[address]
    end
    for _, packet in ipairs(packets) do
        if packet:exists("ip.src") then
            local a, b = entry(packet:value("ip.src")), entry(packet:value("ip.dst"))
            a.tx_packets, a.tx_bytes = a.tx_packets + 1, a.tx_bytes + packet.length
            b.rx_packets, b.rx_bytes = b.rx_packets + 1, b.rx_bytes + packet.length
        end
    end
    local result = {}
    for _, row in pairs(by_ip) do
        row.packets, row.bytes = row.tx_packets + row.rx_packets, row.tx_bytes + row.rx_bytes
        result[#result + 1] = row
    end
    table.sort(result, function(a, b)
        if a.bytes ~= b.bytes then
            return a.bytes > b.bytes
        end
        if a.packets ~= b.packets then
            return a.packets > b.packets
        end
        return a.address < b.address
    end)
    return result
end
return M
