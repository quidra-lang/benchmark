#include "linker.h"
typedef struct Allocation {
    void *value;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
void *ml_alloc(size_t size) {
    void *value = calloc(1, size ? size : 1);
    Allocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    record->value = value;
    record->next = allocations;
    allocations = record;
    return value;
}
void *ml_grow(void *items, int *capacity, size_t size, int count) {
    int next = *capacity ? *capacity * 2 : 8;
    void *result = ml_alloc((size_t)next * size);
    if (count)
        memcpy(result, items, (size_t)count * size);
    *capacity = next;
    return result;
}
char *ml_text(const char *text, size_t length) {
    char *result = ml_alloc(length + 1);
    memcpy(result, text, length);
    return result;
}
char *ml_format(const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *result = ml_alloc((size_t)count + 1);
    vsnprintf(result, (size_t)count + 1, format, args);
    va_end(args);
    return result;
}
void ml_cleanup(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->value);
        free(allocations);
        allocations = next;
    }
}
void text_add(Text *text, const char *value) {
    size_t length = strlen(value);
    while ((size_t)text->capacity < (size_t)text->count + length + 1)
        text->items = ml_grow(text->items, &text->capacity, 1, text->count);
    memcpy(text->items + text->count, value, length + 1);
    text->count += (int)length;
}
void text_char(Text *text, char c) {
    char value[2] = {c, 0};
    text_add(text, value);
}
char *text_value(Text *text) {
    if (!text->items)
        return ml_text("", 0);
    return text->items;
}
void *layout_alloc(Linker *linker, size_t size) {
    void *value = calloc(1, size ? size : 1);
    LayoutAllocation *record = malloc(sizeof(*record));
    if (!value || !record)
        exit(1);
    record->value = value;
    record->next = linker->layout_allocations;
    linker->layout_allocations = record;
    return value;
}
void layout_clear(Linker *linker) {
    while (linker->layout_allocations) {
        LayoutAllocation *next = linker->layout_allocations->next;
        free(linker->layout_allocations->value);
        free(linker->layout_allocations);
        linker->layout_allocations = next;
    }
}
static bool string_member(StringList list, const char *value) {
    for (int i = 0; i < list.count; ++i)
        if (equal(list.items[i], value))
            return true;
    return false;
}
Name *find_name(Linker *linker, const char *name, bool create) {
    uint32_t hash = 0;
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p)
        hash = hash * 65599u + *p;
    int bucket = (int)(hash % 8192);
    for (Name *entry = linker->buckets[bucket]; entry; entry = entry->next)
        if (equal(entry->name, name))
            return entry;
    if (!create)
        return NULL;
    Name *entry = ml_alloc(sizeof(*entry));
    entry->name = name;
    entry->next = linker->buckets[bucket];
    linker->buckets[bucket] = entry;
    PUSH(linker->names, entry);
    return entry;
}
static Segment *segment_named(Script *script, const char *name) {
    for (int i = 0; i < script->segments.count; ++i)
        if (equal(script->segments.items[i]->name, name))
            return script->segments.items[i];
    return NULL;
}
static OutputSection *output_named(Script *script, const char *name) {
    for (int i = 0; i < script->outputs.count; ++i)
        if (equal(script->outputs.items[i]->name, name))
            return script->outputs.items[i];
    return NULL;
}
static void read_script(Linker *linker) {
    Script *script = &linker->script;
    StringList lines = read_lines("input/link.txt");
    for (int i = 0; i < lines.count; ++i) {
        const char *line = lines.items[i];
        StringList a = words(line);
        if (equal(a.items[0], "entry"))
            script->entry = a.items[1];
        else if (equal(a.items[0], "gc"))
            script->gc = equal(a.items[1], "on");
        else if (equal(a.items[0], "segment")) {
            Segment *segment = ml_alloc(sizeof(*segment));
            segment->name = a.items[1];
            segment->base = number(a.items[2]);
            segment->length = number(a.items[3]);
            segment->fill = number(a.items[4]);
            for (int j = 5; j < a.count; ++j) {
                OutputSection *output = ml_alloc(sizeof(*output));
                output->name = a.items[j];
                output->segment = segment;
                PUSH(segment->sections, output);
                PUSH(script->outputs, output);
            }
            PUSH(script->segments, segment);
        } else if (equal(a.items[0], "load")) {
            Load load = {segment_named(script, a.items[1]), segment_named(script, a.items[2])};
            PUSH(script->loads, load);
        } else if (equal(a.items[0], "keep"))
            PUSH(script->keep, a.items[1]);
        else if (equal(a.items[0], "sort"))
            PUSH(script->sort, a.items[1]);
        else if (equal(a.items[0], "wrap"))
            PUSH(script->wrap, a.items[1]);
        else if (equal(a.items[0], "define")) {
            ScriptDefinition definition = {a.items[1], strstr(line, " = ") + 3};
            PUSH(script->definitions, definition);
            find_name(linker, a.items[1], true)->script = true;
        } else if (equal(a.items[0], "checksum")) {
            script->checksum_segment = segment_named(script, a.items[1]);
            script->checksum_symbol = a.items[2];
        } else {
            Input input = {0};
            input.kind = a.items[0];
            for (int j = 1; j < a.count; ++j)
                PUSH(input.names, a.items[j]);
            PUSH(script->inputs, input);
        }
    }
}
void load_object(Linker *linker, Object *object) {
    object->rank = linker->objects.count;
    for (int i = 0; i < object->groups.count; ++i) {
        COMDATGroup group = object->groups.items[i];
        COMDATRecord *previous = NULL;
        for (int j = 0; j < linker->comdat.count; ++j)
            if (equal(linker->comdat.items[j]->signature, group.signature)) {
                previous = linker->comdat.items[j];
                break;
            }
        if (previous) {
            for (int j = 0; j < group.sections.count; ++j)
                group.sections.items[j]->reason = "comdat";
            PUSH(previous->discarders, (char *)object->name);
        } else {
            COMDATRecord *record = ml_alloc(sizeof(*record));
            record->signature = group.signature;
            record->keeper = object;
            PUSH(linker->comdat, record);
        }
    }
    for (int i = 0; i < object->symbols.count; ++i) {
        Symbol *symbol = object->symbols.items[i];
        if (equal(symbol->binding, "local"))
            continue;
        if (equal(symbol->location, "section") && equal(symbol->section->reason, "comdat")) {
            symbol->location = "undef";
            symbol->section = NULL;
        }
        if (equal(symbol->location, "undef")) {
            if (string_member(linker->script.wrap, symbol->name))
                symbol->name = ml_format("__wrap_%s", symbol->name);
            else if (strncmp(symbol->name, "__real_", 7) == 0 &&
                     string_member(linker->script.wrap, symbol->name + 7))
                symbol->name += 7;
        }
        Name *name = find_name(linker, symbol->name, true);
        symbol->global_name = name;
        PUSH(name->entries, symbol);
    }
    PUSH(linker->objects, object);
}
static bool defined_name(Linker *linker, const char *value) {
    Name *name = find_name(linker, value, false);
    if (!name)
        return false;
    if (name->script)
        return true;
    for (int i = 0; i < name->entries.count; ++i)
        if (!equal(name->entries.items[i]->location, "undef"))
            return true;
    return false;
}
bool undefined_name(Linker *linker, const char *value) {
    if (defined_name(linker, value))
        return false;
    if (equal(value, linker->script.entry))
        return true;
    Name *name = find_name(linker, value, false);
    if (name)
        for (int i = 0; i < name->entries.count; ++i)
            if (equal(name->entries.items[i]->binding, "global") &&
                equal(name->entries.items[i]->location, "undef"))
                return true;
    return false;
}
const char *referrer(Linker *linker, const char *value) {
    Name *name = find_name(linker, value, false);
    if (name)
        for (int i = 0; i < name->entries.count; ++i)
            if (equal(name->entries.items[i]->binding, "global") &&
                equal(name->entries.items[i]->location, "undef"))
                return name->entries.items[i]->object->name;
    return "*entry*";
}
static int scan(Linker *linker, const char *name) {
    Archive *archive = NULL;
    for (int i = 0; i < linker->archives.count; ++i)
        if (equal(linker->archives.items[i]->name, name))
            archive = linker->archives.items[i];
    if (!archive) {
        archive = read_archive(name);
        PUSH(linker->archives, archive);
    }
    return scan_archive(archive, linker);
}
static void load_inputs(Linker *linker) {
    for (int i = 0; i < linker->script.inputs.count; ++i) {
        Input input = linker->script.inputs.items[i];
        if (equal(input.kind, "object"))
            load_object(linker,
                        parse_object(read_lines(ml_format("input/%s", input.names.items[0])),
                                     input.names.items[0]));
        else if (equal(input.kind, "library"))
            scan(linker, input.names.items[0]);
        else
            while (true) {
                int count = 0;
                for (int j = 0; j < input.names.count; ++j)
                    count += scan(linker, input.names.items[j]);
                if (!count)
                    break;
            }
    }
}
static int name_compare(const void *left, const void *right) {
    Name *a = *(Name *const *)left;
    Name *b = *(Name *const *)right;
    return strcmp(a->name, b->name);
}
static void resolve(Linker *linker) {
    if (linker->names.count > 1)
        qsort(linker->names.items, (size_t)linker->names.count, sizeof(Name *), name_compare);
    for (int i = 0; i < linker->names.count; ++i) {
        Name *name = linker->names.items[i];
        name->resolution = resolve_name(name->name, name->entries, name->script);
    }
}
static void mark(SectionList *queue, Section *section) {
    if (section && !*section->reason && section->output && !section->live) {
        section->live = true;
        PUSH(*queue, section);
    }
}
static void collect(Linker *linker) {
    for (int i = 0; i < linker->objects.count; ++i) {
        Object *object = linker->objects.items[i];
        for (int j = 0; j < object->sections.count; ++j) {
            Section *section = object->sections.items[j];
            if (equal(section->reason, "comdat"))
                continue;
            section->output = output_for(section, linker->script.outputs);
            if (!section->output) {
                section->reason = "orphan";
                int k = 0;
                while (k < linker->orphans.count &&
                       !equal(linker->orphans.items[k].name, section->name))
                    ++k;
                if (k == linker->orphans.count) {
                    OrphanCount count = {section->name, 0};
                    PUSH(linker->orphans, count);
                }
                ++linker->orphans.items[k].count;
            } else if (!linker->script.gc)
                section->live = true;
        }
    }
    if (!linker->script.gc) {
        for (int i = 0; i < linker->names.count; ++i)
            if (equal(linker->names.items[i]->resolution->kind, "common"))
                linker->names.items[i]->resolution->live = true;
        return;
    }
    SectionList queue = {0};
    for (int i = 0; i < linker->objects.count; ++i)
        for (int j = 0; j < linker->objects.items[i]->sections.count; ++j) {
            Section *section = linker->objects.items[i]->sections.items[j];
            if (section->output && string_member(linker->script.keep, section->output->name))
                mark(&queue, section);
        }
    Name *entry = find_name(linker, linker->script.entry, false);
    if (entry) {
        Resolution *r = entry->resolution;
        if (equal(r->kind, "global") || equal(r->kind, "weak"))
            mark(&queue, r->definition->section);
        else if (equal(r->kind, "common"))
            r->live = true;
    }
    for (int head = 0; head < queue.count; ++head)
        for (int j = 0; j < queue.items[head]->relocations.count; ++j) {
            Symbol *symbol = queue.items[head]->relocations.items[j]->symbol;
            if (equal(symbol->binding, "local"))
                mark(&queue, symbol->section);
            else {
                Resolution *r = symbol->global_name->resolution;
                if (equal(r->kind, "global") || equal(r->kind, "weak"))
                    mark(&queue, r->definition->section);
                else if (equal(r->kind, "common"))
                    r->live = true;
            }
        }
    for (int i = 0; i < linker->objects.count; ++i)
        for (int j = 0; j < linker->objects.items[i]->sections.count; ++j) {
            Section *section = linker->objects.items[i]->sections.items[j];
            if (section->output && !*section->reason && !section->live)
                section->reason = "gc";
        }
}
static OutputSection *sorting_output;
static int section_compare(const void *left, const void *right) {
    Section *a = *(Section *const *)left;
    Section *b = *(Section *const *)right;
    int64_t pa = equal(a->name, sorting_output->name)
                     ? 65536
                     : number(a->name + strlen(sorting_output->name) + 1);
    int64_t pb = equal(b->name, sorting_output->name)
                     ? 65536
                     : number(b->name + strlen(sorting_output->name) + 1);
    if (pa != pb)
        return pa < pb ? -1 : 1;
    if (a->object->rank != b->object->rank)
        return a->object->rank - b->object->rank;
    return a->order - b->order;
}
static int common_compare(const void *left, const void *right) {
    Resolution *a = *(Resolution *const *)left;
    Resolution *b = *(Resolution *const *)right;
    if (a->alignment != b->alignment)
        return a->alignment > b->alignment ? -1 : 1;
    return strcmp(a->name, b->name);
}
static Component *component_new(Linker *linker, const char *kind) {
    Component *result = layout_alloc(linker, sizeof(*result));
    result->kind = kind;
    result->alignment = 1;
    return result;
}
typedef struct StringEntry {
    const uint8_t *data;
    int length;
    int64_t offset;
    struct StringEntry *next;
} StringEntry;
static void components(Linker *linker, OutputSection *output) {
    int count = 0;
    for (int i = 0; i < linker->objects.count; ++i)
        for (int j = 0; j < linker->objects.items[i]->sections.count; ++j) {
            Section *section = linker->objects.items[i]->sections.items[j];
            if (section->live && section->output == output)
                ++count;
        }
    Section **sections = layout_alloc(linker, (size_t)count * sizeof(*sections));
    int at = 0;
    for (int i = 0; i < linker->objects.count; ++i)
        for (int j = 0; j < linker->objects.items[i]->sections.count; ++j) {
            Section *section = linker->objects.items[i]->sections.items[j];
            if (section->live && section->output == output)
                sections[at++] = section;
        }
    if (string_member(linker->script.sort, output->name) && count > 1) {
        sorting_output = output;
        qsort(sections, (size_t)count, sizeof(Section *), section_compare);
    }
    int string_sections = 0;
    int64_t original_size = 0;
    for (int i = 0; i < count; ++i)
        if (belongs(sections[i]->name, ".rodata.str")) {
            ++string_sections;
            original_size += sections[i]->size;
        }
    Component *merged = NULL;
    if (string_sections) {
        merged = component_new(linker, "merged");
        merged->string_sections = string_sections;
        merged->original_size = original_size;
        merged->data.items = layout_alloc(linker, (size_t)original_size);
        merged->data.capacity = (int)original_size;
        StringEntry **buckets = layout_alloc(linker, 8192 * sizeof(*buckets));
        for (int i = 0; i < count; ++i) {
            Section *section = sections[i];
            if (!belongs(section->name, ".rodata.str"))
                continue;
            section->merged = merged;
            section->string_offsets =
                layout_alloc(linker, ((size_t)section->size + 1) * sizeof(int64_t));
            for (int start = 0; start < section->data.count;) {
                int end = start;
                while (section->data.items[end])
                    ++end;
                ++end;
                int length = end - start;
                uint32_t hash = 0;
                for (int j = start; j < end; ++j)
                    hash = hash * 65599u + section->data.items[j];
                int bucket = (int)(hash % 8192);
                StringEntry *found = buckets[bucket];
                while (found &&
                       (found->length != length ||
                        memcmp(found->data, section->data.items + start, (size_t)length) != 0))
                    found = found->next;
                int64_t offset;
                if (found)
                    offset = found->offset;
                else {
                    offset = merged->data.count;
                    memcpy(merged->data.items + merged->data.count, section->data.items + start,
                           (size_t)length);
                    merged->data.count += length;
                    ++merged->unique;
                    StringEntry *entry = layout_alloc(linker, sizeof(*entry));
                    entry->data = section->data.items + start;
                    entry->length = length;
                    entry->offset = offset;
                    entry->next = buckets[bucket];
                    buckets[bucket] = entry;
                }
                section->string_offsets[start] = offset;
                ++merged->strings;
                start = end;
            }
        }
        merged->size = merged->data.count;
    }
    output->components.count = 0;
    bool inserted = false;
    for (int i = 0; i < count; ++i) {
        Section *section = sections[i];
        if (belongs(section->name, ".rodata.str")) {
            if (!inserted) {
                PUSH(output->components, merged);
                inserted = true;
            }
        } else {
            Component *component = component_new(linker, "section");
            component->size = section->size;
            component->alignment = section->alignment;
            component->section = section;
            PUSH(output->components, component);
        }
    }
    if (equal(output->name, ".bss")) {
        int common_count = 0;
        for (int i = 0; i < linker->names.count; ++i) {
            Resolution *r = linker->names.items[i]->resolution;
            if (equal(r->kind, "common") && r->live)
                ++common_count;
        }
        Resolution **commons = layout_alloc(linker, (size_t)common_count * sizeof(*commons));
        at = 0;
        for (int i = 0; i < linker->names.count; ++i) {
            Resolution *r = linker->names.items[i]->resolution;
            if (equal(r->kind, "common") && r->live)
                commons[at++] = r;
        }
        if (common_count > 1)
            qsort(commons, (size_t)common_count, sizeof(Resolution *), common_compare);
        for (int i = 0; i < common_count; ++i) {
            Component *component = component_new(linker, "common");
            component->size = commons[i]->size;
            component->alignment = commons[i]->alignment;
            component->common = commons[i];
            PUSH(output->components, component);
        }
    }
    if (output->veneer_targets.count > 1)
        qsort(output->veneer_targets.items, (size_t)output->veneer_targets.count, sizeof(Name *),
              name_compare);
    for (int i = 0; i < output->veneer_targets.count; ++i) {
        Component *component = component_new(linker, "veneer");
        component->size = 8;
        component->alignment = 4;
        component->target = output->veneer_targets.items[i];
        PUSH(output->components, component);
    }
}
static int64_t section_value(Section *section, int64_t offset) {
    return belongs(section->name, ".rodata.str")
               ? section->merged->address + section->string_offsets[offset]
               : section->address + offset;
}
static bool name_value(Name *name, int64_t *value) {
    Resolution *r = name->resolution;
    if (equal(r->kind, "global") || equal(r->kind, "weak"))
        *value = section_value(r->definition->section, r->definition->offset);
    else if (equal(r->kind, "common"))
        *value = r->address;
    else if (equal(r->kind, "script"))
        *value = name->value;
    else if (equal(r->kind, "weakundef"))
        *value = 0;
    else
        return false;
    return true;
}
static bool symbol_value(Symbol *symbol, int64_t *value) {
    if (equal(symbol->binding, "local")) {
        *value = section_value(symbol->section, symbol->offset);
        return true;
    }
    return name_value(symbol->global_name, value);
}
static bool far_call(Relocation *relocation) {
    if (!equal(relocation->type, "CALL24") || equal(relocation->symbol->binding, "local"))
        return false;
    Resolution *r = relocation->symbol->global_name->resolution;
    if (!equal(r->kind, "global") && !equal(r->kind, "weak"))
        return false;
    int64_t s;
    name_value(relocation->symbol->global_name, &s);
    int64_t value = s + relocation->addend - (relocation->section->address + relocation->offset);
    return value < -(INT64_C(1) << 25) || value >= (INT64_C(1) << 25);
}
static void layout(Linker *linker) {
    while (true) {
        layout_clear(linker);
        for (int i = 0; i < linker->script.segments.count; ++i) {
            Segment *segment = linker->script.segments.items[i];
            for (int j = 0; j < segment->sections.count; ++j)
                components(linker, segment->sections.items[j]);
            place_segment(segment);
        }
        bool changed = false;
        for (int i = 0; i < linker->objects.count; ++i)
            for (int j = 0; j < linker->objects.items[i]->sections.count; ++j) {
                Section *section = linker->objects.items[i]->sections.items[j];
                if (!section->live)
                    continue;
                for (int k = 0; k < section->relocations.count; ++k) {
                    Relocation *relocation = section->relocations.items[k];
                    if (!far_call(relocation))
                        continue;
                    Name *target = relocation->symbol->global_name;
                    bool found = false;
                    for (int n = 0; n < section->output->veneer_targets.count; ++n)
                        if (section->output->veneer_targets.items[n] == target)
                            found = true;
                    if (!found) {
                        PUSH(section->output->veneer_targets, target);
                        changed = true;
                    }
                }
            }
        if (!changed)
            return;
    }
}
static void load_addresses(Linker *linker) {
    int64_t positions[8] = {0};
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        segment->physical = segment->base;
        positions[i] = segment->base + segment->memory_size;
    }
    for (int i = 0; i < linker->script.loads.count; ++i) {
        Load load = linker->script.loads.items[i];
        int b = 0;
        while (linker->script.segments.items[b] != load.target)
            ++b;
        load.source->physical = aligned(positions[b], 4);
        positions[b] = load.source->physical + load.source->file_size;
    }
    for (int i = 0; i < linker->script.segments.count; ++i)
        linker->script.segments.items[i]->used =
            positions[i] - linker->script.segments.items[i]->base;
}
typedef struct {
    StringList tokens;
    int index;
    Linker *linker;
} ScriptExpression;
static StringList expression_tokens(const char *source) {
    StringList tokens = {0};
    size_t i = 0;
    while (source[i]) {
        if (source[i] == ' ') {
            ++i;
            continue;
        }
        if (strchr("(),+-", source[i])) {
            char *token = ml_text(source + i, 1);
            PUSH(tokens, token);
            ++i;
            continue;
        }
        size_t start = i;
        while (source[i] && source[i] != ' ' && !strchr("(),+-", source[i]))
            ++i;
        char *token = ml_text(source + start, i - start);
        PUSH(tokens, token);
    }
    return tokens;
}
static const char *expression_peek(ScriptExpression *e) {
    return e->index == e->tokens.count ? "" : e->tokens.items[e->index];
}
static int64_t script_expression(ScriptExpression *);
static int64_t script_term(ScriptExpression *e) {
    const char *token = e->tokens.items[e->index++];
    if (equal(token, "(")) {
        int64_t value = script_expression(e);
        ++e->index;
        return value;
    }
    if (token[0] >= '0' && token[0] <= '9')
        return number(token);
    if (equal(expression_peek(e), "(") && word_in("start end size loadaddr align", token)) {
        ++e->index;
        if (equal(token, "align")) {
            int64_t value = script_expression(e);
            ++e->index;
            int64_t alignment = script_expression(e);
            ++e->index;
            return aligned(value, alignment);
        }
        OutputSection *output = output_named(&e->linker->script, e->tokens.items[e->index]);
        e->index += 2;
        if (equal(token, "start"))
            return output->address;
        if (equal(token, "end"))
            return output->address + output->size;
        if (equal(token, "size"))
            return output->size;
        return output->segment->physical + output->address - output->segment->base;
    }
    return find_name(e->linker, token, false)->value;
}
static int64_t script_expression(ScriptExpression *e) {
    int64_t value = script_term(e);
    while (equal(expression_peek(e), "+") || equal(expression_peek(e), "-")) {
        const char *op = e->tokens.items[e->index++];
        int64_t right = script_term(e);
        if (equal(op, "+"))
            value += right;
        else
            value -= right;
    }
    return value;
}
static void define_script_symbols(Linker *linker) {
    for (int i = 0; i < linker->script.definitions.count; ++i) {
        ScriptDefinition definition = linker->script.definitions.items[i];
        ScriptExpression expression = {expression_tokens(definition.expression), 0, linker};
        find_name(linker, definition.name, false)->value = script_expression(&expression);
    }
}
static char *hex_value(int64_t value, int width) {
    return ml_format("%0*llx", width, (unsigned long long)value);
}
static char *joined(StringList values, const char *separator) {
    if (!values.count)
        return "-";
    Text result = {0};
    for (int i = 0; i < values.count; ++i) {
        if (i)
            text_add(&result, separator);
        text_add(&result, values.items[i]);
    }
    return text_value(&result);
}
static char *relocation_location(Relocation *relocation) {
    return ml_format("%s %s+%lld", relocation->section->object->name, relocation->section->name,
                     (long long)relocation->offset);
}
static Component *veneer_component(OutputSection *output, Name *target) {
    for (int i = 0; i < output->components.count; ++i) {
        Component *component = output->components.items[i];
        if (equal(component->kind, "veneer") && component->target == target)
            return component;
    }
    return NULL;
}
static void relocate(Linker *linker) {
    Name *gp_name = find_name(linker, "_gp", false);
    int64_t gp = gp_name ? gp_name->value : 0;
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        for (int j = 0; j < segment->sections.count; ++j) {
            OutputSection *output = segment->sections.items[j];
            for (int k = 0; k < output->components.count; ++k) {
                Component *component = output->components.items[k];
                if (!equal(component->kind, "section"))
                    continue;
                Section *section = component->section;
                for (int n = 0; n < section->relocations.count; ++n) {
                    Relocation *relocation = section->relocations.items[n];
                    if (unpaired(section->relocations, n)) {
                        char *line =
                            ml_format("error: unpaired HI16 at %s against %s",
                                      relocation_location(relocation), relocation->symbol->name);
                        PUSH(linker->relocation_diagnostics, line);
                    }
                    int64_t p = section->address + relocation->offset, s = 0;
                    bool defined = symbol_value(relocation->symbol, &s);
                    int status_index = 4;
                    const char *status = "undefined";
                    char *shown = "-", *value = "-", *field = "-";
                    if (defined) {
                        status = "ok";
                        status_index = 1;
                        if (far_call(relocation)) {
                            s = veneer_component(output, relocation->symbol->global_name)->address;
                            status = "veneer";
                            status_index = 2;
                        }
                        RelocationField result =
                            relocation_field(relocation->type, s, relocation->addend, p, gp);
                        if (!result.valid) {
                            status = "overflow";
                            status_index = 3;
                            char *line = ml_format(
                                "error: relocation overflow at %s: %s value %lld against %s",
                                relocation_location(relocation), relocation->type,
                                (long long)result.value, relocation->symbol->name);
                            PUSH(linker->relocation_diagnostics, line);
                        }
                        little_endian(section->data, (int)relocation->offset, result.field,
                                      relocation_width(relocation->type));
                        shown = hex_value(s, 8);
                        value = ml_format("%lld", (long long)result.value);
                        field = hex_value(result.field, 2 * relocation_width(relocation->type));
                    }
                    int type = 0;
                    while (!equal(relocation_types[type], relocation->type))
                        ++type;
                    ++linker->relocation_counts[type][0];
                    ++linker->relocation_counts[type][status_index];
                    char *line = ml_format(
                        "%08llx %s %s+%lld %s %s %lld %s %s %s %s", (unsigned long long)p,
                        section->object->name, section->name, (long long)relocation->offset,
                        relocation->type, relocation->symbol->name, (long long)relocation->addend,
                        shown, value, field, status);
                    PUSH(linker->relocation_lines, line);
                }
            }
        }
    }
    for (int i = 0; i < 7; ++i) {
        int *counts = linker->relocation_counts[i];
        char *line =
            ml_format("summary %s total %d ok %d veneer %d overflow %d undefined %d",
                      relocation_types[i], counts[0], counts[1], counts[2], counts[3], counts[4]);
        PUSH(linker->relocation_lines, line);
    }
}
static void build_images(Linker *linker) {
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        segment->image.count = (int)segment->file_size;
        segment->image.capacity = segment->image.count;
        segment->image.items = ml_alloc((size_t)segment->file_size);
        memset(segment->image.items, (int)segment->fill, (size_t)segment->file_size);
        for (int j = 0; j < segment->sections.count; ++j) {
            OutputSection *output = segment->sections.items[j];
            if (belongs(output->name, ".bss"))
                continue;
            for (int k = 0; k < output->components.count; ++k) {
                Component *component = output->components.items[k];
                Bytes data;
                if (equal(component->kind, "section"))
                    data = component->section->data;
                else {
                    if (equal(component->kind, "veneer")) {
                        component->data.items = layout_alloc(linker, 8);
                        component->data.count = component->data.capacity = 8;
                        component->data.items[0] = 0x04;
                        component->data.items[1] = 0xf0;
                        component->data.items[2] = 0x1f;
                        component->data.items[3] = 0xe5;
                        int64_t target;
                        name_value(component->target, &target);
                        little_endian(component->data, 4, target, 4);
                    }
                    data = component->data;
                }
                if (data.count)
                    memcpy(segment->image.items + (size_t)(component->address - segment->base),
                           data.items, (size_t)data.count);
            }
        }
    }
    if (linker->script.checksum_segment) {
        Segment *segment = linker->script.checksum_segment;
        Resolution *resolution =
            find_name(linker, linker->script.checksum_symbol, false)->resolution;
        int offset =
            (int)(section_value(resolution->definition->section, resolution->definition->offset) -
                  segment->base);
        little_endian(segment->image, offset, 0, 4);
        int64_t total = 0;
        for (int i = 0; i < segment->image.count; i += 4) {
            int64_t value = 0;
            for (int j = 0; j < 4 && i + j < segment->image.count; ++j)
                value += (int64_t)segment->image.items[i + j] << (8 * j);
            total = modulo(total + value, INT64_C(1) << 32);
        }
        little_endian(segment->image, offset, modulo(-total, INT64_C(1) << 32), 4);
    }
}
static int64_t entry_address(Linker *linker) {
    Name *entry = find_name(linker, linker->script.entry, false);
    if (!entry)
        return 0;
    Resolution *resolution = entry->resolution;
    if (equal(resolution->kind, "global") || equal(resolution->kind, "weak"))
        return section_value(resolution->definition->section, resolution->definition->offset);
    if (equal(resolution->kind, "common"))
        return resolution->address;
    return 0;
}
static int orphan_compare(const void *left, const void *right) {
    const OrphanCount *a = left;
    const OrphanCount *b = right;
    return strcmp(a->name, b->name);
}
static StringList diagnostics(Linker *linker) {
    StringList result = {0};
    if (linker->orphans.count > 1)
        qsort(linker->orphans.items, (size_t)linker->orphans.count, sizeof(OrphanCount),
              orphan_compare);
    for (int i = 0; i < linker->orphans.count; ++i) {
        OrphanCount orphan = linker->orphans.items[i];
        char *line = ml_format("warning: orphan section %s discarded from %d object(s)",
                               orphan.name, orphan.count);
        PUSH(result, line);
    }
    for (int i = 0; i < linker->names.count; ++i) {
        Name *name = linker->names.items[i];
        Resolution *r = name->resolution;
        StringList definers = strong_definers(r, name->script);
        if (definers.count >= 2) {
            char *line = ml_format("error: multiple definition of %s: %s", name->name,
                                   joined(definers, " "));
            PUSH(result, line);
        }
        if (r->common.count && (equal(r->kind, "global") || equal(r->kind, "script"))) {
            char *line =
                ml_format("warning: common symbol %s overridden by %s", name->name, r->definer);
            PUSH(result, line);
        }
        if (equal(r->kind, "common")) {
            bool different = false;
            for (int j = 1; j < r->common.count; ++j)
                if (r->common.items[j]->size != r->common.items[0]->size ||
                    r->common.items[j]->alignment != r->common.items[0]->alignment)
                    different = true;
            if (different) {
                char *line = ml_format("warning: common symbol %s merged to size %lld align %lld",
                                       name->name, (long long)r->size, (long long)r->alignment);
                PUSH(result, line);
            }
        }
    }
    Name *entry = find_name(linker, linker->script.entry, false);
    if (!entry || equal(entry->resolution->kind, "undefined") ||
        equal(entry->resolution->kind, "weakundef")) {
        char *line = ml_format("error: entry symbol %s is undefined", linker->script.entry);
        PUSH(result, line);
    }
    for (int i = 0; i < linker->names.count; ++i) {
        Name *name = linker->names.items[i];
        if (!equal(name->resolution->kind, "undefined"))
            continue;
        StringList referrers = {0};
        for (int j = 0; j < linker->objects.count; ++j) {
            Object *object = linker->objects.items[j];
            bool used = false;
            for (int k = 0; k < object->sections.count; ++k) {
                Section *section = object->sections.items[k];
                if (!section->live)
                    continue;
                for (int n = 0; n < section->relocations.count; ++n) {
                    Symbol *symbol = section->relocations.items[n]->symbol;
                    if (!equal(symbol->binding, "local") && symbol->global_name == name)
                        used = true;
                }
            }
            if (used)
                PUSH(referrers, (char *)object->name);
        }
        if (referrers.count) {
            char *line = ml_format("error: undefined symbol %s referenced by %s", name->name,
                                   joined(referrers, " "));
            PUSH(result, line);
        }
    }
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        if (segment->used > segment->length) {
            char *line = ml_format("error: segment %s overflows its length by %lld bytes",
                                   segment->name, (long long)(segment->used - segment->length));
            PUSH(result, line);
        }
    }
    for (int i = 0; i < linker->script.segments.count; ++i)
        for (int j = i + 1; j < linker->script.segments.count; ++j) {
            Segment *a = linker->script.segments.items[i];
            Segment *b = linker->script.segments.items[j];
            if (a->memory_size >= 1 && b->memory_size >= 1 && a->base < b->base + b->memory_size &&
                b->base < a->base + a->memory_size) {
                char *line = ml_format("error: segments %s and %s overlap", a->name, b->name);
                PUSH(result, line);
            }
        }
    for (int i = 0; i < linker->relocation_diagnostics.count; ++i)
        PUSH(result, linker->relocation_diagnostics.items[i]);
    int errors = 0, warnings = 0;
    for (int i = 0; i < result.count; ++i) {
        if (strncmp(result.items[i], "error", 5) == 0)
            ++errors;
        else if (strncmp(result.items[i], "warning", 7) == 0)
            ++warnings;
    }
    char *totals = ml_format("errors %d warnings %d", errors, warnings);
    PUSH(result, totals);
    return result;
}
static void intel_record(FILE *output, int address, int type, const uint8_t *data, int n) {
    int sum = n + address / 256 + address % 256 + type;
    fprintf(output, ":%02X%04X%02X", (unsigned)n, (unsigned)address, (unsigned)type);
    for (int i = 0; i < n; ++i) {
        fprintf(output, "%02X", (unsigned)data[i]);
        sum += data[i];
    }
    fprintf(output, "%02X\n", (unsigned)((256 - sum % 256) % 256));
}

