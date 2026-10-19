#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Number;
typedef struct { char text[64]; } Text;
typedef enum { FIXED, PASS, BASESTOCK, MINMAX, MOVAVG, SMOOTH, STERMAN } PolicyKind;
typedef enum { ORDERS, INV, BACK, NET } Metric;
typedef struct { PolicyKind kind; Number values[4]; char notation[64]; } Policy;
typedef struct {
    Number inventory, quantity, holding, backlog;
    int shipping_delay, order_delay;
    Policy policy;
} Initial;
typedef struct {
    Number received, incoming, shipped, before, ontime, inventory, backlog, order;
    Number holding_cost, backlog_cost;
} Record;
typedef struct {
    Number inventory, backlog, shipping[4], orders[4], expected;
    Number holding_rate, backlog_rate, lot, capacity;
    int shipping_delay, order_delay;
    Policy policy;
    Record records[104];
} Stage;
typedef struct { Number incoming, produced, backlog; } PlantRecord;
typedef struct {
    int week, horizon;
    Number demand[104];
    Stage stages[4];
    Number plant_backlog, plant_capacity;
    PlantRecord plant_records[104];
    bool visible;
} Simulation;
typedef struct { char name[9]; Simulation *state; } Snapshot;
typedef struct { Number total, minimum, maximum; } Statistics;
typedef struct { int first, end; } Range;
typedef struct { Number holding, backlog; } Costs;
typedef struct {
    Policy policy;
    int index;
    Number cost, ontime, incoming, variation;
} Comparison;

static const char *stage_names[] = { "RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY" };
static const char *policy_names[] = { "FIXED", "PASS", "BASESTOCK", "MINMAX", "MOVAVG", "SMOOTH", "STERMAN" };
static const char *metric_names[] = { "ORDERS", "INV", "BACK", "NET" };
static Initial initial[4];
static Number base_demand[104];
static int base_horizon, snapshot_count;
static Simulation current;
static Snapshot snapshots[1000];

static bool equal(const char *a, const char *b) { return strcmp(a, b) == 0; }
static Number number(const char *text) { return strtoll(text, NULL, 10); }
static Number minimum(Number a, Number b) { return a < b ? a : b; }
static Number maximum(Number a, Number b) { return a > b ? a : b; }
static Number absolute(Number n) { return n < 0 ? -n : n; }
static Number floor_div(Number a, Number b) { return a / b - (a % b < 0); }
static Number cost(Record r) { return r.holding_cost + r.backlog_cost; }

static void *resize(void *data, size_t size) {
    void *result = realloc(data, size);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = resize(NULL, capacity);
    int ch;
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 == capacity) line = resize(line, capacity *= 2);
        line[length++] = (char)ch;
    }
    if (!length && ch == EOF) { free(line); return NULL; }
    line[length] = '\0';
    return line;
}

static char **words(char *line, int *count) {
    int capacity = 16;
    char **tokens = resize(NULL, (size_t)capacity * sizeof *tokens);
    *count = 0;
    for (char *token = strtok(line, " "); token; token = strtok(NULL, " ")) {
        if (*count == capacity) tokens = resize(tokens, (size_t)(capacity *= 2) * sizeof *tokens);
        tokens[(*count)++] = token;
    }
    return tokens;
}

static bool fail(const char *format, ...) {
    va_list args;
    va_start(args, format);
    fputs("ERROR ", stdout);
    vprintf(format, args);
    putchar('\n');
    va_end(args);
    return false;
}

static Text money(Number cents) {
    Text result;
    snprintf(result.text, sizeof result.text, "%" PRId64 ".%02" PRId64, cents / 100, cents % 100);
    return result;
}

static Text decimal(Number numerator, Number denominator, int places) {
    Text result;
    if (!denominator) { strcpy(result.text, "n/a"); return result; }
    Number scale = places == 2 ? 100 : 10000;
    Number value = numerator * scale / denominator;
    snprintf(result.text, sizeof result.text, "%" PRId64 ".%0*" PRId64,
             value / scale, places, value % scale);
    return result;
}

static Text percentage(Number numerator, Number denominator) {
    Text result = decimal(numerator * 100, denominator, 2);
    if (denominator) strcat(result.text, "%");
    return result;
}

static Text capacity_text(Number capacity) {
    Text result;
    if (capacity < 0) strcpy(result.text, "OFF");
    else snprintf(result.text, sizeof result.text, "%" PRId64, capacity);
    return result;
}

static Text week_text(int week) {
    Text result;
    if (!week) strcpy(result.text, "-");
    else snprintf(result.text, sizeof result.text, "%d", week);
    return result;
}

static Number sum(const Number *values, int count) {
    Number total = 0;
    for (int i = 0; i < count; ++i) total += values[i];
    return total;
}

