function hex_lines(samples)
    [join((uppercase(string(value,base=16,pad=2)) for value in samples[start:min(
        start+31,
        length(samples)
    )])) for start in 1:32:length(samples)]
end
function adler32_text(values)
    a,b = 1,0
    for value in values
        a = (a+value)%65521
        b = (b+a)%65521
    end
    uppercase(string(b*65536+a,base=16,pad=8))
end
peak(values,center) = maximum((abs(value-center) for value in values);init=0)
root_mean_square(values,center) = isqrt(sum((value-center)*(value-center) for value in values)÷length(values))
zero_crossings(samples) = sum((samples[i] < 128) != (samples[i+1] < 128) for i in 1:length(samples)-1;init=0)
