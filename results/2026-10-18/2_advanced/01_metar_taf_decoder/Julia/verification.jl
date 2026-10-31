const CATEGORIES = ("VFR", "MVFR", "IFR", "LIFR")
covers(f, t) = f.issue <= t && f.start <= hourmark(t)<f.stop
function chosenforecast(fs, t)
    chosen = nothing
    for f in fs
        if covers(f, t) && (isnothing(chosen) || f.issue >= chosen.issue)
            chosen = f
        end
    end
    chosen
end
mutable struct Contingency
    table::Matrix{Int}
    temporaryhits::Int
end
Contingency() = Contingency(zeros(Int, 4, 4), 0)
function add!(c, f, o, hit)
    c.table[findfirst( == (f), CATEGORIES), findfirst( == (o), CATEGORIES)] += 1
    c.temporaryhits += hit
end
rowtotal(c, i) = sum(c.table[i, :])
coltotal(c, i) = sum(c.table[:, i])
total(c) = sum(c.table)
hits(c) = (sum(c.table[i, i] for i in 1:4), total(c))
temporaryhits(c) = (c.temporaryhits, total(c))
function skill(c)
    k, n = hits(c)
    e = sum(rowtotal(c, i)*coltotal(c, i) for i in 1:4)
    n*k-e, n*n-e
end
pod(c, i) = (c.table[i, i], coltotal(c, i))
far(c, i) = (rowtotal(c, i)-c.table[i, i], rowtotal(c, i))
