#include "sat.h"
#include <sys/stat.h>
typedef struct {
    Preprocess reduced;
    Model *models;
    int model_count, rounds, removed;
    Statistics stats;
    Lines trace;
    const char *stop;
} Solution;
static const char *status(const Solution *solution) {
    return solution->model_count ? "SAT" : "UNSAT";
}
static Solution solve(const Formula *formula, int limit) {
    Solution out = {.stop = "preprocess"};
    out.reduced = preprocess(formula, limit == 1);
    out.removed = removed_count(&out.reduced);
    if (out.reduced.conflict)
        return out;
    out.models = resize(NULL, (size_t)limit * sizeof(Model));
    Formula clauses = {.variables = formula->variables};
    for (int i = 0; i < out.reduced.count; ++i)
        formula_push(&clauses, int_copy(&out.reduced.clauses[i].literals));
    while (out.model_count < limit) {
        ++out.rounds;
        Round round = dpll_round(&clauses);
        stats_add(&out.stats, &round.stats);
        if (out.rounds == 1)
            append_lines(&out.trace, &round.events);
        free_lines(&round.events);
        if (!round.sat) {
            out.stop = "all";
            formula_free(&clauses);
            return out;
        }
        Model model = round.values;
        Clause block = {0};
        for (int x = 1; x <= formula->variables; ++x) {
            if (out.reduced.fixed.values[x] >= 0)
                model.values[x] = out.reduced.fixed.values[x];
            else
                int_push(&block, model.values[x] ? -x : x);
        }
        out.models[out.model_count++] = model;
        formula_push(&clauses, block);
    }
    out.stop = "limit";
    formula_free(&clauses);
    return out;
}
static void solution_free(Solution *solution) {
    preprocess_free(&solution->reduced);
    free(solution->models);
    free_lines(&solution->trace);
    *solution = (Solution){0};
}
static int edge_compare(const void *left, const void *right) {
    const Edge *a = left, *b = right;
    return a->a != b->a ? (a->a > b->a) - (a->a < b->a) : (a->b > b->b) - (a->b < b->b);
}
static int read_graphs(Graph *graphs) {
    Lines lines = read_lines("input/graphs.txt");
    int count = 0;
    for (int i = 0; i < lines.count; ++i) {
        if (!lines.data[i][0] || lines.data[i][0] == '#')
            continue;
        Lines header = words(lines.data[i]);
        Graph graph = {.name = text(header.data[1]), .vertices = atoi(header.data[2])};
        free_lines(&header);
        while (++i < lines.count && strcmp(lines.data[i], "END")) {
            if (graph.error)
                continue;
            Lines tokens = words(lines.data[i]);
            const char *reason = NULL;
            if (tokens.count != 2 || !well_number(tokens.data[0]) || !well_number(tokens.data[1]))
                reason = "bad edge line";
            else {
                int a = atoi(tokens.data[0]), b = atoi(tokens.data[1]);
                if (a < 1 || a > graph.vertices || b < 1 || b > graph.vertices)
                    reason = "vertex out of range";
                else if (a == b)
                    reason = "self loop";
                else {
                    if (a > b) {
                        int temporary = a;
                        a = b;
                        b = temporary;
                    }
                    for (int e = 0; e < graph.edge_count; ++e)
                        if (graph.edges[e].a == a && graph.edges[e].b == b)
                            reason = "duplicate edge";
                    if (!reason) {
                        graph.edges[graph.edge_count++] = (Edge){a, b};
                        ++graph.degrees[a];
                        ++graph.degrees[b];
                    }
                }
            }
            if (reason)
                graph.error = format("%s at line %d", reason, i + 1);
            free_lines(&tokens);
        }
        qsort(graph.edges, (size_t)graph.edge_count, sizeof(Edge), edge_compare);
        graphs[count++] = graph;
    }
    free_lines(&lines);
    return count;
}
static IntList greedy(const Graph *graph) {
    int order[30], colors[31] = {0};
    for (int i = 0; i < graph->vertices; ++i)
        order[i] = i + 1;
    for (int i = 1; i < graph->vertices; ++i) {
        int vertex = order[i], j = i;
        while (j > 0 && (graph->degrees[order[j - 1]] < graph->degrees[vertex] ||
                         (graph->degrees[order[j - 1]] == graph->degrees[vertex] && order[j - 1] > vertex))) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = vertex;
    }
    for (int i = 0; i < graph->vertices; ++i) {
        int vertex = order[i];
        bool used[31] = {0};
        for (int e = 0; e < graph->edge_count; ++e) {
            Edge edge = graph->edges[e];
            if (edge.a == vertex)
                used[colors[edge.b]] = true;
            if (edge.b == vertex)
                used[colors[edge.a]] = true;
        }
        int color = 1;
        while (used[color])
            ++color;
        colors[vertex] = color;
    }
    IntList out = {0};
    for (int x = 1; x <= graph->vertices; ++x)
        int_push(&out, colors[x]);
    return out;
}
static int maximum(const IntList *values) {
    int greatest = 0;
    for (int i = 0; i < values->count; ++i)
        if (values->data[i] > greatest)
            greatest = values->data[i];
    return greatest;
}
static char *graph_line(const Graph *graph) {
    IntList colors = greedy(graph);
    int degree = 0;
    for (int x = 1; x <= graph->vertices; ++x)
        if (graph->degrees[x] > degree)
            degree = graph->degrees[x];
    char *out = format("graph vertices=%d edges=%d max_degree=%d greedy=%d", graph->vertices,
                       graph->edge_count, degree, maximum(&colors));
    int_free(&colors);
    return out;
}
typedef enum { SOLVE, ENUM, CORE, QUEENS, PIGEON, COLOR, CHROMATIC } Command;
static const char *commands[] = {"SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC"};
typedef struct {
    Command command;
    char *error;
    int a, b, limit;
    const Graph *graph;
    Formula formula;
} Job;
static Job validate(const Lines *tokens, const Graph *graphs, int graph_count) {
    Job job = {.limit = 1};
    int command = -1;
    for (int i = 0; i < 7; ++i)
        if (!strcmp(tokens->data[0], commands[i]))
            command = i;
    if (command < 0) {
        job.error = format("unknown command %s", tokens->data[0]);
        return job;
    }
    job.command = (Command)command;
    const int arguments[] = {1, 2, 1, 2, 3, 3, 2};
    if (tokens->count != arguments[command] + 1) {
        job.error = text("wrong argument count");
        return job;
    }
    bool file = command <= CORE, graph = command == COLOR || command == CHROMATIC;
    for (int i = 1; i < tokens->count; ++i) {
        const char *token = tokens->data[i];
        if (i == 1 && file) {
            size_t length = strlen(token);
            bool valid = length >= 5 && length <= 24 && !strcmp(token + length - 4, ".cnf");
            if (valid)
                for (size_t j = 0; j < length - 4; ++j) {
                    char c = token[j];
                    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'))
                        valid = false;
                }
            if (!valid) {
                job.error = format("bad file name %s", token);
                return job;
            }
        } else if (i == 1 && graph) {
            for (int g = 0; g < graph_count; ++g)
                if (!strcmp(graphs[g].name, token))
                    job.graph = &graphs[g];
            if (!job.graph)
                job.error = format("unknown graph %s", token);
            else if (job.graph->error)
                job.error = format("invalid graph %s: %s", token, job.graph->error);
            if (job.error)
                return job;
        } else {
            if (!well_number(token)) {
                job.error = format("bad number %s", token);
                return job;
            }
            int value = atoi(token);
            bool limit = (command == ENUM && i == 2) || (command == QUEENS && i == 2) ||
                         ((command == PIGEON || command == COLOR) && i == 3);
            int upper = limit ? 200 : graph ? 6 : 8;
            if (value < 1 || value > upper) {
                job.error = format("out of range %s", token);
                return job;
            }
            if (limit)
                job.limit = value;
            else if (command == PIGEON && i == 2)
                job.b = value;
            else
                job.a = value;
        }
    }
    if (file) {
        CnfInput input = read_cnf(tokens->data[1]);
        job.formula = input.formula;
        job.error = input.error;
    } else if (command == QUEENS)
        job.formula = queens_formula(job.a);
    else if (command == PIGEON)
        job.formula = pigeon_formula(job.a, job.b);
    else if (command == COLOR)
        job.formula = color_formula(job.graph, job.a);
    return job;
}
static int true_count(const Clause *clause, const Model *model) {
    int count = 0;
    for (int i = 0; i < clause->count; ++i) {
        int literal = clause->data[i];
        if (model->values[abs(literal)] == (literal > 0))
            ++count;
    }
    return count;
}
static bool satisfied(const Formula *formula, const Model *model) {
    for (int i = 0; i < formula->count; ++i)
        if (!true_count(&formula->clauses[i], model))
            return false;
    return true;
}
static void analysis(Lines *lines, const Formula *formula, const Solution *solution, bool extended) {
    if (!solution->model_count)
        return;
    int bad_model = 0, bad_clause = 0;
    for (int i = 0; i < solution->model_count && !bad_model; ++i)
        for (int j = 0; j < formula->count; ++j)
            if (!true_count(&formula->clauses[j], &solution->models[i])) {
                bad_model = i + 1;
                bad_clause = j + 1;
                break;
            }
    if (bad_model)
        line_push(lines, format("verify failed model=%d clause=%d", bad_model, bad_clause));
    else {
        int counts[201] = {0};
        for (int i = 0; i < formula->count; ++i)
            ++counts[true_count(&formula->clauses[i], &solution->models[0])];
        char *frequency = frequency_list(counts, 201);
        line_push(lines, format("verify ok models=%d clauses=%d true_literals=%s", solution->model_count,
                                formula->count, frequency));
        free(frequency);
    }
    IntList flips = {0};
    Model model = solution->models[0];
    for (int x = 1; x <= formula->variables; ++x) {
        model.values[x] = 1 - model.values[x];
        if (satisfied(formula, &model))
            int_push(&flips, x);
        model.values[x] = 1 - model.values[x];
    }
    char *list = number_list(&flips);
    line_push(lines, format("flips safe=%d variables=%s", flips.count, list));
    free(list);
    int_free(&flips);
    if (extended && solution->model_count >= 2) {
        int pairs = 0, minimum = formula->variables, greatest = 0;
        for (int i = 0; i < solution->model_count; ++i)
            for (int j = i + 1; j < solution->model_count; ++j) {
                int distance = 0;
                for (int x = 1; x <= formula->variables; ++x)
                    if (solution->models[i].values[x] != solution->models[j].values[x])
                        ++distance;
                ++pairs;
                if (distance < minimum)
                    minimum = distance;
                if (distance > greatest)
                    greatest = distance;
            }
        line_push(lines,
                  format("diversity pairs=%d min_distance=%d max_distance=%d", pairs, minimum, greatest));
    }
    if (extended && !strcmp(solution->stop, "all")) {
        IntList backbone = {0};
        for (int x = 1; x <= formula->variables; ++x) {
            bool same = true;
            for (int i = 0; i < solution->model_count; ++i)
                if (solution->models[i].values[x] != model.values[x])
                    same = false;
            if (same)
                int_push(&backbone, model.values[x] ? x : -x);
        }
        list = number_list(&backbone);
        line_push(lines, format("backbone size=%d literals=%s", backbone.count, list));
        free(list);
        int_free(&backbone);
    }
}
static char *search_line(const Statistics *stats) {
    return format("search decisions=%d propagations=%d conflicts=%d max_depth=%d", stats->decisions,
                  stats->propagations, stats->conflicts, stats->max_depth);
}
static int int_compare(const void *a, const void *b) {
    int left = *(const int *)a, right = *(const int *)b;
    return (left > right) - (left < right);
}
static void regular_result(Lines *lines, const Job *job, const Solution *solution) {
    const Formula *formula = &job->formula;
    const Preprocess *reduced = &solution->reduced;
    if (job->command == COLOR)
        line_push(lines, graph_line(job->graph));
    int lengths[201] = {0}, literals = 0;
    for (int i = 0; i < formula->count; ++i) {
        ++lengths[formula->clauses[i].count];
        literals += formula->clauses[i].count;
    }
    char *frequency = frequency_list(lengths, 201);
    line_push(lines, format("formula variables=%d clauses=%d literals=%d lengths=%s", formula->variables,
                            formula->count, literals, frequency));
    free(frequency);
    line_push(
        lines,
        format(
            "preprocess pure=%s tautologies=%d duplicate_literals=%d unit_fixed=%d unit_removed=%d subsumed=%d pure_fixed=%d pure_removed=%d removed=%d",
            reduced->pure ? "on" : "off", reduced->tautologies, reduced->duplicate_literals,
            reduced->unit_fixed, reduced->unit_removed, reduced->subsumed, reduced->pure_fixed,
            reduced->pure_removed, solution->removed));
    char *records[4];
    for (int i = 0; i < 4; ++i) {
        IntList sorted = int_copy(&reduced->removed[i]);
        qsort(sorted.data, (size_t)sorted.count, sizeof(int), int_compare);
        records[i] = number_list(&sorted);
        int_free(&sorted);
    }
    line_push(lines, format("removed_clauses tautology=%s unit=%s subsumed=%s pure=%s", records[0],
                            records[1], records[2], records[3]));
    for (int i = 0; i < 4; ++i)
        free(records[i]);
    if (reduced->conflict)
        line_push(lines, format("simplified empty_clause=%d", reduced->empty_clause));
    else {
        memset(lengths, 0, sizeof lengths);
        literals = 0;
        for (int i = 0; i < reduced->count; ++i) {
            ++lengths[reduced->clauses[i].literals.count];
            literals += reduced->clauses[i].literals.count;
        }
        IntList fixed = {0};
        for (int x = 1; x <= formula->variables; ++x)
            if (reduced->fixed.values[x] >= 0)
                int_push(&fixed, reduced->fixed.values[x] ? x : -x);
        frequency = frequency_list(lengths, 201);
        line_push(lines,
                  format("simplified clauses=%d literals=%d lengths=%s fixed=%d active=%d", reduced->count,
                         literals, frequency, fixed.count, formula->variables - fixed.count));
        free(frequency);
        char *list = number_list(&fixed);
        line_push(lines, format("fixed literals=%s", list));
        free(list);
        int_free(&fixed);
    }
    line_push(lines, format("result %s models=%d rounds=%d stop=%s", status(solution), solution->model_count,
                            solution->rounds, solution->stop));
    line_push(lines, search_line(&solution->stats));
    if (solution->rounds) {
        char *trace = text("");
        for (int i = 0; i < solution->trace.count && i < 12; ++i) {
            char *next = format("%s%s%s", trace, i ? " " : "", solution->trace.data[i]);
            free(trace);
            trace = next;
        }
        if (solution->trace.count > 12) {
            char *next = format("%s +%d", trace, solution->trace.count - 12);
            free(trace);
            trace = next;
        }
        line_push(lines, format("trace %s", *trace ? trace : "-"));
        free(trace);
    }
    analysis(lines, formula, solution, true);
    if (job->command == CORE && !solution->model_count) {
        bool *keep = resize(NULL, (size_t)formula->count * sizeof(bool));
        for (int i = 0; i < formula->count; ++i)
            keep[i] = true;
        Statistics tests = {0};
        for (int i = 0; i < formula->count; ++i) {
            Formula trial = {.variables = formula->variables};
            for (int j = 0; j < formula->count; ++j)
                if (keep[j] && j != i)
                    formula_push(&trial, int_copy(&formula->clauses[j]));
            Solution test = solve(&trial, 1);
            stats_add(&tests, &test.stats);
            if (!test.model_count)
                keep[i] = false;
            solution_free(&test);
            formula_free(&trial);
        }
        IntList core = {0};
        for (int i = 0; i < formula->count; ++i)
            if (keep[i])
                int_push(&core, i + 1);
        char *list = number_list(&core);
        line_push(lines, format("core size=%d decisions=%d conflicts=%d clauses=%s", core.count,
                                tests.decisions, tests.conflicts, list));
        free(list);
        free(keep);
        int_free(&core);
    }
}
typedef struct {
    IntList canonical;
    int orbit, found, first;
} BoardClass;
static int sequence_compare(const IntList *a, const IntList *b) {
    for (int i = 0; i < a->count && i < b->count; ++i)
        if (a->data[i] != b->data[i])
            return a->data[i] < b->data[i] ? -1 : 1;
    return (a->count > b->count) - (a->count < b->count);
}
static IntList queen_canonical(const IntList *columns, int *orbit) {
    int n = columns->count;
    IntList boards[8] = {{0}};
    for (int t = 0; t < 8; ++t) {
        for (int i = 0; i < n; ++i)
            int_push(&boards[t], 0);
        for (int r = 1; r <= n; ++r) {
            int c = columns->data[r - 1];
            Edge positions[8] = {{r, c},         {c, n + 1 - r},        {n + 1 - r, n + 1 - c},
                                 {n + 1 - c, r}, {r, n + 1 - c},        {n + 1 - r, c},
                                 {c, r},         {n + 1 - c, n + 1 - r}};
            boards[t].data[positions[t].a - 1] = positions[t].b;
        }
    }
    int smallest = 0;
    *orbit = 0;
    for (int t = 0; t < 8; ++t) {
        bool first = true;
        for (int earlier = 0; earlier < t; ++earlier)
            if (!sequence_compare(&boards[t], &boards[earlier]))
                first = false;
        if (first)
            ++*orbit;
        if (sequence_compare(&boards[t], &boards[smallest]) < 0)
            smallest = t;
    }
    IntList out = int_copy(&boards[smallest]);
    for (int t = 0; t < 8; ++t)
        int_free(&boards[t]);
    return out;
}
static IntList color_canonical(const IntList *colors) {
    int names[31] = {0}, count = 0;
    IntList out = {0};
    for (int i = 0; i < colors->count; ++i) {
        int color = colors->data[i];
        if (!names[color])
            names[color] = ++count;
        int_push(&out, names[color]);
    }
    return out;
}
static Lines puzzle_board(int index, const Job *job, const Solution *solution, int colors) {
    Lines lines = {0};
    bool queens = job->command == QUEENS, pigeon = job->command == PIGEON;
    if (queens)
        line_push(&lines, format("QUEENS job=%d n=%d", index, job->a));
    else if (pigeon)
        line_push(&lines, format("PIGEON job=%d pigeons=%d holes=%d", index, job->a, job->b));
    else {
        const Graph *graph = job->graph;
        line_push(&lines, format("%s job=%d graph=%s vertices=%d edges=%d colors=%d", commands[job->command],
                                 index, graph->name, graph->vertices, graph->edge_count, colors));
        IntList coloring = greedy(graph);
        char *list = number_list(&coloring);
        line_push(&lines, format("greedy used=%d colors=%s", maximum(&coloring), list));
        free(list);
        int_free(&coloring);
    }
    BoardClass classes[200] = {0};
    int class_count = 0;
    for (int i = 0; i < solution->model_count; ++i) {
        IntList positions = decode(&solution->models[i], queens || pigeon ? job->a : job->graph->vertices,
                                   queens   ? job->a
                                   : pigeon ? job->b
                                            : colors);
        char *list = number_list(&positions);
        if (pigeon) {
            IntList empty = {0};
            for (int h = 1; h <= job->b; ++h)
                if (!int_contains(&positions, h))
                    int_push(&empty, h);
            char *holes = number_list(&empty);
            line_push(&lines, format("assignment %d holes=%s empty=%s", i + 1, list, holes));
            free(holes);
            int_free(&empty);
        } else {
            int orbit = 0;
            IntList canonical = queens ? queen_canonical(&positions, &orbit) : color_canonical(&positions);
            int category = 0;
            while (category < class_count && sequence_compare(&classes[category].canonical, &canonical))
                ++category;
            bool first = category == class_count;
            if (first)
                classes[class_count++] = (BoardClass){canonical, orbit, 0, i + 1};
            else
                int_free(&canonical);
            ++classes[category].found;
            if (queens) {
                line_push(&lines, format("solution %d columns=%s class=%d", i + 1, list, category + 1));
                if (first) {
                    Lines board = board_lines(&positions);
                    append_lines(&lines, &board);
                    free_lines(&board);
                }
            } else {
                IntList sizes = {0};
                for (int c = 1; c <= colors; ++c)
                    int_push(&sizes, 0);
                for (int v = 0; v < positions.count; ++v)
                    ++sizes.data[positions.data[v] - 1];
                int used = 0;
                for (int c = 0; c < colors; ++c)
                    if (sizes.data[c])
                        ++used;
                char *counts = number_list(&sizes);
                line_push(&lines, format("coloring %d colors=%s used=%d sizes=%s class=%d", i + 1, list, used,
                                         counts, category + 1));
                free(counts);
                int_free(&sizes);
            }
        }
        free(list);
        int_free(&positions);
    }
    for (int c = 0; c < class_count; ++c) {
        BoardClass *category = &classes[c];
        char *list = number_list(&category->canonical);
        if (queens)
            line_push(&lines, format("class %d orbit=%d found=%d first=%d canonical=%s", c + 1,
                                     category->orbit, category->found, category->first, list));
        else
            line_push(&lines, format("class %d found=%d first=%d canonical=%s", c + 1, category->found,
                                     category->first, list));
        free(list);
        int_free(&category->canonical);
    }
    if (pigeon) {
        int expected = job->a <= job->b ? 1 : 0;
        if (expected)
            for (int i = 0; i < job->a; ++i)
                expected *= job->b - i;
        line_push(&lines, format("summary assignments=%d stop=%s expected=%d", solution->model_count,
                                 solution->stop, expected));
    } else
        line_push(&lines, format("summary %s=%d stop=%s classes=%d", queens ? "solutions" : "colorings",
                                 solution->model_count, solution->stop, class_count));
    return lines;
}
typedef struct {
    int index;
    Command command;
    bool sat;
    Statistics stats;
    int variables, clauses, removed, models, rounds;
} Record;
int main(void) {
    mkdir("output", 0777);
    Graph graphs[20] = {0};
    int graph_count = read_graphs(graphs);
    Lines results = {0}, models = {0}, boards = {0}, csv = {0};
    line_push(
        &csv,
        text(
            "job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds"));
    Record records[60];
    int record_count = 0, index = 0, errors = 0;
    Lines jobs = read_lines("input/jobs.txt");
    for (int j = 0; j < jobs.count; ++j) {
        const char *raw = jobs.data[j];
        if (!*raw || *raw == '#')
            continue;
        ++index;
        char *header = format("JOB %d %s", index, raw);
        Lines result = {0};
        line_push(&result, text(header));
        Lines tokens = words(raw);
        Job job = validate(&tokens, graphs, graph_count);
        free_lines(&tokens);
        if (job.error) {
            line_push(&result, format("error %s", job.error));
            paragraph(&results, &result);
            free_lines(&result);
            free(header);
            free(job.error);
            formula_free(&job.formula);
            ++errors;
            continue;
        }
        Solution solution = {0};
        int colors = job.a;
        if (job.command == CHROMATIC) {
            line_push(&result, graph_line(job.graph));
            Statistics aggregate = {0};
            int removed = 0, rounds = 0;
            for (colors = 1; colors <= job.a; ++colors) {
                formula_free(&job.formula);
                solution_free(&solution);
                job.formula = color_formula(job.graph, colors);
                solution = solve(&job.formula, 1);
                stats_add(&aggregate, &solution.stats);
                removed += solution.removed;
                rounds += solution.rounds;
                line_push(
                    &result,
                    format(
                        "attempt k=%d clauses=%d removed=%d result=%s stop=%s decisions=%d propagations=%d conflicts=%d max_depth=%d",
                        colors, job.formula.count, solution.removed, status(&solution), solution.stop,
                        solution.stats.decisions, solution.stats.propagations, solution.stats.conflicts,
                        solution.stats.max_depth));
                if (solution.model_count)
                    break;
            }
            if (colors > job.a)
                colors = job.a;
            char *chromatic = solution.model_count ? format("%d", colors) : text("-");
            line_push(&result,
                      format("result %s chromatic=%s attempts=%d", status(&solution), chromatic, colors));
            free(chromatic);
            solution.stats = aggregate;
            solution.removed = removed;
            solution.rounds = rounds;
            line_push(&result, search_line(&aggregate));
            analysis(&result, &job.formula, &solution, false);
        } else {
            solution = solve(&job.formula, job.limit);
            regular_result(&result, &job, &solution);
        }
        paragraph(&results, &result);
        free_lines(&result);
        if (solution.model_count) {
            Lines entries = {0};
            line_push(&entries, text(header));
            for (int i = 0; i < solution.model_count; ++i) {
                line_push(&entries, format("model %d", i + 1));
                Lines v = model_lines(&solution.models[i], job.formula.variables);
                append_lines(&entries, &v);
                free_lines(&v);
            }
            paragraph(&models, &entries);
            free_lines(&entries);
        }
        if (job.command >= QUEENS) {
            Lines entries = puzzle_board(index, &job, &solution, colors);
            paragraph(&boards, &entries);
            free_lines(&entries);
        }
        Record record = {index,
                         job.command,
                         solution.model_count > 0,
                         solution.stats,
                         job.formula.variables,
                         job.formula.count,
                         solution.removed,
                         solution.model_count,
                         solution.rounds};
        records[record_count++] = record;
        line_push(&csv, format("%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d", index, commands[job.command],
                               status(&solution), record.variables, record.clauses, record.removed,
                               record.stats.decisions, record.stats.propagations, record.stats.conflicts,
                               record.stats.max_depth, record.models, record.rounds));
        free(header);
        solution_free(&solution);
        formula_free(&job.formula);
    }
    Statistics totals = {0};
    int sat = 0, model_total = 0, round_total = 0, removed_total = 0;
    for (int i = 0; i < record_count; ++i) {
        Record *record = &records[i];
        sat += record->sat;
        stats_add(&totals, &record->stats);
        model_total += record->models;
        round_total += record->rounds;
        removed_total += record->removed;
    }
    Lines summary = {0};
    line_push(&summary,
              format("SUMMARY jobs=%d sat=%d unsat=%d error=%d", index, sat, record_count - sat, errors));
    line_push(
        &summary,
        format("totals models=%d rounds=%d decisions=%d propagations=%d conflicts=%d removed_clauses=%d",
               model_total, round_total, totals.decisions, totals.propagations, totals.conflicts,
               removed_total));
    for (int command = 0; command < 7; ++command) {
        int jobs_count = 0, command_sat = 0;
        Statistics stats = {0};
        for (int i = 0; i < record_count; ++i)
            if (records[i].command == (Command)command) {
                ++jobs_count;
                command_sat += records[i].sat;
                stats_add(&stats, &records[i].stats);
            }
        if (jobs_count)
            line_push(&summary,
                      format("command %s jobs=%d sat=%d unsat=%d decisions=%d propagations=%d conflicts=%d",
                             commands[command], jobs_count, command_sat, jobs_count - command_sat,
                             stats.decisions, stats.propagations, stats.conflicts));
    }
    if (record_count) {
        Record *hardest = &records[0], *deepest = hardest, *busiest = hardest;
        for (int i = 0; i < record_count; ++i) {
            Record *record = &records[i];
            if (record->stats.conflicts > hardest->stats.conflicts)
                hardest = record;
            if (record->stats.max_depth > deepest->stats.max_depth)
                deepest = record;
            if (record->stats.propagations > busiest->stats.propagations)
                busiest = record;
        }
        line_push(&summary, format("hardest job=%d conflicts=%d", hardest->index, hardest->stats.conflicts));
        line_push(&summary, format("deepest job=%d max_depth=%d", deepest->index, deepest->stats.max_depth));
        line_push(&summary,
                  format("busiest job=%d propagations=%d", busiest->index, busiest->stats.propagations));
    }
    paragraph(&results, &summary);
    write_lines("results.txt", &results);
    write_lines("models.txt", &models);
    write_lines("boards.txt", &boards);
    write_lines("stats.csv", &csv);
    free_lines(&summary);
    free_lines(&results);
    free_lines(&models);
    free_lines(&boards);
    free_lines(&csv);
    free_lines(&jobs);
    for (int i = 0; i < graph_count; ++i) {
        free(graphs[i].name);
        free(graphs[i].error);
    }
    return 0;
}
