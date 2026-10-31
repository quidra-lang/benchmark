function render_grid(polygons, operands, x0,y0,cw,ch,cols,rows)
    result_rings = [ring for polygon in polygons for ring in polygon]
    counts = Dict(c => 0 for c in ['#','a','b','+'])
    lines = String[]
    for j in 0:rows-1
        y = BigInt(2*y0+(2*(rows-1-j)+1)*ch)//BigInt(2)
        cells = Char[]
        for i in 0:cols-1
            x = BigInt(2*x0+(2*i+1)*cw)//BigInt(2)
            p = (x,y)
            character = '.'
            if interior(result_rings,p)
                character = '#'
            elseif operands !== nothing
                a,b = interior(operands[1].rings,p),interior(operands[2].rings,p)
                character = a && b ? '+' : a ? 'a' : b ? 'b' : '.'
            end
            push!(cells,character)
            haskey(counts,character) && (counts[character] += 1)
        end
        push!(lines,String(cells))
    end
    return lines,counts
end
