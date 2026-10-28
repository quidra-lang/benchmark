#include "reinforcement.hpp"
struct Params {
    Integer gamma, step_reward, q, floor_slip, ice_slip, theta, seed, rollout_seed;
    int episodes, limit, block, planning, rollouts;
    Values gammas;
    std::vector<std::pair<Integer, Integer>> slips, alpha, epsilon;
};
static Params read_params() {
    const Lines lines = read_lines("input/params.txt");
    std::vector<Values> rows;
    for (const std::string &line : lines) {
        std::istringstream in(line);
        std::string word;
        in >> word;
        Values row;
        Integer value;
        while (in >> value)
            row.push_back(value);
        rows.push_back(row);
    }
    auto pairs = [](const Values &row) {
        std::vector<std::pair<Integer, Integer>> result;
        for (std::size_t i = 0; i < row.size(); i += 2)
            result.emplace_back(row[i], row[i + 1]);
        return result;
    };
    return {rows[0][0],      rows[1][0],       rows[2][0],       rows[2][1],      rows[2][2],
            rows[3][0],      rows[12][0],      rows[14][0],      int(rows[6][0]), int(rows[7][0]),
            int(rows[8][0]), int(rows[11][0]), int(rows[13][0]), rows[4],         pairs(rows[5]),
            pairs(rows[9]),  pairs(rows[10])};
}
static Integer schedule(const std::vector<std::pair<Integer, Integer>> &values, int episode) {
    Integer result = 0;
    for (const auto &pair : values) {
        if (pair.first > episode)
            break;
        result = pair.second;
    }
    return result;
}
const std::array<std::string, 5> method_names = {"mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"};
const std::array<std::string, 7> policy_names = {"value_iteration", "policy_iteration", "mc",    "sarsa",
                                                 "q_learning",      "expected_sarsa",   "dyna_q"};
