#include "coherence.h"
typedef struct {
    int number, core;
    Number cycle, address, block;
    char operation;
    int word, distance, line_id;
} Event;
VECTOR(Events, Event)
typedef struct {
    int number;
    char *reason;
} Rejection;
VECTOR(Rejections, Rejection)
VECTOR(Indexes, int)
typedef struct {
    Events events;
    Rejections rejected;
} Validated;
static Number maximum(Number a, Number b) { return a > b ? a : b; }
static Number minimum(Number a, Number b) { return a < b ? a : b; }
static Validated validate_trace(Names lines, const Config *c) {
    Validated out = {0};
    Number latest = 0;
    for (size_t i = 0; i < lines.count; ++i) {
        Names f = split(lines.items[i], " ");
        char **s = f.items, *reason = NULL;
        bool empty = false;
        for (size_t j = 0; j < f.count; ++j)
            empty |= !*s[j];
        if ((f.count != 3 && f.count != 4) || empty)
            reason = "fields";
        else if (!decimal_integer(s[0], 7))
            reason = "cycle";
        else if (!decimal_integer(s[1], 1000000) || atoll(s[1]) >= c->cores)
            reason = "core";
        else if ((strcmp(s[2], "R") && strcmp(s[2], "W") && strcmp(s[2], "FENCE")) ||
                 (!strcmp(s[2], "FENCE") ? f.count != 3 : f.count != 4))
            reason = "op";
        else if (strcmp(s[2], "FENCE") && (!valid_hex_address(s[3]) || hex_value(s[3]) % 4 != 0 ||
                                           hex_value(s[3]) > 0x7fffffff))
            reason = "address";
        else if (atoll(s[0]) < latest)
            reason = "order";
        if (reason) {
            Rejections_add(&out.rejected, (Rejection){(int)i + 1, reason});
            continue;
        }
        Event event = {.number = (int)out.events.count + 1,
                       .core = atoi(s[1]),
                       .cycle = atoll(s[0]),
                       .operation = !strcmp(s[2], "FENCE") ? 'F' : s[2][0]};
        latest = event.cycle;
        if (event.operation != 'F') {
            event.address = hex_value(s[3]);
            event.block = event.address / c->line_size;
            event.word = (int)(event.address % c->line_size / 4);
        }
        Events_add(&out.events, event);
    }
    return out;
}
typedef struct {
    unsigned reads, writes;
} WordSharing;
typedef struct {
    unsigned cores, writers;
    Number reads, writes;
    WordSharing words[32];
    bool shared, true_line;
} StaticLine;
typedef struct {
    Number *blocks;
    int count;
    Indexes grouped[8];
    StaticLine *sharing;
} Facts;
static int number_order(const void *a, const void *b) {
    Number x = *(const Number *)a, y = *(const Number *)b;
    return x < y ? -1 : x > y;
}
static int bit_count(unsigned mask) {
    int count = 0;
    while (mask) {
        mask &= mask - 1;
        ++count;
    }
    return count;
}
static int line_id(const Facts *facts, Number block) {
    int lo = 0, hi = facts->count;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (facts->blocks[mid] < block)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}
