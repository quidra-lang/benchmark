#include "planner.h"
typedef struct {
    uint64_t *bits;
    int size, words, count;
} Mutex;
static Mutex mutex_create(int size) {
    Mutex out = {0};
    out.size = size;
    out.words = (size + 63) / 64;
    out.bits = allocate((size_t)size * (size_t)out.words * sizeof *out.bits);
    return out;
}
static bool mutex_has(const Mutex *mutex, int a, int b) {
    return a != b && (mutex->bits[(size_t)a * (size_t)mutex->words + (size_t)b / 64] &
                      (UINT64_C(1) << (b % 64)));
}
static void mutex_put(Mutex *mutex, int a, int b) {
    if (a == b || mutex_has(mutex, a, b))
        return;
    mutex->bits[(size_t)a * (size_t)mutex->words + (size_t)b / 64] |= UINT64_C(1) << (b % 64);
    mutex->bits[(size_t)b * (size_t)mutex->words + (size_t)a / 64] |= UINT64_C(1) << (a % 64);
    ++mutex->count;
}
static bool mutex_compatible(const Mutex *mutex, State facts) {
    for (int i = 0; i < 256; ++i)
        if (state_has(facts, i))
            for (int j = i + 1; j < 256; ++j)
                if (state_has(facts, j) && mutex_has(mutex, i, j))
                    return false;
    return true;
}
void layers_push(Layers *layers, IntList layer) {
    if (layers->count == layers->capacity) {
        layers->capacity = layers->capacity ? layers->capacity * 2 : 8;
        layers->data = resize(layers->data, (size_t)layers->capacity * sizeof *layers->data);
    }
    layers->data[layers->count++] = layer;
}
void layers_free(Layers *layers) {
    for (int i = 0; i < layers->count; ++i)
        int_free(&layers->data[i]);
    free(layers->data);
    *layers = (Layers){0};
}
void graph_result_free(GraphPlanResult *result) {
    int_free(&result->plan);
    layers_free(&result->layers);
    lines_free(&result->logs);
}
typedef struct {
    GraphElement *data;
    int count;
} ActionLevel;
typedef struct {
    const GraphElement *actions;
    int action_count;
    State facts[31];
    Mutex fact_mutex[31];
    ActionLevel elements[30];
    Mutex action_mutex[30];
    StateTable memo[31];
    GraphPlanResult result;
} PlanningGraph;
static bool extract(PlanningGraph *graph, int level, State goals, Layers *out);
static int compare_ints(const void *left, const void *right) {
    int a = *(const int *)left, b = *(const int *)right;
    return (a > b) - (a < b);
}
static bool assign(PlanningGraph *graph, int level, const IntList *goals, int at, IntList *chosen,
                   Layers *out) {
    const ActionLevel *entries = &graph->elements[level - 1];
    const Mutex *mutex = &graph->action_mutex[level - 1];
    State covered = {0};
    for (int i = 0; i < chosen->count; ++i)
        covered = state_union(covered, entries->data[chosen->data[i]].add);
    while (at < goals->count && state_has(covered, goals->data[at]))
        ++at;
    if (at == goals->count) {
        State pre = {0};
        for (int i = 0; i < chosen->count; ++i)
            pre = state_union(pre, entries->data[chosen->data[i]].pre);
        if (!extract(graph, level - 1, pre, out))
            return false;
        IntList layer = {0};
        for (int i = 0; i < chosen->count; ++i) {
            int action = entries->data[chosen->data[i]].action;
            if (action >= 0)
                int_push(&layer, action);
        }
        if (layer.count > 1)
            qsort(layer.data, (size_t)layer.count, sizeof *layer.data, compare_ints);
        layers_push(out, layer);
        return true;
    }
    int fact = goals->data[at];
    IntList achievers = {0};
    for (int i = 0; i < entries->count; ++i)
        if (entries->data[i].action < 0 && entries->data[i].fact == fact)
            int_push(&achievers, i);
    for (int i = 0; i < entries->count; ++i)
        if (entries->data[i].action >= 0 && state_has(entries->data[i].add, fact))
            int_push(&achievers, i);
    for (int i = 0; i < achievers.count; ++i) {
        int index = achievers.data[i];
        bool compatible = true;
        for (int j = 0; j < chosen->count; ++j)
            if (mutex_has(mutex, index, chosen->data[j])) {
                compatible = false;
                break;
            }
        if (!compatible)
            continue;
        ++graph->result.tried;
        int_push(chosen, index);
        bool success = assign(graph, level, goals, at + 1, chosen, out);
        --chosen->count;
        if (success) {
            int_free(&achievers);
            return true;
        }
    }
    int_free(&achievers);
    return false;
}
static bool extract(PlanningGraph *graph, int level, State goals, Layers *out) {
    if (!level)
        return true;
    if (state_table_get(&graph->memo[level], goals, NULL)) {
        ++graph->result.memo_hits;
        return false;
    }
    ++graph->result.searched;
    IntList numbers = state_numbers(goals), chosen = {0};
    bool success = assign(graph, level, &numbers, 0, &chosen, out);
    int_free(&numbers);
    int_free(&chosen);
    if (!success)
        state_table_set(&graph->memo[level], goals, 0);
    return success;
}
static void expand(PlanningGraph *graph, int level) {
    State previous = graph->facts[level];
    const Mutex *previous_mutex = &graph->fact_mutex[level];
    ActionLevel entries = {0};
    entries.data =
        allocate((size_t)(graph->action_count + state_count(previous)) * sizeof *entries.data);
    for (int i = 0; i < graph->action_count; ++i) {
        GraphElement action = graph->actions[i];
        if (state_contains(previous, action.pre) && mutex_compatible(previous_mutex, action.pre))
            entries.data[entries.count++] = action;
    }
    int real = entries.count;
    for (int fact = 0; fact < 256; ++fact)
        if (state_has(previous, fact)) {
            State one = {0};
            state_put(&one, fact);
            entries.data[entries.count++] = (GraphElement){-1, fact, one, one, {{0}}};
        }
    Mutex mutex = mutex_create(entries.count);
    for (int i = 0; i < entries.count; ++i)
        for (int j = i + 1; j < entries.count; ++j) {
            const GraphElement *a = &entries.data[i], *b = &entries.data[j];
            bool exclusive = state_intersects(a->del, state_union(b->pre, b->add)) ||
                             state_intersects(b->del, state_union(a->pre, a->add));
            if (!exclusive)
                for (int p = 0; p < 256 && !exclusive; ++p)
                    if (state_has(a->pre, p))
                        for (int q = 0; q < 256; ++q)
                            if (state_has(b->pre, q) && mutex_has(previous_mutex, p, q)) {
                                exclusive = true;
                                break;
                            }
            if (exclusive)
                mutex_put(&mutex, i, j);
        }
    lines_push(&graph->result.logs, format_text("action level %d: actions=%d noops=%d mutexes=%d",
                                                level, real, state_count(previous), mutex.count));
    State next = {0};
    IntList achievers[256] = {0};
    for (int i = 0; i < entries.count; ++i) {
        next = state_union(next, entries.data[i].add);
        for (int fact = 0; fact < 256; ++fact)
            if (state_has(entries.data[i].add, fact))
                int_push(&achievers[fact], i);
    }
    Mutex next_mutex = mutex_create(256);
    for (int p = 0; p < 256; ++p)
        if (state_has(next, p))
            for (int q = p + 1; q < 256; ++q)
                if (state_has(next, q)) {
                    bool exclusive = true;
                    for (int x = 0; x < achievers[p].count && exclusive; ++x)
                        for (int y = 0; y < achievers[q].count; ++y)
                            if (!mutex_has(&mutex, achievers[p].data[x], achievers[q].data[y])) {
                                exclusive = false;
                                break;
                            }
                    if (exclusive)
                        mutex_put(&next_mutex, p, q);
                }
    for (int i = 0; i < 256; ++i)
        int_free(&achievers[i]);
    graph->elements[level] = entries;
    graph->action_mutex[level] = mutex;
    graph->facts[level + 1] = next;
    graph->fact_mutex[level + 1] = next_mutex;
}
GraphPlanResult graph_plan(const GraphElement *actions, int action_count, State initial, State goal,
                           int limit) {
    PlanningGraph *graph = allocate(sizeof *graph);
    graph->actions = actions;
    graph->action_count = action_count;
    graph->facts[0] = initial;
    graph->fact_mutex[0] = mutex_create(256);
    int last = 0;
    for (int level = 0;; ++level) {
        last = level;
        State facts = graph->facts[level];
        const Mutex *mutex = &graph->fact_mutex[level];
        lines_push(&graph->result.logs, format_text("fact level %d: facts=%d mutexes=%d", level,
                                                    state_count(facts), mutex->count));
        bool attempted = state_contains(facts, goal) && mutex_compatible(mutex, goal);
        if (attempted) {
            Value searched = graph->result.searched, hits = graph->result.memo_hits;
            Layers layers = {0};
            bool success = extract(graph, level, goal, &layers);
            lines_push(&graph->result.logs,
                       format_text("extract level %d: %s searched=%lld memo_hits=%lld", level,
                                   success ? "success" : "fail", graph->result.searched - searched,
                                   graph->result.memo_hits - hits));
            if (success) {
                graph->result.status = "solved";
                graph->result.layers = layers;
                for (int i = 0; i < layers.count; ++i)
                    for (int j = 0; j < layers.data[i].count; ++j)
                        int_push(&graph->result.plan, layers.data[i].data[j]);
                break;
            }
            layers_free(&layers);
        } else if (level && state_count(facts) == state_count(graph->facts[level - 1]) &&
                   mutex->count == graph->fact_mutex[level - 1].count) {
            graph->result.status = "unreachable";
            break;
        }
        if (level == limit) {
            graph->result.status = "level limit";
            break;
        }
        expand(graph, level);
    }
    for (int i = 0; i <= last; ++i) {
        free(graph->fact_mutex[i].bits);
        state_table_free(&graph->memo[i]);
        if (i < last) {
            free(graph->elements[i].data);
            free(graph->action_mutex[i].bits);
        }
    }
    GraphPlanResult out = graph->result;
    free(graph);
    return out;
}
