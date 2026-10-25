module Signals
export Signal, ClipCounter, saturate!, rdiv, peak, read_signals, format_signal, impulse, step_signal, noise
struct Signal
    name::String
    rate::Int
    samples::Vector{Int}
    origin::String
    ingredients::Vector{Signal}
end
Signal(name, rate, samples) = Signal(name, rate, samples, "input", Signal[])
mutable struct ClipCounter
    count::Int
end
ClipCounter() = ClipCounter(0)
rdiv(a, b) = fld(2a + b, 2b)
function saturate!(counter, value)
    limited = clamp(value, -32768, 32767)
    counter.count += limited != value
    limited
end
peak(samples) = maximum(abs, samples)
function read_signals(path)
    lines = readlines(path)
    result = Signal[]
    i = 1
    while i <= length(lines)
        header = split(lines[i])
        count = parse(Int, header[4])
        samples = Int[]
        i += 1
        while length(samples) < count
            append!(samples, parse.(Int, split(lines[i])))
            i += 1
        end
        push!(result, Signal(String(header[2]), parse(Int, header[3]), samples))
    end
    result
end
function format_signal(signal)
    result = ["SIGNAL $(signal.name) $(signal.rate) $(length(signal.samples))"]
    for first in 1:16:length(signal.samples)
        push!(result, join(signal.samples[first:min(first + 15, end)], " "))
    end
    result
end
function impulse(count, position, amplitude)
    result = zeros(Int, count)
    result[position + 1] = amplitude
    result
end
step_signal(count, position, amplitude) = [i >= position ? amplitude : 0 for i in 0:count-1]
function noise(count, seed)
    result = Vector{Int}(undef, count)
    state = seed
    for i in eachindex(result)
        state = mod(48271state, 2147483647)
        result[i] = mod(state, 65536) - 32768
    end
    result
end
end
