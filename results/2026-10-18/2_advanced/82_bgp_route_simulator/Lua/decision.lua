local Decision = {}

function Decision.sequence_equal(first, second)
    if #first ~= #second then return false end
    for i, value in ipairs(first) do if value ~= second[i] then return false end end
    return true
end

function Decision.equal(first, second)
    if first == second then return true end
    return first ~= nil and second ~= nil and first.origin == second.origin and first.med == second.med
        and first.link == second.link and first.local_pref == second.local_pref
        and Decision.sequence_equal(first.path, second.path)
        and Decision.sequence_equal(first.communities, second.communities)
end

function Decision.originated(origin, communities)
    return {path = {}, origin = origin, med = 0, communities = communities}
end

function Decision.best(candidates, router_ids)
    local remaining = candidates
    if #remaining == 1 then return remaining[1], "ONLY" end
    local origin_order = {IGP = 0, EGP = 1, INCOMPLETE = 2}
    local stages = {{"LOCALPREF", function(r) return -r.local_pref end},
        {"ASPATH", function(r) return #r.path end}, {"ORIGIN", function(r) return origin_order[r.origin] end},
        {"MED"}, {"ROUTERID", function(r) return router_ids[r.path[1]] end},
        {"LINK", function(r) return r.link.number end}}
    for _, stage in ipairs(stages) do
        local filtered, minima, minimum = {}, {}, math.maxinteger
        if stage[1] == "MED" then
            for _, route in ipairs(remaining) do
                local neighbor = route.path[1]
                minima[neighbor] = math.min(minima[neighbor] or route.med, route.med)
            end
        else
            for _, route in ipairs(remaining) do minimum = math.min(minimum, stage[2](route)) end
        end
        for _, route in ipairs(remaining) do
            if (stage[1] == "MED" and route.med == minima[route.path[1]])
                or (stage[1] ~= "MED" and stage[2](route) == minimum) then filtered[#filtered + 1] = route end
        end
        remaining = filtered
        if #remaining == 1 then return remaining[1], stage[1] end
    end
end

return Decision
