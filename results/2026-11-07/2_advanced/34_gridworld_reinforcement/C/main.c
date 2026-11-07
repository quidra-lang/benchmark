#include "reinforcement.h"
typedef struct {
    Integer *data;
    size_t len, cap;
} Numbers;
typedef struct {
    Integer gamma, step_reward, q, floor_slip, ice_slip, theta, seed, rollout_seed;
    int episodes, limit, block, planning, rollouts;
    Numbers gammas, slips, alpha, epsilon;
} Params;
static Params read_params(void) {
    Lines lines = read_lines("input/params.txt");
    Numbers rows[15] = {{0}};
    for (int i = 0; i < 15; ++i) {
        const char *cursor = strchr(lines.data[i], ' ') + 1;
        while (*cursor) {
            char *end;
            Integer value = strtoll(cursor, &end, 10);
            grow((void **)&rows[i].data, &rows[i].cap, rows[i].len + 1, sizeof *rows[i].data);
            rows[i].data[rows[i].len++] = value;
            cursor = end;
            while (*cursor == ' ')
                ++cursor;
        }
    }
    return (Params){rows[0].data[0],
                    rows[1].data[0],
                    rows[2].data[0],
                    rows[2].data[1],
                    rows[2].data[2],
                    rows[3].data[0],
                    rows[12].data[0],
                    rows[14].data[0],
                    (int)rows[6].data[0],
                    (int)rows[7].data[0],
                    (int)rows[8].data[0],
                    (int)rows[11].data[0],
                    (int)rows[13].data[0],
                    rows[4],
                    rows[5],
                    rows[9],
                    rows[10]};
}
static Integer schedule(Numbers values, int episode) {
    Integer result = 0;
    for (size_t i = 0; i < values.len; i += 2) {
        if (values.data[i] > episode)
            break;
        result = values.data[i + 1];
    }
    return result;
}
static const char *method_names[5] = {"mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"};
static const char *policy_names[7] = {"value_iteration", "policy_iteration", "mc",    "sarsa",
                                      "q_learning",      "expected_sarsa",   "dyna_q"};
