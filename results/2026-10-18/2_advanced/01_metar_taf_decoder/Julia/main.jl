include("units.jl")
include("groups.jl")
include("metar.jl")
include("taf.jl")
include("verification.jl")

function readstations()
    stations = Dict{String, Any}()
    for line in eachline("input/stations.txt")
        code, elevation, rs, name = split(line, ' ';limit = 4)
        runways = [(name = String(first(split(r, '/'))), heading = num(last(split(r, '/')))) for r in split(rs, ',')]
        stations[code] = (code = String(code), elevation = num(elevation), runways = runways, name = String(name))
    end
    stations
end
function readsettings()
    p = Dict(first(split(l, ' ';limit = 2)) => last(split(l, ' ';limit = 2)) for l in eachline("input/params.txt"))
    (calendar = Calendar(num(p["YEAR"]), num(p["MONTH"])), cross = num(p["CROSSWIND_LIMIT"]), tail = num(p["TAILWIND_LIMIT"]),
        verified = split(p["VERIFY"]))
end
function readreports()
    reports = []
    for line in eachline("input/reports.txt")
        words = String.(split(line))
        if startswith(line, " ")
            append!(reports[end].words, words)
        else
            push!(reports, (number = length(reports)+1, words = words, errors = Tuple{Int, String}[]))
        end
    end
    reports
end
function parsetime(t, c)
    occursin(r"^[0-9]{6}Z$", t) || return nothing
    d, h, m = num(t[1:2]), num(t[3:4]), num(t[5:6])
    1 <= d <= c.days && h <= 23 && m <= 59 ? dayminutes(d, h, m) : nothing
end
function joingroups(ws, i)
    gs = Tuple{Int, String}[]
    while i <= length(ws)
        p, t = i, ws[i]
        i += 1
        if occursin(r"^[0-9]$", t) && i <= length(ws) && occursin(r"^[0-9]/[0-9]{1,2}SM$", ws[i])
            t *= " "*ws[i]
            i += 1
        end
        push!(gs, (p, t))
    end
    gs
end
function header(r, stations, c)
    ws = r.words
    k = ws[1]
    if !(k in ("METAR", "SPECI", "TAF"))
        push!(r.errors, (1, "rejected report, invalid type \"$k\""))
        return nothing
    end
    i = 2
    modifier = ""
    station = nothing
    t = nothing
    validity = nothing
    if k == "TAF" && i <= length(ws) && ws[i] in ("AMD", "COR")
        modifier = ws[i]
        i += 1
    end
    for item in (k == "TAF" ? ("station", "time", "validity") : ("station", "time"))
        if i>length(ws)
            push!(r.errors, (i, "rejected report, missing $item"))
            return nothing
        end
        w = ws[i]
        valid = if item == "station"
            station = get(stations, w, nothing)
            !isnothing(station)
        elseif item == "time"
            t = parsetime(w, c)
            !isnothing(t)
        else
            validity = period(w, dayof(t), c)
            !isnothing(validity) && validity[2] <= validity[1]+1800
        end
        if !valid
            push!(r.errors, (i, "rejected report, invalid $item \"$w\""))
            return nothing
        end
        i += 1
    end
    (kind = k, modifier = modifier, station = station, time = t, validity = validity, body = joingroups(ws, i))
end
function matchgroups!(gs, slots, s, errors)
    current = 1
    for (pos, t) in gs
        index = 0
        value = nothing
        for j in current:length(slots)
            value = parsegroup(slots[j][1], t)
            if !isnothing(value)
                index = j
                break
            end
        end
        if index == 0
            earlier = any(j -> !isnothing(parsegroup(slots[j][1], t)), 1:current-1)
            label = earlier ? "out of order group" : "unknown group"
            push!(errors, (pos, "$label \"$t\""))
            continue
        end
        k, repeatable = slots[index]
        if !validgroup(k, value, s)
            push!(errors, (pos, "invalid group \"$t\""))
            continue
        end
        record!(s, k, value)
        if k == :visibility && value.kind == :cavok
            s.state.weather = []
            s.state.cloud = []
            current = findfirst(x -> x[1] == :cloud, slots)+1
        else
            current = index+!repeatable
        end
    end
    s
