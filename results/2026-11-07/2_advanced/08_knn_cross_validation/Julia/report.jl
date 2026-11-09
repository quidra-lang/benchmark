module Report
using Printf
export fixed, fourdecimal, ratio, fraction, writelines
function fixed(value,places=4)
    value === nothing && return "-"
    text = if places == 6
        @sprintf("%.6f",value)
    elseif places == 2
        @sprintf("%.2f",value)
    else
        @sprintf("%.4f",value)
    end
    startswith(text,"-") && all(c -> c == '0' || c == '.',text[2:end]) ? text[2:end] : text
end
fourdecimal(value) = round(value,digits=4)
ratio(n,d) = "$n/$d $(fixed(n/d))"
function fraction(n,d)
    d == 0 && return "- -"
    divisor = gcd(n,d)
    "$(div(n,divisor))/$(div(d,divisor)) $(fixed(n/d))"
end
writelines(name,lines) = write("output/"*name,join(lines,"\n")*"\n")
end
