function fraction(a,b)
    common = gcd(a,b)
    "$(a÷common)/$(b÷common)"
end
function ids(values)
    sequence = join(values," ")
    isempty(sequence) ? "-" : sequence
end
function distances(values)
    sequence = join(("$id:$distance" for (id,distance) in values)," ")
    isempty(sequence) ? "-" : sequence
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        for line in lines
            println(io,line)
        end
    end
end