struct Episode {
    Integer returns = 0;
    int steps = 0;
    std::string end;
    std::vector<int> cells;
};
struct Block {
    Integer returns = 0, steps = 0;
    std::array<Integer, 3> endings{};
    Integer agree = 0, error = 0, coverage = 0;
};
struct Learning {
    Table q, visits;
    Policy policy;
    std::vector<Episode> episodes;
    std::vector<Block> blocks;
};
static int ending_index(const std::string &end) {
    return end == "goal" ? 0 : end == "pit" ? 1 : 2;
}
static Integer visit_total(const Table &visits, std::size_t state) {
    Integer total = 0;
    for (Integer count : visits[state])
        total += count;
    return total;
}
static Learning learn(const Model &model, const Params &p, const Iteration &optimal, int method) {
    const World &w = *model.world;
    const int start = w.index[w.start];
    Learning result;
    result.q.resize(w.states.size());
    result.visits.resize(w.states.size());
    Table sums(w.states.size()), counts(w.states.size());
    Dyna dyna(w.states.size());
    Random random{p.seed};
    for (int episode = 1; episode <= p.episodes; ++episode) {
        const Integer alpha = schedule(p.alpha, episode), epsilon = schedule(p.epsilon, episode);
        int state = start;
        int action = method == 1 ? choose(result.q, state, epsilon, random) : 0;
        Episode record;
        if (episode == p.episodes)
            record.cells.push_back(w.start);
        std::vector<Sample> samples;
        for (int t = 0; t < p.limit; ++t) {
            if (method != 1)
                action = choose(result.q, state, epsilon, random);
            const auto outcome = step(model, state, action, random);
            const int next = outcome.first, next_state = w.index[next];
            const Integer r = outcome.second;
            ++result.visits[state][action];
            int next_action = 0;
            if (method == 0)
                samples.push_back({state, action, r});
            else {
                Integer f = 0;
                if (next_state >= 0) {
                    if (method == 1) {
                        next_action = choose(result.q, next_state, epsilon, random);
                        f = result.q[next_state][next_action];
                    } else
                        f = next_value(result.q, next_state, epsilon, method == 3);
                }
                td_update(model, result.q, state, action, next, r, p.gamma, alpha, f);
                if (method == 4) {
                    dyna.record(state, action, next, r);
                    dyna.plan(model, result.q, p.planning, p.gamma, alpha, random);
                }
            }
            record.returns += r;
            ++record.steps;
            if (episode == p.episodes)
                record.cells.push_back(next);
            record.end = ending(w, next);
            if (terminal(w, next))
                break;
            state = next_state;
            if (method == 1)
                action = next_action;
        }
        if (method == 0)
            monte_carlo(samples, result.q, sums, counts, p.gamma);
        result.episodes.push_back(std::move(record));
        if (episode % p.block == 0) {
            Block block;
            for (int j = episode - p.block; j < episode; ++j) {
                const Episode &record_ = result.episodes[j];
                block.returns += record_.returns;
                block.steps += record_.steps;
                ++block.endings[ending_index(record_.end)];
            }
            for (std::size_t s = 0; s < result.q.size(); ++s) {
                const int a = first_maximum(result.q[s]);
                if (a == optimal.policy[s])
                    ++block.agree;
                block.error += absolute(result.q[s][a] - optimal.values[s]);
                if (visit_total(result.visits, s) > 0)
                    ++block.coverage;
            }
            block.error = floor_div(block.error, result.q.size());
            result.blocks.push_back(block);
        }
    }
    result.policy = greedy(result.q);
    return result;
}
struct Path {
    std::vector<int> cells;
    std::string end;
    int steps() const {
        return int(cells.size()) - 1;
    }
};
static Path path(const World &w, const Policy &policy, int origin, int limit) {
    Path result{{origin}, {}};
    std::vector<bool> seen(w.cells.size());
    seen[origin] = true;
    while (true) {
        const int next = w.moves[w.index[result.cells.back()]][policy[w.index[result.cells.back()]]];
        const bool repeated = seen[next];
        result.cells.push_back(next);
        if (terminal(w, next)) {
            result.end = ending(w, next);
            break;
        }
        if (repeated) {
            result.end = "loop";
            break;
        }
        if (result.steps() >= limit) {
            result.end = "limit";
            break;
        }
        seen[next] = true;
    }
    return result;
}
static Values distances(const Model &model) {
    const World &w = *model.world;
    Values distance(w.cells.size(), -1);
    distance[w.start] = 0;
    std::queue<int> queue;
    queue.push(w.start);
    while (!queue.empty()) {
        const int cell = queue.front();
        queue.pop();
        if (terminal(w, cell))
            continue;
        for (int a = 0; a < 4; ++a)
            for (const Transition &t : model.transitions(w.index[cell], a))
                if (distance[t.cell] < 0) {
                    distance[t.cell] = distance[cell] + 1;
                    queue.push(t.cell);
                }
    }
    return distance;
}
static int differences(const Policy &a, const Policy &b) {
    int count = 0;
    for (std::size_t i = 0; i < a.size(); ++i)
        if (a[i] != b[i])
            ++count;
    return count;
}
static std::array<Integer, 4> absorption(const Model &model, const Policy &policy, int limit) {
    const World &w = *model.world;
    Values goal(w.states.size()), pit(w.states.size()), expected(w.states.size());
    const Integer d = 100000000;
    for (int k = 0; k < limit; ++k) {
        Values ng(goal.size()), np(goal.size()), ne(goal.size());
        for (std::size_t s = 0; s < goal.size(); ++s) {
            Integer g = 0, p = 0, e = 0;
            for (const Transition &t : model.transitions(s, policy[s])) {
                const int next = w.index[t.cell];
                g += t.weight * (next < 0 ? (w.cells[t.cell] == 'G' ? d : 0) : goal[next]);
                p += t.weight * (next < 0 ? (w.cells[t.cell] == 'P' ? d : 0) : pit[next]);
                e += t.weight * (next < 0 ? 0 : expected[next]);
            }
            ng[s] = floor_div(g, model.q);
            np[s] = floor_div(p, model.q);
            ne[s] = d + floor_div(e, model.q);
        }
        goal = std::move(ng);
        pit = std::move(np);
        expected = std::move(ne);
    }
    const int start = w.index[w.start];
    return {floor_div(goal[start], 10000), floor_div(pit[start], 10000),
            floor_div(d - goal[start] - pit[start], 10000), floor_div(expected[start], 10000)};
}
static std::pair<Integer, int> behaviour(const Model &model, const Policy &policy, const Params &p) {
    Values values(policy.size());
    const Integer epsilon = schedule(p.epsilon, p.episodes);
    int sweeps = 0;
    while (true) {
        ++sweeps;
        Integer delta = 0;
        for (std::size_t s = 0; s < policy.size(); ++s) {
            Integer sum = 0;
            for (int a = 0; a < 4; ++a)
                sum += (epsilon + (a == policy[s] ? 4 * (1000 - epsilon) : 0)) *
                       bellman(model, values, s, a, p.gamma);
            const Integer value = floor_div(sum, 4000);
            delta = std::max(delta, absolute(value - values[s]));
            values[s] = value;
        }
        if (delta <= p.theta)
            return {values[model.world->index[model.world->start]], sweeps};
    }
}
struct Rollouts {
    Integer returns = 0, discounted = 0, steps = 0;
    std::array<Integer, 3> endings{};
    Values terminals, sorted_returns;
};
static Rollouts rollout(const Model &model, const Policy &policy, const Params &p) {
    const World &w = *model.world;
    Rollouts result;
    result.terminals.resize(w.terminals.size());
    Random random{p.rollout_seed};
    for (int i = 0; i < p.rollouts; ++i) {
        int state = w.index[w.start], last = w.start;
        Integer total = 0;
        Values rewards;
        for (int t = 0; t < p.limit; ++t) {
            const auto outcome = step(model, state, policy[state], random);
            last = outcome.first;
            total += outcome.second;
            rewards.push_back(outcome.second);
            if (terminal(w, last))
                break;
            state = w.index[last];
        }
        result.returns += total;
        result.discounted += discounted(rewards, p.gamma);
        result.steps += rewards.size();
        ++result.endings[ending_index(ending(w, last))];
        if (terminal(w, last))
            ++result.terminals[w.terminal_index[last]];
        result.sorted_returns.push_back(total);
    }
    std::sort(result.sorted_returns.begin(), result.sorted_returns.end());
    return result;
}
static void extend(Lines &out, const Lines &lines) {
    out.insert(out.end(), lines.begin(), lines.end());
}
static Lines policy_lines(const Model &model, const Policy &policy, const Learning *learning, int limit) {
    const World &w = *model.world;
    Lines out = policy_grid(w, policy);
    const Path nominal = path(w, policy, w.start, limit);
    out.push_back("path " + nominal.end + " steps " + number(nominal.steps()) + " " +
                  cells_text(w, nominal.cells));
    std::array<Integer, 4> counts{};
    Integer risky = 0;
    Lines basin;
    for (std::size_t s = 0; s < policy.size(); ++s) {
        ++counts[policy[s]];
        bool risk = false;
        for (const Transition &transition : model.transitions(s, policy[s]))
            if (w.cells[transition.cell] == 'P')
                risk = true;
        if (risk)
            ++risky;
        const Path route = path(w, policy, w.states[s], limit);
        basin.push_back(route.end == "goal" || route.end == "pit"
                            ? std::string(1, char('a' + w.terminal_index[route.cells.back()]))
                            : "*");
    }
    out.push_back("actions N " + number(counts[0]) + " E " + number(counts[1]) + " S " + number(counts[2]) +
                  " W " + number(counts[3]) + " risk " + number(risky));
    out.push_back("basins");
    extend(out, grid(w, basin, ""));
    if (learning) {
        out.push_back("visits");
        Lines fields;
        for (std::size_t s = 0; s < policy.size(); ++s) {
            const Integer total = visit_total(learning->visits, s);
            fields.push_back(total == 0 ? "0" : number(number(total).size()));
        }
        extend(out, grid(w, fields, ""));
    }
    return out;
}
int main() {
    const World w = read_world();
    const Params p = read_params();
    const Model model{&w, p.q, p.floor_slip, p.ice_slip, p.step_reward};
    const Iteration optimal = value_iteration(model, p.gamma, p.theta);
    const auto inplace = in_place(model, p.gamma, p.theta);
    const PolicyIteration pi = policy_iteration(model, p.gamma, p.theta);
    const int start = w.index[w.start];
    std::vector<Learning> learning;
    for (int method = 0; method < 5; ++method)
        learning.push_back(learn(model, p, optimal, method));
    std::vector<Policy> policies = {optimal.policy, pi.policy};
    for (const Learning &method : learning)
        policies.push_back(method.policy);
    std::vector<Rollouts> rollouts;
    for (const Policy &policy : policies)
        rollouts.push_back(rollout(model, policy, p));
    const Values distance = distances(model);
    std::vector<Lines> value_parts(10);
    std::array<Integer, 6> kinds{};
    for (char c : w.cells) {
        int index = c == '#' ? 0 : c == '.' || c == 'S' ? 1 : c == '~' ? 2 : c == 'G' ? 3 : 4;
        ++kinds[index];
    }
    Integer reachable = 0;
    for (int cell : w.states)
        if (distance[cell] >= 0)
            ++reachable;
    value_parts[0].push_back("world rows " + number(w.rows) + " cols " + number(w.cols) + " states " +
                             number(w.states.size()) + " walls " + number(kinds[0]) + " floor " +
                             number(kinds[1]) + " ice " + number(kinds[2]) + " goals " + number(kinds[3]) +
                             " pits " + number(kinds[4]));
    value_parts[0].push_back("start " + cell_text(w, w.start) + " reachable " + number(reachable));
    for (int cell : w.terminals)
        value_parts[0].push_back("terminal " + cell_text(w, cell) + " " + ending(w, cell) + " reward " +
                                 number(w.rewards[cell]) + " distance " +
                                 (distance[cell] < 0 ? "-" : number(distance[cell])));
    value_parts[1].push_back("value_iteration gamma " + number(p.gamma) + " theta " + fixed(p.theta) +
                             " iterations " + number(optimal.deltas.size()));
    for (std::size_t i = 0; i < optimal.deltas.size(); ++i)
        value_parts[1].push_back("iteration " + number(i + 1) + " max_change " + fixed(optimal.deltas[i]));
    value_parts[2] = {"optimal_values"};
    extend(value_parts[2], value_grid(w, optimal.values));
    value_parts[3] = {"optimal_action_counts"};
    Lines counts;
    std::vector<std::string> sets;
    int ties = 0;
    for (const auto &row : optimal.actions) {
        const Integer best = row[first_maximum(row)];
        std::string actions;
        for (int a = 0; a < 4; ++a)
            if (row[a] == best)
                actions += "NESW"[a];
        sets.push_back(actions);
        counts.push_back(number(actions.size()));
        if (actions.size() > 1)
            ++ties;
    }
    extend(value_parts[3], grid(w, counts, ""));
    value_parts[4] = {"ties " + number(ties)};
    for (std::size_t s = 0; s < sets.size(); ++s)
        if (sets[s].size() > 1)
            value_parts[4].push_back("tie " + cell_text(w, w.states[s]) + " " + sets[s]);
    Integer pairs = 0, equal_values = 0, mirrored = 0;
    const std::array<int, 4> mirror = {0, 3, 2, 1};
    for (std::size_t s = 0; s < w.states.size(); ++s) {
        const int cell = w.states[s], col = cell % w.cols,
                  other = (cell / w.cols) * w.cols + w.cols - 1 - col;
        if (col >= w.cols - 1 - col || w.index[other] < 0)
            continue;
        ++pairs;
        const int t = w.index[other];
        if (optimal.values[s] == optimal.values[t])
            ++equal_values;
        if (optimal.policy[t] == mirror[optimal.policy[s]])
            ++mirrored;
    }
    value_parts[4].push_back("symmetry pairs " + number(pairs) + " equal_values " + number(equal_values) +
                             " mirrored_actions " + number(mirrored));
    value_parts[5] = {"policy_iteration rounds " + number(pi.rounds.size())};
    Integer pi_sweeps = 0;
    for (std::size_t i = 0; i < pi.rounds.size(); ++i) {
        const Round &r = pi.rounds[i];
        pi_sweeps += r.sweeps;
        value_parts[5].push_back("round " + number(i + 1) + " sweeps " + number(r.sweeps) + " changed " +
                                 number(r.changed) + " value_start " + fixed(r.start));
    }
    value_parts[6] = {"policy_iteration_values"};
    extend(value_parts[6], value_grid(w, pi.values));
    Integer maximum_difference = -1;
    int maximum_at = 0;
    for (std::size_t s = 0; s < w.states.size(); ++s)
        if (absolute(pi.values[s] - optimal.values[s]) > maximum_difference) {
            maximum_difference = absolute(pi.values[s] - optimal.values[s]);
            maximum_at = s;
        }
    value_parts[7] = {
        "comparison policy_differences " + number(differences(pi.policy, optimal.policy)) +
            " max_value_difference " + fixed(maximum_difference) + " at " +
            cell_text(w, w.states[maximum_at]),
        "backups value_iteration " + number(Integer(optimal.deltas.size()) * w.states.size() * 4) +
            " in_place_iterations " + number(inplace.second) + " in_place " +
            number(Integer(inplace.second) * w.states.size() * 4) + " policy_iteration " +
            number(pi_sweeps * w.states.size() + Integer(pi.rounds.size()) * w.states.size() * 4)};
    value_parts[8] = {"gamma_sweep"};
    for (Integer gamma : p.gammas) {
        const Iteration result = value_iteration(model, gamma, p.theta);
        const Path route = path(w, result.policy, w.start, p.limit);
        value_parts[8].push_back("gamma " + number(gamma) + " iterations " + number(result.deltas.size()) +
                                 " value_start " + fixed(result.values[start]) + " path " + route.end +
                                 " steps " + number(route.steps()) + " last " +
                                 cell_text(w, route.cells.back()) + " differences " +
                                 number(differences(result.policy, optimal.policy)));
    }
    value_parts[9] = {"slip_sweep"};
    for (const auto &slip : p.slips) {
        const Model changed{&w, p.q, slip.first, slip.second, p.step_reward};
        const Iteration result = value_iteration(changed, p.gamma, p.theta);
        const Path route = path(w, result.policy, w.start, p.limit);
        value_parts[9].push_back("slip " + number(slip.first) + " " + number(slip.second) + " iterations " +
                                 number(result.deltas.size()) + " value_start " +
                                 fixed(result.values[start]) + " path " + route.end + " steps " +
                                 number(route.steps()) + " last " + cell_text(w, route.cells.back()) +
                                 " differences " + number(differences(result.policy, optimal.policy)));
    }
    std::vector<Lines> policy_parts;
    for (std::size_t i = 0; i < policies.size(); ++i) {
        Lines lines = {policy_names[i]};
        Lines body = policy_lines(model, policies[i], i >= 2 ? &learning[i - 2] : nullptr, p.limit);
        extend(lines, body);
        policy_parts.push_back(lines);
    }
    Lines tables = {"method,row,col,action,value,visits"};
    extend(tables, q_rows(w, "value_iteration", optimal.actions, nullptr));
    Lines curves = {"method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage"};
    for (int method = 0; method < 5; ++method) {
        extend(tables, q_rows(w, method_names[method], learning[method].q, &learning[method].visits));
        for (std::size_t i = 0; i < learning[method].blocks.size(); ++i) {
            const Block &b = learning[method].blocks[i];
            curves.push_back(method_names[method] + "," + number(i + 1) + "," + average(b.returns, p.block) +
                             "," + average(b.steps, p.block) + "," + number(b.endings[0]) + "," +
                             number(b.endings[1]) + "," + number(b.endings[2]) + "," + number(b.agree) + "," +
                             fixed(b.error) + "," + number(b.coverage));
        }
    }
    std::vector<Lines> evaluation(14);
    evaluation[0] = {"summary states " + number(w.states.size()) + " start " + cell_text(w, w.start) +
                     " rollouts " + number(p.rollouts) + " step_limit " + number(p.limit)};
    evaluation[1] = {"policies", "policy agree optimal_actions value_start sweeps max_gap at"};
    evaluation[2] = {"improvement", "policy changed value_start agree"};
    evaluation[3] = {"absorption", "policy p_goal p_pit p_timeout expected_steps"};
    evaluation[4] = {"behaviour", "method epsilon value_start sweeps"};
    evaluation[5] = {"q_errors", "method mean_abs max_abs at unvisited tied"};
    evaluation[6] = {"q_action_errors", "method N E S W"};
    evaluation[7] = {"rollouts",
                     "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"};
    evaluation[8] = {"terminals"};
    std::string terminal_header = "policy";
    for (int cell : w.terminals)
        terminal_header += " " + cell_text(w, cell);
    evaluation[8].push_back(terminal_header);
    evaluation[9] = {"agreement",
                     "policy value_iteration policy_iteration mc sarsa q_learning expected_sarsa dyna_q"};
    evaluation[10] = {"training", "method steps goals pits timeouts best_block best_mean last_mean reach"};
    evaluation[11] = {"visited"};
    evaluation[12] = {"last_episodes"};
    evaluation[13] = {"phases"};
    for (std::size_t i = 0; i < policies.size(); ++i) {
        const Policy &policy = policies[i];
        const auto evaluated = evaluate(model, policy, Values(w.states.size()), p.gamma, p.theta);
        Integer agree = 0, optimal_actions = 0, max_gap = optimal.values[0] - evaluated.first[0];
        int gap_at = 0;
        for (std::size_t s = 0; s < w.states.size(); ++s) {
            if (policy[s] == optimal.policy[s])
                ++agree;
            if (optimal.actions[s][policy[s]] == optimal.actions[s][optimal.policy[s]])
                ++optimal_actions;
            const Integer gap = optimal.values[s] - evaluated.first[s];
            if (gap > max_gap) {
                max_gap = gap;
                gap_at = s;
            }
        }
        evaluation[1].push_back(policy_names[i] + " " + number(agree) + " " + number(optimal_actions) + " " +
                                fixed(evaluated.first[start]) + " " + number(evaluated.second) + " " +
                                fixed(max_gap) + " " + cell_text(w, w.states[gap_at]));
        const Policy improved = greedy(action_values(model, evaluated.first, p.gamma));
        const auto improved_value = evaluate(model, improved, Values(w.states.size()), p.gamma, p.theta);
        evaluation[2].push_back(policy_names[i] + " " + number(differences(policy, improved)) + " " +
                                fixed(improved_value.first[start]) + " " +
                                number(w.states.size() - differences(improved, optimal.policy)));
        std::string absorption_line = policy_names[i];
        for (Integer value : absorption(model, policy, p.limit))
            absorption_line += " " + fixed(value);
        evaluation[3].push_back(absorption_line);
        const Rollouts &r = rollouts[i];
        evaluation[7].push_back(
            policy_names[i] + " " + average(r.returns, p.rollouts) + " " +
            fixed(floor_div(r.discounted, p.rollouts)) + " " + average(r.steps, p.rollouts) + " " +
            number(r.endings[0]) + " " + number(r.endings[1]) + " " + number(r.endings[2]) + " " +
            number(r.sorted_returns.front()) + " " + number(r.sorted_returns[(p.rollouts - 1) / 2]) + " " +
            number(r.sorted_returns.back()));
        std::string terminal_line = policy_names[i];
        for (Integer value : r.terminals)
            terminal_line += " " + number(value);
        evaluation[8].push_back(terminal_line);
        std::string agreement_line = policy_names[i];
        for (const Policy &other : policies)
            agreement_line += " " + number(w.states.size() - differences(policy, other));
        evaluation[9].push_back(agreement_line);
        if (i < 2)
            continue;
        const int method = i - 2;
        const Learning &m = learning[method];
        const auto behavior = behaviour(model, policy, p);
        evaluation[4].push_back(method_names[method] + " " + number(schedule(p.epsilon, p.episodes)) + " " +
                                fixed(behavior.first) + " " + number(behavior.second));
        Integer errors = 0, maximum = -1, unvisited = 0, tied = 0;
        int at = 0;
        std::array<Integer, 4> action_errors{}, action_counts{};
        for (std::size_t s = 0; s < w.states.size(); ++s) {
            const Integer best = m.q[s][first_maximum(m.q[s])], error = absolute(best - optimal.values[s]);
            errors += error;
            if (error > maximum) {
                maximum = error;
                at = s;
            }
            if (visit_total(m.visits, s) == 0)
                ++unvisited;
            int count = 0;
            for (int a = 0; a < 4; ++a) {
                if (m.q[s][a] == best)
                    ++count;
                if (m.visits[s][a] > 0) {
                    action_errors[a] += absolute(m.q[s][a] - optimal.actions[s][a]);
                    ++action_counts[a];
                }
            }
            if (count > 1)
                ++tied;
        }
        evaluation[5].push_back(method_names[method] + " " + fixed(floor_div(errors, w.states.size())) + " " +
                                fixed(maximum) + " " + cell_text(w, w.states[at]) + " " + number(unvisited) +
                                " " + number(tied));
        std::string action_line = method_names[method];
        for (int a = 0; a < 4; ++a)
            action_line +=
                " " + (action_counts[a] ? fixed(floor_div(action_errors[a], action_counts[a])) : "-");
        evaluation[6].push_back(action_line);
        Integer steps_total = 0;
        std::array<Integer, 3> endings{};
        for (const Episode &e : m.episodes) {
            steps_total += e.steps;
            ++endings[ending_index(e.end)];
        }
        int best_block = 0, reach = -1;
        for (std::size_t b = 0; b < m.blocks.size(); ++b) {
            if (m.blocks[b].returns > m.blocks[best_block].returns)
                best_block = b;
            if (reach < 0 &&
                10 * Integer(p.rollouts) * m.blocks[b].returns >= 9 * Integer(p.block) * rollouts[0].returns)
                reach = b + 1;
        }
        evaluation[10].push_back(
            method_names[method] + " " + number(steps_total) + " " + number(endings[0]) + " " +
            number(endings[1]) + " " + number(endings[2]) + " " + number(best_block + 1) + " " +
            average(m.blocks[best_block].returns, p.block) + " " + average(m.blocks.back().returns, p.block) +
            " " + (reach < 0 ? "-" : number(reach)));
        std::vector<int> order(w.states.size());
        std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            const Integer av = visit_total(m.visits, a), bv = visit_total(m.visits, b);
            return av != bv ? av > bv : a < b;
        });
        std::string visited = method_names[method];
        for (int j = 0; j < 3; ++j)
            visited += " " + cell_text(w, w.states[order[j]]) + ":" + number(visit_total(m.visits, order[j]));
        evaluation[11].push_back(visited);
        const Episode &last = m.episodes.back();
        evaluation[12].push_back(method_names[method] + " return " + number(last.returns) + " steps " +
                                 number(last.steps) + " end " + last.end + " " + cells_text(w, last.cells));
        std::set<Integer> phase_starts;
        for (const auto &pair : p.alpha)
            phase_starts.insert(pair.first);
        for (const auto &pair : p.epsilon)
            phase_starts.insert(pair.first);
        Values phases(phase_starts.begin(), phase_starts.end());
        phases.push_back(p.episodes + 1);
        for (std::size_t phase = 0; phase + 1 < phases.size(); ++phase) {
            const int first = phases[phase], last_episode = phases[phase + 1] - 1;
            Integer returns = 0, steps_ = 0, goals = 0;
            for (int episode = first; episode <= last_episode; ++episode) {
                const Episode &e = m.episodes[episode - 1];
                returns += e.returns;
                steps_ += e.steps;
                if (e.end == "goal")
                    ++goals;
            }
            evaluation[13].push_back(method_names[method] + " " + number(first) + "-" + number(last_episode) +
                                     " alpha " + number(schedule(p.alpha, first)) + " epsilon " +
                                     number(schedule(p.epsilon, first)) + " mean_return " +
                                     average(returns, last_episode - first + 1) + " mean_steps " +
                                     average(steps_, last_episode - first + 1) + " goals " + number(goals));
        }
    }
    write_lines("values.txt", parts(value_parts));
    write_lines("policies.txt", parts(policy_parts));
    write_lines("q_tables.csv", tables);
    write_lines("learning_curves.csv", curves);
    write_lines("evaluation.txt", parts(evaluation));
}