typedef struct {
    Integer returns;
    int steps;
    const char *end;
    int *cells;
} Episode;
typedef struct {
    Integer returns, steps, endings[3], agree, error, coverage;
} Block;
typedef struct {
    Table q, visits;
    int *policy;
    Episode *episodes;
    Block *blocks;
} Learning;
static int ending_index(const char *end) {
    return !strcmp(end, "goal") ? 0 : !strcmp(end, "pit") ? 1 : 2;
}
static Integer visit_total(Table visits, int state) {
    Integer total = 0;
    for (int a = 0; a < 4; ++a)
        total += visits[state][a];
    return total;
}
static Learning learn(const Model *model, const Params *p, const Iteration *optimal, int method) {
    const World *w = model->world;
    Learning out = {0};
    out.q = allocate(w->n, sizeof *out.q);
    out.visits = allocate(w->n, sizeof *out.visits);
    out.episodes = allocate(p->episodes, sizeof *out.episodes);
    out.blocks = allocate(p->episodes / p->block, sizeof *out.blocks);
    Table sums = allocate(w->n, sizeof *sums), counts = allocate(w->n, sizeof *counts);
    Dyna dyna = dyna_create(w->n);
    Random random = {p->seed};
    Sample *samples = allocate(p->limit, sizeof *samples);
    for (int episode = 1; episode <= p->episodes; ++episode) {
        Integer alpha = schedule(p->alpha, episode), epsilon = schedule(p->epsilon, episode);
        int state = w->index[w->start], action = method == 1 ? choose(out.q, state, epsilon, &random) : 0;
        Episode *record = &out.episodes[episode - 1];
        if (episode == p->episodes) {
            record->cells = allocate((size_t)p->limit + 1, sizeof *record->cells);
            record->cells[0] = w->start;
        }
        int sample_count = 0;
        for (int t = 0; t < p->limit; ++t) {
            if (method != 1)
                action = choose(out.q, state, epsilon, &random);
            Outcome outcome = step(model, state, action, &random);
            int next_state = w->index[outcome.cell];
            ++out.visits[state][action];
            int next_action = 0;
            if (method == 0)
                samples[sample_count++] = (Sample){state, action, outcome.reward};
            else {
                Integer f = 0;
                if (next_state >= 0) {
                    if (method == 1) {
                        next_action = choose(out.q, next_state, epsilon, &random);
                        f = out.q[next_state][next_action];
                    } else
                        f = next_value(out.q, next_state, epsilon, method == 3);
                }
                td_update(model, out.q, state, action, outcome.cell, outcome.reward, p->gamma, alpha, f);
                if (method == 4) {
                    dyna_record(&dyna, state, action, outcome.cell, outcome.reward);
                    dyna_plan(&dyna, model, out.q, p->planning, p->gamma, alpha, &random);
                }
            }
            record->returns += outcome.reward;
            ++record->steps;
            if (episode == p->episodes)
                record->cells[record->steps] = outcome.cell;
            record->end = ending(w, outcome.cell);
            if (terminal(w, outcome.cell))
                break;
            state = next_state;
            if (method == 1)
                action = next_action;
        }
        if (method == 0)
            monte_carlo(samples, sample_count, out.q, sums, counts, w->n, p->gamma);
        if (episode % p->block == 0) {
            Block *block = &out.blocks[episode / p->block - 1];
            for (int j = episode - p->block; j < episode; ++j) {
                Episode e = out.episodes[j];
                block->returns += e.returns;
                block->steps += e.steps;
                ++block->endings[ending_index(e.end)];
            }
            for (int s = 0; s < w->n; ++s) {
                int a = first_maximum(out.q[s]);
                if (a == optimal->policy[s])
                    ++block->agree;
                block->error += absolute(out.q[s][a] - optimal->values[s]);
                if (visit_total(out.visits, s) > 0)
                    ++block->coverage;
            }
            block->error = floor_div(block->error, w->n);
        }
    }
    out.policy = greedy(out.q, w->n);
    free(samples);
    return out;
}
typedef struct {
    int *cells, count;
    const char *end;
} Path;
static Path path(const World *w, const int *policy, int origin, int limit) {
    Path out = {allocate((size_t)limit + 1, sizeof *out.cells), 1, NULL};
    out.cells[0] = origin;
    bool *seen = allocate((size_t)w->rows * w->cols, sizeof *seen);
    seen[origin] = true;
    for (;;) {
        int current = out.cells[out.count - 1], next = w->moves[w->index[current]][policy[w->index[current]]];
        bool repeated = seen[next];
        out.cells[out.count++] = next;
        if (terminal(w, next)) {
            out.end = ending(w, next);
            break;
        }
        if (repeated) {
            out.end = "loop";
            break;
        }
        if (out.count - 1 >= limit) {
            out.end = "limit";
            break;
        }
        seen[next] = true;
    }
    free(seen);
    return out;
}
static Integer *distances(const Model *model) {
    const World *w = model->world;
    int count = w->rows * w->cols;
    Integer *distance = allocate(count, sizeof *distance);
    for (int i = 0; i < count; ++i)
        distance[i] = -1;
    distance[w->start] = 0;
    int *queue = allocate(count, sizeof *queue), front = 0, end = 1;
    queue[0] = w->start;
    while (front < end) {
        int cell = queue[front++];
        if (terminal(w, cell))
            continue;
        for (int a = 0; a < 4; ++a) {
            Transitions ts = transitions(model, w->index[cell], a);
            for (int i = 0; i < ts.count; ++i) {
                int next = ts.data[i].cell;
                if (distance[next] < 0) {
                    distance[next] = distance[cell] + 1;
                    queue[end++] = next;
                }
            }
        }
    }
    free(queue);
    return distance;
}
static int differences(const int *a, const int *b, int count) {
    int result = 0;
    for (int s = 0; s < count; ++s)
        if (a[s] != b[s])
            ++result;
    return result;
}
typedef struct {
    Integer data[4];
} Four;
static Four absorption(const Model *model, const int *policy, int limit) {
    const World *w = model->world;
    Integer *goal = allocate(w->n, sizeof *goal), *pit = allocate(w->n, sizeof *pit),
            *expected = allocate(w->n, sizeof *expected), d = 100000000;
    for (int k = 0; k < limit; ++k) {
        Integer *ng = allocate(w->n, sizeof *ng), *np = allocate(w->n, sizeof *np),
                *ne = allocate(w->n, sizeof *ne);
        for (int s = 0; s < w->n; ++s) {
            Integer g = 0, p = 0, e = 0;
            Transitions ts = transitions(model, s, policy[s]);
            for (int i = 0; i < ts.count; ++i) {
                Transition t = ts.data[i];
                int next = w->index[t.cell];
                g += t.weight * (next < 0 ? (w->cells[t.cell] == 'G' ? d : 0) : goal[next]);
                p += t.weight * (next < 0 ? (w->cells[t.cell] == 'P' ? d : 0) : pit[next]);
                e += t.weight * (next < 0 ? 0 : expected[next]);
            }
            ng[s] = floor_div(g, model->q);
            np[s] = floor_div(p, model->q);
            ne[s] = d + floor_div(e, model->q);
        }
        free(goal);
        free(pit);
        free(expected);
        goal = ng;
        pit = np;
        expected = ne;
    }
    int start = w->index[w->start];
    Four result = {{floor_div(goal[start], 10000), floor_div(pit[start], 10000),
                    floor_div(d - goal[start] - pit[start], 10000), floor_div(expected[start], 10000)}};
    free(goal);
    free(pit);
    free(expected);
    return result;
}
static Evaluation behaviour(const Model *model, const int *policy, const Params *p) {
    const World *w = model->world;
    Integer *values = allocate(w->n, sizeof *values), epsilon = schedule(p->epsilon, p->episodes);
    int sweeps = 0;
    for (;;) {
        ++sweeps;
        Integer delta = 0;
        for (int s = 0; s < w->n; ++s) {
            Integer sum = 0;
            for (int a = 0; a < 4; ++a)
                sum += (epsilon + (a == policy[s] ? 4 * (1000 - epsilon) : 0)) *
                       bellman(model, values, s, a, p->gamma);
            Integer value = floor_div(sum, 4000), difference = absolute(value - values[s]);
            if (difference > delta)
                delta = difference;
            values[s] = value;
        }
        if (delta <= p->theta)
            return (Evaluation){values, sweeps};
    }
}
typedef struct {
    Integer returns, discounted, steps, endings[3], *terminals, *sorted_returns;
} Rollouts;
static int integer_compare(const void *a, const void *b) {
    Integer x = *(const Integer *)a, y = *(const Integer *)b;
    return x < y ? -1 : x > y;
}
static Rollouts rollout(const Model *model, const int *policy, const Params *p) {
    const World *w = model->world;
    Rollouts out = {0};
    out.terminals = allocate(w->nt, sizeof *out.terminals);
    out.sorted_returns = allocate(p->rollouts, sizeof *out.sorted_returns);
    Integer *rewards = allocate(p->limit, sizeof *rewards);
    Random random = {p->rollout_seed};
    for (int i = 0; i < p->rollouts; ++i) {
        int state = w->index[w->start], last = w->start, length = 0;
        Integer total = 0;
        for (int t = 0; t < p->limit; ++t) {
            Outcome outcome = step(model, state, policy[state], &random);
            last = outcome.cell;
            total += outcome.reward;
            rewards[length++] = outcome.reward;
            if (terminal(w, last))
                break;
            state = w->index[last];
        }
        out.returns += total;
        out.discounted += discounted(rewards, length, p->gamma);
        out.steps += length;
        ++out.endings[ending_index(ending(w, last))];
        if (terminal(w, last))
            ++out.terminals[w->terminal_index[last]];
        out.sorted_returns[i] = total;
    }
    free(rewards);
    qsort(out.sorted_returns, p->rollouts, sizeof *out.sorted_returns, integer_compare);
    return out;
}
static Lines policy_lines(const Model *model, const int *policy, const Learning *learning, int limit) {
    const World *w = model->world;
    Lines out = policy_grid(w, policy);
    Path route = path(w, policy, w->start, limit);
    line_add(&out, "path %s steps %d %s", route.end, route.count - 1,
             cells_text(w, route.cells, route.count));
    Integer counts[4] = {0}, risk = 0;
    char **basin = allocate(w->n, sizeof *basin);
    for (int s = 0; s < w->n; ++s) {
        ++counts[policy[s]];
        bool risky = false;
        Transitions ts = transitions(model, s, policy[s]);
        for (int i = 0; i < ts.count; ++i)
            if (w->cells[ts.data[i].cell] == 'P')
                risky = true;
        if (risky)
            ++risk;
        Path nominal = path(w, policy, w->states[s], limit);
        basin[s] = !strcmp(nominal.end, "goal") || !strcmp(nominal.end, "pit")
                       ? format("%c", 'a' + w->terminal_index[nominal.cells[nominal.count - 1]])
                       : "*";
    }
    line_add(&out, "actions N %s E %s S %s W %s risk %s", number(counts[0]), number(counts[1]),
             number(counts[2]), number(counts[3]), number(risk));
    line_add(&out, "basins");
    extend(&out, grid(w, basin, ""));
    if (learning) {
        line_add(&out, "visits");
        char **fields = allocate(w->n, sizeof *fields);
        for (int s = 0; s < w->n; ++s) {
            Integer count = visit_total(learning->visits, s);
            fields[s] = count ? number((Integer)strlen(number(count))) : "0";
        }
        extend(&out, grid(w, fields, ""));
    }
    return out;
}
typedef struct {
    int state;
    Integer visits;
} Visit;
static int visit_compare(const void *pa, const void *pb) {
    const Visit *a = pa, *b = pb;
    if (a->visits != b->visits)
        return a->visits > b->visits ? -1 : 1;
    return a->state < b->state ? -1 : a->state > b->state;
}
int main(void) {
    World w = read_world();
    Params p = read_params();
    Model model = {&w, p.q, p.floor_slip, p.ice_slip, p.step_reward};
    Iteration optimal = value_iteration(&model, p.gamma, p.theta);
    Evaluation inplace = in_place(&model, p.gamma, p.theta);
    PolicyIteration pi = policy_iteration(&model, p.gamma, p.theta);
    int start = w.index[w.start];
    Learning learning[5];
    for (int i = 0; i < 5; ++i)
        learning[i] = learn(&model, &p, &optimal, i);
    int *policies[7] = {optimal.policy,     pi.policy,          learning[0].policy, learning[1].policy,
                        learning[2].policy, learning[3].policy, learning[4].policy};
    Rollouts rollouts[7];
    for (int i = 0; i < 7; ++i)
        rollouts[i] = rollout(&model, policies[i], &p);
    Integer *distance = distances(&model);
    Lines value_parts[10] = {{0}};
    Integer kinds[5] = {0}, reachable = 0;
    for (int cell = 0; cell < w.rows * w.cols; ++cell) {
        char c = w.cells[cell];
        ++kinds[c == '#' ? 0 : c == '.' || c == 'S' ? 1 : c == '~' ? 2 : c == 'G' ? 3 : 4];
    }
    for (int s = 0; s < w.n; ++s)
        if (distance[w.states[s]] >= 0)
            ++reachable;
    line_add(&value_parts[0], "world rows %d cols %d states %d walls %s floor %s ice %s goals %s pits %s",
             w.rows, w.cols, w.n, number(kinds[0]), number(kinds[1]), number(kinds[2]), number(kinds[3]),
             number(kinds[4]));
    line_add(&value_parts[0], "start %s reachable %s", cell_text(&w, w.start), number(reachable));
    for (int i = 0; i < w.nt; ++i) {
        int cell = w.terminals[i];
        line_add(&value_parts[0], "terminal %s %s reward %s distance %s", cell_text(&w, cell),
                 ending(&w, cell), number(w.rewards[cell]),
                 distance[cell] < 0 ? "-" : number(distance[cell]));
    }
    line_add(&value_parts[1], "value_iteration gamma %s theta %s iterations %zu", number(p.gamma),
             fixed(p.theta), optimal.count);
    for (size_t i = 0; i < optimal.count; ++i)
        line_add(&value_parts[1], "iteration %zu max_change %s", i + 1, fixed(optimal.deltas[i]));
    line_add(&value_parts[2], "optimal_values");
    extend(&value_parts[2], value_grid(&w, optimal.values));
    line_add(&value_parts[3], "optimal_action_counts");
    char **counts = allocate(w.n, sizeof *counts), **sets = allocate(w.n, sizeof *sets);
    int ties = 0;
    for (int s = 0; s < w.n; ++s) {
        Integer best = optimal.actions[s][first_maximum(optimal.actions[s])];
        Text actions = {0};
        for (int a = 0; a < 4; ++a)
            if (optimal.actions[s][a] == best)
                text_add(&actions, "%c", "NESW"[a]);
        sets[s] = actions.data;
        counts[s] = number((Integer)actions.len);
        if (actions.len > 1)
            ++ties;
    }
    extend(&value_parts[3], grid(&w, counts, ""));
    line_add(&value_parts[4], "ties %d", ties);
    for (int s = 0; s < w.n; ++s)
        if (strlen(sets[s]) > 1)
            line_add(&value_parts[4], "tie %s %s", cell_text(&w, w.states[s]), sets[s]);
    Integer pairs = 0, equal_values = 0, mirrored = 0;
    int mirror[4] = {0, 3, 2, 1};
    for (int s = 0; s < w.n; ++s) {
        int cell = w.states[s], col = cell % w.cols, other = (cell / w.cols) * w.cols + w.cols - 1 - col;
        if (col >= w.cols - 1 - col || w.index[other] < 0)
            continue;
        ++pairs;
        int t = w.index[other];
        if (optimal.values[s] == optimal.values[t])
            ++equal_values;
        if (optimal.policy[t] == mirror[optimal.policy[s]])
            ++mirrored;
    }
    line_add(&value_parts[4], "symmetry pairs %s equal_values %s mirrored_actions %s", number(pairs),
             number(equal_values), number(mirrored));
    line_add(&value_parts[5], "policy_iteration rounds %zu", pi.count);
    Integer pi_sweeps = 0;
    for (size_t i = 0; i < pi.count; ++i) {
        Round r = pi.rounds[i];
        pi_sweeps += r.sweeps;
        line_add(&value_parts[5], "round %zu sweeps %d changed %d value_start %s", i + 1, r.sweeps, r.changed,
                 fixed(r.start));
    }
    line_add(&value_parts[6], "policy_iteration_values");
    extend(&value_parts[6], value_grid(&w, pi.values));
    Integer maximum = -1;
    int at = 0;
    for (int s = 0; s < w.n; ++s) {
        Integer difference = absolute(pi.values[s] - optimal.values[s]);
        if (difference > maximum) {
            maximum = difference;
            at = s;
        }
    }
    line_add(&value_parts[7], "comparison policy_differences %d max_value_difference %s at %s",
             differences(pi.policy, optimal.policy, w.n), fixed(maximum), cell_text(&w, w.states[at]));
    line_add(
        &value_parts[7], "backups value_iteration %s in_place_iterations %d in_place %s policy_iteration %s",
        number((Integer)optimal.count * w.n * 4), inplace.sweeps, number((Integer)inplace.sweeps * w.n * 4),
        number(pi_sweeps * w.n + (Integer)pi.count * w.n * 4));
    line_add(&value_parts[8], "gamma_sweep");
    for (size_t i = 0; i < p.gammas.len; ++i) {
        Integer gamma = p.gammas.data[i];
        Iteration result = value_iteration(&model, gamma, p.theta);
        Path route = path(&w, result.policy, w.start, p.limit);
        line_add(
            &value_parts[8], "gamma %s iterations %zu value_start %s path %s steps %d last %s differences %d",
            number(gamma), result.count, fixed(result.values[start]), route.end, route.count - 1,
            cell_text(&w, route.cells[route.count - 1]), differences(result.policy, optimal.policy, w.n));
    }
    line_add(&value_parts[9], "slip_sweep");
    for (size_t i = 0; i < p.slips.len; i += 2) {
        Model changed = {&w, p.q, p.slips.data[i], p.slips.data[i + 1], p.step_reward};
        Iteration result = value_iteration(&changed, p.gamma, p.theta);
        Path route = path(&w, result.policy, w.start, p.limit);
        line_add(&value_parts[9],
                 "slip %s %s iterations %zu value_start %s path %s steps %d last %s differences %d",
                 number(changed.floor_slip), number(changed.ice_slip), result.count,
                 fixed(result.values[start]), route.end, route.count - 1,
                 cell_text(&w, route.cells[route.count - 1]),
                 differences(result.policy, optimal.policy, w.n));
    }
    Lines policy_parts[7] = {{0}}, tables = {0}, curves = {0};
    for (int i = 0; i < 7; ++i) {
        line_add(&policy_parts[i], "%s", policy_names[i]);
        extend(&policy_parts[i],
               policy_lines(&model, policies[i], i >= 2 ? &learning[i - 2] : NULL, p.limit));
    }
    line_add(&tables, "method,row,col,action,value,visits");
    extend(&tables, q_rows(&w, "value_iteration", optimal.actions, NULL));
    line_add(&curves, "method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage");
    for (int m = 0; m < 5; ++m) {
        extend(&tables, q_rows(&w, method_names[m], learning[m].q, learning[m].visits));
        for (int b = 0; b < p.episodes / p.block; ++b) {
            Block block = learning[m].blocks[b];
            line_add(&curves, "%s,%d,%s,%s,%s,%s,%s,%s,%s,%s", method_names[m], b + 1,
                     average(block.returns, p.block), average(block.steps, p.block), number(block.endings[0]),
                     number(block.endings[1]), number(block.endings[2]), number(block.agree),
                     fixed(block.error), number(block.coverage));
        }
    }
    Lines evaluation[14] = {{0}};
    line_add(&evaluation[0], "summary states %d start %s rollouts %d step_limit %d", w.n,
             cell_text(&w, w.start), p.rollouts, p.limit);
    const char *headers[13][2] = {
        {"policies", "policy agree optimal_actions value_start sweeps max_gap at"},
        {"improvement", "policy changed value_start agree"},
        {"absorption", "policy p_goal p_pit p_timeout expected_steps"},
        {"behaviour", "method epsilon value_start sweeps"},
        {"q_errors", "method mean_abs max_abs at unvisited tied"},
        {"q_action_errors", "method N E S W"},
        {"rollouts", "policy mean_return mean_discounted mean_steps goals pits timeouts min median max"},
        {"terminals", NULL},
        {"agreement", "policy value_iteration policy_iteration mc sarsa q_learning expected_sarsa dyna_q"},
        {"training", "method steps goals pits timeouts best_block best_mean last_mean reach"},
        {"visited", NULL},
        {"last_episodes", NULL},
        {"phases", NULL}};
    for (int i = 0; i < 13; ++i) {
        line_add(&evaluation[i + 1], "%s", headers[i][0]);
        if (headers[i][1])
            line_add(&evaluation[i + 1], "%s", headers[i][1]);
    }
    Text terminal_header = {0};
    text_add(&terminal_header, "policy");
    for (int i = 0; i < w.nt; ++i)
        text_add(&terminal_header, " %s", cell_text(&w, w.terminals[i]));
    line_add(&evaluation[8], "%s", terminal_header.data);
    for (int i = 0; i < 7; ++i) {
        int *policy = policies[i];
        Evaluation evaluated = evaluate(&model, policy, allocate(w.n, sizeof(Integer)), p.gamma, p.theta);
        Integer agree = 0, optimal_actions = 0, max_gap = optimal.values[0] - evaluated.values[0];
        int gap_at = 0;
        for (int s = 0; s < w.n; ++s) {
            if (policy[s] == optimal.policy[s])
                ++agree;
            if (optimal.actions[s][policy[s]] == optimal.actions[s][optimal.policy[s]])
                ++optimal_actions;
            Integer gap = optimal.values[s] - evaluated.values[s];
            if (gap > max_gap) {
                max_gap = gap;
                gap_at = s;
            }
        }
        line_add(&evaluation[1], "%s %s %s %s %d %s %s", policy_names[i], number(agree),
                 number(optimal_actions), fixed(evaluated.values[start]), evaluated.sweeps, fixed(max_gap),
                 cell_text(&w, w.states[gap_at]));
        Table improved_actions = action_values(&model, evaluated.values, p.gamma);
        int *improved = greedy(improved_actions, w.n);
        Evaluation improved_value =
            evaluate(&model, improved, allocate(w.n, sizeof(Integer)), p.gamma, p.theta);
        line_add(&evaluation[2], "%s %d %s %d", policy_names[i], differences(policy, improved, w.n),
                 fixed(improved_value.values[start]), w.n - differences(improved, optimal.policy, w.n));
        Four absorbed = absorption(&model, policy, p.limit);
        line_add(&evaluation[3], "%s %s %s %s %s", policy_names[i], fixed(absorbed.data[0]),
                 fixed(absorbed.data[1]), fixed(absorbed.data[2]), fixed(absorbed.data[3]));
        Rollouts r = rollouts[i];
        line_add(&evaluation[7], "%s %s %s %s %s %s %s %s %s %s", policy_names[i],
                 average(r.returns, p.rollouts), fixed(floor_div(r.discounted, p.rollouts)),
                 average(r.steps, p.rollouts), number(r.endings[0]), number(r.endings[1]),
                 number(r.endings[2]), number(r.sorted_returns[0]),
                 number(r.sorted_returns[(p.rollouts - 1) / 2]), number(r.sorted_returns[p.rollouts - 1]));
        Text terminal_line = {0}, agreement_line = {0};
        text_add(&terminal_line, "%s", policy_names[i]);
        for (int t = 0; t < w.nt; ++t)
            text_add(&terminal_line, " %s", number(r.terminals[t]));
        line_add(&evaluation[8], "%s", terminal_line.data);
        text_add(&agreement_line, "%s", policy_names[i]);
        for (int j = 0; j < 7; ++j)
            text_add(&agreement_line, " %d", w.n - differences(policy, policies[j], w.n));
        line_add(&evaluation[9], "%s", agreement_line.data);
        if (i < 2)
            continue;
        int method = i - 2;
        Learning m = learning[method];
        Evaluation behavior = behaviour(&model, policy, &p);
        line_add(&evaluation[4], "%s %s %s %d", method_names[method], number(schedule(p.epsilon, p.episodes)),
                 fixed(behavior.values[start]), behavior.sweeps);
        Integer errors = 0, maximum_error = -1, unvisited = 0, tied = 0, action_errors[4] = {0},
                action_counts[4] = {0};
        int error_at = 0;
        for (int s = 0; s < w.n; ++s) {
            Integer best = m.q[s][first_maximum(m.q[s])], error = absolute(best - optimal.values[s]);
            errors += error;
            if (error > maximum_error) {
                maximum_error = error;
                error_at = s;
            }
            if (!visit_total(m.visits, s))
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
        line_add(&evaluation[5], "%s %s %s %s %s %s", method_names[method], fixed(floor_div(errors, w.n)),
                 fixed(maximum_error), cell_text(&w, w.states[error_at]), number(unvisited), number(tied));
        Text action_line = {0};
        text_add(&action_line, "%s", method_names[method]);
        for (int a = 0; a < 4; ++a)
            text_add(&action_line, " %s",
                     action_counts[a] ? fixed(floor_div(action_errors[a], action_counts[a])) : "-");
        line_add(&evaluation[6], "%s", action_line.data);
        Integer steps_total = 0, endings[3] = {0};
        for (int e = 0; e < p.episodes; ++e) {
            steps_total += m.episodes[e].steps;
            ++endings[ending_index(m.episodes[e].end)];
        }
        int best_block = 0, reach = -1, blocks = p.episodes / p.block;
        for (int b = 0; b < blocks; ++b) {
            if (m.blocks[b].returns > m.blocks[best_block].returns)
                best_block = b;
            if (reach < 0 &&
                10 * (Integer)p.rollouts * m.blocks[b].returns >= 9 * (Integer)p.block * rollouts[0].returns)
                reach = b + 1;
        }
        line_add(&evaluation[10], "%s %s %s %s %s %d %s %s %s", method_names[method], number(steps_total),
                 number(endings[0]), number(endings[1]), number(endings[2]), best_block + 1,
                 average(m.blocks[best_block].returns, p.block),
                 average(m.blocks[blocks - 1].returns, p.block), reach < 0 ? "-" : number(reach));
        Visit *visits = allocate(w.n, sizeof *visits);
        for (int s = 0; s < w.n; ++s)
            visits[s] = (Visit){s, visit_total(m.visits, s)};
        qsort(visits, w.n, sizeof *visits, visit_compare);
        line_add(&evaluation[11], "%s %s:%s %s:%s %s:%s", method_names[method],
                 cell_text(&w, w.states[visits[0].state]), number(visits[0].visits),
                 cell_text(&w, w.states[visits[1].state]), number(visits[1].visits),
                 cell_text(&w, w.states[visits[2].state]), number(visits[2].visits));
        Episode last = m.episodes[p.episodes - 1];
        line_add(&evaluation[12], "%s return %s steps %d end %s %s", method_names[method],
                 number(last.returns), last.steps, last.end, cells_text(&w, last.cells, last.steps + 1));
        Numbers phases = {0};
        for (size_t a = 0; a < p.alpha.len; a += 2) {
            grow((void **)&phases.data, &phases.cap, phases.len + 1, sizeof *phases.data);
            phases.data[phases.len++] = p.alpha.data[a];
        }
        for (size_t a = 0; a < p.epsilon.len; a += 2) {
            grow((void **)&phases.data, &phases.cap, phases.len + 1, sizeof *phases.data);
            phases.data[phases.len++] = p.epsilon.data[a];
        }
        qsort(phases.data, phases.len, sizeof *phases.data, integer_compare);
        size_t unique = 0;
        for (size_t a = 0; a < phases.len; ++a)
            if (!unique || phases.data[a] != phases.data[unique - 1])
                phases.data[unique++] = phases.data[a];
        phases.len = unique;
        grow((void **)&phases.data, &phases.cap, phases.len + 1, sizeof *phases.data);
        phases.data[phases.len++] = (Integer)p.episodes + 1;
        for (size_t phase = 0; phase + 1 < phases.len; ++phase) {
            int first = (int)phases.data[phase], last_episode = (int)phases.data[phase + 1] - 1;
            Integer returns = 0, steps_ = 0, goals = 0;
            for (int e = first; e <= last_episode; ++e) {
                Episode record = m.episodes[e - 1];
                returns += record.returns;
                steps_ += record.steps;
                if (!strcmp(record.end, "goal"))
                    ++goals;
            }
            line_add(&evaluation[13], "%s %d-%d alpha %s epsilon %s mean_return %s mean_steps %s goals %s",
                     method_names[method], first, last_episode, number(schedule(p.alpha, first)),
                     number(schedule(p.epsilon, first)), average(returns, last_episode - first + 1),
                     average(steps_, last_episode - first + 1), number(goals));
        }
    }
    write_lines("values.txt", parts(value_parts, 10));
    write_lines("policies.txt", parts(policy_parts, 7));
    write_lines("q_tables.csv", tables);
    write_lines("learning_curves.csv", curves);
    write_lines("evaluation.txt", parts(evaluation, 14));
    return 0;
}
