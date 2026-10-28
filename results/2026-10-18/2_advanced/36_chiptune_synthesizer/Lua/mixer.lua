local instruments = require("instruments")
local M = {}
function M.channel_value(channel)
    if not channel.sounding then
        return 0
    end
    local level = instruments.wave(channel.instrument, channel.mode, channel.phase, channel.register)
    channel.phase = channel.phase + channel.increment
    if channel.phase >= 65536 then
        channel.phase = channel.phase - 65536
        if channel.instrument.wave == "NOISE" then
            channel.register = instruments.clock(channel.register, channel.mode)
        end
    end
    return (2 * level - 15) * channel.amplitude
end
function M.tick(channels, count, gain, muted, samples, lanes)
    local clipped = 0
    for _ = 1, count do
        local total = 0
        for i, channel in ipairs(channels) do
            local value = M.channel_value(channel)
            lanes[i][#lanes[i] + 1] = value
            if muted[i] == 0 then
                total = total + value
            end
        end
        local sample = 128 + gain * total // 4096
        if sample < 0 or sample > 255 then
            clipped = clipped + 1
            sample = instruments.clamp(sample, 0, 255)
        end
        samples[#samples + 1] = sample
    end
    return clipped
end
function M.fade(samples, fade)
    local count, length = #samples, math.min(fade, #samples)
    for i = count - length + 1, count do
        samples[i] = 128 + (samples[i] - 128) * (count - i) // length
    end
end
return M
