local U = require('units')
local G = {}
G.descriptors = {MI = 'shallow', BC = 'patches', PR = 'partial', DR = 'low drifting', BL = 'blowing', SH = 'showers', TS = 'thunderstorm', FZ = 'freezing'}
G.phenomena = {DZ = 'drizzle', RA = 'rain', SN = 'snow', SG = 'snow grains', IC = 'ice crystals', PL = 'ice pellets', GR = 'hail', GS = 'small hail', UP = 'unknown precipitation', BR = 'mist', FG = 'fog', FU = 'smoke', VA = 'volcanic ash', DU = 'dust', SA = 'sand', HZ = 'haze', PY = 'spray', PO = 'dust whirls', SQ = 'squalls', FC = 'funnel cloud', SS = 'sandstorm', DS = 'duststorm'}
G.precip = {DZ = true, RA = true, SN = true, SG = true, IC = true, PL = true, GR = true, GS = true, UP = true}
G.amounts = {FEW = 'few', SCT = 'scattered', BKN = 'broken', OVC = 'overcast'}
G.clear = {SKC = 'sky clear', CLR = 'clear below 12000 ft', NSC = 'no significant cloud'}
local function reading(s)
    local q = ''
    if s:sub(1, 1) == 'M' or s:sub(1, 1) == 'P' then
        q = s:sub(1, 1)
        s = s:sub(2)
    end
    if U.digits(s, 4) then
        return {q, tonumber(s)}
    end
end

