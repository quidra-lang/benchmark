local instance_io, Minstd, dispatch, genetic, gantt = require("instance"), require("minstd"), require("dispatch_rules"), require("genetic"), require("gantt")
local rules = {"SPT", "LPT", "MWKR", "FIFO"}
local function copy(values)
    return {table.unpack(values)}
end
local function zeros(n)
    local values = {}
    for i = 1, n do
        values[i] = 0
    end
    return values
end
local function sum(values)
    local total = 0
    for _, value in ipairs(values) do
        total = total + value
    end
    return total
end
local function append(destination, source)
    for _, value in ipairs(source) do
        destination[#destination + 1] = value
    end
end
local function percentage(part, whole)
    local tenths = (2000 * part + whole) // (2 * whole)
    return tenths // 10 .. "." .. tenths % 10 .. "%"
end
local function letter(job)
    return string.char(64 + job)
end
local function order_copy(order)
    local result = {}
    for i, sequence in ipairs(order) do
        result[i] = copy(sequence)
    end
    return result
end
local function params()
    local result = {}
    for line in io.lines("input/ga_params.txt") do
        local name, rest = line:match("^(%S+) (.+)$")
        local values = {}
        for value in rest:gmatch("%S+") do
            values[#values + 1] = tonumber(value) or value
        end
        result[name] = values
    end
    for _, key in ipairs({"crossover", "swap_mutation", "insert_mutation"}) do
        local numerator, denominator = result[key][1]:match("^(%d+)/(%d+)$")
        result[key] = {tonumber(numerator), tonumber(denominator)}
    end
    for _, key in ipairs({"seed", "population", "generations", "tournament", "elitism", "tabu_iterations", "tabu_tenure", "gantt_width"}) do
        result[key] = result[key][1]
    end
    return result
end
local function makespan(starts, durations)
    local value = 0
    for i, start in ipairs(starts) do
        value = math.max(value, start + durations[i])
    end
    return value
end
local function jackson(instance, machine)
    local remaining, time, bound, left = {}, 0, 0, #machine.operations
    for i, ident in ipairs(machine.operations) do
        remaining[i] = instance.operations[ident].duration
    end
    while left > 0 do
        local release = 2147483647
        for i, ident in ipairs(machine.operations) do
            if remaining[i] > 0 then
                release = math.min(release, instance.operations[ident].head)
            end
        end
        time = math.max(time, release)
        local chosen
        for i, ident in ipairs(machine.operations) do
            local operation = instance.operations[ident]
            if remaining[i] > 0 and operation.head <= time then
                local old = chosen and instance.operations[machine.operations[chosen]]
                if not old or operation.tail > old.tail or operation.tail == old.tail and operation.job < old.job then
                    chosen = i
                end
            end
        end
        local step = remaining[chosen]
        for _, ident in ipairs(machine.operations) do
            local head = instance.operations[ident].head
            if head > time then
                step = math.min(step, head - time)
            end
        end
        time, remaining[chosen] = time + step, remaining[chosen] - step
        if remaining[chosen] == 0 then
            left, bound = left - 1, math.max(bound, time + instance.operations[machine.operations[chosen]].tail)
        end
    end
    return bound
end
local function order_starts(instance, order, durations)
    local starts, completions, positions, placed = {}, zeros(#instance.operations), {}, 0
    for m = 1, instance.machine_count do
        positions[m] = 1
    end
    while placed < #instance.operations do
        for m, sequence in ipairs(order) do
            while positions[m] <= #sequence do
                local position, ident = positions[m], sequence[positions[m]]
                local previous = instance.operations[ident].job_prev
                if previous and starts[previous] == nil then
                    break
                end
                local ready = previous and completions[previous] or 0
                local free = position > 1 and completions[sequence[position - 1]] or 0
                starts[ident] = math.max(ready, free)
                completions[ident] = starts[ident] + durations[ident]
                positions[m], placed = position + 1, placed + 1
            end
        end
    end
    return starts
end
local Schedule = {}
Schedule.__index = Schedule
function Schedule.new(instance, starts)
    local self = setmetatable({instance = instance, starts = starts, durations = instance.durations, completions = {}, makespan = makespan(starts, instance.durations), order = {}, machine_prev = {}, machine_next = {}}, Schedule)
    for i, start in ipairs(starts) do
        self.completions[i] = start + instance.durations[i]
    end
    for m = 1, instance.machine_count do
        self.order[m] = {}
    end
    for _, ident in ipairs(self:by_start()) do
        local sequence = self.order[instance.operations[ident].machine]
        local previous = sequence[#sequence]
        if previous then
            self.machine_prev[ident], self.machine_next[previous] = previous, ident
        end
        sequence[#sequence + 1] = ident
    end
    return self
end
function Schedule:by_start()
    local order = {}
    for i = 1, #self.starts do
        order[i] = i
    end
    table.sort(order, function(a, b)
        return self.starts[a] < self.starts[b] or self.starts[a] == self.starts[b] and a < b
    end)
    return order
end
function Schedule:chromosome()
    local values = {}
    for i, ident in ipairs(self:by_start()) do
        values[i] = self.instance.operations[ident].job
    end
    return values
end
function Schedule:path()
    local current
    for i, completion in ipairs(self.completions) do
        if completion == self.makespan then
            current = i
            break
        end
    end
    local reverse, path = {}, {}
    while true do
        reverse[#reverse + 1] = current
        if self.starts[current] == 0 then
            break
        end
        local previous = self.machine_prev[current]
        if previous and self.completions[previous] == self.starts[current] then
            current = previous
        else
            current = self.instance.operations[current].job_prev
        end
    end
    for i = #reverse, 1, -1 do
        path[#path + 1] = reverse[i]
    end
    return path
end
function Schedule:blocks(path)
    local blocks = {}
    for _, ident in ipairs(path) do
        local last = blocks[#blocks]
        if last and self.instance.operations[last[#last]].machine == self.instance.operations[ident].machine then
            last[#last + 1] = ident
        else
            blocks[#blocks + 1] = {ident}
        end
    end
    return blocks
end
function Schedule:moves()
    local moves = {}
    for _, block in ipairs(self:blocks(self:path())) do
        for i = 1, #block - 1 do
            moves[#moves + 1] = {block[i], block[i + 1]}
        end
    end
    return moves
end
function Schedule:path_count()
    local ways = zeros(#self.starts)
    for _, ident in ipairs(self:by_start()) do
        if self.starts[ident] == 0 then
            ways[ident] = 1
        else
            local job_previous, machine_previous = self.instance.operations[ident].job_prev, self.machine_prev[ident]
            if job_previous and self.completions[job_previous] == self.starts[ident] then
                ways[ident] = ways[ident] + ways[job_previous]
            end
            if machine_previous and self.completions[machine_previous] == self.starts[ident] then
                ways[ident] = ways[ident] + ways[machine_previous]
            end
        end
    end
    local count = 0
    for i, completion in ipairs(self.completions) do
        if completion == self.makespan then
            count = count + ways[i]
        end
    end
    return count
end
function Schedule:left_shift(ident)
    local operation = self.instance.operations[ident]
    local sequence, position = self.order[operation.machine]
    for i, candidate in ipairs(sequence) do
        if candidate == ident then
            position = i
            break
        end
    end
    if position == 1 then
        return
    end
    local ready = operation.job_prev and self.completions[operation.job_prev] or 0
    for insertion = 1, position - 1 do
        local begin = insertion == 1 and 0 or self.completions[sequence[insertion - 1]]
        local start = math.max(begin, ready)
        if start + operation.duration <= self.starts[sequence[insertion]] then
            return start, insertion
        end
    end
end
function Schedule:shiftable()
    local count = 0
    for i = 1, #self.starts do
        if self:left_shift(i) ~= nil then
            count = count + 1
        end
    end
    return count
end
function Schedule:slacks()
    local latest, slack, free = {}, {}, {}
    local order = self:by_start()
    for p = #order, 1, -1 do
        local ident = order[p]
        local job_next, machine_next = self.instance.operations[ident].job_next, self.machine_next[ident]
        local latest_limit, start_limit = self.makespan, self.makespan
        if job_next then
            latest_limit, start_limit = math.min(latest_limit, latest[job_next]), math.min(start_limit, self.starts[job_next])
        end
        if machine_next then
            latest_limit, start_limit = math.min(latest_limit, latest[machine_next]), math.min(start_limit, self.starts[machine_next])
        end
        latest[ident] = latest_limit - self.durations[ident]
        slack[ident], free[ident] = latest[ident] - self.starts[ident], start_limit - self.completions[ident]
    end
    return slack, free
end
function Schedule:path_counts(path)
    local counts = zeros(self.instance.machine_count)
    for _, ident in ipairs(path) do
        local m = self.instance.operations[ident].machine
        counts[m] = counts[m] + 1
    end
    return counts
end
function Schedule:bottleneck(path)
    local counts, best = self:path_counts(path), 1
    for m = 2, #counts do
        if counts[m] > counts[best] then
            best = m
        end
    end
    return best, counts[best]
end
function Schedule:flow()
    local total = 0
    for _, job in ipairs(self.instance.jobs) do
        total = total + self.completions[job.operations[#job.operations]]
    end
    return total
end
function Schedule:idle()
    return self.makespan * self.instance.machine_count - sum(self.durations)
end
function Schedule:letters(machine)
    local parts = {}
    for i, ident in ipairs(self.order[machine]) do
        parts[i] = letter(self.instance.operations[ident].job)
    end
    return table.concat(parts)
end
local function schedule_order(instance, order)
    return Schedule.new(instance, order_starts(instance, order, instance.durations))
end
local function apply_move(instance, order, move)
    local result = order_copy(order)
    local sequence = result[instance.operations[move[1]].machine]
    for i = 1, #sequence - 1 do
        if sequence[i] == move[1] then
            sequence[i], sequence[i + 1] = move[2], move[1]
            break
        end
    end
    return result
end
local function distances(first, second)
    local result = {}
    for m, sequence in ipairs(first.order) do
        local rank, count = {}, 0
        for i, ident in ipairs(second.order[m]) do
            rank[ident] = i
        end
        for i = 1, #sequence do
            for j = i + 1, #sequence do
                if rank[sequence[i]] > rank[sequence[j]] then
                    count = count + 1
                end
            end
        end
        result[m] = count
    end
    return result
end
local function tabu(instance, order, parameters)
    local start = schedule_order(instance, order).makespan
    local result = {start = start, best_order = order_copy(order), best = start, found = 0, records = {}, reason = "limit"}
    local current, expiry = order_copy(order), {}
    for iteration = 1, parameters.tabu_iterations do
        local moves = schedule_order(instance, current):moves()
        if #moves == 0 then
            result.reason = "no_moves"
            return result
        end
        local values, blocked, tabu_count, chosen, best_order = {}, {}, 0, nil, nil
        for i, move in ipairs(moves) do
            local candidate = apply_move(instance, current, move)
            values[i] = schedule_order(instance, candidate).makespan
            blocked[i] = (expiry[move[1] .. ":" .. move[2]] or 0) >= iteration
            if blocked[i] then
                tabu_count = tabu_count + 1
            end
            if not blocked[i] or values[i] < result.best then
                if not chosen or values[i] < values[chosen] then
                    chosen, best_order = i, candidate
                end
            end
        end
        if not chosen then
            result.reason = "all_tabu"
            return result
        end
        local move = moves[chosen]
        current = best_order
        expiry[move[2] .. ":" .. move[1]] = iteration + parameters.tabu_tenure
        if values[chosen] < result.best then
            result.best_order, result.best, result.found = order_copy(current), values[chosen], iteration
        end
        result.records[#result.records + 1] = {iteration = iteration, moves = #moves, tabu = tabu_count, move = move, aspiration = blocked[chosen], value = values[chosen], best = result.best}
    end
    return result
end
local function activate(instance, order)
    local current, shifts = order_copy(order), {}
    while true do
        local schedule, selected, start, insertion = schedule_order(instance, current)
        for _, ident in ipairs(schedule:by_start()) do
            local new_start, position = schedule:left_shift(ident)
            if new_start then
                selected, start, insertion = ident, new_start, position
                break
            end
        end
        if not selected then
            return current, shifts
        end
        local sequence = current[instance.operations[selected].machine]
        for i, ident in ipairs(sequence) do
            if ident == selected then
                table.remove(sequence, i)
                break
            end
        end
        table.insert(sequence, insertion, selected)
        shifts[#shifts + 1] = {ident = selected, old = schedule.starts[selected], new = start}
    end
end
local function ranking(values)
    local indices = {}
    for i = 1, #values do
        indices[i] = i
    end
    table.sort(indices, function(a, b)
        return values[a] < values[b] or values[a] == values[b] and a < b
    end)
    return indices
end
local function gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end
local function run_ga(instance, parameters, baselines)
    local rng, jobs, basic, population = Minstd.new(parameters.seed), {}, {}, {}
    for _, job in ipairs(instance.jobs) do
        jobs[#jobs + 1] = job.number
        for _ = 1, #job.operations do
            basic[#basic + 1] = job.number
        end
    end
    for i, baseline in ipairs(baselines) do
        population[i] = baseline.schedule:chromosome()
    end
    while #population < parameters.population do
        local chromosome = copy(basic)
        rng:shuffle(chromosome)
        population[#population + 1] = chromosome
    end
    local result = {records = {}, progress = {"generation,best,mean,worst,distinct"}, crossovers = 0, swaps = 0, inserts = 0}
    local previous_best
    local function mutate(child)
        if rng:chance(parameters.swap_mutation) then
            result.swaps = result.swaps + 1
            genetic.swap_mutation(rng, child)
        end
        if rng:chance(parameters.insert_mutation) then
            result.inserts = result.inserts + 1
            genetic.insert_mutation(rng, child)
        end
    end
    for generation = 0, parameters.generations do
        local values = {}
        for i, chromosome in ipairs(population) do
            values[i] = makespan(genetic.decode(instance, chromosome), instance.durations)
        end
        local ranked = ranking(values)
        local best = ranked[1]
        if not previous_best or values[best] < previous_best then
            result.records[#result.records + 1] = {generation = generation, value = values[best], individual = best}
        end
        previous_best = values[best]
        local checkpoint = false
        for _, number in ipairs(parameters.checkpoints) do
            if number == generation then
                checkpoint = true
            end
        end
        if checkpoint then
            local seen, distinct = {}, 0
            for _, chromosome in ipairs(population) do
                local key = table.concat(chromosome, ",")
                if not seen[key] then
                    seen[key], distinct = true, distinct + 1
                end
            end
            local total, divisor = sum(values), gcd(sum(values), #values)
            result.progress[#result.progress + 1] = string.format("%d,%d,%d/%d,%d,%d", generation, values[best], total // divisor, #values // divisor, values[ranked[#ranked]], distinct)
        end
        result.population, result.values, result.ranked = population, values, ranked
        if generation == parameters.generations then
            break
        end
        local offspring = {}
        for i = 1, parameters.elitism do
            offspring[i] = copy(population[ranked[i]])
        end
        for _ = 1, (parameters.population - parameters.elitism) // 2 do
            local first = population[genetic.tournament(rng, values, parameters.tournament)]
            local second = population[genetic.tournament(rng, values, parameters.tournament)]
            local child1, child2
            if rng:chance(parameters.crossover) then
                result.crossovers = result.crossovers + 1
                child1, child2 = genetic.crossover(rng, first, second, jobs)
            else
                child1, child2 = copy(first), copy(second)
            end
            mutate(child1)
            mutate(child2)
            offspring[#offspring + 1], offspring[#offspring + 2] = child1, child2
        end
        population = offspring
    end
    return result
end
local instance, parameters = instance_io.load_instance("input/instance.txt"), params()
local baselines, jacksons, seeds = {}, {}, {}
local job_bound, machine_bound, jackson_machine = instance.jobs[1], instance.machines[1], 1
for _, job in ipairs(instance.jobs) do
    if job.work > job_bound.work then
        job_bound = job
    end
end
for m, machine in ipairs(instance.machines) do
    jacksons[m] = jackson(instance, machine)
    if machine.bound > machine_bound.bound then
        machine_bound = machine
    end
    if jacksons[m] > jacksons[jackson_machine] then
        jackson_machine = m
    end
end
local lower = math.max(job_bound.work, machine_bound.bound, jacksons[jackson_machine])
for i, rule in ipairs(rules) do
    local starts, decisions, ties = dispatch.giffler_thompson(instance, rule)
    local schedule = Schedule.new(instance, starts)
    baselines[i] = {rule = rule, schedule = schedule, decisions = decisions, ties = ties, search = tabu(instance, schedule.order, parameters)}
end
local ga = run_ga(instance, parameters, baselines)
local best_chromosome = ga.population[ga.ranked[1]]
local ga_schedule = Schedule.new(instance, genetic.decode(instance, best_chromosome))
local gene_positions = {}
for position, ident in ipairs(genetic.gene_operations(instance, best_chromosome)) do
    gene_positions[ident] = position
end
local active_starts, active_decisions = dispatch.giffler_thompson(instance, "GENES", gene_positions)
local activated, shifts = activate(instance, ga_schedule.order)
local activated_value = schedule_order(instance, activated).makespan
local search = tabu(instance, activated, parameters)
local final = schedule_order(instance, search.best_order)
local path, blocks, slack, free = final:path(), nil, final:slacks()
blocks = final:blocks(path)
local baseline_lines = {string.format("INSTANCE jobs %d machines %d operations %d work %d errors %d", #instance.jobs, instance.machine_count, #instance.operations, sum(instance.durations), #instance.errors)}
for _, error in ipairs(instance.errors) do
    baseline_lines[#baseline_lines + 1] = "ERROR " .. error
end
for _, job in ipairs(instance.jobs) do
    local route = {}
    for i, ident in ipairs(job.operations) do
        route[i] = "M" .. instance.operations[ident].machine
    end
    baseline_lines[#baseline_lines + 1] = string.format("JOB J%d operations %d work %d route %s", job.number, #job.operations, job.work, table.concat(route, " "))
end
for m, machine in ipairs(instance.machines) do
    baseline_lines[#baseline_lines + 1] = string.format("MACHINE M%d operations %d load %d head %d tail %d bound %d jackson %d", m, #machine.operations, machine.load, machine.head, machine.tail, machine.bound, jacksons[m])
end
append(baseline_lines, {"BOUND job " .. job_bound.work .. " J" .. job_bound.number, "BOUND machine " .. machine_bound.bound .. " M" .. machine_bound.number, "BOUND jackson " .. jacksons[jackson_machine] .. " M" .. jackson_machine, "BOUND lower " .. lower})
local best_baseline = 1
for i, baseline in ipairs(baselines) do
    local schedule, previous = baseline.schedule, baseline.search
    local baseline_path = schedule:path()
    local bottleneck = schedule:bottleneck(baseline_path)
    baseline_lines[#baseline_lines + 1] = string.format("RULE %s makespan %d gap %s flow %d idle %d decisions %d ties %d", baseline.rule, schedule.makespan, percentage(schedule.makespan - lower, lower), schedule:flow(), schedule:idle(), baseline.decisions, baseline.ties)
    baseline_lines[#baseline_lines + 1] = string.format("PATH %s operations %d blocks %d critical_paths %d bottleneck M%d", baseline.rule, #baseline_path, #schedule:blocks(baseline_path), schedule:path_count(), bottleneck)
    baseline_lines[#baseline_lines + 1] = string.format("TABU %s makespan %d -> %d found %d iterations %d stop %s", baseline.rule, schedule.makespan, previous.best, previous.found, #previous.records, previous.reason)
    if schedule.makespan < baselines[best_baseline].schedule.makespan then
        best_baseline = i
    end
end
baseline_lines[#baseline_lines + 1] = "BEST " .. rules[best_baseline] .. " makespan " .. baselines[best_baseline].schedule.makespan
for m, machine in ipairs(instance.machines) do
    local parts = {"UTILIZATION M" .. m}
    for i, baseline in ipairs(baselines) do
        parts[#parts + 1] = rules[i] .. " " .. percentage(machine.load, baseline.schedule.makespan)
    end
    baseline_lines[#baseline_lines + 1] = table.concat(parts, " ")
end
local schedule_lines = {string.format("GA best %d generation %d crossovers %d swaps %d inserts %d", ga_schedule.makespan, ga.records[#ga.records].generation, ga.crossovers, ga.swaps, ga.inserts)}
for _, record in ipairs(ga.records) do
    schedule_lines[#schedule_lines + 1] = string.format("RECORD generation %d makespan %d individual %d", record.generation, record.value, record.individual)
end
local seen, top = {}, 0
for _, index in ipairs(ga.ranked) do
    local chromosome = ga.population[index]
    local key = table.concat(chromosome, ",")
    if not seen[key] then
        top, seen[key] = top + 1, true
        local other = Schedule.new(instance, genetic.decode(instance, chromosome))
        schedule_lines[#schedule_lines + 1] = string.format("TOP %d individual %d makespan %d distance %d", top, index, ga.values[index], sum(distances(other, ga_schedule)))
        if top == 5 then
            break
        end
    end
end
schedule_lines[#schedule_lines + 1] = "GA_CHROMOSOME " .. table.concat(best_chromosome, " ")
schedule_lines[#schedule_lines + 1] = string.format("ACTIVE_DECODE makespan %d decisions %d", makespan(active_starts, instance.durations), active_decisions)
for i, shift in ipairs(shifts) do
    local operation = instance.operations[shift.ident]
    schedule_lines[#schedule_lines + 1] = string.format("SHIFT %d %s M%d start %d -> %d", i, operation.code, operation.machine, shift.old, shift.new)
end
schedule_lines[#schedule_lines + 1] = string.format("ACTIVATED makespan %d -> %d shifts %d", ga_schedule.makespan, activated_value, #shifts)
schedule_lines[#schedule_lines + 1] = string.format("SCHEDULE makespan %d lower_bound %d gap %s improvement %d shiftable %d", final.makespan, lower, percentage(final.makespan - lower, lower), ga_schedule.makespan - final.makespan, final:shiftable())
schedule_lines[#schedule_lines + 1] = "CHROMOSOME " .. table.concat(final:chromosome(), " ")
local legend = {}
for i, job in ipairs(instance.jobs) do
    legend[i] = letter(job.number) .. "=J" .. job.number
end
schedule_lines[#schedule_lines + 1] = "LEGEND " .. table.concat(legend, " ")
local scale, columns = gantt.chart_scale(final.makespan, parameters.gantt_width)
append(schedule_lines, {"GANTT scale " .. scale .. " columns " .. columns, gantt.time_row(scale, columns), gantt.rule_row(columns)})
local on_path, machine_intervals = {}, {}
for _, ident in ipairs(path) do
    on_path[ident] = true
end
for m = 1, instance.machine_count do
    machine_intervals[m] = {}
end
for ident, operation in ipairs(instance.operations) do
    local mark = letter(operation.job)
    if on_path[ident] then
        mark = mark:lower()
    end
    local intervals = machine_intervals[operation.machine]
    intervals[#intervals + 1] = {start = final.starts[ident], finish = final.completions[ident], mark = mark}
end
for m, intervals in ipairs(machine_intervals) do
    schedule_lines[#schedule_lines + 1] = gantt.chart_row("M" .. m, intervals, scale, columns)
end
schedule_lines[#schedule_lines + 1] = gantt.busy_row(machine_intervals, scale, columns)
for _, job in ipairs(instance.jobs) do
    local intervals = {}
    for i, ident in ipairs(job.operations) do
        intervals[i] = {start = final.starts[ident], finish = final.completions[ident], mark = tostring(instance.operations[ident].machine % 10)}
    end
    schedule_lines[#schedule_lines + 1] = gantt.chart_row("J" .. job.number, intervals, scale, columns)
end
for m = 1, instance.machine_count do
    local parts = {"ORDER M" .. m .. " FINAL " .. final:letters(m)}
    for i, baseline in ipairs(baselines) do
        parts[#parts + 1] = rules[i] .. " " .. baseline.schedule:letters(m)
    end
    schedule_lines[#schedule_lines + 1] = table.concat(parts, " ")
end
for m, machine in ipairs(instance.machines) do
    local sequence, intervals, gaps, longest, description = final.order[m], {}, 0, 0, {}
    local previous = 0
    for i, ident in ipairs(sequence) do
        local start, completion = final.starts[ident], final.completions[ident]
        if start > previous then
            intervals[#intervals + 1] = previous .. "-" .. start
            if i > 1 then
                gaps, longest = gaps + 1, math.max(longest, start - previous)
            end
        end
        description[#description + 1] = "J" .. instance.operations[ident].job .. ":" .. start .. "-" .. completion
        previous = completion
    end
    if previous < final.makespan then
        intervals[#intervals + 1] = previous .. "-" .. final.makespan
    end
    schedule_lines[#schedule_lines + 1] = string.format("MACHINE M%d load %d idle %d utilization %s gaps %d longest_gap %d sequence %s", m, machine.load, final.makespan - machine.load, percentage(machine.load, final.makespan), gaps, longest, table.concat(description, " "))
    schedule_lines[#schedule_lines + 1] = "IDLE M" .. m .. " " .. (#intervals > 0 and table.concat(intervals, " ") or "none")
end
local total_waiting = 0
for _, job in ipairs(instance.jobs) do
    local completion = final.completions[job.operations[#job.operations]]
    total_waiting = total_waiting + completion - job.work
    schedule_lines[#schedule_lines + 1] = string.format("JOB J%d operations %d work %d start %d completion %d waiting %d", job.number, #job.operations, job.work, final.starts[job.operations[1]], completion, completion - job.work)
end
schedule_lines[#schedule_lines + 1] = string.format("TOTAL flow %d waiting %d idle %d", final:flow(), total_waiting, final:idle())
local all_distances, labels, totals, total_pairs = {}, {"SPT", "LPT", "MWKR", "FIFO", "GA"}, zeros(5), 0
for i, baseline in ipairs(baselines) do
    all_distances[i] = distances(final, baseline.schedule)
end
all_distances[5] = distances(final, ga_schedule)
for m, machine in ipairs(instance.machines) do
    local pairs = #machine.operations * (#machine.operations - 1) // 2
    total_pairs = total_pairs + pairs
    local parts = {"DISTANCE M" .. m .. " pairs " .. pairs}
    for i, values in ipairs(all_distances) do
        parts[#parts + 1] = labels[i] .. " " .. values[m]
        totals[i] = totals[i] + values[m]
    end
    schedule_lines[#schedule_lines + 1] = table.concat(parts, " ")
end
local parts = {"DISTANCE total pairs " .. total_pairs}
for i, total in ipairs(totals) do
    parts[#parts + 1] = labels[i] .. " " .. total
end
schedule_lines[#schedule_lines + 1] = table.concat(parts, " ")
local critical_lines = {"SEARCH start " .. search.start .. " iterations " .. parameters.tabu_iterations .. " tenure " .. parameters.tabu_tenure}
for _, record in ipairs(search.records) do
    local first, second = instance.operations[record.move[1]], instance.operations[record.move[2]]
    critical_lines[#critical_lines + 1] = string.format("ITER %d moves %d tabu %d swap M%d %s %s %s makespan %d best %d", record.iteration, record.moves, record.tabu, first.machine, first.code, second.code, record.aspiration and "aspiration" or "free", record.value, record.best)
end
critical_lines[#critical_lines + 1] = string.format("STOP iterations %d reason %s best %d found %d", #search.records, search.reason, search.best, search.found)
critical_lines[#critical_lines + 1] = string.format("PATH operations %d blocks %d makespan %d critical_paths %d", #path, #blocks, final.makespan, final:path_count())
for i, ident in ipairs(path) do
    local operation = instance.operations[ident]
    local link = i == 1 and "start" or final.machine_prev[ident] == path[i - 1] and "machine" or "job"
    critical_lines[#critical_lines + 1] = string.format("NODE %d %s M%d %d-%d %s", i, operation.code, operation.machine, final.starts[ident], final.completions[ident], link)
end
for i, block in ipairs(blocks) do
    local names = {}
    for j, ident in ipairs(block) do
        names[j] = instance.operations[ident].code
    end
    critical_lines[#critical_lines + 1] = string.format("BLOCK %d M%d %d-%d %s", i, instance.operations[block[1]].machine, final.starts[block[1]], final.completions[block[#block]], table.concat(names, " "))
end
for i, move in ipairs(final:moves()) do
    local first, second = instance.operations[move[1]], instance.operations[move[2]]
    local value = schedule_order(instance, apply_move(instance, final.order, move)).makespan
    critical_lines[#critical_lines + 1] = string.format("NEIGHBOUR %d M%d %s %s makespan %d", i, first.machine, first.code, second.code, value)
end
local critical_count = 0
for _, value in ipairs(slack) do
    if value == 0 then
        critical_count = critical_count + 1
    end
end
critical_lines[#critical_lines + 1] = "CRITICAL operations " .. critical_count .. " total " .. #instance.operations
for _, kind in ipairs({"SLACK", "FREE"}) do
    local values = kind == "SLACK" and slack or free
    for _, job in ipairs(instance.jobs) do
        local items = {}
        for i, ident in ipairs(job.operations) do
            items[i] = values[ident]
        end
        critical_lines[#critical_lines + 1] = kind .. " J" .. job.number .. " " .. table.concat(items, " ")
    end
end
local path_counts = final:path_counts(path)
for m, machine in ipairs(instance.machines) do
    local count, durations = 0, copy(instance.durations)
    for _, ident in ipairs(machine.operations) do
        if slack[ident] == 0 then
            count = count + 1
        end
        durations[ident] = durations[ident] + (durations[ident] + 9) // 10
    end
    local sensitivity = makespan(order_starts(instance, final.order, durations), durations)
    critical_lines[#critical_lines + 1] = string.format("MACHINE M%d critical %d path %d sensitivity %d delta %d", m, count, path_counts[m], sensitivity, sensitivity - final.makespan)
end
local bottleneck, bottleneck_count = final:bottleneck(path)
critical_lines[#critical_lines + 1] = "BOTTLENECK M" .. bottleneck .. " path " .. bottleneck_count
os.execute("mkdir -p output")
local function write_lines(name, lines)
    local handle = assert(io.open("output/" .. name, "wb"))
    handle:write(table.concat(lines, "\n"), "\n")
    handle:close()
end
write_lines("baselines.txt", baseline_lines)
write_lines("ga_progress.csv", ga.progress)
write_lines("best_schedule.txt", schedule_lines)
write_lines("critical_path.txt", critical_lines)
