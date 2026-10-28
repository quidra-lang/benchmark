base10log(value) = log(value)/2.302585092994046
function median_value(values)
    ordered = sort(collect(values))
    n = length(ordered)
    isodd(n) ? ordered[n÷2+1] : (ordered[n÷2]+ordered[n÷2+1])/2
end
function per_pick_magnitude(pick,r,params)
    al,bl,cl = params["local_magnitude"]
    ad,bd,cd = params["duration_magnitude"]
    md = ad+bd*base10log(pick.duration/100)+cd*r
    ml = pick.clipped ? nothing : base10log(pick.amplitude)+al*base10log(r/100)+bl*(r-100)+cl
    (r=r,ml=ml,md=md)
end
magnitude_hundredths(value) = value<0 ? -floor(Int,-value*100+0.5) : floor(Int,value*100+0.5)
class_number(value) = fld(magnitude_hundredths(value)+5,10)
function magnitude_class(value)
    absolute = abs(value)
    (value<0 ? "-" : "")*"$(absolute÷10).$(absolute%10)"
end
function frequency_statistics(magnitudes)
    classes = class_number.(magnitudes)
    counts = Dict(t=>count(==(t),classes) for t in sort(unique(classes)))
    completeness = argmin(t->(-counts[t],t),collect(keys(counts)))
    above = [t for t in classes if t>=completeness]
    mc = completeness/10
    mean = sum(above)/(10length(above))
    b = 0.4342944819032518/(mean-(mc-0.05))
    (
        counts=counts,
        completeness=completeness,
        nb=length(above),
        b=b,
        sigma=b/sqrt(length(above)),
        a=base10log(length(above))+b*mc
    )
end
