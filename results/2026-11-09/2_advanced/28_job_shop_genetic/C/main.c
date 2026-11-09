#include "scheduler.h"
static const char *rules[4] = {"SPT", "LPT", "MWKR", "FIFO"};
static int maximum(int a, int b) {
    return a > b ? a : b;
}
static int minimum(int a, int b) {
    return a < b ? a : b;
}
static bool earlier(const Instance *data, const Schedule *s, int a, int b) {
    return s->start[a] < s->start[b] ||
           (s->start[a] == s->start[b] && data->operations[a].job < data->operations[b].job);
}
static Sequence chronological(const Instance *data, const Schedule *s) {
    Sequence ids = {.count = data->count};
    for (int i = 0; i < data->count; ++i) {
        int at = i;
        while (at && earlier(data, s, i, ids.ids[at - 1])) {
            ids.ids[at] = ids.ids[at - 1];
            --at;
        }
        ids.ids[at] = i;
    }
    return ids;
}
Schedule from_starts(const Instance *data, const int *starts) {
    Schedule s = {0};
    for (int i = 0; i < data->count; ++i) {
        s.start[i] = starts[i];
        s.finish[i] = starts[i] + data->operations[i].duration;
        s.previous[i] = s.next[i] = -1;
        s.makespan = maximum(s.makespan, s.finish[i]);
    }
    Sequence ids = chronological(data, &s);
    for (int i = 0; i < ids.count; ++i) {
        int id = ids.ids[i];
        Sequence *seq = &s.order.machines[data->operations[id].machine];
        if (seq->count) {
            s.previous[id] = seq->ids[seq->count - 1];
            s.next[seq->ids[seq->count - 1]] = id;
        }
        seq->ids[seq->count++] = id;
    }
    return s;
}
Schedule schedule_order(const Instance *data, Order order, int inflated) {
    Schedule s = {.order = order};
    for (int i = 0; i < data->count; ++i)
        s.start[i] = s.previous[i] = s.next[i] = -1;
    for (int m = 0; m < data->machines; ++m) {
        Sequence seq = order.machines[m];
        for (int i = 1; i < seq.count; ++i) {
            s.previous[seq.ids[i]] = seq.ids[i - 1];
            s.next[seq.ids[i - 1]] = seq.ids[i];
        }
    }
    int remaining = data->count;
    while (remaining)
        for (int i = 0; i < data->count; ++i) {
            if (s.start[i] >= 0)
                continue;
            Operation op = data->operations[i];
            int a = op.previous, b = s.previous[i];
            if ((a >= 0 && s.start[a] < 0) || (b >= 0 && s.start[b] < 0))
                continue;
            s.start[i] = maximum(a < 0 ? 0 : s.finish[a], b < 0 ? 0 : s.finish[b]);
            s.finish[i] = s.start[i] + op.duration + (op.machine == inflated ? (op.duration + 9) / 10 : 0);
            s.makespan = maximum(s.makespan, s.finish[i]);
            --remaining;
        }
    return s;
}
Chromosome chromosome(const Instance *data, const Schedule *s) {
    Sequence order = chronological(data, s);
    Chromosome genes = {.count = data->count};
    for (int i = 0; i < order.count; ++i)
        genes.ids[i] = data->operations[order.ids[i]].job;
    return genes;
}
typedef struct {
    Integer seed;
    int population, generations, tournament, elites, iterations, tenure, width, cross_a, cross_b, swap_a,
        swap_b, insert_a, insert_b;
    int checkpoints[101], checkpoint_count;
} Params;
static Params read_params(void) {
    Params p = {0};
    FILE *f = fopen("input/ga_params.txt", "r");
    fscanf(f, "%*s %" SCNd64, &p.seed);
    fscanf(f, "%*s %d %*s %d %*s %d", &p.population, &p.generations, &p.tournament);
    fscanf(f, "%*s %d/%d %*s %d/%d %*s %d/%d", &p.cross_a, &p.cross_b, &p.swap_a, &p.swap_b, &p.insert_a,
           &p.insert_b);
    fscanf(f, "%*s %d", &p.elites);
    free(read_line(f));
    char *line = read_line(f), *field = strtok(line, " ");
    while ((field = strtok(NULL, " ")))
        p.checkpoints[p.checkpoint_count++] = atoi(field);
    free(line);
    fscanf(f, "%*s %d %*s %d %*s %d", &p.iterations, &p.tenure, &p.width);
    fclose(f);
    return p;
}
static char *percent(Integer a, Integer b) {
    Integer value = (2000 * a + b) / (2 * b);
    char *text = malloc(64);
    snprintf(text, 64, "%" PRId64 ".%" PRId64 "%%", value / 10, value % 10);
    return text;
}
typedef struct {
    Sequence path;
    int block_starts[100], block_lengths[100], block_count, bottleneck, slack[100], free_slack[100];
    Integer paths;
} Analysis;
static Analysis analyze(const Instance *data, const Schedule *s) {
    Analysis result = {0};
    int current = -1;
    for (int i = 0; i < data->count; ++i)
        if (s->finish[i] == s->makespan &&
            (current < 0 || data->operations[i].job < data->operations[current].job))
            current = i;
    for (;;) {
        result.path.ids[result.path.count++] = current;
        if (!s->start[current])
            break;
        int previous = s->previous[current];
        current = previous >= 0 && s->finish[previous] == s->start[current]
                      ? previous
                      : data->operations[current].previous;
    }
    for (int i = 0; i < result.path.count / 2; ++i) {
        int value = result.path.ids[i];
        result.path.ids[i] = result.path.ids[result.path.count - i - 1];
        result.path.ids[result.path.count - i - 1] = value;
    }
    int counts[10] = {0};
    for (int i = 0; i < result.path.count; ++i) {
        int machine = data->operations[result.path.ids[i]].machine;
        ++counts[machine];
        if (!i || data->operations[result.path.ids[i - 1]].machine != machine) {
            result.block_starts[result.block_count] = i;
            result.block_lengths[result.block_count++] = 0;
        }
        ++result.block_lengths[result.block_count - 1];
    }
    for (int m = 1; m < data->machines; ++m)
        if (counts[m] > counts[result.bottleneck])
            result.bottleneck = m;
    Sequence order = chronological(data, s);
    Integer paths[100] = {0};
    for (int i = 0; i < order.count; ++i) {
        int id = order.ids[i], a = data->operations[id].previous, b = s->previous[id];
        if (!s->start[id])
            paths[id] = 1;
        else {
            if (a >= 0 && s->finish[a] == s->start[id])
                paths[id] += paths[a];
            if (b >= 0 && s->finish[b] == s->start[id])
                paths[id] += paths[b];
        }
        if (s->finish[id] == s->makespan)
            result.paths += paths[id];
    }
    int latest[100] = {0};
    for (int i = order.count - 1; i >= 0; --i) {
        int id = order.ids[i], a = data->operations[id].next, b = s->next[id], limit = s->makespan,
            free_limit = s->makespan;
        if (a >= 0) {
            limit = minimum(limit, latest[a]);
            free_limit = minimum(free_limit, s->start[a]);
        }
        if (b >= 0) {
            limit = minimum(limit, latest[b]);
            free_limit = minimum(free_limit, s->start[b]);
        }
        latest[id] = limit - data->operations[id].duration;
        result.slack[id] = latest[id] - s->start[id];
        result.free_slack[id] = free_limit - s->finish[id];
    }
    return result;
}
typedef struct {
    int first, second;
} Move;
typedef struct {
    Move items[100];
    int count;
} Moves;
static Moves moves(const Analysis *a) {
    Moves result = {0};
    for (int b = 0; b < a->block_count; ++b)
        for (int i = 1; i < a->block_lengths[b]; ++i) {
            int at = a->block_starts[b] + i;
            result.items[result.count++] = (Move){a->path.ids[at - 1], a->path.ids[at]};
        }
    return result;
}
static Order swapped(const Instance *data, Order order, Move move) {
    Sequence *seq = &order.machines[data->operations[move.first].machine];
    int a = -1, b = -1;
    for (int i = 0; i < seq->count; ++i) {
        if (seq->ids[i] == move.first)
            a = i;
        if (seq->ids[i] == move.second)
            b = i;
    }
    int value = seq->ids[a];
    seq->ids[a] = seq->ids[b];
    seq->ids[b] = value;
    return order;
}
typedef struct {
    int number, count, tabu_count;
    Move move;
    bool tabu;
    int value, best;
} Iteration;
typedef struct {
    Schedule best;
    int found, count;
    const char *stop;
    Iteration iterations[100];
} Search;
static Search tabu_search(const Instance *data, const Schedule *start, const Params *p) {
    Search result = {.best = *start, .stop = "limit"};
    Schedule current = *start;
    int tabu[100][100] = {0};
    for (int it = 1; it <= p->iterations; ++it) {
        Analysis analysis = analyze(data, &current);
        Moves list = moves(&analysis);
        if (!list.count) {
            result.stop = "no_moves";
            break;
        }
        int selected = -1, value = INT_MAX, tabu_count = 0;
        bool chosen_tabu = false;
        for (int i = 0; i < list.count; ++i) {
            Move move = list.items[i];
            Schedule candidate = schedule_order(data, swapped(data, current.order, move), -1);
            bool forbidden = tabu[move.first][move.second] >= it;
            if (forbidden)
                ++tabu_count;
            if ((!forbidden || candidate.makespan < result.best.makespan) && candidate.makespan < value) {
                selected = i;
                value = candidate.makespan;
                chosen_tabu = forbidden;
            }
        }
        if (selected < 0) {
            result.stop = "all_tabu";
            break;
        }
        Move move = list.items[selected];
        current = schedule_order(data, swapped(data, current.order, move), -1);
        tabu[move.second][move.first] = it + p->tenure;
        if (value < result.best.makespan) {
            result.best = current;
            result.found = it;
        }
        result.iterations[result.count++] =
            (Iteration){it, list.count, tabu_count, move, chosen_tabu, value, result.best.makespan};
    }
    return result;
}
typedef struct {
    int operation, machine, position, insertion, old_start, new_start;
} Shift;
typedef struct {
    Shift *items;
    int count;
} Shifts;
static Shifts shiftable(const Instance *data, const Schedule *s) {
    Shifts result = {.items = malloc((size_t)data->count * sizeof(Shift))};
    for (int m = 0; m < data->machines; ++m) {
        Sequence seq = s->order.machines[m];
        for (int i = 1; i < seq.count; ++i) {
            int id = seq.ids[i], previous = data->operations[id].previous,
                ready = previous < 0 ? 0 : s->finish[previous];
            for (int gap = 0; gap < i; ++gap) {
                int start = maximum(ready, gap ? s->finish[seq.ids[gap - 1]] : 0);
                if (start + data->operations[id].duration <= s->start[seq.ids[gap]]) {
                    result.items[result.count++] = (Shift){id, m, i, gap, s->start[id], start};
                    break;
                }
            }
        }
    }
    return result;
}
static Schedule activate(const Instance *data, Schedule current, Shifts *history) {
    for (;;) {
        Shifts options = shiftable(data, &current);
        if (!options.count) {
            free(options.items);
            break;
        }
        int best = 0;
        for (int i = 1; i < options.count; ++i) {
            Shift a = options.items[i], b = options.items[best];
            if (a.old_start < b.old_start ||
                (a.old_start == b.old_start &&
                 data->operations[a.operation].job < data->operations[b.operation].job))
                best = i;
        }
        Shift shift = options.items[best];
        history->items = realloc(history->items, (size_t)(history->count + 1) * sizeof *history->items);
        history->items[history->count++] = shift;
        Order order = current.order;
        Sequence *seq = &order.machines[shift.machine];
        memmove(seq->ids + shift.insertion + 1, seq->ids + shift.insertion,
                (size_t)(shift.position - shift.insertion) * sizeof(int));
        seq->ids[shift.insertion] = shift.operation;
        current = schedule_order(data, order, -1);
        free(options.items);
    }
    return current;
}
static void distance(const Instance *data, const Schedule *a, const Schedule *b, int *result) {
    int positions[100] = {0};
    for (int m = 0; m < data->machines; ++m) {
        Sequence seq = b->order.machines[m];
        for (int i = 0; i < seq.count; ++i)
            positions[seq.ids[i]] = i;
    }
    for (int m = 0; m < data->machines; ++m) {
        result[m] = 0;
        Sequence seq = a->order.machines[m];
        for (int i = 0; i < seq.count; ++i)
            for (int j = i + 1; j < seq.count; ++j)
                if (positions[seq.ids[i]] > positions[seq.ids[j]])
                    ++result[m];
    }
}
static int sum(const int *values, int count) {
    int result = 0;
    for (int i = 0; i < count; ++i)
        result += values[i];
    return result;
}
static int flow(const Instance *data, const Schedule *s) {
    int total = 0;
    for (int j = 0; j < data->job_count; ++j) {
        Sequence seq = data->jobs[j].operations;
        total += s->finish[seq.ids[seq.count - 1]];
    }
    return total;
}
static int jackson(const Instance *data, int machine) {
    int ids[100], remaining[100], count = 0;
    for (int i = 0; i < data->count; ++i)
        if (data->operations[i].machine == machine) {
            ids[count] = i;
            remaining[count++] = data->operations[i].duration;
        }
    int time = 0, bound = 0, left = count;
    while (left) {
        int selected = -1, next = INT_MAX;
        for (int i = 0; i < count; ++i) {
            Operation op = data->operations[ids[i]];
            if (op.head > time)
                next = minimum(next, op.head);
            if (remaining[i] && op.head <= time &&
                (selected < 0 || op.tail > data->operations[ids[selected]].tail ||
                 (op.tail == data->operations[ids[selected]].tail &&
                  op.job < data->operations[ids[selected]].job)))
                selected = i;
        }
        if (selected < 0) {
            time = next;
            continue;
        }
        int amount = minimum(remaining[selected], next == INT_MAX ? remaining[selected] : next - time);
        time += amount;
        remaining[selected] -= amount;
        if (!remaining[selected]) {
            --left;
            bound = maximum(bound, time + data->operations[ids[selected]].tail);
        }
    }
    return bound;
}
typedef struct {
    int generation, value, individual;
} Record;
typedef struct {
    Schedule best;
    Chromosome genes, population[30];
    int values[30], rank[30], crossovers, swaps, inserts, record_count, progress_count;
    Record records[101];
    char *progress[101];
} GeneticResult;
static bool same_chromosome(Chromosome a, Chromosome b) {
    return a.count == b.count && !memcmp(a.ids, b.ids, (size_t)a.count * sizeof(int));
}
static Integer gcd(Integer a, Integer b) {
    while (b) {
        Integer next = a % b;
        a = b;
        b = next;
    }
    return a;
}
static GeneticResult run_genetic(const Instance *data, const Params *p, const Schedule *baselines) {
    GeneticResult result = {0};
    Minstd random = {p->seed};
    Chromosome basic = {0}, population[30];
    for (int j = 0; j < data->job_count; ++j)
        for (int i = 0; i < data->jobs[j].operations.count; ++i)
            basic.ids[basic.count++] = data->jobs[j].number;
    for (int i = 0; i < 4; ++i)
        population[i] = chromosome(data, baselines + i);
    for (int i = 4; i < p->population; ++i) {
        population[i] = basic;
        shuffle(&random, population + i);
    }
    int previous = INT_MAX;
    for (int generation = 0; generation <= p->generations; ++generation) {
        int values[30], rank[30];
        for (int i = 0; i < p->population; ++i) {
            Schedule s = decode(data, population + i);
            values[i] = s.makespan;
            int at = i;
            while (at && (values[i] < values[rank[at - 1]] ||
                          (values[i] == values[rank[at - 1]] && i < rank[at - 1]))) {
                rank[at] = rank[at - 1];
                --at;
            }
            rank[at] = i;
        }
        int best = rank[0];
        if (values[best] < previous)
            result.records[result.record_count++] = (Record){generation, values[best], best + 1};
        previous = values[best];
        bool checkpoint = false;
        for (int i = 0; i < p->checkpoint_count; ++i)
            if (p->checkpoints[i] == generation)
                checkpoint = true;
        if (checkpoint) {
            Integer total = 0;
            int distinct = 0, worst = 0;
            for (int i = 0; i < p->population; ++i) {
                total += values[i];
                worst = maximum(worst, values[i]);
                bool first = true;
                for (int j = 0; j < i; ++j)
                    if (same_chromosome(population[i], population[j]))
                        first = false;
                if (first)
                    ++distinct;
            }
            Integer divisor = gcd(total, p->population);
            char *line = malloc(128);
            snprintf(line, 128, "%d,%d,%" PRId64 "/%" PRId64 ",%d,%d", generation, values[best],
                     total / divisor, p->population / divisor, worst, distinct);
            result.progress[result.progress_count++] = line;
        }
        if (generation == p->generations) {
            memcpy(result.population, population, (size_t)p->population * sizeof *population);
            memcpy(result.values, values, (size_t)p->population * sizeof *values);
            memcpy(result.rank, rank, (size_t)p->population * sizeof *rank);
            result.genes = population[best];
            result.best = decode(data, &result.genes);
            break;
        }
        Chromosome next[30];
        int count = 0;
        for (int i = 0; i < p->elites; ++i)
            next[count++] = population[rank[i]];
        while (count < p->population) {
            int first = tournament(&random, values, p->population, p->tournament),
                second = tournament(&random, values, p->population, p->tournament);
            Chromosome a = population[first], b = population[second];
            if (chance(&random, p->cross_a, p->cross_b)) {
                ++result.crossovers;
                crossover(&random, data, population + first, population + second, &a, &b);
            }
            Chromosome *children[2] = {&a, &b};
            for (int i = 0; i < 2; ++i) {
                if (chance(&random, p->swap_a, p->swap_b)) {
                    ++result.swaps;
                    swap_mutation(&random, children[i]);
                }
                if (chance(&random, p->insert_a, p->insert_b)) {
                    ++result.inserts;
                    insertion_mutation(&random, children[i]);
                }
            }
            next[count++] = a;
            next[count++] = b;
        }
        memcpy(population, next, (size_t)p->population * sizeof *next);
    }
    return result;
}
static void genes_line(FILE *out, const char *label, Chromosome genes) {
    fputs(label, out);
    for (int i = 0; i < genes.count; ++i)
        fprintf(out, " %d", genes.ids[i]);
    fputc('\n', out);
}
static char *letters(const Instance *data, Sequence seq) {
    char *result = malloc((size_t)seq.count + 1);
    for (int i = 0; i < seq.count; ++i)
        result[i] = (char)('A' + data->operations[seq.ids[i]].job - 1);
    result[seq.count] = 0;
    return result;
}
static void write_baselines(const Instance *data, const Schedule *baselines, const Search *searches,
                            int lower, const int *jackson_bounds, int job_bound, int job_number,
                            int machine_bound, int machine_number, int jackson_bound, int jackson_machine) {
    FILE *out = fopen("output/baselines.txt", "w");
    fprintf(out, "INSTANCE jobs %d machines %d operations %d work %d errors %d\n", data->job_count,
            data->machines, data->count, data->work, data->error_count);
    for (int i = 0; i < data->error_count; ++i)
        fprintf(out, "ERROR %s\n", data->errors[i]);
    for (int j = 0; j < data->job_count; ++j) {
        Job job = data->jobs[j];
        fprintf(out, "JOB J%d operations %d work %d route", job.number, job.operations.count, job.work);
        for (int i = 0; i < job.operations.count; ++i)
            fprintf(out, " M%d", data->operations[job.operations.ids[i]].machine + 1);
        fputc('\n', out);
    }
    for (int m = 0; m < data->machines; ++m) {
        Machine machine = data->machine[m];
        fprintf(out, "MACHINE M%d operations %d load %d head %d tail %d bound %d jackson %d\n", m + 1,
                machine.count, machine.load, machine.head, machine.tail, machine.bound, jackson_bounds[m]);
    }
    fprintf(out, "BOUND job %d J%d\nBOUND machine %d M%d\nBOUND jackson %d M%d\nBOUND lower %d\n", job_bound,
            job_number, machine_bound, machine_number, jackson_bound, jackson_machine, lower);
    int best = 0;
    for (int r = 0; r < 4; ++r) {
        const Schedule *s = baselines + r;
        Analysis a = analyze(data, s);
        const Search *search = searches + r;
        if (s->makespan < baselines[best].makespan)
            best = r;
        fprintf(out, "RULE %s makespan %d gap %s flow %d idle %d decisions %d ties %d\n", rules[r],
                s->makespan, percent(s->makespan - lower, lower), flow(data, s),
                data->machines * s->makespan - data->work, s->decisions, s->ties);
        fprintf(out, "PATH %s operations %d blocks %d critical_paths %" PRId64 " bottleneck M%d\n", rules[r],
                a.path.count, a.block_count, a.paths, a.bottleneck + 1);
        fprintf(out, "TABU %s makespan %d -> %d found %d iterations %d stop %s\n", rules[r], s->makespan,
                search->best.makespan, search->found, search->count, search->stop);
    }
    fprintf(out, "BEST %s makespan %d\n", rules[best], baselines[best].makespan);
    for (int m = 0; m < data->machines; ++m) {
        fprintf(out, "UTILIZATION M%d", m + 1);
        for (int r = 0; r < 4; ++r)
            fprintf(out, " %s %s", rules[r], percent(data->machine[m].load, baselines[r].makespan));
        fputc('\n', out);
    }
    fclose(out);
}
static void write_schedule(const Instance *data, const Params *p, const Schedule *baselines,
                           const GeneticResult *ga, const Schedule *active_decode, const Schedule *activated,
                           Shifts shifts, const Schedule *final, const Analysis *analysis, int lower) {
    FILE *out = fopen("output/best_schedule.txt", "w");
    fprintf(out, "GA best %d generation %d crossovers %d swaps %d inserts %d\n", ga->best.makespan,
            ga->records[ga->record_count - 1].generation, ga->crossovers, ga->swaps, ga->inserts);
    for (int i = 0; i < ga->record_count; ++i) {
        Record r = ga->records[i];
        fprintf(out, "RECORD generation %d makespan %d individual %d\n", r.generation, r.value, r.individual);
    }
    Chromosome seen[30];
    int top = 0;
    for (int i = 0; i < p->population && top < 5; ++i) {
        int individual = ga->rank[i];
        bool distinct = true;
        for (int j = 0; j < top; ++j)
            if (same_chromosome(ga->population[individual], seen[j]))
                distinct = false;
        if (!distinct)
            continue;
        seen[top++] = ga->population[individual];
        Schedule decoded = decode(data, ga->population + individual);
        int distances[10];
        distance(data, &decoded, &ga->best, distances);
        fprintf(out, "TOP %d individual %d makespan %d distance %d\n", top, individual + 1,
                ga->values[individual], sum(distances, data->machines));
    }
    genes_line(out, "GA_CHROMOSOME", ga->genes);
    fprintf(out, "ACTIVE_DECODE makespan %d decisions %d\n", active_decode->makespan,
            active_decode->decisions);
    for (int i = 0; i < shifts.count; ++i) {
        Shift s = shifts.items[i];
        fprintf(out, "SHIFT %d %s M%d start %d -> %d\n", i + 1, notation(data->operations[s.operation]),
                s.machine + 1, s.old_start, s.new_start);
    }
    fprintf(out, "ACTIVATED makespan %d -> %d shifts %d\n", ga->best.makespan, activated->makespan,
            shifts.count);
    Shifts options = shiftable(data, final);
    fprintf(out, "SCHEDULE makespan %d lower_bound %d gap %s improvement %d shiftable %d\n", final->makespan,
            lower, percent(final->makespan - lower, lower), ga->best.makespan - final->makespan,
            options.count);
    free(options.items);
    genes_line(out, "CHROMOSOME", chromosome(data, final));
    fputs("LEGEND", out);
    for (int j = 0; j < data->job_count; ++j)
        fprintf(out, " %c=J%d", 'A' + data->jobs[j].number - 1, data->jobs[j].number);
    fputc('\n', out);
    Chart chart = gantt(data, final, &analysis->path, p->width);
    fprintf(out, "GANTT scale %d columns %d\n", chart.scale, chart.columns);
    for (int i = 0; i < chart.count; ++i) {
        fprintf(out, "%s\n", chart.lines[i]);
        free(chart.lines[i]);
    }
    for (int m = 0; m < data->machines; ++m) {
        fprintf(out, "ORDER M%d FINAL %s", m + 1, letters(data, final->order.machines[m]));
        for (int r = 0; r < 4; ++r)
            fprintf(out, " %s %s", rules[r], letters(data, baselines[r].order.machines[m]));
        fputc('\n', out);
    }
    for (int m = 0; m < data->machines; ++m) {
        Sequence seq = final->order.machines[m];
        int gaps = 0, longest = 0, idle_start[101], idle_end[101], idle_count = 0, previous = 0;
        for (int i = 0; i < seq.count; ++i) {
            int id = seq.ids[i];
            if (final->start[id] > previous) {
                idle_start[idle_count] = previous;
                idle_end[idle_count++] = final->start[id];
                if (i) {
                    ++gaps;
                    longest = maximum(longest, final->start[id] - previous);
                }
            }
            previous = final->finish[id];
        }
        if (previous < final->makespan) {
            idle_start[idle_count] = previous;
            idle_end[idle_count++] = final->makespan;
        }
        fprintf(out, "MACHINE M%d load %d idle %d utilization %s gaps %d longest_gap %d sequence", m + 1,
                data->machine[m].load, final->makespan - data->machine[m].load,
                percent(data->machine[m].load, final->makespan), gaps, longest);
        for (int i = 0; i < seq.count; ++i) {
            int id = seq.ids[i];
            fprintf(out, " J%d:%d-%d", data->operations[id].job, final->start[id], final->finish[id]);
        }
        fprintf(out, "\nIDLE M%d", m + 1);
        if (!idle_count)
            fputs(" none", out);
        for (int i = 0; i < idle_count; ++i)
            fprintf(out, " %d-%d", idle_start[i], idle_end[i]);
        fputc('\n', out);
    }
    for (int j = 0; j < data->job_count; ++j) {
        Job job = data->jobs[j];
        int first = job.operations.ids[0], last = job.operations.ids[job.operations.count - 1];
        fprintf(out, "JOB J%d operations %d work %d start %d completion %d waiting %d\n", job.number,
                job.operations.count, job.work, final->start[first], final->finish[last],
                final->finish[last] - job.work);
    }
    fprintf(out, "TOTAL flow %d waiting %d idle %d\n", flow(data, final), flow(data, final) - data->work,
            data->machines * final->makespan - data->work);
    int distances[5][10], pairs_total = 0;
    for (int r = 0; r < 4; ++r)
        distance(data, final, baselines + r, distances[r]);
    distance(data, final, &ga->best, distances[4]);
    for (int m = 0; m < data->machines; ++m) {
        int q = data->machine[m].count, pairs = q * (q - 1) / 2;
        pairs_total += pairs;
        fprintf(out, "DISTANCE M%d pairs %d", m + 1, pairs);
        for (int r = 0; r < 5; ++r)
            fprintf(out, " %s %d", r < 4 ? rules[r] : "GA", distances[r][m]);
        fputc('\n', out);
    }
    fprintf(out, "DISTANCE total pairs %d", pairs_total);
    for (int r = 0; r < 5; ++r)
        fprintf(out, " %s %d", r < 4 ? rules[r] : "GA", sum(distances[r], data->machines));
    fputc('\n', out);
    fclose(out);
}
static void write_critical(const Instance *data, const Params *p, const Schedule *activated,
                           const Search *search, const Analysis *a) {
    FILE *out = fopen("output/critical_path.txt", "w");
    const Schedule *final = &search->best;
    fprintf(out, "SEARCH start %d iterations %d tenure %d\n", activated->makespan, p->iterations, p->tenure);
    for (int i = 0; i < search->count; ++i) {
        Iteration it = search->iterations[i];
        Operation first = data->operations[it.move.first], second = data->operations[it.move.second];
        fprintf(out, "ITER %d moves %d tabu %d swap M%d %s %s %s makespan %d best %d\n", it.number, it.count,
                it.tabu_count, first.machine + 1, notation(first), notation(second),
                it.tabu ? "aspiration" : "free", it.value, it.best);
    }
    fprintf(out, "STOP iterations %d reason %s best %d found %d\n", search->count, search->stop,
            final->makespan, search->found);
    fprintf(out, "PATH operations %d blocks %d makespan %d critical_paths %" PRId64 "\n", a->path.count,
            a->block_count, final->makespan, a->paths);
    for (int i = 0; i < a->path.count; ++i) {
        int id = a->path.ids[i];
        fprintf(out, "NODE %d %s M%d %d-%d %s\n", i + 1, notation(data->operations[id]),
                data->operations[id].machine + 1, final->start[id], final->finish[id],
                !i                                          ? "start"
                : final->previous[id] == a->path.ids[i - 1] ? "machine"
                                                            : "job");
    }
    for (int i = 0; i < a->block_count; ++i) {
        int first = a->path.ids[a->block_starts[i]],
            last = a->path.ids[a->block_starts[i] + a->block_lengths[i] - 1];
        fprintf(out, "BLOCK %d M%d %d-%d", i + 1, data->operations[first].machine + 1, final->start[first],
                final->finish[last]);
        for (int j = 0; j < a->block_lengths[i]; ++j)
            fprintf(out, " %s", notation(data->operations[a->path.ids[a->block_starts[i] + j]]));
        fputc('\n', out);
    }
    Moves neighbours = moves(a);
    for (int i = 0; i < neighbours.count; ++i) {
        Move move = neighbours.items[i];
        Schedule candidate = schedule_order(data, swapped(data, final->order, move), -1);
        fprintf(out, "NEIGHBOUR %d M%d %s %s makespan %d\n", i + 1, data->operations[move.first].machine + 1,
                notation(data->operations[move.first]), notation(data->operations[move.second]),
                candidate.makespan);
    }
    int count = 0;
    for (int i = 0; i < data->count; ++i)
        if (!a->slack[i])
            ++count;
    fprintf(out, "CRITICAL operations %d total %d\n", count, data->count);
    for (int j = 0; j < data->job_count; ++j) {
        Job job = data->jobs[j];
        fprintf(out, "SLACK J%d", job.number);
        for (int i = 0; i < job.operations.count; ++i)
            fprintf(out, " %d", a->slack[job.operations.ids[i]]);
        fputc('\n', out);
    }
    for (int j = 0; j < data->job_count; ++j) {
        Job job = data->jobs[j];
        fprintf(out, "FREE J%d", job.number);
        for (int i = 0; i < job.operations.count; ++i)
            fprintf(out, " %d", a->free_slack[job.operations.ids[i]]);
        fputc('\n', out);
    }
    int bottleneck_count = 0;
    for (int m = 0; m < data->machines; ++m) {
        int critical = 0, path = 0;
        Sequence seq = final->order.machines[m];
        for (int i = 0; i < seq.count; ++i)
            if (!a->slack[seq.ids[i]])
                ++critical;
        for (int i = 0; i < a->path.count; ++i)
            if (data->operations[a->path.ids[i]].machine == m)
                ++path;
        Schedule sensitivity = schedule_order(data, final->order, m);
        fprintf(out, "MACHINE M%d critical %d path %d sensitivity %d delta %d\n", m + 1, critical, path,
                sensitivity.makespan, sensitivity.makespan - final->makespan);
        if (m == a->bottleneck)
            bottleneck_count = path;
    }
    fprintf(out, "BOTTLENECK M%d path %d\n", a->bottleneck + 1, bottleneck_count);
    fclose(out);
}
int main(void) {
    Instance data = read_instance();
    Params p = read_params();
    mkdir("output", 0777);
    int jackson_bounds[10], job_bound = 0, job_number = 0, machine_bound = 0, machine_number = 0,
                            jackson_bound = 0, jackson_machine = 0;
    for (int j = 0; j < data.job_count; ++j)
        if (data.jobs[j].work > job_bound) {
            job_bound = data.jobs[j].work;
            job_number = data.jobs[j].number;
        }
    for (int m = 0; m < data.machines; ++m) {
        jackson_bounds[m] = jackson(&data, m);
        if (data.machine[m].bound > machine_bound) {
            machine_bound = data.machine[m].bound;
            machine_number = m + 1;
        }
        if (jackson_bounds[m] > jackson_bound) {
            jackson_bound = jackson_bounds[m];
            jackson_machine = m + 1;
        }
    }
    int lower = maximum(maximum(job_bound, machine_bound), jackson_bound);
    Schedule baselines[4];
    Search searches[4];
    for (int r = 0; r < 4; ++r) {
        baselines[r] = dispatch(&data, rules[r], NULL);
        searches[r] = tabu_search(&data, baselines + r, &p);
    }
    write_baselines(&data, baselines, searches, lower, jackson_bounds, job_bound, job_number, machine_bound,
                    machine_number, jackson_bound, jackson_machine);
    GeneticResult ga = run_genetic(&data, &p, baselines);
    FILE *progress = fopen("output/ga_progress.csv", "w");
    fputs("generation,best,mean,worst,distinct\n", progress);
    for (int i = 0; i < ga.progress_count; ++i)
        fprintf(progress, "%s\n", ga.progress[i]);
    fclose(progress);
    Schedule active_decode = dispatch(&data, "GENES", &ga.genes);
    Shifts shifts = {0};
    Schedule activated = activate(&data, ga.best, &shifts);
    Search search = tabu_search(&data, &activated, &p);
    Analysis analysis = analyze(&data, &search.best);
    write_schedule(&data, &p, baselines, &ga, &active_decode, &activated, shifts, &search.best, &analysis,
                   lower);
    write_critical(&data, &p, &activated, &search, &analysis);
    free(shifts.items);
    return 0;
}
