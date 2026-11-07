#include "railway.h"
#include <string.h>

static const char *const properties[4] = {"OCCUPANCY", "POINT_MOTION", "CONFLICT",
                                          "SIGNAL_PASSING"};
void safety_violation(Safety *s, int time, int property, const char *details) {
    ++s->violations[property];
    lines_add(&s->records, format_text("VIOLATION %d %s %s", time, properties[property], details));
}
void safety_signal_passing(Safety *s, int time, const Train *t, const Signal *g) {
    ++s->checks[3];
    if (g->aspect == ASPECT_RED) {
        char details[27];
        snprintf(details, sizeof(details), "%s %s", t->name, g->name);
        safety_violation(s, time, 3, details);
    }
}
static bool active(RouteState state) { return state == ROUTE_LOCKED || state == ROUTE_APPROACH; }
void safety_check(Safety *s, int time, const Layout *l, const Interlocking *i,
                  const Train trains[26], int train_count) {
    for (int n = 0; n < l->section_count; ++n) {
        const Section *section = &l->sections[n];
        ++s->checks[0];
        if (bit_count(section->occupants) >= 2) {
            char details[512];
            snprintf(details, sizeof(details), "%s ", section->name);
            bool first = true;
            for (int t = 0; t < train_count; ++t)
                if (section->occupants & (UINT32_C(1) << t)) {
                    if (!first)
                        strcat(details, ",");
                    strcat(details, trains[t].name);
                    first = false;
                }
            safety_violation(s, time, 0, details);
        }
    }
    for (int n = 0; n < l->point_count; ++n) {
        const Point *point = &l->points[n];
        if (!point->moving)
            continue;
        ++s->checks[1];
        char details[32];
        if (l->sections[point->common].occupants) {
            snprintf(details, sizeof(details), "%s occupied", point->name);
            safety_violation(s, time, 1, details);
        } else
            for (int r = 0; r < i->count; ++r)
                if (((point->normal_locks | point->reverse_locks) & (UINT64_C(1) << r)) &&
                    (i->routes[r].state == ROUTE_USED || i->routes[r].state == ROUTE_APPROACH)) {
                    snprintf(details, sizeof(details), "%s locked", point->name);
                    safety_violation(s, time, 1, details);
                    break;
                }
    }
    for (int a = 0; a < i->count; ++a) {
        const Route *first = &i->routes[a];
        if (!active(first->state))
            continue;
        for (int b = a + 1; b < i->count; ++b) {
            const Route *second = &i->routes[b];
            if (!active(second->state))
                continue;
            ++s->checks[2];
            bool conflict = false;
            for (size_t j = 0; j < first->conflict_count; ++j)
                conflict = conflict || first->conflicts[j] == b;
            for (size_t j = 0; j < second->conflict_count; ++j)
                conflict = conflict || second->conflicts[j] == a;
            if (conflict) {
                char details[27];
                snprintf(details, sizeof(details), "%s %s", first->name, second->name);
                safety_violation(s, time, 2, details);
            }
        }
    }
}
void safety_write(const Safety *s, FILE *file) {
    bool safe = true;
    for (int p = 0; p < 4; ++p) {
        safe = safe && s->violations[p] == 0;
        fprintf(file, "%s %s checks %d violations %d\n", properties[p],
                s->violations[p] ? "FAIL" : "OK", s->checks[p], s->violations[p]);
    }
    for (size_t j = 0; j < s->records.count; ++j)
        fprintf(file, "%s\n", s->records.items[j]);
    fprintf(file, "RESULT %s\n", safe ? "SAFE" : "UNSAFE");
}