static Statistics statistics(const Number *values, int count) {
    Statistics result = { 0, INT64_MAX, INT64_MIN };
    for (int i = 0; i < count; ++i) {
        result.total += values[i];
        result.minimum = minimum(result.minimum, values[i]);
        result.maximum = maximum(result.maximum, values[i]);
    }
    return result;
}

static Number variation(const Number *values, int count) {
    Number squares = 0, total = sum(values, count);
    for (int i = 0; i < count; ++i) squares += values[i] * values[i];
    return count * squares - total * total;
}

static int stage_index(const char *name) {
    for (int i = 0; i < 4; ++i) if (equal(name, stage_names[i])) return i;
    fail("unknown stage %s", name);
    return -1;
}

static bool target(const char *name, int *index) {
    if (equal(name, "ALL")) { *index = -1; return true; }
    *index = stage_index(name);
    return *index >= 0;
}

static int metric_index(const char *name) {
    for (int i = 0; i < 4; ++i) if (equal(name, metric_names[i])) return i;
    fail("unknown mode %s", name);
    return -1;
}

static bool require_weeks(void) {
    return current.week > 0 || fail("no weeks simulated");
}

static bool range(char **args, int count, int limit, Range *result) {
    int first = count ? (int)number(args[0]) : 1;
    int end = count ? (int)number(args[1]) : limit;
    if (first < 1 || first > end || end > limit) return fail("bad range %s %s", args[0], args[1]);
    *result = (Range){ first - 1, end };
    return true;
}

static bool parse_policy(char **args, int count, Policy *result) {
    int kind = -1;
    for (int i = 0; i < 7; ++i) if (equal(args[0], policy_names[i])) kind = i;
    if (kind < 0) return fail("unknown policy %s", args[0]);
    const int parameter_counts[] = { 1, 0, 1, 2, 2, 2, 4 };
    int parameters = parameter_counts[kind];
    if (count != parameters + 1) return fail("%s needs %d parameters", args[0], parameters);
    Policy p = { .kind = (PolicyKind)kind };
    for (int i = 0; i < parameters; ++i) {
        p.values[i] = number(args[i + 1]);
        if (kind == STERMAN && i < 3)
            p.values[i] = p.values[i] * 100 + number(strchr(args[i + 1], '.') + 1);
    }
    Number *v = p.values;
    bool valid = false;
    switch (p.kind) {
        case FIXED: valid = v[0] <= 1000; break;
        case PASS: valid = true; break;
        case BASESTOCK: valid = v[0] <= 10000; break;
        case MINMAX: valid = v[0] < v[1] && v[1] <= 10000; break;
        case MOVAVG: valid = v[0] >= 1 && v[0] <= 52 && v[1] <= 10000; break;
        case SMOOTH: valid = v[0] >= 1 && v[0] <= 10 && v[1] <= 10000; break;
        case STERMAN: valid = v[0] <= 100 && v[1] <= 100 && v[2] <= 100 && v[3] <= 10000; break;
    }
    if (!valid) return fail("invalid parameter for %s", args[0]);
    for (int i = 0; i < count; ++i) {
        if (i) strcat(p.notation, " ");
        strcat(p.notation, args[i]);
    }
    *result = p;
    return true;
}

static void initialize(Simulation *sim, const Number *demand, int horizon) {
    memset(sim, 0, sizeof *sim);
    sim->horizon = horizon;
    memcpy(sim->demand, demand, (size_t)horizon * sizeof *demand);
    sim->plant_capacity = -1;
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i];
        Initial *cfg = &initial[i];
        s->inventory = cfg->inventory;
        s->shipping_delay = cfg->shipping_delay;
        s->order_delay = cfg->order_delay;
        for (int j = 0; j < 4; ++j) s->shipping[j] = s->orders[j] = cfg->quantity;
        s->policy = cfg->policy;
        s->expected = 100 * cfg->quantity;
        s->holding_rate = cfg->holding;
        s->backlog_rate = cfg->backlog;
        s->lot = 1;
        s->capacity = -1;
    }
}

static Number supply(const Simulation *sim, int index) {
    const Stage *s = &sim->stages[index];
    Number upstream = index == 3 ? sim->plant_backlog : sim->stages[index + 1].backlog;
    return sum(s->shipping, s->shipping_delay) + sum(s->orders, s->order_delay) + upstream;
}

static Number signal(const Simulation *sim, int stage, int week) {
    return sim->visible ? sim->demand[week] : sim->stages[stage].records[week].incoming;
}

static Number pop(Number *pipeline, int length) {
    Number value = pipeline[0];
    memmove(pipeline, pipeline + 1, (size_t)(length - 1) * sizeof *pipeline);
    pipeline[length - 1] = 0;
    return value;
}

