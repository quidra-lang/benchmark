#include "railway.h"

static int cleared_route(const Layout *l, const Interlocking *i, int signal) {
    for (int n = 0; n < i->count; ++n) {
        const Route *r = &i->routes[n];
        if (r->start != signal || r->state != ROUTE_LOCKED)
            continue;
        bool clear = true;
        for (size_t j = 0; j < requirement_count(r); ++j) {
            Requirement q = requirement_at(r, j);
            const Point *p = &l->points[q.point];
            clear = clear && detected(p) && p->position == q.position;
        }
        for (int j = 0; j < r->section_count; ++j)
            clear = clear && !occupied(&l->sections[r->sections[j]]);
        for (int j = 0; j < r->overlap_count; ++j)
            clear = clear && !occupied(&l->sections[r->overlap[j]]);
        if (clear)
            return n;
    }
    return -1;
}
void signal_aspects(const Layout *l, const Interlocking *i, Aspect out[30]) {
    int cleared[30];
    for (int g = 0; g < l->signal_count; ++g)
        cleared[g] = cleared_route(l, i, g);
    for (int g = 0; g < l->signal_count; ++g) {
        out[g] = ASPECT_RED;
        if (cleared[g] < 0)
            continue;
        const Route *r = &i->routes[cleared[g]];
        int finish = signal_index(l, r->finish);
        if (finish >= 0)
            out[g] = cleared[finish] >= 0 ? ASPECT_GREEN : ASPECT_YELLOW;
        else
            out[g] = buffer_index(l, r->finish) >= 0 ? ASPECT_YELLOW : ASPECT_GREEN;
    }
}