end
function forecaststate(gs, nsw, errors)
    matchgroups!(gs, TAF_SLOTS, Section(String[], nsw), errors).state
end
function decodeforecast(r, h, c)
    f = Taf(r.number, h.station, h.time, h.modifier, h.validity..., State(), Change[])
    gs, f.changes = splitchanges(f, h.body, c, r.errors)
    f.base = forecaststate(gs, false, r.errors)
    for ch in f.changes
        ch.state = forecaststate(ch.groups, true, r.errors)
    end
    f
end
function ceiling(s)
    for c in something(s.cloud, [])
        c.amount in ("BKN", "OVC", "VV") && return c.height
    end
    nothing
end
function category(s)
    h = ceiling(s)
    v = isnothing(s.visibility) ? nothing : miles(s.visibility)
    (!isnothing(h) && h<500 || !isnothing(v) && v<1) && return "LIFR"
    (!isnothing(h) && h<1000 || !isnothing(v) && v<3) && return "IFR"
    (!isnothing(h) && h <= 3000 || !isnothing(v) && v <= 5) && return "MVFR"
    "VFR"
end
inhgvalue(p) = p.unit == "A" ? p.value : inhg(p.value)
components(d, h, w) = (fld(w*icos(d-h), 1000), fld(w*isin(d-h), 1000))
function runwaywinds(st, w, p)
    (isnothing(w) || !directed(w)) && return nothing
    winds = []
    for r in st.runways
        mean = components(w.direction, r.heading, w.speed)
        gust = isnothing(w.gust) ? nothing : components(w.direction, r.heading, w.gust)
        head, cross = isnothing(gust) ? mean : gust
        push!(winds, (runway = r, mean = mean, gust = gust, usable = abs(cross) <= p.cross && -head <= p.tail))
    end
    winds
end
function windchanges(a, b, angle)
    (isnothing(a) || isnothing(b)) && return String[]
    reasons = String[]
    d = mod(abs(a.direction-b.direction), 360)
    directed(a) && directed(b) && max(a.speed, b.speed) >= 10 && min(d, 360-d) >= angle && push!(reasons, "wind shift")
    abs(a.speed-b.speed) >= 10 && push!(reasons, "wind speed")
    reasons
end
thunder(s) = any(w -> descriptor(w) == "TS", something(s.weather, []))
freezing(s) = any(w -> descriptor(w) == "FZ" && any(c -> c in ("DZ", "RA"), phenomena(w)), something(s.weather, []))
function specreasons(previous, o)
    isnothing(previous) && return ["no previous report"]
    a, b = previous.main.state, o.main.state
    rs = String[]
    previous.category != o.category && push!(rs, "category $(previous.category) to $(o.category)")
    append!(rs, windchanges(a.wind, b.wind, 45))
    thunder(a) != thunder(b) && push!(rs, thunder(b) ? "thunderstorm began" : "thunderstorm ended")
    freezing(a) != freezing(b) && push!(rs, freezing(b) ? "freezing precipitation began" : "freezing precipitation ended")
    isempty(rs) ? ["no criteria met"] : rs