static void step(Simulation *sim) {
    Record rows[4] = { 0 };
    PlantRecord plant = { 0 };
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i];
        rows[i].received = pop(s->shipping, s->shipping_delay);
        s->inventory += rows[i].received;
    }
    rows[0].incoming = sim->demand[sim->week];
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i];
        Number incoming = pop(s->orders, s->order_delay);
        if (i == 3) plant.incoming = incoming;
        else rows[i + 1].incoming = incoming;
    }
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i];
        Record *r = &rows[i];
        r->before = s->backlog;
        Number requested = s->backlog + r->incoming;
        r->shipped = minimum(s->inventory, requested);
        if (s->capacity >= 0) r->shipped = minimum(r->shipped, s->capacity);
        s->inventory -= r->shipped;
        s->backlog = requested - r->shipped;
        r->ontime = minimum(maximum(0, r->shipped - r->before), r->incoming);
        r->inventory = s->inventory;
        r->backlog = s->backlog;
        if (i) {
            Stage *downstream = &sim->stages[i - 1];
            downstream->shipping[downstream->shipping_delay - 1] = r->shipped;
        }
    }
    plant.produced = sim->plant_backlog + plant.incoming;
    if (sim->plant_capacity >= 0) plant.produced = minimum(plant.produced, sim->plant_capacity);
    sim->plant_backlog += plant.incoming - plant.produced;
    plant.backlog = sim->plant_backlog;
    Stage *factory = &sim->stages[3];
    factory->shipping[factory->shipping_delay - 1] = plant.produced;
    Number supplies[4];
    for (int i = 0; i < 4; ++i) supplies[i] = supply(sim, i);
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i];
        Record *r = &rows[i];
        Number position = s->inventory + supplies[i] - s->backlog;
        Number demand = sim->visible ? sim->demand[sim->week] : r->incoming;
        Number *p = s->policy.values, quantity = 0;
        switch (s->policy.kind) {
            case FIXED: quantity = p[0]; break;
            case PASS: quantity = r->incoming; break;
            case BASESTOCK: quantity = maximum(0, p[0] - position); break;
            case MINMAX: quantity = position <= p[0] ? p[1] - position : 0; break;
            case MOVAVG: {
                int count = (int)minimum(p[0], sim->week + 1);
                Number total = demand;
                for (int t = sim->week + 1 - count; t < sim->week; ++t) total += signal(sim, i, t);
                Number forecast = total / count;
                quantity = maximum(0, p[1] + forecast * (s->shipping_delay + s->order_delay) - position);
                break;
            }
            case SMOOTH: quantity = maximum(0, demand + floor_div(p[1] - position, p[0])); break;
            case STERMAN: {
                s->expected = floor_div(100 * p[0] * demand + (100 - p[0]) * s->expected, 100);
                Number net = s->inventory - s->backlog;
                quantity = maximum(0, floor_div(100 * s->expected + p[1] * (100 * (p[3] - net) - p[2] * supplies[i]), 10000));
                break;
            }
        }
        r->order = (quantity + s->lot - 1) / s->lot * s->lot;
        s->orders[s->order_delay - 1] = r->order;
        r->holding_cost = s->holding_rate * s->inventory;
        r->backlog_cost = s->backlog_rate * s->backlog;
        s->records[sim->week] = *r;
    }
    sim->plant_records[sim->week++] = plant;
}

static void trial(Simulation *sim, const Policy *policies) {
    initialize(sim, current.demand, current.horizon);
    sim->visible = current.visible;
    sim->plant_capacity = current.plant_capacity;
    for (int i = 0; i < 4; ++i) {
        Stage *s = &sim->stages[i], *old = &current.stages[i];
        s->policy = policies[i];
        s->lot = old->lot;
        s->capacity = old->capacity;
        s->holding_rate = old->holding_rate;
        s->backlog_rate = old->backlog_rate;
    }
    while (sim->week < sim->horizon) step(sim);
}

static Costs stage_costs(const Simulation *sim, int stage) {
    Costs result = { 0 };
    for (int t = 0; t < sim->week; ++t) {
        result.holding += sim->stages[stage].records[t].holding_cost;
        result.backlog += sim->stages[stage].records[t].backlog_cost;
    }
    return result;
}

static Number total_cost(const Simulation *sim) {
    Number total = 0;
    for (int i = 0; i < 4; ++i) {
        Costs c = stage_costs(sim, i);
        total += c.holding + c.backlog;
    }
    return total;
}

