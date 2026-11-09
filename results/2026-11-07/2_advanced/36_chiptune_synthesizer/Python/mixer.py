from instruments import clamp, clock_register, wave_value


def channel_value(channel):
    if not channel.sounding:
        return 0
    instrument = channel.instrument
    level = wave_value(instrument, channel.mode, channel.phase, channel.register)
    channel.phase += channel.increment
    if channel.phase >= 65536:
        channel.phase -= 65536
        if instrument.wave == "NOISE":
            channel.register = clock_register(channel.register, channel.mode)
    return (2 * level - 15) * channel.amplitude


def mix_tick(channels, count, gain, muted, samples, lanes):
    clipped = 0
    for _ in range(count):
        total = 0
        for channel, lane, mute in zip(channels, lanes, muted):
            value = channel_value(channel)
            lane.append(value)
            if not mute:
                total += value
        sample = 128 + gain * total // 4096
        if sample < 0 or sample > 255:
            clipped += 1
            sample = clamp(sample, 0, 255)
        samples.append(sample)
    return clipped


def fade_out(samples, fade):
    total = len(samples)
    length = min(fade, total)
    for index in range(total - length, total):
        samples[index] = 128 + (samples[index] - 128) * (total - 1 - index) // length