end
function decodeobservation(r, h, previous, p)
    mainpart, trendpart, remarks = splitbody(h.body)
    s = matchgroups!(mainpart, MAIN_SLOTS, Section([r.name for r in h.station.runways]), r.errors)
    trends = []
    for gs in trendsections(trendpart)
        t = readtrend(gs, r.errors)
        if !isnothing(t)
            ts = matchgroups!(t.groups, TREND_SLOTS, Section(String[], true), r.errors)
            push!(trends, merge(t, (state = ts.state, )))
        end
    end
    slp, temps = readremarks(remarks)
    pa = isnothing(s.pressure) ? nothing : h.station.elevation+10*(2992-inhgvalue(s.pressure))
    da = isnothing(pa) || isnothing(s.temperature) ? nothing : pa+fld(120*(1000*s.temperature.air-15000+2*pa), 1000)
    o = (number = r.number, kind = h.kind, station = h.station, time = h.time, main = s, trends = trends, slp = slp,
        temps = temps, ceiling = ceiling(s.state), category = category(s.state), pa = pa, da = da,
        winds = runwaywinds(h.station, s.state.wind, p))
    merge(o, (reasons = h.kind == "SPECI" ? specreasons(previous, o) : String[], ))
end

const QUALIFIERS = Dict("" => "", "M" => "less than ", "P" => "more than ")
function windphrase(w)
    t = calm(w) ? "calm" : w.variable ? "variable at $(w.speed) KT" : "$(pad(w.direction,3)) degrees at $(w.speed) KT"
    isnothing(w.gust) ? t : t*" gusting $(w.gust) KT"
end
function milenumber(v)
    v.den == 0 && return string(v.whole)
    (v.whole == 0 ? "" : "$(v.whole) ")*"$(v.num)/$(v.den)"
end
function visibilityphrase(v)
    v.kind == :cavok && return "10 km or more (CAVOK)"
    v.kind == :meters && return v.qual == "P" ? "10 km or more" : "$(v.meters) m"
    QUALIFIERS[v.qual]*milenumber(v)*" SM"
end
function weatherphrase(w)
    w.text == "NSW" && return "no significant weather"
    ps = String[]
    !isempty(w.intensity) && push!(ps, INTENSITIES[w.intensity])
    !isempty(descriptor(w)) && push!(ps, DESCRIPTORS[descriptor(w)])
    !isempty(phenomena(w)) && push!(ps, join((PHENOMENA[c] for c in phenomena(w)), " and "))
    join(ps, " ")
end
function cloudphrase(c)
    haskey(CLEAR, c.amount) && return CLEAR[c.amount]
    c.amount == "VV" && return "vertical visibility $(c.height) ft"
    AMOUNTS[c.amount]*" at $(c.height) ft"*(isempty(c.ctype) ? "" : " "*CLOUDTYPES[c.ctype])
end
function statesummary(s)
    ps = String[]
    !isnothing(s.wind) && push!(ps, "wind "*windphrase(s.wind))
    !isnothing(s.visibility) && push!(ps, "visibility "*visibilityphrase(s.visibility))
    !isempty(something(s.weather, [])) && push!(ps, "weather "*join(weatherphrase.(s.weather), ", "))
    !isempty(something(s.cloud, [])) && push!(ps, "cloud "*join(cloudphrase.(s.cloud), ", "))
    isempty(ps) ? "no conditions" : join(ps, "; ")
end
function windcode(w)
    calm(w) && return "00000KT"
    (w.variable ? "VRB" : pad(w.direction, 3))*pad(w.speed, 2)*(isnothing(w.gust) ? "" : "G"*pad(w.gust, 2))*"KT"
end
visibilitycode(v) = v.kind == :cavok ? "CAVOK" : v.kind == :meters ? (v.qual == "P" ? "9999" : pad(v.meters, 4)) : v.qual*milenumber(v)*"SM"
function tokens(s)
    ps = String[]
    !isnothing(s.wind) && push!(ps, windcode(s.wind))
    !isnothing(s.visibility) && push!(ps, visibilitycode(s.visibility))
    append!(ps, [w.text for w in something(s.weather, []) if w.text != "NSW"])
    append!(ps, [c.text for c in something(s.cloud, [])])
    push!(ps, category(s))
    join(ps, " ")
