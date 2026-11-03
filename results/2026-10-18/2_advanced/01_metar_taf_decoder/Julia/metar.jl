const MAIN_SLOTS = [(:modifier, false), (:wind, false), (:variation, false), (:visibility, false), (:rvr, true), (:weather, true),
    (:cloud, true), (:temperature, false), (:pressure, false), (:notrend, false)]
const TREND_SLOTS = [(:wind, false), (:visibility, false), (:weather, true), (:cloud, true)]
function splitbody(gs)
    r = findfirst(g -> g[2] == "RMK", gs)
    remarks = isnothing(r) ? [] : gs[r+1:end]
    body = isnothing(r) ? gs : gs[1:r-1]
    t = findfirst(g -> g[2] in ("BECMG", "TEMPO"), body)
    isnothing(t) ? (body, [], remarks) : (body[1:t-1], body[t:end], remarks)
end
function trendsections(gs)
    sections = Vector{Any}[]
    for g in gs
        g[2] in ("BECMG", "TEMPO") && push!(sections, Any[])
        push!(sections[end], g)
    end
    sections
end
function readtrend(gs, errors)
    istime(i, ps) = i <= length(gs) && occursin(r"^(FM|TL|AT)[0-9]{4}$", gs[i][2]) && gs[i][2][1:2] in ps
    n = istime(2, ("FM", )) ? (istime(3, ("TL", )) ? 2 : 1) : (istime(2, ("TL", "AT")) ? 1 : 0)
    times = []
    for (pos, t) in gs[2:n+1]
        h, m = num(t[3:4]), num(t[5:6])
        if h>23 || m>59
            push!(errors, (pos, "invalid period \"$t\""))
            return nothing
        end
        push!(times, (t[1:2], h, m))
    end
    (kind = gs[1][2], times = times, groups = gs[n+2:end])
end
function readremarks(gs)
    slp, temps = [], []
    signed(s) = (s[1] == '1' ? -1 : 1)*num(s[2:4])
    for (_, t) in gs
        if occursin(r"^SLP[0-9]{3}$", t)
            v = num(t[4:6])
            push!(slp, (v >= 500 ? 9000 : 10000)+v)
        elseif occursin(r"^T[01][0-9]{3}[01][0-9]{3}$", t)
            push!(temps, (signed(t[2:5]), signed(t[6:9])))
        end
    end
    slp, temps
end
