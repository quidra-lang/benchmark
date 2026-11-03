#include "mapf.h"
#include <stdlib.h>
#include <string.h>
ConstraintList *constraints_retain(ConstraintList *list) {
    if (list)
        ++list->references;
    return list;
}
ConstraintList *constraints_append(const ConstraintList *old, Constraint value) {
    ConstraintList *result = allocate(sizeof(*result));
    result->references = 1;
    result->count = (old ? old->count : 0) + 1;
    result->items = allocate(result->count * sizeof(Constraint));
    if (old && old->count)
        memcpy(result->items, old->items, old->count * sizeof(Constraint));
    result->items[result->count - 1] = value;
    return result;
}
void constraints_release(ConstraintList *list) {
    if (list && !--list->references) {
        free(list->items);
        free(list);
    }
}
int position(const Path *path, int time) {
    return path->cells[time < path->count ? time : path->count - 1];
}
void plan_costs(const Plan *paths, int *soc, int *makespan) {
    *soc = *makespan = 0;
    for (int i = 0; i < paths->count; ++i) {
        int cost = paths->paths[i]->count - 1;
        *soc += cost;
        if (cost > *makespan)
            *makespan = cost;
    }
}
Conflicts conflicts(const Plan *paths) {
    Conflicts result = {0};
    int soc, last;
    plan_costs(paths, &soc, &last);
    for (int t = 1; t <= last; ++t)
        for (int a = 0; a < paths->count; ++a)
            for (int b = a + 1; b < paths->count; ++b) {
                int u = position(paths->paths[a], t - 1), v = position(paths->paths[a], t),
                    bu = position(paths->paths[b], t - 1), bv = position(paths->paths[b], t);
                bool vertex = v == bv, edge = !vertex && v == bu && bv == u;
                if (!vertex && !edge)
                    continue;
                if (result.count == result.capacity) {
                    result.capacity = result.capacity ? result.capacity * 2 : 32;
                    result.items = resize(result.items, result.capacity * sizeof(Conflict));
                }
                result.items[result.count++] = (Conflict){t, a, b, vertex ? v : u, v, edge};
            }
    return result;
}
Constraint conflict_constraint(Conflict c, int agent) {
    return c.edge && agent == c.b ? (Constraint){agent, c.time, c.v, c.u, true}
                                  : (Constraint){agent, c.time, c.u, c.v, c.edge};
}
bool node_less(const TreeNode *a, const TreeNode *b) {
    if (a->cost != b->cost)
        return a->cost < b->cost;
    if (a->conflicts.count != b->conflicts.count)
        return a->conflicts.count < b->conflicts.count;
    return a->number < b->number;
}
