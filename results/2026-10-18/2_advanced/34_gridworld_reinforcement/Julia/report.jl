const POLICY_SYMBOLS = "^>v<"
fixed_text(value) = (value < 0 ? "-" : "")*"$(abs(value)÷10000).$(lpad(abs(value)%10000,4,'0'))"
average_text(total,count) = fixed_text(fld(10000*total,count))
cell_text(world,cell) = "$((cell-1)÷world.cols),$((cell-1)%world.cols)"
cells_text(world,cells) = join((cell_text(world,cell) for cell in cells),' ')
function grid_lines(world,fields,separator)
    lines = String[]
    for row in 0:world.rows-1
        parts = String[]
        for cell in (row*world.cols+1):((row+1)*world.cols)
            state = world.state_index[cell]
            push!(parts,state == 0 ? string(world.kinds[cell]) : string(fields[state]))
        end
        push!(lines,join(parts,separator))
    end
    lines
end
value_grid(world,values) = grid_lines(world,fixed_text.(values)," ")
policy_grid(world,policy) = grid_lines(world,[POLICY_SYMBOLS[action] for action in policy],"")
symbol_grid(world,symbols) = grid_lines(world,symbols,"")
function q_table_rows(world,name,q,visits)
    lines = String[]
    for (state,cell) in enumerate(world.states), action in 1:4
        count = isnothing(visits) ? "-" : string(visits[state,action])
        push!(
            lines,
            "$name,$((cell-1)÷world.cols),$((cell-1)%world.cols),$(ACTION_LETTERS[action]),$(fixed_text(q[state,action])),$count"
        )
    end
    lines
end
function join_parts(parts)
    lines = String[]
    for part in parts
        !isempty(lines) && push!(lines,"")
        append!(lines,part)
    end
    lines
end
function write_lines(path,lines)
    open(path,"w") do handle
        foreach(line->println(handle,line),lines)
    end
end
