function display_line(pieces,slack,alignment,last)
    pieces = replace.(pieces,"~"=>" ")
    text = join(pieces,' ')
    slack <= 0 && return text
    gaps = length(pieces)-1
    if alignment == "justify" && !last && gaps > 0
        quotient,remainder = divrem(slack,gaps)
        parts = [pieces[1]]
        for (index,piece) in enumerate(pieces[2:end])
            push!(parts,repeat(" ",quotient+1+(index <= remainder ? 1 : 0)))
            push!(parts,piece)
        end
        return join(parts)
    elseif alignment == "right"
        return repeat(" ",slack)*text
    elseif alignment == "center"
        return repeat(" ",slack÷2)*text
    end
    text
end
function format_table(rows,columns,caption,number)
    widths = [maximum(length(row[index]) for row in rows) for index in eachindex(columns)]
    lines = String[]
    !isempty(caption) && push!(lines,"Table $number. $caption")
    for (row_index,row) in enumerate(rows)
        cells = String[]
        for (text,alignment,width) in zip(row,columns,widths)
            missing = width-length(text)
            before = alignment == 'l' ? 0 : alignment == 'r' ? missing : missing÷2
            push!(cells,repeat(" ",before)*text*repeat(" ",missing-before))
        end
        push!(lines,rstrip(join(cells," | "),' '))
        row_index == 1 && push!(lines,join((repeat("-",width) for width in widths),"-+-"))
    end
    lines
end
function running_head(fields,values,width,serial)
    expanded = String[]
    for field in fields
        for (name,value) in values
            field = replace(field,"{"*name*"}"=>value)
        end
        push!(expanded,field)
    end
    left,center,right = expanded
    iseven(serial) && ((left,right)=(right,left))
    line = fill(' ',width)
    for (start,text) in ((0,left),((width-length(center))÷2,center),(width-length(right),right))
        line[start+1:start+length(text)] = collect(text)
    end
    rstrip(join(line),' ')
end
function pages_lines(pages)
    lines = String[]
    for page in pages
        append!(lines,["--- page $(page[:serial]) ---",page[:header],""])
        append!(lines,page[:body])
        append!(lines,["",page[:footer]])
    end
    lines
end
