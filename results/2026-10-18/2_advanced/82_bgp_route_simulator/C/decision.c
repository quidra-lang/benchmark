#include "bgp.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
Attribute *attribute_new(void) {
    Attribute *attribute = allocate(sizeof(*attribute));
    *attribute = (Attribute){.references = 1};
    return attribute;
}
Attribute *attribute_copy(const Attribute *a) {
    Attribute *result = attribute_new();
    result->origin = a->origin;
    result->med = a->med;
    result->path_count = a->path_count;
    if (a->path_count) {
        result->path = allocate(a->path_count * sizeof(int));
        memcpy(result->path, a->path, a->path_count * sizeof(int));
    }
    result->communities = communities_copy(&a->communities);
    return result;
}
Attribute *attribute_retain(Attribute *a) {
    if (a)
        ++a->references;
    return a;
}
void attribute_release(Attribute *a) {
    if (a && !--a->references) {
        free(a->path);
        free(a->communities.items);
        free(a);
    }
}
bool attribute_equal(const Attribute *a, const Attribute *b) {
    if (!a || !b)
        return a == b;
    return a->origin == b->origin && a->med == b->med && a->path_count == b->path_count &&
           a->communities.count == b->communities.count &&
           (!a->path_count || memcmp(a->path, b->path, a->path_count * sizeof(int)) == 0) &&
           (!a->communities.count || memcmp(a->communities.items, b->communities.items,
                                            a->communities.count * sizeof(uint32_t)) == 0);
}
Route route_retain(Route route) {
    attribute_retain(route.attribute);
    return route;
}
void route_release(Route *route) {
    attribute_release(route->attribute);
    *route = (Route){0};
}
bool route_equal(Route a, Route b) {
    if (!a.attribute || !b.attribute)
        return a.attribute == b.attribute;
    return a.local == b.local && a.preference == b.preference && a.link == b.link &&
           attribute_equal(a.attribute, b.attribute);
}
int origin_rank(const char *name) {
    return strcmp(name, "IGP") == 0 ? 0 : strcmp(name, "EGP") == 0 ? 1 : 2;
}
const char *origin_name(int rank) {
    static const char *names[] = {"IGP", "EGP", "INCOMPLETE"};
    return names[rank];
}
static int64_t stage_value(const Route *route, int stage, const Topology *t) {
    if (stage == 0)
        return -(int64_t)route->preference;
    if (stage == 1)
        return (int64_t)route->attribute->path_count;
    if (stage == 2)
        return route->attribute->origin;
    if (stage == 4) {
        for (int i = 0; i < t->node_count; ++i)
            if (t->nodes[i].number == route->attribute->path[0])
                return (int64_t)t->nodes[i].router;
    }
    return route->link->number;
}
int best_route(const Route *routes, int count, const Topology *t, const char **reason) {
    int candidates[100], kept[100];
    for (int i = 0; i < count; ++i)
        candidates[i] = i;
    if (count == 1) {
        *reason = "ONLY";
        return 0;
    }
    static const char *names[] = {"LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK"};
    for (int stage = 0; stage < 6; ++stage) {
        int remaining = 0;
        if (stage == 3) {
            for (int i = 0; i < count; ++i) {
                const Route *r = &routes[candidates[i]];
                bool keep = true;
                for (int j = 0; j < count; ++j) {
                    const Route *q = &routes[candidates[j]];
                    if (r->attribute->path[0] == q->attribute->path[0] &&
                        q->attribute->med < r->attribute->med)
                        keep = false;
                }
                if (keep)
                    kept[remaining++] = candidates[i];
            }
        } else {
            int64_t minimum = INT64_MAX;
            for (int i = 0; i < count; ++i) {
                int64_t value = stage_value(&routes[candidates[i]], stage, t);
                if (value < minimum)
                    minimum = value;
            }
            for (int i = 0; i < count; ++i)
                if (stage_value(&routes[candidates[i]], stage, t) == minimum)
                    kept[remaining++] = candidates[i];
        }
        count = remaining;
        memcpy(candidates, kept, (size_t)count * sizeof(int));
        if (count == 1) {
            *reason = names[stage];
            return candidates[0];
        }
    }
    *reason = "LINK";
    return candidates[0];
}
