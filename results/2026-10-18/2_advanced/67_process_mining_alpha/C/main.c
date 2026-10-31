#include "mining.h"
#define V(value) ((long long)(value))
typedef struct {
    Trace trace;
    int cases[300], count, keep;
} Variant;
typedef struct {
    Net net;
    Candidate *pairs;
    int pair_count, candidates, causal;
    unsigned activities, starts, ends;
} Discovery;
typedef struct {
    I markings, edges, unsafe, deadlocks, stuck;
    int final;
    unsigned dead;
    Counts follows;
} Exploration;
typedef struct {
    int activity[50], length;
    I weight;
    unsigned followers;
} Prefix;
typedef struct {
    Input input;
    Event *events;
    int event_count;
    Case *cases;
    int case_count;
    char activities[12][21], resources[20][13];
    int activity_count, resource_count;
    Net reference, nets[3];
    I minimum, limit, positive, kept_cases, kept_events;
    Fraction dependency_threshold, relative, loop1_threshold, loop2_threshold, and_threshold;
    Lines errors;
    Log full, filtered;
    Counts counts;
    Variant variants[300];
    int variant_count, variant_by_case[300];
    Replay reference_replays[300];
    Prefix *prefixes;
    int prefix_count;
} Study;
static int string_order(const void *left, const void *right) { return strcmp(left, right); }
static int activity_id(const Study *s, const char *name) {
    for (int i = 0; i < s->activity_count; ++i)
        if (!strcmp(s->activities[i], name))
            return i;
    return -1;
}
static int resource_id(const Study *s, const char *name) {
    for (int i = 0; i < s->resource_count; ++i)
        if (!strcmp(s->resources[i], name))
            return i;
    return -1;
}
static char *mask_names(const Study *s, unsigned mask) {
    const char *list[12];
    int n = 0;
    for (int i = 0; i < s->activity_count; ++i)
        if (mask & (1u << i))
            list[n++] = s->activities[i];
    return names(list, n);
}
static char *place_names(const Net *net, const unsigned char *arcs, int t) {
    const char **list = malloc((size_t)net->place_count * sizeof(char *));
    int n = 0;
    for (int p = 0; p < net->place_count; ++p)
        if (arcs[t * net->place_count + p])
            list[n++] = net->places[p];
    char *out = names(list, n);
    free(list);
    return out;
}
static int trace_order(const int *a, int na, const int *b, int nb) {
    for (int i = 0; i < na && i < nb; ++i)
        if (a[i] != b[i])
            return a[i] - b[i];
    return na - nb;
}
static int variant_order(const void *left, const void *right) {
    const Variant *a = left, *b = right;
    return a->count != b->count ? b->count - a->count
                                : trace_order(a->trace.activity, a->trace.length, b->trace.activity,
                                              b->trace.length);
}
static Fraction parse_fraction(const char *value) {
    I a = 0, b = 1;
    char *end;
    a = strtoll(value, &end, 10);
    if (*end == '/')
        b = strtoll(end + 1, NULL, 10);
    return ratio(a, b);
}
static Relations relations(const Counts *counts, const Counts *triangles, int plus) {
    Relations out = {0};
    for (int a = 0; a < 12; ++a)
        for (int b = 0; b < 12; ++b)
            out.values[a][b] =
                plus ? plus_relation(counts, triangles, a, b) : basic_relation(counts, a, b);
    return out;
}
static void initialize(Study *s) {
    s->input = read_inputs();
    s->reference = read_model();
    s->minimum = strtoll(s->input.values[0], NULL, 10);
    s->limit = strtoll(s->input.values[1], NULL, 10);
    s->positive = strtoll(s->input.values[2], NULL, 10);
    s->dependency_threshold = parse_fraction(s->input.values[3]);
    s->relative = parse_fraction(s->input.values[4]);
    s->loop1_threshold = parse_fraction(s->input.values[5]);
    s->loop2_threshold = parse_fraction(s->input.values[6]);
    s->and_threshold = parse_fraction(s->input.values[7]);
    s->events = calloc(3000, sizeof(Event));
    for (int i = 0; i < s->input.row_count; ++i) {
        Event e = s->input.rows[i];
        if (!timestamp_minutes(e.timestamp, &e.time)) {
            line(&s->errors, "ERROR line %d: bad timestamp %s", e.line, e.timestamp);
            continue;
        }
        int duplicate = 0;
        for (int j = 0; j < s->event_count; ++j) {
            Event *old = &s->events[j];
            if (!strcmp(old->case_id, e.case_id) && !strcmp(old->activity, e.activity) &&
                !strcmp(old->timestamp, e.timestamp)) {
                duplicate = 1;
                break;
            }
        }
        if (duplicate) {
            line(&s->errors, "ERROR line %d: duplicate event %s %s %s", e.line, e.case_id,
                 e.activity, e.timestamp);
            continue;
        }
        s->events[s->event_count++] = e;
        if (activity_id(s, e.activity) < 0)
            strcpy(s->activities[s->activity_count++], e.activity);
        if (resource_id(s, e.resource) < 0)
            strcpy(s->resources[s->resource_count++], e.resource);
    }
    qsort(s->activities, (size_t)s->activity_count, sizeof(s->activities[0]), string_order);
    qsort(s->resources, (size_t)s->resource_count, sizeof(s->resources[0]), string_order);
    s->cases = group_cases(s->events, s->event_count, &s->case_count);
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        Trace *trace = &s->full.entries[s->full.count++];
        trace->length = item->count;
        trace->weight = 1;
        for (int i = 0; i < item->count; ++i)
            trace->activity[i] = item->trace[i] = activity_id(s, item->events[i]->activity);
    }
    s->counts = directly_follows(&s->full);
}
static void build_variants(Study *s) {
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        int v = 0;
        while (v < s->variant_count &&
               trace_order(s->variants[v].trace.activity, s->variants[v].trace.length, item->trace,
                           item->count))
            ++v;
        if (v == s->variant_count) {
            Variant *entry = &s->variants[s->variant_count++];
            entry->trace = s->full.entries[c];
            entry->keep = 1;
            for (int i = 1; i < item->count; ++i)
                if (s->counts.values[item->trace[i - 1]][item->trace[i]] < s->minimum)
                    entry->keep = 0;
        }
        s->variants[v].cases[s->variants[v].count++] = c;
    }
    qsort(s->variants, (size_t)s->variant_count, sizeof(Variant), variant_order);
    for (int v = 0; v < s->variant_count; ++v) {
        Variant *entry = &s->variants[v];
        for (int i = 0; i < entry->count; ++i)
            s->variant_by_case[entry->cases[i]] = v + 1;
        if (entry->keep) {
            Trace trace = entry->trace;
            trace.weight = entry->count;
            s->filtered.entries[s->filtered.count++] = trace;
            s->kept_cases += entry->count;
            s->kept_events += (I)entry->count * trace.length;
        }
    }
}
static Lines summary(Study *s) {
    Lines out = {0};
    for (int i = 0; i < s->errors.count; ++i)
        line(&out, "%s", s->errors.values[i]);
    Event *first = &s->events[0], *last = first;
    for (int i = 1; i < s->event_count; ++i) {
        if (s->events[i].time < first->time)
            first = &s->events[i];
        if (s->events[i].time > last->time)
            last = &s->events[i];
    }
    line(&out,
         "LOG rows %d adopted %d rejected %d cases %d activities %d resources %d first %s last %s",
         s->input.row_count, s->event_count, s->errors.count, s->case_count, s->activity_count,
         s->resource_count, first->timestamp, last->timestamp);
    I events[12] = {0}, cases[12] = {0}, starts[12] = {0}, ends[12] = {0}, rework[12] = {0},
      wait_count[12] = {0}, wait_sum[12] = {0}, weekday_events[7] = {0}, weekday_starts[7] = {0},
      weekday_ends[7] = {0}, lengths[300], durations[300], days[366] = {0}, late = 0;
    unsigned workers[12] = {0};
    int maxday = 0;
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        int occurrences[12] = {0};
        ++starts[item->trace[0]];
        ++ends[item->trace[item->count - 1]];
        ++weekday_starts[(item->events[0]->time / 1440 + 3) % 7];
        ++weekday_ends[(item->events[item->count - 1]->time / 1440 + 3) % 7];
        for (int i = 0; i < item->count; ++i) {
            int a = item->trace[i];
            Event *e = item->events[i];
            ++events[a];
            ++occurrences[a];
            workers[a] |= 1u << resource_id(s, e->resource);
            ++weekday_events[(e->time / 1440 + 3) % 7];
            if (i) {
                ++wait_count[a];
                wait_sum[a] += e->time - item->events[i - 1]->time;
            }
        }
        for (int a = 0; a < s->activity_count; ++a) {
            cases[a] += occurrences[a] > 0;
            rework[a] += occurrences[a] >= 2;
        }
        lengths[c] = item->count;
        durations[c] = item->duration;
        int day = (int)(item->duration / 1440);
        ++days[day];
        if (day > maxday)
            maxday = day;
        late += item->duration > s->limit;
    }
    for (int a = 0; a < s->activity_count; ++a) {
        int resource_count = 0;
        for (int r = 0; r < s->resource_count; ++r)
            resource_count += (workers[a] >> r) & 1u;
        line(
            &out,
            "ACTIVITY %s events %lld cases %lld start %lld end %lld rework %lld wait %s resources %d model %s",
            s->activities[a], V(events[a]), V(cases[a]), V(starts[a]), V(ends[a]), V(rework[a]),
            wait_count[a] ? fraction(ratio(wait_sum[a], wait_count[a])) : "-", resource_count,
            transition_index(&s->reference, s->activities[a]) >= 0 ? "yes" : "no");
    }
    for (int type = 0; type < 2; ++type) {
        I *values = type ? durations : lengths, minimum = values[0], maximum = values[0], total = 0;
        for (int i = 0; i < s->case_count; ++i) {
            if (values[i] < minimum)
                minimum = values[i];
            if (values[i] > maximum)
                maximum = values[i];
            total += values[i];
        }
        line(&out, "%s min %lld max %lld mean %s median %s", type ? "DURATION" : "LENGTH",
             V(minimum), V(maximum), fraction(ratio(total, s->case_count)),
             fraction(median(values, s->case_count)));
    }
    for (int d = 0; d <= maxday; ++d)
        line(&out, "DAYS %d cases %lld share %s", d, V(days[d]),
             percentage(days[d], s->case_count));
    line(&out, "SLA limit %lld late %lld share %s", V(s->limit), V(late),
         percentage(late, s->case_count));
    const char *weekdays[7] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    for (int i = 0; i < 7; ++i)
        line(&out, "WEEKDAY %s events %lld starts %lld ends %lld", weekdays[i],
             V(weekday_events[i]), V(weekday_starts[i]), V(weekday_ends[i]));
    return out;
}
static char *trace_names(const Study *s, const Trace *trace) {
    const char *list[50];
    for (int i = 0; i < trace->length; ++i)
        list[i] = s->activities[trace->activity[i]];
    return names(list, trace->length);
}
static Lines variant_report(const Study *s) {
    Lines out = {0};
    for (int v = 0; v < s->variant_count; ++v) {
        const Variant *entry = &s->variants[v];
        I duration = 0, late = 0;
        for (int i = 0; i < entry->count; ++i) {
            Case *item = &s->cases[entry->cases[i]];
            duration += item->duration;
            late += item->duration > s->limit;
        }
        int first = entry->cases[0];
        line(
            &out,
            "VARIANT %d count %d share %s length %d first %s duration %s late %lld fitness %s %s %s",
            v + 1, entry->count, percentage(entry->count, s->case_count), entry->trace.length,
            s->cases[first].id, fraction(ratio(duration, entry->count)), V(late),
            fraction(fitness(&s->reference_replays[first])), entry->keep ? "KEEP" : "DROP",
            trace_names(s, &entry->trace));
    }
    line(&out, "FILTER min_follows %lld variants %d of %d cases %lld of %d events %lld of %d",
         V(s->minimum), s->filtered.count, s->variant_count, V(s->kept_cases), s->case_count,
         V(s->kept_events), s->event_count);
    return out;
}
typedef struct {
    int a, b;
    I count;
} Ranked;
static int ranked_order(const void *left, const void *right) {
    const Ranked *a = left, *b = right;
    if (a->count != b->count)
        return (a->count < b->count) - (a->count > b->count);
    if (a->a != b->a)
        return a->a - b->a;
    return a->b - b->b;
}
static int rank_counts(const I *counts, int n, Ranked *out) {
    int length = 0;
    for (int a = 0; a < n; ++a)
        for (int b = 0; b < n; ++b)
            if (counts[a * n + b])
                out[length++] = (Ranked){a, b, counts[a * n + b]};
    qsort(out, (size_t)length, sizeof(Ranked), ranked_order);
    return length;
}
static Lines dfg_report(Study *s) {
    Lines out = {0};
    I starts[12] = {0}, ends[12] = {0}, duration[12] = {0}, edge_cases[12][12] = {{0}},
      wait_sum[12][12] = {{0}}, wait_min[12][12], wait_max[12][12] = {{0}};
    for (int a = 0; a < 12; ++a)
        for (int b = 0; b < 12; ++b)
            wait_min[a][b] = INT64_MAX;
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        ++starts[item->trace[0]];
        int last = item->trace[item->count - 1];
        ++ends[last];
        duration[last] += item->duration;
        int seen[12][12] = {{0}};
        for (int i = 1; i < item->count; ++i) {
            int a = item->trace[i - 1], b = item->trace[i];
            I wait = item->events[i]->time - item->events[i - 1]->time;
            wait_sum[a][b] += wait;
            if (wait < wait_min[a][b])
                wait_min[a][b] = wait;
            if (wait > wait_max[a][b])
                wait_max[a][b] = wait;
            seen[a][b] = 1;
        }
        for (int a = 0; a < s->activity_count; ++a)
            for (int b = 0; b < s->activity_count; ++b)
                edge_cases[a][b] += seen[a][b];
    }
    Ranked ranked[144];
    for (int type = 0; type < 2; ++type) {
        I *values = type ? ends : starts;
        int n = 0;
        for (int a = 0; a < s->activity_count; ++a)
            if (values[a])
                ranked[n++] = (Ranked){a, 0, values[a]};
        qsort(ranked, (size_t)n, sizeof(Ranked), ranked_order);
        for (int i = 0; i < n; ++i) {
            int a = ranked[i].a;
            if (type)
                line(&out, "END %s count %lld duration %s", s->activities[a], V(ends[a]),
                     fraction(ratio(duration[a], ends[a])));
            else
                line(&out, "START %s count %lld", s->activities[a], V(starts[a]));
        }
    }
    int n = rank_counts(&s->counts.values[0][0], 12, ranked);
    for (int i = 0; i < n; ++i) {
        int a = ranked[i].a, b = ranked[i].b;
        line(&out, "EDGE %s %s count %lld cases %lld mean %s min %lld max %lld", s->activities[a],
             s->activities[b], V(s->counts.values[a][b]), V(edge_cases[a][b]),
             fraction(ratio(wait_sum[a][b], s->counts.values[a][b])), V(wait_min[a][b]),
             V(wait_max[a][b]));
    }
    int ids[12];
    for (int a = 0; a < s->activity_count; ++a)
        ids[a] = a;
    Relations r = relations(&s->counts, NULL, 0);
    footprint(&out, s->activities, ids, s->activity_count, &r);
    return out;
}
static int insert_candidate(int *slots, Candidate *values, int *count, Candidate pair) {
    unsigned key = (pair.first << 12) | pair.second, index = (key * 2654435761u) & 16383u;
    while (slots[index] >= 0) {
        Candidate existing = values[slots[index]];
        if (existing.first == pair.first && existing.second == pair.second)
            return 0;
        index = (index + 1) & 16383u;
    }
    slots[index] = *count;
    values[(*count)++] = pair;
    return 1;
}
static Discovery discover(Study *s, const Log *log, unsigned activities, const Relations *r) {
    Discovery d = {0};
    d.activities = activities;
    Candidate *candidates = malloc(5000 * sizeof(Candidate));
    int *slots = malloc(16384 * sizeof(int));
    for (int i = 0; i < 16384; ++i)
        slots[i] = -1;
    for (int a = 0; a < s->activity_count; ++a)
        if (activities & (1u << a))
            for (int b = 0; b < s->activity_count; ++b)
                if ((activities & (1u << b)) && r->values[a][b] == FORWARD) {
                    ++d.causal;
                    if (r->values[a][a] == UNRELATED && r->values[b][b] == UNRELATED)
                        insert_candidate(slots, candidates, &d.candidates,
                                         (Candidate){1u << a, 1u << b});
                }
    for (int i = 0; i < d.candidates; ++i)
        for (int a = 0; a < s->activity_count; ++a)
            if (activities & (1u << a))
                for (int side = 0; side < 2; ++side) {
                    Candidate next;
                    if (extend_pair(candidates[i], a, side, r, &next))
                        insert_candidate(slots, candidates, &d.candidates, next);
                }
    d.pairs = malloc((size_t)d.candidates * sizeof(Candidate));
    for (int i = 0; i < d.candidates; ++i) {
        int extension = 0;
        for (int a = 0; a < s->activity_count; ++a)
            if (activities & (1u << a))
                for (int side = 0; side < 2; ++side) {
                    Candidate next;
                    if (extend_pair(candidates[i], a, side, r, &next))
                        extension = 1;
                }
        if (!extension)
            d.pairs[d.pair_count++] = candidates[i];
    }
    qsort(d.pairs, (size_t)d.pair_count, sizeof(Candidate), pair_order);
    free(candidates);
    free(slots);
    for (int i = 0; i < log->count; ++i) {
        Trace trace = log->entries[i];
        d.starts |= 1u << trace.activity[0];
        d.ends |= 1u << trace.activity[trace.length - 1];
    }
    int np = d.pair_count + 2, nt = 0;
    char (*places)[21] = calloc((size_t)np, sizeof(*places)), transitions[12][21];
    strcpy(places[0], "start");
    for (int i = 0; i < d.pair_count; ++i)
        snprintf(places[i + 1], 21, "p%d", i + 1);
    strcpy(places[np - 1], "end");
    for (int a = 0; a < s->activity_count; ++a)
        if (activities & (1u << a))
            strcpy(transitions[nt++], s->activities[a]);
    d.net = net_create(places, np, transitions, nt, "start", "end");
    free(places);
    for (int a = 0; a < s->activity_count; ++a) {
        if (d.starts & (1u << a))
            net_arc(&d.net, "start", s->activities[a]);
        if (d.ends & (1u << a))
            net_arc(&d.net, s->activities[a], "end");
    }
    for (int i = 0; i < d.pair_count; ++i)
        for (int a = 0; a < s->activity_count; ++a) {
            if (d.pairs[i].first & (1u << a))
                net_arc(&d.net, s->activities[a], d.net.places[i + 1]);
            if (d.pairs[i].second & (1u << a))
                net_arc(&d.net, d.net.places[i + 1], s->activities[a]);
        }
    return d;
}
static void pair_line(Lines *out, const Discovery *d) {
    line(out, "PAIRS causal %d candidates %d maximal %d", d->causal, d->candidates, d->pair_count);
}
static void net_lines(Lines *out, Study *s, const Discovery *d) {
    const Net *net = &d->net;
    line(out, "PLACE start - %s", mask_names(s, d->starts));
    for (int i = 0; i < d->pair_count; ++i)
        line(out, "PLACE p%d %s %s", i + 1, mask_names(s, d->pairs[i].first),
             mask_names(s, d->pairs[i].second));
    line(out, "PLACE end %s -", mask_names(s, d->ends));
    for (int t = 0; t < net->transition_count; ++t)
        line(out, "TRANSITION %s in %s out %s", net->transitions[t],
             place_names(net, net->inputs, t), place_names(net, net->outputs, t));
    line(out, "NET places %d transitions %d arcs %d", net->place_count, net->transition_count,
         net->arc_count);
}
static void print_footprint(Lines *out, Study *s, unsigned mask, const Relations *r) {
    int ids[12], n = 0;
    for (int a = 0; a < s->activity_count; ++a)
        if (mask & (1u << a))
            ids[n++] = a;
    footprint(out, s->activities, ids, n, r);
}
static Lines mine_workflows(Study *s) {
    Lines out = {0};
    Counts counts = directly_follows(&s->filtered);
    unsigned activities = 0, loops = 0;
    for (int i = 0; i < s->filtered.count; ++i)
        for (int j = 0; j < s->filtered.entries[i].length; ++j)
            activities |= 1u << s->filtered.entries[i].activity[j];
    for (int a = 0; a < s->activity_count; ++a)
        if (counts.values[a][a])
            loops |= 1u << a;
    unsigned retained = activities & ~loops;
    Relations basic = relations(&counts, NULL, 0);
    Discovery alpha = discover(s, &s->filtered, activities, &basic);
    line(&out, "LOG variants %d cases %lld activities %s", s->filtered.count, V(s->kept_cases),
         mask_names(s, activities));
    line(&out, "LOOPS %s", mask_names(s, loops));
    line(&out, "MINER alpha");
    print_footprint(&out, s, activities, &basic);
    pair_line(&out, &alpha);
    net_lines(&out, s, &alpha);
    Log reduced = {0};
    for (int i = 0; i < s->filtered.count; ++i) {
        Trace *trace = &reduced.entries[reduced.count++], *original = &s->filtered.entries[i];
        trace->weight = original->weight;
        for (int j = 0; j < original->length; ++j)
            if (!(loops & (1u << original->activity[j])))
                trace->activity[trace->length++] = original->activity[j];
    }
    Counts reduced_counts = directly_follows(&reduced), triangles = triangle_counts(&reduced);
    Relations plus = relations(&reduced_counts, &triangles, 1);
    Discovery alpha_plus = discover(s, &reduced, retained, &plus);
    line(&out, "MINER alpha_plus");
    for (int a = 0; a < s->activity_count; ++a)
        for (int b = 0; b < s->activity_count; ++b)
            if (triangles.values[a][b])
                line(&out, "TRIANGLE %s %s count %lld", s->activities[a], s->activities[b],
                     V(triangles.values[a][b]));
    print_footprint(&out, s, retained, &plus);
    pair_line(&out, &alpha_plus);
    char transition_names[12][21];
    int nt = 0;
    for (int a = 0; a < s->activity_count; ++a)
        if (activities & (1u << a))
            strcpy(transition_names[nt++], s->activities[a]);
    Net net = net_create(alpha_plus.net.places, alpha_plus.net.place_count, transition_names, nt,
                         "start", "end");
    for (int t = 0; t < alpha_plus.net.transition_count; ++t)
        for (int p = 0; p < net.place_count; ++p) {
            if (alpha_plus.net.inputs[t * net.place_count + p])
                net_arc(&net, net.places[p], alpha_plus.net.transitions[t]);
            if (alpha_plus.net.outputs[t * net.place_count + p])
                net_arc(&net, alpha_plus.net.transitions[t], net.places[p]);
        }
    for (int a = 0; a < s->activity_count; ++a)
        if (loops & (1u << a)) {
            Candidate pair = {0};
            for (int b = 0; b < s->activity_count; ++b)
                if (retained & (1u << b)) {
                    if (counts.values[b][a])
                        pair.first |= 1u << b;
                    if (counts.values[a][b])
                        pair.second |= 1u << b;
                }
            const char *place = "-";
            for (int i = 0; i < alpha_plus.pair_count; ++i)
                if (pair.first == alpha_plus.pairs[i].first &&
                    pair.second == alpha_plus.pairs[i].second) {
                    place = net.places[i + 1];
                    net_arc(&net, place, s->activities[a]);
                    net_arc(&net, s->activities[a], place);
                    break;
                }
            line(&out, "LOOP %s before %s after %s place %s", s->activities[a],
                 mask_names(s, pair.first), mask_names(s, pair.second), place);
        }
    free(alpha_plus.net.places);
    free(alpha_plus.net.inputs);
    free(alpha_plus.net.outputs);
    alpha_plus.net = net;
    net_lines(&out, s, &alpha_plus);
    s->nets[0] = s->reference;
    s->nets[1] = alpha.net;
    s->nets[2] = alpha_plus.net;
    free(alpha.pairs);
    free(alpha_plus.pairs);
    return out;
}
static Lines heuristic_report(Study *s) {
    Lines out = {0};
    Counts triangles = triangle_counts(&s->full);
    unsigned loops1 = 0;
    int loops2[12][12] = {{0}}, edges[12][12] = {{0}}, loop2_count = 0, edge_count = 0;
    Fraction best_out[12], best_in[12];
    for (int a = 0; a < 12; ++a)
        best_out[a] = best_in[a] = ratio(-1, 1);
    for (int a = 0; a < s->activity_count; ++a) {
        I n = s->counts.values[a][a];
        if (!n)
            continue;
        Fraction measure = loop_measure(n);
        int accept = n >= s->positive && compare(measure, s->loop1_threshold) >= 0;
        if (accept) {
            loops1 |= 1u << a;
            edges[a][a] = 1;
        }
        line(&out, "L1 %s count %lld measure %s %s", s->activities[a], V(n), fraction(measure),
             accept ? "ACCEPT" : "REJECT");
    }
    for (int a = 0; a < s->activity_count; ++a)
        for (int b = a + 1; b < s->activity_count; ++b) {
            I n = triangles.values[a][b] + triangles.values[b][a];
            if (!n || (loops1 & ((1u << a) | (1u << b))))
                continue;
            Fraction measure = loop_measure(n);
            int accept = n >= s->positive && compare(measure, s->loop2_threshold) >= 0;
            if (accept) {
                loops2[a][b] = loops2[b][a] = 1;
                ++loop2_count;
            }
            line(&out, "L2 %s %s count %lld measure %s %s", s->activities[a], s->activities[b],
                 V(n), fraction(measure), accept ? "ACCEPT" : "REJECT");
        }
    for (int a = 0; a < s->activity_count; ++a)
        for (int b = 0; b < s->activity_count; ++b)
            if (a != b && s->counts.values[a][b]) {
                Fraction measure = dependency(&s->counts, a, b);
                if (compare(measure, best_out[a]) > 0)
                    best_out[a] = measure;
                if (compare(measure, best_in[b]) > 0)
                    best_in[b] = measure;
            }
    for (int a = 0; a < s->activity_count; ++a)
        for (int b = 0; b < s->activity_count; ++b)
            if (a != b && s->counts.values[a][b]) {
                Fraction measure = dependency(&s->counts, a, b);
                const char *verdict;
                if (loops2[a][b])
                    verdict = "LOOP2";
                else if (s->counts.values[a][b] < s->positive)
                    verdict = "REJECT_COUNT";
                else if (compare(measure, s->dependency_threshold) < 0)
                    verdict = "REJECT_MEASURE";
                else if (compare(minus(best_out[a], measure), s->relative) > 0 &&
                         compare(minus(best_in[b], measure), s->relative) > 0)
                    verdict = "REJECT_BEST";
                else
                    verdict = "ACCEPT";
                if (!strcmp(verdict, "ACCEPT") || !strcmp(verdict, "LOOP2"))
                    edges[a][b] = 1;
                line(&out, "DEP %s %s count %lld reverse %lld measure %s %s", s->activities[a],
                     s->activities[b], V(s->counts.values[a][b]), V(s->counts.values[b][a]),
                     fraction(measure), verdict);
            }
    for (int a = 0; a < s->activity_count; ++a) {
        unsigned in = 0, out = 0;
        for (int b = 0; b < s->activity_count; ++b) {
            if (edges[b][a])
                in |= 1u << b;
            if (edges[a][b]) {
                out |= 1u << b;
                ++edge_count;
            }
        }
        line(&out, "NODE %s in %s out %s", s->activities[a], mask_names(s, in), mask_names(s, out));
    }
    for (int a = 0; a < s->activity_count; ++a)
        for (int direction = 0; direction < 2; ++direction)
            for (int b = 0; b < s->activity_count; ++b)
                if (a != b && (direction ? edges[b][a] : edges[a][b]))
                    for (int c = b + 1; c < s->activity_count; ++c)
                        if (a != c && (direction ? edges[c][a] : edges[a][c])) {
                            Fraction measure = direction ? join_measure(&s->counts, a, b, c)
                                                         : split_measure(&s->counts, a, b, c);
                            line(&out, "%s %s %s %s measure %s %s", direction ? "JOIN" : "SPLIT",
                                 s->activities[a], s->activities[b], s->activities[c],
                                 fraction(measure),
                                 compare(measure, s->and_threshold) >= 0 ? "AND" : "XOR");
                        }
    int loop1_count = 0;
    for (int a = 0; a < s->activity_count; ++a)
        loop1_count += (loops1 >> a) & 1u;
    line(&out, "GRAPH activities %d edges %d loops1 %d loops2 %d", s->activity_count, edge_count,
         loop1_count, loop2_count);
    return out;
}
typedef struct {
    int from, to, transition;
} StateEdge;
static unsigned marking_hash(const unsigned char *marking, int count) {
    unsigned hash = 2166136261u;
    for (int i = 0; i < count; ++i)
        hash = (hash ^ marking[i]) * 16777619u;
    return hash;
}
static Exploration explore(const Net *net) {
    Exploration result = {0};
    int np = net->place_count, nt = net->transition_count, marking_count = 1, edge_count = 0;
    unsigned char *markings = calloc((size_t)1000 * np, 1), *after = malloc((size_t)np),
                  *final = final_marking(net);
    markings[net->initial] = 1;
    int slots[2048];
    for (int i = 0; i < 2048; ++i)
        slots[i] = -1;
    slots[marking_hash(markings, np) & 2047u] = 0;
    unsigned short enabled_at[1000] = {0};
    StateEdge edges[12000];
    unsigned ever = 0;
    for (int from = 0; from < marking_count; ++from) {
        unsigned char *before = markings + (size_t)from * np;
        unsigned active = 0;
        for (int t = 0; t < nt; ++t)
            if (enabled(net, before, t))
                active |= 1u << t;
        enabled_at[from] = (unsigned short)active;
        ever |= active;
        if (!active && memcmp(before, final, (size_t)np))
            ++result.deadlocks;
        for (int t = 0; t < nt; ++t)
            if (active & (1u << t)) {
                fire(net, before, t, after);
                int unsafe = 0;
                for (int p = 0; p < np; ++p)
                    if (after[p] > 1)
                        unsafe = 1;
                if (unsafe) {
                    ++result.unsafe;
                    continue;
                }
                unsigned slot = marking_hash(after, np) & 2047u;
                while (slots[slot] >= 0 &&
                       memcmp(markings + (size_t)slots[slot] * np, after, (size_t)np))
                    slot = (slot + 1) & 2047u;
                int to = slots[slot];
                if (to < 0) {
                    to = marking_count++;
                    slots[slot] = to;
                    memcpy(markings + (size_t)to * np, after, (size_t)np);
                }
                edges[edge_count++] = (StateEdge){from, to, t};
            }
    }
    int pending[1000], pending_count = 0;
    unsigned char reaches[1000] = {0};
    for (int i = 0; i < marking_count; ++i)
        if (!memcmp(markings + (size_t)i * np, final, (size_t)np)) {
            result.final = 1;
            reaches[i] = 1;
            pending[pending_count++] = i;
            break;
        }
    for (int i = 0; i < pending_count; ++i)
        for (int e = 0; e < edge_count; ++e)
            if (edges[e].to == pending[i] && !reaches[edges[e].from]) {
                reaches[edges[e].from] = 1;
                pending[pending_count++] = edges[e].from;
            }
    result.markings = marking_count;
    result.edges = edge_count;
    result.stuck = marking_count - pending_count;
    result.dead = ((1u << nt) - 1) & ~ever;
    for (int e = 0; e < edge_count; ++e)
        for (int u = 0; u < nt; ++u)
            if (enabled_at[edges[e].to] & (1u << u))
                result.follows.values[edges[e].transition][u] = 1;
    free(markings);
    free(after);
    free(final);
    return result;
}
static char *transition_names(const Net *net, unsigned mask) {
    const char *list[12];
    int n = 0;
    for (int t = 0; t < net->transition_count; ++t)
        if (mask & (1u << t))
            list[n++] = net->transitions[t];
    return names(list, n);
}
static void build_prefixes(Study *s) {
    s->prefixes = calloc(5000, sizeof(Prefix));
    int slots[8192];
    for (int i = 0; i < 8192; ++i)
        slots[i] = -1;
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        unsigned hash = 2166136261u;
        for (int n = 0; n <= item->count; ++n) {
            if (n)
                hash = (hash ^ (unsigned)(item->trace[n - 1] + 1)) * 16777619u;
            unsigned slot = hash & 8191u;
            while (slots[slot] >= 0) {
                Prefix *old = &s->prefixes[slots[slot]];
                if (!trace_order(old->activity, old->length, item->trace, n))
                    break;
                slot = (slot + 1) & 8191u;
            }
            if (slots[slot] < 0) {
                slots[slot] = s->prefix_count;
                Prefix *p = &s->prefixes[s->prefix_count++];
                p->length = n;
                memcpy(p->activity, item->trace, (size_t)n * sizeof(int));
            }
            Prefix *p = &s->prefixes[slots[slot]];
            ++p->weight;
            if (n < item->count)
                p->followers |= 1u << item->trace[n];
        }
    }
}
static void precision_report(Lines *out, const Study *s, const char *name, const Net *net) {
    I fitted = 0, allowed = 0, escaping = 0, escapes[12] = {0};
    unsigned char *marking = malloc((size_t)net->place_count),
                  *after = malloc((size_t)net->place_count);
    for (int i = 0; i < s->prefix_count; ++i) {
        const Prefix *prefix = &s->prefixes[i];
        memset(marking, 0, (size_t)net->place_count);
        marking[net->initial] = 1;
        int fit = 1;
        for (int j = 0; j < prefix->length; ++j) {
            int t = transition_index(net, s->activities[prefix->activity[j]]);
            if (t < 0 || !enabled(net, marking, t)) {
                fit = 0;
                break;
            }
            fire(net, marking, t, after);
            memcpy(marking, after, (size_t)net->place_count);
        }
        if (!fit)
            continue;
        ++fitted;
        for (int t = 0; t < net->transition_count; ++t)
            if (enabled(net, marking, t)) {
                allowed += prefix->weight;
                int a = activity_id(s, net->transitions[t]);
                if (a < 0 || !(prefix->followers & (1u << a))) {
                    escaping += prefix->weight;
                    escapes[t] += prefix->weight;
                }
            }
    }
    line(out, "PRECISION %s prefixes %lld allowed %lld escaping %lld precision %s", name, V(fitted),
         V(allowed), V(escaping),
         fraction(allowed ? ratio(allowed - escaping, allowed) : ratio(1, 1)));
    Ranked ranked[12];
    int n = 0;
    for (int t = 0; t < net->transition_count; ++t)
        if (escapes[t])
            ranked[n++] = (Ranked){t, 0, escapes[t]};
    qsort(ranked, (size_t)n, sizeof(Ranked), ranked_order);
    for (int i = 0; i < n; ++i)
        line(out, "ESCAPE %s %s weight %lld", name, net->transitions[ranked[i].a],
             V(ranked[i].count));
    free(marking);
    free(after);
}
static Replay replay_case(const Net *net, const Case *item) {
    Replay r = replay_create(net);
    int np = net->place_count, nt = net->transition_count;
    I *tokens = calloc((size_t)np * 52, sizeof(I));
    int *head = calloc((size_t)np, sizeof(int)), *tail = calloc((size_t)np, sizeof(int));
    tokens[net->initial * 52] = item->events[0]->time;
    tail[net->initial] = 1;
    r.produced = 1;
    for (int i = 0; i < item->count; ++i) {
        Event *event = item->events[i];
        int t = transition_index(net, event->activity);
        if (t < 0) {
            ++r.skipped;
            continue;
        }
        for (int p = 0; p < np; ++p)
            if (net->inputs[t * np + p]) {
                ++r.consumed;
                if (head[p] < tail[p]) {
                    I wait = event->time - tokens[p * 52 + head[p]++];
                    ++r.wait_count[p];
                    r.wait_sum[p] += wait;
                    if (wait > r.wait_max[p])
                        r.wait_max[p] = wait;
                    ++r.routes[p * nt + t];
                } else {
                    ++r.missing;
                    ++r.place_missing[p];
                }
            }
        for (int p = 0; p < np; ++p)
            if (net->outputs[t * np + p]) {
                tokens[p * 52 + tail[p]++] = event->time;
                ++r.produced;
            }
    }
    ++r.consumed;
    if (head[net->final] < tail[net->final])
        ++head[net->final];
    else {
        ++r.missing;
        ++r.place_missing[net->final];
    }
    for (int p = 0; p < np; ++p) {
        r.place_remaining[p] = tail[p] - head[p];
        r.remaining += r.place_remaining[p];
        r.deviating[p] = r.place_missing[p] > 0 || r.place_remaining[p] > 0;
    }
    free(tokens);
    free(head);
    free(tail);
    return r;
}
static void aggregate(Replay *total, const Replay *r, const Net *net) {
    total->missing += r->missing;
    total->remaining += r->remaining;
    total->consumed += r->consumed;
    total->produced += r->produced;
    total->skipped += r->skipped;
    for (int p = 0; p < net->place_count; ++p) {
        total->place_missing[p] += r->place_missing[p];
        total->place_remaining[p] += r->place_remaining[p];
        total->deviating[p] += r->deviating[p];
        total->wait_count[p] += r->wait_count[p];
        total->wait_sum[p] += r->wait_sum[p];
        if (r->wait_max[p] > total->wait_max[p])
            total->wait_max[p] = r->wait_max[p];
        for (int t = 0; t < net->transition_count; ++t)
            total->routes[p * net->transition_count + t] +=
                r->routes[p * net->transition_count + t];
    }
}
static Lines conformance_report(Study *s) {
    Lines out = {0};
    const char *names_net[3] = {"reference", "alpha", "alpha_plus"};
    Exploration explored[3];
    line(&out, "MODEL places %d transitions %d arcs %d", s->reference.place_count,
         s->reference.transition_count, s->reference.arc_count);
    for (int i = 0; i < 3; ++i) {
        Net *net = &s->nets[i];
        explored[i] = explore(net);
        Exploration *e = &explored[i];
        line(
            &out,
            "REACHABILITY %s markings %lld edges %lld unsafe %lld deadlocks %lld stuck %lld final %s dead %s sound %s",
            names_net[i], V(e->markings), V(e->edges), V(e->unsafe), V(e->deadlocks), V(e->stuck),
            e->final ? "yes" : "no", transition_names(net, e->dead),
            !e->unsafe && !e->stuck && !e->dead ? "yes" : "no");
    }
    for (int i = 0; i < 3; ++i) {
        Net *net = &s->nets[i];
        char universe[24][21];
        int n = s->activity_count;
        memcpy(universe, s->activities, (size_t)n * sizeof(universe[0]));
        for (int t = 0; t < net->transition_count; ++t)
            if (activity_id(s, net->transitions[t]) < 0)
                strcpy(universe[n++], net->transitions[t]);
        qsort(universe, (size_t)n, sizeof(universe[0]), string_order);
        I differing = 0;
        Lines differences = {0};
        for (int a = 0; a < n; ++a)
            for (int b = 0; b < n; ++b) {
                int la = activity_id(s, universe[a]), lb = activity_id(s, universe[b]),
                    ma = transition_index(net, universe[a]),
                    mb = transition_index(net, universe[b]);
                Relation observed =
                             la < 0 || lb < 0 ? UNRELATED : basic_relation(&s->counts, la, lb),
                         modeled = ma < 0 || mb < 0 ? UNRELATED
                                                    : basic_relation(&explored[i].follows, ma, mb);
                if (observed != modeled) {
                    ++differing;
                    if (i == 0 && a <= b)
                        line(&differences, "DIFF %s %s log %s model %s", universe[a], universe[b],
                             symbol(observed), symbol(modeled));
                }
            }
        I cells = (I)n * n;
        line(&out, "FOOTPRINT %s activities %d cells %lld differing %lld fitness %s", names_net[i],
             n, V(cells), V(differing), fraction(ratio(cells - differing, cells)));
        for (int j = 0; j < differences.count; ++j)
            line(&out, "%s", differences.values[j]);
    }
    build_prefixes(s);
    for (int i = 0; i < 3; ++i)
        precision_report(&out, s, names_net[i], &s->nets[i]);
    for (int i = 0; i < 3; ++i) {
        Net *net = &s->nets[i];
        Replay total = replay_create(net);
        I fitting = 0;
        for (int c = 0; c < s->case_count; ++c) {
            Replay r = replay_case(net, &s->cases[c]);
            fitting += r.missing == 0 && r.remaining == 0;
            aggregate(&total, &r, net);
            if (i == 0)
                s->reference_replays[c] = r;
            else
                replay_free(&r);
        }
        line(
            &out,
            "REPLAY %s cases %d fitting %lld skipped %lld missing %lld remaining %lld consumed %lld produced %lld fitness %s",
            names_net[i], s->case_count, V(fitting), V(total.skipped), V(total.missing),
            V(total.remaining), V(total.consumed), V(total.produced), fraction(fitness(&total)));
        for (int p = 0; p < net->place_count; ++p)
            line(
                &out,
                "PLACE %s %s missing %lld remaining %lld deviating %lld tokens %lld mean %s max %s",
                names_net[i], net->places[p], V(total.place_missing[p]),
                V(total.place_remaining[p]), V(total.deviating[p]), V(total.wait_count[p]),
                total.wait_count[p] ? fraction(ratio(total.wait_sum[p], total.wait_count[p])) : "-",
                total.wait_count[p] ? format("%lld", V(total.wait_max[p])) : "-");
        for (int p = 0; p < net->place_count; ++p) {
            const char *routes[12];
            int n = 0;
            for (int t = 0; t < net->transition_count; ++t)
                if (net->inputs[t * net->place_count + p])
                    routes[n++] = format("%s=%lld", net->transitions[t],
                                         V(total.routes[p * net->transition_count + t]));
            if (n >= 2)
                line(&out, "ROUTE %s %s %s", names_net[i], net->places[p], names(routes, n));
        }
        replay_free(&total);
    }
    return out;
}
static Lines conformance_csv(const Study *s) {
    Lines out = {0};
    line(&out, "case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness");
    for (int c = 0; c < s->case_count; ++c) {
        const Replay *r = &s->reference_replays[c];
        line(&out, "%s,%d,%d,%lld,%lld,%lld,%lld,%lld,%s", s->cases[c].id, s->variant_by_case[c],
             s->cases[c].count, V(r->skipped), V(r->missing), V(r->remaining), V(r->consumed),
             V(r->produced), fraction(fitness(r)));
    }
    return out;
}
static Lines resource_report(const Study *s) {
    Lines out = {0};
    I events[20] = {0}, cases[20] = {0}, work[20][12] = {{0}}, handovers[20][20] = {{0}},
      handover_cases[20][20] = {{0}}, subcontract[20][20] = {{0}}, together[20][20] = {{0}};
    for (int c = 0; c < s->case_count; ++c) {
        Case *item = &s->cases[c];
        int workers[50], present[20] = {0}, pairs[20][20] = {{0}};
        for (int i = 0; i < item->count; ++i) {
            int r = workers[i] = resource_id(s, item->events[i]->resource);
            present[r] = 1;
            ++events[r];
            ++work[r][item->trace[i]];
            if (i) {
                ++handovers[workers[i - 1]][r];
                pairs[workers[i - 1]][r] = 1;
            }
            if (i >= 2 && workers[i - 2] == r && workers[i - 1] != r)
                ++subcontract[r][workers[i - 1]];
        }
        for (int a = 0; a < s->resource_count; ++a) {
            cases[a] += present[a];
            for (int b = 0; b < s->resource_count; ++b) {
                handover_cases[a][b] += pairs[a][b];
                if (a < b && present[a] && present[b])
                    ++together[a][b];
            }
        }
    }
    for (int r = 0; r < s->resource_count; ++r) {
        const char *list[12];
        int n = 0;
        for (int a = 0; a < s->activity_count; ++a)
            if (work[r][a])
                list[n++] = format("%s=%lld", s->activities[a], V(work[r][a]));
        line(&out, "RESOURCE %d %s events %lld cases %lld work %s", r + 1, s->resources[r],
             V(events[r]), V(cases[r]), names(list, n));
    }
    Ranked ranked[400];
    int n = rank_counts(&handovers[0][0], 20, ranked);
    for (int i = 0; i < n; ++i) {
        int a = ranked[i].a, b = ranked[i].b;
        if (a != b)
            line(&out, "HANDOVER %s %s count %lld cases %lld", s->resources[a], s->resources[b],
                 V(handovers[a][b]), V(handover_cases[a][b]));
    }
    char ***rows = malloc((size_t)s->resource_count * sizeof(char **));
    for (int a = 0; a < s->resource_count; ++a) {
        rows[a] = malloc((size_t)s->resource_count * sizeof(char *));
        for (int b = 0; b < s->resource_count; ++b)
            rows[a][b] = format("%lld", V(handovers[a][b]));
    }
    table(&out, rows, s->resource_count, 5);
    n = rank_counts(&subcontract[0][0], 20, ranked);
    for (int i = 0; i < n; ++i)
        line(&out, "SUBCONTRACT %s %s count %lld", s->resources[ranked[i].a],
             s->resources[ranked[i].b], V(ranked[i].count));
    n = rank_counts(&together[0][0], 20, ranked);
    for (int i = 0; i < n; ++i)
        line(&out, "TOGETHER %s %s cases %lld", s->resources[ranked[i].a],
             s->resources[ranked[i].b], V(ranked[i].count));
    I total = 0, self = 0;
    for (int a = 0; a < s->resource_count; ++a)
        for (int b = 0; b < s->resource_count; ++b) {
            total += handovers[a][b];
            if (a == b)
                self += handovers[a][b];
        }
    line(&out, "TOTAL handovers %lld self %lld other %lld", V(total), V(self), V(total - self));
    return out;
}
int main(void) {
    Study *s = calloc(1, sizeof(Study));
    initialize(s);
    build_variants(s);
    Lines alpha = mine_workflows(s), conformance = conformance_report(s);
    mkdir("output", 0777);
    Lines log = summary(s), variants = variant_report(s), dfg = dfg_report(s),
          heuristic = heuristic_report(s), csv = conformance_csv(s), resources = resource_report(s);
    save("log_summary.txt", &log);
    save("variants.txt", &variants);
    save("dfg.txt", &dfg);
    save("alpha_net.txt", &alpha);
    save("heuristic_net.txt", &heuristic);
    save("conformance.csv", &csv);
    save("conformance.txt", &conformance);
    save("resources.txt", &resources);
    return 0;
}
