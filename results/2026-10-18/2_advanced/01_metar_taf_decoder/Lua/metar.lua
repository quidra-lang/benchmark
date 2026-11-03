local G = require('groups')
local M = {slots = {{'modifier', false}, {'wind', false}, {'variation', false}, {'visibility', false}, {'rvr', true}, {'weather', true}, {'cloud', true}, {'temperature', false}, {'pressure', false}, {'nosig', false}}}
function M.slotValue(kind, text)
    return G.recognize(kind, text)
end

local function slice(a, i, j)
    local b = {}
    for n = i, j do
        b[#b + 1] = a[n]
    end
    return b
end

local function time(g)
    if not g then
        return nil
    end
    local k, h, m = g.text:match('^(%u%u)(%d%d)(%d%d)$')
    if k == 'FM' or k == 'TL' or k == 'AT' then
        return {kind = k, hour = tonumber(h), minute = tonumber(m), group = g}
    end
end

function M.split(groups, error)
    local rmk = #groups + 1
    for i, g in ipairs(groups) do
        if g.text == 'RMK' then
            rmk = i
            break
        end
    end
    local first = rmk
    for i = 1, rmk - 1 do
        if groups[i].text == 'BECMG' or groups[i].text == 'TEMPO' then
            first = i
            break
        end
    end
    local trends = {}
    local i = first
    while i < rmk do
        local finish = i + 1
        while finish < rmk and groups[finish].text ~= 'BECMG' and groups[finish].text ~= 'TEMPO' do
            finish = finish + 1
        end
        local j = i + 1
        local times = {}
        local t = j < finish and time(groups[j])
        if t then
            times[#times + 1] = t
            j = j + 1
            local u = j < finish and time(groups[j])
            if t.kind == 'FM' and u and u.kind == 'TL' then
                times[#times + 1] = u
                j = j + 1
            end
        end
        local bad
        for _, v in ipairs(times) do
            if v.hour > 23 or v.minute > 59 then
                bad = v
                break
            end
        end
        if bad then
            error(bad.group, 'invalid period')
        else
            trends[#trends + 1] = {kind = groups[i].text, times = times, groups = slice(groups, j, finish - 1)}
        end
        i = finish
    end
    local sea, precise = {}, {}
    for j = rmk + 1, #groups do
        local s = groups[j].text
        local p = s:match('^SLP(%d%d%d)$')
        if p then
            p = tonumber(p)
            sea[#sea + 1] = (p >= 500 and 9000 or 10000) + p
        else
            local a, t, b, d = s:match('^T([01])(%d%d%d)([01])(%d%d%d)$')
            if a then
                precise[#precise + 1] = {tonumber(t) * (a == '1' and - 1 or 1), tonumber(d) * (b == '1' and - 1 or 1)}
            end
        end
    end
    return {main = slice(groups, 1, first - 1), trends = trends, sea = sea, precise = precise}
end
return M