typedef struct {
    int64_t address;
    const char *name, *kind, *definer;
    int order;
} OutputSymbol;
typedef struct {
    OutputSymbol *items;
    int count, capacity;
} OutputSymbols;
static int symbol_compare(const void *left, const void *right) {
    const OutputSymbol *a = left;
    const OutputSymbol *b = right;
    if (a->address != b->address)
        return a->address < b->address ? -1 : 1;
    int order = strcmp(a->name, b->name);
    return order ? order : a->order - b->order;
}
static void write_reports(Linker *linker) {
    mkdir("output", 0777);
    FILE *image = fopen("output/image.hex", "w");
    FILE *flash = fopen("output/flash.ihex", "w");
    FILE *map = fopen("output/link.map", "w");
    FILE *xref = fopen("output/xref.txt", "w");
    FILE *relocations = fopen("output/relocations.txt", "w");
    FILE *diagnostic_output = fopen("output/diagnostics.txt", "w");
    if (!image || !flash || !map || !xref || !relocations || !diagnostic_output)
        return;
    int64_t entry = entry_address(linker);
    fprintf(image, "entry %08llx %s\n", (unsigned long long)entry, linker->script.entry);
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        fprintf(image, "segment %s vaddr %08llx paddr %08llx filesz %lld memsz %lld\n",
                segment->name, (unsigned long long)segment->base,
                (unsigned long long)segment->physical, (long long)segment->file_size,
                (long long)segment->memory_size);
        for (int k = 0; k < segment->image.count; k += 16) {
            fprintf(image, "%08llx", (unsigned long long)(segment->base + k));
            for (int j = k; j < k + 16 && j < segment->image.count; ++j)
                fprintf(image, " %02x", (unsigned)segment->image.items[j]);
            fputc('\n', image);
        }
    }
    SegmentList ordered = {0};
    for (int i = 0; i < linker->script.segments.count; ++i)
        if (linker->script.segments.items[i]->file_size)
            PUSH(ordered, linker->script.segments.items[i]);
    for (int i = 1; i < ordered.count; ++i) {
        Segment *segment = ordered.items[i];
        int j = i;
        while (j > 0 && ordered.items[j - 1]->physical > segment->physical) {
            ordered.items[j] = ordered.items[j - 1];
            --j;
        }
        ordered.items[j] = segment;
    }
    int64_t upper = 0;
    for (int i = 0; i < ordered.count; ++i) {
        Segment *segment = ordered.items[i];
        for (int k = 0; k < segment->image.count;) {
            int64_t address = segment->physical + k;
            int n = segment->image.count - k;
            if (n > 16)
                n = 16;
            if (n > 65536 - address % 65536)
                n = (int)(65536 - address % 65536);
            if (address / 65536 != upper) {
                upper = address / 65536;
                uint8_t bytes[2] = {(uint8_t)(upper / 256), (uint8_t)(upper % 256)};
                intel_record(flash, 0, 4, bytes, 2);
            }
            intel_record(flash, (int)(address % 65536), 0, segment->image.items + k, n);
            k += n;
        }
    }
    uint8_t entry_bytes[4] = {(uint8_t)((entry >> 24) & 255), (uint8_t)((entry >> 16) & 255),
                              (uint8_t)((entry >> 8) & 255), (uint8_t)(entry & 255)};
    intel_record(flash, 0, 5, entry_bytes, 4);
    intel_record(flash, 0, 1, NULL, 0);
    for (int i = 0; i < linker->extractions.count; ++i) {
        Extraction extraction = linker->extractions.items[i];
        fprintf(map, "member %s %s %s\n", extraction.object, extraction.referrer,
                extraction.reason);
    }
    for (int i = 0; i < linker->comdat.count; ++i) {
        COMDATRecord *record = linker->comdat.items[i];
        fprintf(map, "comdat %s %s %s\n", record->signature, record->keeper->name,
                joined(record->discarders, ","));
    }
    OutputSymbols symbols = {0};
    for (int i = 0; i < linker->script.segments.count; ++i) {
        Segment *segment = linker->script.segments.items[i];
        fprintf(
            map,
            "segment %s vaddr %08llx paddr %08llx filesz %lld memsz %lld used %lld length %lld %lld%%\n",
            segment->name, (unsigned long long)segment->base, (unsigned long long)segment->physical,
            (long long)segment->file_size, (long long)segment->memory_size,
            (long long)segment->used, (long long)segment->length,
            (long long)(100 * segment->used / segment->length));
        for (int j = 0; j < segment->sections.count; ++j) {
            OutputSection *output = segment->sections.items[j];
            fprintf(map, "section %s %08llx %lld %lld\n", output->name,
                    (unsigned long long)output->address, (long long)output->size,
                    (long long)output->alignment);
            for (int k = 0; k < output->components.count; ++k) {
                Component *component = output->components.items[k];
                if (equal(component->kind, "section"))
                    fprintf(map, "input %08llx %lld %lld %s %s\n",
                            (unsigned long long)component->address, (long long)component->size,
                            (long long)component->alignment, component->section->object->name,
                            component->section->name);
                else if (equal(component->kind, "merged"))
                    fprintf(map, "merged %08llx %lld sections %d strings %d unique %d saved %lld\n",
                            (unsigned long long)component->address, (long long)component->size,
                            component->string_sections, component->strings, component->unique,
                            (long long)(component->original_size - component->size));
                else if (equal(component->kind, "common"))
                    fprintf(map, "common %08llx %lld %lld %s %s\n",
                            (unsigned long long)component->address, (long long)component->size,
                            (long long)component->alignment, component->common->definer,
                            component->common->name);
                else {
                    fprintf(map, "veneer %08llx 8 %s\n", (unsigned long long)component->address,
                            component->target->name);
                    OutputSymbol symbol = {component->address,
                                           ml_format("__veneer_%s", component->target->name),
                                           "veneer", "*linker*", symbols.count};
                    PUSH(symbols, symbol);
                }
            }
        }
    }
    for (int i = 0; i < linker->objects.count; ++i) {
        Object *object = linker->objects.items[i];
        for (int j = 0; j < object->sections.count; ++j) {
            Section *section = object->sections.items[j];
            if (*section->reason)
                fprintf(map, "discard %s %s %lld %s\n", object->name, section->name,
                        (long long)section->size, section->reason);
        }
    }
    for (int i = 0; i < linker->names.count; ++i) {
        Name *name = linker->names.items[i];
        Resolution *r = name->resolution;
        if (equal(r->kind, "common") && !r->live)
            fprintf(map, "discard %s COMMON(%s) %lld gc\n", r->definer, name->name,
                    (long long)r->size);
        bool kept =
            equal(r->kind, "script") || (equal(r->kind, "common") && r->live) ||
            ((equal(r->kind, "global") || equal(r->kind, "weak")) && r->definition->section->live);
        if (kept) {
            int64_t value;
            name_value(name, &value);
            OutputSymbol symbol = {value, name->name, r->kind, r->definer, symbols.count};
            PUSH(symbols, symbol);
        }
        const char *status = "-";
        if (equal(r->kind, "script"))
            status = "kept";
        else if (equal(r->kind, "common"))
            status = r->live ? "kept" : "discarded";
        else if (equal(r->kind, "global") || equal(r->kind, "weak"))
            status = r->definition->section->live ? "kept" : "discarded";
        fprintf(xref, "%s %s %s %s %s\n", name->name, r->kind, status, r->definer,
                joined(r->referrers, ","));
    }
    if (symbols.count > 1)
        qsort(symbols.items, (size_t)symbols.count, sizeof(OutputSymbol), symbol_compare);
    for (int i = 0; i < symbols.count; ++i) {
        OutputSymbol symbol = symbols.items[i];
        fprintf(map, "symbol %08llx %s %s %s\n", (unsigned long long)symbol.address, symbol.name,
                symbol.kind, symbol.definer);
    }
    for (int i = 0; i < linker->relocation_lines.count; ++i)
        fprintf(relocations, "%s\n", linker->relocation_lines.items[i]);
    StringList messages = diagnostics(linker);
    for (int i = 0; i < messages.count; ++i)
        fprintf(diagnostic_output, "%s\n", messages.items[i]);
    fclose(image);
    fclose(flash);
    fclose(map);
    fclose(xref);
    fclose(relocations);
    fclose(diagnostic_output);
}
int main(void) {
    Linker *linker = ml_alloc(sizeof(*linker));
    read_script(linker);
    load_inputs(linker);
    resolve(linker);
    collect(linker);
    layout(linker);
    load_addresses(linker);
    define_script_symbols(linker);
    relocate(linker);
    build_images(linker);
    write_reports(linker);
    layout_clear(linker);
    ml_cleanup();
    return 0;
}
