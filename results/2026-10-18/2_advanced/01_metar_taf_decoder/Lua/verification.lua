local V = {categories = {'VFR', 'MVFR', 'IFR', 'LIFR'}}
local index = {VFR = 1, MVFR = 2, IFR = 3, LIFR = 4}
function V.covers(f, o)
    local h = o.time - o.time % 60
    return f.time <= o.time and f.start <= h and h < f.finish
end

function V.select(forecasts, o)
    local chosen
    for _, f in ipairs(forecasts) do
        if V.covers(f, o) and (not chosen or f.time >= chosen.time) then
            chosen = f
        end
    end
    return chosen
end

function V.compare(observations, forecasts)
    local r = {table = {}, rows = {0, 0, 0, 0}, columns = {0, 0, 0, 0}, total = 0, hits = 0, temporaryHits = 0, noForecast = 0, selected = {}, pod = {}, far = {}}
    for i = 1, 4 do
        r.table[i] = {0, 0, 0, 0}
    end
    for _, o in ipairs(observations) do
        local f = V.select(forecasts, o)
        if not f then
            r.noForecast = r.noForecast + 1
        else
            local states = f.hours[o.time - o.time % 60]
            local cat = states.state.category
            local actual = o.state.category
            local possible = {[cat] = true}
            for _, c in ipairs(states.temporary) do
                possible[c.state.category] = true
            end
            local i, j = index[cat], index[actual]
            r.table[i][j] = r.table[i][j] + 1
            if possible[actual] then
                r.temporaryHits = r.temporaryHits + 1
            end
            r.selected[#r.selected + 1] = {observation = o, states = states, possible = possible}
        end
    end
    for i = 1, 4 do
        for j = 1, 4 do
            r.rows[i] = r.rows[i] + r.table[i][j]
            r.columns[j] = r.columns[j] + r.table[i][j]
        end
        r.hits = r.hits + r.table[i][i]
    end
    local expected = 0
    for i = 1, 4 do
        r.total = r.total + r.rows[i]
        expected = expected + r.rows[i] * r.columns[i]
        r.pod[i] = {r.table[i][i], r.columns[i]}
        r.far[i] = {r.rows[i] - r.table[i][i], r.rows[i]}
    end
    r.skill = {r.total * r.hits - expected, r.total * r.total - expected}
    return r
end
return V
