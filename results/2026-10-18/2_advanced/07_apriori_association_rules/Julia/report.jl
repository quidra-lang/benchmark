module Report
using ..Baskets: members
export fractiontext, percenttext, moneytext, itemtext, arrow, rulecsv, writereport
function fractiontext(value::Rational)
    p,q = abs(numerator(value)),denominator(value)
    scaled = div(10000*p,q)
    decimal = string(div(scaled,10000),".",lpad(mod(scaled,10000),4,'0'))
    sign = value < 0 ? "-" : ""
    decimalsign = value < 0 && scaled > 0 ? "-" : ""
    "$sign$p/$q=$decimalsign$decimal"
end
fractiontext(value::Integer) = fractiontext(value//1)
function percenttext(part,whole)
    scaled = div(10000*part,whole)
    string(div(scaled,100),".",lpad(mod(scaled,100),2,'0'),"%")
end
moneytext(cents) = string(div(cents,100),".",lpad(mod(cents,100),2,'0'))
itemtext(mask,names) = join(names[members(mask)],"+")
arrow(rule,names) = itemtext(rule.x,names)*" -> "*itemtext(rule.y,names)
function rulecsv(rules,names)
    lines = ["rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"]
    for (rank,r) in enumerate(rules)
        metrics = [fractiontext(r.support),fractiontext(r.confidence),fractiontext(r.lift),fractiontext(r.leverage),r.conviction === nothing ? "INF" : fractiontext(r.conviction),fractiontext(r.improvement)]
        push!(lines,join([string(rank),itemtext(r.x,names),itemtext(r.y,names),string(r.count),metrics...],","))
    end
    lines
end
function writereport(name,lines)
    mkpath("output")
    write("output/"*name,isempty(lines) ? "" : join(lines,"\n")*"\n")
end
end
