function channel_value!(channel)
    channel.sounding || return 0
    level = wave_value(channel.instrument,channel.mode,channel.phase,channel.register)
    channel.phase += channel.increment
    if channel.phase >= 65536
        channel.phase -= 65536
        channel.instrument.wave == "NOISE" && (channel.register=clock_register(channel.register,channel.mode))
    end
    (2*level-15)*channel.amplitude
end
function mix_tick!(channels,count,gain,muted,samples,lanes)
    clipped = 0
    for _ in 1:count
        total = 0
        for (channel,lane,mute) in zip(channels,lanes,muted)
            value = channel_value!(channel)
            push!(lane,value)
            !mute && (total += value)
        end
        sample = 128+fld(gain*total,4096)
        if sample < 0 || sample > 255
            clipped += 1
            sample = clamp(sample,0,255)
        end
        push!(samples,sample)
    end
    clipped
end
function fade_out!(samples,fade)
    total = length(samples)
    count = min(fade,total)
    for index in total-count+1:total
        samples[index] = 128+fld((samples[index]-128)*(total-index),count)
    end
end
