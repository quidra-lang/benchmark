#include "geometry.h"
#include <stdlib.h>
#include <string.h>
typedef struct {
    Fraction position;
    GhNode *node;
} Inserted;
typedef struct {
    Inserted *items;
    size_t count;
} InsertedList;
static GhNode *new_node(GhGraph *g, Point p, int side, OriginalLine outgoing) {
    GhNode *node = allocate(sizeof(*node));
    *node = (GhNode){.point = p, .side = side, .outgoing = outgoing};
    if (g->node_count == g->node_capacity) {
        g->node_capacity = g->node_capacity ? 2 * g->node_capacity : 64;
        g->node_storage = resize(g->node_storage, g->node_capacity * sizeof(GhNode *));
    }
    g->node_storage[g->node_count++] = node;
    return node;
}
static void node_add(NodeList *list, GhNode *node) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? 2 * list->capacity : 16;
        list->items = resize(list->items, list->capacity * sizeof(GhNode *));
    }
    list->items[list->count++] = node;
}
static int inserted_compare(const void *left, const void *right) {
    return fraction_compare(((const Inserted *)left)->position,
                            ((const Inserted *)right)->position);
}
GhGraph *graph_new(const Rings *first, const Rings *second) {
    GhGraph *g = allocate(sizeof(*g));
    *g = (GhGraph){.rings = {rings_copy(first), rings_copy(second)}};
    InsertedList **slots[2];
    for (int side = 0; side < 2; ++side) {
        size_t count = g->rings[side].count;
        slots[side] = allocate(count * sizeof(InsertedList *));
        g->nodes[side] = allocate(count * sizeof(NodeList));
        memset(g->nodes[side], 0, count * sizeof(NodeList));
        g->initial_inside[side] = allocate(count * sizeof(bool));
        for (size_t i = 0; i < count; ++i) {
            size_t edges = g->rings[side].items[i]->count;
            slots[side][i] = allocate(edges * sizeof(InsertedList));
            memset(slots[side][i], 0, edges * sizeof(InsertedList));
        }
    }
    for (size_t i = 0; i < first->count; ++i)
        for (size_t e = 0; e < first->items[i]->count; ++e)
            for (size_t j = 0; j < second->count; ++j)
                for (size_t f = 0; f < second->items[j]->count; ++f) {
                    Intersection value;
                    if (!crossing(first->items[i]->edges[e], second->items[j]->edges[f], &value))
                        continue;
                    GhNode *a = new_node(g, value.point, 0, first->items[i]->edges[e]),
                           *b = new_node(g, value.point, 1, second->items[j]->edges[f]);
                    Crossing *record = allocate(sizeof(*record));
                    *record = (Crossing){value.point, a, b, g->crossing_count};
                    if (g->crossing_count == g->crossing_capacity) {
                        g->crossing_capacity = g->crossing_capacity ? 2 * g->crossing_capacity : 32;
                        g->crossing_storage =
                            resize(g->crossing_storage, g->crossing_capacity * sizeof(Crossing *));
                    }
                    g->crossing_storage[g->crossing_count++] = record;
                    a->crossing = b->crossing = record;
                    a->other = b;
                    b->other = a;
                    InsertedList *x = &slots[0][i][e], *y = &slots[1][j][f];
                    x->items = resize(x->items, (x->count + 1) * sizeof(Inserted));
                    x->items[x->count++] = (Inserted){value.first, a};
                    y->items = resize(y->items, (y->count + 1) * sizeof(Inserted));
                    y->items[y->count++] = (Inserted){value.second, b};
                }
    g->crossings = allocate(g->crossing_count * sizeof(Crossing *));
    for (int side = 0; side < 2; ++side) {
        for (size_t i = 0; i < g->rings[side].count; ++i) {
            Ring *ring = g->rings[side].items[i];
            NodeList *list = &g->nodes[side][i];
            for (size_t e = 0; e < ring->count; ++e) {
                node_add(list, new_node(g, ring->points[e], side, ring->edges[e]));
                InsertedList *inserted = &slots[side][i][e];
                if (inserted->count)
                    qsort(inserted->items, inserted->count, sizeof(Inserted), inserted_compare);
                for (size_t j = 0; j < inserted->count; ++j)
                    node_add(list, inserted->items[j].node);
                free(inserted->items);
            }
            bool state = interior(ring->points[0], &g->rings[1 - side]);
            g->initial_inside[side][i] = state;
            if (state) {
                if (side == 0)
                    ++g->na;
                else
                    ++g->nb;
            }
            for (size_t k = 0; k < list->count; ++k) {
                GhNode *node = list->items[k];
                node->previous = list->items[(k + list->count - 1) % list->count];
                node->next = list->items[(k + 1) % list->count];
                if (node->crossing) {
                    node->entering = !state;
                    state = !state;
                    if (side == 0)
                        g->crossings[g->order_count++] = node->crossing;
                }
            }
            free(slots[side][i]);
        }
        free(slots[side]);
    }
    return g;
}
Rings traverse(const GhGraph *g, bool invert_first, bool invert_second) {
    bool inverted[2] = {invert_first, invert_second};
    bool *visited = allocate(g->crossing_count * sizeof(bool));
    memset(visited, 0, g->crossing_count * sizeof(bool));
    Rings result = {0};
    for (size_t i = 0; i < g->order_count; ++i) {
        Crossing *start = g->crossings[i];
        if (visited[start->index])
            continue;
        Ring *ring = ring_new();
        GhNode *current = start->first;
        for (;;) {
            visited[current->crossing->index] = true;
            ring_point(ring, current->point);
            bool forward = current->entering != inverted[current->side];
            GhNode *moving = current;
            for (;;) {
                GhNode *next = forward ? moving->next : moving->previous;
                ring_edge(ring, forward ? moving->outgoing : reverse_line(next->outgoing));
                moving = next;
                if (moving->crossing)
                    break;
                ring_point(ring, moving->point);
            }
            if (moving->crossing == start)
                break;
            current = moving->other;
        }
        rings_add(&result, ring);
    }
    for (int side = 0; side < 2; ++side)
        for (size_t i = 0; i < g->rings[side].count; ++i) {
            bool crossed = false;
            for (size_t j = 0; j < g->nodes[side][i].count; ++j)
                crossed = crossed || g->nodes[side][i].items[j]->crossing != NULL;
            if (!crossed && g->initial_inside[side][i] != inverted[side])
                rings_add(&result, ring_retain(g->rings[side].items[i]));
        }
    free(visited);
    return result;
}
void graph_free(GhGraph *g) {
    for (int side = 0; side < 2; ++side) {
        for (size_t i = 0; i < g->rings[side].count; ++i)
            free(g->nodes[side][i].items);
        free(g->nodes[side]);
        free(g->initial_inside[side]);
        rings_free(&g->rings[side]);
    }
    for (size_t i = 0; i < g->node_count; ++i)
        free(g->node_storage[i]);
    for (size_t i = 0; i < g->crossing_count; ++i)
        free(g->crossing_storage[i]);
    free(g->node_storage);
    free(g->crossing_storage);
    free(g->crossings);
    free(g);
}
