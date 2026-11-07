function decimal(numerator,denominator)
    scaled = (2numerator*10000+denominator)÷(2denominator)
    "$(scaled÷10000).$(lpad(scaled%10000,4,'0'))"
end
function percentage(numerator,denominator)
    denominator==0 && return "-"
    scaled = (2numerator*10000+denominator)÷(2denominator)
    "$(scaled÷100).$(lpad(scaled%100,2,'0'))"
end
function reduced_fraction(numerator,denominator)
    divisor = gcd(numerator,denominator)
    "$(numerator÷divisor)/$(denominator÷divisor)"
end
hexadecimal(value) = string(value;base=16,pad=8)
register_text(value) = value==-1 ? "-" : "r$value"
cycle_heading(start,ending) = "cycle"*repeat(" ",18)*join(string(cycle%10) for cycle in start:ending)
function diagram_row(number,pc,kind,characters,annotation="")
    identifier = number==0 ? "     -" : lpad(number,6)
    "$identifier $(hexadecimal(pc)) $(rpad(kind,6)) $characters$annotation"
end
function join_parts(parts)
    lines = String[]
    for part in parts
        isempty(lines) || push!(lines,"")
        append!(lines,part)
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
