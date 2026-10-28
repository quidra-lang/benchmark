using Printf
function real_text(value)
    text = @sprintf("%.4f",value)
    text=="-0.0000" ? "0.0000" : text
end
field_text(value) = value isa AbstractFloat ? real_text(value) : string(value)
fields(;items...) = join(("$key=$(field_text(value))" for (key,value) in items)," ")
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
function write_csv(name,header,rows)
    write_lines(name,vcat([header],[join(field_text.(row),",") for row in rows]))
end
function shade_lines(grid,fs,n,band_db)
    maximum_value = maximum(maximum(row) for row in grid)
    shades = collect(" .:-=+*#%@")
    lines = String[]
    for k in n÷2:-1:0
        pixels = [shades[max(0,9-floor(Int,-20log10(row[k+1]/maximum_value)/band_db))+1] for row in grid]
        push!(lines,lpad(real_text(k*fs/n),9)*" |"*join(pixels)*"|")
    end
    lines
end
