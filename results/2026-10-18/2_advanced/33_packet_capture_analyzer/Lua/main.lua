local hexdump = require("hexdump")
local network = require("link_network")
local transport = require("transport")
local dns = require("dns_app")
local flows = require("flows")
local fields = {
    {"frame.number", "integer"},
    {"frame.time", "integer"},
    {"frame.len", "integer"},
    {"frame.protocols", "string"},
    {"frame.malformed", "string"},
    {"frame.bad_checksum", "presence"},
    {"eth.dst", "mac"},
    {"eth.src", "mac"},
    {"eth.type", "hex4"},
    {"arp.opcode", "integer"},
    {"arp.src.hw", "mac"},
    {"arp.src.ip", "ipv4"},
    {"arp.dst.hw", "mac"},
    {"arp.dst.ip", "ipv4"},
    {"ip.hdr_len", "integer"},
    {"ip.tos", "hex2"},
    {"ip.len", "integer"},
    {"ip.id", "hex4"},
    {"ip.flags.df", "integer"},
    {"ip.flags.mf", "integer"},
    {"ip.frag_offset", "integer"},
    {"ip.ttl", "integer"},
    {"ip.proto", "integer"},
    {"ip.checksum", "hex4"},
    {"ip.checksum.status", "string"},
    {"ip.src", "ipv4"},
    {"ip.dst", "ipv4"},
    {"ip.fragment", "presence"},
    {"icmp.type", "integer"},
    {"icmp.code", "integer"},
    {"icmp.checksum", "hex4"},
    {"icmp.checksum.status", "string"},
    {"icmp.id", "integer"},
    {"icmp.seq", "integer"},
    {"udp.srcport", "integer"},
    {"udp.dstport", "integer"},
    {"udp.length", "integer"},
    {"udp.checksum", "hex4"},
    {"udp.checksum.status", "string"},
    {"tcp.srcport", "integer"},
    {"tcp.dstport", "integer"},
    {"tcp.stream", "integer"},
    {"tcp.seq", "integer"},
    {"tcp.seq_raw", "integer"},
    {"tcp.ack", "integer"},
    {"tcp.ack_raw", "integer"},
    {"tcp.hdr_len", "integer"},
    {"tcp.flags", "hex2"},
    {"tcp.flags.fin", "integer"},
    {"tcp.flags.syn", "integer"},
    {"tcp.flags.rst", "integer"},
    {"tcp.flags.psh", "integer"},
    {"tcp.flags.ack", "integer"},
    {"tcp.flags.urg", "integer"},
    {"tcp.window", "integer"},
    {"tcp.window.calc", "integer"},
    {"tcp.checksum", "hex4"},
    {"tcp.checksum.status", "string"},
    {"tcp.urgent", "integer"},
    {"tcp.option", "string"},
    {"tcp.options.mss", "integer"},
    {"tcp.options.wscale", "integer"},
    {"tcp.options.malformed", "presence"},
    {"tcp.len", "integer"},
    {"tcp.analysis.retransmission", "presence"},
    {"tcp.analysis.out_of_order", "presence"},
    {"tcp.analysis.lost_segment", "presence"},
    {"tcp.analysis.duplicate_ack", "presence"},
    {"dns.id", "hex4"},
    {"dns.flags", "hex4"},
    {"dns.flags.response", "integer"},
    {"dns.flags.opcode", "integer"},
    {"dns.flags.rcode", "integer"},
    {"dns.count.queries", "integer"},
    {"dns.count.answers", "integer"},
    {"dns.count.auth_rr", "integer"},
    {"dns.count.add_rr", "integer"},
    {"dns.qry.name", "string"},
    {"dns.qry.type", "integer"},
    {"dns.answer", "string"},
    {"dns.authority", "string"},
    {"dns.additional", "string"},
    {"dns.a", "ipv4"},
    {"data.len", "integer"},
}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function line(...)
    return table.concat({...}, " ")