static void values(const Simulation *sim, int stage, Metric metric, Number *result) {
    for (int t = 0; t < sim->week; ++t) {
        Record r = sim->stages[stage].records[t];
        switch (metric) {
            case ORDERS: result[t] = r.order; break;
            case INV: result[t] = r.inventory; break;
            case BACK: result[t] = r.backlog; break;
            case NET: result[t] = r.inventory - r.backlog; break;
        }
    }
}

static void set_demand(const Number *demand, int horizon) {
    memcpy(base_demand, demand, (size_t)horizon * sizeof *demand);
    base_horizon = horizon;
    initialize(&current, base_demand, base_horizon);
    Statistics s = statistics(demand, horizon);
    printf("DEMAND weeks %d total %" PRId64 " min %" PRId64 " max %" PRId64 "\n", horizon, s.total, s.minimum, s.maximum);
}

static void pipeline(const Number *values, int count) {
    for (int i = 0; i < count; ++i) printf("%s%" PRId64, i ? "," : "", values[i]);
}

static void repeat(char ch, Number count) {
    for (Number i = 0; i < count; ++i) putchar(ch);
}

static int compare_results(const void *left, const void *right) {
    const Comparison *a = left, *b = right;
    if (a->cost != b->cost) return a->cost < b->cost ? -1 : 1;
    return a->index - b->index;
}

