local environment = require("environment")
local dp = require("dynamic_programming")
local td = require("td_learning")
local mc = require("monte_carlo")
local report = require("report")
local methods = {"mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"}
local policy_names = {"value_iteration", "policy_iteration", "mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"}
local function line(...)
    return table.concat({...}, " ")
end
local function append(target, source)
    for _, value in ipairs(source) do
        target[#target + 1] = value
    end
end
local function total(values)
    local result = 0
    for _, value in ipairs(values) do
        result = result + value
    end
    return result
end
local function map(values, operation)
    local result = {}
    for i, value in ipairs(values) do
        result[i] = operation(value, i)
    end
    return result
end
local function zeros(count)
    local result = {}
    for i = 1, count do
        result[i] = 0
    end
    return result
end
local function matrix(count)
    local result = {}
    for i = 1, count do
        result[i] = {0, 0, 0, 0}
    end
    return result
end
local function pairs_of(values)
    local result = {}
    for i = 1, #values, 2 do
        result[#result + 1] = {values[i], values[i + 1]}
    end
    return result
end
local function read_settings()
    local rows, file = {}, assert(io.open("input/params.txt"))
    for text in file:lines() do
        local values = {}
        for value in text:gmatch("-?%d+") do
            values[#values + 1] = tonumber(value)
        end
        rows[#rows + 1] = values
    end
    file:close()
    return {gamma = rows[1][1], step_reward = rows[2][1], slip_total = rows[3][1], floor_slip = rows[3][2], ice_slip = rows[3][3], theta = rows[4][1], gamma_sweep = rows[5], slip_sweep = pairs_of(rows[6]), episodes = rows[7][1], step_limit = rows[8][1], block_size = rows[9][1], alpha = pairs_of(rows[10]), epsilon = pairs_of(rows[11]), planning_steps = rows[12][1], seed = rows[13][1], rollouts = rows[14][1], rollout_seed = rows[15][1]}
end
local function schedule_value(schedule, episode)
    local result = schedule[1][2]
    for _, entry in ipairs(schedule) do
        if entry[1] <= episode then
            result = entry[2]
        end
    end
    return result
end
local function agreements(first, second)
    local count = 0
    for i, value in ipairs(first) do
        if value == second[i] then
            count = count + 1
        end
    end
    return count
end
local function counts(endings)
    local result = {goal = 0, pit = 0, timeout = 0}
    for _, ending in ipairs(endings) do
        result[ending] = result[ending] + 1
    end
    return result
end
local function largest(values)
    local index = 1
    for i = 2, #values do
        if values[i] > values[index] then
            index = i
        end
    end
    return values[index], index
end
local world, settings = environment.read_world("input/world.txt"), read_settings()
local env = environment.new(world, settings.step_reward, settings.slip_total, settings.floor_slip, settings.ice_slip)
local n, start = #world.states, world.start_state
local optimal_values, changes = dp.value_iteration(env, settings.gamma, settings.theta)
local optimal_q = {}
for state = 1, n do
    optimal_q[state] = dp.actions(env, optimal_values, settings.gamma, state)
end
local optimal_policy = map(optimal_q, dp.first_max)
local optimal_actions = map(optimal_q, function(row)
    local result, best = {}, math.max(table.unpack(row))
    for action = 0, 3 do
        if row[action + 1] == best then
            result[#result + 1] = action
        end
    end
    return result
end)
local _, in_place_sweeps = dp.in_place(env, settings.gamma, settings.theta)
local iteration_policy, iteration_values, rounds = dp.policy_iteration(env, settings.gamma, settings.theta)
local function learn(method)
    local q, visits, generator = matrix(n), matrix(n), environment.generator(settings.seed)
    local model, averages = td.model(n), mc.new(n)
    local episodes, blocks = {}, {}
    for episode_number = 1, settings.episodes do
        local alpha = schedule_value(settings.alpha, episode_number)
        local epsilon = schedule_value(settings.epsilon, episode_number)
        local episode = {total = 0, steps = 0, ending = "timeout", cells = {world.start}}
        local state, history, action = start, {}, 0
        if method == "sarsa" then
            action = td.choose(generator, q[state], epsilon)
        end
        while episode.steps < settings.step_limit do
            if method ~= "sarsa" then
                action = td.choose(generator, q[state], epsilon)
            end
            local cell, reward = env:step(generator, state, action)
            local next_state = world.state_index[cell + 1]
            visits[state][action + 1] = visits[state][action + 1] + 1
            episode.total, episode.steps = episode.total + reward, episode.steps + 1
            episode.cells[#episode.cells + 1] = cell
            if method == "mc" then
                history[#history + 1] = {state = state, action = action, reward = reward}
            else
                local value, next_action = 0, action
                if next_state then
                    if method == "sarsa" then
                        next_action = td.choose(generator, q[next_state], epsilon)
                        value = q[next_state][next_action + 1]
                    elseif method == "expected_sarsa" then
                        value = td.expected(q[next_state], epsilon)
                    else
                        value = math.max(table.unpack(q[next_state]))
                    end
                end
                td.update(q[state], action, td.target(reward, not next_state, value, settings.gamma), alpha)
                if method == "sarsa" then
                    action = next_action
                end
                if method == "dyna_q" then
                    model:record(state, action, reward, next_state)
                    model:plan(generator, q, settings.gamma, alpha, settings.planning_steps)
                end
            end
            if not next_state then
                episode.ending = world:ending(cell)
                break
            end
            state = next_state
        end
        if method == "mc" then
            averages:update(q, history, settings.gamma)
        end
        episodes[#episodes + 1] = episode
        if episode_number % settings.block_size == 0 then
            local error_sum, coverage, agree = 0, 0, 0
            for state = 1, n do
                error_sum = error_sum + math.abs(math.max(table.unpack(q[state])) - optimal_values[state])
                if total(visits[state]) > 0 then
                    coverage = coverage + 1
                end
                if dp.first_max(q[state]) == optimal_policy[state] then
                    agree = agree + 1
                end
            end
            blocks[#blocks + 1] = {agree = agree, error = error_sum // n, coverage = coverage}
        end
    end
    return {method = method, q = q, visits = visits, episodes = episodes, blocks = blocks, policy = map(q, dp.first_max), state_visits = map(visits, total)}
end
local learners, policies = {}, {optimal_policy, iteration_policy}
for i, method in ipairs(methods) do
    learners[i] = learn(method)
    policies[#policies + 1] = learners[i].policy
end
local function nominal_path(current_env, policy, origin)
    local cells, seen = {origin}, {[origin] = true}
    while true do
        local state = world.state_index[cells[#cells] + 1]
        local target = current_env.moves[state][policy[state] + 1]
        local repeated = seen[target]
        cells[#cells + 1], seen[target] = target, true
        if world:terminal(target) then
            return world:ending(target), cells
        end
        if repeated then
            return "loop", cells
        end
        if #cells - 1 == settings.step_limit then
            return "limit", cells
        end
    end
end
local function distances()
    local values, frontier, level = {[world.start + 1] = 0}, {world.start}, 0
    while #frontier > 0 do
        local following = {}
        level = level + 1
        for _, cell in ipairs(frontier) do
            for _, transitions in ipairs(env.transitions[world.state_index[cell + 1]]) do
                for _, entry in ipairs(transitions) do
                    if values[entry.cell + 1] == nil then
                        values[entry.cell + 1] = level
                        if not world:terminal(entry.cell) then
                            following[#following + 1] = entry.cell
                        end
                    end
                end
            end
        end
        frontier = following
    end
    return values
end
local function absorption(policy)
    local goal, pit, expected = zeros(n), zeros(n), zeros(n)
    for _ = 1, settings.step_limit do
        local next_goal, next_pit, next_expected = {}, {}, {}
        for state, action in ipairs(policy) do
            local g, p, e = 0, 0, 0
            for _, entry in ipairs(env.transitions[state][action + 1]) do
                local next_state = world.state_index[entry.cell + 1]
                if next_state then
                    g, p, e = g + entry.numerator * goal[next_state], p + entry.numerator * pit[next_state], e + entry.numerator * expected[next_state]
                elseif world:ending(entry.cell) == "goal" then
                    g = g + entry.numerator * 100000000
                else
                    p = p + entry.numerator * 100000000
                end
            end
            next_goal[state], next_pit[state], next_expected[state] = g // settings.slip_total, p // settings.slip_total, 100000000 + e // settings.slip_total
        end
        goal, pit, expected = next_goal, next_pit, next_expected
    end
    return {goal[start], pit[start], 100000000 - goal[start] - pit[start], expected[start]}
end
local function behaviour(policy, epsilon)
    local values, sweeps = zeros(n), 0
    while true do
        local delta = 0
        sweeps = sweeps + 1
        for state, chosen in ipairs(policy) do
            local sum = 0
            local backups = dp.actions(env, values, settings.gamma, state)
            for action = 0, 3 do
                local weight = epsilon + (action == chosen and 4 * (1000 - epsilon) or 0)
                sum = sum + weight * backups[action + 1]
            end
            local value = sum // 4000
            delta, values[state] = math.max(delta, math.abs(value - values[state])), value
        end
        if delta <= settings.theta then
            return values[start], sweeps
        end
    end
end
local function rollouts(policy)
    local generator = environment.generator(settings.rollout_seed)
    local result = {returns = {}, discounted = {}, steps = {}, endings = {}, terminals = zeros(#world.terminals)}
    for _ = 1, settings.rollouts do
        local state, rewards, ending = start, {}, "timeout"
        while #rewards < settings.step_limit do
            local cell, reward = env:step(generator, state, policy[state])
            rewards[#rewards + 1] = reward
            state = world.state_index[cell + 1]
            if not state then
                ending = world:ending(cell)
                local index = world.terminal_index[cell + 1]
                result.terminals[index] = result.terminals[index] + 1
                break
            end
        end
        result.returns[#result.returns + 1] = total(rewards)
        result.discounted[#result.discounted + 1] = mc.discounted(rewards, settings.gamma)
        result.steps[#result.steps + 1], result.endings[#result.endings + 1] = #rewards, ending
    end
    return result
end
local evaluations = {}
for i, policy in ipairs(policies) do
    local values, sweeps = dp.evaluate(env, policy, zeros(n), settings.gamma, settings.theta)
    local gaps, optimal_count = {}, 0
    for state, action in ipairs(policy) do
        gaps[state] = optimal_values[state] - values[state]
        for _, candidate in ipairs(optimal_actions[state]) do
            if action == candidate then
                optimal_count = optimal_count + 1
            end
        end
    end
    local gap, gap_state = largest(gaps)
    local improved = dp.policy(env, values, settings.gamma)
    local improved_values = dp.evaluate(env, improved, zeros(n), settings.gamma, settings.theta)
    evaluations[i] = {values = values, sweeps = sweeps, agree = agreements(policy, optimal_policy), optimal = optimal_count, gap = gap, gap_state = gap_state, changes = n - agreements(improved, policy), improved_start = improved_values[start], improved_agree = agreements(improved, optimal_policy), absorption = absorption(policy), rollouts = rollouts(policy)}
end
local function sensitivity(current_env, gamma)
    local values, trace = dp.value_iteration(current_env, gamma, settings.theta)
    local policy = dp.policy(current_env, values, gamma)
    local ending, cells = nominal_path(current_env, policy, world.start)
    return line("iterations", #trace, "value_start", report.fixed(values[start]), "path", ending, "steps", #cells - 1, "last", report.cell(world, cells[#cells]), "differences", n - agreements(policy, optimal_policy))
end
local function state_text(state)
    return report.cell(world, world.states[state])
end
local distance, reachable = distances(), 0
for _, cell in ipairs(world.states) do
    if distance[cell + 1] ~= nil then
        reachable = reachable + 1
    end
end
local kind_counts = {}
for index = 1, #world.kinds do
    local kind = world.kinds:sub(index, index)
    kind_counts[kind] = (kind_counts[kind] or 0) + 1
end
local world_lines = {line("world rows", world.rows, "cols", world.cols, "states", n, "walls", kind_counts["#"] or 0, "floor", (kind_counts["."] or 0) + (kind_counts.S or 0), "ice", kind_counts["~"] or 0, "goals", kind_counts.G or 0, "pits", kind_counts.P or 0), line("start", report.cell(world, world.start), "reachable", reachable)}
for index, cell in ipairs(world.terminals) do
    world_lines[#world_lines + 1] = line("terminal", report.cell(world, cell), world:ending(cell), "reward", world.rewards[index], "distance", distance[cell + 1] or "-")
end
local iteration_lines = {line("value_iteration gamma", settings.gamma, "theta", report.fixed(settings.theta), "iterations", #changes)}
for i, value in ipairs(changes) do
    iteration_lines[#iteration_lines + 1] = line("iteration", i, "max_change", report.fixed(value))
end
local tied = {}
for state, actions in ipairs(optimal_actions) do
    if #actions > 1 then
        local letters = map(actions, function(action)
            return ("NESW"):sub(action + 1, action + 1)
        end)
        tied[#tied + 1] = line("tie", state_text(state), table.concat(letters))
    end
end
local symmetry_pairs, equal_values, mirrored_actions, mirror = 0, 0, 0, {0, 3, 2, 1}
for state, cell in ipairs(world.states) do
    local column, row = cell % world.cols, cell // world.cols
    local other_column = world.cols - 1 - column
    local other = world.state_index[row * world.cols + other_column + 1]
    if column < other_column and other then
        symmetry_pairs = symmetry_pairs + 1
        if optimal_values[state] == optimal_values[other] then
            equal_values = equal_values + 1
        end
        if optimal_policy[other] == mirror[optimal_policy[state] + 1] then
            mirrored_actions = mirrored_actions + 1
        end
    end
end
local ties_lines = {line("ties", #tied)}
append(ties_lines, tied)
ties_lines[#ties_lines + 1] = line("symmetry pairs", symmetry_pairs, "equal_values", equal_values, "mirrored_actions", mirrored_actions)
local round_lines, total_sweeps = {line("policy_iteration rounds", #rounds)}, 0
for i, round in ipairs(rounds) do
    total_sweeps = total_sweeps + round.sweeps
    round_lines[#round_lines + 1] = line("round", i, "sweeps", round.sweeps, "changed", round.changes, "value_start", report.fixed(round.value))
end
local differences = map(iteration_values, function(value, state)
    return math.abs(value - optimal_values[state])
end)
local difference, difference_state = largest(differences)
local comparison_lines = {line("comparison policy_differences", n - agreements(iteration_policy, optimal_policy), "max_value_difference", report.fixed(difference), "at", state_text(difference_state)), line("backups value_iteration", #changes * n * 4, "in_place_iterations", in_place_sweeps, "in_place", in_place_sweeps * n * 4, "policy_iteration", total_sweeps * n + #rounds * n * 4)}
local gamma_lines, slip_lines = {"gamma_sweep"}, {"slip_sweep"}
for _, gamma in ipairs(settings.gamma_sweep) do
    gamma_lines[#gamma_lines + 1] = line("gamma", gamma, sensitivity(env, gamma))
end
for _, pair in ipairs(settings.slip_sweep) do
    local varied = environment.new(world, settings.step_reward, settings.slip_total, pair[1], pair[2])
    slip_lines[#slip_lines + 1] = line("slip", pair[1], pair[2], sensitivity(varied, settings.gamma))
end
local values_output = report.join_parts({world_lines, iteration_lines, {"optimal_values", table.unpack(report.values(world, optimal_values))}, {"optimal_action_counts", table.unpack(report.grid(world, map(optimal_actions, function(actions)
    return tostring(#actions)
end), ""))}, ties_lines, round_lines, {"policy_iteration_values", table.unpack(report.values(world, iteration_values))}, comparison_lines, gamma_lines, slip_lines})
local policies_parts = {}
for index, policy in ipairs(policies) do
    local lines = {policy_names[index]}
    append(lines, report.policy(world, policy))
    local ending, cells = nominal_path(env, policy, world.start)
    lines[#lines + 1] = line("path", ending, "steps", #cells - 1, report.cells(world, cells))
    local action_counts, risk = {0, 0, 0, 0}, 0
    for state, action in ipairs(policy) do
        action_counts[action + 1] = action_counts[action + 1] + 1
        for _, entry in ipairs(env.transitions[state][action + 1]) do
            if world.kinds:sub(entry.cell + 1, entry.cell + 1) == "P" then
                risk = risk + 1
                break
            end
        end
    end
    lines[#lines + 1] = line("actions N", action_counts[1], "E", action_counts[2], "S", action_counts[3], "W", action_counts[4], "risk", risk)
    lines[#lines + 1] = "basins"
    local symbols = {}
    for state, origin in ipairs(world.states) do
        local terminal_ending, path = nominal_path(env, policy, origin)
        symbols[state] = (terminal_ending == "goal" or terminal_ending == "pit")
            and ("abcdefghijklmnopqrstuvwxyz"):sub(world.terminal_index[path[#path] + 1], world.terminal_index[path[#path] + 1]) or "*"
    end
    append(lines, report.grid(world, symbols, ""))
    if index > 2 then
        lines[#lines + 1] = "visits"
        append(lines, report.grid(world, map(learners[index - 2].state_visits, function(value)
            return value == 0 and "0" or tostring(#tostring(value))
        end), ""))
    end
    policies_parts[#policies_parts + 1] = lines
end
local q_output = {"method,row,col,action,value,visits"}
append(q_output, report.q_rows(world, "value_iteration", optimal_q))
for _, learner in ipairs(learners) do
    append(q_output, report.q_rows(world, learner.method, learner.q, learner.visits))
end
local function episode_totals(episodes, first, last)
    local result = {total = 0, steps = 0, goal = 0, pit = 0, timeout = 0}
    for index = first, last do
        local episode = episodes[index]
        result.total, result.steps = result.total + episode.total, result.steps + episode.steps
        result[episode.ending] = result[episode.ending] + 1
    end
    return result
end
local curve_output = {"method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"}
for _, learner in ipairs(learners) do
    learner.block_totals = {}
    for number, block in ipairs(learner.blocks) do
        local aggregate = episode_totals(learner.episodes, (number - 1) * settings.block_size + 1, number * settings.block_size)
        learner.block_totals[number] = aggregate.total
        curve_output[#curve_output + 1] = table.concat({learner.method, number, report.average(aggregate.total, settings.block_size), report.average(aggregate.steps, settings.block_size), aggregate.goal, aggregate.pit, aggregate.timeout, block.agree, report.fixed(block.error), block.coverage}, ",")
    end
end
local evaluation_parts = {
    {line("summary states", n, "start", report.cell(world, world.start), "rollouts", settings.rollouts, "step_limit", settings.step_limit)}
}
local policy_value_lines = {"policies", "policy agree optimal_actions value_start sweeps max_gap at"}
local improvement_lines = {"improvement", "policy changed value_start agree"}
local absorption_lines = {"absorption", "policy p_goal p_pit p_timeout expected_steps"}
local rollout_lines = {"rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"}
local terminal_lines = {"terminals", "policy " .. report.cells(world, world.terminals)}
local agreement_lines = {"agreement", "policy " .. table.concat(policy_names, " ")}
for index, evaluation in ipairs(evaluations) do
    local name, draws = policy_names[index], evaluation.rollouts
    policy_value_lines[#policy_value_lines + 1] = line(name, evaluation.agree, evaluation.optimal, report.fixed(evaluation.values[start]), evaluation.sweeps, report.fixed(evaluation.gap), state_text(evaluation.gap_state))
    improvement_lines[#improvement_lines + 1] = line(name, evaluation.changes, report.fixed(evaluation.improved_start), evaluation.improved_agree)
    local absorption_fields = {name}
    for _, value in ipairs(evaluation.absorption) do
        absorption_fields[#absorption_fields + 1] = report.fixed(value // 10000)
    end
    absorption_lines[#absorption_lines + 1] = table.concat(absorption_fields, " ")
    local returns = {}
    append(returns, draws.returns)
    table.sort(returns)
    local endings = counts(draws.endings)
    rollout_lines[#rollout_lines + 1] = line(name, report.average(total(draws.returns), settings.rollouts), report.fixed(total(draws.discounted) // settings.rollouts), report.average(total(draws.steps), settings.rollouts), endings.goal, endings.pit, endings.timeout, returns[1], returns[(settings.rollouts + 1) // 2], returns[#returns])
    terminal_lines[#terminal_lines + 1] = name .. " " .. table.concat(draws.terminals, " ")
    local agreement_fields = {name}
    for _, other in ipairs(policies) do
        agreement_fields[#agreement_fields + 1] = agreements(policies[index], other)
    end
    agreement_lines[#agreement_lines + 1] = table.concat(agreement_fields, " ")
end
append(evaluation_parts, {policy_value_lines, improvement_lines, absorption_lines})
local behaviour_lines = {"behaviour", "method epsilon value_start sweeps"}
local q_error_lines = {"q_errors", "method mean_abs max_abs at unvisited tied"}
local q_action_lines = {"q_action_errors", "method N E S W"}
local final_epsilon = schedule_value(settings.epsilon, settings.episodes)
for _, learner in ipairs(learners) do
    local value, sweeps = behaviour(learner.policy, final_epsilon)
    behaviour_lines[#behaviour_lines + 1] = line(learner.method, final_epsilon, report.fixed(value), sweeps)
    local errors, unvisited, ties = {}, 0, 0
    for state, row in ipairs(learner.q) do
        local best, equal = math.max(table.unpack(row)), 0
        errors[state] = math.abs(best - optimal_values[state])
        if learner.state_visits[state] == 0 then
            unvisited = unvisited + 1
        end
        for _, entry in ipairs(row) do
            if entry == best then
                equal = equal + 1
            end
        end
        if equal > 1 then
            ties = ties + 1
        end
    end
    local max_error, worst = largest(errors)
    q_error_lines[#q_error_lines + 1] = line(learner.method, report.fixed(total(errors) // n), report.fixed(max_error), state_text(worst), unvisited, ties)
    local fields = {learner.method}
    for action = 1, 4 do
        local sum, count = 0, 0
        for state, row in ipairs(learner.q) do
            if learner.visits[state][action] > 0 then
                sum, count = sum + math.abs(row[action] - optimal_q[state][action]), count + 1
            end
        end
        fields[#fields + 1] = count > 0 and report.fixed(sum // count) or "-"
    end
    q_action_lines[#q_action_lines + 1] = table.concat(fields, " ")
end
append(evaluation_parts, {behaviour_lines, q_error_lines, q_action_lines, rollout_lines, terminal_lines, agreement_lines})
local training_lines = {"training", "method steps goals pits timeouts best_block best_mean last_mean reach"}
local visited_lines, last_lines, phase_lines = {"visited"}, {"last_episodes"}, {"phases"}
local optimal_total = total(evaluations[1].rollouts.returns)
local phase_starts, phase_set = {}, {}
for _, schedule in ipairs({settings.alpha, settings.epsilon}) do
    for _, entry in ipairs(schedule) do
        phase_set[entry[1]] = true
    end
end
for first in pairs(phase_set) do
    phase_starts[#phase_starts + 1] = first
end
table.sort(phase_starts)
for _, learner in ipairs(learners) do
    local aggregate = episode_totals(learner.episodes, 1, settings.episodes)
    local best_total, best = largest(learner.block_totals)
    local reach = "-"
    for number, value in ipairs(learner.block_totals) do
        if 10 * settings.rollouts * value >= 9 * settings.block_size * optimal_total then
            reach = number
            break
        end
    end
    training_lines[#training_lines + 1] = line(learner.method, aggregate.steps, aggregate.goal, aggregate.pit, aggregate.timeout, best, report.average(best_total, settings.block_size), report.average(learner.block_totals[#learner.block_totals], settings.block_size), reach)
    local order = {}
    for state = 1, n do
        order[state] = state
    end
    table.sort(order, function(a, b)
        return learner.state_visits[a] > learner.state_visits[b] or learner.state_visits[a] == learner.state_visits[b] and a < b
    end)
    local visits = {learner.method}
    for i = 1, 3 do
        local state = order[i]
        visits[#visits + 1] = state_text(state) .. ":" .. learner.state_visits[state]
    end
    visited_lines[#visited_lines + 1] = table.concat(visits, " ")
    local episode = learner.episodes[#learner.episodes]
    last_lines[#last_lines + 1] = line(learner.method, "return", episode.total, "steps", episode.steps, "end", episode.ending, report.cells(world, episode.cells))
    for index, first in ipairs(phase_starts) do
        local last = phase_starts[index + 1] and phase_starts[index + 1] - 1 or settings.episodes
        local phase = episode_totals(learner.episodes, first, last)
        phase_lines[#phase_lines + 1] = line(learner.method, first .. "-" .. last, "alpha", schedule_value(settings.alpha, first), "epsilon", schedule_value(settings.epsilon, first), "mean_return", report.average(phase.total, last - first + 1), "mean_steps", report.average(phase.steps, last - first + 1), "goals", phase.goal)
    end
end
append(evaluation_parts, {training_lines, visited_lines, last_lines, phase_lines})
os.execute("mkdir -p output")
report.write("values.txt", values_output)
report.write("policies.txt", report.join_parts(policies_parts))
report.write("q_tables.csv", q_output)
report.write("learning_curves.csv", curve_output)
report.write("evaluation.txt", report.join_parts(evaluation_parts))
