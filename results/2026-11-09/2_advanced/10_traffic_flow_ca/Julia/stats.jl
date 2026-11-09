module TrafficStats
export dec, frac, percentile, histogram_lines
function dec(a, b, places)
    b == 0 && return "-"
    scale = 10^places
    z = fld(2a*scale+b, 2b)
    "$(fld(z, scale)).$(lpad(mod(z, scale), places, '0'))"
end
function frac(a, b)
    b == 0 && return "-"
    divisor = gcd(a, b)
    "$(div(a, divisor))/$(div(b, divisor))"
end
percentile(times, q) = times[fld(q*length(times)+99, 100)]
function histogram_lines(times, width)
    first = fld(times[1], width)
    counts = zeros(Int, fld(times[end], width)-first+1)
    for time in times
        counts[fld(time, width)-first+1] += 1
    end
    largest = maximum(counts)
    lines = String[]
    for (i, count) in enumerate(counts)
        low = (first+i-1)*width
        stars = fld(80count+largest, 2largest)
        line = "  $low-$(low+width-1) $count"
        stars > 0 && (line *= " " * repeat("*", stars))
        push!(lines, line)
    end
    lines
end
end
