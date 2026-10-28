local M = {}
local function contains(clause, literal)
    for _, value in ipairs(clause) do
        if value == literal then
            return true
        end
    end
    return false
end
function M.run(variables, original, use_pure)
    local working, fixed = {}, {}
    local records = {tautology = {}, unit = {}, subsumed = {}, pure = {}}
    local counts = {tautologies = 0, duplicate_literals = 0, unit_fixed = 0, unit_removed = 0, subsumed = 0, pure_fixed = 0, pure_removed = 0}
    for number, clause in ipairs(original) do
        local present, tautology = {}, false
        for _, literal in ipairs(clause) do
            present[literal] = true
        end
        for _, literal in ipairs(clause) do
            if present[-literal] then
                tautology = true
                break
            end
        end
        if tautology then
            counts.tautologies = counts.tautologies + 1
            records.tautology[#records.tautology + 1] = number
        else
            local reduced, seen = {}, {}
            for _, literal in ipairs(clause) do
                if seen[literal] then
                    counts.duplicate_literals = counts.duplicate_literals + 1
                else
                    seen[literal] = true
                    reduced[#reduced + 1] = literal
                end
            end
            working[#working + 1] = {number = number, clause = reduced}
        end
    end
    local empty_clause
    while true do
        local unit
        for _, entry in ipairs(working) do
            if #entry.clause == 0 then
                empty_clause = entry.number
                break
            end
        end
        if empty_clause then
            break
        end
        for _, entry in ipairs(working) do
            if #entry.clause == 1 then
                unit = entry.clause[1]
                break
            end
        end
        if unit == nil then
            break
        end
        fixed[math.abs(unit)] = unit > 0
        counts.unit_fixed = counts.unit_fixed + 1
        local surviving = {}
        for _, entry in ipairs(working) do
            if contains(entry.clause, unit) then
                counts.unit_removed = counts.unit_removed + 1
                records.unit[#records.unit + 1] = entry.number
            else
                local reduced = {}
                for _, literal in ipairs(entry.clause) do
                    if literal ~= -unit then
                        reduced[#reduced + 1] = literal
                    end
                end
                surviving[#surviving + 1] = {number = entry.number, clause = reduced}
            end
        end
        working = surviving
    end
    if not empty_clause then
        local removed, sets = {}, {}
        for i, entry in ipairs(working) do
            sets[i] = {}
            for _, literal in ipairs(entry.clause) do
                sets[i][literal] = true
            end
        end
        for b, entry_b in ipairs(working) do
            for a, entry_a in ipairs(working) do
                if a ~= b and (#entry_a.clause < #entry_b.clause or a < b) then
                    local subset = true
                    for _, literal in ipairs(entry_a.clause) do
                        if not sets[b][literal] then
                            subset = false
                            break
                        end
                    end
                    if subset then
                        removed[b] = true
                        break
                    end
                end
            end
        end
        local surviving = {}
        for i, entry in ipairs(working) do
            if removed[i] then
                counts.subsumed = counts.subsumed + 1
                records.subsumed[#records.subsumed + 1] = entry.number
            else
                surviving[#surviving + 1] = entry
            end
        end
        working = surviving
        if use_pure then
            while true do
                local present, pure, pure_count = {}, {}, 0
                for _, entry in ipairs(working) do
                    for _, literal in ipairs(entry.clause) do
                        present[literal] = true
                    end
                end
                for literal in pairs(present) do
                    if not present[-literal] then
                        pure[literal], pure_count = true, pure_count + 1
                        fixed[math.abs(literal)] = literal > 0
                    end
                end
                if pure_count == 0 then
                    break
                end
                counts.pure_fixed = counts.pure_fixed + pure_count
                surviving = {}
                for _, entry in ipairs(working) do
                    local satisfied = false
                    for _, literal in ipairs(entry.clause) do
                        if pure[literal] then
                            satisfied = true
                            break
                        end
                    end
                    if satisfied then
                        counts.pure_removed = counts.pure_removed + 1
                        records.pure[#records.pure + 1] = entry.number
                    else
                        surviving[#surviving + 1] = entry
                    end
                end
                working = surviving
            end
        end
    end
    counts.removed = counts.tautologies + counts.unit_removed + counts.subsumed + counts.pure_removed
    for _, values in pairs(records) do
        table.sort(values)
    end
    local clauses, active = {}, {}
    for _, entry in ipairs(working) do
        clauses[#clauses + 1] = entry.clause
    end
    for variable = 1, variables do
        if fixed[variable] == nil then
            active[#active + 1] = variable
        end
    end
    return {clauses = clauses, fixed = fixed, active = active, counts = counts, records = records, empty_clause = empty_clause, pure = use_pure}
end
return M
