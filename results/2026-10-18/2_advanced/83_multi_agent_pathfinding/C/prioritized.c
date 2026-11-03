#include "mapf.h"
PriorityResult prioritized(const Grid *g, const Parameters *p, const int *order, int number,
                           Run *r) {
    Prohibitions b = prohibitions_new(g, p->horizon);
    PriorityResult result = {.paths = {.count = g->agent_count}, .failed = -1};
    for (int i = 0; i < g->agent_count; ++i) {
        int agent = order[i], before = r->counter.expansions;
        Path *path =
            low_level(g, agent, g->agents[agent].start, 0, p->horizon, &b, false, &r->counter);
        if (r->counter.aborted) {
            result.failed = agent;
            plan_release(&result.paths);
            break;
        }
        if (!path) {
            lines_add(&r->trace, format_text("order %d agent %c failed expansions %d", number,
                                             'A' + agent, r->counter.expansions - before));
            result.failed = agent;
            plan_release(&result.paths);
            break;
        }
        lines_add(&r->trace,
                  format_text("order %d agent %c cost %d expansions %d", number, 'A' + agent,
                              path->count - 1, r->counter.expansions - before));
        result.paths.paths[agent] = path;
        ++result.planned;
        reserve_path(&b, path, 0, true);
    }
    prohibitions_free(&b);
    return result;
}