function G.recognize(k, s)
    if k == 'modifier' then
        if s == 'AUTO' or s == 'COR' then
            return {code = s}
        end
    elseif k == 'wind' then
        local direction, rest = s:sub(1, 3), s:sub(4)
        if direction ~= 'VRB' and not U.digits(direction, 3) then
            return nil
        end
        local unit
        if rest:sub( -3) == 'MPS' then
            unit = 'MPS'
            rest = rest:sub(1, - 4)
        elseif rest:sub( -2) == 'KT' then
            unit = 'KT'
            rest = rest:sub(1, - 3)
        else
            return nil
        end
        local speed, gust = rest:match('^(%d+)G(%d+)$')
        if not speed then
            speed = rest
        end
        if not U.digits(speed, 2, 3) or (gust and not U.digits(gust, 2, 3)) then
            return nil
        end
        return {direction = direction == 'VRB' and 'VRB' or tonumber(direction), speed = tonumber(speed), gust = gust and tonumber(gust), unit = unit}
    elseif k == 'variation' then
        local a, b = s:match('^(%d%d%d)V(%d%d%d)$')
        if a then
            return {first = tonumber(a), last = tonumber(b)}
        end
    elseif k == 'visibility' then
        if s == 'CAVOK' then
            return {kind = 'cavok', value = 10000, qualifier = 'P'}
        end
        if U.digits(s, 4) then
            return {kind = 'meters', value = s == '9999' and 10000 or tonumber(s), qualifier = s == '9999' and 'P' or ''}
        end
        if s:sub( -2) ~= 'SM' then
            return nil
        end
        local body = s:sub(1, - 3)
        local q = ''
        if body:sub(1, 1) == 'M' or body:sub(1, 1) == 'P' then
            q = body:sub(1, 1)
            body = body:sub(2)
        end
        if U.digits(body, 1, 2) then
            return {kind = 'miles', whole = tonumber(body), num = 0, den = 1, qualifier = q, fraction = false}
        end
        local w, n, d = body:match('^(%d) (%d)/(%d+)$')
        if w then
            if q ~= '' or not U.digits(d, 1, 2) then
                return nil
            end
            return {kind = 'miles', whole = tonumber(w), num = tonumber(n), den = tonumber(d), qualifier = '', fraction = true, mixed = true}
        end
        n, d = body:match('^(%d)/(%d+)$')
        if n and U.digits(d, 1, 2) then
            return {kind = 'miles', whole = 0, num = tonumber(n), den = tonumber(d), qualifier = q, fraction = true}
        end
    elseif k == 'rvr' then
        local runway, body = s:match('^R([^/]+)/(.+)$')
        if not runway then
            return nil
        end
        if not (U.digits(runway, 2) or (#runway == 3 and U.digits(runway:sub(1, 2), 2) and runway:sub(3):match('^[LCR]$'))) then
            return nil
        end
        local trend = ''
        if body:sub( -1):match('^[UDN]$') then
            trend = body:sub( -1)
            body = body:sub(1, - 2)
        end
        local unit = 'm'
        if body:sub( -2) == 'FT' then
            unit = 'ft'
            body = body:sub(1, - 3)
        end
        local a, b = body:match('^([^V]+)V([^V]+)$')
        local rs = {}
        if a then
            local x, y = reading(a), reading(b)
            if not x or not y then
                return nil
            end
            rs = {x, y}
        else
            local x = reading(body)
            if not x then
                return nil
            end
            rs = {x}
        end
        return {runway = runway, readings = rs, unit = unit, trend = trend}
    elseif k == 'weather' then
        if s == 'NSW' then
            return {raw = s, nsw = true, phenomena = {}}
        end
        local body = s
        local intensity = ''
        if body:sub(1, 2) == 'VC' then
            intensity = 'VC'
            body = body:sub(3)
        elseif body:sub(1, 1) == '-' or body:sub(1, 1) == '+' then
            intensity = body:sub(1, 1)
            body = body:sub(2)
        end
        if #body == 0 or #body % 2 ~= 0 then
            return nil
        end
        local codes = {}
        for i = 1, #body, 2 do
            local c = body:sub(i, i + 1)
            if not G.descriptors[c] and not G.phenomena[c] then
                return nil
            end
            codes[#codes + 1] = c
        end
        local desc
        if G.descriptors[codes[1]] then
            desc = table.remove(codes, 1)
        end
        return {raw = s, nsw = false, intensity = intensity, descriptor = desc, phenomena = codes}
    elseif k == 'cloud' then
        local amount = s:sub(1, 3)
        if G.amounts[amount] then
            local height = s:sub(4, 6)
            local extra = s:sub(7)
            if U.digits(height, 3) and (extra == '' or extra == 'CB' or extra == 'TCU') then
                return {amount = amount, height = tonumber(height) * 100, extra = extra, layer = true}
            end
        elseif s:sub(1, 2) == 'VV' and U.digits(s:sub(3), 3) then
            return {amount = 'VV', height = tonumber(s:sub(3)) * 100, extra = '', layer = false}
        elseif G.clear[s] then
            return {amount = s, extra = '', layer = false}
        end
    elseif k == 'temperature' then
        local a, b = s:match('^([^/]+)/([^/]+)$')
        if not a then
            return nil
        end
        local function temp(t)
            local sign = 1
            if t:sub(1, 1) == 'M' then
                sign = -1
                t = t:sub(2)
            end
            if U.digits(t, 2) then
                return tonumber(t) * sign
            end
        end
        local t, d = temp(a), temp(b)
        if t and d then
            return {temperature = t, dew = d}
        end
    elseif k == 'pressure' then
        if (s:sub(1, 1) == 'A' or s:sub(1, 1) == 'Q') and U.digits(s:sub(2), 4) then
            return {unit = s:sub(1, 1), value = tonumber(s:sub(2))}
        end
    elseif k == 'nosig' and s == 'NOSIG' then
        return {code = s}
    end
end

function G.valid(k, v, s, station, change)
    if k == 'wind' then
        local d, w, g = v.direction, v.speed, v.gust
        if d == 'VRB' then
            if w < 1 then
                return false
            end
        elseif d > 360 or d % 10 ~= 0 or ((d == 0) ~= (w == 0)) or (d == 0 and g) then
            return false
        end
        return not g or g > w
    elseif k == 'variation' then
        local a, b, w = v.first, v.last, s.wind
        return a >= 10 and a <= 360 and b >= 10 and b <= 360 and a % 10 == 0 and b % 10 == 0 and a ~= b and w and w.direction ~= 'VRB' and w.direction ~= 0
    elseif k == 'visibility' then
        if v.kind ~= 'miles' then
            return true
        end
        if not v.fraction then
            return v.whole >= 1
        end
        return (v.den == 2 or v.den == 4 or v.den == 8 or v.den == 16) and v.num >= 1 and v.num < v.den and (not v.mixed or v.whole >= 1)
    elseif k == 'rvr' then
        local exists = false
        for _, r in ipairs(station.runways) do
            if r.name == v.runway then
                exists = true
            end
        end
        return exists and (#v.readings == 1 or v.readings[1][2] < v.readings[2][2])
    elseif k == 'weather' then
        local previous = s.weather or {}
        if #previous >= 3 then
            return false
        end
        for _, p in ipairs(previous) do
            if p.nsw then
                return false
            end
        end
        if v.nsw then
            return change and #previous == 0
        end
        local seen = {}
        local precipitation = false
        for _, p in ipairs(v.phenomena) do
            if not G.phenomena[p] or seen[p] then
                return false
            end
            seen[p] = true
            precipitation = precipitation or G.precip[p]
            if #v.phenomena >= 2 and not G.precip[p] then
                return false
            end
        end
        if #v.phenomena == 0 and v.descriptor ~= 'TS' and v.descriptor ~= 'SH' then
            return false
        end
        return (v.intensity ~= '-' and v.intensity ~= '+') or precipitation
    elseif k == 'cloud' then
        local p = s.cloud or {}
        local last = p[#p]
        return not last or (v.layer and last.layer and v.height > last.height)
    elseif k == 'temperature' then
        return v.dew <= v.temperature
    elseif k == 'pressure' then
        return v.value >= (v.unit == 'A' and 2500 or 850) and v.value <= (v.unit == 'A' and 3150 or 1070)
    end
    return true
end

function G.record(s, k, v, repeatable)
    if k == 'wind' and v.unit == 'MPS' then
        v.speed = U.knots(v.speed)
        if v.gust then
            v.gust = U.knots(v.gust)
        end
        v.unit = 'KT'
    end
    if k == 'pressure' then
        v.inhg = v.unit == 'A' and v.value or U.inhg(v.value)
        v.hpa = v.unit == 'Q' and v.value or U.hpa(v.value)
    end
    if repeatable then
        s[k] = s[k] or {}
        s[k][#s[k] + 1] = v
    else
        s[k] = v
    end
end
return G