static void execute(char **a, int count) {
    const char *op = a[0], *id = count > 1 ? a[1] : "";
    Simulation *sim = &current;
    int n = sim->week;
    if (equal(op, "DEMAND")) {
        Number demand[104];
        for (int i = 1; i < count; ++i) demand[i - 1] = number(a[i]);
        set_demand(demand, count - 1);
    } else if (equal(op, "GENERATE")) {
        int horizon = (int)number(id);
        for (int i = 5; i < count; i += 3) {
            Number week = number(a[i + 1]);
            if (week < 1 || week > horizon) { fail("week %s outside horizon", a[i + 1]); return; }
        }
        Number demand[104], random = number(a[4]);
        for (int t = 1; t <= horizon; ++t) {
            Number level = number(a[2]);
            for (int i = 5; i < count; i += 3) {
                Number elapsed = t - number(a[i + 1]), amount = number(a[i + 2]);
                if (elapsed < 0) continue;
                if (equal(a[i], "STEP")) level += amount;
                else if (equal(a[i], "RAMP")) level += amount * (elapsed + 1);
                else if (!elapsed) level += amount;
            }
            if (level < 0) { fail("negative level at week %d", t); return; }
            random = 48271 * random % 2147483647;
            demand[t - 1] = level + random % number(a[3]);
        }
        set_demand(demand, horizon);
    } else if (equal(op, "RUN")) {
        if (n == sim->horizon) { fail("horizon reached at week %d", n); return; }
        int end = (int)minimum(sim->horizon, n + number(id));
        Number total = 0;
        while (sim->week < end) {
            step(sim);
            for (int i = 0; i < 4; ++i) {
                Record r = sim->stages[i].records[sim->week - 1];
                total += cost(r);
                if (!r.before && r.backlog > 0) printf("STOCKOUT %s week %d backlog %" PRId64 "\n", stage_names[i], sim->week, r.backlog);
                if (r.before > 0 && !r.backlog) printf("RECOVER %s week %d\n", stage_names[i], sim->week);
            }
        }
        printf("RUN %d-%d demand %" PRId64 " cost %s\n", n + 1, end, sum(sim->demand + n, end - n), money(total).text);
        if (end == sim->horizon) printf("HORIZON %d\n", end);
    } else if (equal(op, "RESET")) {
        initialize(sim, base_demand, base_horizon);
        puts("RESET week 0");
    } else if (equal(op, "SAVE") || equal(op, "LOAD")) {
        int i = 0;
        while (i < snapshot_count && !equal(snapshots[i].name, id)) ++i;
        if (equal(op, "LOAD")) {
            if (i == snapshot_count) { fail("no snapshot %s", id); return; }
            *sim = *snapshots[i].state;
        } else {
            if (i == snapshot_count) {
                strcpy(snapshots[i].name, id);
                snapshots[i].state = resize(NULL, sizeof *sim);
                ++snapshot_count;
            }
            *snapshots[i].state = *sim;
        }
        printf("%s %s week %d\n", op, id, sim->week);
    } else if (equal(op, "SET")) {
        int selected;
        Policy policy;
        if (!target(id, &selected) || !parse_policy(a + 2, count - 2, &policy)) return;
        for (int i = 0; i < 4; ++i) {
            if (selected >= 0 && selected != i) continue;
            sim->stages[i].policy = policy;
            if (policy.kind == STERMAN) sim->stages[i].expected = 100 * (n ? signal(sim, i, n - 1) : initial[i].quantity);
        }
        printf("SET %s %s\n", id, policy.notation);
    } else if (equal(op, "BATCH") || equal(op, "CAPACITY") || equal(op, "COST")) {
        int i = equal(op, "CAPACITY") && equal(id, "PLANT") ? 4 : stage_index(id);
        if (i < 0) return;
        if (equal(op, "BATCH")) {
            Number lot = number(a[2]);
            if (lot < 1 || lot > 100) { fail("invalid batch size %s", a[2]); return; }
            sim->stages[i].lot = lot;
            printf("BATCH %s %" PRId64 "\n", id, lot);
        } else if (equal(op, "CAPACITY")) {
            Number cap = equal(a[2], "OFF") ? -1 : number(a[2]);
            if (cap > 10000) { fail("invalid capacity %s", a[2]); return; }
            if (i == 4) sim->plant_capacity = cap;
            else sim->stages[i].capacity = cap;
            printf("CAPACITY %s %s\n", id, a[2]);
        } else {
            Number holding = number(a[2]), backlog = number(a[3]);
            if (holding > 1000 || backlog > 1000) { fail("invalid cost"); return; }
            sim->stages[i].holding_rate = holding;
            sim->stages[i].backlog_rate = backlog;
            printf("COST %s holding %" PRId64 " backlog %" PRId64 "\n", id, holding, backlog);
        }
    } else if (equal(op, "VISIBILITY")) {
        if (!equal(id, "ON") && !equal(id, "OFF")) { fail("unknown visibility %s", id); return; }
        sim->visible = equal(id, "ON");
        printf("VISIBILITY %s\n", id);
    } else if (equal(op, "SHOCK")) {
        int week = (int)number(id);
        if (week < 1 || week > sim->horizon) { fail("week %s outside horizon", id); return; }
        if (week <= n) { fail("week %s already simulated", id); return; }
        Number old = sim->demand[week - 1];
        sim->demand[week - 1] = number(a[2]);
        printf("SHOCK week %d %" PRId64 " -> %" PRId64 "\n", week, old, sim->demand[week - 1]);
    } else if (equal(op, "STATUS")) {
        printf("STATUS week %d of %d\n", n, sim->horizon);
        for (int i = 0; i < 4; ++i) {
            Stage *s = &sim->stages[i];
            printf("%s inv %" PRId64 " back %" PRId64 " transit ", stage_names[i], s->inventory, s->backlog);
            pipeline(s->shipping, s->shipping_delay);
            fputs(" pending ", stdout);
            pipeline(s->orders, s->order_delay);
            Number line = supply(sim, i);
            printf(" supply %" PRId64 " position %" PRId64 " policy %s", line, s->inventory + line - s->backlog, s->policy.notation);
            if (s->policy.kind == STERMAN) printf(" expect %s", money(s->expected).text);
            putchar('\n');
        }
        printf("PLANT back %" PRId64 "\n", sim->plant_backlog);
    } else if (equal(op, "SETTINGS")) {
        puts("SETTINGS");
        for (int i = 0; i < 4; ++i) {
            Stage *s = &sim->stages[i];
            printf("%s holding %" PRId64 " backlog %" PRId64 " batch %" PRId64 " capacity %s delays %d %d\n",
                   stage_names[i], s->holding_rate, s->backlog_rate, s->lot, capacity_text(s->capacity).text, s->shipping_delay, s->order_delay);
        }
        printf("PLANT capacity %s\nVISIBILITY %s\n", capacity_text(sim->plant_capacity).text, sim->visible ? "ON" : "OFF");
    } else if (equal(op, "WEEK")) {
        if (!require_weeks()) return;
        int week = (int)number(id);
        if (week < 1 || week > n) { fail("bad week %s", id); return; }
        printf("WEEK %d demand %" PRId64 "\n", week, sim->demand[week - 1]);
        for (int i = 0; i < 4; ++i) {
            Record r = sim->stages[i].records[week - 1];
            printf("%s recv %" PRId64 " in %" PRId64 " ship %" PRId64 " inv %" PRId64 " back %" PRId64 " order %" PRId64 " cost %s\n",
                   stage_names[i], r.received, r.incoming, r.shipped, r.inventory, r.backlog, r.order, money(cost(r)).text);
        }
        PlantRecord p = sim->plant_records[week - 1];
        printf("PLANT in %" PRId64 " made %" PRId64 " back %" PRId64 "\n", p.incoming, p.produced, p.backlog);
    } else if (equal(op, "TABLE") || equal(op, "CHAIN") || equal(op, "DEMANDS")) {
        int i = -1, skip = equal(op, "TABLE") ? 2 : 1;
        if (skip == 2 && (i = stage_index(id)) < 0) return;
        if (!equal(op, "DEMANDS") && !require_weeks()) return;
        Range r;
        if (!range(a + skip, count - skip, equal(op, "DEMANDS") ? sim->horizon : n, &r)) return;
        if (equal(op, "TABLE")) {
            printf("TABLE %s %d-%d\nweek     in   ship   recv    inv   back  order      cost\n", id, r.first + 1, r.end);
            for (int t = r.first; t < r.end; ++t) {
                Record v = sim->stages[i].records[t];
                printf("%4d %6" PRId64 " %6" PRId64 " %6" PRId64 " %6" PRId64 " %6" PRId64 " %6" PRId64 " %9s\n",
                       t + 1, v.incoming, v.shipped, v.received, v.inventory, v.backlog, v.order, money(cost(v)).text);
            }
        } else if (equal(op, "CHAIN")) {
            printf("CHAIN %d-%d\n%4s %6s", r.first + 1, r.end, "week", "demand");
            for (int j = 0; j < 4; ++j) printf(" %11s", stage_names[j]);
            putchar('\n');
            for (int t = r.first; t < r.end; ++t) {
                printf("%4d %6" PRId64, t + 1, sim->demand[t]);
                for (int j = 0; j < 4; ++j) printf(" %11" PRId64, sim->stages[j].records[t].order);
                putchar('\n');
            }
        } else {
            Statistics s = statistics(sim->demand + r.first, r.end - r.first);
            printf("DEMANDS %d-%d total %" PRId64 " min %" PRId64 " max %" PRId64 "\n", r.first + 1, r.end, s.total, s.minimum, s.maximum);
            for (int t = r.first; t < r.end; ++t) printf("%s%" PRId64, t == r.first ? "" : " ", sim->demand[t]);
            putchar('\n');
        }
    } else if (equal(op, "COSTS")) {
        printf("COSTS week %d\n", n);
        Costs total = { 0 };
        for (int i = 0; i < 4; ++i) {
            Costs c = stage_costs(sim, i);
            printf("%s holding %s backlog %s total %s\n", stage_names[i], money(c.holding).text, money(c.backlog).text, money(c.holding + c.backlog).text);
            total.holding += c.holding;
            total.backlog += c.backlog;
        }
        printf("TOTAL holding %s backlog %s total %s\n", money(total.holding).text, money(total.backlog).text, money(total.holding + total.backlog).text);
    } else if (equal(op, "SUMMARY")) {
        if (!require_weeks()) return;
        printf("SUMMARY weeks 1-%d\n", n);
        for (int i = 0; i < 4; ++i) {
            Number inventory = 0, backlog = 0, orders[104];
            int zero = 0;
            values(sim, i, ORDERS, orders);
            Statistics s = statistics(orders, n);
            for (int t = 0; t < n; ++t) {
                Record r = sim->stages[i].records[t];
                inventory += r.inventory;
                backlog += r.backlog;
                zero += r.order == 0;
            }
            printf("%s avg_inv %s avg_back %s orders %" PRId64 " min %" PRId64 " max %" PRId64 " zero_weeks %d\n",
                   stage_names[i], decimal(inventory, n, 2).text, decimal(backlog, n, 2).text, s.total, s.minimum, s.maximum, zero);
        }
    } else if (equal(op, "BALANCE")) {
        printf("BALANCE week %d\n", n);
        Number goods = 0, stock = 0, transit = 0, delivered = 0, produced = 0;
        for (int i = 0; i < 4; ++i) {
            Stage *s = &sim->stages[i];
            Number received = 0, shipped = 0;
            for (int t = 0; t < n; ++t) { received += s->records[t].received; shipped += s->records[t].shipped; }
            printf("%s start %" PRId64 " received %" PRId64 " shipped %" PRId64 " end %" PRId64 " owed %" PRId64 "\n",
                   stage_names[i], initial[i].inventory, received, shipped, s->inventory, s->backlog);
            goods += initial[i].inventory + initial[i].quantity * s->shipping_delay;
            stock += s->inventory;
            transit += sum(s->shipping, s->shipping_delay);
            if (!i) delivered = shipped;
        }
        for (int t = 0; t < n; ++t) produced += sim->plant_records[t].produced;
        printf("SYSTEM initial %" PRId64 " produced %" PRId64 " delivered %" PRId64 " stock %" PRId64 " transit %" PRId64 "\n", goods, produced, delivered, stock, transit);
    } else if (equal(op, "FILLRATE")) {
        if (!require_weeks()) return;
        printf("FILLRATE weeks 1-%d\n", n);
        for (int i = 0; i < 4; ++i) {
            Number ontime = 0, incoming = 0;
            int stockouts = 0;
            for (int t = 0; t < n; ++t) {
                Record r = sim->stages[i].records[t];
                ontime += r.ontime; incoming += r.incoming; stockouts += r.backlog > 0;
            }
            printf("%s fill %s ontime %" PRId64 " ordered %" PRId64 " stockout_weeks %d service %s\n",
                   stage_names[i], percentage(ontime, incoming).text, ontime, incoming, stockouts, percentage(n - stockouts, n).text);
        }
    } else if (equal(op, "BULLWHIP")) {
        if (!require_weeks()) return;
        Number demand_var = variation(sim->demand, n), previous = demand_var;
        printf("BULLWHIP weeks 1-%d demand mean %s var %s\n", n, decimal(sum(sim->demand, n), n, 4).text, decimal(demand_var, n * n, 4).text);
        for (int i = 0; i < 4; ++i) {
            Number orders[104];
            values(sim, i, ORDERS, orders);
            Number v = variation(orders, n);
            printf("%s mean %s var %s ratio %s step %s\n", stage_names[i], decimal(sum(orders, n), n, 4).text,
                   decimal(v, n * n, 4).text, decimal(v, demand_var, 4).text, decimal(v, previous, 4).text);
            previous = v;
        }
    } else if (equal(op, "PEAKS")) {
        if (!require_weeks()) return;
        printf("PEAKS weeks 1-%d\n", n);
        for (int i = 0; i < 4; ++i) {
            Number inventory = 0, backlog = 0;
            int inv_week = 0, back_week = 0, streak = 0, longest = 0, last = 0;
            for (int t = 0; t < n; ++t) {
                Record r = sim->stages[i].records[t];
                if (r.inventory > inventory) { inventory = r.inventory; inv_week = t + 1; }
                if (r.backlog > backlog) { backlog = r.backlog; back_week = t + 1; }
                streak = r.backlog > 0 ? streak + 1 : 0;
                if (streak > longest) { longest = streak; last = t + 1; }
            }
            printf("%s max_inv %" PRId64 " week %s max_back %" PRId64 " week %s longest_stockout %d",
                   stage_names[i], inventory, week_text(inv_week).text, backlog, week_text(back_week).text, longest);
            if (longest) printf(" weeks %d-%d", last - longest + 1, last);
            putchar('\n');
        }
    } else if (equal(op, "LEADTIME")) {
        int i = stage_index(id);
        if (i < 0 || !require_weeks()) return;
        Stage *s = &sim->stages[i];
        int nominal = s->shipping_delay + s->order_delay;
        Number arrivals[104], received = -nominal * initial[i].quantity, ordered = 0, total = 0;
        for (int t = 0; t < n; ++t) { received += s->records[t].received; arrivals[t] = received; }
        int orders = 0, completed = 0, low = INT_MAX, high = 0;
        for (int t = 0; t < n; ++t) {
            ordered += s->records[t].order;
            if (!s->records[t].order) continue;
            ++orders;
            for (int u = t + 1; u < n; ++u) {
                if (arrivals[u] < ordered) continue;
                int lead = u - t;
                if (lead < low) low = lead;
                if (lead > high) high = lead;
                total += lead;
                ++completed;
                break;
            }
        }
        printf("LEADTIME %s nominal %d orders %d completed %d open %d", id, nominal, orders, completed, orders - completed);
        if (!completed) puts(" min - avg - max -");
        else printf(" min %d avg %s max %d\n", low, decimal(total, completed, 2).text, high);
    } else if (equal(op, "PLOT") || equal(op, "HISTOGRAM")) {
        int i = stage_index(id);
        if (i < 0) return;
        int metric = metric_index(a[2]);
        if (metric < 0) return;
        bool histogram = equal(op, "HISTOGRAM");
        Number width = histogram ? number(a[3]) : 0;
        if (histogram && (width < 1 || width > 100)) { fail("invalid width %s", a[3]); return; }
        if (!require_weeks()) return;
        Range r = { 0, n };
        if (!histogram && !range(a + 3, count - 3, n, &r)) return;
        Number all[104];
        values(sim, i, (Metric)metric, all);
        Statistics stats = statistics(all + r.first, r.end - r.first);
        if (histogram) {
            printf("HISTOGRAM %s %s width %" PRId64 " weeks 1-%d\n", id, a[2], width, n);
            Number last = floor_div(stats.maximum, width);
            for (Number bin = floor_div(stats.minimum, width); bin <= last; ++bin) {
                int frequency = 0;
                for (int t = 0; t < n; ++t) frequency += floor_div(all[t], width) == bin;
                printf("%" PRId64 "..%" PRId64 " %d", bin * width, bin * width + width - 1, frequency);
                if (frequency) { putchar(' '); repeat('*', frequency); }
                putchar('\n');
            }
        } else if (metric == NET) {
            printf("PLOT %s NET %d-%d min %" PRId64 " max %" PRId64 "\n", id, r.first + 1, r.end, stats.minimum, stats.maximum);
            Number magnitude = maximum(absolute(stats.minimum), absolute(stats.maximum));
            for (int t = r.first; t < r.end; ++t) {
                Number bars = magnitude ? absolute(all[t]) * 25 / magnitude : 0;
                printf("%3d ", t + 1);
                repeat(' ', all[t] < 0 ? 25 - bars : 25);
                if (all[t] < 0) repeat('-', bars);
                putchar('|');
                if (all[t] > 0) repeat('+', bars);
                printf(" %" PRId64 "\n", all[t]);
            }
        } else {
            printf("PLOT %s %s %d-%d max %" PRId64 "\n", id, a[2], r.first + 1, r.end, stats.maximum);
            for (int t = r.first; t < r.end; ++t) {
                printf("%3d |", t + 1);
                repeat('#', stats.maximum ? all[t] * 50 / stats.maximum : 0);
                printf(" %" PRId64 "\n", all[t]);
            }
        }
    } else if (equal(op, "COMPARE")) {
        Policy policies[8];
        Comparison results[8];
        int start = 1, length = 0;
        for (int i = 1; i <= count; ++i) {
            if (i < count && !equal(a[i], "/")) continue;
            if (!parse_policy(a + start, i - start, &policies[length++])) return;
            start = i + 1;
        }
        for (int i = 0; i < length; ++i) {
            Policy all[4];
            for (int j = 0; j < 4; ++j) all[j] = policies[i];
            Simulation candidate;
            trial(&candidate, all);
            Comparison r = { .policy = policies[i], .index = i, .cost = total_cost(&candidate) };
            for (int t = 0; t < candidate.week; ++t) {
                r.ontime += candidate.stages[0].records[t].ontime;
                r.incoming += candidate.stages[0].records[t].incoming;
            }
            Number orders[104];
            values(&candidate, 3, ORDERS, orders);
            r.variation = variation(orders, candidate.week);
            results[i] = r;
        }
        qsort(results, (size_t)length, sizeof *results, compare_results);
        Number demand_variation = variation(sim->demand, sim->horizon);
        printf("COMPARE %d weeks %d\n", length, sim->horizon);
        for (int i = 0; i < length; ++i) {
            Comparison r = results[i];
            printf("%d %s total %s fill %s bullwhip %s\n", i + 1, r.policy.notation, money(r.cost).text,
                   percentage(r.ontime, r.incoming).text, decimal(r.variation, demand_variation, 4).text);
        }
    } else if (equal(op, "OPTIMIZE")) {
        int selected;
        if (!target(id, &selected)) return;
        Number low = number(a[2]), high = number(a[3]);
        if (low > high) { fail("bad range %s %s", a[2], a[3]); return; }
        if (high - low > 200) { fail("range too large"); return; }
        Number best = low, best_cost = INT64_MAX, best_total = 0;
        for (Number stock = low; stock <= high; ++stock) {
            Policy policies[4];
            for (int i = 0; i < 4; ++i)
                policies[i] = selected < 0 || selected == i ? (Policy){ .kind = BASESTOCK, .values = { stock } } : sim->stages[i].policy;
            Simulation candidate;
            trial(&candidate, policies);
            Number total = total_cost(&candidate), objective = total;
            if (selected >= 0) {
                Costs c = stage_costs(&candidate, selected);
                objective = c.holding + c.backlog;
            }
            if (objective < best_cost) { best = stock; best_cost = objective; best_total = total; }
        }
        printf("OPTIMIZE %s BASESTOCK %" PRId64 " cost %s total %s\n", id, best, money(best_cost).text, money(best_total).text);
    } else fail("unknown command %s", op);
}

int main(void) {
    for (int i = 0; i < 4; ++i) {
        char *line = read_line();
        if (!line) return EXIT_FAILURE;
        int count;
        char **a = words(line, &count);
        initial[i] = (Initial){ .inventory = number(a[1]), .quantity = number(a[2]),
            .shipping_delay = (int)number(a[3]), .order_delay = (int)number(a[4]),
            .holding = number(a[5]), .backlog = number(a[6]) };
        if (!parse_policy(a + 7, count - 7, &initial[i].policy)) return EXIT_FAILURE;
        free(a);
        free(line);
    }
    initialize(&current, base_demand, 0);
    char *line;
    while ((line = read_line()) != NULL) {
        int count;
        char **a = words(line, &count);
        bool done = equal(a[0], "END");
        if (!done) execute(a, count);
        free(a);
        free(line);
        if (done) break;
    }
    for (int i = 0; i < snapshot_count; ++i) free(snapshots[i].state);
    return 0;
}
