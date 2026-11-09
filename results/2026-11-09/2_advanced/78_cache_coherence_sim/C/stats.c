#include "coherence.h"
const char *transaction_names[5] = {"BusRd", "BusRdX", "BusUpgr", "BusWr", "WB"};
const char *service_names[6] = {"l1", "upgrade", "through", "cache", "l2", "memory"};
const char *miss_names[4] = {"compulsory", "capacity", "conflict", "coherence"};
char *fraction(Number p, Number q) {
    Number a = p, b = q;
    while (b) {
        Number next = a % b;
        a = b;
        b = next;
    }
    return format("%lld/%lld", p / a, q / a);
}
char *decimal(Number p, Number q) {
    Number value = (2 * p * 100 + q) / (2 * q);
    return format("%lld.%02lld", value / 100, value % 100);
}
char *core_string(unsigned cores) {
    char *out = allocate(9);
    int count = 0;
    for (int core = 0; core < 8; ++core)
        if (cores & (1u << core))
            out[count++] = (char)('0' + core);
    return count ? out : "-";
}
char *range_counts(const char *const *names, const Number *counts, int count) {
    Names values = {0};
    for (int i = 0; i < count; ++i)
        Names_add(&values, format("%s:%lld", names[i], counts[i]));
    return join(values, " ");
}
CoreStats total_counters(const CoreStats *cores, int count) {
    CoreStats total = {0};
    for (int k = 0; k < count; ++k) {
        const CoreStats *s = &cores[k];
        total.accesses += s->accesses;
        total.reads += s->reads;
        total.writes += s->writes;
        total.hits += s->hits;
        total.misses += s->misses;
        total.fences += s->fences;
        total.latency += s->latency;
        total.fence_stall += s->fence_stall;
        total.read_latency += s->read_latency;
        total.write_latency += s->write_latency;
        if (s->finish > total.finish)
            total.finish = s->finish;
        for (int i = 0; i < 6; ++i) {
            total.miss_counts[i] += s->miss_counts[i];
            total.service[i] += s->service[i];
        }
        for (int i = 0; i < 5; ++i)
            total.bus[i] += s->bus[i];
        for (int i = 0; i < 4; ++i)
            total.snoop[i] += s->snoop[i];
    }
    return total;
}
Names six_lines(const char *label, const CoreStats *s) {
    Names out = {0};
    Names_add(&out,
              format("%s accesses %lld reads %lld writes %lld hits %lld misses %lld fences %lld",
                     label, s->accesses, s->reads, s->writes, s->hits, s->misses, s->fences));
    Names_add(
        &out,
        format(
            "%s misses compulsory %lld capacity %lld conflict %lld coherence %lld true_sharing %lld false_sharing %lld",
            label, s->miss_counts[0], s->miss_counts[1], s->miss_counts[2], s->miss_counts[3],
            s->miss_counts[4], s->miss_counts[5]));
    Names values = {0};
    for (int i = 0; i < 6; ++i)
        Names_add(&values, format("%s %lld", service_names[i], s->service[i]));
    Names_add(&out, format("%s service %s", label, join(values, " ")));
    values = (Names){0};
    for (int i = 0; i < 5; ++i)
        Names_add(&values, format("%s %lld", transaction_names[i], s->bus[i]));
    Names_add(&out, format("%s bus %s", label, join(values, " ")));
    const char *names[] = {"invalidations_sent", "invalidations_received", "supplied",
                           "back_invalidations"};
    values = (Names){0};
    for (int i = 0; i < 4; ++i)
        Names_add(&values, format("%s %lld", names[i], s->snoop[i]));
    Names_add(&out, format("%s snoop %s", label, join(values, " ")));
    Names_add(&out, format("%s time latency %lld amat %s %s fence_stall %lld finish %lld", label,
                           s->latency, fraction(s->latency, s->accesses),
                           decimal(s->latency, s->accesses), s->fence_stall, s->finish));
    return out;
}
