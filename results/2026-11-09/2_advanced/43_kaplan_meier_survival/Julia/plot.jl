function curve_lines(groups,collections,estimates,width,height,time_limit)
    cells = fill(" ",height,width)
    step = time_limit÷width
    for (g,group) in enumerate(groups)
        letter = string(Char(Int('A')+g-1))
        maximum_time = maximum(s.time for s in collections[group])
        previous = nothing
        for column in 0:width-1
            time = column*step
            time>maximum_time && break
            band = min(height-1,floor(Int,row_at(estimates[group],time).survival*height))
            occupied = isnothing(previous) || previous-1<=band ? (band:band) : (band:previous-1)
            for row in occupied
                cells[row+1,column+1] = cells[row+1,column+1]==" " ? letter : "*"
            end
            previous = band
        end
    end
    border = "   +"*repeat("-",width)*"+"
    lines = [border]
    for band in height-1:-1:0
        push!(lines,lpad(fld(100band,height),3)*"|"*join(cells[band+1,:])*"|")
    end
    push!(lines,border)
    lines
end
