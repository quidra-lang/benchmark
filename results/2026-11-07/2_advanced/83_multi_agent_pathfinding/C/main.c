#include "mapf.h"
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static const char *class_names[] = {"cardinal", "semi_cardinal", "non_cardinal"};
static void read_parameters(Parameters *p, int n) {
    memset(p, 0, sizeof(*p));
    p->order_count = 1;
    for (int i = 0; i < n; ++i)
        p->orders[0][i] = i;
    FILE *file = open_file("input/params.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words a = split_words(line);
        if (strcmp(a.items[0], "HORIZON") == 0)
            p->horizon = atoi(a.items[1]);
        else if (strcmp(a.items[0], "HL_BUDGET") == 0)
            p->high_budget = atoi(a.items[1]);
        else if (strcmp(a.items[0], "LL_BUDGET") == 0)
            p->low_budget = atoi(a.items[1]);
        else if (strcmp(a.items[0], "WINDOW") == 0) {
            p->window = atoi(a.items[1]);
            p->step = atoi(a.items[2]);
        } else if (strcmp(a.items[0], "ORDER") == 0) {
            int *order = p->orders[p->order_count++];
            for (int i = 0; i < n; ++i)
                order[i] = atoi(a.items[i + 1]);
        } else if (strcmp(a.items[0], "RUN") == 0) {
            RunDefinition *d = &p->runs[p->run_count++];
            d->solver = strcmp(a.items[1], "PP") == 0     ? SOLVER_PP
                        : strcmp(a.items[1], "CBS") == 0  ? SOLVER_CBS
                        : strcmp(a.items[1], "ICBS") == 0 ? SOLVER_ICBS
                                                          : SOLVER_WHCA;
            d->makespan = strcmp(a.items[2], "MAKESPAN") == 0;
            snprintf(d->name, sizeof(d->name), "%s-%s", a.items[1], a.items[2]);
        } else if (strcmp(a.items[0], "ANIMATE") == 0) {
            strcpy(p->animate, a.items[1]);
            p->frames = atoi(a.items[2]);
        } else
            p->delays[p->delay_count++] =
                (Delay){atoi(a.items[1]), atoi(a.items[2]), atoi(a.items[3])};
        free(a.items);
        free(line);
    }
    fclose(file);
}
static int *mdd(const Grid *g, int agent, int length, const Prohibitions *b) {
    int cells = g->width * g->height;
    size_t size = (size_t)(length + 1) * cells;
    uint8_t *forward = allocate(size), *valid = allocate(size);
    memset(forward, 0, size);
    memset(valid, 0, size);
    forward[g->agents[agent].start] = 1;
    for (int t = 1; t <= length; ++t)
        for (int c = 0; c < cells; ++c)
            if (forward[(size_t)(t - 1) * cells + c]) {
                Destinations next = destinations(g, c);
                for (int i = 0; i < next.count; ++i) {
                    int v = next.items[i];
                    if (g->distance[agent][v] >= 0 && t + g->distance[agent][v] <= length &&
                        allowed(b, c, v, t))
                        forward[(size_t)t * cells + v] = 1;
                }
            }
    valid[(size_t)length * cells + g->agents[agent].goal] = 1;
    for (int t = length - 1; t >= 0; --t)
        for (int c = 0; c < cells; ++c)
            if (forward[(size_t)t * cells + c]) {
                Destinations next = destinations(g, c);
                for (int i = 0; i < next.count; ++i) {
                    int v = next.items[i];
                    if (valid[(size_t)(t + 1) * cells + v] && allowed(b, c, v, t + 1)) {
                        valid[(size_t)t * cells + c] = 1;
                        break;
                    }
                }
            }
    int *widths = allocate((size_t)(length + 1) * sizeof(int));
    for (int t = 0; t <= length; ++t) {
        widths[t] = 0;
        for (int c = 0; c < cells; ++c)
            widths[t] += valid[(size_t)t * cells + c] != 0;
    }
    free(forward);
    free(valid);
    return widths;
}
static int classify(const Grid *g, Conflict c, const Plan *paths,
                    ConstraintList *const constraints[20], int *cache[20]) {
    int fixed = 0, agents[2] = {c.a, c.b};
    for (int i = 0; i < 2; ++i) {
        int agent = agents[i], length = paths->paths[agent]->count - 1;
        if (c.time > length) {
            ++fixed;
            continue;
        }
        if (!cache[agent]) {
            Prohibitions b = constraint_prohibitions(g, length, constraints[agent]);
            cache[agent] = mdd(g, agent, length, &b);
            prohibitions_free(&b);
        }
        if (cache[agent][c.time] == 1 && (!c.edge || cache[agent][c.time - 1] == 1))
            ++fixed;
    }
    return 2 - fixed;
}
static void cache_free(int *cache[20]) {
    for (int i = 0; i < 20; ++i)
        free(cache[i]);
}
static Lines overview(const Grid *g, const Parameters *p, const Plan *independent) {
    int cells = g->width * g->height, free_count = 0, components = 0, degrees[4] = {0};
    bool seen[1024] = {0};
    for (int c = 0; c < cells; ++c) {
        if (!free_cell(g, c))
            continue;
        ++free_count;
        int degree = destinations(g, c).count - 1;
        ++degrees[degree < 3 ? degree : 3];
        if (seen[c])
            continue;
        ++components;
        int queue[1024] = {c}, tail = 1;
        seen[c] = true;
        for (int head = 0; head < tail; ++head) {
            Destinations next = destinations(g, queue[head]);
            for (int i = 1; i < next.count; ++i)
                if (!seen[next.items[i]]) {
                    seen[next.items[i]] = true;
                    queue[tail++] = next.items[i];
                }
        }
    }
    Lines result = {0};
    lines_add(&result, format_text("instance width %d height %d free %d agents %d", g->width,
                                   g->height, free_count, g->agent_count));
    lines_add(&result,
              format_text("map isolated %d dead_ends %d corridors %d junctions %d components %d",
                          degrees[0], degrees[1], degrees[2], degrees[3], components));
    int lower_soc = 0, lower_max = 0;
    Prohibitions empty = prohibitions_new(g, p->horizon);
    for (int i = 0; i < g->agent_count; ++i) {
        int distance = g->distance[i][g->agents[i].start], *widths = mdd(g, i, distance, &empty),
            states = 0, width = 0;
        for (int t = 0; t <= distance; ++t) {
            states += widths[t];
            if (widths[t] > width)
                width = widths[t];
        }
        free(widths);
        lower_soc += distance;
        if (distance > lower_max)
            lower_max = distance;
        char *start = cell_text(g, g->agents[i].start), *goal = cell_text(g, g->agents[i].goal);
        lines_add(&result, format_text("agent %c start %s goal %s distance %d mdd %d width %d",
                                       'A' + i, start, goal, distance, states, width));
        free(start);
        free(goal);
    }
    prohibitions_free(&empty);
    lines_add(&result, format_text("lower_bound soc %d makespan %d", lower_soc, lower_max));
    Conflicts sequence = conflicts(independent);
    int counts[3] = {0}, vertex = 0, edge = 0, *cache[20] = {0};
    ConstraintList *constraints[20] = {0};
    uint32_t adjacency[20] = {0};
    for (size_t i = 0; i < sequence.count; ++i) {
        Conflict c = sequence.items[i];
        ++counts[classify(g, c, independent, constraints, cache)];
        if (c.edge)
            ++edge;
        else
            ++vertex;
        adjacency[c.a] |= UINT32_C(1) << c.b;
        adjacency[c.b] |= UINT32_C(1) << c.a;
    }
    cache_free(cache);
    lines_add(
        &result,
        format_text(
            "independent conflicts %zu vertex %d edge %d cardinal %d semi_cardinal %d non_cardinal %d",
            sequence.count, vertex, edge, counts[0], counts[1], counts[2]));
    free(sequence.items);
    Text groups = {0};
    text_add(&groups, "groups");
    bool visited[20] = {0}, any = false;
    for (int i = 0; i < g->agent_count; ++i)
        if (!visited[i] && adjacency[i]) {
            int queue[20] = {i}, tail = 1;
            uint32_t members = UINT32_C(1) << i;
            visited[i] = true;
            for (int head = 0; head < tail; ++head)
                for (int j = 0; j < g->agent_count; ++j)
                    if ((adjacency[queue[head]] & (UINT32_C(1) << j)) && !visited[j]) {
                        visited[j] = true;
                        members |= UINT32_C(1) << j;
                        queue[tail++] = j;
                    }
            text_add(&groups, " ");
            for (int j = 0; j < g->agent_count; ++j)
                if (members & (UINT32_C(1) << j))
                    text_format(&groups, "%c", 'A' + j);
            any = true;
        }
    if (!any)
        text_add(&groups, " -");
    lines_add(&result, text_take(&groups));
    return result;
}
static void solve_pp(const Grid *g, const Parameters *p, Run *r) {
    for (int k = 0; k < p->order_count; ++k) {
        ++r->high;
        int before = r->counter.expansions;
        PriorityResult result = prioritized(g, p, p->orders[k], k + 1, r);
        if (r->counter.aborted) {
            r->reason = "ll_budget";
            return;
        }
        char order[21];
        for (int i = 0; i < g->agent_count; ++i)
            order[i] = (char)('A' + p->orders[k][i]);
        order[g->agent_count] = 0;
        if (result.paths.count) {
            r->paths = result.paths;
            lines_add(&r->specific,
                      format_text("order %d %s planned %d expansions %d ok", k + 1, order,
                                  result.planned, r->counter.expansions - before));
            r->end = format_text("end OK order %d", k + 1);
            return;
        }
        lines_add(&r->specific,
                  format_text("order %d %s planned %d expansions %d failed %c", k + 1, order,
                              result.planned, r->counter.expansions - before, 'A' + result.failed));
    }
    r->reason = "orders";
}
static TreeNode *node_new(const Plan *paths, ConstraintList *const constraints[20], int number,
                          int parent, int depth, bool makespan) {
    TreeNode *node = allocate(sizeof(*node));
    *node =
        (TreeNode){.number = number, .parent = parent, .depth = depth, .paths = plan_copy(paths)};
    for (int i = 0; i < paths->count; ++i)
        node->constraints[i] = constraints_retain(constraints[i]);
    int soc, maximum;
    plan_costs(paths, &soc, &maximum);
    node->cost = makespan ? maximum : soc;
    node->conflicts = conflicts(paths);
    return node;
}
static void node_free(TreeNode *node) {
    if (!node)
        return;
    for (int i = 0; i < node->paths.count; ++i)
        constraints_release(node->constraints[i]);
    plan_release(&node->paths);
    free(node->conflicts.items);
    free(node);
}
typedef struct {
    TreeNode **items;
    int count, capacity;
} NodeHeap;
static void heap_push(NodeHeap *heap, TreeNode *node) {
    if (heap->count == heap->capacity) {
        heap->capacity = heap->capacity ? 2 * heap->capacity : 32;
        heap->items = resize(heap->items, (size_t)heap->capacity * sizeof(TreeNode *));
    }
    int at = heap->count++;
    while (at) {
        int parent = (at - 1) / 2;
        if (!node_less(node, heap->items[parent]))
            break;
        heap->items[at] = heap->items[parent];
        at = parent;
    }
    heap->items[at] = node;
}
static TreeNode *heap_pop(NodeHeap *heap) {
    TreeNode *result = heap->items[0], *last = heap->items[--heap->count];
    if (heap->count) {
        int at = 0;
        while (2 * at + 1 < heap->count) {
            int child = 2 * at + 1;
            if (child + 1 < heap->count && node_less(heap->items[child + 1], heap->items[child]))
                ++child;
            if (!node_less(heap->items[child], last))
                break;
            heap->items[at] = heap->items[child];
            at = child;
        }
        heap->items[at] = last;
    }
    return result;
}
static int constraint_width;
static int constraint_compare(const void *left, const void *right) {
    const Constraint *a = left, *b = right;
    int x[] = {a->agent,
               a->time,
               a->edge,
               a->u % constraint_width,
               a->u / constraint_width,
               a->v % constraint_width,
               a->v / constraint_width},
        y[] = {b->agent,
               b->time,
               b->edge,
               b->u % constraint_width,
               b->u / constraint_width,
               b->v % constraint_width,
               b->v / constraint_width};
    for (int i = 0; i < 7; ++i)
        if (x[i] != y[i])
            return x[i] < y[i] ? -1 : 1;
    return 0;
}
static void solve_cbs(const Grid *g, const Parameters *p, Run *r) {
    NodeHeap open = {0};
    Plan root = {.count = g->agent_count};
    ConstraintList *empty[20] = {0};
    Prohibitions bans = prohibitions_new(g, p->horizon);
    bool complete = true;
    for (int i = 0; i < g->agent_count; ++i) {
        root.paths[i] =
            low_level(g, i, g->agents[i].start, 0, p->horizon, &bans, false, &r->counter);
        if (r->counter.aborted) {
            r->reason = "ll_budget";
            complete = false;
            break;
        }
    }
    prohibitions_free(&bans);
    if (complete) {
        heap_push(&open, node_new(&root, empty, 0, -1, 0, r->definition.makespan));
        r->generated = 1;
    }
    plan_release(&root);
    while (!r->reason && open.count) {
        TreeNode *node = heap_pop(&open);
        if (!node->conflicts.count) {
            r->paths = plan_copy(&node->paths);
            r->answer = node;
            r->end = format_text("end OK node %d cost %d", node->number, node->cost);
            break;
        }
        if (r->high == p->high_budget) {
            r->reason = "hl_budget";
            node_free(node);
            break;
        }
        ++r->high;
        Conflict split = node->conflicts.items[0];
        int selected_class = 2;
        if (r->definition.solver == SOLVER_ICBS) {
            selected_class = 3;
            int *cache[20] = {0};
            for (size_t i = 0; i < node->conflicts.count; ++i) {
                Conflict c = node->conflicts.items[i];
                int kind = classify(g, c, &node->paths, node->constraints, cache);
                if (kind < selected_class) {
                    split = c;
                    selected_class = kind;
                }
            }
            cache_free(cache);
            ++r->classes[selected_class];
        }
        int children[2] = {-1, -1}, agents[2] = {split.a, split.b};
        for (int side = 0; side < 2; ++side) {
            int agent = agents[side];
            ConstraintList *constraints[20];
            memcpy(constraints, node->constraints, sizeof(constraints));
            constraints[agent] =
                constraints_append(node->constraints[agent], conflict_constraint(split, agent));
            bans = constraint_prohibitions(g, p->horizon, constraints[agent]);
            Path *path = low_level(g, agent, g->agents[agent].start, 0, p->horizon, &bans, false,
                                   &r->counter);
            prohibitions_free(&bans);
            if (r->counter.aborted) {
                r->reason = "ll_budget";
                constraints_release(constraints[agent]);
                break;
            }
            if (!path) {
                ++r->pruned;
                constraints_release(constraints[agent]);
                continue;
            }
            Plan paths = plan_copy(&node->paths);
            path_release(paths.paths[agent]);
            paths.paths[agent] = path;
            int number = r->generated++;
            heap_push(&open, node_new(&paths, constraints, number, node->number, node->depth + 1,
                                      r->definition.makespan));
            children[side] = number;
            plan_release(&paths);
            constraints_release(constraints[agent]);
        }
        if (!r->counter.aborted) {
            char *parent = node->parent < 0 ? copy_text("-") : format_text("%d", node->parent),
                 *child0 = children[0] < 0 ? copy_text("-") : format_text("%d", children[0]),
                 *child1 = children[1] < 0 ? copy_text("-") : format_text("%d", children[1]),
                 *split_text = conflict_text(g, split);
            lines_add(
                &r->trace,
                format_text(
                    "expand %d node %d parent %s depth %d cost %d conflicts %zu split %s%s%s children %s %s",
                    r->high, node->number, parent, node->depth, node->cost, node->conflicts.count,
                    split_text, r->definition.solver == SOLVER_ICBS ? " class " : "",
                    r->definition.solver == SOLVER_ICBS ? class_names[selected_class] : "", child0,
                    child1));
            free(parent);
            free(child0);
            free(child1);
            free(split_text);
        }
        node_free(node);
    }
    if (!r->reason && !r->paths.count)
        r->reason = "exhausted";
    r->open = open.count;
    lines_add(&r->specific, format_text("search expanded %d generated %d pruned %d open %d",
                                        r->high, r->generated, r->pruned, r->open));
    if (r->definition.solver == SOLVER_ICBS)
        lines_add(&r->specific, format_text("classes cardinal %d semi_cardinal %d non_cardinal %d",
                                            r->classes[0], r->classes[1], r->classes[2]));
    if (r->answer) {
        lines_add(&r->specific,
                  format_text("solution node %d depth %d", r->answer->number, r->answer->depth));
        size_t count = 0;
        for (int i = 0; i < g->agent_count; ++i)
            if (r->answer->constraints[i])
                count += r->answer->constraints[i]->count;
        Constraint *all = allocate(count * sizeof(Constraint));
        size_t at = 0;
        for (int i = 0; i < g->agent_count; ++i) {
            ConstraintList *list = r->answer->constraints[i];
            if (list && list->count) {
                memcpy(all + at, list->items, list->count * sizeof(Constraint));
                at += list->count;
            }
        }
        constraint_width = g->width;
        qsort(all, count, sizeof(Constraint), constraint_compare);
        for (size_t i = 0; i < count; ++i) {
            Constraint c = all[i];
            char *u = cell_text(g, c.u), *v = cell_text(g, c.v);
            lines_add(
                &r->specific,
                c.edge ? format_text("constraint %c edge %s %s t %d", 'A' + c.agent, u, v, c.time)
                       : format_text("constraint %c vertex %s t %d", 'A' + c.agent, v, c.time));
            free(u);
            free(v);
        }
        free(all);
    }
    while (open.count)
        node_free(heap_pop(&open));
    free(open.items);
}
static void solve_whca(const Grid *g, const Parameters *p, Run *r) {
    Plan executed = {.count = g->agent_count};
    int current[20];
    for (int i = 0; i < g->agent_count; ++i) {
        executed.paths[i] = path_new();
        current[i] = g->agents[i].start;
        path_append(executed.paths[i], current[i]);
    }
    for (int time = 0;; time += p->step) {
        bool done = true;
        for (int i = 0; i < g->agent_count; ++i)
            done = done && current[i] == g->agents[i].goal;
        if (done) {
            for (int i = 0; i < g->agent_count; ++i) {
                Path *path = executed.paths[i];
                while (path->count > 1 && path->cells[path->count - 2] == g->agents[i].goal)
                    --path->count;
            }
            r->paths = executed;
            executed = (Plan){0};
            r->end = format_text("end OK rounds %d", r->high);
            break;
        }
        if (time >= p->horizon) {
            r->reason = "timeout";
            break;
        }
        ++r->high;
        int order[20], order_count = 0;
        for (int goal = 0; goal < 2; ++goal)
            for (int i = 0; i < g->agent_count; ++i)
                if ((current[i] == g->agents[i].goal) == (goal != 0))
                    order[order_count++] = i;
        Prohibitions b = prohibitions_new(g, time + p->window);
        Plan window = {.count = g->agent_count};
        for (int i = 0; i < order_count; ++i) {
            int agent = order[i], before = r->counter.expansions;
            Path *path =
                low_level(g, agent, current[agent], time, time + p->window, &b, true, &r->counter);
            if (r->counter.aborted) {
                r->reason = "ll_budget";
                break;
            }
            if (!path) {
                lines_add(&r->trace,
                          format_text("round %d time %d agent %c blocked expansions %d", r->high,
                                      time, 'A' + agent, r->counter.expansions - before));
                r->reason = "blocked";
                break;
            }
            while (path->count < p->window + 1)
                path_append(path, path->cells[path->count - 1]);
            char *moves = actions(g, path);
            lines_add(&r->trace,
                      format_text("round %d time %d agent %c moves %s expansions %d", r->high, time,
                                  'A' + agent, moves, r->counter.expansions - before));
            free(moves);
            reserve_path(&b, path, time, false);
            window.paths[agent] = path;
        }
        prohibitions_free(&b);
        if (!r->reason)
            for (int i = 0; i < g->agent_count; ++i) {
                for (int k = 1; k <= p->step; ++k)
                    path_append(executed.paths[i], window.paths[i]->cells[k]);
                current[i] = window.paths[i]->cells[p->step];
            }
        plan_release(&window);
        if (r->reason)
            break;
    }
    plan_release(&executed);
    lines_add(&r->specific,
              format_text("window %d step %d rounds %d", p->window, p->step, r->high));
}
static void metrics(const Grid *g, const Plan *paths, PlanMetrics *m) {
    memset(m, 0, sizeof(*m));
    plan_costs(paths, &m->soc, &m->makespan);
    m->arrivals = allocate((size_t)(m->makespan + 1) * sizeof(int));
    memset(m->arrivals, 0, (size_t)(m->makespan + 1) * sizeof(int));
    for (int i = 0; i < paths->count; ++i) {
        Path *path = paths->paths[i];
        AgentMetrics *a = &m->agents[i];
        a->cost = path->count - 1;
        a->extra = a->cost - g->distance[i][g->agents[i].start];
        a->arrival = -1;
        a->actions = actions(g, path);
        bool seen[1024] = {0};
        char last = 0;
        for (int t = 0; t < path->count; ++t) {
            int c = path->cells[t];
            seen[c] = true;
            if (c == g->agents[i].goal && a->arrival < 0)
                a->arrival = t;
            if (!t)
                continue;
            if (c == path->cells[t - 1]) {
                ++a->waits;
                ++m->cell_waits[c];
            } else {
                char direction = action(g, path->cells[t - 1], c);
                if (last && last != direction)
                    ++a->turns;
                last = direction;
            }
            if (path->cells[t - 1] == g->agents[i].goal && c != g->agents[i].goal)
                ++a->leave;
        }
        for (int c = 0; c < g->width * g->height; ++c)
            if (seen[c])
                ++m->traffic[c];
        for (int t = a->cost; t <= m->makespan; ++t)
            ++m->arrivals[t];
        m->sum_extra += a->extra;
        if (a->extra > m->max_extra)
            m->max_extra = a->extra;
        m->waits += a->waits;
        m->turns += a->turns;
    }
    for (int c = 0; c < g->width * g->height; ++c)
        if (m->traffic[c]) {
            int at = 0;
            while (at < m->hotspot_count &&
                   (m->traffic[m->hotspots[at]] > m->traffic[c] ||
                    (m->traffic[m->hotspots[at]] == m->traffic[c] && m->hotspots[at] < c)))
                ++at;
            if (at >= 5)
                continue;
            int end = m->hotspot_count < 5 ? m->hotspot_count : 4;
            for (int i = end; i > at; --i)
                m->hotspots[i] = m->hotspots[i - 1];
            m->hotspots[at] = c;
            if (m->hotspot_count < 5)
                ++m->hotspot_count;
        }
}
static Lines validation(const Grid *g, const char *name, const Plan *paths, bool independent) {
    int start = 0, goal = 0, moves = 0, follows = 0, vertex = 0, edge = 0;
    for (int i = 0; i < paths->count; ++i) {
        Path *path = paths->paths[i];
        start += path->cells[0] != g->agents[i].start;
        goal += path->cells[path->count - 1] != g->agents[i].goal;
        for (int t = 1; t < path->count; ++t) {
            Destinations next = destinations(g, path->cells[t - 1]);
            bool valid = false;
            for (int j = 0; j < next.count; ++j)
                if (next.items[j] == path->cells[t])
                    valid = true;
            if (!valid)
                ++moves;
        }
    }
    Conflicts sequence = conflicts(paths);
    for (size_t i = 0; i < sequence.count; ++i)
        if (sequence.items[i].edge)
            ++edge;
        else
            ++vertex;
    int soc, last;
    plan_costs(paths, &soc, &last);
    for (int t = 1; t <= last; ++t)
        for (int a = 0; a < paths->count; ++a)
            for (int b = 0; b < paths->count; ++b)
                if (a != b && position(paths->paths[a], t) != position(paths->paths[a], t - 1) &&
                    position(paths->paths[a], t) == position(paths->paths[b], t - 1) &&
                    position(paths->paths[b], t) != position(paths->paths[a], t - 1))
                    ++follows;
    Lines result = {0};
    lines_add(
        &result,
        format_text("plan %s verdict %s start %d goal %d moves %d vertex %d edge %d follows %d",
                    name, start + goal + moves + vertex + edge ? "INVALID" : "VALID", start, goal,
                    moves, vertex, edge, follows));
    int *cache[20] = {0};
    ConstraintList *constraints[20] = {0};
    for (size_t i = 0; i < sequence.count; ++i) {
        Conflict c = sequence.items[i];
        char *text = conflict_text(g, c);
        lines_add(
            &result,
            format_text("  %s%s%s", text, independent ? " " : "",
                        independent ? class_names[classify(g, c, paths, constraints, cache)] : ""));
        free(text);
    }
    cache_free(cache);
    free(sequence.items);
    return result;
}
static Execution delayed(const Plan *paths, const Parameters *p) {
    typedef struct {
        int time, cell;
    } Step;
    int n = paths->count;
    Step *steps[20] = {0};
    int counts[20] = {0};
    for (int i = 0; i < n; ++i) {
        Path *path = paths->paths[i];
        steps[i] = allocate((size_t)path->count * sizeof(Step));
        steps[i][counts[i]++] = (Step){0, path->cells[0]};
        for (int t = 1; t < path->count; ++t)
            if (path->cells[t] != path->cells[t - 1])
                steps[i][counts[i]++] = (Step){t, path->cells[t]};
    }
    int *needs[20] = {0};
    for (int i = 0; i < n; ++i) {
        needs[i] = allocate((size_t)counts[i] * n * sizeof(int));
        for (int k = 0; k < counts[i] * n; ++k)
            needs[i][k] = -1;
        for (int k = 1; k < counts[i]; ++k)
            for (int j = 0; j < n; ++j)
                if (i != j)
                    for (int l = 0; l < counts[j]; ++l)
                        if (steps[j][l].cell == steps[i][k].cell &&
                            steps[j][l].time < steps[i][k].time)
                            needs[i][k * n + j] = l;
    }
    Execution result = {0};
    int progress[20] = {0};
    for (int time = 0;; ++time) {
        bool done = true;
        for (int i = 0; i < n; ++i)
            done = done && progress[i] == counts[i] - 1;
        if (done) {
            for (int i = 0; i < n; ++i) {
                result.soc += result.finish[i];
                if (result.finish[i] > result.makespan)
                    result.makespan = result.finish[i];
            }
            break;
        }
        bool advance[20] = {0}, stopped = false, any = false;
        for (int i = 0; i < n; ++i) {
            if (progress[i] == counts[i] - 1)
                continue;
            bool stop = false;
            for (int d = 0; d < p->delay_count; ++d)
                if (p->delays[d].agent == i && p->delays[d].start <= time &&
                    time < p->delays[d].start + p->delays[d].length)
                    stop = true;
            if (stop) {
                stopped = true;
                continue;
            }
            bool held = false;
            for (int j = 0; j < n; ++j)
                if (progress[j] <= needs[i][(progress[i] + 1) * n + j])
                    held = true;
            if (held)
                ++result.blocked;
            else {
                advance[i] = true;
                any = true;
            }
        }
        if (!any && !stopped) {
            result.deadlock = true;
            result.time = time;
            break;
        }
        for (int i = 0; i < n; ++i)
            if (advance[i]) {
                ++progress[i];
                result.finish[i] = time + 1;
            }
    }
    for (int i = 0; i < n; ++i) {
        free(steps[i]);
        free(needs[i]);
    }
    return result;
}
static void count_picture(Lines *out, const Grid *g, const int *counts) {
    for (int y = 0; y < g->height; ++y) {
        char row[33];
        strcpy(row, g->rows[y]);
        for (int x = 0; x < g->width; ++x) {
            int c = y * g->width + x;
            if (free_cell(g, c))
                row[x] = counts[c] == 0 ? '.' : counts[c] < 10 ? (char)('0' + counts[c]) : '+';
        }
        lines_add(out, copy_text(row));
    }
}
static Lines frames(const Grid *g, const Parameters *p, const Run *r) {
    Lines result = {0};
    if (!r->paths.count) {
        lines_add(&result, format_text("run %s FAIL", p->animate));
        return result;
    }
    lines_add(&result, format_text("run %s frames %d", p->animate, p->frames));
    for (int t = 0; t < p->frames; ++t) {
        char picture[32][33];
        memcpy(picture, g->rows, sizeof(picture));
        for (int i = 0; i < g->agent_count; ++i)
            picture[g->agents[i].goal / g->width][g->agents[i].goal % g->width] = (char)('a' + i);
        int done = 0, moving = 0, waiting = 0;
        for (int i = 0; i < r->paths.count; ++i) {
            Path *path = r->paths.paths[i];
            int c = position(path, t);
            picture[c / g->width][c % g->width] = (char)('A' + i);
            if (t >= path->count - 1)
                ++done;
            else if (t >= 1 && position(path, t) != position(path, t - 1))
                ++moving;
            else
                ++waiting;
        }
        lines_add(&result, copy_text(""));
        lines_add(&result,
                  format_text("frame %d done %d moving %d waiting %d", t, done, moving, waiting));
        for (int y = 0; y < g->height; ++y)
            lines_add(&result, copy_text(picture[y]));
    }
    lines_add(&result, copy_text(""));
    lines_add(&result, copy_text("traffic"));
    count_picture(&result, g, r->metrics.traffic);
    lines_add(&result, copy_text(""));
    lines_add(&result, copy_text("waits"));
    count_picture(&result, g, r->metrics.cell_waits);
    return result;
}
static Lines run_block(const Grid *g, const Run *r) {
    Lines result = {0};
    const RunDefinition *d = &r->definition;
    if (!r->paths.count) {
        lines_add(&result,
                  format_text("run %s solver %s cost_function %s result FAIL reason %s", d->name,
                              solver_name(d->solver), cost_function(d->makespan), r->reason));
        lines_copy(&result, &r->specific);
        return result;
    }
    const PlanMetrics *m = &r->metrics;
    int cost = d->makespan ? m->makespan : m->soc, lower = 0;
    for (int i = 0; i < g->agent_count; ++i) {
        int distance = g->distance[i][g->agents[i].start];
        if (!d->makespan)
            lower += distance;
        else if (distance > lower)
            lower = distance;
    }
    char *ratio = fraction(cost, lower);
    lines_add(&result,
              format_text(
                  "run %s solver %s cost_function %s result OK cost %d soc %d makespan %d ratio %s",
                  d->name, solver_name(d->solver), cost_function(d->makespan), cost, m->soc,
                  m->makespan, ratio));
    free(ratio);
    lines_copy(&result, &r->specific);
    for (int i = 0; i < g->agent_count; ++i) {
        const AgentMetrics *a = &m->agents[i];
        lines_add(
            &result,
            format_text("agent %c cost %d extra %d waits %d turns %d arrive %d leave %d moves %s",
                        'A' + i, a->cost, a->extra, a->waits, a->turns, a->arrival, a->leave,
                        a->actions));
    }
    char *arrivals = integers(m->arrivals, m->makespan + 1);
    lines_add(&result, format_text("arrivals %s", arrivals));
    free(arrivals);
    Text hotspots = {0};
    text_add(&hotspots, "hotspots");
    for (int i = 0; i < m->hotspot_count; ++i) {
        int c = m->hotspots[i];
        char *notation = cell_text(g, c);
        text_format(&hotspots, " %s:%d", notation, m->traffic[c]);
        free(notation);
    }
    lines_add(&result, text_take(&hotspots));
    const Execution *e = &r->execution;
    if (e->deadlock)
        lines_add(&result, format_text("execution deadlock time %d", e->time));
    else {
        char *finish = integers(e->finish, g->agent_count);
        lines_add(&result, format_text("execution soc %d makespan %d blocked %d finish %s", e->soc,
                                       e->makespan, e->blocked, finish));
        free(finish);
    }
    return result;
}
static char *stats_line(const Run *r) {
    Text text = {0};
    const RunDefinition *d = &r->definition;
    text_format(&text, "%s,%s,%s,", d->name, solver_name(d->solver), cost_function(d->makespan));
    if (!r->paths.count)
        text_format(&text, "FAIL,%s,-,-,-,-,-,-,-,-,-", r->reason);
    else {
        const PlanMetrics *m = &r->metrics;
        text_format(&text, "OK,-,%d,%d,%d,%d,%d,%d,%d,", d->makespan ? m->makespan : m->soc, m->soc,
                    m->makespan, m->sum_extra, m->max_extra, m->waits, m->turns);
        if (r->execution.deadlock)
            text_add(&text, "-,-");
        else
            text_format(&text, "%d,%d", r->execution.soc, r->execution.makespan);
    }
    text_format(&text, ",%d,", r->high);
    if (d->solver == SOLVER_CBS || d->solver == SOLVER_ICBS)
        text_format(&text, "%d", r->generated);
    else
        text_add(&text, "-");
    text_format(&text, ",%d,%d", r->counter.searches, r->counter.expansions);
    return text_take(&text);
}
static void append_owned(Lines *out, Lines in) {
    for (size_t i = 0; i < in.count; ++i)
        lines_add(out, in.items[i]);
    free(in.items);
}
static void run_free(Run *r) {
    plan_release(&r->paths);
    node_free(r->answer);
    for (int i = 0; i < 20; ++i)
        free(r->metrics.agents[i].actions);
    free(r->metrics.arrivals);
    free(r->end);
    lines_free(&r->specific);
    lines_free(&r->trace);
}
int main(void) {
    Grid *g = allocate(sizeof(*g));
    read_grid(g);
    Parameters p;
    read_parameters(&p, g->agent_count);
    Plan independent = {.count = g->agent_count};
    Counters counter = {.limit = INT_MAX};
    Prohibitions empty = prohibitions_new(g, p.horizon);
    for (int i = 0; i < g->agent_count; ++i)
        independent.paths[i] =
            low_level(g, i, g->agents[i].start, 0, p.horizon, &empty, false, &counter);
    prohibitions_free(&empty);
    Lines solutions = overview(g, &p, &independent),
          validations = validation(g, "INDEPENDENT", &independent, true), stats = {0}, trace = {0};
    lines_add(
        &stats,
        copy_text(
            "run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions"));
    Run *runs = allocate((size_t)p.run_count * sizeof(Run));
    memset(runs, 0, (size_t)p.run_count * sizeof(Run));
    int successful[10], success_count = 0, animated = 0;
    for (int i = 0; i < p.run_count; ++i) {
        Run *r = &runs[i];
        r->definition = p.runs[i];
        r->counter.limit = p.low_budget;
        if (r->definition.solver == SOLVER_PP)
            solve_pp(g, &p, r);
        else if (r->definition.solver == SOLVER_WHCA)
            solve_whca(g, &p, r);
        else
            solve_cbs(g, &p, r);
        if (r->paths.count) {
            metrics(g, &r->paths, &r->metrics);
            r->execution = delayed(&r->paths, &p);
            successful[success_count++] = i;
            append_owned(&validations, validation(g, r->definition.name, &r->paths, false));
        } else {
            lines_add(&validations, format_text("plan %s verdict NONE", r->definition.name));
            r->end = format_text("end FAIL %s", r->reason);
        }
        lines_add(&solutions, copy_text(""));
        append_owned(&solutions, run_block(g, r));
        lines_add(&stats, stats_line(r));
        if (i)
            lines_add(&trace, copy_text(""));
        lines_add(&trace, format_text("run %s", r->definition.name));
        lines_copy(&trace, &r->trace);
        lines_add(&trace, copy_text(r->end));
        if (strcmp(r->definition.name, p.animate) == 0)
            animated = i;
    }
    lines_add(&solutions, copy_text(""));
    lines_add(&solutions,
              format_text("summary ok %d failed %d", success_count, p.run_count - success_count));
    if (success_count) {
        int best_soc = runs[successful[0]].metrics.soc,
            best_max = runs[successful[0]].metrics.makespan;
        for (int i = 1; i < success_count; ++i) {
            Run *r = &runs[successful[i]];
            if (r->metrics.soc < best_soc)
                best_soc = r->metrics.soc;
            if (r->metrics.makespan < best_max)
                best_max = r->metrics.makespan;
        }
        Text soc = {0}, maximum = {0};
        text_format(&soc, "best_soc %d", best_soc);
        text_format(&maximum, "best_makespan %d", best_max);
        for (int i = 0; i < success_count; ++i) {
            Run *r = &runs[successful[i]];
            if (r->metrics.soc == best_soc)
                text_format(&soc, " %s", r->definition.name);
            if (r->metrics.makespan == best_max)
                text_format(&maximum, " %s", r->definition.name);
        }
        lines_add(&solutions, text_take(&soc));
        lines_add(&solutions, text_take(&maximum));
        for (int i = 1; i < success_count; ++i) {
            int current = successful[i], j = i;
            while (j > 0) {
                int previous = successful[j - 1];
                PlanMetrics *a = &runs[current].metrics, *b = &runs[previous].metrics;
                bool less = a->soc != b->soc             ? a->soc < b->soc
                            : a->makespan != b->makespan ? a->makespan < b->makespan
                                                         : current < previous;
                if (!less)
                    break;
                successful[j] = previous;
                --j;
            }
            successful[j] = current;
        }
        Text ranking = {0};
        text_add(&ranking, "ranking");
        for (int i = 0; i < success_count; ++i)
            text_format(&ranking, " %s", runs[successful[i]].definition.name);
        lines_add(&solutions, text_take(&ranking));
    }
    Lines animation = frames(g, &p, &runs[animated]);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    write_lines("solutions.txt", &solutions);
    write_lines("stats.csv", &stats);
    write_lines("validation.txt", &validations);
    write_lines("trace.txt", &trace);
    write_lines("frames.txt", &animation);
    lines_free(&solutions);
    lines_free(&stats);
    lines_free(&validations);
    lines_free(&trace);
    lines_free(&animation);
    for (int i = 0; i < p.run_count; ++i)
        run_free(&runs[i]);
    free(runs);
    plan_release(&independent);
    free(g);
    return EXIT_SUCCESS;
}
