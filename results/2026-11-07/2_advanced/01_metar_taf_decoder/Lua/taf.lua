local T = {slots = {{'wind', false}, {'visibility', false}, {'weather', true}, {'cloud', true}}, elements = {'wind', 'visibility', 'weather', 'cloud'}}
function T.indicator(s)
    return s == 'BECMG' or s == 'TEMPO' or s == 'PROB30' or s == 'PROB40' or s:match('^FM%d%d%d%d%d%d$') ~= nil
end

function T.split(groups, r, cal, error)
    local first = #groups + 1
    for i, g in ipairs(groups) do
        if T.indicator(g.text) then
            first = i
            break
        end
    end
    local base = {}
    for i = 1, first - 1 do
        base[#base + 1] = groups[i]
    end
    local changes = {}
    local i = first
    while i <= #groups do
        local g = groups[i]
        local kind = g.text
        local j = i + 1
        if (kind == 'PROB30' or kind == 'PROB40') and groups[j] and groups[j].text == 'TEMPO' then
            kind = kind .. ' TEMPO'
            j = j + 1
        end
        local finish = j
        while finish <= #groups and not T.indicator(groups[finish].text) do
            finish = finish + 1
        end
        local c = {kind = kind}
        local valid = true
        if kind:sub(1, 2) == 'FM' then
            local day, h, m = tonumber(kind:sub(3, 4)), tonumber(kind:sub(5, 6)), tonumber(kind:sub(7, 8))
            local t = cal:dayTime(day, h, m, r.issueDay)
            if h > 23 or m > 59 or not t or t < r.start or t >= r.finish then
                error(g, 'invalid period')
                valid = false
            else
                c.kind = 'FM'
                c.time = t
            end
        elseif j >= finish or not groups[j].text:match('^%d%d%d%d/%d%d%d%d$') then
            error({text = kind, position = g.position}, 'missing period')
            valid = false
        else
            local p = cal:period(groups[j].text, r.issueDay)
            if not p or p[1] < r.start or p[2] > r.finish then
                error(groups[j], 'invalid period')
                valid = false
            else
                c.start, c.finish = p[1], p[2]
            end
            j = j + 1
        end
        if valid then
            c.groups = {}
            for n = j, finish - 1 do
                c.groups[#c.groups + 1] = groups[n]
            end
            changes[#changes + 1] = c
        end
        i = finish
    end
    return {base = base, changes = changes}
end

function T.overlay(base, change, replace)
    local s = {}
    for _, k in ipairs(T.elements) do
        if change[k] ~= nil then
            s[k] = change[k]
        elseif not replace then
            s[k] = base[k]
        end
    end
    return s
end

function T.expand(r, describe)
    local hours = {}
    for h = r.start, r.finish - 60, 60 do
        local s = T.overlay(r.base, {}, false)
        for _, c in ipairs(r.changes) do
            if c.kind == 'FM' and c.time <= h then
                s = T.overlay(s, c.state, true)
            elseif c.kind == 'BECMG' and c.finish <= h then
                s = T.overlay(s, c.state, false)
            end
        end
        s = describe(s)
        local temporary = {}
        for _, c in ipairs(r.changes) do
            if c.kind ~= 'FM' and c.kind ~= 'BECMG' and c.start <= h and h < c.finish then
                temporary[#temporary + 1] = {kind = c.kind, state = describe(T.overlay(s, c.state, false))}
            end
        end
        hours[h] = {state = s, temporary = temporary}
    end
    return hours
end
return T