end
tenths(v) = (v<0 ? "-" : "")*"$(div(abs(v),10)).$(mod(abs(v),10))"
inhgtext(v) = "$(fld(v,100)).$(pad(mod(v,100),2))"
function componentphrase(h, c)
    t = h<0 ? "tailwind $(-h) KT" : "headwind $h KT"
    t*", crosswind $(abs(c)) KT"*(c == 0 ? "" : c>0 ? " from right" : " from left")
end
function rvrphrase(r)
    readings = [QUALIFIERS[v.qual]*string(v.value) for v in r.readings]
    t = "runway $(r.runway) "*(length(readings) == 1 ? readings[1] : "between "*join(readings, " and "))*(r.feet ? " ft" : " m")
    isempty(r.trend) ? t : t*", "*Dict("U" => "rising", "D" => "falling", "N" => "no change")[r.trend]
end
function temperaturephrase(t)
    isnothing(t) ? "not reported" : "$(t.air) C, dew point $(t.dew) C, spread $(t.air-t.dew) C"
end
function altimeterphrase(p)
    isnothing(p) && return "not reported"
    a = inhgtext(inhgvalue(p))
    p.unit == "A" ? "$a inHg ($(hpa(p.value)) hPa)" : "$(p.value) hPa ($a inHg)"
end
altitudetext(v) = isnothing(v) ? "not available" : "$v ft"
title(s) = "$(s.code) ($(s.name))"
function observationlines(o, c)
    m = o.main
    s = m.state
    ls = ["REPORT $(o.number): $(o.kind) $(title(o.station))", "  time: "*stamp(c, o.time)]
    !isempty(m.modifier) && push!(ls, "  modifier: "*MODIFIERS[m.modifier])
    w = isnothing(s.wind) ? "not reported" : windphrase(s.wind)
    if !isnothing(m.variation)
        w *= ", varying between $(pad(m.variation[1],3)) and $(pad(m.variation[2],3)) degrees"
    end
    push!(ls, "  wind: "*w, "  visibility: "*(isnothing(s.visibility) ? "not reported" : visibilityphrase(s.visibility)))
    append!(ls, ["  runway visual range: "*rvrphrase(r) for r in m.rvrs])
    append!(ls, ["  weather: "*weatherphrase(w) for w in something(s.weather, [])])
    clouds = !isnothing(s.visibility) && s.visibility.kind == :cavok ? ["no significant cloud"] : isnothing(s.cloud) ? ["not reported"] : cloudphrase.(s.cloud)
    append!(ls, ["  cloud: "*t for t in clouds])
    push!(ls, "  temperature: "*temperaturephrase(m.temperature), "  altimeter: "*altimeterphrase(m.pressure))
    m.notrend && push!(ls, "  trend: no significant change")
    for t in o.trends
        text = t.kind == "BECMG" ? "becoming" : "temporarily"
        for (prefix, h, mm) in t.times
            text *= " "*Dict("FM" => "from", "TL" => "until", "AT" => "at")[prefix]*" $(pad(h,2)):$(pad(mm,2))Z"
        end
        push!(ls, "  trend: $text: "*statesummary(t.state))
    end
    append!(ls, ["  sea level pressure: $(tenths(v)) hPa" for v in o.slp])
    append!(ls, ["  precise temperature: $(tenths(a)) C, dew point $(tenths(d)) C" for (a, d) in o.temps])
    push!(ls, "  ceiling: "*(isnothing(o.ceiling) ? "none" : "$(o.ceiling) ft"), "  flight category: "*o.category,
        "  pressure altitude: "*altitudetext(o.pa), "  density altitude: "*altitudetext(o.da))
    if isnothing(o.winds)
        push!(ls, "  runway wind: not computed")
    else
        usable = filter(w -> w.usable, o.winds)
        preferred = nothing
        for w in o.winds
            text = "  runway $(w.runway.name): "*componentphrase(w.mean...)
            !isnothing(w.gust) && (text *= "; gusts "*componentphrase(w.gust...))
            push!(ls, text)
            w.usable && (isnothing(preferred) || w.mean[1]>preferred.mean[1]) && (preferred = w)
        end
        push!(ls, "  usable runways: "*(isempty(usable) ? "none" : join([w.runway.name for w in usable], " ")),
            "  preferred runway: "*(isnothing(preferred) ? "none" : preferred.runway.name))
    end
    o.kind == "SPECI" && push!(ls, "  speci check: "*join(o.reasons, ", "))
    ls
