using Printf
const LEVELS = collect(" .:-=+*#%@")
function dec(value,places=4)
    text = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(text,"-") && parse(Float64,text)==0 ? text[2:end] : text
end
optional(value) = isnothing(value) ? "-" : dec(value)
real_values(items) = join(dec.(items)," ")
integer_values(items) = join(items," ")
function framed(grid)
    border = "+"*repeat("-",size(grid,2))*"+"
    vcat([border],["|"*join(grid[r,:])*"|" for r in axes(grid,1)],[border])
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function write_blocks(name,blocks)
    lines = String[]
    for block in blocks
        isempty(lines) || push!(lines,"")
        append!(lines,block)
    end
    write_lines(name,lines)
end
