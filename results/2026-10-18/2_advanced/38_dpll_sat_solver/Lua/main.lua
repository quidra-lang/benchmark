local cnf = require("cnf_io")
local encoders = require("encoders")
local preprocess = require("preprocess")
local dpll = require("dpll")
local report = require("report")
local commands = {"SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"}
local argument_types = {SOLVE = {"file"}, ENUM = {"file", "limit"}, CORE = {"file"}, QUEENS = {"small", "limit"},
    PIGEON = {"small", "small", "limit"}, COLOR = {"graph", "color", "limit"}, CHROMATIC = {"graph", "color"}}
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function words(text)
    local values = {}
    for value in text:gmatch("[^ ]+") do
        values[#values + 1] = value
    end
    return values
end
local function new_stats()
    return {decisions = 0, propagations = 0, conflicts = 0, max_depth = 0}
end
local function accumulate(target, source)
    target.decisions = target.decisions + source.decisions
    target.propagations = target.propagations + source.propagations
    target.conflicts = target.conflicts + source.conflicts
    target.max_depth = math.max(target.max_depth, source.max_depth)
end
local function load_graphs()
    local graphs, current, number = {}, nil, 0
    for line in io.lines("input/graphs.txt") do
        number = number + 1
        if not current then
            if line ~= "" and line:sub(1, 1) ~= "#" then
                local header = words(line)
                current = {name = header[2], vertices = tonumber(header[3]), edges = {}, seen = {}}
            end
        elseif line == "END" then
            table.sort(current.edges, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
            graphs[current.name], current = current, nil
        elseif not current.invalid then
            local tokens, reason = words(line), nil
            if #tokens ~= 2 or not cnf.valid_number(tokens[1]) or not cnf.valid_number(tokens[2]) then
                reason = "bad edge line"
            else
                local a, b = tonumber(tokens[1]), tonumber(tokens[2])
                if a < 1 or a > current.vertices or b < 1 or b > current.vertices then
                    reason = "vertex out of range"
                elseif a == b then
                    reason = "self loop"
                else
                    a, b = math.min(a, b), math.max(a, b)
                    local key = a .. "," .. b
                    if current.seen[key] then
                        reason = "duplicate edge"
                    else
                        current.seen[key] = true
                        current.edges[#current.edges + 1] = {a, b}
                    end
                end
            end
            if reason then
                current.invalid = reason .. " at line " .. number
            end
        end
    end
    return graphs
end
local function load_jobs()
    local jobs = {}
    for line in io.lines("input/jobs.txt") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local tokens = words(line)
            local command = table.remove(tokens, 1)
            jobs[#jobs + 1] = {number = #jobs + 1, text = line, command = command, args = tokens}
        end
    end
    return jobs
end
local function validate(job, graphs)
    local types = argument_types[job.command]
    if not types then
        return "unknown command " .. job.command
    end
    if #job.args ~= #types then
        return "wrong argument count"
    end
    for index, kind in ipairs(types) do
        local argument = job.args[index]
        if kind == "file" then
            local stem = argument:sub(1, -5)
            if argument:sub(-4) ~= ".cnf" or #stem < 1 or #stem > 20 or not stem:match("^[a-z0-9_]+$") then
                return "bad file name " .. argument
            end
        elseif kind == "graph" then
            if not graphs[argument] then
                return "unknown graph " .. argument
            elseif graphs[argument].invalid then
                return "invalid graph " .. argument .. ": " .. graphs[argument].invalid
            end
        else
            if not cnf.valid_number(argument) then
                return "bad number " .. argument
            end
            local value, maximum = tonumber(argument), ({small = 8, color = 6, limit = 200})[kind]
            if value < 1 or value > maximum then
                return "out of range " .. argument
            end
        end
    end
    return nil
end
local function greedy_coloring(graph)
    local degree, neighbors, order, colors = {}, {}, {}, {}
    for vertex = 1, graph.vertices do
        degree[vertex], neighbors[vertex], order[vertex], colors[vertex] = 0, {}, vertex, 0
    end
    for _, edge in ipairs(graph.edges) do
        local a, b = edge[1], edge[2]
        degree[a], degree[b] = degree[a] + 1, degree[b] + 1
        neighbors[a][b], neighbors[b][a] = true, true
    end
    table.sort(order, function(a, b) return degree[a] > degree[b] or (degree[a] == degree[b] and a < b) end)
    local used, maximum_degree = 0, 0
    for _, vertex in ipairs(order) do
        local present, candidate = {}, 1
        for neighbor in pairs(neighbors[vertex]) do
            if colors[neighbor] > 0 then
                present[colors[neighbor]] = true
            end
        end
        while present[candidate] do
            candidate = candidate + 1
        end
        colors[vertex], used = candidate, math.max(used, candidate)
        maximum_degree = math.max(maximum_degree, degree[vertex])
    end
    return colors, used, maximum_degree
end
local function solve_formula(variables, clauses, limit)
    local preparation = preprocess.run(variables, clauses, limit == 1)
    local models, stats, trace, blocking = {}, new_stats(), {}, {}
    local rounds, stop = 0, "limit"
    if preparation.empty_clause then
        stop = "preprocess"
    else
        while #models < limit do
            rounds = rounds + 1
            local search_clauses = {}
            append(search_clauses, preparation.clauses)
            append(search_clauses, blocking)
            local model, events, counters = dpll.run(variables, search_clauses)
            if rounds == 1 then
                trace = events
            end
            accumulate(stats, counters)
            if not model then
                stop = "all"
                break
            end
            for variable, value in pairs(preparation.fixed) do
                model[variable] = value
            end
            models[#models + 1] = model
            local block = {}
            for _, variable in ipairs(preparation.active) do
                block[#block + 1] = model[variable] and -variable or variable
            end
            blocking[#blocking + 1] = block
        end
    end
    return {variables = variables, clauses = clauses, models = models, status = #models > 0 and "SAT" or "UNSAT", rounds = rounds,
        stop = stop, trace = trace, stats = stats, preparation = preparation, removed = preparation.counts.removed}
end
local function true_literal(model, literal)
    if literal > 0 then
        return model[literal]
    end
    return not model[-literal]
end
local function satisfies(model, clauses)
    for _, clause in ipairs(clauses) do
        local satisfied = false
        for _, literal in ipairs(clause) do
            if true_literal(model, literal) then
                satisfied = true
                break
            end
        end
        if not satisfied then
            return false
        end
    end
    return true
end
local function analyze(solution)
    local models, clauses, variables = solution.models, solution.clauses, solution.variables
    if #models == 0 then
        return nil
    end
    local analysis = {distribution = {}, safe = {}, diversity = {}, backbone = {}}
    for i, model in ipairs(models) do
        for number, clause in ipairs(clauses) do
            if not satisfies(model, {clause}) then
                analysis.failure = {i, number}
                break
            end
        end
        if analysis.failure then
            break
        end
    end
    for _, clause in ipairs(clauses) do
        local count = 0
        for _, literal in ipairs(clause) do
            if true_literal(models[1], literal) then
                count = count + 1
            end
        end
        analysis.distribution[#analysis.distribution + 1] = count
    end
    for variable = 1, variables do
        local inverted = {table.unpack(models[1])}
        inverted[variable] = not inverted[variable]
        if satisfies(inverted, clauses) then
            analysis.safe[#analysis.safe + 1] = variable
        end
        local same = true
        for _, model in ipairs(models) do
            if model[variable] ~= models[1][variable] then
                same = false
                break
            end
        end
        if same then
            analysis.backbone[#analysis.backbone + 1] = models[1][variable] and variable or -variable
        end
    end
    for i = 1, #models do
        for j = i + 1, #models do
            local distance = 0
            for variable = 1, variables do
                if models[i][variable] ~= models[j][variable] then
                    distance = distance + 1
                end
            end
            analysis.diversity[#analysis.diversity + 1] = distance
        end
    end
    return analysis
end
local function unsat_core(variables, clauses)
    local remaining, decisions, conflicts = {}, 0, 0
    for i = 1, #clauses do
        remaining[i] = true
    end
    for remove = 1, #clauses do
        local candidate = {}
        for number, clause in ipairs(clauses) do
            if remaining[number] and number ~= remove then
                candidate[#candidate + 1] = clause
            end
        end
        local test = solve_formula(variables, candidate, 1)
        decisions, conflicts = decisions + test.stats.decisions, conflicts + test.stats.conflicts
        if test.status == "UNSAT" then
            remaining[remove] = false
        end
    end
    local core = {}
    for number = 1, #clauses do
        if remaining[number] then
            core[#core + 1] = number
        end
    end
    return {clauses = core, decisions = decisions, conflicts = conflicts}
end
local function execute(job, graphs)
    job.error = validate(job, graphs)
    if job.error then
        return
    end
    local args, command = job.args, job.command
    if command == "CHROMATIC" then
        job.graph, job.attempts, job.aggregate_stats = graphs[args[1]], {}, new_stats()
        job.aggregate_rounds, job.aggregate_removed = 0, 0
        for colors = 1, tonumber(args[2]) do
            local variables, clauses = encoders.coloring(job.graph.vertices, job.graph.edges, colors)
            local solution = solve_formula(variables, clauses, 1)
            solution.colors = colors
            job.attempts[#job.attempts + 1] = solution
            accumulate(job.aggregate_stats, solution.stats)
            job.aggregate_rounds = job.aggregate_rounds + solution.rounds
            job.aggregate_removed = job.aggregate_removed + solution.removed
            job.solution, job.colors = solution, colors
            if solution.status == "SAT" then
                job.chromatic = colors
                break
            end
        end
    else
        local variables, clauses, limit
        if command == "SOLVE" or command == "ENUM" or command == "CORE" then
            variables, clauses, job.error = cnf.read(args[1])
            if job.error then
                return
            end
            limit = command == "ENUM" and tonumber(args[2]) or 1
        elseif command == "QUEENS" then
            variables, clauses = encoders.queens(tonumber(args[1]))
            limit = tonumber(args[2])
        elseif command == "PIGEON" then
            variables, clauses = encoders.pigeon(tonumber(args[1]), tonumber(args[2]))
            limit = tonumber(args[3])
        else
            job.graph, job.colors = graphs[args[1]], tonumber(args[2])
            variables, clauses = encoders.coloring(job.graph.vertices, job.graph.edges, job.colors)
            limit = tonumber(args[3])
        end
        job.solution = solve_formula(variables, clauses, limit)
        job.aggregate_stats, job.aggregate_rounds, job.aggregate_removed = job.solution.stats, job.solution.rounds, job.solution.removed
        if command == "CORE" and job.solution.status == "UNSAT" then
            job.core = unsat_core(variables, clauses)
        end
    end
    job.analysis = analyze(job.solution)
end
local function heading(job)
    return "JOB " .. job.number .. " " .. job.text
end
local function formula_summary(variables, clauses)
    local lengths, literals = {}, 0
    for i, clause in ipairs(clauses) do
        lengths[i], literals = #clause, literals + #clause
    end
    return "variables=" .. variables .. " clauses=" .. #clauses .. " literals=" .. literals .. " lengths=" .. report.frequency(lengths)
end
local function graph_summary(graph)
    local _, used, maximum_degree = greedy_coloring(graph)
    return "graph vertices=" .. graph.vertices .. " edges=" .. #graph.edges .. " max_degree=" .. maximum_degree .. " greedy=" .. used
end
local function preprocessing_report(preparation)
    local c, r = preparation.counts, preparation.records
    local lines = {"preprocess " .. report.named({{"pure", preparation.pure and "on" or "off"}, {"tautologies", c.tautologies},
        {"duplicate_literals", c.duplicate_literals}, {"unit_fixed", c.unit_fixed}, {"unit_removed", c.unit_removed}, {"subsumed", c.subsumed},
        {"pure_fixed", c.pure_fixed}, {"pure_removed", c.pure_removed}, {"removed", c.removed}}),
        "removed_clauses " .. report.named({{"tautology", report.number_list(r.tautology)}, {"unit", report.number_list(r.unit)}, {"subsumed", report.number_list(r.subsumed)}, {"pure", report.number_list(r.pure)}})}
    if preparation.empty_clause then
        lines[#lines + 1] = "simplified empty_clause=" .. preparation.empty_clause
    else
        local lengths, total, fixed = {}, 0, {}
        for i, clause in ipairs(preparation.clauses) do
            lengths[i], total = #clause, total + #clause
        end
        for variable, value in pairs(preparation.fixed) do
            fixed[#fixed + 1] = value and variable or -variable
        end
        table.sort(fixed, function(a, b) return math.abs(a) < math.abs(b) end)
        lines[#lines + 1] = "simplified clauses=" .. #lengths .. " literals=" .. total .. " lengths=" .. report.frequency(lengths) .. " fixed=" .. #fixed .. " active=" .. #preparation.active
        lines[#lines + 1] = "fixed literals=" .. report.number_list(fixed)
    end
    return lines
end
local function search_report(stats)
    return "search " .. report.named({{"decisions", stats.decisions}, {"propagations", stats.propagations}, {"conflicts", stats.conflicts}, {"max_depth", stats.max_depth}})
end
local function verification_report(solution, analysis)
    if analysis.failure then
        return "verify failed model=" .. analysis.failure[1] .. " clause=" .. analysis.failure[2]
    end
    return "verify ok models=" .. #solution.models .. " clauses=" .. #solution.clauses .. " true_literals=" .. report.frequency(analysis.distribution)
end
local function analysis_report(solution, analysis)
    if not analysis then
        return {}
    end
    local lines = {verification_report(solution, analysis), "flips safe=" .. #analysis.safe .. " variables=" .. report.number_list(analysis.safe)}
    if #analysis.diversity > 0 then
        local low, high = analysis.diversity[1], analysis.diversity[1]
        for _, distance in ipairs(analysis.diversity) do
            low, high = math.min(low, distance), math.max(high, distance)
        end
        lines[#lines + 1] = "diversity pairs=" .. #analysis.diversity .. " min_distance=" .. low .. " max_distance=" .. high
    end
    if solution.stop == "all" then
        lines[#lines + 1] = "backbone size=" .. #analysis.backbone .. " literals=" .. report.number_list(analysis.backbone)
    end
    return lines
end
local function result_paragraph(job)
    local lines = {heading(job)}
    if job.error then
        lines[2] = "error " .. job.error
        return lines
    end
    local solution = job.solution
    if job.command == "CHROMATIC" then
        lines[#lines + 1] = graph_summary(job.graph)
        for _, attempt in ipairs(job.attempts) do
            local s = attempt.stats
            lines[#lines + 1] = "attempt " .. report.named({{"k", attempt.colors}, {"clauses", #attempt.clauses}, {"removed", attempt.removed}, {"result", attempt.status}, {"stop", attempt.stop},
                {"decisions", s.decisions}, {"propagations", s.propagations}, {"conflicts", s.conflicts}, {"max_depth", s.max_depth}})
        end
        lines[#lines + 1] = "result " .. solution.status .. " chromatic=" .. (job.chromatic or "-") .. " attempts=" .. #job.attempts
        lines[#lines + 1] = search_report(job.aggregate_stats)
        if job.analysis then
            lines[#lines + 1] = verification_report(solution, job.analysis)
            lines[#lines + 1] = "flips safe=" .. #job.analysis.safe .. " variables=" .. report.number_list(job.analysis.safe)
        end
    else
        if job.command == "COLOR" then
            lines[#lines + 1] = graph_summary(job.graph)
        end
        lines[#lines + 1] = "formula " .. formula_summary(solution.variables, solution.clauses)
        append(lines, preprocessing_report(solution.preparation))
        lines[#lines + 1] = "result " .. solution.status .. " models=" .. #solution.models .. " rounds=" .. solution.rounds .. " stop=" .. solution.stop
        lines[#lines + 1] = search_report(solution.stats)
        if solution.rounds > 0 then
            local initial = {}
            for i = 1, math.min(12, #solution.trace) do
                initial[#initial + 1] = solution.trace[i]
            end
            local text = #initial > 0 and table.concat(initial, " ") or "-"
            if #solution.trace > 12 then
                text = text .. " +" .. (#solution.trace - 12)
            end
            lines[#lines + 1] = "trace " .. text
        end
        append(lines, analysis_report(solution, job.analysis))
        if job.core then
            lines[#lines + 1] = "core size=" .. #job.core.clauses .. " decisions=" .. job.core.decisions .. " conflicts=" .. job.core.conflicts .. " clauses=" .. report.number_list(job.core.clauses)
        end
    end
    return lines
end
local function sequence_less(a, b)
    for i = 1, #a do
        if a[i] ~= b[i] then
            return a[i] < b[i]
        end
    end
    return false
end
local function canonical_queens(columns)
    local n, variants, distinct = #columns, {}, {}
    for transform = 1, 8 do
        local current = {}
        for row, column in ipairs(columns) do
            local r, c
            if transform == 1 then
                r, c = row, column
            elseif transform == 2 then
                r, c = column, n + 1 - row
            elseif transform == 3 then
                r, c = n + 1 - row, n + 1 - column
            elseif transform == 4 then
                r, c = n + 1 - column, row
            elseif transform == 5 then
                r, c = row, n + 1 - column
            elseif transform == 6 then
                r, c = n + 1 - row, column
            elseif transform == 7 then
                r, c = column, row
            else
                r, c = n + 1 - column, n + 1 - row
            end
            current[r] = c
        end
        variants[#variants + 1] = current
        distinct[report.number_list(current)] = true
    end
    table.sort(variants, sequence_less)
    local orbit = 0
    for _ in pairs(distinct) do
        orbit = orbit + 1
    end
    return variants[1], orbit
end
local function canonical_colors(colors)
    local numbers, result, count = {}, {}, 0
    for i, color in ipairs(colors) do
        if not numbers[color] then
            count = count + 1
            numbers[color] = count
        end
        result[i] = numbers[color]
    end
    return result, count
end
local function boards(job)
    local command, args, solution = job.command, job.args, job.solution
    if command == "PIGEON" then
        local p, h = tonumber(args[1]), tonumber(args[2])
        local lines = {"PIGEON job=" .. job.number .. " pigeons=" .. p .. " holes=" .. h}
        for index, model in ipairs(solution.models) do
            local places, occupied, empty = encoders.positions(model, p, h), {}, {}
            for _, hole in ipairs(places) do
                occupied[hole] = true
            end
            for hole = 1, h do
                if not occupied[hole] then
                    empty[#empty + 1] = hole
                end
            end
            lines[#lines + 1] = "assignment " .. index .. " holes=" .. report.number_list(places) .. " empty=" .. report.number_list(empty)
        end
        local expected = p <= h and 1 or 0
        if p <= h then
            for value = h, h - p + 1, -1 do
                expected = expected * value
            end
        end
        lines[#lines + 1] = "summary assignments=" .. #solution.models .. " stop=" .. solution.stop .. " expected=" .. expected
        return lines
    end
    local queens = command == "QUEENS"
    local rows = queens and tonumber(args[1]) or job.graph.vertices
    local width = queens and rows or job.colors
    local lines
    if queens then
        lines = {"QUEENS job=" .. job.number .. " n=" .. rows}
    else
        lines = {command .. " job=" .. job.number .. " graph=" .. job.graph.name .. " vertices=" .. rows .. " edges=" .. #job.graph.edges .. " colors=" .. width}
        local greedy, used = greedy_coloring(job.graph)
        lines[#lines + 1] = "greedy used=" .. used .. " colors=" .. report.number_list(greedy)
    end
    local groups, by_key = {}, {}
    for index, model in ipairs(solution.models) do
        local places = encoders.positions(model, rows, width)
        local canonical, orbit
        if queens then
            canonical, orbit = canonical_queens(places)
        else
            canonical, orbit = canonical_colors(places)
        end
        local key = report.number_list(canonical)
        local group = by_key[key]
        local first = group == nil
        if first then
            group = {number = #groups + 1, first = index, found = 0, canonical = canonical, orbit = orbit}
            groups[#groups + 1], by_key[key] = group, group
        end
        group.found = group.found + 1
        if queens then
            lines[#lines + 1] = "solution " .. index .. " columns=" .. report.number_list(places) .. " class=" .. group.number
            if first then
                append(lines, report.queens_board(places))
            end
        else
            local sizes = {}
            for color = 1, width do
                sizes[color] = 0
            end
            for _, color in ipairs(places) do
                sizes[color] = sizes[color] + 1
            end
            lines[#lines + 1] = "coloring " .. index .. " colors=" .. report.number_list(places) .. " used=" .. orbit .. " sizes=" .. report.number_list(sizes) .. " class=" .. group.number
        end
    end
    for _, group in ipairs(groups) do
        local line = "class " .. group.number
        if queens then
            line = line .. " orbit=" .. group.orbit
        end
        lines[#lines + 1] = line .. " found=" .. group.found .. " first=" .. group.first .. " canonical=" .. report.number_list(group.canonical)
    end
    lines[#lines + 1] = "summary " .. (queens and "solutions=" or "colorings=") .. #solution.models .. " stop=" .. solution.stop .. " classes=" .. #groups
    return lines
end
local function summary(jobs, valid)
    local sat, totals = 0, {models = 0, rounds = 0, decisions = 0, propagations = 0, conflicts = 0, removed = 0}
    for _, job in ipairs(valid) do
        if job.solution.status == "SAT" then
            sat = sat + 1
        end
        totals.models = totals.models + #job.solution.models
        totals.rounds = totals.rounds + job.aggregate_rounds
        totals.decisions = totals.decisions + job.aggregate_stats.decisions
        totals.propagations = totals.propagations + job.aggregate_stats.propagations
        totals.conflicts = totals.conflicts + job.aggregate_stats.conflicts
        totals.removed = totals.removed + job.aggregate_removed
    end
    local lines = {"SUMMARY jobs=" .. #jobs .. " sat=" .. sat .. " unsat=" .. (#valid - sat) .. " error=" .. (#jobs - #valid),
        "totals " .. report.named({{"models", totals.models}, {"rounds", totals.rounds}, {"decisions", totals.decisions}, {"propagations", totals.propagations}, {"conflicts", totals.conflicts}, {"removed_clauses", totals.removed}})}
    for _, command in ipairs(commands) do
        local count, yes, no, decisions, propagations, conflicts = 0, 0, 0, 0, 0, 0
        for _, job in ipairs(valid) do
            if job.command == command then
                count = count + 1
                if job.solution.status == "SAT" then
                    yes = yes + 1
                else
                    no = no + 1
                end
                decisions, propagations, conflicts = decisions + job.aggregate_stats.decisions, propagations + job.aggregate_stats.propagations, conflicts + job.aggregate_stats.conflicts
            end
        end
        if count > 0 then
            lines[#lines + 1] = "command " .. command .. " " .. report.named({{"jobs", count}, {"sat", yes}, {"unsat", no}, {"decisions", decisions}, {"propagations", propagations}, {"conflicts", conflicts}})
        end
    end
    if #valid > 0 then
        for _, field in ipairs({{"hardest", "conflicts"}, {"deepest", "max_depth"}, {"busiest", "propagations"}}) do
            local best = valid[1]
            for _, job in ipairs(valid) do
                if job.aggregate_stats[field[2]] > best.aggregate_stats[field[2]] then
                    best = job
                end
            end
            lines[#lines + 1] = field[1] .. " job=" .. best.number .. " " .. field[2] .. "=" .. best.aggregate_stats[field[2]]
        end
    end
    return lines
end
local graphs, jobs = load_graphs(), load_jobs()
local valid, results, models_output, boards_output = {}, {}, {}, {}
local stats_output = {"job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"}
for _, job in ipairs(jobs) do
    execute(job, graphs)
    results[#results + 1] = result_paragraph(job)
    if not job.error then
        valid[#valid + 1] = job
        local solution, stats = job.solution, job.aggregate_stats
        if #solution.models > 0 then
            local lines = {heading(job)}
            for index, model in ipairs(solution.models) do
                lines[#lines + 1] = "model " .. index
                append(lines, cnf.model_lines(model))
            end
            models_output[#models_output + 1] = lines
        end
        if job.command == "QUEENS" or job.command == "PIGEON" or job.command == "COLOR" or job.command == "CHROMATIC" then
            boards_output[#boards_output + 1] = boards(job)
        end
        local record = {job.number, job.command, solution.status, solution.variables, #solution.clauses, job.aggregate_removed,
            stats.decisions, stats.propagations, stats.conflicts, stats.max_depth, #solution.models, job.aggregate_rounds}
        for i, value in ipairs(record) do
            record[i] = tostring(value)
        end
        stats_output[#stats_output + 1] = table.concat(record, ",")
    end
end
results[#results + 1] = summary(jobs, valid)
os.execute('mkdir -p output')
report.save_paragraphs("results.txt", results)
report.save_paragraphs("models.txt", models_output)
report.save_paragraphs("boards.txt", boards_output)
report.save_lines("stats.csv", stats_output)