end
function forecastlines(f, c)
    ls = ["REPORT $(f.number): TAF $(title(f.station))", "  issued: "*stamp(c, f.issue)]
    !isempty(f.modifier) && push!(ls, "  modifier: "*(f.modifier == "AMD" ? "amended" : "corrected"))
    push!(ls, "  valid: $(stamp(c,f.start)) to $(stamp(c,f.stop))", "  base: "*statesummary(f.base))
    for ch in f.changes
        p = stamp(c, ch.start)*(ch.kind == "FM" ? "" : " to "*stamp(c, ch.stop))
        push!(ls, "  $(ch.kind) $p: "*statesummary(ch.state))
    end
    ls
end
categorycounts(cs) = join(["$k $(count(==(k),cs))" for k in CATEGORIES], ", ")
function categorylines(os, c)
    ls = ["station,time,ceiling,visibility,category"]
    for o in os
        v = o.main.state.visibility
        push!(ls,
            join((o.station.code, stamp(c, o.time), isnothing(o.ceiling) ? "NONE" : string(o.ceiling), isnothing(v) ? "NONE" : v.qual*string(meters(v)), o.category), ","))
    end
    ls
end
function timelinelines(f, c)
    ls = ["TAF $(f.station.code) issued $(stamp(c,f.issue)) valid $(stamp(c,f.start)) to $(stamp(c,f.stop))"]
    cs = String[]
    for h in f.start:60:f.stop-1
        s = prevailing(f, h)
        line = stamp(c, h)*" "*tokens(s)
        for (kind, t) in temporary(f, h)
            line *= " | $kind "*tokens(t)
        end
        push!(ls, line)
        push!(cs, category(s))
    end
    push!(ls, "summary: "*categorycounts(cs))
    ls
end
function extremelines(os, c)
    ls = String[]
    specs = [("lowest temperature", o -> isnothing(o.main.temperature) ? nothing : o.main.temperature.air, false, o -> "$(o.main.temperature.air) C"),
    ("highest temperature", o -> isnothing(o.main.temperature) ? nothing : o.main.temperature.air, true, o -> "$(o.main.temperature.air) C"),
    ("strongest wind", o -> isnothing(o.main.state.wind) ? nothing : strength(o.main.state.wind), true, o -> windphrase(o.main.state.wind)),
    ("lowest ceiling", o -> o.ceiling, false, o -> "$(o.ceiling) ft"),
    ("lowest visibility", o -> isnothing(o.main.state.visibility) ? nothing : miles(o.main.state.visibility), false,
        o -> visibilityphrase(o.main.state.visibility))]
    for (label, value, maximum, describe) in specs
        best = nothing
        bv = nothing
        for o in os
            v = value(o)
            if !isnothing(v) && (isnothing(best) || (maximum ? v>bv : v<bv))
                best = o
                bv = v
            end
        end
        push!(ls, label*": "*(isnothing(best) ? "not available" : describe(best)*" at "*stamp(c, best.time)))
    end
    ls
