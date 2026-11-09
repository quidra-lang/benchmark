local Q = require("rational")
local parser = require("lp_parser")
local Tableau = require("tableau")
local phase = require("simplex")
local branch_bound = require("branch_bound")
local Z, ONE = Q.zero, Q.one
local function copy(values) return { table.unpack(values) } end
local function zeros(n)
    local values = {}
    for i = 1, n do values[i] = Z end
    return values
end
local function append(target, source)
    for _, line in ipairs(source) do target[#target + 1] = line end
end
local function dot(a, b)
    local result = Z
    for i, value in ipairs(a) do result = result + value * b[i] end
    return result
end
local function coefficients(terms, positions, n)
    local values = zeros(n)
    for _, term in ipairs(terms) do
        local j = positions[term[1]]
        values[j] = values[j] + term[2]
    end
    return values
end
local function content_check(model)
    if model.error then return model end
    local variables, positions, expressions = {}, {}, { model.objective }
    for _, row in ipairs(model.constraints) do expressions[#expressions + 1] = row.terms end
    for _, terms in ipairs(expressions) do
        for _, term in ipairs(terms) do
            if not positions[term[1]] then
                variables[#variables + 1] = term[1]
                positions[term[1]] = #variables
            end
        end
    end
    model.variables, model.costs = variables, coefficients(model.objective, positions, #variables)
    model.matrix, model.rhs, model.comparisons = {}, {}, {}
    model.lower, model.upper, model.integer, model.integer_count = {}, {}, {}, 0
    for j = 1, #variables do model.lower[j], model.upper[j], model.integer[j] = Z, false, false end
    local seen = {}
    for i, row in ipairs(model.constraints) do
        if seen[row.name] then model.error = { row.line, "duplicate constraint " .. row.name }; return model end
        seen[row.name] = true
        model.matrix[i], model.rhs[i], model.comparisons[i] = coefficients(row.terms, positions, #variables), row.rhs, row.comparison
    end
    local function variable(name, line)
        local j = positions[name]
        if not j then model.error = { line, "unknown variable " .. name } end
        return j
    end
    local function consistent(j, line)
        if model.lower[j] and model.upper[j] and model.lower[j] > model.upper[j] then
            model.error = { line, "inconsistent bounds " .. variables[j] }
            return false
        end
        return true
    end
    for _, bound in ipairs(model.bounds) do
        local j = variable(bound.name, bound.line)
        if not j then return model end
        if bound.kind == "lower" or bound.kind == "both" then model.lower[j] = bound.lower end
        if bound.kind == "upper" or bound.kind == "both" then model.upper[j] = bound.upper end
        if not consistent(j, bound.line) then return model end
    end
    for _, declaration in ipairs(model.integers) do
        for _, name in ipairs(declaration[2]) do
            local j = variable(name, declaration[1])
            if not j then return model end
            model.integer[j] = true
            if model.lower[j] then model.lower[j] = Q.new(Q.ceil(model.lower[j])) end
            if model.upper[j] then model.upper[j] = Q.new(Q.floor(model.upper[j])) end
            if not consistent(j, declaration[1]) then return model end
        end
    end
    for _, declaration in ipairs(model.binaries) do
        for _, name in ipairs(declaration[2]) do
            local j = variable(name, declaration[1])
            if not j then return model end
            model.integer[j], model.lower[j], model.upper[j] = true, Z, ONE
        end
    end
    for _, integer in ipairs(model.integer) do if integer then model.integer_count = model.integer_count + 1 end end
    return model
end
local function standard_form(model, lower, upper)
    local form = { column_names = {}, row_names = {}, mappings = {}, matrix = {}, rhs = {}, signs = {},
        slack = {}, artificial = {}, initial = {}, phase1 = {}, phase2 = {}, artificial_count = 0,
        direction = model.direction == "minimize" and 1 or -1 }
    local owners, directions, offsets = {}, {}, {}
    for j, name in ipairs(model.variables) do
        local first, mapping = #form.column_names + 1, {}
        if lower[j] then
            mapping.kind, mapping.offset, mapping.columns, mapping.directions = "shift", lower[j], { first }, { 1 }
            form.column_names[first] = name
        elseif upper[j] then
            mapping.kind, mapping.offset, mapping.columns, mapping.directions = "reflect", upper[j], { first }, { -1 }
            form.column_names[first] = name .. "'"
        else
            mapping.kind, mapping.offset, mapping.columns, mapping.directions = "split", Z, { first, first + 1 }, { 1, -1 }
            form.column_names[first], form.column_names[first + 1] = name .. "+", name .. "-"
        end
        for i, column in ipairs(mapping.columns) do owners[column], directions[column] = j, mapping.directions[i] end
        form.mappings[j], offsets[j] = mapping, mapping.offset
    end
    local comparisons = copy(model.comparisons)
    for i, original in ipairs(model.matrix) do
        local row = {}
        for k, j in ipairs(owners) do row[k] = directions[k] * original[j] end
        form.matrix[i], form.rhs[i], form.row_names[i] = row, model.rhs[i] - dot(original, offsets), model.constraints[i].name
    end
    for j, mapping in ipairs(form.mappings) do
        if mapping.kind == "shift" and upper[j] then
            local i = #form.row_names + 1
            mapping.upper_row = i
            form.row_names[i], form.matrix[i] = model.variables[j] .. ".ub", zeros(#form.column_names)
            form.matrix[i][mapping.columns[1]], form.rhs[i], comparisons[i] = ONE, upper[j] - lower[j], "<="
        end
    end
    for i, row in ipairs(form.matrix) do
        form.signs[i] = 1
        if form.rhs[i] < Z then
            for k, value in ipairs(row) do row[k] = -value end
            form.rhs[i], form.signs[i] = -form.rhs[i], -1
            comparisons[i] = comparisons[i] == "<=" and ">=" or (comparisons[i] == ">=" and "<=" or "=")
        end
    end
    for i, comparison in ipairs(comparisons) do
        form.slack[i] = false
        if comparison ~= "=" then
            local k = #form.column_names + 1
            form.slack[i], form.column_names[k] = k, "s:" .. form.row_names[i]
            for t, row in ipairs(form.matrix) do row[k] = Q.new(t == i and (comparison == "<=" and 1 or -1) or 0) end
            if comparison == "<=" then form.initial[i] = k end
        end
    end
    for i, comparison in ipairs(comparisons) do
        if comparison ~= "<=" then
            local k = #form.column_names + 1
            form.artificial[k], form.initial[i], form.column_names[k] = true, k, "a:" .. form.row_names[i]
            form.artificial_count = form.artificial_count + 1
            for t, row in ipairs(form.matrix) do row[k] = t == i and ONE or Z end
        end
    end
    for k = 1, #form.column_names do
        form.phase1[k] = form.artificial[k] and ONE or Z
        form.phase2[k] = owners[k] and form.direction * directions[k] * model.costs[owners[k]] or Z
    end
    form.constant = dot(model.costs, offsets)
    return form
end
local function solution(form, tableau)
    local values, result = zeros(#form.column_names), {}
    for i, basic in ipairs(tableau.basic) do values[basic] = tableau.rhs[i] end
    for j, mapping in ipairs(form.mappings) do
        local value = mapping.offset
        for i, k in ipairs(mapping.columns) do value = value + mapping.directions[i] * values[k] end
        result[j] = value
    end
    return result
end
local function solve_lp(model, lower, upper, number, level)
    local form = standard_form(model, lower, upper)
    local tableau = Tableau.new(form)
    local result = { form = form, tableau = tableau, lines = {}, status = "OPTIMAL", phase1 = 0,
        phase2 = 0, drives = 0, redundant = 0, infeasibility = Z }
    local function emit(required, text) if required <= level then result.lines[#result.lines + 1] = text end end
    local function display(heading, costs, objective)
        if level >= 2 then append(result.lines, tableau:display(heading, costs, objective)) end
    end
    local function original(value) return form.constant + form.direction * value end
    local function identity(value) return value end
    emit(0, string.format("SOLVE node %d rows %d columns %d artificials %d", number, #form.row_names, #form.column_names, form.artificial_count))
    for j, mapping in ipairs(form.mappings) do
        local line = "MAP " .. model.variables[j] .. " " .. mapping.kind
        if mapping.kind ~= "split" then line = line .. " " .. mapping.offset end
        if mapping.kind == "shift" and upper[j] then line = line .. " upper " .. upper[j] end
        emit(1, line)
    end
    for i, sign in ipairs(form.signs) do if sign == -1 then emit(1, "FLIP " .. form.row_names[i]) end end
    local all, nonartificial = {}, {}
    for k = 1, #form.column_names do
        all[#all + 1] = k
        if not form.artificial[k] then nonartificial[#nonartificial + 1] = k end
    end
    if form.artificial_count > 0 then
        emit(1, "PHASE 1")
        display("phase 1 start", form.phase1, identity)
        local outcome = phase(tableau, form.phase1, all, identity)
        result.phase1, result.infeasibility = outcome.iterations, tableau:phase_value(form.phase1)
        for _, line in ipairs(outcome.lines) do emit(1, line) end
        emit(1, "PHASE 1 END objective " .. result.infeasibility .. " iterations " .. result.phase1)
        if result.infeasibility > Z then
            result.status = "INFEASIBLE"
            display("final", form.phase1, identity)
        else
            for i, basic in ipairs(tableau.basic) do
                if form.artificial[basic] then
                    local entering = false
                    for _, k in ipairs(nonartificial) do if tableau.values[i][k] ~= Z then entering = k; break end end
                    if not entering then
                        result.redundant = result.redundant + 1
                        emit(1, "REDUNDANT row " .. form.row_names[i])
                    else
                        local leaving = form.column_names[basic]
                        tableau:pivot(i, entering)
                        result.drives = result.drives + 1
                        emit(1, "DRIVE row " .. form.row_names[i] .. " enter " .. form.column_names[entering] .. " leave " .. leaving)
                    end
                end
            end
        end
    end
    if result.status ~= "INFEASIBLE" then
        emit(1, "PHASE 2")
        display("phase 2 start", form.phase2, original)
        local outcome = phase(tableau, form.phase2, nonartificial, original)
        result.phase2, result.unbounded = outcome.iterations, outcome.unbounded
        for _, line in ipairs(outcome.lines) do emit(1, line) end
        if outcome.unbounded then
            result.status = "UNBOUNDED"
            emit(1, "UNBOUNDED enter " .. form.column_names[outcome.unbounded])
        end
        emit(1, "PHASE 2 END objective " .. original(tableau:phase_value(form.phase2)) .. " iterations " .. result.phase2)
        display("final", form.phase2, original)
    end
    result.objective = result.status == "OPTIMAL" and original(tableau:phase_value(form.phase2)) or false
    result.solution, result.pivots = solution(form, tableau), result.phase1 + result.phase2 + result.drives
    emit(0, string.format("RESULT %s objective %s phase1 %d phase2 %d drives %d redundant %d", result.status,
        result.objective and tostring(result.objective) or "-", result.phase1, result.phase2, result.drives, result.redundant))
    return result
end
local function range(origin, coefficients, numerators)
    local lower, upper = false, false
    for i, coefficient in ipairs(coefficients) do
        if coefficient ~= Z then
            local value = numerators[i] / coefficient
            if coefficient > Z then
                if not lower or lower < value then lower = value end
            elseif not upper or upper > value then upper = value end
        end
    end
    return lower and origin + lower or false, upper and origin + upper or false
end
local function variable_status(form, basic, j)
    local mapping = form.mappings[j]
    if mapping.kind == "split" then
        return (basic[mapping.columns[1]] or basic[mapping.columns[2]]) and "basic" or "zero"
    elseif mapping.kind == "reflect" then return basic[mapping.columns[1]] and "basic" or "upper" end
    if not basic[mapping.columns[1]] then return "lower" end
    if mapping.upper_row and not basic[form.slack[mapping.upper_row]] then return "upper" end
    return "basic"
end
local function sensitivity(model, result)
    local form, tableau = result.form, result.tableau
    local reduced, basic, nonbasic, dual, variable_reduced = tableau:reduced(form.phase2), {}, {}, {}, {}
    local basis, primal, dual_count = {}, 0, 0
    for i, k in ipairs(tableau.basic) do
        basic[k], basis[i] = true, form.column_names[k]
        if not form.artificial[k] and tableau.rhs[i] == Z then primal = primal + 1 end
    end
    for k = 1, #form.column_names do
        if not basic[k] and not form.artificial[k] then
            nonbasic[#nonbasic + 1] = k
            if reduced[k] == Z then dual_count = dual_count + 1 end
        end
    end
    for i = 1, #model.constraints do dual[i] = -form.direction * form.signs[i] * reduced[form.initial[i]] end
    for j, cost in ipairs(model.costs) do
        local value = cost
        for i, price in ipairs(dual) do value = value - price * model.matrix[i][j] end
        variable_reduced[j] = value
    end
    local kind = model.integer_count > 0 and "relaxation" or "lp"
    local lines = { "MODEL " .. model.name .. " " .. kind .. " objective " .. result.objective,
        "BASIS " .. table.concat(basis, " "), "DEGENERACY primal " .. primal .. " dual " .. dual_count,
        "DUAL objective " .. (dot(dual, model.rhs) + dot(variable_reduced, result.solution)) }
    for i, constraint in ipairs(model.constraints) do
        local rho, numerators, pinned = {}, {}, false
        for t, row in ipairs(tableau.values) do
            rho[t], numerators[t] = form.signs[i] * row[form.initial[i]], -tableau.rhs[t]
            if rho[t] ~= Z and form.artificial[tableau.basic[t]] then pinned = true end
        end
        local lower, upper
        if pinned then lower, upper = model.rhs[i], model.rhs[i]
        else lower, upper = range(model.rhs[i], rho, numerators) end
        lines[#lines + 1] = string.format("CONSTRAINT %s price %s rhs %s range %s %s", constraint.name,
            dual[i], model.rhs[i], Q.endpoint(lower, true), Q.endpoint(upper, false))
    end
    for j, name in ipairs(model.variables) do
        local h = zeros(#form.column_names)
        local mapping = form.mappings[j]
        for i, k in ipairs(mapping.columns) do h[k] = Q.new(form.direction * mapping.directions[i]) end
        local eta, numerators = {}, {}
        for t, k in ipairs(nonbasic) do
            local value = h[k]
            for i, b in ipairs(tableau.basic) do value = value - h[b] * tableau.values[i][k] end
            eta[t], numerators[t] = value, -reduced[k]
        end
        local lower, upper = range(model.costs[j], eta, numerators)
        lines[#lines + 1] = string.format("VARIABLE %s %s value %s reduced %s cost %s range %s %s", name,
            variable_status(form, basic, j), result.solution[j], variable_reduced[j], model.costs[j],
            Q.endpoint(lower, true), Q.endpoint(upper, false))
    end
    return lines
end
local function statistics(model)
    local matrix, bounds = {}, {}
    for _, row in ipairs(model.matrix) do
        for _, value in ipairs(row) do if value ~= Z then matrix[#matrix + 1] = value end end
    end
    for j = 1, #model.variables do
        if model.lower[j] then bounds[#bounds + 1] = model.lower[j] end
        if model.upper[j] then bounds[#bounds + 1] = model.upper[j] end
    end
    local parts = { "STATS nonzeros " .. #matrix }
    for _, entry in ipairs({ { "matrix", matrix }, { "objective", model.costs }, { "rhs", model.rhs }, { "bounds", bounds } }) do
        local low, high = false, false
        for _, value in ipairs(entry[2]) do
            if value ~= Z then
                local magnitude = Q.abs(value)
                if not low or magnitude < low then low = magnitude end
                if not high or magnitude > high then high = magnitude end
            end
        end
        parts[#parts + 1] = entry[1] .. " " .. (low and tostring(low) or "-") .. " " .. (high and tostring(high) or "-")
    end
    return table.concat(parts, " ")
end
local function solution_lines(model, result, pivots)
    local root = result.root
    local lines = { string.format("MODEL %s %s variables %d constraints %d integers %d", model.name, model.direction,
        #model.variables, #model.constraints, model.integer_count), statistics(model), "STATUS " .. result.status }
    if result.solution then
        lines[#lines + 1] = "OBJECTIVE " .. result.objective .. " approx " .. Q.approximate(result.objective)
    end
    if model.integer_count > 0 and root.status == "OPTIMAL" then
        lines[#lines + 1] = "RELAXATION " .. root.objective .. " approx " .. Q.approximate(root.objective)
    end
    if root.status == "INFEASIBLE" then
        lines[#lines + 1] = "INFEASIBILITY " .. root.infeasibility
        local reduced = root.tableau:reduced(root.form.phase1)
        for i, name in ipairs(root.form.row_names) do
            local k = root.form.initial[i]
            local multiplier = root.form.signs[i] * (root.form.phase1[k] - reduced[k])
            lines[#lines + 1] = "FARKAS " .. name .. " " .. multiplier
        end
    end
    local values = result.status == "UNBOUNDED" and root.solution or result.solution
    if values then
        for j, name in ipairs(model.variables) do lines[#lines + 1] = "VALUE " .. name .. " " .. values[j] end
    end
    if result.status == "UNBOUNDED" then
        local form, tableau, q = root.form, root.tableau, root.unbounded
        local delta, ray = zeros(#form.column_names), {}
        delta[q] = ONE
        for i, basic in ipairs(tableau.basic) do delta[basic] = -tableau.values[i][q] end
        for j, mapping in ipairs(form.mappings) do
            local value = Z
            for i, k in ipairs(mapping.columns) do value = value + mapping.directions[i] * delta[k] end
            ray[j] = value
            lines[#lines + 1] = "RAY " .. model.variables[j] .. " " .. value
        end
        lines[#lines + 1] = "RATE " .. dot(model.costs, ray)
    end
    if result.solution then
        for i, constraint in ipairs(model.constraints) do
            local value = dot(model.matrix[i], result.solution)
            local margin = model.comparisons[i] == "<=" and model.rhs[i] - value or value - model.rhs[i]
            lines[#lines + 1] = "ROW " .. constraint.name .. " " .. value .. " " .. margin
        end
    end
    if model.integer_count > 0 then lines[#lines + 1] = "NODES " .. result.nodes end
    lines[#lines + 1] = "PIVOTS " .. pivots
    return lines
end
local settings = parser.settings()
local iterations, solutions, sensitivities, tree = {}, {}, {}, {}
local summary = { "model,status,objective,approx,relaxation,nodes,pivots" }
local statuses = { OPTIMAL = 0, INFEASIBLE = 0, UNBOUNDED = 0, NODE_LIMIT = 0, ERROR = 0 }
local counts = { models = 0, solves = 0, phase1 = 0, phase2 = 0, drives = 0,
    analyzed = 0, integer_models = 0, integer_nodes = 0, limited_models = 0 }
for _, parsed in ipairs(parser.models()) do
    local model = content_check(parsed)
    counts.models = counts.models + 1
    if model.error then
        statuses.ERROR = statuses.ERROR + 1
        iterations[#iterations + 1] = "MODEL " .. model.name .. " error"
        solutions[#solutions + 1] = "MODEL " .. model.name
        solutions[#solutions + 1] = "STATUS ERROR line " .. model.error[1] .. " " .. model.error[2]
        sensitivities[#sensitivities + 1] = "MODEL " .. model.name .. " skipped ERROR"
        summary[#summary + 1] = model.name .. ",ERROR,-,-,-,0,0"
    else
        local level, limit = settings.logs[model.name] or settings.level, settings.limits[model.name] or settings.limit
        local function solve(lower, upper, number) return solve_lp(model, lower, upper, number, level) end
        local result
        if model.integer_count > 0 then result = branch_bound(model, limit, solve)
        else
            local lp = solve(model.lower, model.upper, 1)
            result = { status = lp.status, objective = lp.objective, root = lp, solves = { lp }, nodes = 1,
                solution = lp.status == "OPTIMAL" and lp.solution or false, lines = {} }
        end
        statuses[result.status] = statuses[result.status] + 1
        iterations[#iterations + 1] = "MODEL " .. model.name .. " level " .. level
        local pivots = 0
        for _, lp in ipairs(result.solves) do
            append(iterations, lp.lines)
            counts.solves, counts.phase1 = counts.solves + 1, counts.phase1 + lp.phase1
            counts.phase2, counts.drives = counts.phase2 + lp.phase2, counts.drives + lp.drives
            pivots = pivots + lp.pivots
        end
        append(solutions, solution_lines(model, result, pivots))
        if result.root.status == "OPTIMAL" then
            counts.analyzed = counts.analyzed + 1
            append(sensitivities, sensitivity(model, result.root))
        else sensitivities[#sensitivities + 1] = "MODEL " .. model.name .. " skipped " .. result.root.status end
        if model.integer_count > 0 then
            counts.integer_models, counts.integer_nodes = counts.integer_models + 1, counts.integer_nodes + result.nodes
            if result.status == "NODE_LIMIT" then counts.limited_models = counts.limited_models + 1 end
            tree[#tree + 1] = string.format("MODEL %s %s integers %d node_limit %d", model.name, model.direction, model.integer_count, limit)
            append(tree, result.lines)
        end
        summary[#summary + 1] = table.concat({ model.name, result.status,
            result.objective and tostring(result.objective) or "-", result.objective and Q.approximate(result.objective) or "-",
            result.root.objective and tostring(result.root.objective) or "-", tostring(#result.solves), tostring(pivots) }, ",")
    end
end
iterations[#iterations + 1] = string.format("TOTAL solves %d phase1 %d phase2 %d drives %d pivots %d", counts.solves,
    counts.phase1, counts.phase2, counts.drives, counts.phase1 + counts.phase2 + counts.drives)
solutions[#solutions + 1] = string.format("SUMMARY models %d optimal %d infeasible %d unbounded %d node_limit %d error %d",
    counts.models, statuses.OPTIMAL, statuses.INFEASIBLE, statuses.UNBOUNDED, statuses.NODE_LIMIT, statuses.ERROR)
sensitivities[#sensitivities + 1] = string.format("SUMMARY analyzed %d skipped %d", counts.analyzed, counts.models - counts.analyzed)
tree[#tree + 1] = string.format("SUMMARY models %d nodes %d node_limit %d", counts.integer_models, counts.integer_nodes, counts.limited_models)
for _, entry in ipairs({ { "iterations.txt", iterations }, { "solutions.txt", solutions },
    { "sensitivity.txt", sensitivities }, { "bnb_tree.txt", tree }, { "summary.csv", summary } }) do
    local target = assert(io.open("output/" .. entry[1], "w"))
    target:write(table.concat(entry[2], "\n"), "\n")
    target:close()
end
