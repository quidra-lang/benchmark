#include "simulator.h"
const char *classes[7] = {"ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP"};
const char *causes[4] = {"control", "structural", "load_use", "raw"};
const char *misses[3] = {"direction", "btb_miss", "wrong_target"};
const char *stages[5] = {"IF", "ID", "EX", "MEM", "WB"};
typedef struct {
    int line;
    const char *reason;
} Rejection;
typedef struct {
    int line;
    I expected, found;
} Gap;
typedef struct {
    int first, last;
    I count, taken, stalls[4];
} Static;
typedef struct {
    I pc;
    int id;
} StaticRef;
typedef struct {
    Instruction *instructions;
    Static *statics;
    int *next_static, *hash;
    int count, static_count, rejected_count, gap_count;
    Rejection *rejected;
    Gap *gaps;
} Trace;
static unsigned hash_pc(I pc) { return (unsigned)((uint64_t)(pc / 4) * 2654435761u) & 65535u; }
static int *find_slot(Trace *trace, I pc) {
    unsigned slot = hash_pc(pc);
    while (trace->hash[slot] &&
           trace->instructions[trace->statics[trace->hash[slot] - 1].first].pc != pc)
        slot = (slot + 1) & 65535u;
    return &trace->hash[slot];
}
static const char *check(char *text, Trace *trace, Instruction *out) {
    char *fields[8];
    int count = 1;
    fields[0] = text;
    for (char *p = text; *p; ++p)
        if (*p == ' ') {
            *p = '\0';
            if (count < 8)
                fields[count] = p + 1;
            ++count;
        }
    if (count != 8)
        return "fields";
    for (int i = 0; i < 8; ++i)
        if (!*fields[i])
            return "fields";
    if (!parse_hex(fields[0], &out->pc) || out->pc % 4)
        return "pc";
    out->kind = -1;
    for (int i = 0; i < 7; ++i)
        if (strcmp(fields[1], classes[i]) == 0)
            out->kind = i;
    if (out->kind < 0)
        return "class";
    int registers[3] = {parse_register(fields[2]), parse_register(fields[3]),
                        parse_register(fields[4])};
    for (int i = 0; i < 3; ++i)
        if (registers[i] == -2)
            return "register";
    static const int usage[7][3] = {{1, 1, 0},  {1, 1, 1},  {1, 1, -1},  {-1, 1, 1},
                                    {-1, 1, 0}, {0, 0, -1}, {-1, -1, -1}};
    for (int i = 0; i < 3; ++i)
        if ((usage[out->kind][i] == 1 && registers[i] < 0) ||
            (usage[out->kind][i] == -1 && registers[i] >= 0))
            return "operands";
    out->rd = registers[0];
    out->rs1 = registers[1];
    out->rs2 = registers[2];
    if (out->kind == BRANCH ? (strcmp(fields[5], "T") && strcmp(fields[5], "N"))
                            : strcmp(fields[5], out->kind == JUMP ? "T" : "-"))
        return "taken";
    out->taken = strcmp(fields[5], "T") == 0;
    if (control(*out)) {
        if (!parse_hex(fields[6], &out->target) || out->target % 4 || out->target == out->pc + 4)
            return "target";
    } else if (strcmp(fields[6], "-"))
        return "target";
    if (out->kind == LOAD || out->kind == STORE) {
        if (!parse_hex(fields[7], &out->address) || out->address % 4)
            return "address";
    } else if (strcmp(fields[7], "-"))
        return "address";
    int slot = *find_slot(trace, out->pc);
    if (slot) {
        Instruction old = trace->instructions[trace->statics[slot - 1].first];
        if (out->kind != old.kind || out->rd != old.rd || out->rs1 != old.rs1 ||
            out->rs2 != old.rs2 ||
            ((out->kind == BRANCH || (out->kind == JUMP && out->rs1 < 0)) &&
             out->target != old.target))
            return "conflict";
    }
    out->next = out->taken ? out->target : out->pc + 4;
    return NULL;
}
static Trace validate(Lines lines) {
    Trace out = {0};
    out.instructions = allocate((size_t)lines.count, sizeof(Instruction));
    out.statics = allocate((size_t)lines.count, sizeof(Static));
    out.next_static = allocate((size_t)lines.count, sizeof(int));
    out.hash = allocate(65536, sizeof(int));
    out.rejected = allocate((size_t)lines.count, sizeof(Rejection));
    out.gaps = allocate((size_t)lines.count, sizeof(Gap));
    for (int i = 0; i < lines.count; ++i) {
        Instruction instruction = {0};
        char *copy = format("%s", lines.data[i]);
        const char *error = check(copy, &out, &instruction);
        if (error) {
            out.rejected[out.rejected_count++] = (Rejection){i + 1, error};
            continue;
        }
        instruction.line = i + 1;
        if (out.count && out.instructions[out.count - 1].next != instruction.pc)
            out.gaps[out.gap_count++] =
                (Gap){i + 1, out.instructions[out.count - 1].next, instruction.pc};
        int *slot = find_slot(&out, instruction.pc);
        if (!*slot) {
            *slot = ++out.static_count;
            out.statics[*slot - 1].first = out.count;
        } else
            out.next_static[out.statics[*slot - 1].last] = out.count;
        instruction.static_id = *slot - 1;
        Static *group = &out.statics[instruction.static_id];
        group->last = out.count;
        ++group->count;
        group->taken += instruction.taken;
        out.next_static[out.count] = -1;
        out.instructions[out.count++] = instruction;
    }
    return out;
}
typedef struct {
    I predicted;
    int miss;
} Detail;
typedef struct {
    Detail *details;
    bool *flags;
    I control, total_misses, hits, calls, returns, ras_predictions, ras_correct, count[2], wrong[2],
        kinds[3];
    int bits;
} Prediction;
static Prediction predict(const Instruction *instructions, int count, Predictor definition,
                          Config config) {
    Prediction out = {0};
    out.details = allocate((size_t)count, sizeof(Detail));
    out.flags = allocate((size_t)count, sizeof(bool));
    out.bits = storage(definition);
    BTB btb = btb_create(config.btb);
    RAS ras = {0};
    ras.depth = config.ras;
    DirectionPredictor direction = direction_create(definition);
    for (int i = 0; i < count; ++i) {
        Instruction instruction = instructions[i];
        out.details[i].miss = -1;
        if (!control(instruction))
            continue;
        I candidate = 0;
        bool has_candidate = btb_lookup(&btb, instruction.pc, &candidate);
        ++out.control;
        out.hits += has_candidate;
        bool call = instruction.kind == JUMP && instruction.rd == 31,
             ret = instruction.kind == JUMP && instruction.rd < 0 && instruction.rs1 == 31;
        out.calls += call;
        out.returns += ret;
        I address;
        if (ret && ras_pop(&ras, &address)) {
            candidate = address;
            has_candidate = true;
            ++out.ras_predictions;
            out.ras_correct += address == instruction.target;
        }
        if (call)
            ras_push(&ras, instruction.pc + 4);
        bool taken = instruction.kind == BRANCH
                         ? direction_predict(&direction, instruction.pc, instruction.target)
                         : true;
        I next = strcmp(definition.scheme, "PERFECT") == 0
                     ? instruction.next
                     : ((instruction.kind == JUMP || taken) && has_candidate ? candidate
                                                                             : instruction.pc + 4);
        out.details[i].predicted = next;
        if (next != instruction.next) {
            int kind = instruction.kind == BRANCH && taken != instruction.taken ? 0
                       : !has_candidate                                         ? 1
                                                                                : 2;
            out.details[i].miss = kind;
            ++out.kinds[kind];
            ++out.total_misses;
            out.flags[i] = true;
        }
        int kind = instruction.kind == BRANCH ? 0 : 1;
        ++out.count[kind];
        out.wrong[kind] += out.flags[i];
        if (instruction.kind == BRANCH)
            direction_update(&direction, instruction.pc, instruction.taken);
        if (instruction.taken)
            btb_insert(&btb, instruction.pc, instruction.target);
    }
    free(btb.entries);
    direction_free(&direction);
    return out;
}
typedef struct {
    int first, last;
    char mark;
    int stage;
} CellSegment;
typedef struct {
    Lines lines;
    I occupancy[5][2], flushed, rows, stall_cells, flushed_cells, completed;
    int (*contents)[5];
} Diagram;
static void add_row(Diagram *diagram, Config config, int number, I pc, const char *kind,
                    const CellSegment *segments, int count, const char *annotation) {
    int width = config.end - config.start + 1;
    char cells[101];
    memset(cells, '.', (size_t)width);
    cells[width] = '\0';
    bool present = false;
    for (int i = 0; i < count; ++i) {
        CellSegment s = segments[i];
        if (s.last < s.first)
            continue;
        if (s.stage >= 0)
            diagram->occupancy[s.stage][number < 0] += s.last - s.first + 1;
        int first = s.first > config.start ? s.first : config.start,
            last = s.last < config.end ? s.last : config.end;
        for (int cycle = first; cycle <= last; ++cycle) {
            cells[cycle - config.start] = s.mark;
            present = true;
            diagram->stall_cells += s.mark == '*';
            diagram->flushed_cells += s.mark == 'x';
            if (s.stage >= 0)
                diagram->contents[cycle - config.start][s.stage] = number;
        }
    }
    if (present) {
        line(&diagram->lines, "%s", diagram_row(number, pc, kind, cells, annotation));
        ++diagram->rows;
    }
}
static Diagram diagram(const Instruction *instructions, int count, const Run *run, Variant variant,
                       const Prediction *prediction, Config config) {
    Diagram out = {0};
    int width = config.end - config.start + 1;
    out.contents = allocate((size_t)width, sizeof(*out.contents));
    line(&out.lines, "pipeline variant=%s predictor=%s cycles %d-%d", variant.name,
         config.primary_predictor, config.start, config.end);
    char *heading = cycle_heading(config.start, config.end);
    line(&out.lines, "%s", heading);
    free(heading);
    char **annotations = allocate((size_t)count, sizeof(char *));
    for (int i = 0; i < count; ++i)
        annotations[i] = "";
    for (int i = 0; i < run->count; ++i) {
        Record r = run->records[i];
        if (r.waiting >= 0)
            annotations[r.waiting] =
                joined(annotations[r.waiting], format(" %s %d", causes[r.cause], r.cycles));
    }
    for (int i = 0; i < count; ++i) {
        Timing t = run->timings[i];
        Instruction instruction = instructions[i];
        const char *annotation = annotations[i];
        if (prediction->flags[i])
            annotation =
                joined(annotation, format(" mispredict %s", misses[prediction->details[i].miss]));
        CellSegment correct[] = {{t.f, t.f, 'F', 0},     {t.f + 1, t.d - 1, '*', 0},
                                 {t.d, t.d, 'D', 1},     {t.d + 1, t.x - 1, '*', 1},
                                 {t.x, t.m - 1, 'X', 2}, {t.m, t.m, 'M', 3},
                                 {t.w, t.w, 'W', 4}};
        add_row(&out, config, i + 1, instruction.pc, classes[instruction.kind], correct, 7,
                annotation);
        out.completed += t.w >= config.start && t.w <= config.end;
        if (!prediction->flags[i])
            continue;
        bool early = id_resolved(instruction, variant);
        I pc = prediction->details[i].predicted;
        CellSegment first[] = {{t.d, t.d, 'F', 0},
                               {t.d + 1, t.x - 1, '*', 0},
                               {t.x, t.x, early ? 'x' : 'D', early ? -1 : 1},
                               {t.x + 1, t.x + 1, 'x', -1}};
        add_row(&out, config, -1, pc, "FLUSH", first, early ? 3 : 4, "");
        ++out.flushed;
        if (!early) {
            CellSegment second[] = {{t.x, t.x, 'F', 0}, {t.x + 1, t.x + 1, 'x', -1}};
            add_row(&out, config, -1, pc + 4, "FLUSH", second, 2, "");
            ++out.flushed;
        }
    }
    line(&out.lines, "rows %lld completed %lld stall_cells %lld flushed %lld", out.rows,
         out.completed, out.stall_cells, out.flushed_cells);
    line(&out.lines, "");
    line(&out.lines, "stages");
    line(&out.lines, "cycle IF ID EX MEM WB");
    for (int i = 0; i < width; ++i) {
        const char *content[5];
        for (int stage = 0; stage < 5; ++stage)
            content[stage] = out.contents[i][stage] == 0  ? "."
                             : out.contents[i][stage] < 0 ? "w"
                                                          : format("%d", out.contents[i][stage]);
        line(&out.lines, "%d %s %s %s %s %s", config.start + i, content[0], content[1], content[2],
             content[3], content[4]);
    }
    free(annotations);
    free(out.contents);
    out.contents = NULL;
    return out;
}
typedef struct {
    int variant, predictor, cycles;
    I stalls[4];
} Combination;
typedef struct {
    I producer, waiting, cycles, events;
    int cause, producer_kind, waiting_kind;
} Dependency;
typedef struct {
    I pc, cycles, instructions, instances;
} ProfileSegment;
typedef struct {
    I pc, total, stalls[4];
    int kind;
} Hotspot;
typedef struct {
    I target, count;
} Target;
static I sum4(const I *values) { return values[0] + values[1] + values[2] + values[3]; }
static int compare_i(const void *a, const void *b) {
    I x = *(const I *)a, y = *(const I *)b;
    return (x > y) - (x < y);
}
static int compare_static(const void *a, const void *b) {
    const StaticRef *x = a, *y = b;
    return (x->pc > y->pc) - (x->pc < y->pc);
}
static int compare_hotspot(const void *a, const void *b) {
    const Hotspot *x = a, *y = b;
    if (x->total != y->total)
        return x->total > y->total ? -1 : 1;
    return (x->pc > y->pc) - (x->pc < y->pc);
}
static int compare_dependency_key(const void *a, const void *b) {
    const Dependency *x = a, *y = b;
    if (x->producer != y->producer)
        return x->producer < y->producer ? -1 : 1;
    if (x->waiting != y->waiting)
        return x->waiting < y->waiting ? -1 : 1;
    return x->cause - y->cause;
}
static int compare_dependency(const void *a, const void *b) {
    const Dependency *x = a, *y = b;
    return x->cycles != y->cycles ? (x->cycles > y->cycles ? -1 : 1) : compare_dependency_key(a, b);
}
static int compare_segment(const void *a, const void *b) {
    const ProfileSegment *x = a, *y = b;
    if (x->cycles != y->cycles)
        return x->cycles > y->cycles ? -1 : 1;
    return (x->pc > y->pc) - (x->pc < y->pc);
}
static int compare_target(const void *a, const void *b) {
    const Target *x = a, *y = b;
    if (x->count != y->count)
        return x->count > y->count ? -1 : 1;
    return (x->target > y->target) - (x->target < y->target);
}
static const Config *sort_config;
static int compare_combination(const void *a, const void *b) {
    const Combination *x = a, *y = b;
    if (x->cycles != y->cycles)
        return x->cycles < y->cycles ? -1 : 1;
    int v = strcmp(sort_config->variants[x->variant].name, sort_config->variants[y->variant].name);
    return v ? v
             : strcmp(sort_config->predictors[x->predictor].name,
                      sort_config->predictors[y->predictor].name);
}
int main(void) {
    Input input = read_inputs();
    Config config = input.config;
    Trace trace = validate(input.trace);
    Instruction *instructions = trace.instructions;
    int n = trace.count;
    Sources *sources = dependencies(instructions, n);
    Prediction predictions[8] = {0};
    int primary_predictor = 0, primary_variant = 0;
    for (int p = 0; p < config.predictor_count; ++p) {
        predictions[p] = predict(instructions, n, config.predictors[p], config);
        if (strcmp(config.predictors[p].name, config.primary_predictor) == 0)
            primary_predictor = p;
    }
    for (int v = 0; v < config.variant_count; ++v)
        if (strcmp(config.variants[v].name, config.primary_variant) == 0)
            primary_variant = v;
    Combination combinations[64];
    int combination_count = 0, table[8][8] = {0};
    Run primary = {0};
    for (int v = 0; v < config.variant_count; ++v)
        for (int p = 0; p < config.predictor_count; ++p) {
            Run run = simulate(instructions, sources, n, config.variants[v], predictions[p].flags);
            table[v][p] = run.cycles;
            Combination *pair = &combinations[combination_count++];
            pair->variant = v;
            pair->predictor = p;
            pair->cycles = run.cycles;
            memcpy(pair->stalls, run.stalls, sizeof(pair->stalls));
            if (v == primary_variant && p == primary_predictor)
                primary = run;
            else
                free_run(&run);
        }
    Variant variant = config.variants[primary_variant];
    Prediction prediction = predictions[primary_predictor];
    int cycles = primary.cycles;
    Diagram picture = diagram(instructions, n, &primary, variant, &prediction, config);
    save("pipeline.txt", picture.lines);
    I mix[7] = {0}, class_stalls[7] = {0}, distances[5] = {0}, lengths[5] = {0}, paths[3] = {0};
    I taken = 0, backward = 0, indirect = 0, link = 0, operands = 0, produced = 0, height = 0;
    I *addresses = allocate((size_t)n, sizeof(I));
    int address_count = 0;
    I *finish = allocate((size_t)n, sizeof(I));
    for (int i = 0; i < n; ++i) {
        Instruction r = instructions[i];
        ++mix[r.kind];
        if (r.kind == BRANCH) {
            taken += r.taken;
            backward += r.target < r.pc;
        }
        if (r.kind == JUMP) {
            indirect += r.rs1 >= 0;
            link += r.rd >= 0;
        }
        if (r.kind == LOAD || r.kind == STORE)
            addresses[address_count++] = r.address;
        int registers[2] = {r.rs1, r.rs2};
        I start = 0;
        for (int j = 0; j < 2; ++j)
            if (registers[j] > 0) {
                ++operands;
                int p = sources[i].producer[j];
                if (p >= 0) {
                    ++produced;
                    int distance = i - p;
                    ++distances[(distance > 5 ? 5 : distance) - 1];
                    if (finish[p] > start)
                        start = finish[p];
                }
                ++paths[forwarding_path(r, p < 0 ? NULL : &primary.timings[p], primary.timings[i],
                                        variant)];
            }
        finish[i] = start + (r.kind == LOAD ? 2 : r.kind == MUL ? variant.latency : 1);
        if (finish[i] > height)
            height = finish[i];
        if (i) {
            int delay = primary.timings[i].x - primary.timings[i - 1].x - 1;
            if (delay > 0)
                ++lengths[(delay > 5 ? 5 : delay) - 1];
        }
    }
    qsort(addresses, (size_t)address_count, sizeof(I), compare_i);
    int distinct_addresses = 0;
    for (int i = 0; i < address_count; ++i)
        if (i == 0 || addresses[i] != addresses[i - 1])
            ++distinct_addresses;
    Dependency *deps = allocate((size_t)primary.count, sizeof(Dependency));
    int dependency_count = 0;
    for (int i = 0; i < primary.count; ++i) {
        Record r = primary.records[i];
        Instruction responsible = instructions[r.responsible];
        class_stalls[responsible.kind] += r.cycles;
        trace.statics[responsible.static_id].stalls[r.cause] += r.cycles;
        if (r.cause >= 2) {
            Instruction producer = instructions[r.producer], waiting = instructions[r.waiting];
            deps[dependency_count++] = (Dependency){producer.pc, waiting.pc,    r.cycles,    1,
                                                    r.cause,     producer.kind, waiting.kind};
        }
    }
    qsort(deps, (size_t)dependency_count, sizeof(Dependency), compare_dependency_key);
    int grouped = 0;
    for (int i = 0; i < dependency_count; ++i) {
        if (grouped && compare_dependency_key(&deps[grouped - 1], &deps[i]) == 0) {
            deps[grouped - 1].cycles += deps[i].cycles;
            deps[grouped - 1].events += deps[i].events;
        } else
            deps[grouped++] = deps[i];
    }
    dependency_count = grouped;
    qsort(deps, (size_t)dependency_count, sizeof(Dependency), compare_dependency);
    StaticRef *statics = allocate((size_t)trace.static_count, sizeof(StaticRef));
    Hotspot *hotspots = allocate((size_t)trace.static_count, sizeof(Hotspot));
    int hotspot_count = 0, static_branches = 0, static_jumps = 0;
    for (int i = 0; i < trace.static_count; ++i) {
        Instruction r = instructions[trace.statics[i].first];
        statics[i] = (StaticRef){r.pc, i};
        static_branches += r.kind == BRANCH;
        static_jumps += r.kind == JUMP;
        I total = sum4(trace.statics[i].stalls);
        if (total) {
            Hotspot *h = &hotspots[hotspot_count++];
            h->pc = r.pc;
            h->total = total;
            h->kind = r.kind;
            memcpy(h->stalls, trace.statics[i].stalls, sizeof(h->stalls));
        }
    }
    qsort(statics, (size_t)trace.static_count, sizeof(StaticRef), compare_static);
    qsort(hotspots, (size_t)hotspot_count, sizeof(Hotspot), compare_hotspot);
    Lines stats = {0};
    line(&stats, "input lines %d accepted %d rejected %d gaps %d", input.trace.count, n,
         trace.rejected_count, trace.gap_count);
    for (int i = 0; i < trace.rejected_count; ++i)
        line(&stats, "reject line %d %s", trace.rejected[i].line, trace.rejected[i].reason);
    for (int i = 0; i < trace.gap_count; ++i) {
        Gap g = trace.gaps[i];
        line(&stats, "gap line %d expected %s found %s", g.line, hexadecimal(g.expected),
             hexadecimal(g.found));
    }
    line(&stats, "");
    line(&stats, "trace");
    line(&stats, "instructions %d", n);
    line(&stats, "static_instructions %d", trace.static_count);
    char *mix_line = "mix";
    for (int i = 0; i < 7; ++i)
        mix_line = joined(mix_line, format(" %s %lld", classes[i], mix[i]));
    line(&stats, "%s", mix_line);
    line(&stats, "branches %lld taken %lld backward %lld", mix[BRANCH], taken, backward);
    line(&stats, "jumps %lld indirect %lld link %lld", mix[JUMP], indirect, link);
    line(&stats, "static_control branches %d jumps %d", static_branches, static_jumps);
    line(&stats, "memory loads %lld stores %lld distinct_addresses %d", mix[LOAD], mix[STORE],
         distinct_addresses);
    line(&stats, "operands %lld with_producer %lld distance 1 %lld 2 %lld 3 %lld 4 %lld 5+ %lld",
         operands, produced, distances[0], distances[1], distances[2], distances[3], distances[4]);
    line(&stats, "");
    line(&stats, "prediction");
    for (int p = 0; p < config.predictor_count; ++p) {
        Prediction r = predictions[p];
        Predictor d = config.predictors[p];
        line(
            &stats,
            "%s %s bits %d control %lld mispredicted %lld accuracy %s branches %s jumps %s direction %lld btb_miss %lld wrong_target %lld",
            d.name, d.scheme, r.bits, r.control, r.total_misses,
            percentage(r.control - r.total_misses, r.control),
            percentage(r.count[0] - r.wrong[0], r.count[0]),
            percentage(r.count[1] - r.wrong[1], r.count[1]), r.kinds[0], r.kinds[1], r.kinds[2]);
    }
    line(&stats, "btb entries %d lookups %lld hits %lld misses %lld", config.btb,
         prediction.control, prediction.hits, prediction.control - prediction.hits);
    line(&stats, "ras depth %d calls %lld returns %lld predicted %lld correct %lld", config.ras,
         prediction.calls, prediction.returns, prediction.ras_predictions, prediction.ras_correct);
    line(&stats, "");
    line(&stats, "timing variant=%s predictor=%s", variant.name, config.primary_predictor);
    line(&stats, "forwarding %s branch_stage %s mul_latency %d", variant.forwarding ? "on" : "off",
         variant.id ? "ID" : "EX", variant.latency);
    line(&stats, "cycles %d", cycles);
    line(&stats, "cpi %s %s", fraction(cycles, n), decimal(cycles, n));
    line(&stats, "ipc %s", decimal(n, cycles));
    I total_stalls = sum4(primary.stalls);
    line(&stats, "stall_cycles total %lld control %lld structural %lld load_use %lld raw %lld",
         total_stalls, primary.stalls[0], primary.stalls[1], primary.stalls[2], primary.stalls[3]);
    line(&stats, "stall_events control %lld structural %lld load_use %lld raw %lld",
         primary.events[0], primary.events[1], primary.events[2], primary.events[3]);
    line(&stats, "flushed %lld", picture.flushed);
    line(&stats, "cycle_check %d + 4 + %lld = %lld", n, total_stalls, n + 4 + total_stalls);
    line(&stats, "cpi_stack base 1.0000 fill %s control %s structural %s load_use %s raw %s",
         decimal(4, n), decimal(primary.stalls[0], n), decimal(primary.stalls[1], n),
         decimal(primary.stalls[2], n), decimal(primary.stalls[3], n));
    line(&stats, "stall_lengths 1 %lld 2 %lld 3 %lld 4 %lld 5+ %lld", lengths[0], lengths[1],
         lengths[2], lengths[3], lengths[4]);
    line(&stats, "dataflow height %lld ilp %s", height, decimal(n, height));
    line(&stats, "");
    line(&stats, "whatif");
    bool *perfect = allocate((size_t)n, sizeof(bool));
    for (int change = 0; change < 4; ++change) {
        Variant modified = variant;
        const char *name;
        const bool *flags = prediction.flags;
        if (change == 0) {
            name = "perfect_prediction";
            flags = perfect;
        } else if (change == 1) {
            name = "single_cycle_mul";
            modified.latency = 1;
        } else if (change == 2) {
            name = variant.forwarding ? "forwarding_off" : "forwarding_on";
            modified.forwarding = !variant.forwarding;
        } else {
            name = variant.id ? "branch_stage_EX" : "branch_stage_ID";
            modified.id = !variant.id;
        }
        Run run = simulate(instructions, sources, n, modified, flags);
        line(&stats, "%s cycles %d saved %d speedup %s", name, run.cycles, cycles - run.cycles,
             decimal(cycles, run.cycles));
        free_run(&run);
    }
    line(&stats, "");
    line(&stats, "classes");
    for (int i = 0; i < 7; ++i)
        line(&stats, "%s count %lld stall_cycles %lld per_instruction %s", classes[i], mix[i],
             class_stalls[i], mix[i] ? decimal(class_stalls[i], mix[i]) : "-");
    line(&stats, "");
    line(&stats, "forwarding regfile %lld ex_mem %lld mem_wb %lld", paths[0], paths[1], paths[2]);
    line(&stats, "");
    line(&stats, "occupancy cycles %d", cycles);
    for (int i = 0; i < 5; ++i) {
        I a = picture.occupancy[i][0], b = picture.occupancy[i][1];
        line(&stats, "%s correct %lld wrong %lld idle %lld busy %s", stages[i], a, b,
             cycles - a - b, percentage(a + b, cycles));
    }
    line(&stats, "");
    line(&stats, "hotspots");
    for (int i = 0; i < hotspot_count && i < config.top; ++i) {
        Hotspot h = hotspots[i];
        line(&stats,
             "%d %s %s stall_cycles %lld control %lld structural %lld load_use %lld raw %lld",
             i + 1, hexadecimal(h.pc), classes[h.kind], h.total, h.stalls[0], h.stalls[1],
             h.stalls[2], h.stalls[3]);
    }
    line(&stats, "");
    line(&stats, "dependencies total %d", dependency_count);
    for (int i = 0; i < dependency_count && i < config.top; ++i) {
        Dependency d = deps[i];
        line(&stats, "%d %s %s -> %s %s %s stall_cycles %lld events %lld", i + 1,
             hexadecimal(d.producer), classes[d.producer_kind], hexadecimal(d.waiting),
             classes[d.waiting_kind], causes[d.cause], d.cycles, d.events);
    }
    line(&stats, "");
    line(&stats, "intervals size %d", config.interval);
    for (int a = 0; a < n; a += config.interval) {
        int b = a + config.interval < n ? a + config.interval - 1 : n - 1;
        int count = primary.timings[b].w - (a ? primary.timings[a - 1].w : 0);
        line(&stats, "%d-%d cycles %d cpi %s", a + 1, b + 1, count, decimal(count, b - a + 1));
    }
    line(&stats, "");
    char *heading = "cycles_table";
    for (int p = 0; p < config.predictor_count; ++p)
        heading = joined(heading, format(" %s", config.predictors[p].name));
    line(&stats, "%s", heading);
    for (int v = 0; v < config.variant_count; ++v) {
        char *row = config.variants[v].name;
        for (int p = 0; p < config.predictor_count; ++p)
            row = joined(row, format(" %d", table[v][p]));
        line(&stats, "%s", row);
    }
    save("stats.txt", stats);
    Lines branches = {0};
    line(&branches, "predictor,pc,class,executions,taken,mispredictions,accuracy");
    for (int p = 0; p < config.predictor_count; ++p)
        for (int s = 0; s < trace.static_count; ++s) {
            Static group = trace.statics[statics[s].id];
            Instruction r = instructions[group.first];
            if (!control(r))
                continue;
            I wrong = 0;
            for (int i = group.first; i >= 0; i = trace.next_static[i])
                wrong += predictions[p].flags[i];
            line(&branches, "%s,%s,%s,%lld,%lld,%lld,%s", config.predictors[p].name,
                 hexadecimal(r.pc), classes[r.kind], group.count, group.taken, wrong,
                 percentage(group.count - wrong, group.count));
        }
    save("branches.csv", branches);
    sort_config = &config;
    qsort(combinations, (size_t)combination_count, sizeof(Combination), compare_combination);
    Lines comparison = {0};
    line(
        &comparison,
        "rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw");
    for (int i = 0; i < combination_count; ++i) {
        Combination r = combinations[i];
        Prediction p = predictions[r.predictor];
        line(&comparison, "%d,%s,%s,%d,%s,%s,%s,%lld,%lld,%lld,%lld,%lld", i + 1,
             config.variants[r.variant].name, config.predictors[r.predictor].name, r.cycles,
             decimal(r.cycles, n), decimal(cycles, r.cycles),
             percentage(p.control - p.total_misses, p.control), p.total_misses, r.stalls[0],
             r.stalls[1], r.stalls[2], r.stalls[3]);
    }
    save("comparison.csv", comparison);
    Lines profile = {0};
    line(&profile, "branches");
    for (int s = 0; s < trace.static_count; ++s) {
        Static group = trace.statics[statics[s].id];
        Instruction r = instructions[group.first];
        if (r.kind != BRANCH)
            continue;
        I transitions = 0, run_length = 0, longest[2] = {0};
        bool previous = false;
        for (int i = group.first; i >= 0; i = trace.next_static[i]) {
            bool value = instructions[i].taken;
            if (run_length && value != previous) {
                ++transitions;
                run_length = 0;
            }
            ++run_length;
            if (run_length > longest[value])
                longest[value] = run_length;
            previous = value;
        }
        I best_misses = group.count + 1;
        int best = 0;
        for (int p = 0; p < config.predictor_count; ++p)
            if (strcmp(config.predictors[p].scheme, "PERFECT")) {
                I wrong = 0;
                for (int i = group.first; i >= 0; i = trace.next_static[i])
                    wrong += predictions[p].flags[i];
                if (wrong < best_misses) {
                    best_misses = wrong;
                    best = p;
                }
            }
        line(
            &profile,
            "%s %s executions %lld taken %lld transitions %lld longest_taken %lld longest_not_taken %lld best %s %lld",
            hexadecimal(r.pc), r.target < r.pc ? "backward" : "forward", group.count, group.taken,
            transitions, longest[1], longest[0], config.predictors[best].name, best_misses);
    }
    line(&profile, "");
    line(&profile, "loops");
    for (int s = 0; s < trace.static_count; ++s) {
        Static group = trace.statics[statics[s].id];
        Instruction r = instructions[group.first];
        if (r.kind != BRANCH || r.target >= r.pc)
            continue;
        I entries = 0, longest = 0, length = 0;
        for (int i = group.first; i >= 0; i = trace.next_static[i]) {
            ++length;
            if (!instructions[i].taken) {
                ++entries;
                if (length > longest)
                    longest = length;
                length = 0;
            }
        }
        if (length) {
            ++entries;
            if (length > longest)
                longest = length;
        }
        line(&profile, "%s-%s body %lld entries %lld iterations %lld avg_trip %s max_trip %lld",
             hexadecimal(r.target), hexadecimal(r.pc), (r.pc - r.target) / 4 + 1, entries,
             group.count, decimal(group.count, entries), longest);
    }
    ProfileSegment *segments = allocate((size_t)trace.static_count, sizeof(ProfileSegment));
    for (int a = 0; a < n;) {
        int b = a;
        while (b < n - 1 && !control(instructions[b]))
            ++b;
        ProfileSegment *group = &segments[instructions[a].static_id];
        group->pc = instructions[a].pc;
        ++group->instances;
        group->instructions += b - a + 1;
        group->cycles += primary.timings[b].w - (a ? primary.timings[a - 1].w : 0);
        a = b + 1;
    }
    int segment_count = 0;
    for (int i = 0; i < trace.static_count; ++i)
        if (segments[i].instances)
            segments[segment_count++] = segments[i];
    qsort(segments, (size_t)segment_count, sizeof(ProfileSegment), compare_segment);
    line(&profile, "");
    line(&profile, "segments total %d", segment_count);
    for (int i = 0; i < segment_count && i < config.top; ++i) {
        ProfileSegment r = segments[i];
        line(&profile, "%d %s instances %lld instructions %lld cycles %lld cpi %s", i + 1,
             hexadecimal(r.pc), r.instances, r.instructions, r.cycles,
             decimal(r.cycles, r.instructions));
    }
    line(&profile, "");
    line(&profile, "indirect");
    I *target_values = allocate((size_t)n, sizeof(I));
    Target *targets = allocate((size_t)n, sizeof(Target));
    for (int s = 0; s < trace.static_count; ++s) {
        Static group = trace.statics[statics[s].id];
        Instruction r = instructions[group.first];
        if (r.kind != JUMP || r.rs1 < 0)
            continue;
        int count = 0;
        for (int i = group.first; i >= 0; i = trace.next_static[i])
            target_values[count++] = instructions[i].target;
        qsort(target_values, (size_t)count, sizeof(I), compare_i);
        int distinct = 0;
        for (int i = 0; i < count; ++i) {
            if (i == 0 || target_values[i] != target_values[i - 1])
                targets[distinct++] = (Target){target_values[i], 1};
            else
                ++targets[distinct - 1].count;
        }
        qsort(targets, (size_t)distinct, sizeof(Target), compare_target);
        char *tail = "";
        for (int i = 0; i < distinct; ++i)
            tail =
                joined(tail, format(" %s:%lld", hexadecimal(targets[i].target), targets[i].count));
        line(&profile, "%s executions %lld distinct %d targets%s", hexadecimal(r.pc), group.count,
             distinct, tail);
    }
    line(&profile, "");
    line(&profile, "instructions");
    for (int s = 0; s < trace.static_count; ++s) {
        Static group = trace.statics[statics[s].id];
        Instruction r = instructions[group.first];
        line(&profile, "%s %s %s %s %s executions %lld stall_cycles %lld", hexadecimal(r.pc),
             classes[r.kind], register_name(r.rd), register_name(r.rs1), register_name(r.rs2),
             group.count, sum4(group.stalls));
    }
    save("profile.txt", profile);
    for (int p = 0; p < config.predictor_count; ++p) {
        free(predictions[p].details);
        free(predictions[p].flags);
    }
    free(input.trace.data);
    free(trace.instructions);
    free(trace.statics);
    free(trace.next_static);
    free(trace.hash);
    free(trace.rejected);
    free(trace.gaps);
    free(sources);
    free_run(&primary);
    free(picture.lines.data);
    free(stats.data);
    free(branches.data);
    free(comparison.data);
    free(profile.data);
    free(addresses);
    free(finish);
    free(perfect);
    free(deps);
    free(statics);
    free(hotspots);
    free(segments);
    free(target_values);
    free(targets);
    return 0;
}
