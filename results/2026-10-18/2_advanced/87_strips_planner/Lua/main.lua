local Parser = require("pddl_parser")
local Sets = require("grounding")
local Heuristics = require("heuristics")
local Search = require("search")
local Graph = require("graphplan")
local Planner = {}
Planner.__index = Planner

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function action_text(action)
    return "(" .. action.source.name .. (#action.arguments > 0 and " " .. table.concat(action.arguments, " ") or "") .. ")"
end

local function number_list(numbers)
    local values = {}
    for _, number in ipairs(Sets.sorted(numbers)) do append(values, number - 1) end
    return #values == 0 and "-" or table.concat(values, ",")
end

local function headed(heading, items)
    return heading .. " " .. (#items == 0 and "-" or table.concat(items, " "))
end

local function value_text(value)
    return value == Heuristics.INF and "inf" or tostring(value)
end

local function heuristic_text(values)
    local parts = {}
    for _, name in ipairs(Heuristics.names) do append(parts, name .. "=" .. value_text(values[name])) end
    return table.concat(parts, " ")
end

local function read_settings()
    local settings = {runs = {}}
    for line in io.lines("input/params.txt") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local f = Parser.words(line)
            if f[1] == "run" then append(settings.runs, {f[2], f[3]})
            elseif f[1] == "repair" then settings.repair = {f[2], f[3]}
            else settings[f[1]] = tonumber(f[2]) end
        end
    end
    return settings
end

local function read_candidates()
    local candidates, current = {}, nil
    for line in io.lines("input/candidates.txt") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local f = Parser.words(line)
            if f[1] == "plan" then current = {number = #candidates + 1, problem = f[2], label = f[3], steps = {}}
            elseif line == "end" then append(candidates, current)
            else
                local fields, arguments = Parser.words(line:sub(2, -2)), {}
                for i = 2, #fields do append(arguments, fields[i]) end
                append(current.steps, {name = fields[1], arguments = arguments})
            end
        end
    end
    return candidates
end

local function argument_error(domain, arguments, expected, types, noun)
    if #arguments ~= #expected then return string.format("expected %d arguments, got %d", #expected, #arguments) end
    for i, argument in ipairs(arguments) do
        if not types[argument] then return "unknown " .. noun .. " " .. argument end
        if not Sets.subtype(domain.parents, types[argument], expected[i]) then
            return string.format("argument %d (%s) is not of type %s", i, argument, expected[i])
        end
    end
end

local function validate_domain(domain)
    local kept, diagnostics, used = {}, {}, {}
    for _, action in ipairs(domain.actions) do
        local error, parameters = nil, {}
        for _, parameter in ipairs(action.parameters) do
            parameters[parameter.name] = parameter.type
            if domain.parents[parameter.type] == nil then error = "unknown type " .. parameter.type; break end
        end
        if not error then
            local literals = Sets.copy(action.condition)
            extend(literals, action.effects)
            for _, literal in ipairs(literals) do
                local atom = literal.atom
                if atom.predicate ~= "=" and not domain.predicates[atom.predicate] then error = "unknown predicate " .. atom.predicate
                else error = argument_error(domain, atom.terms, atom.predicate == "=" and {"object", "object"}
                    or domain.predicates[atom.predicate], parameters, "variable") end
                if error then error = atom.key .. ": " .. error; break end
            end
        end
        if error then append(diagnostics, "error: action " .. action.name .. ": " .. error)
        else
            append(kept, action)
            for _, literal in ipairs(action.condition) do used[literal.atom.predicate] = true end
            for _, literal in ipairs(action.effects) do used[literal.atom.predicate] = true end
        end
    end
    domain.actions, domain.by_name = kept, {}
    for _, action in ipairs(kept) do domain.by_name[action.name] = action end
    for _, predicate in ipairs(domain.predicate_order) do
        if not used[predicate] then append(diagnostics, "warning: predicate " .. predicate .. " is not used by any action") end
    end
    domain.fluent, domain.static = Sets.classes(domain)
    domain.diagnostics = diagnostics
end

local function validate_problem(domain, problem)
    local diagnostics = {}
    for _, pair in ipairs({{"init", "initial"}, {"goal", "goals"}}) do
        local kept, seen = {}, {}
        for _, atom in ipairs(problem[pair[2]]) do
            local error
            if not domain.predicates[atom.predicate] then error = "unknown predicate " .. atom.predicate
            else error = argument_error(domain, atom.terms, domain.predicates[atom.predicate], problem.objects, "object") end
            if not error and seen[atom.key] then error = "duplicate" end
            if error then append(diagnostics, "warning: " .. pair[1] .. " " .. atom.key .. ": " .. error)
            else append(kept, atom); seen[atom.key] = true end
        end
        problem[pair[2]] = kept
    end
    problem.diagnostics = diagnostics
end

local function validation(status, messages, correct)
    return {status = status, messages = messages, correct = correct}
end

local function validate_steps(domain, problem, steps)
    local world, cost = Sets.atom_set(problem.initial), 0
    for position, step in ipairs(steps) do
        local notation = "(" .. step.name .. (#step.arguments > 0 and " " .. table.concat(step.arguments, " ") or "") .. ")"
        local heading = string.format("step %d %s: ", position, notation)
        local schema = domain.by_name[step.name]
        if not schema then return validation("invalid", {heading .. "unknown action " .. step.name}, position - 1) end
        local expected, assignment = {}, {}
        for i, parameter in ipairs(schema.parameters) do expected[i], assignment[parameter.name] = parameter.type, step.arguments[i] end
        local error = argument_error(domain, step.arguments, expected, problem.objects, "object")
        if error then return validation("invalid", {heading .. error}, position - 1) end
        for _, literal in ipairs(schema.condition) do
            local atom = Sets.substitute(literal.atom, assignment)
            local truth
            if atom.predicate == "=" then truth = atom.terms[1] == atom.terms[2] else truth = world[atom.key] ~= nil end
            if truth ~= literal.sign then
                local text = literal.sign and atom.key or "(not " .. atom.key .. ")"
                return validation("invalid", {heading .. "precondition " .. text .. " is false"}, position - 1)
            end
        end
        local adds, deletes = {}, {}
        for _, literal in ipairs(schema.effects) do
            local atom = Sets.substitute(literal.atom, assignment)
            if literal.sign then adds[atom.key] = atom else deletes[atom.key] = atom end
        end
        world, cost = Sets.union(Sets.difference(world, deletes), adds), cost + schema.cost
    end
    local missing = {}
    for _, atom in ipairs(problem.goals) do if not world[atom.key] then append(missing, "unsatisfied goal " .. atom.key) end end
    if #missing > 0 then return validation("goal not reached", missing, #steps) end
    return validation("valid", {string.format("length=%d cost=%d", #steps, cost)}, #steps)
end

local function verdict(checked)
    return checked.status .. (checked.status == "valid" and " " or ": ") .. checked.messages[1]
end

local function plan_steps(problem, plan)
    local steps = {}
    for _, number in ipairs(plan) do local action = problem.actions[number]; append(steps, {name = action.source.name, arguments = action.arguments}) end
    return steps
end

local function plan_cost(problem, plan)
    local cost = 0
    for _, number in ipairs(plan) do cost = cost + problem.actions[number].cost end
    return cost
end

local function interferes(first, second)
    return Sets.intersects(first.delete, Sets.union(second.pre, second.add)) or Sets.intersects(second.delete, Sets.union(first.pre, first.add))
        or Sets.intersects(first.add, second.neg) or Sets.intersects(second.add, first.neg)
end

local function parallelize(problem, plan)
    local assigned, layers = {}, {}
    for position, number in ipairs(plan) do
        local action, layer = problem.actions[number], 1
        for earlier = 1, position - 1 do
            local previous = problem.actions[plan[earlier]]
            if Sets.intersects(previous.add, action.pre) or Sets.intersects(previous.delete, action.neg) or interferes(previous, action) then
                layer = math.max(layer, assigned[earlier] + 1)
            end
        end
        assigned[position] = layer
        while #layers < layer do append(layers, {}) end
        append(layers[layer], number)
    end
    return layers
end

local function validate_parallel(problem, layers)
    local state = problem.initial
    for position, layer in ipairs(layers) do
        local deletes, adds = {}, {}
        for i, number in ipairs(layer) do
            local action = problem.actions[number]
            if not Search.applicable(action, state) then return "invalid at layer " .. position end
            for j = i + 1, #layer do if interferes(action, problem.actions[layer[j]]) then return "invalid at layer " .. position end end
            deletes, adds = Sets.union(deletes, action.delete), Sets.union(adds, action.add)
        end
        state = Sets.union(Sets.difference(state, deletes), adds)
    end
    return Sets.subset(problem.goal, state) and "valid" or "goal not reached"
end

local function improve(problem, plan)
    local sequence, position = Sets.copy(plan), 1
    while position <= #sequence do
        local state, prefix, applied = problem.initial, {}, {}
        for i = 1, position - 1 do state = Search.apply(problem.actions[sequence[i]], state); append(prefix, sequence[i]) end
        for i = position + 1, #sequence do
            local action = problem.actions[sequence[i]]
            if Search.applicable(action, state) then state = Search.apply(action, state); append(applied, action.number) end
        end
        if Sets.subset(problem.goal, state) then extend(prefix, applied); sequence = prefix else position = position + 1 end
    end
    return sequence
end

local function reached_landmarks(problem, plan, landmarks)
    local state, reached = problem.initial, {}
    for _, number in ipairs(plan) do state = Search.apply(problem.actions[number], state); reached = Sets.union(reached, Sets.intersection(state, landmarks)) end
    return reached
end

local function transform_negatives(problem)
    local negative = {}
    for _, action in ipairs(problem.actions) do negative = Sets.union(negative, action.neg) end
    local ordered, complements, actions, initial = Sets.sorted(negative), {}, {}, Sets.copy(problem.initial)
    for i, fact in ipairs(ordered) do complements[fact] = #problem.facts + i end
    for _, action in ipairs(problem.actions) do
        local pre, add, delete = Sets.copy(action.pre), Sets.copy(action.add), Sets.copy(action.delete)
        for fact in pairs(action.neg) do pre[complements[fact]] = true end
        for fact in pairs(action.delete) do if complements[fact] then add[complements[fact]] = true end end
        for fact in pairs(action.add) do if complements[fact] then delete[complements[fact]] = true end end
        append(actions, {number = action.number, pre = pre, add = add, delete = delete})
    end
    for _, fact in ipairs(ordered) do if not problem.initial[fact] then initial[complements[fact]] = true end end
    return actions, initial, #ordered
end

function Planner.new()
    local domain = Parser.domain(Parser.read("input/domain.txt"))
    validate_domain(domain)
    local settings, tags, totals = read_settings(), {}, {}
    for _, pair in ipairs(settings.runs) do append(tags, table.concat(pair, " ")); append(totals, {solved = 0, best = 0, expanded = 0, generated = 0}) end
    append(tags, "graphplan")
    append(totals, {solved = 0, best = 0, expanded = 0, generated = 0})
    return setmetatable({domain = domain, sources = Parser.problems(Parser.read("input/problems.txt")), settings = settings,
        candidates = read_candidates(), tags = tags, totals = totals, grounding_lines = {}, plan_lines = {}, graph_lines = {},
        validation_lines = {}, comparison_lines = {"problem,algorithm,heuristic,length,cost,expanded,generated"},
        problems = {}, evaluators = {}, summaries = {}, validated_plans = 0, valid_plans = 0, valid_candidates = 0}, Planner)
end

function Planner:domain_report()
    local domain, lines = self.domain, self.grounding_lines
    append(lines, "== domain " .. domain.name .. " ==")
    extend(lines, domain.diagnostics)
    for _, kind in ipairs(domain.type_order) do
        local chain, current = {}, kind
        while current do append(chain, current); current = domain.parents[current] end
        append(lines, "type " .. table.concat(chain, " < "))
    end
    for _, name in ipairs(domain.predicate_order) do append(lines, string.format("predicate %s/%d %s", name,
        #domain.predicates[name], domain.fluent[name] and "fluent" or "static")) end
    for _, action in ipairs(domain.actions) do
        local adds, deletes = 0, 0
        for _, literal in ipairs(action.effects) do if literal.sign then adds = adds + 1 else deletes = deletes + 1 end end
        append(lines, string.format("action %s/%d cost=%d pre=%d add=%d del=%d", action.name, #action.parameters,
            action.cost, #action.condition, adds, deletes))
    end
end

function Planner:grounding_report(problem)
    local lines = self.grounding_lines
    append(lines, "")
    append(lines, "== problem " .. problem.name .. " ==")
    extend(lines, problem.source.diagnostics)
    append(lines, "objects: " .. #problem.source.object_order)
    for _, kind in ipairs(self.domain.type_order) do append(lines, headed("  " .. kind .. ":", problem.objects_by_type[kind])) end
    append(lines, "static facts: " .. problem.static_count)
    for _, action in ipairs(self.domain.actions) do
        local s = problem.statistics[action.name]
        append(lines, string.format("schema %s: assignments=%d candidates=%d reachable=%d", action.name, s[1], s[2], s[3]))
    end
    append(lines, string.format("candidates: %d reachable: %d", problem.candidate_count, #problem.actions))
    append(lines, string.format("facts: %d init: %d goals: %d", #problem.facts, Sets.size(problem.initial), Sets.size(problem.goal)))
    for _, atom in ipairs(problem.unreachable) do append(lines, "unreachable goal: " .. atom.key) end
    local counts, entries = {}, {}
    for _, atom in ipairs(problem.facts) do counts[atom.predicate] = (counts[atom.predicate] or 0) + 1 end
    for _, name in ipairs(self.domain.predicate_order) do if self.domain.fluent[name] then append(entries, name .. "=" .. (counts[name] or 0)) end end
    append(lines, headed("facts by predicate:", entries))
    append(lines, "facts:")
    for i, atom in ipairs(problem.facts) do append(lines, string.format("  %d %s", i - 1, atom.key)) end
    append(lines, "actions:")
    for _, action in ipairs(problem.actions) do append(lines, string.format("  %d %s cost=%d pre=%s neg=%s add=%s del=%s",
        action.number - 1, action_text(action), action.cost, number_list(action.pre), number_list(action.neg), number_list(action.add), number_list(action.delete))) end
end

function Planner:initial_report(problem, evaluator)
    local values = evaluator:values(problem.initial)
    local landmarks, relaxed = evaluator:landmarks(problem.initial) or {}, evaluator:relaxed_plan(problem.initial) or {}
    local lines = self.plan_lines
    append(lines, "initial h: " .. heuristic_text(values))
    append(lines, "landmarks: " .. Sets.size(landmarks))
    for _, number in ipairs(Sets.sorted(landmarks)) do append(lines, "  " .. problem.facts[number].key) end
    append(lines, string.format("relaxed plan: length=%d cost=%s", #relaxed, value_text(values.ff)))
    for _, number in ipairs(relaxed) do append(lines, "  " .. action_text(problem.actions[number])) end
    local helpful = {}
    for _, number in ipairs(evaluator:helpful(problem.initial)) do append(helpful, action_text(problem.actions[number])) end
    append(lines, headed("helpful:", helpful))
    return landmarks
end

function Planner:plan_report(problem, tag, plan, landmarks, earlier)
    local lines, key = self.plan_lines, table.concat(plan, ",")
    local first = earlier[key]
    if not first then earlier[key] = tag end
    append(lines, string.format("plan: length=%d cost=%d", #plan, plan_cost(problem, plan)) .. (first and " (same as " .. first .. ")" or ""))
    local counts = {}
    for position, number in ipairs(plan) do
        local action = problem.actions[number]
        append(lines, string.format("  %d %s", position, action_text(action)))
        counts[action.source.name] = (counts[action.source.name] or 0) + 1
    end
    local schemas = {}
    for _, action in ipairs(self.domain.actions) do if counts[action.name] then append(schemas, action.name .. "=" .. counts[action.name]) end end
    append(lines, headed("schemas:", schemas))
    local layers = parallelize(problem, plan)
    append(lines, "parallel: layers=" .. #layers)
    for i, layer in ipairs(layers) do
        local names = {}
        for _, number in ipairs(layer) do append(names, action_text(problem.actions[number])) end
        append(lines, headed("  " .. i .. ":", names))
    end
    local improved = improve(problem, plan)
    local removed = #plan - #improved
    append(lines, string.format("improved: length=%d cost=%d removed=%d", #improved, plan_cost(problem, improved), removed))
    if removed > 0 then for i, number in ipairs(improved) do append(lines, string.format("  %d %s", i, action_text(problem.actions[number]))) end end
    local reached = reached_landmarks(problem, plan, landmarks)
    append(lines, string.format("landmarks reached: %d/%d", Sets.size(reached), Sets.size(landmarks)))
    for _, number in ipairs(Sets.sorted(Sets.difference(landmarks, reached))) do append(lines, "  missed " .. problem.facts[number].key) end
    local checked = validate_steps(self.domain, problem.source, plan_steps(problem, plan))
    local checked_improved = validate_steps(self.domain, problem.source, plan_steps(problem, improved))
    append(self.validation_lines, tag .. ": " .. verdict(checked))
    append(self.validation_lines, "  parallel: " .. validate_parallel(problem, layers))
    append(self.validation_lines, "  improved: " .. verdict(checked_improved))
    self.validated_plans = self.validated_plans + 1
    if checked.status == "valid" then self.valid_plans = self.valid_plans + 1 end
end

function Planner:search_result_report(problem, tag, outcome, landmarks, earlier)
    append(self.plan_lines, "-- " .. tag .. " --")
    if #problem.unreachable > 0 then append(self.plan_lines, "result: FAIL (unreachable goal)"); return end
    local state = outcome.status == "solved" and "solved" or "FAIL (" .. outcome.status .. ")"
    append(self.plan_lines, string.format("result: %s expanded=%d generated=%d", state, outcome.expanded, outcome.generated))
    if outcome.status == "solved" then self:plan_report(problem, tag, outcome.plan, landmarks, earlier) end
end

function Planner:graph_report(problem, outcome, complements)
    local lines = self.graph_lines
    if #problem.unreachable > 0 then append(lines, "result: FAIL (unreachable goal)"); return end
    append(lines, "complementary facts: " .. complements)
    extend(lines, outcome.lines)
    local counts = string.format(" searched=%d memo_hits=%d tried=%d", outcome.expanded, outcome.memo_hits, outcome.generated)
    if outcome.status == "solved" then
        append(lines, string.format("result: solved levels=%d length=%d cost=%d", #outcome.layers, #outcome.plan, plan_cost(problem, outcome.plan)) .. counts)
        for i, layer in ipairs(outcome.layers) do
            local names = {}
            for _, number in ipairs(layer) do append(names, action_text(problem.actions[number])) end
            append(lines, headed("layer " .. i .. ":", names))
        end
    else append(lines, "result: FAIL (" .. outcome.status .. ")" .. counts) end
end

function Planner:profile_report(problem, evaluator, tag, plan)
    local lines, state, remaining, overestimates = self.plan_lines, problem.initial, plan_cost(problem, plan), {}
    for _, name in ipairs(Heuristics.names) do overestimates[name] = 0 end
    append(lines, "-- profile (" .. tag .. ") --")
    for position = 0, #plan do
        local values = evaluator:values(state)
        append(lines, string.format("  %d: h*=%d %s", position, remaining, heuristic_text(values)))
        for _, name in ipairs(Heuristics.names) do if values[name] > remaining then overestimates[name] = overestimates[name] + 1 end end
        if position < #plan then
            local action = problem.actions[plan[position + 1]]
            state, remaining = Search.apply(action, state), remaining - action.cost
        end
    end
    local entries = {}
    for _, name in ipairs(Heuristics.names) do append(entries, name .. "=" .. overestimates[name]) end
    append(lines, "overestimates: " .. table.concat(entries, " "))
    append(lines, "-- causal links (" .. tag .. ") --")
    local suppliers = {}
    for position, number in ipairs(plan) do
        local action, links = problem.actions[number], {}
        for _, fact in ipairs(Sets.sorted(action.pre)) do append(links, problem.facts[fact].key .. "<-" .. (suppliers[fact] or 0)) end
        append(lines, headed("  " .. position .. " " .. action_text(action) .. ":", links))
        for fact in pairs(action.add) do suppliers[fact] = position end
    end
    entries = {}
    for _, fact in ipairs(Sets.sorted(problem.goal)) do append(entries, problem.facts[fact].key .. "<-" .. (suppliers[fact] or 0)) end
    append(lines, headed("  goal:", entries))
end

function Planner:summarize_problem(problem, outcomes, proof)
    local solved, best = 0, nil
    for _, outcome in ipairs(outcomes) do
        if outcome.status == "solved" then
            solved = solved + 1
            local cost = plan_cost(problem, outcome.plan)
            best = best and math.min(best, cost) or cost
        end
    end
    local optimal = "unknown"
    if proof then optimal = tostring(plan_cost(problem, outcomes[proof].plan))
    else
        for _, outcome in ipairs(outcomes) do
            if outcome.status == "unreachable goal" or outcome.status == "dead end" or outcome.status == "exhausted" or outcome.status == "unreachable" then optimal = "none"; break end
        end
    end
    self.summaries[problem.name] = {solved = solved, best = best, optimal = optimal}
    for index, outcome in ipairs(outcomes) do
        local pair, totals = self.settings.runs[index] or {"graphplan", "none"}, self.totals[index]
        totals.expanded, totals.generated = totals.expanded + outcome.expanded, totals.generated + outcome.generated
        local length, cost = "-", "-"
        if outcome.status == "solved" then
            length, cost = #outcome.plan, plan_cost(problem, outcome.plan)
            totals.solved = totals.solved + 1
            if cost == best then totals.best = totals.best + 1 end
        end
        append(self.comparison_lines, table.concat({problem.name, pair[1], pair[2], length, cost, outcome.expanded, outcome.generated}, ","))
    end
end

function Planner:solve_problem(source)
    validate_problem(self.domain, source)
    local problem = Sets.ground(self.domain, source)
    self.problems[problem.name] = problem
    self:grounding_report(problem)
    for _, lines in ipairs({self.plan_lines, self.graph_lines, self.validation_lines}) do append(lines, "== problem " .. problem.name .. " ==") end
    local outcomes, earlier, proof, evaluator, landmarks = {}, {}, nil, nil, {}
    if #problem.unreachable > 0 then append(self.plan_lines, "initial h: unreachable goal")
    else
        evaluator = Heuristics.new(problem)
        self.evaluators[problem.name] = evaluator
        landmarks = self:initial_report(problem, evaluator)
    end
    for index, pair in ipairs(self.settings.runs) do
        local algorithm, heuristic, outcome = pair[1], pair[2]
        if #problem.unreachable > 0 then outcome = Search.result("unreachable goal")
        else outcome = Search.run(problem, problem.initial, algorithm, heuristic, self.settings.budget, self.settings.weight, evaluator) end
        append(outcomes, outcome)
        self:search_result_report(problem, self.tags[index], outcome, landmarks, earlier)
        if not proof and ((algorithm == "ucs" and heuristic == "none") or (algorithm == "astar" and heuristic == "hmax")) and outcome.status == "solved" then proof = index end
    end
    local graph, complements = nil, 0
    if #problem.unreachable > 0 then graph = Search.result("unreachable goal")
    else
        local actions, initial
        actions, initial, complements = transform_negatives(problem)
        graph = Graph.new(actions, initial, problem.goal, self.settings.graphplan):run()
    end
    append(outcomes, graph)
    self:search_result_report(problem, "graphplan", graph, landmarks, earlier)
    self:graph_report(problem, graph, complements)
    if proof then self:profile_report(problem, evaluator, self.tags[proof], outcomes[proof].plan) end
    self:summarize_problem(problem, outcomes, proof)
    for _, lines in ipairs({self.plan_lines, self.graph_lines, self.validation_lines}) do append(lines, "") end
end

function Planner:summary_report()
    append(self.plan_lines, "== summary ==")
    for _, source in ipairs(self.sources) do
        local summary = self.summaries[source.name]
        append(self.plan_lines, string.format("%s: solved=%d/%d best=%s optimal=%s", source.name, summary.solved,
            #self.tags, summary.best ~= nil and tostring(summary.best) or "-", summary.optimal))
    end
    for index, tag in ipairs(self.tags) do
        local totals = self.totals[index]
        append(self.plan_lines, string.format("%s: solved=%d best=%d expanded=%d generated=%d", tag, totals.solved,
            totals.best, totals.expanded, totals.generated))
    end
end

function Planner:mapped_steps(problem, steps, count)
    local plan = {}
    for i = 1, count or #steps do
        local step = steps[i]
        append(plan, assert(problem.action_numbers[step.name .. " " .. table.concat(step.arguments, " ")]))
    end
    return plan
end

function Planner:repair_candidate(problem, candidate, checked)
    if #problem.unreachable > 0 then append(self.validation_lines, "  repair: FAIL (unreachable goal)"); return end
    local prefix = self:mapped_steps(problem, candidate.steps, checked.correct)
    local state = problem.initial
    for _, number in ipairs(prefix) do state = Search.apply(problem.actions[number], state) end
    local pair = self.settings.repair
    local outcome = Search.run(problem, state, pair[1], pair[2], self.settings.budget, self.settings.weight, self.evaluators[problem.name])
    if outcome.status ~= "solved" then append(self.validation_lines, "  repair: FAIL (" .. outcome.status .. ")"); return end
    local repaired = Sets.copy(prefix)
    extend(repaired, outcome.plan)
    local checked_repair = validate_steps(self.domain, problem.source, plan_steps(problem, repaired))
    append(self.validation_lines, string.format("  repair: kept=%d added=%d %s", #prefix, #outcome.plan, verdict(checked_repair)))
    for position, number in ipairs(repaired) do append(self.validation_lines, string.format("    %d %s", position, action_text(problem.actions[number]))) end
end

function Planner:candidate_report()
    local lines = self.validation_lines
    append(lines, "== candidates ==")
    for _, candidate in ipairs(self.candidates) do
        local problem = self.problems[candidate.problem]
        local checked = validate_steps(self.domain, problem.source, candidate.steps)
        local heading = string.format("candidate %d %s %s: ", candidate.number, candidate.problem, candidate.label)
        if checked.status == "valid" then
            self.valid_candidates = self.valid_candidates + 1
            append(lines, heading .. verdict(checked))
            local mapped = self:mapped_steps(problem, candidate.steps)
            local improved, best = improve(problem, mapped), self.summaries[problem.name].best
            append(lines, string.format("  improved: length=%d cost=%d removed=%d best known=%s", #improved,
                plan_cost(problem, improved), #mapped - #improved, best ~= nil and tostring(best) or "-"))
        else
            append(lines, heading .. checked.status)
            for _, message in ipairs(checked.messages) do append(lines, "  " .. message) end
            self:repair_candidate(problem, candidate, checked)
        end
    end
    extend(lines, {"", "== summary ==", string.format("plans: %d valid: %d", self.validated_plans, self.valid_plans),
        string.format("candidates: %d valid: %d", #self.candidates, self.valid_candidates)})
end

function Planner:write_reports()
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs({{"grounding.txt", self.grounding_lines}, {"plans.txt", self.plan_lines},
        {"graphplan.txt", self.graph_lines}, {"validation.txt", self.validation_lines}, {"comparison.csv", self.comparison_lines}}) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

function Planner:run()
    self:domain_report()
    for _, source in ipairs(self.sources) do self:solve_problem(source) end
    self:summary_report()
    self:candidate_report()
    self:write_reports()
end

Planner.new():run()
