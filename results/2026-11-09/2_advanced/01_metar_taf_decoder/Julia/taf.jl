const TAF_SLOTS = TREND_SLOTS
const TEMPORARY = ("TEMPO", "PROB30", "PROB40", "PROB30 TEMPO", "PROB40 TEMPO")
mutable struct Change
    kind::String
    start::Int
    stop::Union{Int, Nothing}
    groups::Vector
    state::State
end
mutable struct Taf
    number::Int
    station::Any
    issue::Int
    modifier::String
    start::Int
    stop::Int
    base::State
    changes::Vector{Change}
end
isfm(t) = occursin(r"^FM[0-9]{6}$", t)
isindicator(t) = t in ("BECMG", "TEMPO", "PROB30", "PROB40") || isfm(t)
isperiod(t) = occursin(r"^[0-9]{4}/[0-9]{4}$", t)
function period(t, issueday, c)
    isperiod(t) || return nothing
    h1, h2 = num(t[3:4]), num(t[8:9])
    h1 <= 23 && 1 <= h2 <= 24 || return nothing
    s, e = forecasttime(c, num(t[1:2]), h1, 0, issueday), forecasttime(c, num(t[6:7]), h2, 0, issueday)
    isnothing(s) || isnothing(e) || s >= e ? nothing : (s, e)
end
function splitchanges(f, gs, c, errors)
    i = 1
    while i <= length(gs) && !isindicator(gs[i][2])
        i += 1
    end
    base = gs[1:i-1]
    changes = Change[]
    while i <= length(gs)
        pos, k = gs[i]
        i += 1
        if k in ("PROB30", "PROB40") && i <= length(gs) && gs[i][2] == "TEMPO"
            k *= " TEMPO"
            i += 1
        end
        change = nothing
        if isfm(k)
            h, m = num(k[5:6]), num(k[7:8])
            t = h <= 23 && m <= 59 ? forecasttime(c, num(k[3:4]), h, m, dayof(f.issue)) : nothing
            if isnothing(t) || !(f.start <= t<f.stop)
                push!(errors, (pos, "invalid period \"$k\""))
            else
                change = Change("FM", t, nothing, [], State())
            end
        elseif i>length(gs) || !isperiod(gs[i][2])
            push!(errors, (pos, "missing period \"$k\""))
        else
            p, t = gs[i]
            i += 1
            v = period(t, dayof(f.issue), c)
            if isnothing(v) || v[1]<f.start || v[2]>f.stop
                push!(errors, (p, "invalid period \"$t\""))
            else
                change = Change(k, v[1], v[2], [], State())
            end
        end
        j = i
        while j <= length(gs) && !isindicator(gs[j][2])
            j += 1
        end
        if !isnothing(change)
            change.groups = gs[i:j-1]
            push!(changes, change)
        end
        i = j
    end
    base, changes
end
overlay(s, c) = State((isnothing(getfield(c, k)) ? getfield(s, k) : getfield(c, k) for k in fieldnames(State))...)
function prevailing(f, h)
    s = f.base
    for c in f.changes
        if c.kind == "FM" && c.start <= h
            s = c.state
        elseif c.kind == "BECMG" && c.stop <= h
            s = overlay(s, c.state)
        end
    end
    s
end
temporary(f, h) = [(c.kind, overlay(prevailing(f, h), c.state)) for c in f.changes if c.kind in TEMPORARY && c.start <= h<c.stop]
