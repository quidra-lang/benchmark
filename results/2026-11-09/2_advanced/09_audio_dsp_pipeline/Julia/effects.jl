module Effects
using ..Signals
function gain(samples, num, den)
    counter = ClipCounter()
    result = [saturate!(counter, rdiv(x * num, den)) for x in samples]
    result, counter.count
end
function mix(tracks, weights, den)
    counter = ClipCounter()
    result = Int[]
    for i in 1:maximum(length, tracks)
        total = 0
        for (track, weight) in zip(tracks, weights)
            i <= length(track) && (total += weight * track[i])
        end
        push!(result, saturate!(counter, rdiv(total, den)))
    end
    result, counter.count
end
delay(samples, count) = vcat(zeros(Int, count), samples)
function echo(samples, delay_length, num, den, tail)
    result = vcat(samples, zeros(Int, tail))
    counter = ClipCounter()
    for i in delay_length+1:length(result)
        result[i] = saturate!(counter, result[i] + rdiv(num * result[i - delay_length], den))
    end
    result, counter.count
end
resampled_length(count, old_rate, new_rate) = fld((count - 1) * new_rate, old_rate) + 1
function resample(samples, old_rate, new_rate)
    result = Int[]
    for j in 0:resampled_length(length(samples), old_rate, new_rate)-1
        p, q = divrem(j * old_rate, new_rate)
        value = samples[p + 1]
        q > 0 && (value += rdiv((samples[p + 2] - value) * q, new_rate))
        push!(result, value)
    end
    result
end
function fade(samples, fade_in, fade_out)
    result = copy(samples)
    count = length(result)
    for i in 0:fade_in-1
        result[i + 1] = rdiv(result[i + 1] * i, fade_in)
    end
    for i in count-fade_out:count-1
        result[i + 1] = rdiv(result[i + 1] * (count - 1 - i), fade_out)
    end
    result
end
end