static Facts build_facts(Events *events, const Config *c) {
    Facts out = {.blocks = allocate(events->count * sizeof(Number))};
    for (size_t i = 0; i < events->count; ++i) {
        Event *event = &events->items[i];
        Indexes_add(&out.grouped[event->core], (int)i);
        if (event->operation != 'F')
            out.blocks[out.count++] = event->block;
    }
    qsort(out.blocks, (size_t)out.count, sizeof(Number), number_order);
    int count = 0;
    for (int i = 0; i < out.count; ++i)
        if (!i || out.blocks[i] != out.blocks[i - 1])
            out.blocks[count++] = out.blocks[i];
    out.count = count;
    out.sharing = allocate((size_t)count * sizeof(StaticLine));
    for (size_t i = 0; i < events->count; ++i) {
        Event *event = &events->items[i];
        if (event->operation == 'F')
            continue;
        event->line_id = line_id(&out, event->block);
        StaticLine *info = &out.sharing[event->line_id];
        unsigned core = 1u << event->core;
        info->cores |= core;
        WordSharing *word = &info->words[event->word];
        if (event->operation == 'W') {
            info->writers |= core;
            ++info->writes;
            word->writes |= core;
        } else {
            ++info->reads;
            word->reads |= core;
        }
    }
    for (int i = 0; i < count; ++i) {
        StaticLine *info = &out.sharing[i];
        info->shared = bit_count(info->cores) >= 2 && info->writers;
        for (int w = 0; w < c->line_size / 4; ++w)
            if (info->words[w].writes &&
                bit_count(info->words[w].reads | info->words[w].writes) >= 2)
                info->true_line = true;
    }
    return out;
}
typedef struct {
    int core, accesses, lines;
    Number cold, opt, distances[6], capacities[5], lru[5];
} Reuse;
static void fenwick_add(int *tree, int length, int position, int value) {
    for (int i = position; i <= length; i += i & -i)
        tree[i] += value;
}
static int fenwick_sum(const int *tree, int position) {
    int result = 0;
    for (int i = position; i > 0; i -= i & -i)
        result += tree[i];
    return result;
}
typedef struct {
    int next, id;
    Number block;
} HeapEntry;
static bool farther(HeapEntry a, HeapEntry b) {
    return a.next != b.next ? a.next > b.next : a.block < b.block;
}
static void heap_push(HeapEntry *heap, int *count, HeapEntry value) {
    int i = (*count)++;
    while (i > 0) {
        int parent = (i - 1) / 2;
        if (!farther(value, heap[parent]))
            break;
        heap[i] = heap[parent];
        i = parent;
    }
    heap[i] = value;
}
static HeapEntry heap_pop(HeapEntry *heap, int *count) {
    HeapEntry result = heap[0], value = heap[--*count];
    int i = 0;
    while (2 * i + 1 < *count) {
        int child = 2 * i + 1;
        if (child + 1 < *count && farther(heap[child + 1], heap[child]))
            ++child;
        if (!farther(heap[child], value))
            break;
        heap[i] = heap[child];
        i = child;
    }
    if (*count)
        heap[i] = value;
    return result;
}
static void reuse_analysis(Events *events, const Facts *facts, const Config *c, Reuse analyses[8]) {
    for (int core = 0; core < c->cores; ++core) {
        Memory work = {0};
        memory = &work;
        Indexes accesses = {0};
        for (size_t j = 0; j < facts->grouped[core].count; ++j) {
            int i = facts->grouped[core].items[j];
            if (events->items[i].operation != 'F')
                Indexes_add(&accesses, i);
        }
        int n = (int)accesses.count;
        Reuse row = {
            .core = core,
            .accesses = n,
            .capacities = {c->cap / 4, c->cap / 2, c->cap, 2 * (Number)c->cap, 4 * (Number)c->cap}};
        int *tree = allocate((size_t)(n + 1) * sizeof(int)),
            *last = allocate((size_t)facts->count * sizeof(int));
        for (int i = 0; i < n; ++i) {
            Event *event = &events->items[accesses.items[i]];
            int previous = last[event->line_id];
            if (!previous) {
                ++row.cold;
                ++row.lines;
            } else {
                event->distance = fenwick_sum(tree, i + 1) - fenwick_sum(tree, previous) + 1;
                fenwick_add(tree, n, previous, -1);
                int d = event->distance;
                ++row.distances[d == 1     ? 0
                                : d <= 4   ? 1
                                : d <= 16  ? 2
                                : d <= 64  ? 3
                                : d <= 256 ? 4
                                           : 5];
            }
            for (int j = 0; j < 5; ++j)
                if (!event->distance || event->distance > row.capacities[j])
                    ++row.lru[j];
            last[event->line_id] = i + 1;
            fenwick_add(tree, n, i + 1, 1);
        }
        int *next = allocate((size_t)n * sizeof(int)),
            *resident_next = allocate((size_t)facts->count * sizeof(int));
        bool *resident = allocate((size_t)facts->count * sizeof(bool));
        for (int id = 0; id < facts->count; ++id)
            last[id] = n + 1;
        for (int i = n - 1; i >= 0; --i) {
            int id = events->items[accesses.items[i]].line_id;
            next[i] = last[id];
            last[id] = i;
        }
        HeapEntry *heap = allocate((size_t)n * sizeof(HeapEntry));
        int heap_count = 0, residents = 0;
        for (int i = 0; i < n; ++i) {
            Event *event = &events->items[accesses.items[i]];
            int id = event->line_id;
            if (!resident[id]) {
                ++row.opt;
                if (residents == c->cap) {
                    HeapEntry victim;
                    do {
                        victim = heap_pop(heap, &heap_count);
                    } while (!resident[victim.id] || resident_next[victim.id] != victim.next);
                    resident[victim.id] = false;
                    --residents;
                }
                resident[id] = true;
                ++residents;
            }
            resident_next[id] = next[i];
            heap_push(heap, &heap_count, (HeapEntry){next[i], id, event->block});
        }
        analyses[core] = row;
        clear_memory(&work);
        memory = &permanent;
    }
}
typedef struct {
    int number, core;
    Number issue, address, block, latency;
    int line_id;
    char operation;
    int service, miss_kind;
    bool hit;
} Processed;
VECTOR(Accesses, Processed)
typedef struct {
    int writer;
    unsigned readers;
} WordCommunication;
typedef struct {
    int writer;
    Number handoffs, sharing_misses[2];
    WordCommunication words[32];
} DynamicLine;
typedef struct {
    Number lookups, hits, misses, flushes, writebacks, evictions, dirty_evictions;
} L2Stats;
typedef struct {
    Memory pool;
    const Config *config;
    const Scenario *scenario;
    const Events *events;
    const Facts *facts;
    Cache l1[8], l2;
    Bus bus;
    CoreStats cores[8], total;
    L2Stats l2_stats;
    Accesses processed;
    Names watch;
    DynamicLine *dynamic;
    Number communications[8][8];
    size_t indices[8];
    Number ready[8], write_completion[8];
    uint32_t *invalidations[8];
    bool primary;
} Simulation;
static void line_states(const Simulation *s, Number block, char states[9]) {
    memset(states, 0, 9);
    for (int core = 0; core < s->config->cores; ++core)
        states[core] = cache_state(&s->l1[core], block);
    states[s->config->cores] = cache_state(&s->l2, block);
}
static Transaction *issue_transaction(Simulation *s, int core, TransactionKind kind, Number block,
                                      Number requested) {
    Transaction *tx = bus_assign(&s->bus, core, kind, block, requested);
    ++s->cores[core].bus[kind];
    if (kind == WB)
        ++s->l2_stats.writebacks;
    return tx;
}
static void snoop_others(Simulation *s, Transaction *tx, int word, int id) {
    for (int core = 0; core < s->config->cores; ++core)
        if (core != tx->core) {
            Cache *cache = &s->l1[core];
            char old = cache_state(cache, tx->block);
            if (old == 'I')
                continue;
            SnoopTransition transition = snoop(s->scenario->protocol, old, tx->kind);
            tx->snoop_old[core] = old;
            tx->snoop_new[core] = transition.state;
            ++tx->snoop_hits;
            if (transition.state == 'I') {
                cache_remove(cache, tx->block);
                ++tx->invalidations;
                ++s->cores[tx->core].snoop[0];
                ++s->cores[core].snoop[1];
                s->invalidations[core][id] = UINT32_C(1) << word;
            } else
                cache_change(cache, tx->block, transition.state);
            if (transition.supply) {
                tx->supplier = core;
                ++s->cores[core].snoop[2];
            }
            tx->flushed |= transition.flush;
        }
    if (tx->flushed)
        ++s->l2_stats.flushes;
}
static void access_l2(Simulation *s, Transaction *tx) {
    ++s->l2_stats.lookups;
    if (cache_state(&s->l2, tx->block) != 'I') {
        tx->l2_hit = true;
        ++s->l2_stats.hits;
        cache_touch(&s->l2, tx->block);
    } else {
        ++s->l2_stats.misses;
        Entry victim = cache_fill(&s->l2, tx->block, 'C');
        if (victim.valid) {
            tx->evicted = true;
            tx->evicted_block = victim.block;
            tx->dirty_eviction = victim.state == 'D';
            ++s->l2_stats.evictions;
            for (int core = 0; core < s->config->cores; ++core) {
                char old = cache_state(&s->l1[core], victim.block);
                if (old == 'I')
                    continue;
                cache_remove(&s->l1[core], victim.block);
                tx->copies[core] = old;
                ++s->cores[core].snoop[3];
                tx->dirty_eviction |= dirty(old);
            }
            if (tx->dirty_eviction)
                ++s->l2_stats.dirty_evictions;
        }
    }
    if (tx->flushed || tx->kind == BUS_WR)
        cache_change(&s->l2, tx->block, 'D');
}
typedef struct {
    Number completion;
    int service;
} BusResult;
static BusResult run_transaction(Simulation *s, int core, TransactionKind kind, const Event *event,
                                 Number requested) {
    Transaction *tx = issue_transaction(s, core, kind, event->block, requested);
    snoop_others(s, tx, event->word, event->line_id);
    if (kind != BUS_UPGR)
        access_l2(s, tx);
    BusResult out = {.completion = tx->start + s->config->tb};
    if (kind == BUS_UPGR)
        out.service = 1;
    else if (kind == BUS_WR) {
        out.service = 2;
        out.completion += s->config->t2 + (tx->l2_hit ? 0 : s->config->tm);
    } else if (tx->supplier >= 0)
        out.service = 3;
    else if (tx->l2_hit) {
        out.service = 4;
        out.completion += s->config->t2;
    } else {
        out.service = 5;
        out.completion += s->config->t2 + s->config->tm;
    }
    return out;
}
static void communicate(Simulation *s, const Event *event) {
    DynamicLine *info = &s->dynamic[event->line_id];
    WordCommunication *word = &info->words[event->word];
    unsigned core = 1u << event->core;
    if (event->operation == 'W') {
        if (info->writer >= 0 && info->writer != event->core)
            ++info->handoffs;
        info->writer = event->core;
        word->writer = event->core;
        word->readers = 0;
    } else if (word->writer >= 0 && word->writer != event->core && !(word->readers & core)) {
        ++s->communications[word->writer][event->core];
        word->readers |= core;
    }
}
static void handle_access(Simulation *s, const Event *event, Number issue) {
    const Config *c = s->config;
    int core = event->core, id = event->line_id;
    Cache *cache = &s->l1[core];
    CoreStats *count = &s->cores[core];
    char before[8][9];
    if (s->primary)
        for (int i = 0; i < c->watch_count; ++i)
            line_states(s, c->watch[i], before[i]);
    char old = cache_state(cache, event->block);
    bool hit = old != 'I';
    ++count->accesses;
    if (event->operation == 'R')
        ++count->reads;
    else
        ++count->writes;
    if (hit)
        ++count->hits;
    else
        ++count->misses;
    bool other = false;
    for (int k = 0; k < c->cores; ++k)
        if (k != core && cache_state(&s->l1[k], event->block) != 'I')
            other = true;
    RequestTransition transition = requester(s->scenario->protocol, old, event->operation, other);
    int miss_kind = -1;
    if (hit)
        cache_touch(cache, event->block);
    else {
        uint32_t record = s->invalidations[core][id];
        if (!event->distance)
            miss_kind = 0;
        else if (record) {
            miss_kind = 3;
            int sharing = record & (UINT32_C(1) << event->word) ? 0 : 1;
            ++count->miss_counts[4 + sharing];
            if (s->primary)
                ++s->dynamic[id].sharing_misses[sharing];
        } else
            miss_kind = event->distance > c->cap ? 1 : 2;
        ++count->miss_counts[miss_kind];
    }
    if (event->operation == 'W')
        for (int k = 0; k < c->cores; ++k)
            if (k != core && s->invalidations[k][id])
                s->invalidations[k][id] |= UINT32_C(1) << event->word;
    if (s->primary)
        communicate(s, event);
    Number completion = issue + c->t1;
    int service = 0;
    if (transition.transaction != TX_NONE) {
        BusResult result = run_transaction(s, core, transition.transaction, event, issue + c->t1);
        completion = result.completion;
        service = result.service;
    }
    if (old != 'I')
        cache_change(cache, event->block, transition.state);
    else if (transition.state != 'I') {
        Entry victim = cache_fill(cache, event->block, transition.state);
        s->invalidations[core][id] = 0;
        if (victim.valid && dirty(victim.state)) {
            issue_transaction(s, core, WB, victim.block, s->bus.free);
            cache_touch(&s->l2, victim.block);
            cache_change(&s->l2, victim.block, 'D');
        }
    }
    Number latency = completion - issue;
    ++count->service[service];
    count->latency += latency;
    if (event->operation == 'R') {
        count->read_latency += latency;
        s->ready[core] = completion;
    } else {
        count->write_latency += latency;
        s->ready[core] = issue + c->t1;
        s->write_completion[core] = maximum(s->write_completion[core], completion);
    }
    count->finish = maximum(count->finish, completion);
    Accesses_add(&s->processed,
                 (Processed){event->number, core, issue, event->address, event->block, latency, id,
                             event->operation, service, miss_kind, hit});
    if (s->primary)
        for (int i = 0; i < c->watch_count; ++i) {
            Number block = c->watch[i];
            char after[9];
            line_states(s, block, after);
            if (block != event->block && !memcmp(before[i], after, 9))
                continue;
            Names columns = {0};
            for (int k = 0; k < c->cores; ++k)
                Names_add(&columns, format("c%d:%c", k, after[k]));
            Names_add(&s->watch, format("%d %lld c%d %c %s line %s %s L2:%c", event->number, issue,
                                        core, event->operation, hex_address(event->address),
                                        hex_address(block * c->line_size), join(columns, " "),
                                        after[c->cores]));
        }
}
static void simulate(Simulation *s, const Config *c, const Scenario *scenario, const Events *events,
                     const Facts *facts) {
    s->config = c;
    s->scenario = scenario;
    s->events = events;
    s->facts = facts;
    s->primary = !strcmp(scenario->name, c->primary);
    s->bus.latency = c->tb;
    for (int core = 0; core < c->cores; ++core) {
        s->l1[core] = cache_create(c->l1_sets, c->l1_ways, scenario->l1);
        s->invalidations[core] = allocate((size_t)facts->count * sizeof(uint32_t));
    }
    s->l2 = cache_create(c->l2_sets, c->l2_ways, scenario->l2);
    if (s->primary) {
        s->dynamic = allocate((size_t)facts->count * sizeof(DynamicLine));
        for (int id = 0; id < facts->count; ++id) {
            s->dynamic[id].writer = -1;
            for (int word = 0; word < 32; ++word)
                s->dynamic[id].words[word].writer = -1;
        }
    }
    for (;;) {
        int chosen = -1;
        Number issue = 0;
        for (int core = 0; core < c->cores; ++core)
            if (s->indices[core] < facts->grouped[core].count) {
                const Event *event = &events->items[facts->grouped[core].items[s->indices[core]]];
                Number candidate = maximum(event->cycle, s->ready[core]);
                if (chosen < 0 || candidate < issue) {
                    chosen = core;
                    issue = candidate;
                }
            }
        if (chosen < 0)
            break;
        const Event *event = &events->items[facts->grouped[chosen].items[s->indices[chosen]++]];
        if (event->operation == 'F') {
            Number completion = maximum(issue, s->write_completion[chosen]);
            CoreStats *count = &s->cores[chosen];
            ++count->fences;
            count->fence_stall += completion - issue;
            count->finish = maximum(count->finish, completion);
            s->ready[chosen] = completion;
        } else
            handle_access(s, event, issue);
    }
    s->total = total_counters(s->cores, c->cores);
}
static void extend(Names *out, Names other) {
    for (size_t i = 0; i < other.count; ++i)
        Names_add(out, other.items[i]);
}
static void section(Names *out, Names rows) {
    if (out->count)
        Names_add(out, "");
    extend(out, rows);
}
static Names trace_config(const Config *c, Names trace, const Validated *v) {
    Names out = {0};
    Names_add(&out, format("trace lines %zu accepted %zu rejected %zu", trace.count,
                           v->events.count, v->rejected.count));
    for (size_t i = 0; i < v->rejected.count; ++i)
        Names_add(&out, format("reject line %d %s", v->rejected.items[i].number,
                               v->rejected.items[i].reason));
    Names_add(&out, format("geometry cores %d line %d l1 %d %d sets %d l2 %d %d sets %d", c->cores,
                           c->line_size, c->l1_size, c->l1_ways, c->l1_sets, c->l2_size, c->l2_ways,
                           c->l2_sets));
    Names_add(&out,
              format("latency l1 %lld l2 %lld memory %lld bus %lld", c->t1, c->t2, c->tm, c->tb));
    return out;
}
static Names reuse_lines(const Reuse analyses[8], const Config *c) {
    Names out = {0};
    const char *buckets[] = {"1", "2-4", "5-16", "17-64", "65-256", "257+"};
    for (int core = 0; core < c->cores; ++core) {
        const Reuse *row = &analyses[core];
        Names_add(&out, format("reuse c%d accesses %d lines %d distance %s cold %lld", core,
                               row->accesses, row->lines, range_counts(buckets, row->distances, 6),
                               row->cold));
        Names mrc = {0};
        for (int i = 0; i < 5; ++i)
            Names_add(&mrc, format("%lld:%lld", row->capacities[i], row->lru[i]));
        Names_add(&out,
                  format("mrc c%d lru %s opt %d:%lld", core, join(mrc, " "), c->cap, row->opt));
    }
    return out;
}
static Names scenario_report(const Simulation *s) {
    const Config *c = s->config;
    const CoreStats *t = &s->total;
    L2Stats l2 = s->l2_stats;
    Names out = {0};
    Names_add(&out, format("scenario %s %s %s %s", s->scenario->name,
                           protocol_names[s->scenario->protocol],
                           replacement_names[s->scenario->l1], replacement_names[s->scenario->l2]));
    for (int core = 0; core < c->cores; ++core)
        extend(&out, six_lines(format("c%d", core), &s->cores[core]));
    extend(&out, six_lines("total", t));
    Names_add(
        &out,
        format(
            "l2 lookups %lld hits %lld misses %lld flushes %lld writebacks %lld evictions %lld dirty_evictions %lld",
            l2.lookups, l2.hits, l2.misses, l2.flushes, l2.writebacks, l2.evictions,
            l2.dirty_evictions));
    Number transactions = (Number)s->bus.transactions.count, busy = c->tb * transactions;
    Names_add(&out, format("bus transactions %lld busy %lld wait %lld utilization %s", transactions,
                           busy, s->bus.wait, decimal(100 * busy, t->finish)));
    Names_add(
        &out,
        format("traffic command_bytes %lld data_bytes %lld memory_bytes %lld", 8 * transactions,
               c->line_size * (t->bus[BUS_RD] + t->bus[BUS_RDX] + t->bus[WB]) + 4 * t->bus[BUS_WR],
               c->line_size * (l2.misses + l2.dirty_evictions)));
    Number probes = 0, hits = 0, fanout[8] = {0};
    const char *names[8];
    for (int i = 0; i < c->cores; ++i)
        names[i] = format("%d", i);
    for (size_t i = 0; i < s->bus.transactions.count; ++i) {
        Transaction tx = s->bus.transactions.items[i];
        if (tx.kind == WB)
            continue;
        probes += c->cores - 1;
        hits += tx.snoop_hits;
        if (tx.kind != BUS_RD)
            ++fanout[tx.invalidations];
    }
    Names_add(&out, format("snoops probes %lld hits %lld fanout %s", probes, hits,
                           range_counts(names, fanout, c->cores)));
    Number histogram[6] = {0};
    const char *ranges[] = {"1", "2-9", "10-29", "30-99", "100-299", "300+"};
    for (size_t i = 0; i < s->processed.count; ++i) {
        Number value = s->processed.items[i].latency;
        ++histogram[value == 1     ? 0
                    : value <= 9   ? 1
                    : value <= 29  ? 2
                    : value <= 99  ? 3
                    : value <= 299 ? 4
                                   : 5];
    }
    Names_add(&out, format("latencies reads %lld writes %lld histogram %s", t->read_latency,
                           t->write_latency, range_counts(ranges, histogram, 6)));
    return out;
}
static int rank_order(const void *left, const void *right) {
    const Simulation *a = *(Simulation *const *)left, *b = *(Simulation *const *)right;
    if (a->total.finish != b->total.finish)
        return a->total.finish < b->total.finish ? -1 : 1;
    if (a->bus.transactions.count != b->bus.transactions.count)
        return a->bus.transactions.count < b->bus.transactions.count ? -1 : 1;
    return a->scenario->order - b->scenario->order;
}
static Names ranking(Simulation *const *states, int count) {
    Simulation *ordered[8];
    memcpy(ordered, states, (size_t)count * sizeof(Simulation *));
    qsort(ordered, (size_t)count, sizeof(Simulation *), rank_order);
    Names out = {0};
    Names_add(&out, "ranking");
    for (int i = 0; i < count; ++i) {
        Simulation *s = ordered[i];
        Names_add(&out, format("%d %s finish %lld transactions %zu amat %s %s", i + 1,
                               s->scenario->name, s->total.finish, s->bus.transactions.count,
                               fraction(s->total.latency, s->total.accesses),
                               decimal(s->total.latency, s->total.accesses)));
    }
    return out;
}
typedef struct {
    Number block, types[5], transactions, misses, coherence, invalidations;
    unsigned cores;
} Hot;
static int hot_order(const void *a, const void *b) {
    const Hot *x = *(Hot *const *)a, *y = *(Hot *const *)b;
    if (x->transactions != y->transactions)
        return x->transactions > y->transactions ? -1 : 1;
    return x->block < y->block ? -1 : x->block > y->block;
}
static Names hot_lines(const Simulation *s) {
    Hot *records = allocate((size_t)s->facts->count * sizeof(Hot));
    for (int id = 0; id < s->facts->count; ++id)
        records[id].block = s->facts->blocks[id];
    for (size_t i = 0; i < s->bus.transactions.count; ++i) {
        Transaction tx = s->bus.transactions.items[i];
        Hot *h = &records[line_id(s->facts, tx.block)];
        ++h->transactions;
        ++h->types[tx.kind];
        h->invalidations += tx.invalidations;
        h->cores |= 1u << tx.core;
    }
    for (size_t i = 0; i < s->processed.count; ++i) {
        Processed p = s->processed.items[i];
        if (!p.hit) {
            ++records[p.line_id].misses;
            records[p.line_id].coherence += p.miss_kind == 3;
        }
    }
    Hot **ordered = allocate((size_t)s->facts->count * sizeof(Hot *));
    int count = 0;
    for (int id = 0; id < s->facts->count; ++id)
        if (records[id].transactions)
            ordered[count++] = &records[id];
    qsort(ordered, (size_t)count, sizeof(Hot *), hot_order);
    Names out = {0};
    Names_add(&out, format("hot %s", s->scenario->name));
    for (int i = 0; i < s->config->top && i < count; ++i) {
        Hot *h = ordered[i];
        Names values = {0};
        for (int j = 0; j < 5; ++j)
            Names_add(&values, format("%s %lld", transaction_names[j], h->types[j]));
        Names_add(
            &out,
            format(
                "%d %s transactions %lld %s misses %lld coherence %lld invalidations %lld cores %s",
                i + 1, hex_address(h->block * s->config->line_size), h->transactions,
                join(values, " "), h->misses, h->coherence, h->invalidations,
                core_string(h->cores)));
    }
    return out;
}
static Names interval_rows(const Simulation *s) {
    Number width = s->config->interval, count = s->total.finish / width + 1;
    typedef struct {
        Number accesses[8], misses, transactions, busy;
    } Interval;
    Interval *rows = allocate((size_t)count * sizeof(Interval));
    for (size_t i = 0; i < s->processed.count; ++i) {
        Processed p = s->processed.items[i];
        Interval *row = &rows[p.issue / width];
        ++row->accesses[p.core];
        row->misses += !p.hit;
    }
    for (size_t i = 0; i < s->bus.transactions.count; ++i) {
        Transaction tx = s->bus.transactions.items[i];
        Number first = tx.start, last = first + s->config->tb;
        ++rows[first / width].transactions;
        for (Number bucket = first / width; bucket <= (last - 1) / width && bucket < count;
             ++bucket)
            rows[bucket].busy +=
                maximum(0, minimum(last, (bucket + 1) * width) - maximum(first, bucket * width));
    }
    Names out = {0};
    Names_add(&out, format("intervals %s %lld", s->scenario->name, width));
    for (Number i = 0; i < count; ++i) {
        Names accesses = {0};
        for (int core = 0; core < s->config->cores; ++core)
            Names_add(&accesses, format("%lld", rows[i].accesses[core]));
        Names_add(
            &out,
            format(
                "%lld %lld-%lld accesses %s misses %lld transactions %lld busy %lld utilization %s",
                i, i * width, (i + 1) * width - 1, join(accesses, " "), rows[i].misses,
                rows[i].transactions, rows[i].busy, decimal(100 * rows[i].busy, width)));
    }
    return out;
}
static int slow_order(const void *a, const void *b) {
    const Processed *x = *(Processed *const *)a, *y = *(Processed *const *)b;
    if (x->latency != y->latency)
        return x->latency > y->latency ? -1 : 1;
    return x->number - y->number;
}
static Names slowest_rows(const Simulation *s) {
    Processed **ordered = allocate(s->processed.count * sizeof(Processed *));
    for (size_t i = 0; i < s->processed.count; ++i)
        ordered[i] = &s->processed.items[i];
    qsort(ordered, s->processed.count, sizeof(Processed *), slow_order);
    Names out = {0};
    Names_add(&out, format("slowest %s", s->scenario->name));
    for (size_t i = 0; i < s->processed.count && i < (size_t)s->config->top; ++i) {
        Processed *p = ordered[i];
        Names_add(&out, format("%zu event %d cycle %lld c%d %c %s latency %lld service %s", i + 1,
                               p->number, p->issue, p->core, p->operation, hex_address(p->address),
                               p->latency, service_names[p->service]));
    }
    return out;
}
static int region_for(Number address, const Config *c) {
    for (int i = 0; i < c->region_count; ++i)
        if (c->regions[i].first <= address && address <= c->regions[i].last)
            return i;
    return c->region_count;
}
static Names region_rows(const Simulation *s) {
    typedef struct {
        Number accesses, reads, writes, hits, latency, transactions, misses[4];
    } RegionStats;
    RegionStats rows[17] = {0};
    for (size_t i = 0; i < s->processed.count; ++i) {
        Processed p = s->processed.items[i];
        RegionStats *r = &rows[region_for(p.address, s->config)];
        ++r->accesses;
        if (p.operation == 'R')
            ++r->reads;
        else
            ++r->writes;
        r->latency += p.latency;
        if (p.hit)
            ++r->hits;
        else
            ++r->misses[p.miss_kind];
    }
    for (size_t i = 0; i < s->bus.transactions.count; ++i)
        ++rows[region_for(s->bus.transactions.items[i].block * s->config->line_size, s->config)]
              .transactions;
    Names out = {0};
    Names_add(&out, format("regions %s", s->scenario->name));
    for (int i = 0; i <= s->config->region_count; ++i) {
        RegionStats *r = &rows[i];
        Names misses = {0};
        for (int j = 0; j < 4; ++j)
            Names_add(&misses, format("%s %lld", miss_names[j], r->misses[j]));
        Names_add(
            &out,
            format(
                "%s accesses %lld reads %lld writes %lld hits %lld %s transactions %lld latency %lld amat %s",
                i < s->config->region_count ? s->config->regions[i].name : "other", r->accesses,
                r->reads, r->writes, r->hits, join(misses, " "), r->transactions, r->latency,
                r->accesses ? format("%s %s", fraction(r->latency, r->accesses),
                                     decimal(r->latency, r->accesses))
                            : "-"));
    }
    return out;
}
static Names sharing_output(const Facts *facts, const Simulation *s) {
    Names out = {0};
    Number count = 0, true_lines = 0, true_misses = 0, false_misses = 0;
    for (int id = 0; id < facts->count; ++id) {
        StaticLine *info = &facts->sharing[id];
        if (!info->shared)
            continue;
        ++count;
        true_lines += info->true_line;
        DynamicLine *dynamic = &s->dynamic[id];
        Number t = dynamic->sharing_misses[0], f = dynamic->sharing_misses[1];
        true_misses += t;
        false_misses += f;
        Names words = {0};
        for (int w = 0; w < s->config->line_size / 4; ++w) {
            WordSharing word = info->words[w];
            if (word.reads || word.writes)
                Names_add(&words, format("w%d=%s/%s", w, core_string(word.reads),
                                         core_string(word.writes)));
        }
        Names_add(
            &out,
            format(
                "%s %s cores %s writers %s reads %lld writes %lld handoffs %lld coherence %lld true %lld false %lld words %s",
                hex_address(facts->blocks[id] * s->config->line_size),
                info->true_line ? "true" : "false", core_string(info->cores),
                core_string(info->writers), info->reads, info->writes, dynamic->handoffs, t + f, t,
                f, join(words, " ")));
    }
    Names_add(
        &out,
        format("lines %lld true_lines %lld false_lines %lld coherence %lld true %lld false %lld",
               count, true_lines, count - true_lines, true_misses + false_misses, true_misses,
               false_misses));
    Names_add(&out, "communication");
    for (int core = 0; core < s->config->cores; ++core) {
        Names values = {0};
        for (int k = 0; k < s->config->cores; ++k)
            Names_add(&values, format("%lld", s->communications[core][k]));
        Names_add(&out, format("c%d %s", core, join(values, " ")));
    }
    return out;
}
static Names cache_rows(const Cache *cache, const char *label, int line_size) {
    Names out = {0};
    const char *policies[] = {"lru", "fifo", "plru"};
    for (int row = 0; row < cache->set_count; ++row) {
        Names ways = {0};
        const CacheSet *set = &cache->sets[row];
        for (int way = 0; way < cache->ways; ++way) {
            Entry entry = set->entries[way];
            Names_add(&ways, entry.valid ? format("%s:%c", hex_address(entry.block * line_size),
                                                  entry.state)
                                         : "-");
        }
        Names_add(&out, format("%s %d %s %s %s fills %lld evictions %lld", label, row,
                               join(ways, " "), policies[cache->replacement],
                               cache_order(cache, row), set->fills, set->evictions));
    }
    return out;
}
static Names final_state_output(const Simulation *s) {
    Names out = {0};
    bool *in_l1 = allocate((size_t)s->facts->count * sizeof(bool));
    Number in_l1_count = 0;
    for (int core = 0; core < s->config->cores; ++core) {
        const Cache *cache = &s->l1[core];
        extend(&out, cache_rows(cache, format("c%d", core), s->config->line_size));
        Number counts[256] = {0}, total = 0;
        for (int row = 0; row < cache->set_count; ++row)
            for (int way = 0; way < cache->ways; ++way) {
                Entry entry = cache->sets[row].entries[way];
                if (entry.valid) {
                    ++total;
                    ++counts[(unsigned char)entry.state];
                    int id = line_id(s->facts, entry.block);
                    if (!in_l1[id]) {
                        in_l1[id] = true;
                        ++in_l1_count;
                    }
                }
            }
        Names_add(&out, format("c%d lines %lld M %lld O %lld E %lld S %lld V %lld", core, total,
                               counts['M'], counts['O'], counts['E'], counts['S'], counts['V']));
    }
    extend(&out, cache_rows(&s->l2, "L2", s->config->line_size));
    Number dirty_count = 0, clean_count = 0;
    for (int row = 0; row < s->l2.set_count; ++row)
        for (int way = 0; way < s->l2.ways; ++way) {
            Entry entry = s->l2.sets[row].entries[way];
            if (entry.valid) {
                dirty_count += entry.state == 'D';
                clean_count += entry.state == 'C';
            }
        }
    Names_add(&out, format("L2 lines %lld dirty %lld clean %lld in_l1 %lld",
                           dirty_count + clean_count, dirty_count, clean_count, in_l1_count));
    return out;
}
int main(void) {
    Config config = read_config();
    Names trace = read_lines("input/trace.txt");
    Validated validated = validate_trace(trace, &config);
    Facts facts = build_facts(&validated.events, &config);
    Reuse reuse[8] = {0};
    reuse_analysis(&validated.events, &facts, &config, reuse);
    Simulation *states[8], *primary = NULL;
    for (int i = 0; i < config.scenario_count; ++i) {
        Simulation *state = allocate(sizeof(*state));
        states[i] = state;
        memory = &state->pool;
        simulate(state, &config, &config.scenarios[i], &validated.events, &facts);
        if (state->primary)
            primary = state;
        memory = &permanent;
    }
    Names statistics = {0};
    section(&statistics, trace_config(&config, trace, &validated));
    section(&statistics, reuse_lines(reuse, &config));
    for (int i = 0; i < config.scenario_count; ++i)
        section(&statistics, scenario_report(states[i]));
    section(&statistics, ranking(states, config.scenario_count));
    section(&statistics, hot_lines(primary));
    section(&statistics, interval_rows(primary));
    section(&statistics, slowest_rows(primary));
    section(&statistics, region_rows(primary));
    write_lines("stats.txt", statistics);
    Names transactions = {0};
    for (size_t i = 0; i < primary->bus.transactions.count; ++i)
        Names_add(&transactions, bus_line(&primary->bus, &primary->bus.transactions.items[i],
                                          config.line_size, config.cores));
    write_lines("bus_log.txt", transactions);
    write_lines("watch.txt", primary->watch);
    write_lines("sharing.txt", sharing_output(&facts, primary));
    write_lines("final_state.txt", final_state_output(primary));
    for (int i = 0; i < config.scenario_count; ++i)
        clear_memory(&states[i]->pool);
    clear_memory(&permanent);
    return 0;
}
