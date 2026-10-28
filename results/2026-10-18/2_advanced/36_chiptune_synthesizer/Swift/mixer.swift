func channelValue(_ channel: Channel) -> Int {
    guard channel.sounding, let instrument = channel.instrument else { return 0 }
    let level = waveValue(instrument, channel.mode, channel.phase, channel.register)
    channel.phase += channel.increment
    if channel.phase >= 65536 {
        channel.phase -= 65536
        if instrument.wave == "NOISE" { channel.register = clockRegister(channel.register, channel.mode) }
    }
    return (2 * level - 15) * channel.amplitude
}

func mixTick(_ channels: [Channel], _ count: Int, _ gain: Int, _ muted: [Bool],
             _ samples: inout [Int], _ lanes: inout [[Int]]) -> Int {
    var clipped = 0
    for _ in 0..<count {
        var total = 0
        for index in channels.indices {
            let value = channelValue(channels[index])
            lanes[index].append(value)
            if !muted[index] { total += value }
        }
        let sample = 128 + floorDivide(gain * total, 4096)
        if sample < 0 || sample > 255 { clipped += 1 }
        samples.append(clamp(sample, 0, 255))
    }
    return clipped
}

func fadeOut(_ samples: inout [Int], _ fade: Int) {
    let total = samples.count
    let length = min(fade, total)
    guard length > 0 else { return }
    for index in (total - length)..<total {
        samples[index] = 128 + floorDivide((samples[index] - 128) * (total - 1 - index), length)
    }
}
