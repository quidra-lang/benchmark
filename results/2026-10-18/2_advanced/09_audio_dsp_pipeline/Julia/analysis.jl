module AudioAnalysis
using ..Signals
export energy, rms, zero_crossings, count_clipped, crest_fraction, autocorrelation, pitch_lag
energy(samples) = sum(x*x for x in samples)
rms(samples) = isqrt(fld(energy(samples), length(samples)))
zero_crossings(samples) = count(i -> (samples[i-1] < 0) != (samples[i] < 0), 2:length(samples))
count_clipped(samples) = count(x -> x == -32768 || x == 32767, samples)
function crest_fraction(samples)
    denominator = energy(samples)
    denominator == 0 && return "none"
    numerator = peak(samples)^2 * length(samples)
    divisor = gcd(numerator, denominator)
    "$(div(numerator, divisor))/$(div(denominator, divisor))"
end
function autocorrelation(samples, lag)
    total = 0
    for n in 1:length(samples)-lag
        total += samples[n] * samples[n + lag]
    end
    total
end
function pitch_lag(samples, low, high)
    best_lag = low
    best_value = autocorrelation(samples, low)
    for lag in low+1:high
        value = autocorrelation(samples, lag)
        if value > best_value
            best_lag, best_value = lag, value
        end
    end
    best_value > 0 ? best_lag : nothing
end
end
