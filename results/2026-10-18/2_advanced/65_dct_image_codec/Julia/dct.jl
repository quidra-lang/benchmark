const ZIGZAG = sort!([(u,v) for u in 1:8 for v in 1:8];by=p->(p[1]+p[2],isodd(p[1]+p[2]) ? p[1] : -p[1]))
rounded_shift(value,shift) = fld(value+(1<<(shift-1)),1<<shift)
function forward_dct(block,transform)
    intermediate,result = zeros(Int,8,8),zeros(Int,8,8)
    for u in 1:8,x in 1:8
        total = 0
        for y in 1:8
            total += transform[u,y]*(block[y,x]-128)
        end
        intermediate[u,x] = rounded_shift(total,11)
    end
    for u in 1:8,v in 1:8
        total = 0
        for x in 1:8
            total += intermediate[u,x]*transform[v,x]
        end
        result[u,v] = rounded_shift(total,15)
    end
    result
end
function inverse_dct(coefficients,transform)
    intermediate,result = zeros(Int,8,8),zeros(Int,8,8)
    for y in 1:8,v in 1:8
        total = 0
        for u in 1:8
            total += transform[u,y]*coefficients[u,v]
        end
        intermediate[y,v] = rounded_shift(total,11)
    end
    for y in 1:8,x in 1:8
        total = 0
        for v in 1:8
            total += intermediate[y,v]*transform[v,x]
        end
        result[y,x] = clamp_byte(rounded_shift(total,15)+128)
    end
    result
end
function quantization_tables(basic,quality)
    scale = quality<50 ? 5000÷quality : 200-2quality
    Dict(i-1=>clamp.(fld.(table.*scale.+50,100),1,255) for (i,table) in enumerate(basic))
end
function quantize(values,table)
    [sign(values[u,v])*((abs(values[u,v])+table[u,v]÷2)÷table[u,v]) for u in 1:8,v in 1:8]
end
zigzag(values) = [values[u,v] for (u,v) in ZIGZAG]
function unzigzag(sequence)
    result = zeros(Int,8,8)
    for ((u,v),value) in zip(ZIGZAG,sequence)
        result[u,v] = value
    end
    result
end
function dequantize(sequence,table,keep=64)
    result = zeros(Int,8,8)
    for (index,(u,v)) in enumerate(ZIGZAG)
        index<=keep && (result[u,v]=sequence[index]*table[u,v])
    end
    result
end
