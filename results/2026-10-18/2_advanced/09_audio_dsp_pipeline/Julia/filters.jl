module Filters
using ..Signals
function fir(samples, divisor, taps)
    counter = ClipCounter()
    result = Int[]
    for n in eachindex(samples)
        total = 0
        for k in 1:min(length(taps), n)
            total += taps[k] * samples[n - k + 1]
        end
        push!(result, saturate!(counter, fld(total, divisor)))
    end
    result, counter.count
end
function biquad(samples, coefficients)
    counter = ClipCounter()
    signal = samples
    for first in 1:5:length(coefficients)
        b0, b1, b2, a1, a2 = coefficients[first:first+4]
        result = Int[]
        u1 = u2 = v1 = v2 = 0
        for u in signal
            v = saturate!(counter, fld(b0*u + b1*u1 + b2*u2 - a1*v1 - a2*v2, 16384))
            push!(result, v)
            u1, u2 = u, u1
            v1, v2 = v, v1
        end
        signal = result
    end
    signal, counter.count
end
function moving_average(samples, width)
    result = Int[]
    total = 0
    for n in eachindex(samples)
        total += samples[n]
        n > width && (total -= samples[n - width])
        push!(result, rdiv(total, width))
    end
    result
end
function dc_block(samples, num, den)
    counter = ClipCounter()
    result = Int[]
    previous_input = previous_output = 0
    for x in samples
        previous_output = saturate!(counter, x - previous_input + rdiv(num * previous_output, den))
        previous_input = x
        push!(result, previous_output)
    end
    result, counter.count
end
end
