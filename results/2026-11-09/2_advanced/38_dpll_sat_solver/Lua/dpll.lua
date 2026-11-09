local M = {}
function M.run(variables, search_clauses)
    local clauses, assignment, watches, trail, trace = {}, {}, {}, {}, {}
    local queue_head = 1
    local stats = {decisions = 0, propagations = 0, conflicts = 0, max_depth = 0}
    for i, clause in ipairs(search_clauses) do
        clauses[i] = {table.unpack(clause)}
    end
    local function value(literal)
        local truth = assignment[math.abs(literal)]
        if truth == nil then
            return nil
        end
        return literal > 0 and truth or (literal < 0 and not truth)
    end
    local function assign(literal, kind)
        assignment[math.abs(literal)] = literal > 0
        trail[#trail + 1] = {literal, kind}
        trace[#trace + 1] = kind .. literal
    end
    local function conflict()
        stats.conflicts = stats.conflicts + 1
        trace[#trace + 1] = "C"
    end
    for index, clause in ipairs(clauses) do
        if #clause >= 2 then
            for position = 1, 2 do
                local literal = clause[position]
                watches[literal] = watches[literal] or {}
                watches[literal][#watches[literal] + 1] = index
            end
        end
    end
    for _, clause in ipairs(clauses) do
        if #clause == 0 then
            conflict()
            return nil, trace, stats
        elseif #clause == 1 then
            local truth = value(clause[1])
            if truth == false then
                conflict()
                return nil, trace, stats
            elseif truth == nil then
                assign(clause[1], "P")
                stats.propagations = stats.propagations + 1
            end
        end
    end
    while true do
        local found_conflict = false
        while queue_head <= #trail do
            local false_literal = -trail[queue_head][1]
            queue_head = queue_head + 1
            watches[false_literal] = watches[false_literal] or {}
            local watch_list, index = watches[false_literal], 1
            while index <= #watch_list do
                local clause_id = watch_list[index]
                local clause = clauses[clause_id]
                if clause[1] == false_literal then
                    clause[1], clause[2] = clause[2], clause[1]
                end
                local other = clause[1]
                if value(other) == true then
                    index = index + 1
                else
                    local substitute
                    for position = 3, #clause do
                        if value(clause[position]) ~= false then
                            substitute = position
                            break
                        end
                    end
                    if substitute then
                        clause[2], clause[substitute] = clause[substitute], clause[2]
                        table.remove(watch_list, index)
                        local literal = clause[2]
                        watches[literal] = watches[literal] or {}
                        watches[literal][#watches[literal] + 1] = clause_id
                    else
                        local truth = value(other)
                        if truth == false then
                            conflict()
                            found_conflict = true
                            break
                        elseif truth == nil then
                            assign(other, "P")
                            stats.propagations = stats.propagations + 1
                        end
                        index = index + 1
                    end
                end
            end
            if found_conflict then
                break
            end
        end
        if found_conflict then
            while #trail > 0 and trail[#trail][2] ~= "D" do
                local entry = table.remove(trail)
                assignment[math.abs(entry[1])] = nil
            end
            if #trail == 0 then
                return nil, trace, stats
            end
            local decision = table.remove(trail)[1]
            assignment[math.abs(decision)] = nil
            assign(-decision, "F")
            queue_head = #trail
        else
            local counts = {}
            for _, clause in ipairs(clauses) do
                local satisfied = false
                for _, literal in ipairs(clause) do
                    if value(literal) == true then
                        satisfied = true
                        break
                    end
                end
                if not satisfied then
                    for _, literal in ipairs(clause) do
                        if value(literal) == nil then
                            counts[literal] = (counts[literal] or 0) + 1
                        end
                    end
                end
            end
            local best, maximum = nil, 0
            for variable = 1, variables do
                for _, literal in ipairs({variable, -variable}) do
                    if (counts[literal] or 0) > maximum then
                        best, maximum = literal, counts[literal]
                    end
                end
            end
            if not best then
                local model = {}
                for variable = 1, variables do
                    model[variable] = assignment[variable] == true
                end
                return model, trace, stats
            end
            assign(best, "D")
            stats.decisions = stats.decisions + 1
            local depth = 0
            for _, entry in ipairs(trail) do
                if entry[2] == "D" or entry[2] == "F" then
                    depth = depth + 1
                end
            end
            stats.max_depth = math.max(stats.max_depth, depth)
        end
    end
end
return M
