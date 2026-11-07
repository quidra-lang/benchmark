local clocks = require('clocks')
local M = {}
function M.read()
    local input = assert(io.open('input/topology.txt', 'r'))
    local names, indices, channels, order = {}, {}, {}, {}
    for name in input:read('*l'):gmatch('%S+') do
        if name ~= 'PROCESSES' then names[#names + 1] = name; indices[name] = #names end
    end
    for i = 1, #names do channels[i] = {} end
    for line in input:lines() do
        local t = {}
        for word in line:gmatch('%S+') do t[#t + 1] = word end
        local source, destination = indices[t[2]], indices[t[3]]
        channels[source][destination] = {source = source, destination = destination, kind = t[4], low = tonumber(t[5]), high = tonumber(t[6] or t[5])}
    end
    input:close()
    for source = 1, #names do
        for destination = 1, #names do if source ~= destination then order[#order + 1] = {source, destination} end end
    end
    return names, indices, channels, order
end
function M.initialize(original, size)
    local channels = {}
    for source = 1, size do
        channels[source] = {}
        for destination = 1, size do
            if source ~= destination then
                local original_channel = original[source][destination]
                local c = {source = source, destination = destination, kind = original_channel.kind, low = original_channel.low, high = original_channel.high,
                    sequence = 0, last_arrival = 0, messages = 0, markers = 0, buffered = 0, max_delay = 0, entries = 0, previous = {}}
                for i = 1, size do c.previous[i] = 0 end
                channels[source][destination] = c
            end
        end
    end
    return channels
end
function M.generator(seed) return {state = seed, draws = 0} end
function M.draw(generator)
    generator.state = (48271 * generator.state) % 2147483647
    generator.draws = generator.draws + 1
    return generator.state
end
function M.dispatch(channels, packet, now, generator)
    local c = channels[packet.source][packet.destination]
    c.sequence = c.sequence + 1
    packet.sequence, packet.dispatch_time = c.sequence, now
    local delay = c.low
    if c.low ~= c.high then delay = delay + M.draw(generator) % (c.high - c.low + 1) end
    local arrival = now + delay
    if c.kind == 'FIFO' then arrival = math.max(arrival, c.last_arrival) end
    c.last_arrival = math.max(c.last_arrival, arrival)
    packet.arrival_time = arrival
    c.max_delay = math.max(c.max_delay, arrival - now)
    if packet.marker then c.markers = c.markers + 1
    else
        c.messages = c.messages + 1
        for i, value in ipairs(packet.send_event.vector) do if value ~= c.previous[i] then c.entries = c.entries + 1 end end
        c.previous = clocks.copy(packet.send_event.vector)
    end
    return arrival
end
function M.delay_text(channel)
    if channel.low == channel.high then return tostring(channel.low) end
    return channel.low .. '-' .. channel.high
end
return M