end
local function seconds(value)
    return string.format("%d.%06d", value // 1000000, value % 1000000)
end
local function optional(value)
    return value == nil and "-" or tostring(value)
end
local function notation(kind, value)
    if kind == "hex2" then
        return string.format("0x%02x", value)
    end
    if kind == "hex4" then
        return string.format("0x%04x", value)
    end
    if kind == "ipv4" then
        return network.ipv4(value)
    end
    if kind == "mac" then
        return network.mac(value)
    end
    return tostring(value)
end
local types = {}
for _, field in ipairs(fields) do
    types[field[1]] = field[2]
end
local aliases = {["eth.addr"] = {"mac", "eth.dst", "eth.src"}, ["ip.addr"] = {"ipv4", "ip.src", "ip.dst"}, ["udp.port"] = {"integer", "udp.srcport", "udp.dstport"}, ["tcp.port"] = {"integer", "tcp.srcport", "tcp.dstport"}}
local protocols = {eth = true, arp = true, ip = true, icmp = true, udp = true, tcp = true, dns = true, data = true}
local labels = {eth = "ETH", arp = "ARP", ip = "IPv4", icmp = "ICMP", udp = "UDP", tcp = "TCP", dns = "DNS"}
local checksums = {{"ip", "IPv4"}, {"icmp", "ICMP"}, {"udp", "UDP"}, {"tcp", "TCP"}}
local function field_type(name)
    return types[name] or aliases[name] and aliases[name][1] or protocols[name] and "presence"
end
local function values(packet, name)
    local alias = aliases[name]
    if not alias then
        return packet:values(name)
    end
    local result = {}
    append(result, packet:values(alias[2]))
    append(result, packet:values(alias[3]))
    return result
end
local function shown(packet, name)
    return notation(types[name], packet:value(name))
end
local function dissect_layer(packet, name, data)
    if name == "eth" then
        return network.ethernet(data)
    end
    if name == "arp" then
        return network.arp(data)
    end
    if name == "ip" then
        return network.ipv4_layer(data)
    end
    if name == "icmp" then
        return transport.icmp(data)
    end
    if name == "udp" then
        return transport.udp(data, packet:value("ip.src"), packet:value("ip.dst"))
    end
    if name == "tcp" then
        return transport.tcp(data, packet:value("ip.src"), packet:value("ip.dst"))
    end
    return dns.dissect(data)
end
local function dissect(packet, base_time)
    local reason = packet.error
    if not reason then
        local name, payload = "eth", packet.data
        while true do
            packet.layers[#packet.layers + 1] = name
            local success, layer = pcall(dissect_layer, packet, name, payload)
            if not success then
                reason = layer
                break
            end
            for key, value in pairs(layer.fields) do
                packet.fields[key] = value
            end
            if name == "dns" then
                packet.answers = layer.answers
            end
            if not layer.next_layer then
                packet.remaining = layer.remaining
                break
            end
            name, payload = layer.next_layer, layer.payload
        end
    end
    if not reason and #packet.remaining > 0 then
        packet.layers[#packet.layers + 1] = "data"
        packet:set("data.len", #packet.remaining)
    end
    packet:set("frame.number", packet.number)
    packet:set("frame.time", packet.time - base_time)
    packet:set("frame.len", packet.length)
    if #packet.layers > 0 then
        packet:set("frame.protocols", table.concat(packet.layers, ":"))
    end
    if reason then
        packet:set("frame.malformed", reason)
        packet.remaining = ""
    end
    for _, item in ipairs(checksums) do
        if packet:value(item[1] .. ".checksum.status") == "bad" then
            packet:set("frame.bad_checksum", true)
        end
    end
end
local function contains(items, value)
    for _, item in ipairs(items) do
        if item == value then
            return true
        end
    end
    return false
end
local function mark_text(packet, tracker)
    if packet:exists("tcp.analysis.duplicate_ack") then
        local duplicate = tracker.duplicates[packet.number]
        return "[TCP Dup ACK " .. duplicate[1] .. "#" .. duplicate[2] .. "] "
    end
    for _, mark in ipairs({{"retransmission", "[TCP Retransmission] "}, {"out_of_order", "[TCP Out-Of-Order] "}, {"lost_segment", "[TCP Previous segment not captured] "}}) do
        if packet:exists("tcp.analysis." .. mark[1]) then
            return mark[2]
        end
    end
    return ""
end
local function tcp_info(packet, tracker)
    local flags, bit = {}, 1
    for _, name in ipairs({"FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"}) do
        if packet:value("tcp.flags") // bit % 2 == 1 then
            flags[#flags + 1] = name
        end
        bit = bit * 2
    end
    local flag_text = #flags == 0 and "<None>" or table.concat(flags, ", ")
    local text = mark_text(packet, tracker) .. packet:value("tcp.srcport") .. " -> " .. packet:value("tcp.dstport") .. " [" .. flag_text .. "] Seq=" .. packet:value("tcp.seq")
    if packet:value("tcp.flags.ack") == 1 then
        text = text .. " Ack=" .. packet:value("tcp.ack")
    end
    text = text .. " Win=" .. packet:value("tcp.window.calc") .. " Len=" .. packet:value("tcp.len")
    for _, option in ipairs(packet:values("tcp.option")) do
        local mss = option:match("^MSS (%d+)$")
        local scale = option:match("^WS (%d+)$")
        local first, second = option:match("^TS (%d+) (%d+)$")
        if mss then
            text = text .. " MSS=" .. mss
        elseif scale then
            text = text .. " WS=" .. flows.power2(tonumber(scale))
        elseif option == "SACK_PERM" then
            text = text .. " SACK_PERM"
        elseif first then
            text = text .. " TSval=" .. first .. " TSecr=" .. second
        end
    end
    return text
end
local function basic_info(packet, protocol, tracker)
    if packet:exists("frame.malformed") then
        return packet:value("frame.malformed")
    end
    if protocol == "ETH" then
        return "EtherType " .. shown(packet, "eth.type")
    end
    if protocol == "ARP" then
        local opcode = packet:value("arp.opcode")
        if opcode == 1 then
            return "Who has " .. shown(packet, "arp.dst.ip") .. "? Tell " .. shown(packet, "arp.src.ip")
        end
        if opcode == 2 then
            return shown(packet, "arp.src.ip") .. " is at " .. shown(packet, "arp.src.hw")
        end
        return "Opcode " .. opcode
    end
    if protocol == "IPv4" then
        if not packet:exists("ip.fragment") then
            return "Protocol " .. packet:value("ip.proto")
        end
        return "Fragment id=" .. shown(packet, "ip.id") .. " off=" .. packet:value("ip.frag_offset") .. (packet:value("ip.flags.mf") == 1 and " MF" or "")
    end
    if protocol == "ICMP" then
        local kind = packet:value("icmp.type")
        if kind == 0 or kind == 8 then
            return (kind == 8 and "Echo request" or "Echo reply") .. " id=" .. packet:value("icmp.id") .. " seq=" .. packet:value("icmp.seq")
        end
        return "Type " .. kind .. " code " .. packet:value("icmp.code")
    end
    if protocol == "UDP" then
        return packet:value("udp.srcport") .. " -> " .. packet:value("udp.dstport") .. " Len=" .. (packet:value("udp.length") - 8)
    end
    if protocol == "TCP" then
        return tcp_info(packet, tracker)
    end
    local parts = {packet:value("dns.flags.response") == 1 and "Response" or "Query", shown(packet, "dns.id")}
    local rcode = packet:value("dns.flags.rcode")
    if rcode ~= 0 then
        parts[#parts + 1] = dns.rcode_name(rcode)
    end
    for i, name in ipairs(packet:values("dns.qry.name")) do
        parts[#parts + 1] = dns.type_name(packet:values("dns.qry.type")[i])
        parts[#parts + 1] = name
    end
    append(parts, packet.answers)
    return table.concat(parts, " ")
end
local function summary(packet, tracker)
    local source, destination, protocol = "-", "-", "DUMP"
    if packet:exists("ip.src") then
        source, destination = shown(packet, "ip.src"), shown(packet, "ip.dst")
    elseif packet:exists("eth.src") then
        source, destination = shown(packet, "eth.src"), shown(packet, "eth.dst")
    end
    for _, name in ipairs(packet.layers) do
        if name ~= "data" then
            protocol = labels[name]
        end
    end
    local info = basic_info(packet, protocol, tracker)
    if packet:exists("tcp.options.malformed") then
        info = info .. " [bad TCP options]"
    end
    for _, item in ipairs(checksums) do
        if packet:value(item[1] .. ".checksum.status") == "bad" then
            info = info .. " [bad " .. item[2] .. " checksum]"
        end
    end
    return line(packet.number, seconds(packet:value("frame.time")), source, "->", destination, protocol, packet.length, info)
end
local comparison_operators = {["=="] = true, ["!="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true}
local function tokenize(expression)
    local tokens, index = {}, 1
    while index <= #expression do
        local character, column, pair = expression:sub(index, index), index, expression:sub(index, index + 1)
        if character == " " then
            index = index + 1
        else
            local kind, text
            if comparison_operators[pair] or pair == "&&" or pair == "||" then
                kind, text, index = pair, pair, index + 2
            elseif character == "(" or character == ")" or character == "!" or character == "<" or character == ">" then
                kind, text, index = character, character, index + 1
            elseif character == '"' then
                local last = expression:find('"', index + 1, true)
                if not last then
                    error("unterminated string at column " .. column, 0)
                end
                kind, text, index = "string", expression:sub(index, last), last + 1
            elseif character:match("[A-Za-z0-9._:]") then
                local last = index
                while last <= #expression and expression:sub(last, last):match("[A-Za-z0-9._:]") do
                    last = last + 1
                end
                text = expression:sub(index, last - 1)
                kind, index = ({["and"] = "&&", ["or"] = "||", ["not"] = "!"})[text] or "word", last
            else
                error("invalid character '" .. character .. "' at column " .. column, 0)
            end
            tokens[#tokens + 1] = {kind = kind, text = text, column = column}
        end
    end
    return tokens
end
local function converted(kind, token)
    if kind == "string" then
        return token.kind == "string" and token.text:sub(2, -2) or nil
    end
    if token.kind ~= "word" then
        return nil
    end
    local text = token.text
    if kind == "integer" or kind == "hex2" or kind == "hex4" then
        if #text >= 1 and #text <= 15 and text:match("^%d+$") then
            return tonumber(text)
        end
        local hex = text:match("^0x([0-9a-fA-F]+)$")
        if hex and #hex <= 12 then
            return tonumber(hex, 16)
        end
        return nil
    end
    local parts, separator = {}, kind == "ipv4" and "." or ":"
    local start = 1
    while true do
        local ending = text:find(separator, start, true)
        parts[#parts + 1] = ending and text:sub(start, ending - 1) or text:sub(start)
        if not ending then
            break
        end
        start = ending + 1
    end
    if #parts ~= (kind == "ipv4" and 4 or 6) then
        return nil
    end
    local value = 0
    for _, part in ipairs(parts) do
        local byte
        if kind == "ipv4" then
            if #part < 1 or #part > 3 or not part:match("^%d+$") then
                return nil
            end
            byte = tonumber(part)
            if byte > 255 then
                return nil
            end
        else
            if #part ~= 2 or not part:match("^[0-9a-fA-F][0-9a-fA-F]$") then
                return nil
            end
            byte = tonumber(part, 16)
        end
        value = value * 256 + byte
    end
    return value
end
local function parse_filter(expression)
    local tokens, index = tokenize(expression), 1
    local parse_expression, parse_product, parse_negation
    local function next_kind()
        return tokens[index] and tokens[index].kind
    end
    local function take()
        if not tokens[index] then
            error("unexpected end of filter", 0)
        end
        local token = tokens[index]
        index = index + 1
        return token
    end
    local function unexpected(token)
        error("unexpected '" .. token.text .. "' at column " .. token.column, 0)
    end
    local function test(name)
        local kind = field_type(name)
        if not kind then
            error("unknown field " .. name, 0)
        end
        if not comparison_operators[next_kind()] then
            return {kind = "exists", field = name}
        end
        local operator = take().kind
        if kind == "presence" or kind == "string" and operator ~= "==" and operator ~= "!=" then
            error("operator " .. operator .. " not allowed for " .. name, 0)
        end
        local token = take()
        if token.kind ~= "word" and token.kind ~= "string" then
            unexpected(token)
        end
        local value = converted(kind, token)
        if value == nil then
            error("invalid value " .. token.text .. " for " .. name, 0)
        end
        return {kind = "compare", field = name, operator = operator, value = value}
    end
    parse_negation = function()
        if next_kind() == "!" then
            take()
            return {kind = "not", left = parse_negation()}
        end
        local token = take()
        if token.kind == "(" then
            local node = parse_expression()
            local close = take()
            if close.kind ~= ")" then
                unexpected(close)
            end
            return node
        end
        if token.kind == "word" then
            return test(token.text)
        end
        unexpected(token)
    end
    parse_product = function()
        local node = parse_negation()
        while next_kind() == "&&" do
            take()
            node = {kind = "and", left = node, right = parse_negation()}
        end
        return node
    end
    parse_expression = function()
        local node = parse_product()
        while next_kind() == "||" do
            take()
            node = {kind = "or", left = node, right = parse_product()}
        end
        return node
    end
    local tree = parse_expression()
    if tokens[index] then
        unexpected(tokens[index])
    end
    return tree
end
local function compare(a, operator, b)
    if operator == "==" then
        return a == b
    end
    if operator == "<" then
        return a < b
    end
    if operator == ">" then
        return a > b
    end
    if operator == "<=" then
        return a <= b
    end
    return a >= b
end
local function evaluate(node, packet)
    if node.kind == "and" then
        return evaluate(node.left, packet) and evaluate(node.right, packet)
    end
    if node.kind == "or" then
        return evaluate(node.left, packet) or evaluate(node.right, packet)
    end
    if node.kind == "not" then
        return not evaluate(node.left, packet)
    end
    if node.kind == "exists" and protocols[node.field] then
        return contains(packet.layers, node.field)
    end
    local candidates = values(packet, node.field)
    if node.kind == "exists" then
        return #candidates > 0
    end
    if #candidates == 0 then
        return false
    end
    if node.operator == "!=" then
        for _, value in ipairs(candidates) do
            if value == node.value then
                return false
            end
        end
        return true
    end
    for _, value in ipairs(candidates) do
        if compare(value, node.operator, node.value) then
            return true
        end
    end
    return false
end
local function detail(packet, number)
    if not packet then
        return {"packet " .. number .. " not found"}
    end
    local lines, layers = {"packet " .. number}, {"frame"}
    append(layers, packet.layers)
    for _, name in ipairs(layers) do
        lines[#lines + 1] = name
        for _, field in ipairs(fields) do
            if field[1]:sub(1, #name + 1) == name .. "." then
                for _, value in ipairs(packet:values(field[1])) do
                    lines[#lines + 1] = "  " .. field[1] .. (field[2] == "presence" and "" or " = " .. notation(field[2], value))
                end
            end
        end
        if name == "data" then
            for _, text in ipairs(hexdump.hex_dump(packet.remaining)) do
                lines[#lines + 1] = "  " .. text
            end
        end
    end
    return lines
end
local function dns_transactions(packets)
    local result, pending = {queries = {}, responses = {}, times = {}}, {}
    for _, packet in ipairs(packets) do
        if packet:exists("dns.id") then
            if packet:value("dns.flags.response") == 0 then
                result.queries[#result.queries + 1], pending[#pending + 1] = packet, packet
            else
                result.responses[#result.responses + 1] = packet
                for index, query in ipairs(pending) do
                    if query:value("dns.id") == packet:value("dns.id") and query:value("ip.src") == packet:value("ip.dst") and query:value("udp.srcport") == packet:value("udp.dstport") and query:value("ip.dst") == packet:value("ip.src") and query:value("udp.dstport") == packet:value("udp.srcport") then
                        result.times[#result.times + 1] = packet.time - query.time
                        table.remove(pending, index)
                        break
                    end
                end
            end
        end
    end
    result.unanswered = #pending
    return result
end
local function protocol_statistics(packets, transactions)
    local total_bytes = 0
    for _, packet in ipairs(packets) do
        total_bytes = total_bytes + packet.length
    end
    local lines = {line("packets", #packets), line("bytes", total_bytes), line("duration", seconds(packets[#packets].time - packets[1].time)), "hierarchy"}
    for _, row in ipairs({{"eth", 0}, {"arp", 2}, {"ip", 2}, {"icmp", 4}, {"udp", 4}, {"dns", 6}, {"tcp", 4}}) do
        local count, bytes = 0, 0
        for _, packet in ipairs(packets) do
            if contains(packet.layers, row[1]) then
                count, bytes = count + 1, bytes + packet.length
            end
        end
        lines[#lines + 1] = string.rep(" ", row[2]) .. line(row[1], count, bytes)
    end
    lines[#lines + 1] = "checksums"
    for _, row in ipairs(checksums) do
        local counts = {good = 0, bad = 0, none = 0}
        for _, packet in ipairs(packets) do
            local status = packet:value(row[1] .. ".checksum.status")
            if status then
                counts[status] = counts[status] + 1
            end
        end
        lines[#lines + 1] = line(row[1], "good", counts.good, "bad", counts.bad) .. (row[1] == "udp" and " none " .. counts.none or "")
    end
    lines[#lines + 1] = "malformed"
    local dump = 0
    for _, packet in ipairs(packets) do
        if packet.error then
            dump = dump + 1
        end
    end
    lines[#lines + 1] = "dump " .. dump
    for _, name in ipairs({"eth", "arp", "ip", "icmp", "udp", "tcp", "dns"}) do
        local count = 0
        for _, packet in ipairs(packets) do
            if not packet.error and packet:exists("frame.malformed") and packet.layers[#packet.layers] == name then
                count = count + 1
            end
        end
        lines[#lines + 1] = line(name, count)
    end
    lines[#lines + 1] = "tcp analysis"
    for _, mark in ipairs(flows.marks) do
        local count = 0
        for _, packet in ipairs(packets) do
            if packet:exists("tcp.analysis." .. mark) then
                count = count + 1
            end
        end
        lines[#lines + 1] = line(mark, count)
    end
    append(lines, {"dns", line("queries", #transactions.queries), line("responses", #transactions.responses), line("transactions", #transactions.times), line("unanswered", transactions.unanswered)})
    local minimum, maximum
    for _, value in ipairs(transactions.times) do
        minimum, maximum = minimum and math.min(minimum, value) or value, maximum and math.max(maximum, value) or value
    end
    lines[#lines + 1] = minimum and line("response_time min", seconds(minimum), "max", seconds(maximum)) or "response_time -"
    local rcodes, counts = {}, {}
    for _, packet in ipairs(transactions.responses) do
        local code = packet:value("dns.flags.rcode")
        rcodes[code] = (rcodes[code] or 0) + 1
    end
    for code = 0, 15 do
        if rcodes[code] then
            lines[#lines + 1] = line("rcode", dns.rcode_name(code), rcodes[code])
        end
    end
    for _, packet in ipairs(transactions.queries) do
        for _, name in ipairs(packet:values("dns.qry.name")) do
            counts[name] = (counts[name] or 0) + 1
        end
    end
    local names = {}
    for name in pairs(counts) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        return counts[a] > counts[b] or counts[a] == counts[b] and a < b
    end)
    lines[#lines + 1] = "names"
    for _, name in ipairs(names) do
        lines[#lines + 1] = line(name, counts[name])
    end
    return lines
end
local function endpoint_text(endpoint)
    return network.ipv4(endpoint.address) .. (endpoint.port ~= nil and ":" .. endpoint.port or "")
end
local function conversation_lines(packets, base_time)
    local lines = {"type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"}
    for _, row in ipairs(flows.conversations(packets)) do
        lines[#lines + 1] = table.concat({row.kind, endpoint_text(row.source), endpoint_text(row.destination), row.packets, row.bytes, row.packets_a_to_b, row.bytes_a_to_b, row.packets_b_to_a, row.bytes_b_to_a, seconds(row.start - base_time), seconds(row.finish - row.start)}, ",")
    end
    return lines
end
local function endpoint_lines(packets)
    local lines = {"address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"}
    for _, row in ipairs(flows.endpoints(packets)) do
        lines[#lines + 1] = table.concat({network.ipv4(row.address), row.packets, row.bytes, row.tx_packets, row.tx_bytes, row.rx_packets, row.rx_bytes}, ",")
    end
    return lines
end
local function stream_lines(stream, packets)
    local history = {}
    for _, entry in ipairs(stream.history) do
        history[#history + 1] = line(table.unpack(entry))
    end
    local rtt = "-"
    if stream.syn and stream.handshake_ack then
        rtt = seconds(packets[stream.handshake_ack].time - packets[stream.syn].time)
    end
    local client, server = stream.client_side, stream.server_side
    local lines = {
        line("stream", stream.number, endpoint_text(stream.client), "->", endpoint_text(stream.server)),
        line("packets", stream.packets, "bytes", stream.bytes, "start", seconds(stream.start - packets[1].time), "duration", seconds(stream.finish - stream.start)),
        "states " .. table.concat(history, ", "),
        line("handshake syn", optional(stream.syn), "syn_ack", optional(stream.syn_ack), "ack", optional(stream.handshake_ack), "rtt", rtt),
        line("options client mss", optional(client.mss), "wscale", optional(client.wscale), "server mss", optional(server.mss), "wscale", optional(server.wscale))
    }
    for _, side in ipairs({client, server}) do
        local parts = {line(side.name, "packets", side.packets, "payload", side.payload)}
        for _, mark in ipairs(flows.marks) do
            parts[#parts + 1] = line(mark, side.marks[mark])
        end
        lines[#lines + 1] = table.concat(parts, " ")
    end
    for _, event in ipairs(stream.events) do
        lines[#lines + 1] = line("event", event[1], event[2], event[3], "seq", event[4], "len", event[5])
    end
    return lines
end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, text in ipairs(lines) do
        file:write(text, "\n")
    end
    file:close()
end
local packets = hexdump.read_capture("input/capture.txt")
local base_time, tracker = packets[1].time, flows.tracker()
for _, packet in ipairs(packets) do
    dissect(packet, base_time)
    if packet:exists("tcp.srcport") then
        tracker:track(packet)
    end
end
local summaries, summary_output, detail_output = {}, {}, {}
for i, packet in ipairs(packets) do
    summaries[i] = summary(packet, tracker)
end
append(summary_output, summaries)
local detail_count = 0
for _, request in ipairs(hexdump.read_lines("input/filters.txt")) do
    if request:sub(1, 7) == "FILTER " then
        local expression = request:sub(8)
        append(summary_output, {"", "filter " .. expression})
        local success, tree = pcall(parse_filter, expression)
        if not success then
            summary_output[#summary_output + 1] = "error: " .. tree
        else
            local count = 0
            for i, packet in ipairs(packets) do
                if evaluate(tree, packet) then
                    summary_output[#summary_output + 1], count = summaries[i], count + 1
                end
            end
            summary_output[#summary_output + 1] = line("matched", count, "of", #packets)
        end
    elseif request:sub(1, 7) == "DETAIL " then
        local number = tonumber(request:sub(8))
        if detail_count > 0 then
            detail_output[#detail_output + 1] = ""
        end
        append(detail_output, detail(packets[number], number))
        detail_count = detail_count + 1
    end
end
local streams_output = {}
for i, stream in ipairs(tracker.streams) do
    if i > 1 then
        streams_output[#streams_output + 1] = ""
    end
    append(streams_output, stream_lines(stream, packets))
end
os.execute("mkdir -p output")
write_lines("summary.txt", summary_output)
write_lines("details.txt", detail_output)
write_lines("conversations.csv", conversation_lines(packets, base_time))
write_lines("endpoints.csv", endpoint_lines(packets))
write_lines("protocol_stats.txt", protocol_statistics(packets, dns_transactions(packets)))
write_lines("tcp_streams.txt", streams_output)
