using Printf
function decimal(value,digits=3)
    scale = 10^digits
    rounded = floor(abs(value)*scale+0.5)/scale
    text = Printf.format(Printf.Format("%.$(digits)f"),rounded)
    value<0 && rounded!=0 ? "-"*text : text
end
signed_integer(number) = number>0 ? "+$number" : string(number)
function chart(rows)
    border = "+"*repeat("-",length(rows[1]))*"+"
    [border;["|"*row*"|" for row in rows];border]
end
function write_lines(name,lines)
    mkpath("output")
    write(joinpath("output",name),isempty(lines) ? "" : join(lines,"\n")*"\n")
end
