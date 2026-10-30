local R = {}
function R.resolve(entries, script_names)
    local names, result = {}, {}
    for name in pairs(entries) do names[name] = true end
    for name in pairs(script_names) do names[name] = true end
    for name in pairs(names) do
        local resolution = { name = name, entries = entries[name] or {}, strong = {}, weak = {}, commons = {}, references = {},
            referrers = {}, strong_definers = {}, size = 0, alignment = 1, live = false, unresolved_referrers = {} }
        if script_names[name] then resolution.strong_definers[1] = "*script*" end
        local seen = {}
        for _, entry in ipairs(resolution.entries) do
            local target = entry.kind == "common" and resolution.commons or
                (entry.kind == "undefined" and resolution.references or (entry.binding == "global" and resolution.strong or resolution.weak))
            target[#target + 1] = entry
            if entry.kind == "undefined" and not seen[entry.owner.name] then
                resolution.referrers[#resolution.referrers + 1], seen[entry.owner.name] = entry.owner.name, true
            end
        end
        for _, entry in ipairs(resolution.strong) do resolution.strong_definers[#resolution.strong_definers + 1] = entry.owner.name end
        if script_names[name] then resolution.kind, resolution.definer = "script", "*script*"
        elseif #resolution.strong > 0 then resolution.kind, resolution.definition = "global", resolution.strong[1]
        elseif #resolution.commons > 0 then
            resolution.kind = "common"
            for _, entry in ipairs(resolution.commons) do
                resolution.size, resolution.alignment = math.max(resolution.size, entry.size), math.max(resolution.alignment, entry.alignment)
            end
            for _, entry in ipairs(resolution.commons) do if entry.size == resolution.size then resolution.definer = entry.owner.name; break end end
        elseif #resolution.weak > 0 then resolution.kind, resolution.definition = "weak", resolution.weak[1]
        else
            resolution.kind, resolution.definer = "weakundef", "-"
            for _, entry in ipairs(resolution.references) do if entry.binding == "global" then resolution.kind = "undefined"; break end end
        end
        if resolution.definition then resolution.definer = resolution.definition.owner.name end
        result[name] = resolution
    end
    return result
end
return R