end
tablerow(label, cells) = rpad(label, 8)*join(lpad.(string.(cells), 6))
function verificationlines(st, observations, forecasts, c)
    os = filter(o -> o.station.code == st.code, observations)
    fs = filter(f -> f.station.code == st.code, forecasts)
    mc = count(o -> o.kind == "METAR", os)
    ls = ["station "*title(st), "reports: METAR $mc, SPECI $(length(os)-mc)", "observed categories: "*categorycounts([o.category for o in os])]
    append!(ls, extremelines(os, c))
    ct = Contingency()
    noforecast = 0
    amendments = String[]
    for o in os
        f = chosenforecast(fs, o.time)
        if isnothing(f)
            noforecast += 1
            continue
        end
        h = hourmark(o.time)
        s = prevailing(f, h)
        expected = category(s)
        alternatives = [expected; [category(t) for (_, t) in temporary(f, h)]]
        hit = o.category in alternatives
        add!(ct, expected, o.category, hit)
        reasons = String[]
        !hit && push!(reasons, "category $(o.category), forecast $expected")
        !isempty(windchanges(s.wind, o.main.state.wind, 60)) && push!(reasons, "wind $(windcode(o.main.state.wind)), forecast $(windcode(s.wind))")
        !isempty(reasons) && push!(amendments, "amendment $(stamp(c,o.time)): "*join(reasons, "; "))
    end
    push!(ls, "verified: $(total(ct))", "no forecast: $noforecast", tablerow("forecast", [CATEGORIES... , "total"]))
    for (i, k) in enumerate(CATEGORIES)
        push!(ls, tablerow(k, [ct.table[i, :];rowtotal(ct, i)]))
    end
    push!(ls, tablerow("total", [ [coltotal(ct, i) for i in 1:4]; total(ct)]))
    push!(ls, "hit rate: "*fraction(hits(ct)...), "hit rate with temporary groups: "*fraction(temporaryhits(ct)...),
        "heidke skill score: "*fraction(skill(ct)...))
    for (i, k) in enumerate(CATEGORIES)
        push!(ls, "$k: pod $(fraction(pod(ct,i)...)), far $(fraction(far(ct,i)...))")
    end
    pairs = zeros(Int, 5)
    bhits = zeros(Int, 5)
    for f in fs, o in os
        covers(f, o.time) || continue
        h = hourmark(o.time)
        b = fld(h-f.start, 360)+1
        pairs[b] += 1
        bhits[b] += category(prevailing(f, h)) == o.category
    end
    for b in 1:5
        push!(ls, "hours $(6*(b-1))-$(6*b-1): "*fraction(bhits[b], pairs[b]))
    end
    append!(ls, amendments)
    ls
end
function writeoutput(name, lines)
    open("output/"*name, "w") do io
        for line in lines
            write(io, line, '\n')
        end
    end
end
blocks(bs) = split(join([join(b, "\n") for b in bs], "\n\n"), '\n';keepempty = true)
function writeblocks(name, bs)
    writeoutput(name, isempty(bs) ? String[] : blocks(bs))
end
function main()
    stations = readstations()
    p = readsettings()
    c = p.calendar
    rs = readreports()
    os = []
    fs = []
    decoded = []
    latest = Dict{String, Any}()
    for r in rs
        h = header(r, stations, c)
        isnothing(h) && continue
        if h.kind == "TAF"
            f = decodeforecast(r, h, c)
            push!(fs, f)
            push!(decoded, forecastlines(f, c))
        else
            o = decodeobservation(r, h, get(latest, h.station.code, nothing), p)
            latest[h.station.code] = o
            push!(os, o)
            push!(decoded, observationlines(o, c))
        end
    end
    mkpath("output")
    writeblocks("decoded.txt", decoded)
    writeoutput("categories.csv", categorylines(os, c))
    writeblocks("taf_timeline.txt", [timelinelines(f, c) for f in fs])
    writeblocks("verification.txt", [verificationlines(stations[s], os, fs, c) for s in p.verified])
    errors = String[]
    for r in rs, (pos, msg) in sort(r.errors;by = first, alg = MergeSort)
        push!(errors, "report $(r.number) word $pos: $msg")
    end
    writeoutput("errors.txt", errors)
end
main()
