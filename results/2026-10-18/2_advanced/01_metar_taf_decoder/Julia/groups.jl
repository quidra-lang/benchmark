const MODIFIERS = Dict("AUTO" => "automated", "COR" => "corrected")
const DESCRIPTORS = Dict("MI" => "shallow", "BC" => "patches", "PR" => "partial", "DR" => "low drifting", "BL" => "blowing",
    "SH" => "showers", "TS" => "thunderstorm", "FZ" => "freezing")
const PHENOMENA = Dict(zip(split("DZ RA SN SG IC PL GR GS UP BR FG FU VA DU SA HZ PY PO SQ FC SS DS"), ["drizzle", "rain", "snow", "snow grains", "ice crystals", "ice pellets", "hail", "small hail", "unknown precipitation", "mist", "fog", "smoke", "volcanic ash", "dust", "sand", "haze", "spray", "dust whirls", "squalls", "funnel cloud", "sandstorm", "duststorm"]))
const PRECIPITATION = split("DZ RA SN SG IC PL GR GS UP")
const INTENSITIES = Dict("-" => "light", "+" => "heavy", "VC" => "nearby")
const AMOUNTS = Dict("FEW" => "few", "SCT" => "scattered", "BKN" => "broken", "OVC" => "overcast")
const CLOUDTYPES = Dict("CB" => "cumulonimbus", "TCU" => "towering cumulus")
const CLEAR = Dict("SKC" => "sky clear", "CLR" => "clear below 12000 ft", "NSC" => "no significant cloud")
mutable struct State
    wind::Any
    visibility::Any
    weather::Any
    cloud::Any
end
State() = State(nothing, nothing, nothing, nothing)
mutable struct Section
    state::State
    runways::Vector{String}
    allowsnsw::Bool
    modifier::String
    variation::Any
    rvrs::Vector{Any}
    temperature::Any
    pressure::Any
    notrend::Bool
end
Section(runways = String[], nsw = false) = Section(State(), runways, nsw, "", nothing, [], nothing, nothing, false)
calm(w) = !w.variable && w.direction == 0 && w.speed == 0
directed(w) = !w.variable && !calm(w)
strength(w) = isnothing(w.gust) ? w.speed : w.gust
num(s) = parse(Int, s)
function parsegroup(k, t)
    if k == :modifier
        return haskey(MODIFIERS, t) ? t : nothing
    elseif k == :wind
        m = match(r"^(VRB|[0-9]{3})([0-9]{2,3})(?:G([0-9]{2,3}))?(KT|MPS)$", t)
        isnothing(m) && return nothing
        d, s, g, u = m.captures
        return (variable = d == "VRB", direction = d == "VRB" ? 0 : num(d), speed = num(s), gust = isnothing(g) ? nothing : num(g), unit = u)
    elseif k == :variation
        m = match(r"^([0-9]{3})V([0-9]{3})$", t)
        return isnothing(m) ? nothing : (num(m[1]), num(m[2]))
    elseif k == :visibility
        t == "CAVOK" && return (kind = :cavok, qual = "P", meters = 10000, whole = 0, num = 0, den = 0, joined = false)
        if occursin(r"^[0-9]{4}$", t)
            return (kind = :meters, qual = t == "9999" ? "P" : "", meters = t == "9999" ? 10000 : num(t), whole = 0, num = 0, den = 0, joined = false)
        end
        m = match(r"^([MP]?)(?:([0-9]{1,2})|([0-9])/([0-9]{1,2}))SM$", t)
        if !isnothing(m)
            return (kind = :miles, qual = m[1], meters = 0, whole = isnothing(m[2]) ? 0 : num(m[2]),
                num = isnothing(m[3]) ? 0 : num(m[3]), den = isnothing(m[4]) ? 0 : num(m[4]), joined = false)
        end
        m = match(r"^([0-9]) ([0-9])/([0-9]{1,2})SM$", t)
        return isnothing(m) ? nothing : (kind = :miles, qual = "", meters = 0, whole = num(m[1]), num = num(m[2]), den = num(m[3]), joined = true)
    elseif k == :rvr
        m = match(r"^R([0-9]{2}[LCR]?)/([MP]?)([0-9]{4})(?:V([MP]?)([0-9]{4}))?(FT)?([UDN]?)$", t)
        isnothing(m) && return nothing
        readings = [(qual = m[2], value = num(m[3]))]
        !isnothing(m[5]) && push!(readings, (qual = m[4], value = num(m[5])))
        return (runway = m[1], readings = readings, feet = !isnothing(m[6]), trend = m[7])
    elseif k == :weather
        t == "NSW" && return (intensity = "", codes = String[], text = t)
        m = match(r"^(-|\+|VC)?((?:[A-Z]{2})+)$", t)
        isnothing(m) && return nothing
        codes = [String(m[2][i:i+1]) for i in 1:2:length(m[2])]
        all(c -> haskey(DESCRIPTORS, c)||haskey(PHENOMENA, c), codes) || return nothing
        return (intensity = isnothing(m[1]) ? "" : m[1], codes = codes, text = t)
    elseif k == :cloud
        haskey(CLEAR, t) && return (amount = t, height = nothing, ctype = "", text = t)
        m = match(r"^VV([0-9]{3})$", t)
        !isnothing(m) && return (amount = "VV", height = 100*num(m[1]), ctype = "", text = t)
        m = match(r"^(FEW|SCT|BKN|OVC)([0-9]{3})(CB|TCU)?$", t)
        return isnothing(m) ? nothing : (amount = m[1], height = 100*num(m[2]), ctype = isnothing(m[3]) ? "" : m[3], text = t)
    elseif k == :temperature
        m = match(r"^(M?[0-9]{2})/(M?[0-9]{2})$", t)
        isnothing(m) && return nothing
        c(s) = startswith(s, "M") ? -num(s[2:end]) : num(s)
        return (air = c(m[1]), dew = c(m[2]))
    elseif k == :pressure
        m = match(r"^([AQ])([0-9]{4})$", t)
        return isnothing(m) ? nothing : (unit = m[1], value = num(m[2]))
    end
    t == "NOSIG" ? true : nothing
