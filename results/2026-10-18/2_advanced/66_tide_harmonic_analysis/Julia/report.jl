using Printf
function decimal(value,places)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
optional(value,places) = isnothing(value) ? "none" : decimal(value,places)
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function render_plot(grid,labels)
    width = maximum(length,labels)
    lines = [lpad(labels[row],width)*" |"*join(grid[row,:])*"|" for row in axes(grid,1)]
    axis = join(column%6==0 ? '+' : '-' for column in 0:size(grid,2)-1)
    push!(lines,repeat(" ",width)*" +"*axis*"+")
    lines
end
