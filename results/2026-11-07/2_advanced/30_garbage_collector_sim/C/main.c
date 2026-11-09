#include "collector.h"
static void reachable(const Heap *heap, bool *marks) {
    memset(marks, 0, 5000 * sizeof(bool));
    int stack[5000], depth = 0;
    for (int i = 0; i < heap->root_count; ++i) {
        int id = heap->roots[i];
        if (id && !marks[id - 1]) {
            marks[id - 1] = true;
            stack[depth++] = id;
        }
    }
    while (depth) {
        Object object = heap->objects[stack[--depth] - 1];
        for (int f = 0; f < object.p; ++f) {
            int value = object.fields[f];
            if (value && !marks[value - 1]) {
                marks[value - 1] = true;
                stack[depth++] = value;
            }
        }
    }
}
static Pair amount(const Heap *heap, const bool *ids) {
    Pair pair = {0};
    for (int i = 0; i < heap->count; ++i)
        if (ids[i])
            add_object(&pair, object_size(heap->objects[i]));
    return pair;
}
static int slot_value(const Heap *heap, int index) {
    return index < 0 ? 0 : heap->roots[index];
}
static void execute_plain(Heap *heap, Command command) {
    int *a = command.args;
    switch (command.kind) {
    case ALLOC: {
        int id = heap->count + 1;
        heap->objects[heap->count++] = (Object){.id = id, .p = a[0], .d = a[1], .present = true};
        heap->roots[heap->root_count++] = id;
        break;
    }
    case PUSH:
        heap->roots[heap->root_count++] = slot_value(heap, a[0]);
        break;
    case LOAD:
        heap->roots[heap->root_count++] = heap->objects[heap->roots[a[0]] - 1].fields[a[1]];
        break;
    case POP:
        heap->root_count -= a[0];
        break;
    case SET:
        heap->objects[heap->roots[a[0]] - 1].fields[a[1]] = slot_value(heap, a[2]);
        break;
    case OVERWRITE:
        heap->roots[a[0]] = slot_value(heap, a[1]);
        break;
    case CHECKPOINT:
        break;
    }
}
typedef struct {
    char label[17];
    int line, roots;
    Pair live, allocated, phase, survivors;
} Checkpoint;
typedef struct {
    Heap *heap;
    Script commands, errors;
    int death[5000], lifetime[5000], birth[5000], counts[7], line_count, peak_line;
    Pair allocated, peak, ending;
    Checkpoint *checkpoints;
    int checkpoint_count;
} Reference;
static Reference *analyze_script(Script source) {
    Reference *reference = calloc(1, sizeof *reference);
    reference->heap = calloc(1, sizeof *reference->heap);
    reference->commands.items = malloc(5000 * sizeof(Command));
    reference->errors.items = malloc(5000 * sizeof(Command));
    reference->checkpoints = malloc(5000 * sizeof(Checkpoint));
    reference->line_count = source.count;
    Heap *heap = reference->heap;
    int phase_first = 1;
    Pair phase = {0};
    for (int c = 0; c < source.count; ++c) {
        Command command = source.items[c];
        int roots = heap->root_count, kind = command.kind, *a = command.args;
        if (!command.error) {
            bool invalid = ((kind == ALLOC || kind == PUSH || kind == LOAD) && roots == 64) ||
                           (kind == POP && a[0] > roots);
            if (kind == LOAD || kind == SET || kind == OVERWRITE)
                invalid = invalid || a[0] >= roots;
            int r = kind == PUSH ? a[0] : kind == SET ? a[2] : kind == OVERWRITE ? a[1] : -1;
            if (r >= roots)
                invalid = true;
            if (invalid)
                command.error = "stack";
            else if ((kind == LOAD || kind == SET) && !heap->roots[a[0]])
                command.error = "null";
            else if ((kind == LOAD || kind == SET) && a[1] >= heap->objects[heap->roots[a[0]] - 1].p)
                command.error = "field";
            else if (kind == CHECKPOINT)
                for (int i = 0; i < reference->checkpoint_count; ++i)
                    if (!strcmp(reference->checkpoints[i].label, command.label)) {
                        command.error = "duplicate";
                        break;
                    }
        }
        if (command.error) {
            reference->errors.items[reference->errors.count++] = command;
            continue;
        }
        if (kind == ALLOC) {
            command.object = heap->count + 1;
            reference->birth[heap->count] = (int)reference->allocated.words;
            add_object(&reference->allocated, 1 + a[0] + a[1]);
            add_object(&phase, 1 + a[0] + a[1]);
        }
        if (kind == CHECKPOINT)
            command.checkpoint = reference->checkpoint_count;
        execute_plain(heap, command);
        reference->commands.items[reference->commands.count++] = command;
        ++reference->counts[kind];
        bool live[5000];
        reachable(heap, live);
        reference->ending = amount(heap, live);
        for (int i = 0; i < heap->count; ++i)
            if (!reference->death[i] && !live[i]) {
                reference->death[i] = command.line;
                reference->lifetime[i] =
                    (int)reference->allocated.words - reference->birth[i] - object_size(heap->objects[i]);
            }
        if (reference->ending.words > reference->peak.words) {
            reference->peak = reference->ending;
            reference->peak_line = command.line;
        }
        if (kind == CHECKPOINT) {
            Pair survivors = {0};
            for (int i = phase_first - 1; i < heap->count; ++i)
                if (live[i])
                    add_object(&survivors, object_size(heap->objects[i]));
            Checkpoint *checkpoint = &reference->checkpoints[reference->checkpoint_count++];
            *checkpoint = (Checkpoint){.line = command.line,
                                       .roots = heap->root_count,
                                       .live = reference->ending,
                                       .allocated = reference->allocated,
                                       .phase = phase,
                                       .survivors = survivors};
            strcpy(checkpoint->label, command.label);
            phase = (Pair){0};
            phase_first = heap->count + 1;
        }
    }
    return reference;
}
static Lines reference_report(const Reference *reference) {
    Lines lines = {0};
    add_line(&lines, "script lines %d valid %d errors %d", reference->line_count, reference->commands.count,
             reference->errors.count);
    for (int i = 0; i < reference->errors.count; ++i)
        add_line(&lines, "error line %d %s", reference->errors.items[i].line,
                 reference->errors.items[i].error);
    char *commands = format("commands");
    for (int k = 0; k < 7; ++k)
        append_text(&commands, " %s %d", kind_name(k), reference->counts[k]);
    add_line(&lines, "%s", commands);
    free(commands);
    int sizes[5000];
    for (int i = 0; i < reference->heap->count; ++i)
        sizes[i] = object_size(reference->heap->objects[i]);
    add_line(&lines, "allocated objects %" PRId64 " words %" PRId64 " sizes %s", reference->allocated.count,
             reference->allocated.words, class_table(sizes, reference->heap->count));
    add_line(&lines, "peak_live objects %" PRId64 " words %" PRId64 " line %d", reference->peak.count,
             reference->peak.words, reference->peak_line);
    add_line(&lines, "end_live objects %" PRId64 " words %" PRId64 " stack %d", reference->ending.count,
             reference->ending.words, reference->heap->root_count);
    int lifetimes[6] = {0};
    for (int i = 0; i < reference->heap->count; ++i) {
        int value = reference->lifetime[i];
        ++lifetimes[!reference->death[i] ? 5
                    : value < 64         ? 0
                    : value < 256        ? 1
                    : value < 1024       ? 2
                    : value < 4096       ? 3
                                         : 4];
    }
    add_line(&lines, "lifetimes 0-63 %d 64-255 %d 256-1023 %d 1024-4095 %d 4096+ %d live %d", lifetimes[0],
             lifetimes[1], lifetimes[2], lifetimes[3], lifetimes[4], lifetimes[5]);
    for (int i = 0; i < reference->checkpoint_count; ++i) {
        Checkpoint c = reference->checkpoints[i];
        add_line(&lines,
                 "checkpoint %s line %d stack %d live %" PRId64 " %" PRId64 " allocated %" PRId64 " %" PRId64
                 " phase %" PRId64 " %" PRId64 " survivors %" PRId64 " %" PRId64 " survival %s",
                 c.label, c.line, c.roots, c.live.count, c.live.words, c.allocated.count, c.allocated.words,
                 c.phase.count, c.phase.words, c.survivors.count, c.survivors.words,
                 pct(c.survivors.words, c.phase.words));
    }
    return lines;
}
typedef struct {
    int line;
    Integer work;
    Pair freed;
    bool collection;
} Pause;
typedef struct {
    Integer work, freed, maximum;
    char *p50, *p90;
} PauseStats;
static int integer_compare(const void *a, const void *b) {
    Integer x = *(const Integer *)a, y = *(const Integer *)b;
    return (x > y) - (x < y);
}
static PauseStats pause_stats(const Pause *pauses, int count) {
    PauseStats stats = {.p50 = "-", .p90 = "-"};
    Integer *values = malloc((size_t)count * sizeof *values);
    for (int i = 0; i < count; ++i) {
        Pause pause = pauses[i];
        stats.work += pause.work;
        stats.freed += pause.freed.words;
        if (pause.work > stats.maximum)
            stats.maximum = pause.work;
        values[i] = pause.work;
    }
    if (count) {
        qsort(values, (size_t)count, sizeof *values, integer_compare);
        stats.p50 = format("%" PRId64, values[(50 * count + 99) / 100 - 1]);
        stats.p90 = format("%" PRId64, values[(90 * count + 99) / 100 - 1]);
    }
    free(values);
    return stats;
}
typedef struct {
    Integer end, mutator;
    bool active;
} Segment;
typedef struct {
    Segment *segments;
    int count, capacity;
    Integer total, mutator;
} Timeline;
static void timeline_add(Timeline *timeline, bool active, Integer length) {
    if (!length)
        return;
    timeline->total += length;
    if (active)
        timeline->mutator += length;
    Segment segment = {timeline->total, timeline->mutator, active};
    if (timeline->count && timeline->segments[timeline->count - 1].active == active)
        timeline->segments[timeline->count - 1] = segment;
    else {
        if (timeline->count == timeline->capacity) {
            timeline->capacity = timeline->capacity ? timeline->capacity * 2 : 16;
            timeline->segments =
                realloc(timeline->segments, (size_t)timeline->capacity * sizeof *timeline->segments);
        }
        timeline->segments[timeline->count++] = segment;
    }
}
static Integer timeline_prefix(const Timeline *timeline, Integer time) {
    if (time <= 0)
        return 0;
    int first = 0, end = timeline->count;
    while (first < end) {
        int middle = first + (end - first) / 2;
        if (timeline->segments[middle].end < time)
            first = middle + 1;
        else
            end = middle;
    }
    Integer before = first ? timeline->segments[first - 1].mutator : 0,
            start = first ? timeline->segments[first - 1].end : 0;
    return before + (timeline->segments[first].active ? time - start : 0);
}
static void evaluate_window(const Timeline *timeline, Integer start, int width, Integer *best) {
    if (start < 0 || start + width > timeline->total)
        return;
    Integer value = timeline_prefix(timeline, start + width) - timeline_prefix(timeline, start);
    if (value < *best)
        *best = value;
}
static char *mmu(const Timeline *timeline, int width) {
    if (width > timeline->total)
        return "-";
    Integer best = width;
    evaluate_window(timeline, 0, width, &best);
    evaluate_window(timeline, timeline->total - width, width, &best);
    for (int i = 0; i < timeline->count; ++i) {
        evaluate_window(timeline, timeline->segments[i].end, width, &best);
        evaluate_window(timeline, timeline->segments[i].end - width, width, &best);
    }
    return pct(best, width);
}
typedef struct {
    Pair freed;
    Integer work;
    int line;
} Cascade;
typedef struct {
    const Config *config;
    const Reference *reference;
    Heap *heap;
    Collection *collections;
    int collection_count;
    Pause *pauses;
    int pause_count;
    Timeline timeline;
    Lines leaks, *observations;
    Integer increments, decrements;
    Cascade *cascades;
    int cascade_count, peak_used, oom_line, oom_size;
} Run;
static void retain(Run *run, int id) {
    if (id) {
        ++run->heap->objects[id - 1].references;
        ++run->increments;
    }
}
static void release(Run *run, int id, Cascade *cascade) {
    int *stack = malloc(30001 * sizeof *stack);
    int depth = 0;
    if (id)
        stack[depth++] = id;
    while (depth) {
        int current = stack[--depth];
        Object *object = &run->heap->objects[current - 1];
        ++run->decrements;
        if (--object->references)
            continue;
        object->present = false;
        add_object(&cascade->freed, object_size(*object));
        cascade->work += 1 + object->p;
        for (int f = object->p - 1; f >= 0; --f)
            if (object->fields[f])
                stack[depth++] = object->fields[f];
    }
    free(stack);
}
typedef struct {
    const Heap *heap;
    const bool *garbage;
    int parent[5000], index[5000], low[5000], stack[5000], next, depth;
    bool active[5000], cyclic[5000];
} LeakContext;
static int component_find(LeakContext *context, int id) {
    int root = id;
    while (context->parent[root] != root)
        root = context->parent[root];
    while (context->parent[id] != id) {
        int next = context->parent[id];
        context->parent[id] = root;
        id = next;
    }
    return root;
}
static void cycle_visit(LeakContext *context, int id) {
    context->index[id] = context->low[id] = context->next++;
    context->stack[context->depth++] = id;
    context->active[id] = true;
    Object object = context->heap->objects[id];
    for (int f = 0; f < object.p; ++f) {
        int target = object.fields[f] - 1;
        if (target < 0 || !context->garbage[target])
            continue;
        if (context->index[target] < 0) {
            cycle_visit(context, target);
            if (context->low[target] < context->low[id])
                context->low[id] = context->low[target];
        } else if (context->active[target] && context->index[target] < context->low[id])
            context->low[id] = context->index[target];
    }
    if (context->low[id] != context->index[id])
        return;
    int first = context->depth - 1;
    while (context->stack[first] != id)
        --first;
    bool cycle = context->depth - first > 1;
    if (!cycle)
        for (int f = 0; f < object.p; ++f)
            if (object.fields[f] == id + 1)
                cycle = true;
    while (context->depth > first) {
        int value = context->stack[--context->depth];
        context->active[value] = false;
        context->cyclic[value] = cycle;
    }
}
static Lines leak_report(const Run *run, const char *title, const bool *garbage) {
    Heap *heap = run->heap;
    LeakContext *context = calloc(1, sizeof *context);
    context->heap = heap;
    context->garbage = garbage;
    for (int i = 0; i < heap->count; ++i) {
        context->parent[i] = i;
        context->index[i] = -1;
    }
    for (int i = 0; i < heap->count; ++i)
        if (garbage[i])
            for (int f = 0; f < heap->objects[i].p; ++f) {
                int target = heap->objects[i].fields[f] - 1;
                if (target >= 0 && garbage[target])
                    context->parent[component_find(context, i)] = component_find(context, target);
            }
    for (int i = 0; i < heap->count; ++i)
        if (garbage[i] && context->index[i] < 0)
            cycle_visit(context, i);
    bool seen[5000] = {0};
    int groups[5000], group_count = 0;
    for (int i = 0; i < heap->count; ++i)
        if (garbage[i]) {
            int root = component_find(context, i);
            if (!seen[root]) {
                seen[root] = true;
                groups[group_count++] = root;
            }
        }
    Pair all = amount(heap, garbage);
    Lines lines = {0};
    add_line(&lines, "%s groups %d objects %" PRId64 " words %" PRId64, title, group_count, all.count,
             all.words);
    for (int group = 0; group < group_count; ++group) {
        Pair pair = {0};
        int died = 0, cycles = 0;
        char *ids = NULL;
        for (int i = 0; i < heap->count; ++i)
            if (garbage[i] && component_find(context, i) == groups[group]) {
                add_object(&pair, object_size(heap->objects[i]));
                if (run->reference->death[i] > died)
                    died = run->reference->death[i];
                if (context->cyclic[i])
                    ++cycles;
                append_text(&ids, " %d%s", i + 1, context->cyclic[i] ? "*" : "");
            }
        add_line(&lines, "group %d objects %" PRId64 " words %" PRId64 " cycle %d died %d ids%s", group + 1,
                 pair.count, pair.words, cycles, died, ids);
        free(ids);
    }
    free(context);
    return lines;
}
static void garbage_set(const Heap *heap, const bool *live, bool *garbage) {
    for (int i = 0; i < heap->count; ++i)
        garbage[i] = heap->objects[i].present && !live[i];
}
static bool collect(Run *run, const char *kind, int line, int request) {
    Heap *heap = run->heap;
    Collection record = {.number = run->collection_count + 1, .line = line, .request = request, .kind = kind};
    free_amount(heap, &record.before_total, &record.before_largest);
    bool complete = true;
    if (!strcmp(kind, "sweep"))
        collect_sweep(heap, &record);
    else if (!strcmp(kind, "compact"))
        collect_compact(heap, &record);
    else if (!strcmp(kind, "copy"))
        collect_copy(heap, &record);
    else if (!strcmp(kind, "backup")) {
        marking(heap, &record);
        bool garbage[5000] = {0};
        for (int i = 0; i < heap->count; ++i)
            garbage[i] = heap->objects[i].present && !heap->objects[i].marked;
        Lines report = leak_report(run, format("backup %d line %d", record.number, line), garbage);
        extend_lines(&run->leaks, &report);
        sweeping(heap, &record, false);
        for (int i = 0; i < heap->count; ++i)
            if (garbage[i])
                for (int f = 0; f < heap->objects[i].p; ++f) {
                    int value = heap->objects[i].fields[f];
                    if (value && heap->objects[value - 1].marked) {
                        --heap->objects[value - 1].references;
                        ++run->decrements;
                    }
                }
    } else
        complete = collect_generational(heap, &record);
    if (!complete)
        return false;
    free_amount(heap, &record.after_total, &record.after_largest);
    run->collections[run->collection_count++] = record;
    run->pauses[run->pause_count++] = (Pause){line, record.work, record.freed, true};
    timeline_add(&run->timeline, false, record.work);
    return true;
}
static int allocation_address(const Heap *heap, int size) {
    CollectorType type = heap->collector.type;
    if (type == MARK_SWEEP || type == REFCOUNT)
        return first_fit(heap, size, 0, heap->size);
    int capacity = type == COPYING        ? heap->size / 2
                   : type == GENERATIONAL ? heap->collector.young / 2
                                          : heap->size;
    return heap->top + size <= heap->base + capacity ? heap->top : -1;
}
static const char *generational_kind(const Heap *heap, bool second) {
    int largest = 0;
    Blocks old = range_blocks(heap, heap->collector.young, heap->size);
    for (int i = 0; i < old.count; ++i)
        if (old.values[i].length > largest)
            largest = old.values[i].length;
    return largest < heap->top - heap->base ? (second ? "full" : "major") : (second ? "tenure" : "minor");
}
static bool allocate(Run *run, Command command) {
    Heap *heap = run->heap;
    int size = 1 + command.args[0] + command.args[1], address = allocation_address(heap, size);
    if (address < 0) {
        CollectorType type = heap->collector.type;
        if (type == GENERATIONAL) {
            if (!collect(run, generational_kind(heap, false), command.line, size))
                return false;
            address = allocation_address(heap, size);
            if (address < 0) {
                if (!collect(run, generational_kind(heap, true), command.line, size))
                    return false;
                address = allocation_address(heap, size);
            }
        } else {
            const char *kind = type == MARK_SWEEP     ? "sweep"
                               : type == MARK_COMPACT ? "compact"
                               : type == COPYING      ? "copy"
                                                      : "backup";
            collect(run, kind, command.line, size);
            address = allocation_address(heap, size);
        }
    }
    if (address < 0)
        return false;
    heap->objects[heap->count++] = (Object){.id = command.object,
                                            .p = command.args[0],
                                            .d = command.args[1],
                                            .address = address,
                                            .present = true};
    if (heap->collector.type != MARK_SWEEP && heap->collector.type != REFCOUNT)
        heap->top = address + size;
    if (heap->collector.type == REFCOUNT)
        retain(run, command.object);
    heap->roots[heap->root_count++] = command.object;
    int amount_ = used(heap);
    if (amount_ > run->peak_used)
        run->peak_used = amount_;
    return true;
}
static void observe(Run *run, Command command) {
    Heap *heap = run->heap;
    bool live[5000], dead[5000];
    reachable(heap, live);
    garbage_set(heap, live, dead);
    Pair all = {0};
    for (int i = 0; i < heap->count; ++i)
        if (heap->objects[i].present)
            add_object(&all, object_size(heap->objects[i]));
    Pair live_pair = amount(heap, live), dead_pair = amount(heap, dead);
    Lines *lines = &run->observations[command.checkpoint];
    add_line(lines,
             "heap objects %" PRId64 " %" PRId64 " reachable %" PRId64 " %" PRId64 " garbage %" PRId64
             " %" PRId64,
             all.count, all.words, live_pair.count, live_pair.words, dead_pair.count, dead_pair.words);
    Blocks blocks = free_blocks(heap);
    int total, largest, sizes[4096];
    free_amount(heap, &total, &largest);
    for (int i = 0; i < blocks.count; ++i)
        sizes[i] = blocks.values[i].length;
    add_line(lines, "free total %d largest %d blocks %d sizes %s fragmentation %s", total, largest,
             blocks.count, class_table(sizes, blocks.count), pct(total - largest, total));
    Integer pointers = 0, forward = 0, backward = 0, distance = 0;
    for (int i = 0; i < heap->count; ++i)
        if (live[i]) {
            Object object = heap->objects[i];
            for (int f = 0; f < object.p; ++f) {
                int value = object.fields[f];
                if (!value)
                    continue;
                ++pointers;
                int delta = heap->objects[value - 1].address - object.address;
                if (delta > 0)
                    ++forward;
                if (delta < 0)
                    ++backward;
                distance += delta < 0 ? -delta : delta;
            }
        }
    add_line(lines, "locality pointers %" PRId64 " forward %" PRId64 " backward %" PRId64 " mean_distance %s",
             pointers, forward, backward, pointers ? dec2(distance, pointers) : "-");
    if (heap->collector.type == GENERATIONAL) {
        Pair young = {0}, old = {0};
        int ages[4] = {0}, remembered = 0;
        for (int i = 0; i < heap->count; ++i) {
            Object object = heap->objects[i];
            if (heap->remembered[i])
                ++remembered;
            if (!object.present)
                continue;
            if (object.address < heap->collector.young) {
                add_object(&young, object_size(object));
                ++ages[object.age < 3 ? object.age : 3];
            } else
                add_object(&old, object_size(object));
        }
        add_line(lines,
                 "generations young %" PRId64 " %" PRId64 " old %" PRId64 " %" PRId64
                 " remembered %d ages 0:%d 1:%d 2:%d 3+:%d",
                 young.count, young.words, old.count, old.words, remembered, ages[0], ages[1], ages[2],
                 ages[3]);
    }
    bool map = false;
    for (int i = 0; i < run->config->map_count; ++i)
        if (!strcmp(run->config->maps[i], command.label))
            map = true;
    if (map) {
        char *image = heap_map(heap, live);
        for (int first = 0; first < heap->size; first += run->config->width)
            add_line(lines, "%04d %.*s", first, run->config->width, image + first);
        free(image);
    }
}
static Run *create_run(const Config *config, const Reference *reference, Collector collector) {
    Run *run = calloc(1, sizeof *run);
    run->config = config;
    run->reference = reference;
    run->heap = calloc(1, sizeof *run->heap);
    run->heap->size = config->heap;
    run->heap->collector = collector;
    run->collections = calloc(10000, sizeof(Collection));
    run->pauses = calloc(15000, sizeof(Pause));
    run->cascades = calloc(5000, sizeof(Cascade));
    run->observations = calloc((size_t)reference->checkpoint_count, sizeof(Lines));
    return run;
}
static void execute_run(Run *run) {
    Heap *heap = run->heap;
    for (int c = 0; c < run->reference->commands.count; ++c) {
        Command command = run->reference->commands.items[c];
        Cascade cascade = {.line = command.line};
        int kind = command.kind, *a = command.args;
        bool rc = heap->collector.type == REFCOUNT;
        if (kind == ALLOC) {
            if (!allocate(run, command)) {
                run->oom_line = command.line;
                run->oom_size = 1 + a[0] + a[1];
                break;
            }
        } else if (kind == PUSH || kind == LOAD) {
            int value =
                kind == PUSH ? slot_value(heap, a[0]) : heap->objects[heap->roots[a[0]] - 1].fields[a[1]];
            if (rc)
                retain(run, value);
            heap->roots[heap->root_count++] = value;
        } else if (kind == POP) {
            for (int i = 0; i < a[0]; ++i) {
                int value = heap->roots[--heap->root_count];
                if (rc)
                    release(run, value, &cascade);
            }
        } else if (kind == SET) {
            int target = heap->roots[a[0]], value = slot_value(heap, a[2]),
                before = heap->objects[target - 1].fields[a[1]];
            if (heap->collector.type == GENERATIONAL)
                barrier(heap, target, value);
            if (rc)
                retain(run, value);
            heap->objects[target - 1].fields[a[1]] = value;
            if (rc)
                release(run, before, &cascade);
        } else if (kind == OVERWRITE) {
            int value = slot_value(heap, a[1]), before = heap->roots[a[0]];
            if (rc)
                retain(run, value);
            heap->roots[a[0]] = value;
            if (rc)
                release(run, before, &cascade);
        }
        timeline_add(&run->timeline, true, kind == ALLOC ? 1 + a[0] + a[1] : 1);
        if (cascade.freed.count) {
            run->cascades[run->cascade_count++] = cascade;
            run->pauses[run->pause_count++] = (Pause){command.line, cascade.work, cascade.freed, false};
            timeline_add(&run->timeline, false, cascade.work);
        }
        if (kind == CHECKPOINT)
            observe(run, command);
    }
    if (heap->collector.type == REFCOUNT && !run->oom_line) {
        bool live[5000], garbage[5000];
        reachable(heap, live);
        garbage_set(heap, live, garbage);
        Lines report = leak_report(run, "end", garbage);
        extend_lines(&run->leaks, &report);
    }
}
static Lines collection_report(const Run *run) {
    Heap *heap = run->heap;
    Lines lines = {0};
    add_line(&lines, "collector %s %s", heap->collector.name, type_name(heap->collector.type));
    for (int i = 0; i < run->collection_count; ++i) {
        Collection c = run->collections[i];
        add_line(&lines,
                 "%d line %d size %d kind %s live %" PRId64 " %" PRId64 " freed %" PRId64 " %" PRId64
                 " moved %" PRId64 " %" PRId64 " promoted %" PRId64 " %" PRId64 " stack %" PRId64
                 " work %" PRId64 " before %d %d after %d %d",
                 c.number, c.line, c.request, c.kind, c.live.count, c.live.words, c.freed.count,
                 c.freed.words, c.moved.count, c.moved.words, c.promoted.count, c.promoted.words, c.stack,
                 c.work, c.before_total, c.before_largest, c.after_total, c.after_largest);
    }
    PauseStats stats = pause_stats(run->pauses, run->pause_count);
    add_line(&lines,
             "totals collections %d pauses %d work %" PRId64 " freed %" PRId64
             " pause p50 %s p90 %s max %" PRId64,
             run->collection_count, run->pause_count, stats.work, stats.freed, stats.p50, stats.p90,
             stats.maximum);
    char *utilization = format("utilization %s mmu", pct(run->timeline.mutator, run->timeline.total));
    for (int i = 0; i < run->config->window_count; ++i) {
        int width = run->config->windows[i];
        append_text(&utilization, " %d:%s", width, mmu(&run->timeline, width));
    }
    add_line(&lines, "%s", utilization);
    free(utilization);
    if (heap->collector.type == GENERATIONAL) {
        char *line = format("generational");
        const char *kinds[] = {"minor", "major", "tenure", "full"};
        Pair promotions = {0};
        for (int k = 0; k < 4; ++k) {
            Integer count = 0, work = 0;
            for (int i = 0; i < run->collection_count; ++i)
                if (!strcmp(run->collections[i].kind, kinds[k])) {
                    ++count;
                    work += run->collections[i].work;
                }
            append_text(&line, " %s %" PRId64 " %" PRId64, kinds[k], count, work);
        }
        for (int i = 0; i < run->collection_count; ++i)
            merge_pair(&promotions, run->collections[i].promoted);
        append_text(&line, " promoted %" PRId64 " %" PRId64 " barrier %" PRId64 " remembered %" PRId64,
                    promotions.count, promotions.words, heap->barriers, heap->remembers);
        add_line(&lines, "%s", line);
        free(line);
    }
    if (heap->collector.type == REFCOUNT) {
        Pair freed = {0};
        const Cascade *largest = NULL;
        for (int i = 0; i < run->cascade_count; ++i) {
            const Cascade *cascade = &run->cascades[i];
            merge_pair(&freed, cascade->freed);
            if (!largest || cascade->work > largest->work)
                largest = cascade;
        }
        add_line(&lines,
                 "refcount increments %" PRId64 " decrements %" PRId64 " cascades %d freed %" PRId64
                 " %" PRId64 " max_cascade %" PRId64 " %" PRId64 " line %s",
                 run->increments, run->decrements, run->cascade_count, freed.count, freed.words,
                 largest ? largest->freed.count : 0, largest ? largest->work : 0,
                 largest ? format("%d", largest->line) : "-");
    }
    int previous = 0;
    Pause *phase = malloc((size_t)run->pause_count * sizeof *phase);
    for (int checkpoint = 0; checkpoint < run->reference->checkpoint_count; ++checkpoint) {
        Checkpoint c = run->reference->checkpoints[checkpoint];
        if (!run->observations[checkpoint].count) {
            add_line(&lines, "phase %s out_of_memory", c.label);
            continue;
        }
        int count = 0, collections = 0;
        for (int i = 0; i < run->pause_count; ++i)
            if (run->pauses[i].line > previous && run->pauses[i].line <= c.line) {
                phase[count++] = run->pauses[i];
                if (run->pauses[i].collection)
                    ++collections;
            }
        PauseStats stats_ = pause_stats(phase, count);
        add_line(&lines,
                 "phase %s collections %d pauses %d work %" PRId64 " freed %" PRId64 " max_pause %" PRId64,
                 c.label, collections, count, stats_.work, stats_.freed, stats_.maximum);
        previous = c.line;
    }
    free(phase);
    if (run->oom_line)
        add_line(&lines, "status out_of_memory line %d size %d", run->oom_line, run->oom_size);
    else
        add_line(&lines, "status completed");
    return lines;
}
static char *summary(const Run *run) {
    Heap *heap = run->heap;
    PauseStats stats = pause_stats(run->pauses, run->pause_count);
    Integer live = 0, moved = 0, moved_objects = 0, max_moves = 0;
    for (int i = 0; i < run->collection_count; ++i) {
        live += run->collections[i].live.count;
        moved += run->collections[i].moved.count;
    }
    for (int i = 0; i < heap->count; ++i) {
        if (heap->objects[i].moves)
            ++moved_objects;
        if (heap->objects[i].moves > max_moves)
            max_moves = heap->objects[i].moves;
    }
    char *line = format("%s,%s,%s,%d,%d,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64
                        ",%s,%s,%" PRId64 ",%d",
                        heap->collector.name, type_name(heap->collector.type),
                        run->oom_line ? "out_of_memory" : "completed", run->collection_count,
                        run->pause_count, live, moved, moved_objects, max_moves, stats.freed, stats.work,
                        stats.p50, stats.p90, stats.maximum, run->peak_used);
    if (run->oom_line)
        append_text(&line, ",-,-,-,-");
    else {
        int total, largest;
        free_amount(heap, &total, &largest);
        append_text(&line, ",%d,%d,%d,%s", used(heap), total, largest, pct(total - largest, total));
    }
    return line;
}
int main(void) {
    Config config = read_config();
    Script script = read_commands();
    Reference *reference = analyze_script(script);
    FILE *mutator = fopen("output/mutator.txt", "w");
    Lines report = reference_report(reference);
    write_lines(mutator, &report);
    fclose(mutator);
    Run *runs[8];
    for (int i = 0; i < config.collector_count; ++i) {
        runs[i] = create_run(&config, reference, config.collectors[i]);
        execute_run(runs[i]);
    }
    FILE *maps = fopen("output/heap_maps.txt", "w");
    bool first = true;
    for (int c = 0; c < reference->checkpoint_count; ++c)
        for (int i = 0; i < config.collector_count; ++i) {
            if (!first)
                fputc('\n', maps);
            first = false;
            Checkpoint checkpoint = reference->checkpoints[c];
            fprintf(maps, "checkpoint %s line %d collector %s\n", checkpoint.label, checkpoint.line,
                    runs[i]->heap->collector.name);
            if (!runs[i]->observations[c].count)
                fputs("out_of_memory\n", maps);
            else
                write_lines(maps, &runs[i]->observations[c]);
        }
    fclose(maps);
    FILE *collections = fopen("output/collections.txt", "w"), *csv = fopen("output/summary.csv", "w"),
         *leaks = fopen("output/leaks.txt", "w");
    fputs(
        "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation\n",
        csv);
    bool first_rc = true;
    for (int i = 0; i < config.collector_count; ++i) {
        Run *run = runs[i];
        if (i)
            fputc('\n', collections);
        Lines lines = collection_report(run);
        write_lines(collections, &lines);
        fprintf(csv, "%s\n", summary(run));
        if (run->heap->collector.type == REFCOUNT) {
            if (!first_rc)
                fputc('\n', leaks);
            first_rc = false;
            fprintf(leaks, "collector %s\n", run->heap->collector.name);
            write_lines(leaks, &run->leaks);
            if (run->oom_line)
                fputs("status out_of_memory\n", leaks);
        }
    }
    if (first_rc)
        fputs("none\n", leaks);
    fclose(collections);
    fclose(csv);
    fclose(leaks);
    return 0;
}
