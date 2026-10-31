module ProcessCapability
using ..VariableCharts: realsum
export assess, histogram
function indices(mean,sigma,s)
    cp = (s.usl-s.lsl)/(6*sigma)
    upper = (s.usl-mean)/(3*sigma)
    lower = (mean-s.lsl)/(3*sigma)
    (cp,upper,lower,min(upper,lower))
end
function interval(x,count,z)
    delta = z*sqrt(1/(9*count)+x*x/(2*(count-1)))
    (x-delta,x+delta)
end
function assess(groups,s,c)
    values = [v for g in groups for v in g.values]
    count = length(values)
    mean = sum(values)/count
    within = (sum(g.range for g in groups)/length(groups))/c.d2
    sbar = (realsum(g.sd for g in groups)/length(groups))/c.c4
    overall = sqrt(realsum((v-mean)*(v-mean) for v in values)/(count-1))
    cp,cpu,cpl,cpk = indices(mean,within,s)
    pp,ppu,ppl,ppk = indices(mean,overall,s)
    offset = mean-s.target
    cpm = (s.usl-s.lsl)/(6*sqrt(overall*overall+offset*offset))
    below = countvalues(v -> v < s.lsl,values)
    above = countvalues(v -> v > s.usl,values)
    verdict = cpk >= 1.33 ? "capable" : cpk >= 1.0 ? "marginal" : "incapable"
    (count=count,mean=mean,sigma_within=within,sigma_sbar=sbar,sigma_overall=overall,cp=cp,cpu=cpu,cpl=cpl,cpk=cpk,pp=pp,ppu=ppu,ppl=ppl,ppk=ppk,cpm=cpm,cpk_ci=interval(cpk,count,s.z),ppk_ci=interval(ppk,count,s.z),below=below,above=above,ppm=1000000*(below+above)/count,verdict=verdict)
end
countvalues(predicate,values) = count(predicate,values)
function histogram(groups,s)
    values = [v for g in groups for v in g.values]
    lo = s.bin*fld(min(minimum(values),s.lsl),s.bin)
    hi = s.bin*fld(max(maximum(values),s.usl),s.bin)+s.bin
    frequencies = zeros(Int,div(hi-lo,s.bin))
    for v in values
        frequencies[div(v-lo,s.bin)+1] += 1
    end
    top = maximum(frequencies)
    rows = String[]
    for (i,f) in enumerate(frequencies)
        a = lo+(i-1)*s.bin
        b = a+s.bin-1
        parts = ["bin",string(a),string(b),string(f)]
        f > 0 && push!(parts,repeat("#",cld(50*f,top)))
        for (name,v) in (("lsl",s.lsl),("target",s.target),("usl",s.usl))
            a <= v <= b && push!(parts,name)
        end
        push!(rows,join(parts," "))
    end
    rows
end
end
