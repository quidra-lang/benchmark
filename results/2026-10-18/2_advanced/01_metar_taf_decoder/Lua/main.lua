local directory = (arg[0]:match('^(.*[/\\])') or './')
package.path = directory .. '?.lua;' .. package.path
local U, G, M, T, V = require('units'), require('groups'), require('metar'), require('taf'), require('verification')
local function words(s)
    local a = {}
    for w in s:gmatch('%S+') do
        a[#a + 1] = w
    end
    return a
end

local function read(path)
    local a = {}
    for line in io.lines(path) do
        a[#a + 1] = line
    end
    return a
end

local function write(path, lines)
    local f = assert(io.open(path, 'w'))
    if #lines > 0 then
        f:write(table.concat(lines, '\n'), '\n')
    end
    f:close()
end

local function blocks(path, list)
    local lines = {}
    for i, b in ipairs(list) do
        if i > 1 then
            lines[#lines + 1] = ''
        end
        for _, s in ipairs(b) do
            lines[#lines + 1] = s
        end
    end
    write(path, lines)
end
local stations, settings = {}, {}
for _, line in ipairs(read('input/stations.txt')) do
    local code, elevation, runways, name = line:match('^(%u+) (%-?%d+) (%S+) (.+)$')
    local rs = {}
    for entry in runways:gmatch('[^,]+') do
        local n, h = entry:match('^([^/]+)/(%d+)$')
        rs[#rs + 1] = {name = n, heading = tonumber(h)}
    end
    stations[code] = {code = code, elevation = tonumber(elevation), runways = rs, name = name}
end
for _, line in ipairs(read('input/params.txt')) do
    local p = words(line)
    local key = table.remove(p, 1)
    settings[key] = key == 'VERIFY' and p or tonumber(p[1])
end
local cal = U.calendar(settings.YEAR, settings.MONTH)
local errors = {}
local function errorAt(number, position, text)
    errors[#errors + 1] = {number = number, position = position, text = text}
end

local function groupError(r, g, reason)
    errorAt(r.number, g.position, reason .. ' "' .. g.text .. '"')
end

local function header(w, number)
    local kind = w[1]
    local r = {number = number, kind = kind}
    local i = 2
    if kind ~= 'METAR' and kind ~= 'SPECI' and kind ~= 'TAF' then
        errorAt(number, 1, 'rejected report, invalid type "' .. kind .. '"')
        return nil
    end
    if kind == 'TAF' and (w[i] == 'AMD' or w[i] == 'COR') then
        r.modifier = w[i]
        i = i + 1
    end
    local fields = kind == 'TAF' and {'station', 'time', 'validity'} or {'station', 'time'}
    for _, field in ipairs(fields) do
        if not w[i] then
            errorAt(number, #w + 1, 'rejected report, missing ' .. field)
            return nil
        end
        local value
        if field == 'station' then
            value = stations[w[i]]
        elseif field == 'time' then
            value = cal:reportTime(w[i])
        else
            value = cal:period(w[i], r.issueDay, 1800)
        end
        if value == nil then
            errorAt(number, i, 'rejected report, invalid ' .. field .. ' "' .. w[i] .. '"')
            return nil
        end
        if field == 'validity' then
            r.start, r.finish = value[1], value[2]
        else
            r[field] = value
        end
        if field == 'time' then
            r.issueDay = value // 1440 + 1
        end
        i = i + 1
    end
    r.groups = {}
    while i <= #w do
        local position, text = i, w[i]
        if U.digits(text, 1) and w[i + 1] and w[i + 1]:match('^%d/%d%d?SM$') then
            text = text .. ' ' .. w[i + 1]
            i = i + 1
        end
        r.groups[#r.groups + 1] = {position = position, text = text}
        i = i + 1
    end
    return r
end

local function matchSection(groups, slots, r, change)
    local s = {}
    local current = 1
    local recognize = slots == M.slots and M.slotValue or G.recognize
    for _, g in ipairs(groups) do
        local found, value
        for i = current, #slots do
            local v = recognize(slots[i][1], g.text)
            if v then
                found, value = i, v
                break
            end
        end
        if not found then
            local earlier = false
            for i = 1, current - 1 do
                if recognize(slots[i][1], g.text) then
                    earlier = true
                    break
                end
            end
            groupError(r, g, earlier and 'out of order group' or 'unknown group')
        else
            local k, repeatable = slots[found][1], slots[found][2]
            if not G.valid(k, value, s, r.station, change) then
                groupError(r, g, 'invalid group')
            else
                G.record(s, k, value, repeatable)
                current = repeatable and found or found + 1
                if k == 'visibility' and value.kind == 'cavok' then
                    s.weather = {}
                    s.cloud = {}
                    for i, slot in ipairs(slots) do
                        if slot[1] == 'cloud' then
                            current = i + 1
                        end
                    end
                end
            end
        end
    end
    return s
end

local function describe(s)
    local ceiling
    for _, c in ipairs(s.cloud or {}) do
        if c.amount == 'BKN' or c.amount == 'OVC' or c.amount == 'VV' then
            ceiling = c.height
            break
        end
    end
    local n, d = 0, 0
    if s.visibility then
        n, d = U.miles(s.visibility)
    end
    local category = 'VFR'
    if (ceiling and ceiling < 500) or (d ~= 0 and n < d) then
        category = 'LIFR'
    elseif (ceiling and ceiling < 1000) or (d ~= 0 and n < 3 * d) then
        category = 'IFR'
    elseif (ceiling and ceiling <= 3000) or (d ~= 0 and n <= 5 * d) then
        category = 'MVFR'
    end
    s.ceiling, s.category = ceiling, category
    return s
end

local function components(w, d, h)
    return {w * U.cos(d - h) // 1000, w * U.sin(d - h) // 1000}
end

local function derive(r)
    local s = r.state
    local p, t = s.pressure, s.temperature
    if p then
        local a = r.station.elevation + (2992 - p.inhg) * 10
        r.pressureAltitude = a
        if t then
            r.densityAltitude = a + 120 * (1000 * t.temperature - 15000 + 2 * a) // 1000
        end
    end
    local w = s.wind
    if not w or w.direction == 'VRB' or w.direction == 0 then
        return
    end
    r.components = {}
    r.usable = {}
    local preferred
    for _, runway in ipairs(r.station.runways) do
        local mean = components(w.speed, w.direction, runway.heading)
        local gust = w.gust and components(w.gust, w.direction, runway.heading)
        local d = gust or mean
        r.components[#r.components + 1] = {name = runway.name, mean = mean, gust = gust}
        if math.abs(d[2]) <= settings.CROSSWIND_LIMIT and - d[1] <= settings.TAILWIND_LIMIT then
            r.usable[#r.usable + 1] = runway.name
            if not preferred or mean[1] > preferred.head then
                preferred = {name = runway.name, head = mean[1]}
            end
        end
    end
    r.preferred = preferred and preferred.name or 'none'
end

local function windChanges(a, b, angle)
    if not a or not b then
        return {}
    end
    local reasons = {}
    if a.direction ~= 'VRB' and a.direction ~= 0 and b.direction ~= 'VRB' and b.direction ~= 0 then
        local d = math.abs(a.direction - b.direction) % 360
        if math.max(a.speed, b.speed) >= 10 and math.min(d, 360 - d) >= angle then
            reasons[#reasons + 1] = 'wind shift'
        end
    end
    if math.abs(a.speed - b.speed) >= 10 then
        reasons[#reasons + 1] = 'wind speed'
    end
    return reasons
end

local function weatherPresent(s, kind)
    for _, w in ipairs(s.weather or {}) do
        if kind == 'TS' and w.descriptor == 'TS' then
            return true
        end
        if kind == 'FZ' and w.descriptor == 'FZ' then
            for _, p in ipairs(w.phenomena) do
                if p == 'DZ' or p == 'RA' then
                    return true
                end
            end
        end
    end
    return false
end

local function speci(previous, r)
    if not previous then
        return 'no previous report'
    end
    local a, b = previous.state, r.state
    local reasons = {}
    if a.category ~= b.category then
        reasons[#reasons + 1] = 'category ' .. a.category .. ' to ' .. b.category
    end
    for _, reason in ipairs(windChanges(a.wind, b.wind, 45)) do
        reasons[#reasons + 1] = reason
    end
    for _, v in ipairs({{'TS', 'thunderstorm'}, {'FZ', 'freezing precipitation'}}) do
        local before, after = weatherPresent(a, v[1]), weatherPresent(b, v[1])
        if before ~= after then
            reasons[#reasons + 1] = v[2] .. (after and ' began' or ' ended')
        end
    end
    return #reasons == 0 and 'no criteria met' or table.concat(reasons, ', ')
end

local function windPhrase(w)
    if w.direction == 0 then
        return 'calm'
    end
    local s = w.direction == 'VRB' and ('variable at ' .. w.speed .. ' KT') or string.format('%03d degrees at %d KT', w.direction, w.speed)
    return s .. (w.gust and (' gusting ' .. w.gust .. ' KT') or '')
end

local function visibilityNumber(v)
    if not v.fraction then
        return tostring(v.whole)
    end
    return (v.whole ~= 0 and (v.whole .. ' ') or '') .. v.num .. '/' .. v.den
end

local function visibilityPhrase(v)
    if v.kind == 'cavok' then
        return '10 km or more (CAVOK)'
    end
    if v.kind == 'meters' then
        return v.value == 10000 and '10 km or more' or (v.value .. ' m')
    end
    local prefix = ({M = 'less than ', P = 'more than '})[v.qualifier] or ''
    return prefix .. visibilityNumber(v) .. ' SM'
end

local function weatherPhrase(w)
    if w.nsw then
        return 'no significant weather'
    end
    local p = {}
    local i = ({['-'] = 'light', ['+'] = 'heavy', VC = 'nearby'})[w.intensity]
    if i then
        p[#p + 1] = i
    end
    if w.descriptor then
        p[#p + 1] = G.descriptors[w.descriptor]
    end
    local phenomena = {}
    for _, c in ipairs(w.phenomena) do
        phenomena[#phenomena + 1] = G.phenomena[c]
    end
    if #phenomena > 0 then
        p[#p + 1] = table.concat(phenomena, ' and ')
    end
    return table.concat(p, ' ')
end

local function cloudPhrase(c)
    if G.clear[c.amount] then
        return G.clear[c.amount]
    end
    if c.amount == 'VV' then
        return 'vertical visibility ' .. c.height .. ' ft'
    end
    return G.amounts[c.amount] .. ' at ' .. c.height .. ' ft' .. (({CB = ' cumulonimbus', TCU = ' towering cumulus'})[c.extra] or '')
end

local function summary(s)
    local p = {}
    if s.wind then
        p[#p + 1] = 'wind ' .. windPhrase(s.wind)
    end
    if s.visibility then
        p[#p + 1] = 'visibility ' .. visibilityPhrase(s.visibility)
    end
    for _, item in ipairs({{'weather', weatherPhrase}, {'cloud', cloudPhrase}}) do
        local values = {}
        for _, v in ipairs(s[item[1]] or {}) do
            values[#values + 1] = item[2](v)
        end
        if #values > 0 then
            p[#p + 1] = item[1] .. ' ' .. table.concat(values, ', ')
        end
    end
    return #p == 0 and 'no conditions' or table.concat(p, '; ')
end

local function windCode(w)
    if w.direction == 0 then
        return '00000KT'
    end
    return (w.direction == 'VRB' and 'VRB' or string.format('%03d', w.direction)) .. string.format('%02d', w.speed) .. (w.gust and string.format('G%02d', w.gust) or '') .. 'KT'
end

local function visibilityCode(v)
    if v.kind == 'cavok' then
        return 'CAVOK'
    end
    if v.kind == 'meters' then
        return string.format('%04d', v.value == 10000 and 9999 or v.value)
    end
    return v.qualifier .. visibilityNumber(v) .. 'SM'
end

local function tokens(s)
    local p = {}
    if s.wind then
        p[#p + 1] = windCode(s.wind)
    end
    if s.visibility then
        p[#p + 1] = visibilityCode(s.visibility)
    end
    for _, w in ipairs(s.weather or {}) do
        if not w.nsw then
            p[#p + 1] = w.raw
        end
    end
    for _, c in ipairs(s.cloud or {}) do
        p[#p + 1] = G.clear[c.amount] and c.amount or (c.amount .. string.format('%03d', c.height // 100) .. c.extra)
    end
    p[#p + 1] = s.category
    return table.concat(p, ' ')
end

local function tenths(v)
    return (v < 0 and '-' or '') .. (math.abs(v) // 10) .. '.' .. (math.abs(v) % 10)
end

local function inhgText(v)
    return string.format('%d.%02d', v // 100, v % 100)
end

local function componentPhrase(v)
    local h, c = v[1], v[2]
    return (h < 0 and ('tailwind ' .. - h) or ('headwind ' .. h)) .. ' KT, crosswind ' .. math.abs(c) .. ' KT' .. (c > 0 and ' from right' or (c < 0 and ' from left' or ''))
end

local function rvrPhrase(v)
    local p = {}
    for _, r in ipairs(v.readings) do
        p[#p + 1] = (({M = 'less than ', P = 'more than '})[r[1]] or '') .. r[2]
    end
    return 'runway ' .. v.runway .. ' ' .. (#p == 1 and p[1] or ('between ' .. p[1] .. ' and ' .. p[2])) .. ' ' .. v.unit .. (v.trend ~= '' and (', ' .. ({U = 'rising', D = 'falling', N = 'no change'})[v.trend]) or '')
end

local function decoded(r)
    local lines = {'REPORT ' .. r.number .. ': ' .. r.kind .. ' ' .. r.station.code .. ' (' .. r.station.name .. ')'}
    local function add(s)
        lines[#lines + 1] = '  ' .. s
    end
    if r.kind == 'TAF' then
        add('issued: ' .. cal:stamp(r.time))
        if r.modifier then
            add('modifier: ' .. (r.modifier == 'AMD' and 'amended' or 'corrected'))
        end
        add('valid: ' .. cal:stamp(r.start) .. ' to ' .. cal:stamp(r.finish))
        add('base: ' .. summary(r.base))
        for _, c in ipairs(r.changes) do
            add(c.kind .. ' ' .. (c.kind == 'FM' and cal:stamp(c.time) or (cal:stamp(c.start) .. ' to ' .. cal:stamp(c.finish))) .. ': ' .. summary(c.state))
        end
    else
        local s = r.state
        add('time: ' .. cal:stamp(r.time))
        if s.modifier then
            add('modifier: ' .. (s.modifier.code == 'AUTO' and 'automated' or 'corrected'))
        end
        local w = s.wind and windPhrase(s.wind) or 'not reported'
        if s.variation then
            w = w .. string.format(', varying between %03d and %03d degrees', s.variation.first, s.variation.last)
        end
        add('wind: ' .. w)
        add('visibility: ' .. (s.visibility and visibilityPhrase(s.visibility) or 'not reported'))
        for _, v in ipairs(s.rvr or {}) do
            add('runway visual range: ' .. rvrPhrase(v))
        end
        for _, v in ipairs(s.weather or {}) do
            add('weather: ' .. weatherPhrase(v))
        end
        if s.visibility and s.visibility.kind == 'cavok' then
            add('cloud: no significant cloud')
        elseif not s.cloud then
            add('cloud: not reported')
        else
            for _, c in ipairs(s.cloud) do
                add('cloud: ' .. cloudPhrase(c))
            end
        end
        local t = s.temperature
        add(t and ('temperature: ' .. t.temperature .. ' C, dew point ' .. t.dew .. ' C, spread ' .. (t.temperature - t.dew) .. ' C') or 'temperature: not reported')
        local p = s.pressure
        if not p then
            add('altimeter: not reported')
        elseif p.unit == 'A' then
            add('altimeter: ' .. inhgText(p.inhg) .. ' inHg (' .. p.hpa .. ' hPa)')
        else
            add('altimeter: ' .. p.hpa .. ' hPa (' .. inhgText(p.inhg) .. ' inHg)')
        end
        if s.nosig then
            add('trend: no significant change')
        end
        for _, trend in ipairs(r.trends) do
            local text = trend.kind == 'BECMG' and 'becoming' or 'temporarily'
            for _, v in ipairs(trend.times) do
                text = text .. ' ' .. ({FM = 'from', TL = 'until', AT = 'at'})[v.kind] .. string.format(' %02d:%02dZ', v.hour, v.minute)
            end
            add('trend: ' .. text .. ': ' .. summary(trend.state))
        end
        for _, v in ipairs(r.sea) do
            add('sea level pressure: ' .. tenths(v) .. ' hPa')
        end
        for _, v in ipairs(r.precise) do
            add('precise temperature: ' .. tenths(v[1]) .. ' C, dew point ' .. tenths(v[2]) .. ' C')
        end
        add('ceiling: ' .. (s.ceiling and (s.ceiling .. ' ft') or 'none'))
        add('flight category: ' .. s.category)
        add('pressure altitude: ' .. (r.pressureAltitude and (r.pressureAltitude .. ' ft') or 'not available'))
        add('density altitude: ' .. (r.densityAltitude and (r.densityAltitude .. ' ft') or 'not available'))
        if r.components then
            for _, v in ipairs(r.components) do
                add('runway ' .. v.name .. ': ' .. componentPhrase(v.mean) .. (v.gust and ('; gusts ' .. componentPhrase(v.gust)) or ''))
            end
            add('usable runways: ' .. (#r.usable > 0 and table.concat(r.usable, ' ') or 'none'))
            add('preferred runway: ' .. r.preferred)
        else
            add('runway wind: not computed')
        end
        if r.kind == 'SPECI' then
            add('speci check: ' .. r.speci)
        end
    end
    return lines
end

local function categoryCounts(states)
    local counts = {VFR = 0, MVFR = 0, IFR = 0, LIFR = 0}
    for _, s in ipairs(states) do
        counts[s.category] = counts[s.category] + 1
    end
    local p = {}
    for _, c in ipairs(V.categories) do
        p[#p + 1] = c .. ' ' .. counts[c]
    end
    return table.concat(p, ', ')
end

local function timeline(r)
    local lines = {'TAF ' .. r.station.code .. ' issued ' .. cal:stamp(r.time) .. ' valid ' .. cal:stamp(r.start) .. ' to ' .. cal:stamp(r.finish)}
    local states = {}
    for h = r.start, r.finish - 60, 60 do
        local v = r.hours[h]
        local line = cal:stamp(h) .. ' ' .. tokens(v.state)
        states[#states + 1] = v.state
        for _, c in ipairs(v.temporary) do
            line = line .. ' | ' .. c.kind .. ' ' .. tokens(c.state)
        end
        lines[#lines + 1] = line
    end
    lines[#lines + 1] = 'summary: ' .. categoryCounts(states)
    return lines
end

local function extreme(observations, value, maximum, ratio)
    local chosen, best
    for _, o in ipairs(observations) do
        local v = value(o)
        if v ~= nil then
            local cmp = 0
            if best ~= nil then
                if ratio then
                    cmp = v[1] * best[2] - best[1] * v[2]
                else
                    cmp = v - best
                end
            end
            if not chosen or (maximum and cmp > 0) or (not maximum and cmp < 0) then
                chosen, best = o, v
            end
        end
    end
    return chosen
end

local function verification(station, reports)
    local observations, forecasts = {}, {}
    for _, r in ipairs(reports) do
        if r.station.code == station.code then
            local a = r.kind == 'TAF' and forecasts or observations
            a[#a + 1] = r
        end
    end
    local v = V.compare(observations, forecasts)
    local states = {}
    local counts = {METAR = 0, SPECI = 0}
    for _, o in ipairs(observations) do
        states[#states + 1] = o.state
        counts[o.kind] = counts[o.kind] + 1
    end
    local lines = {'station ' .. station.code .. ' (' .. station.name .. ')', 'reports: METAR ' .. counts.METAR .. ', SPECI ' .. counts.SPECI, 'observed categories: ' .. categoryCounts(states)}
    local function ex(label, value, phrase, maximum, ratio)
        local o = extreme(observations, value, maximum, ratio)
        lines[#lines + 1] = label .. ': ' .. (o and (phrase(o) .. ' at ' .. cal:stamp(o.time)) or 'not available')
    end
    local function temperature(o)
        return o.state.temperature and o.state.temperature.temperature
    end
    ex('lowest temperature', temperature, function(o)
        return temperature(o) .. ' C'
    end)
    ex('highest temperature', temperature, function(o)
        return temperature(o) .. ' C'
    end, true)
    ex('strongest wind', function(o)
        local w = o.state.wind
        return w and (w.gust or w.speed)
    end, function(o)
        return windPhrase(o.state.wind)
    end, true)
    ex('lowest ceiling', function(o)
        return o.state.ceiling
    end, function(o)
        return o.state.ceiling .. ' ft'
    end)
    ex('lowest visibility', function(o)
        if o.state.visibility then
            local n, d = U.miles(o.state.visibility)
            return {n, d}
        end
    end, function(o)
        return visibilityPhrase(o.state.visibility)
    end, false, true)
    lines[#lines + 1] = 'verified: ' .. v.total
    lines[#lines + 1] = 'no forecast: ' .. v.noForecast
    local function row(label, values)
        local s = string.format('%-8s', label)
        for _, x in ipairs(values) do
            s = s .. string.format('%6s', tostring(x))
        end
        return s
    end
    lines[#lines + 1] = row('forecast', {'VFR', 'MVFR', 'IFR', 'LIFR', 'total'})
    for i, c in ipairs(V.categories) do
        lines[#lines + 1] = row(c, {v.table[i][1], v.table[i][2], v.table[i][3], v.table[i][4], v.rows[i]})
    end
    lines[#lines + 1] = row('total', {v.columns[1], v.columns[2], v.columns[3], v.columns[4], v.total})
    lines[#lines + 1] = 'hit rate: ' .. U.fraction(v.hits, v.total)
    lines[#lines + 1] = 'hit rate with temporary groups: ' .. U.fraction(v.temporaryHits, v.total)
    lines[#lines + 1] = 'heidke skill score: ' .. U.fraction(table.unpack(v.skill))
    for i, c in ipairs(V.categories) do
        lines[#lines + 1] = c .. ': pod ' .. U.fraction(table.unpack(v.pod[i])) .. ', far ' .. U.fraction(table.unpack(v.far[i]))
    end
    local buckets = {{0, 0}, {0, 0}, {0, 0}, {0, 0}, {0, 0}}
    for _, f in ipairs(forecasts) do
        for _, o in ipairs(observations) do
            if V.covers(f, o) then
                local h = o.time - o.time % 60
                local b = buckets[(h - f.start) // 360 + 1]
                b[2] = b[2] + 1
                if f.hours[h].state.category == o.state.category then
                    b[1] = b[1] + 1
                end
            end
        end
    end
    for i, b in ipairs(buckets) do
        lines[#lines + 1] = 'hours ' .. ((i - 1) * 6) .. '-' .. ((i - 1) * 6 + 5) .. ': ' .. U.fraction(table.unpack(b))
    end
    for _, choice in ipairs(v.selected) do
        local o = choice.observation
        local actual, forecast = o.state, choice.states.state
        local reasons = {}
        if not choice.possible[actual.category] then
            reasons[#reasons + 1] = 'category ' .. actual.category .. ', forecast ' .. forecast.category
        end
        if #windChanges(forecast.wind, actual.wind, 60) > 0 then
            reasons[#reasons + 1] = 'wind ' .. windCode(actual.wind) .. ', forecast ' .. windCode(forecast.wind)
        end
        if #reasons > 0 then
            lines[#lines + 1] = 'amendment ' .. cal:stamp(o.time) .. ': ' .. table.concat(reasons, '; ')
        end
    end
    return lines
end
local reportsWords = {}
for _, line in ipairs(read('input/reports.txt')) do
    local p = words(line)
    if line:sub(1, 1) == ' ' then
        for _, w in ipairs(p) do
            reportsWords[#reportsWords][#reportsWords[#reportsWords] + 1] = w
        end
    else
        reportsWords[#reportsWords + 1] = p
    end
end
local reports, previous = {}, {}
for i, w in ipairs(reportsWords) do
    local r = header(w, i)
    if r then
        local function err(g, reason)
            groupError(r, g, reason)
        end
        if r.kind == 'TAF' then
            local p = T.split(r.groups, r, cal, err)
            r.base = matchSection(p.base, T.slots, r, false)
            r.changes = {}
            for _, c in ipairs(p.changes) do
                c.state = matchSection(c.groups, T.slots, r, true)
                r.changes[#r.changes + 1] = c
            end
            r.hours = T.expand(r, describe)
        else
            local p = M.split(r.groups, err)
            r.state = describe(matchSection(p.main, M.slots, r, false))
            r.trends = {}
            for _, t in ipairs(p.trends) do
                t.state = matchSection(t.groups, T.slots, r, true)
                r.trends[#r.trends + 1] = t
            end
            r.sea, r.precise = p.sea, p.precise
            derive(r)
            if r.kind == 'SPECI' then
                r.speci = speci(previous[r.station.code], r)
            end
            previous[r.station.code] = r
        end
        reports[#reports + 1] = r
    end
end
-- Lua has no directory creation primitive in its standard library.
os.execute('mkdir -p output')
local decodedBlocks, timelines, verificationBlocks = {}, {}, {}
local categories = {'station,time,ceiling,visibility,category'}
for _, r in ipairs(reports) do
    decodedBlocks[#decodedBlocks + 1] = decoded(r)
    if r.kind == 'TAF' then
        timelines[#timelines + 1] = timeline(r)
    else
        local s = r.state
        local visibility = s.visibility and (s.visibility.qualifier .. U.meters(s.visibility)) or 'NONE'
        categories[#categories + 1] = r.station.code .. ',' .. cal:stamp(r.time) .. ',' .. (s.ceiling or 'NONE') .. ',' .. visibility .. ',' .. s.category
    end
end
for _, code in ipairs(settings.VERIFY) do
    verificationBlocks[#verificationBlocks + 1] = verification(stations[code], reports)
end
blocks('output/decoded.txt', decodedBlocks)
write('output/categories.csv', categories)
blocks('output/taf_timeline.txt', timelines)
blocks('output/verification.txt', verificationBlocks)
table.sort(errors, function(a, b)
    return a.number < b.number or (a.number == b.number and a.position < b.position)
end)
local errorLines = {}
for _, e in ipairs(errors) do
    errorLines[#errorLines + 1] = 'report ' .. e.number .. ' word ' .. e.position .. ': ' .. e.text
end
write('output/errors.txt', errorLines)
