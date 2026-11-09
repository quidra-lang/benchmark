local analysis = {}
function analysis.points(domains, visit)
    local values = {}
    local function walk(index)
        if index > #domains then visit(values); return end
        local domain = domains[index]
        for _, value in ipairs(domain.values) do values[domain.name] = value; walk(index + 1) end
    end
    walk(1)
end
function analysis.day_notation(days)
    local ordered, runs = {}, {}
    for day in pairs(days) do ordered[#ordered + 1] = day end
    table.sort(ordered)
    local first, last = ordered[1], ordered[1]
    for index = 2, #ordered do
        local day = ordered[index]
        if day ~= last + 1 then runs[#runs + 1] = first .. '-' .. last; first = day end
        last = day
    end
    runs[#runs + 1] = first .. '-' .. last
    return table.concat(runs, ',')
end
function analysis.blocker(rule, standalone)
    for _, earlier in ipairs(rule.parent.children) do
        if earlier == rule then break end
        if standalone[earlier.identifier] ~= 'NOT_APPLICABLE' then return earlier.identifier end
    end
end
function analysis.conflict_winner(policy, earlier, later)
    if policy.behavior == 'first-applicable' then return earlier.identifier end
    local effect = (policy.behavior == 'deny-overrides' or policy.behavior == 'permit-unless-deny') and 'DENY' or 'PERMIT'
    return earlier.behavior == effect and earlier.identifier or later.identifier
end
return analysis
