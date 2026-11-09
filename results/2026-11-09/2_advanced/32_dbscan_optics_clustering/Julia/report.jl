using Printf
function fraction_text(a,b)
    divisor = gcd(abs(a),b)
    "$(a÷divisor)/$(b÷divisor)"
end
root_text(value) = @sprintf("%.3f",sqrt(value))
function ari_text(a,b)
    value = @sprintf("%.4f",a/b)
    value == "-0.0000" && (value="0.0000")
    "$(fraction_text(a,b)) $value"
end
function framed(rows,width)
    border = "+"*repeat("-",width)*"+"
    vcat([border],["|$row|" for row in rows],[border])
end
function write_lines(name,lines)
    mkpath("output")
    open(joinpath("output",name),"w") do io
        foreach(line->println(io,line),lines)
    end
end
