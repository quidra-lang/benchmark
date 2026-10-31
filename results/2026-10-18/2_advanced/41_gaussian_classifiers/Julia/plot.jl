using Printf
function real_text(value)
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
reals(values) = join(real_text.(collect(values))," ")
function fraction_text(value)
    isnothing(value) && return "-"
    a,b = value
    "$a/$b $(real_text(a/b))"
end
ratio_text(a,b) = fraction_text(reduced_fraction(a,b))
function frame(grid)
    border = "+"*repeat("-",size(grid,2))*"+"
    vcat([border],["|"*join(grid[i,:])*"|" for i in axes(grid,1)],[border])
end
cell(value,low,high,n) = floor(Int,(value-low)/(high-low)*(n-1)+0.5)
function join_sections(sections)
    lines = String[]
    for section in sections
        isempty(lines) || push!(lines,"")
        append!(lines,section)
    end
    lines
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
