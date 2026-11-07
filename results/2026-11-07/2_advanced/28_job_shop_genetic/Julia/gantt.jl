function chart_scale(makespan,width)
    magnitude = 1
    while true
        for step in (1,2,5)
            scale = step*magnitude
            columns = cld(makespan,scale)
            columns <= width && return (scale,columns)
        end
        magnitude *= 10
    end
end
function time_row(scale,columns)
    row = "time"
    for column in 0:10:(columns-1)
        row = rpad(row,6+column)*string(column*scale)
    end
    row
end
rule_row(columns) = repeat(" ",6)*join(c%10 == 0 ? '+' : '-' for c in 0:(columns-1))
framed(label,marks) = rpad(label,4)*" |"*marks*"|"
function chart_row(label,intervals,scale,columns)
    ordered = sort(intervals)
    marks = Char[]
    for column in 0:(columns-1)
        mark,widest = '.',0
        for (start,stop,symbol) in ordered
            overlap = min(stop,(column+1)*scale)-max(start,column*scale)
            if overlap > widest
                mark,widest = symbol,overlap
            end
        end
        push!(marks,mark)
    end
    framed(label,String(marks))
end
function busy_row(intervals,scale,columns)
    marks = String[]
    for column in 0:(columns-1)
        time = column*scale
        busy = count(row->any(a <= time < b for (a,b,_) in row),intervals)
        push!(marks,busy == 10 ? "X" : string(busy))
    end
    framed("busy",join(marks))
end
