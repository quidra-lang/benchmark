local Parser = require("pddl_parser")
local Grounding = {}

function Grounding.copy(items)
    local result = {}
    for key, value in pairs(items) do result[key] = value end
    return result
end

function Grounding.size(items)
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    return count
end

function Grounding.sorted(items)
    local result = {}
    for item in pairs(items) do result[#result + 1] = item end
    table.sort(result)
    return result
end

function Grounding.key(items)
    return table.concat(Grounding.sorted(items), ",")
end

function Grounding.subset(first, second)
    for item in pairs(first) do if not second[item] then return false end end
    return true
end

function Grounding.intersects(first, second)
    for item in pairs(first) do if second[item] then return true end end
    return false
end

function Grounding.union(first, second)
    local result = Grounding.copy(first)
    for key, value in pairs(second) do result[key] = value end
    return result
end

function Grounding.difference(first, second)
    local result = {}
    for key, value in pairs(first) do if not second[key] then result[key] = value end end
    return result
end

function Grounding.intersection(first, second)
    local result = {}
    for key, value in pairs(first) do if second[key] then result[key] = value end end
    return result
end

function Grounding.subtype(parents, actual, expected)
    while actual do
        if actual == expected then return true end
        actual = parents[actual]
    end
    return false
end

function Grounding.classes(domain)
    local fluent, static = {}, {}
    for _, action in ipairs(domain.actions) do for _, literal in ipairs(action.effects) do fluent[literal.atom.predicate] = true end end
    for _, name in ipairs(domain.predicate_order) do if not fluent[name] then static[name] = true end end
    return fluent, static
end

function Grounding.substitute(atom, binding)
    local expression = {atom.predicate}
    for _, term in ipairs(atom.terms) do expression[#expression + 1] = binding[term] end
    return Parser.atom(expression)
end

function Grounding.atom_set(atoms)
    local result = {}
    for _, atom in ipairs(atoms) do result[atom.key] = atom end
    return result
end

function Grounding.ground(domain, problem)
    local objects_by_type, initial_atoms = {}, Grounding.atom_set(problem.initial)
    for _, kind in ipairs(domain.type_order) do
        local objects = {}
        for _, name in ipairs(problem.object_order) do
            if Grounding.subtype(domain.parents, problem.objects[name], kind) then objects[#objects + 1] = name end
        end
        objects_by_type[kind] = objects
    end
    local candidates, statistics = {}, {}
    for _, schema in ipairs(domain.actions) do
        local choices, assignments = {}, 1
        for i, parameter in ipairs(schema.parameters) do choices[i] = objects_by_type[parameter.type]; assignments = assignments * #choices[i] end
        local stats = {assignments, 0, 0}
        statistics[schema.name] = stats
        local binding, arguments = {}, {}
        local function enumerate(index)
            if index <= #schema.parameters then
                for _, name in ipairs(choices[index]) do
                    arguments[index], binding[schema.parameters[index].name] = name, name
                    enumerate(index + 1)
                end
                return
            end
            local positive, negative = {}, {}
            for _, literal in ipairs(schema.condition) do
                local atom = Grounding.substitute(literal.atom, binding)
                if atom.predicate == "=" or domain.static[atom.predicate] then
                    local truth
                    if atom.predicate == "=" then truth = atom.terms[1] == atom.terms[2] else truth = initial_atoms[atom.key] ~= nil end
                    if truth ~= literal.sign then return end
                elseif literal.sign then positive[atom.key] = atom else negative[atom.key] = atom end
            end
            local adds, deletes = {}, {}
            for _, literal in ipairs(schema.effects) do
                local atom = Grounding.substitute(literal.atom, binding)
                if literal.sign then adds[atom.key] = atom else deletes[atom.key] = atom end
            end
            candidates[#candidates + 1] = {source = schema, arguments = Grounding.copy(arguments), cost = schema.cost,
                pre = positive, neg = negative, add = adds, delete = Grounding.difference(deletes, adds)}
            stats[2] = stats[2] + 1
        end
        enumerate(1)
    end
    local reachable, accepted = {}, {}
    for _, atom in ipairs(problem.initial) do if domain.fluent[atom.predicate] then reachable[atom.key] = atom end end
    while true do
        local changed = false
        for i, candidate in ipairs(candidates) do
            if not accepted[i] and Grounding.subset(candidate.pre, reachable) then
                accepted[i], changed = true, true
                for key, atom in pairs(candidate.add) do reachable[key] = atom end
                local stats = statistics[candidate.source.name]
                stats[3] = stats[3] + 1
            end
        end
        if not changed then break end
    end
    local predicate_order, object_order, facts = {}, {}, {}
    for i, name in ipairs(domain.predicate_order) do predicate_order[name] = i end
    for i, name in ipairs(problem.object_order) do object_order[name] = i end
    for _, atom in pairs(reachable) do facts[#facts + 1] = atom end
    table.sort(facts, function(a, b)
        if a.predicate ~= b.predicate then return predicate_order[a.predicate] < predicate_order[b.predicate] end
        for i, term in ipairs(a.terms) do
            if term ~= b.terms[i] then return object_order[term] < object_order[b.terms[i]] end
        end
        return false
    end)
    local fact_numbers, actions, action_numbers = {}, {}, {}
    for i, atom in ipairs(facts) do fact_numbers[atom.key] = i end
    for i, candidate in ipairs(candidates) do
        if accepted[i] then
            local action = {number = #actions + 1, source = candidate.source, arguments = candidate.arguments, cost = candidate.cost}
            for _, name in ipairs({"pre", "neg", "add", "delete"}) do
                action[name] = {}
                for key in pairs(candidate[name]) do local number = fact_numbers[key]; if number then action[name][number] = true end end
            end
            actions[#actions + 1] = action
            action_numbers[action.source.name .. " " .. table.concat(action.arguments, " ")] = action.number
        end
    end
    local initial, goal, unreachable, static_count = {}, {}, {}, 0
    for _, atom in ipairs(problem.initial) do
        if domain.fluent[atom.predicate] then initial[fact_numbers[atom.key]] = true else static_count = static_count + 1 end
    end
    for _, atom in ipairs(problem.goals) do
        local number = fact_numbers[atom.key]
        if number then goal[number] = true
        elseif not domain.static[atom.predicate] or not initial_atoms[atom.key] then unreachable[#unreachable + 1] = atom end
    end
    return {name = problem.name, source = problem, objects_by_type = objects_by_type, statistics = statistics,
        candidate_count = #candidates, facts = facts, actions = actions, initial = initial, goal = goal,
        unreachable = unreachable, static_count = static_count, action_numbers = action_numbers}
end

return Grounding
