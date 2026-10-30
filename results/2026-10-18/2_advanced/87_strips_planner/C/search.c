#include "planner.h"
bool applicable(const GroundAction *action, State state) {
    return state_contains(state, action->pre) && !state_intersects(state, action->neg);
}
State apply(const GroundAction *action, State state) {
    return state_union(state_without(state, action->del), action->add);
}
typedef struct {
    State state;
    Value g, h, f;
    int depth, serial, parent, action;
} SearchNode;
typedef struct {
    SearchNode *data;
    int count, capacity;
    IntList heap;
} SearchOpen;
static bool node_before(const SearchOpen *open, int a, int b) {
    const SearchNode *left = &open->data[a], *right = &open->data[b];
    if (left->f != right->f)
        return left->f < right->f;
    if (left->h != right->h)
        return left->h < right->h;
    return left->serial < right->serial;
}
static void open_push(SearchOpen *open, SearchNode node) {
    if (open->count == open->capacity) {
        open->capacity = open->capacity ? open->capacity * 2 : 128;
        open->data = resize(open->data, (size_t)open->capacity * sizeof *open->data);
    }
    int index = open->count++;
    open->data[index] = node;
    int_push(&open->heap, index);
    int at = open->heap.count - 1;
    while (at) {
        int parent = (at - 1) / 2;
        if (!node_before(open, open->heap.data[at], open->heap.data[parent]))
            break;
        int value = open->heap.data[at];
        open->heap.data[at] = open->heap.data[parent];
        open->heap.data[parent] = value;
        at = parent;
    }
}
static int open_pop(SearchOpen *open) {
    int out = open->heap.data[0], last = open->heap.data[--open->heap.count];
    if (!open->heap.count)
        return out;
    open->heap.data[0] = last;
    int at = 0;
    for (;;) {
        int child = at * 2 + 1;
        if (child >= open->heap.count)
            break;
        if (child + 1 < open->heap.count &&
            node_before(open, open->heap.data[child + 1], open->heap.data[child]))
            ++child;
        if (!node_before(open, open->heap.data[child], open->heap.data[at]))
            break;
        int value = open->heap.data[at];
        open->heap.data[at] = open->heap.data[child];
        open->heap.data[child] = value;
        at = child;
    }
    return out;
}
static Value f_value(SearchSettings settings, Value cost, int depth, Value h, int weight) {
    if (!strcmp(settings.algorithm, "bfs"))
        return depth;
    if (!strcmp(settings.algorithm, "ucs"))
        return cost;
    if (!strcmp(settings.algorithm, "gbfs"))
        return h;
    return cost + (!strcmp(settings.algorithm, "wastar") ? weight : 1) * h;
}
static SearchResult best_first(GroundProblem *ground, State start, SearchSettings settings,
                               int budget, int weight) {
    SearchResult out = {0};
    Value initial_h = heuristic_value(heuristics(ground, start), settings.heuristic);
    if (initial_h == INFINITY_VALUE) {
        out.status = "dead end";
        return out;
    }
    SearchOpen open = {0};
    open_push(&open, (SearchNode){start, 0, initial_h, f_value(settings, 0, 0, initial_h, weight),
                                  0, 0, -1, -1});
    StateTable table = {0};
    state_table_set(&table, start, 0);
    bool cost_based = !strcmp(settings.algorithm, "ucs") || !strcmp(settings.algorithm, "astar") ||
                      !strcmp(settings.algorithm, "wastar");
    while (open.heap.count) {
        int index = open_pop(&open);
        SearchNode node = open.data[index];
        Value previous;
        state_table_get(&table, node.state, &previous);
        if (cost_based && node.g > previous)
            continue;
        if (state_contains(node.state, ground->goal)) {
            out.status = "solved";
            for (int at = index; open.data[at].parent >= 0; at = open.data[at].parent)
                int_push(&out.plan, open.data[at].action);
            for (int i = 0; i < out.plan.count / 2; ++i) {
                int value = out.plan.data[i];
                out.plan.data[i] = out.plan.data[out.plan.count - 1 - i];
                out.plan.data[out.plan.count - 1 - i] = value;
            }
            break;
        }
        if (out.expanded == budget) {
            out.status = "budget";
            break;
        }
        ++out.expanded;
        for (int i = 0; i < ground->action_count; ++i) {
            const GroundAction *action = &ground->actions[i];
            if (!applicable(action, node.state))
                continue;
            ++out.generated;
            State next = apply(action, node.state);
            Value cost = node.g + action->cost;
            bool seen = state_table_get(&table, next, &previous);
            if (seen && (!cost_based || previous <= cost))
                continue;
            state_table_set(&table, next, cost);
            Value h = heuristic_value(heuristics(ground, next), settings.heuristic);
            if (h == INFINITY_VALUE)
                continue;
            open_push(&open, (SearchNode){next, cost, h,
                                          f_value(settings, cost, node.depth + 1, h, weight),
                                          node.depth + 1, open.count, index, i});
        }
    }
    if (!out.status)
        out.status = "exhausted";
    free(open.data);
    int_free(&open.heap);
    state_table_free(&table);
    return out;
}
typedef struct {
    State state;
    IntList path;
} LocalNode;
static SearchResult hill_climbing(GroundProblem *ground, State start, SearchSettings settings,
                                  int budget) {
    SearchResult out = {0};
    State current = start;
    Value current_h = heuristic_value(heuristics(ground, current), settings.heuristic);
    if (current_h == INFINITY_VALUE) {
        out.status = "dead end";
        return out;
    }
    while (!out.status) {
        if (state_contains(current, ground->goal)) {
            out.status = "solved";
            break;
        }
        int count = 1, capacity = 64;
        LocalNode *queue = allocate((size_t)capacity * sizeof *queue);
        queue[0] = (LocalNode){current, {0}};
        StateTable visited = {0};
        state_table_set(&visited, current, 0);
        bool improved = false;
        for (int head = 0; head < count && !improved; ++head) {
            LocalNode node = queue[head];
            if (out.expanded == budget) {
                out.status = "budget";
                break;
            }
            ++out.expanded;
            Heuristic *estimate = heuristics(ground, node.state);
            for (int i = 0; i < estimate->helpful.count; ++i) {
                int action = estimate->helpful.data[i];
                ++out.generated;
                State next = apply(&ground->actions[action], node.state);
                if (state_table_get(&visited, next, NULL))
                    continue;
                state_table_set(&visited, next, 0);
                Value h = heuristic_value(heuristics(ground, next), settings.heuristic);
                if (h == INFINITY_VALUE)
                    continue;
                IntList path = int_copy(&node.path);
                int_push(&path, action);
                if (h < current_h) {
                    for (int j = 0; j < path.count; ++j)
                        int_push(&out.plan, path.data[j]);
                    int_free(&path);
                    current = next;
                    current_h = h;
                    improved = true;
                    break;
                }
                if (count == capacity) {
                    capacity *= 2;
                    queue = resize(queue, (size_t)capacity * sizeof *queue);
                }
                queue[count++] = (LocalNode){next, path};
            }
        }
        for (int i = 0; i < count; ++i)
            int_free(&queue[i].path);
        free(queue);
        state_table_free(&visited);
        if (!out.status && !improved)
            out.status = "stuck";
    }
    return out;
}
SearchResult search(GroundProblem *ground, State start, SearchSettings settings, int budget,
                    int weight) {
    return !strcmp(settings.algorithm, "ehc") ? hill_climbing(ground, start, settings, budget)
                                              : best_first(ground, start, settings, budget, weight);
}
