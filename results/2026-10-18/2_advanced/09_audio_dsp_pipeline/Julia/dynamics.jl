module Dynamics
using ..Signals
function envelope(samples, attack, release)
    levels = Int[]
    level = 0
    for x in samples
        magnitude = min(abs(x), 32767)
        coefficient = magnitude > level ? attack : release
        level += rdiv((magnitude - level) * coefficient, 32768)
        push!(levels, level)
    end
    levels
end
function normalize(samples, target)
    p = peak(samples)
    (p == 0 ? copy(samples) : [rdiv(x * target, p) for x in samples]), p
end
function gate(samples, threshold, hold)
    result = Int[]
    muted = 0
    last_loud = -length(samples) - hold
    for (i, x) in enumerate(samples)
        abs(x) >= threshold && (last_loud = i)
        if i - last_loud <= hold
            push!(result, x)
        else
            push!(result, 0)
            muted += 1
        end
    end
    result, muted
end
function compress(samples, threshold, ratio_num, ratio_den, attack, release)
    levels = envelope(samples, attack, release)
    result = Int[]
    gain = min_gain = 32768
    reduced = 0
    for (x, level) in zip(samples, levels)
        limited = threshold + rdiv((level - threshold) * ratio_den, ratio_num)
        target = level > threshold ? rdiv(limited * 32768, level) : 32768
        gain = target < gain ? target : gain + rdiv((target - gain) * release, 32768)
        min_gain = min(min_gain, gain)
        reduced += gain < 32768
        push!(result, rdiv(x * gain, 32768))
    end
    result, min_gain, reduced
end
end
