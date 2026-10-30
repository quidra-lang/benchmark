#include "mapf.h"
#include <stdlib.h>
#include <string.h>
Path *path_new(void) {
    Path *p = allocate(sizeof(*p));
    *p = (Path){.references = 1};
    return p;
}
void path_append(Path *p, int cell) {
    if (p->count == p->capacity) {
        p->capacity = p->capacity ? 2 * p->capacity : 16;
        p->cells = resize(p->cells, (size_t)p->capacity * sizeof(int));
    }
    p->cells[p->count++] = cell;
}
Path *path_retain(Path *p) {
    if (p)
        ++p->references;
    return p;
}
void path_release(Path *p) {
    if (p && !--p->references) {
        free(p->cells);
        free(p);
    }
}
Plan plan_copy(const Plan *p) {
    Plan result = *p;
    for (int i = 0; i < result.count; ++i)
        path_retain(result.paths[i]);
    return result;
}
void plan_release(Plan *p) {
    for (int i = 0; i < p->count; ++i)
        path_release(p->paths[i]);
    *p = (Plan){0};
}
Prohibitions prohibitions_new(const Grid *g, int max_time) {
    Prohibitions b = {.cells = g->width * g->height, .width = g->width, .max_time = max_time};
    size_t size = (size_t)(max_time + 1) * b.cells;
    b.states = allocate(size);
    b.moves = allocate(size);
    memset(b.states, 0, size);
    memset(b.moves, 0, size);
    for (int i = 0; i < b.cells; ++i)
        b.permanent[i] = -1;
    return b;
}
void prohibitions_free(Prohibitions *b) {
    free(b->states);
    free(b->moves);
}
static uint8_t move_bit(const Prohibitions *b, int u, int v) {
    int d = v - u;
    return d == -b->width ? 1 : d == 1 ? 2 : d == b->width ? 4 : 8;
}
bool allowed(const Prohibitions *b, int u, int v, int time) {
    if (b->states[(size_t)time * b->cells + v])
        return false;
    if (b->permanent[v] >= 0 && b->permanent[v] <= time)
        return false;
    return u == v || !(b->moves[(size_t)time * b->cells + u] & move_bit(b, u, v));
}
int arrival_allowed(const Prohibitions *b, int goal) {
    int result = 0;
    for (int t = 0; t <= b->max_time; ++t)
        if (b->states[(size_t)t * b->cells + goal])
            result = t + 1;
    return result;
}
void reserve_path(Prohibitions *b, const Path *path, int start, bool permanent) {
    for (int k = 0; k < path->count; ++k) {
        int c = path->cells[k], time = start + k;
        b->states[(size_t)time * b->cells + c] = 1;
        if (k && c != path->cells[k - 1])
            b->moves[(size_t)time * b->cells + c] |= move_bit(b, c, path->cells[k - 1]);
    }
    if (permanent) {
        int goal = path->cells[path->count - 1], time = start + path->count - 1;
        if (b->permanent[goal] < 0 || time < b->permanent[goal])
            b->permanent[goal] = time;
    }
}
Prohibitions constraint_prohibitions(const Grid *g, int maximum,
                                     const ConstraintList *constraints) {
    if (constraints)
        for (size_t i = 0; i < constraints->count; ++i)
            if (constraints->items[i].time > maximum)
                maximum = constraints->items[i].time;
    Prohibitions b = prohibitions_new(g, maximum);
    if (constraints)
        for (size_t i = 0; i < constraints->count; ++i) {
            Constraint c = constraints->items[i];
            if (c.edge)
                b.moves[(size_t)c.time * b.cells + c.u] |= move_bit(&b, c.u, c.v);
            else
                b.states[(size_t)c.time * b.cells + c.v] = 1;
        }
    return b;
}
typedef struct {
    int cell, time, f, g, parent;
} SearchState;
static bool search_less(const SearchState *states, int a, int b) {
    if (states[a].f != states[b].f)
        return states[a].f < states[b].f;
    if (states[a].g != states[b].g)
        return states[a].g > states[b].g;
    return a < b;
}
static void heap_push(int *heap, int *count, int index, const SearchState *states) {
    int at = (*count)++;
    while (at) {
        int parent = (at - 1) / 2;
        if (!search_less(states, index, heap[parent]))
            break;
        heap[at] = heap[parent];
        at = parent;
    }
    heap[at] = index;
}
static int heap_pop(int *heap, int *count, const SearchState *states) {
    int result = heap[0], last = heap[--*count];
    if (*count) {
        int at = 0;
        while (2 * at + 1 < *count) {
            int child = 2 * at + 1;
            if (child + 1 < *count && search_less(states, heap[child + 1], heap[child]))
                ++child;
            if (!search_less(states, heap[child], last))
                break;
            heap[at] = heap[child];
            at = child;
        }
        heap[at] = last;
    }
    return result;
}
Path *low_level(const Grid *g, int agent, int start, int t0, int tmax, const Prohibitions *b,
                bool window, Counters *counter) {
    ++counter->searches;
    int cells = g->width * g->height, maximum = (tmax - t0 + 1) * cells,
        arrival = arrival_allowed(b, g->agents[agent].goal);
    SearchState *states = allocate((size_t)maximum * sizeof(SearchState));
    int *heap = allocate((size_t)maximum * sizeof(int));
    uint8_t *generated = allocate((size_t)maximum);
    memset(generated, 0, (size_t)maximum);
    states[0] = (SearchState){start, t0, g->distance[agent][start], 0, -1};
    generated[start] = 1;
    heap[0] = 0;
    int state_count = 1, open_count = 1;
    Path *result = NULL;
    while (open_count) {
        int index = heap_pop(heap, &open_count, states);
        SearchState state = states[index];
        if (++counter->expansions > counter->limit) {
            counter->aborted = true;
            break;
        }
        if ((state.cell == g->agents[agent].goal && state.time >= arrival) ||
            (window && state.time == tmax)) {
            result = path_new();
            while (index >= 0) {
                path_append(result, states[index].cell);
                index = states[index].parent;
            }
            for (int i = 0, j = result->count - 1; i < j; ++i, --j) {
                int value = result->cells[i];
                result->cells[i] = result->cells[j];
                result->cells[j] = value;
            }
            break;
        }
        if (state.time == tmax)
            continue;
        Destinations next = destinations(g, state.cell);
        for (int i = 0; i < next.count; ++i) {
            int v = next.items[i], distance = state.time + 1 - t0, key = distance * cells + v;
            if (g->distance[agent][v] < 0 || generated[key] ||
                !allowed(b, state.cell, v, state.time + 1))
                continue;
            generated[key] = 1;
            int serial = state_count++;
            states[serial] =
                (SearchState){v, state.time + 1, distance + g->distance[agent][v], distance, index};
            heap_push(heap, &open_count, serial, states);
        }
    }
    free(states);
    free(heap);
    free(generated);
    return result;
}