end
descriptor(w) = !isempty(w.codes) && haskey(DESCRIPTORS, first(w.codes)) ? first(w.codes) : ""
phenomena(w) = filter(c -> haskey(PHENOMENA, c), w.codes)
function validgroup(k, v, s)
    if k == :wind
        (v.variable ? v.speed >= 1 : v.direction <= 360 && v.direction%10 == 0 && ((v.direction == 0) == (v.speed == 0))) || return false
        return isnothing(v.gust) || (!calm(v) && v.gust > v.speed)
    elseif k == :variation
        return all(d -> 10 <= d <= 360 && d%10 == 0, v) && v[1] != v[2] && !isnothing(s.state.wind) && directed(s.state.wind)
    elseif k == :visibility
        v.kind != :miles && return true
        v.den == 0 && return !v.joined && v.whole >= 1
        return (!v.joined || v.whole >= 1) && v.den in (2, 4, 8, 16) && 1 <= v.num<v.den
    elseif k == :rvr
        return v.runway in s.runways && (length(v.readings) == 1 || v.readings[1].value<v.readings[2].value)
    elseif k == :weather
        a = something(s.state.weather, [])
        (length(a)<3 && !any(w -> w.text == "NSW", a)) || return false
        v.text == "NSW" && return s.allowsnsw && isempty(a)
        any(c -> haskey(DESCRIPTORS, c), v.codes[2:end]) && return false
        p = phenomena(v)
        length(unique(p)) == length(p) || return false
        isempty(p) && !(descriptor(v) in ("TS", "SH")) && return false
        v.intensity in ("-", "+") && !any(c -> c in PRECIPITATION, p) && return false
        return length(p)<2 || all(c -> c in PRECIPITATION, p)
    elseif k == :cloud
        a = something(s.state.cloud, [])
        return isempty(a) || (haskey(AMOUNTS, v.amount) && haskey(AMOUNTS, last(a).amount) && v.height>last(a).height)
    elseif k == :temperature
        return v.dew <= v.air
    elseif k == :pressure
        return v.unit == "A" ? 2500 <= v.value <= 3150 : 850 <= v.value <= 1070
    end
    true
end
function record!(s, k, v)
    if k == :wind
        s.state.wind = merge(v, (speed = knots(v.speed, v.unit), gust = isnothing(v.gust) ? nothing : knots(v.gust, v.unit), unit = "KT"))
    elseif k in (:visibility, :weather, :cloud)
        if k in (:weather, :cloud)
            isnothing(getfield(s.state, k)) && setfield!(s.state, k, Any[])
            push!(getfield(s.state, k), v)
        else
            s.state.visibility = v
        end
    elseif k == :rvr
        push!(s.rvrs, v)
    elseif k == :notrend
        s.notrend = true
    else
        setfield!(s, k, v)
    end
end
