using Printf
function real_text(value)
    isnothing(value) && return "-"
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
optional(value) = isnothing(value) ? "-" : string(value)
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
