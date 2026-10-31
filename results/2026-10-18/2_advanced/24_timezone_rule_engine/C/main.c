#include "timezone.h"

typedef struct Allocation { struct Allocation *next; max_align_t alignment; } Allocation;
static Allocation *allocations;
static void release_all(void) {
    while (allocations) { Allocation *next = allocations->next; free(allocations); allocations = next; }
}
void *allocate(size_t bytes) {
    static bool registered;
    if (!registered) { atexit(release_all); registered = true; }
    Allocation *block = calloc(1, sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block + 1;
}
static char *formatted(const char *pattern, va_list arguments) {
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    if (length < 0) exit(EXIT_FAILURE);
    char *result = allocate((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, arguments);
    return result;
}
char *format(const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *result = formatted(pattern, arguments);
    va_end(arguments);
    return result;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *part = formatted(pattern, arguments);
    va_end(arguments);
    size_t length = strlen(part);
    if (text->size + length + 1 > text->capacity) {
        size_t capacity = text->capacity ? 2 * text->capacity : 64;
        while (capacity < text->size + length + 1) capacity *= 2;
        char *data = allocate(capacity);
        if (text->size) memcpy(data, text->data, text->size);
        text->data = data;
        text->capacity = capacity;
    }
    memcpy(text->data + text->size, part, length + 1);
    text->size += length;
}
void add_line(Lines *lines, const char *pattern, ...) {
    va_list arguments;
    va_start(arguments, pattern);
    char *line = formatted(pattern, arguments);
    va_end(arguments);
    if (lines->count == lines->capacity) {
        int capacity = lines->capacity ? 2 * lines->capacity : 32;
        char **items = allocate((size_t)capacity * sizeof(*items));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(*items));
        lines->items = items;
        lines->capacity = capacity;
    }
    lines->items[lines->count++] = line;
}
void paragraph(Lines *target, Lines source) {
    if (target->count) add_line(target, "");
    for (int i = 0; i < source.count; ++i) add_line(target, "%s", source.items[i]);
}
char *slice(const char *text, size_t start, size_t length) {
    char *result = allocate(length + 1);
    memcpy(result, text + start, length);
    return result;
}
Lines split_fields(const char *text) {
    Lines fields = {0};
    size_t position = 0;
    while (text[position]) {
        while (text[position] == ' ') ++position;
        if (!text[position]) break;
        size_t start = position;
        while (text[position] && text[position] != ' ') ++position;
        add_line(&fields, "%s", slice(text, start, position - start));
    }
    return fields;
}
static Lines read_lines(const char *name) {
    FILE *file = fopen(format("input/%s", name), "rb");
    if (!file) exit(EXIT_FAILURE);
    Lines lines = {0};
    char buffer[512];
    while (fgets(buffer, sizeof(buffer), file)) {
        size_t size = strlen(buffer);
        if (size && buffer[size - 1] == '\n') buffer[size - 1] = '\0';
        add_line(&lines, "%s", buffer);
    }
    if (ferror(file)) exit(EXIT_FAILURE);
    fclose(file);
    return lines;
}
static char *join(Lines lines, const char *separator) {
    Text text = {0};
    for (int i = 0; i < lines.count; ++i) text_add(&text, "%s%s", i ? separator : "", lines.items[i]);
    return text.data ? text.data : "";
}
static char *names_or_none(Lines names, const char *separator) { return names.count ? join(names, separator) : "none"; }

enum LineKind { UNKNOWN_LINE, RULE_LINE, ZONE_LINE, CONTINUATION, LINK_LINE };
typedef struct ZoneLine {
    Integer offset, save, start, end;
    char *rules_text, *rule_set, *format_text;
    Until *until;
} ZoneLine;
typedef struct Block Block;
typedef struct {
    int number, position; Lines fields; enum LineKind kind;
    Block *block; ZoneLine *zone_line; bool field_error; char *error;
} SourceLine;
struct Block { char *name; int number, count; SourceLine *lines[400]; bool defined; };
typedef struct { char *name; Rule *rules[400]; int count; Instances instances; } RuleSet;
typedef struct Zone {
    char *name; ZoneLine *lines[400]; int count, applied[401]; Lines aliases;
    Timeline timeline;
} Zone;
typedef struct { char *name; Zone *zone; } Alias;
typedef struct {
    SourceLine lines[400]; int line_count;
    Block *blocks[400]; int block_count;
    RuleSet sets[400]; int set_count;
    Zone *zones[400]; int zone_count;
    Alias aliases[400]; int alias_count;
} Database;

static RuleSet *find_set(Database *database, const char *name) {
    for (int i = 0; i < database->set_count; ++i) if (!strcmp(database->sets[i].name, name)) return &database->sets[i];
    return NULL;
}
static Zone *find_zone(Database *database, const char *name, bool aliases) {
    for (int i = 0; i < database->zone_count; ++i) if (!strcmp(database->zones[i]->name, name)) return database->zones[i];
    if (aliases) for (int i = 0; i < database->alias_count; ++i) if (!strcmp(database->aliases[i].name, name)) return database->aliases[i].zone;
    return NULL;
}
static void block_add(Block *block, SourceLine *line) {
    line->block = block;
    line->position = block->count;
    block->lines[block->count++] = line;
}
static bool accepts_continuation(const SourceLine *line) { return (line->kind == ZONE_LINE && line->fields.count >= 6) || (line->kind == CONTINUATION && line->fields.count >= 4); }
static void assemble_lines(Database *database, Lines raw) {
    SourceLine *previous = NULL;
    for (int i = 0; i < raw.count; ++i) {
        char *content = line_content(raw.items[i]);
        if (!content[0]) continue;
        SourceLine *line = &database->lines[database->line_count++];
        line->number = i + 1;
        line->fields = split_fields(content);
        line->kind = content[0] == ' ' ? CONTINUATION : !strcmp(line->fields.items[0], "Rule") ? RULE_LINE : !strcmp(line->fields.items[0], "Zone") ? ZONE_LINE : !strcmp(line->fields.items[0], "Link") ? LINK_LINE : UNKNOWN_LINE;
        if (line->kind == ZONE_LINE) {
            Block *block = allocate(sizeof(*block));
            block->name = line->fields.items[1];
            block->number = line->number;
            block_add(block, line);
            database->blocks[database->block_count++] = block;
        } else if (line->kind == CONTINUATION && previous && previous->block && accepts_continuation(previous)) block_add(previous->block, line);
        previous = line;
    }
}
static void check_rule(Database *database, SourceLine *line) {
    char **fields = line->fields.items;
    Rule *rule = allocate(sizeof(*rule));
    rule->number = line->number;
    rule->fields = line->fields;
    rule->name = fields[1];
    if (!parse_year(fields[2], &rule->from)) line->error = "bad year";
    else if (!parse_to(fields[3], rule->from, &rule->to)) line->error = "bad year";
    else if (strcmp(fields[4], "-")) line->error = "syntax error";
    else if (!parse_month(fields[5], &rule->month)) line->error = "bad month";
    else if (!parse_day_spec(fields[6], rule->month, &rule->day)) line->error = "bad day spec";
    else if (!parse_time(fields[7], &rule->at, &rule->type)) line->error = "bad time";
    else if (!parse_save(fields[8], &rule->save)) line->error = "bad save";
    else if (!parse_letter(fields[9], &rule->letter)) line->error = "bad letter";
    if (line->error) return;
    RuleSet *set = find_set(database, rule->name);
    if (!set) { set = &database->sets[database->set_count++]; set->name = rule->name; }
    set->rules[set->count++] = rule;
}
static ZoneLine *check_zone_line(SourceLine *source) {
    int start = source->kind == ZONE_LINE ? 2 : 0;
    char **fields = source->fields.items + start;
    ZoneLine *line = allocate(sizeof(*line));
    line->rules_text = fields[1]; line->format_text = fields[2]; line->start = NEG_INFINITY; line->end = POS_INFINITY;
    if (!parse_offset(fields[0], &line->offset)) source->error = "bad offset";
    else {
        if (fields[1][0] >= '0' && fields[1][0] <= '9') {
            if (!parse_save(fields[1], &line->save)) source->error = "bad save";
        } else if (strcmp(fields[1], "-")) line->rule_set = fields[1];
        if (!source->error && !check_format(fields[2], line->rule_set != NULL)) source->error = "bad format";
        if (!source->error && source->fields.count > start + 3) line->until = parse_until(source->fields, start + 3, &source->error);
    }
    return source->error ? NULL : line;
}
static void check_fields(Database *database, SourceLine *line) {
    int count = line->fields.count;
    bool valid = line->kind == RULE_LINE ? count == 10 : line->kind == ZONE_LINE ? count >= 5 && count <= 9 : line->kind == CONTINUATION ? line->block && count >= 3 && count <= 7 : line->kind == LINK_LINE && count == 3;
    if (!valid) line->error = "syntax error";
    else if (line->kind == RULE_LINE) check_rule(database, line);
    else if (line->kind == ZONE_LINE || line->kind == CONTINUATION) line->zone_line = check_zone_line(line);
    line->field_error = line->error != NULL;
}
static char *structural_error(Database *database, SourceLine *line, Lines *reserved) {
    ZoneLine *zone_line = line->zone_line;
    if (line->kind == ZONE_LINE) {
        char *name = line->fields.items[1];
        for (int i = 0; i < reserved->count; ++i) if (!strcmp(reserved->items[i], name)) return format("duplicate zone %s", name);
        add_line(reserved, "%s", name);
    }
    if (zone_line->rule_set && !find_set(database, zone_line->rule_set)) return format("unknown rule %s", zone_line->rule_set);
    if (!zone_line->until) return NULL;
    if (line->kind == CONTINUATION) {
        SourceLine *previous = line->block->lines[line->position - 1];
        if (!previous->field_error && zone_line->until->value <= previous->zone_line->until->value) return "until not increasing";
    }
    return line->position + 1 == line->block->count ? "missing continuation" : NULL;
}
static bool same_state(Period first, Period second) { return first.offset == second.offset && first.dst == second.dst && !strcmp(first.abbreviation, second.abbreviation); }
static void add_period(Zone *zone, ZoneLine *line, Integer start, Integer save, const char *letter) {
    Period period = {start, line->offset + save, save != 0, abbreviation(line->format_text, save, letter)};
    Timeline *timeline = &zone->timeline;
    if (timeline->count && same_state(timeline->items[timeline->count - 1], period)) return;
    if (timeline->count == timeline->capacity) {
        int capacity = timeline->capacity ? 2 * timeline->capacity : 64;
        Period *items = allocate((size_t)capacity * sizeof(*items));
        if (timeline->count) memcpy(items, timeline->items, (size_t)timeline->count * sizeof(*items));
        timeline->items = items; timeline->capacity = capacity;
    }
    timeline->items[timeline->count++] = period;
}
static void define_zone(Database *database, Block *block) {
    Zone *zone = allocate(sizeof(*zone));
    zone->name = block->name;
    Integer start = NEG_INFINITY;
    for (int i = 0; i < block->count; ++i) {
        ZoneLine *line = block->lines[i]->zone_line;
        zone->lines[zone->count++] = line;
        line->start = start;
        if (!line->rule_set) {
            if (line->until) line->end = line->until->value - adjustment(line->until->type, line->offset, line->save);
            add_period(zone, line, start, line->save, "");
        } else {
            RuleSet *set = find_set(database, line->rule_set);
            LineRun run = run_instances(set->instances, line->offset, start, line->until);
            line->end = run.end;
            char *letter = "";
            if (run.pre_start) add_period(zone, line, start, run.pre_start->save, run.pre_start->letter);
            else {
                for (int j = 0; j < set->instances.count; ++j) if (!set->instances.items[j].rule->save) { letter = set->instances.items[j].rule->letter; break; }
                add_period(zone, line, start, 0, letter);
            }
            for (int j = 0; j < run.count; ++j) {
                Rule *rule = run.applied[j].rule;
                add_period(zone, line, run.applied[j].time, rule->save, rule->letter);
                ++zone->applied[rule->number];
            }
            free(run.applied);
        }
        start = line->end;
    }
    database->zones[database->zone_count++] = zone;
}
static Database *load_database(Lines raw) {
    Database *database = allocate(sizeof(*database));
    assemble_lines(database, raw);
    for (int i = 0; i < database->line_count; ++i) check_fields(database, &database->lines[i]);
    Lines reserved = {0};
    for (int i = 0; i < database->line_count; ++i) if (database->lines[i].zone_line) database->lines[i].error = structural_error(database, &database->lines[i], &reserved);
    for (int i = 0; i < database->set_count; ++i) database->sets[i].instances = instance_sequence(database->sets[i].rules, database->sets[i].count);
    for (int i = 0; i < database->block_count; ++i) {
        Block *block = database->blocks[i];
        block->defined = true;
        for (int j = 0; j < block->count; ++j) if (block->lines[j]->error) block->defined = false;
        if (block->defined) define_zone(database, block);
    }
    for (int i = 0; i < database->line_count; ++i) {
        SourceLine *line = &database->lines[i];
        if (line->kind != LINK_LINE || line->error) continue;
        char *target = line->fields.items[1], *alias = line->fields.items[2];
        Zone *zone = find_zone(database, target, false);
        if (!zone) line->error = format("unknown link target %s", target);
        else if (find_zone(database, alias, true)) line->error = format("duplicate link %s", alias);
        else {
            database->aliases[database->alias_count++] = (Alias){alias, zone};
            add_line(&zone->aliases, "%s", alias);
        }
    }
    return database;
}

typedef struct { Integer low, high; } Interval;
typedef struct { Interval *items; int count, capacity; } Intervals;
static void interval_add(Intervals *intervals, Integer low, Integer high) {
    if (intervals->count == intervals->capacity) {
        int capacity = intervals->capacity ? 2 * intervals->capacity : 8;
        Interval *items = allocate((size_t)capacity * sizeof(*items));
        if (intervals->count) memcpy(items, intervals->items, (size_t)intervals->count * sizeof(*items));
        intervals->items = items; intervals->capacity = capacity;
    }
    intervals->items[intervals->count++] = (Interval){low, high};
}
static int interval_order(const void *a, const void *b) {
    const Interval *first = a, *second = b;
    if (first->low != second->low) return first->low < second->low ? -1 : 1;
    return (first->high > second->high) - (first->high < second->high);
}
static Intervals merge_intervals(Intervals source) {
    if (source.count > 1) qsort(source.items, (size_t)source.count, sizeof(Interval), interval_order);
    Intervals result = {0};
    for (int i = 0; i < source.count; ++i) {
        Interval item = source.items[i];
        if (result.count && item.low <= result.items[result.count - 1].high) {
            if (item.high > result.items[result.count - 1].high) result.items[result.count - 1].high = item.high;
        } else interval_add(&result, item.low, item.high);
    }
    return result;
}
static Intervals intersect_intervals(Intervals first, Intervals second) {
    Intervals pieces = {0};
    for (int i = 0; i < first.count; ++i) for (int j = 0; j < second.count; ++j) {
        Integer low = first.items[i].low > second.items[j].low ? first.items[i].low : second.items[j].low;
        Integer high = first.items[i].high < second.items[j].high ? first.items[i].high : second.items[j].high;
        if (low < high) interval_add(&pieces, low, high);
    }
    return merge_intervals(pieces);
}
static Integer year_start(int year) { return day_number(year, 1, 1) * 86400; }
static Integer offset_shift(const Timeline *timeline, int index) { return timeline->items[index].offset - timeline->items[index - 1].offset; }
static char *shifts_text(const Timeline *timeline, Integer low, Integer high) {
    int gaps = 0, overlaps = 0, unchanged = 0;
    for (int i = 1; i < timeline->count; ++i) if (timeline->items[i].start >= low && timeline->items[i].start < high) {
        Integer shift = offset_shift(timeline, i);
        gaps += shift > 0; overlaps += shift < 0; unchanged += shift == 0;
    }
    return format("gaps %d, overlaps %d, no shift %d", gaps, overlaps, unchanged);
}
static int transition_count(const Timeline *timeline, Integer low, Integer high) {
    int count = 0;
    for (int i = 1; i < timeline->count; ++i) count += timeline->items[i].start >= low && timeline->items[i].start < high;
    return count;
}
static char *transition_line(const Timeline *timeline, int index) {
    Integer time = timeline->items[index].start, shift = offset_shift(timeline, index);
    char *kind = shift > 0 ? format("gap %s", duration_text(shift)) : shift < 0 ? format("overlap %s", duration_text(-shift)) : "no shift";
    return format("%s (local %s -> %s, %s)", change_text(timeline, index), local_text(time + timeline->items[index - 1].offset), local_text(time + timeline->items[index].offset), kind);
}
static char *candidate_text(const Timeline *timeline, Integer local, int index) {
    return format("%s (%s)", ut_text(local - timeline->items[index].offset), state_text(&timeline->items[index]));
}
static int chosen_candidate(Candidates found, const char *option) {
    if (found.count == 1) return found.indices[0];
    if (found.count == 2 && option) {
        if (!strcmp(option, "EARLIER")) return found.indices[0];
        if (!strcmp(option, "LATER")) return found.indices[1];
    }
    return -1;
}
static char *unresolved_text(const Timeline *timeline, Integer local, Candidates found) {
    if (found.count) return format("AMBIGUOUS %s or %s", candidate_text(timeline, local, found.indices[0]), candidate_text(timeline, local, found.indices[1]));
    int index = skipping_transition(timeline, local);
    Integer time = timeline->items[index].start;
    return format("NONEXISTENT gap %s to %s at %s", local_text(time + timeline->items[index - 1].offset), local_text(time + timeline->items[index].offset), ut_text(time));
}
static Intervals working_hours(const Timeline *timeline, Integer start, Integer end) {
    Intervals pieces = {0};
    int first = period_index(timeline, start - 57600), last = period_index(timeline, end + 57600);
    for (int i = first; i <= last; ++i) {
        Integer low = start - timeline->items[i].offset, high = end - timeline->items[i].offset;
        if (low < timeline->items[i].start) low = timeline->items[i].start;
        if (high > period_end(timeline, i)) high = period_end(timeline, i);
        if (low < high) interval_add(&pieces, low, high);
    }
    return merge_intervals(pieces);
}
enum ArgumentKind { ARG_ZONE, ARG_LOCAL, ARG_UT, ARG_DATE, ARG_YEAR };
static bool parse_value(enum ArgumentKind kind, const char *word, Integer *value) {
    DateTime date = {atoi(slice(word, 0, 4)),0,0,0,0,0};
    if (date.year < 1800 || date.year > 2099) return false;
    if (kind == ARG_YEAR) { *value = date.year; return true; }
    date.month = atoi(slice(word, 5, 2)); date.day = atoi(slice(word, 8, 2));
    if (date.month < 1 || date.month > 12 || date.day < 1 || date.day > days_in_month(date.year, date.month)) return false;
    if (kind == ARG_DATE) { *value = day_number(date.year, date.month, date.day); return true; }
    date.hour = atoi(slice(word, 11, 2)); date.minute = atoi(slice(word, 14, 2)); date.second = atoi(slice(word, 17, 2));
    if (date.hour > 23 || date.minute > 59 || date.second > 59) return false;
    *value = time_value(date);
    return true;
}
typedef struct { Zone *zone; Integer value; } Argument;
typedef struct { Database *database; Integer work_start, work_end; Lines answers, transitions; } QueryRunner;
static char *meeting(Argument *values, char **words, int count, Integer work_start, Integer work_end) {
    Integer start = values[0].value * 86400 + work_start, end = values[0].value * 86400 + work_end;
    Intervals common = working_hours(&values[1].zone->timeline, start, end);
    for (int i = 2; i < count; ++i) common = intersect_intervals(common, working_hours(&values[i].zone->timeline, start, end));
    if (!common.count) return "NONE";
    Lines parts = {0};
    for (int i = 0; i < common.count; ++i) {
        Interval interval = common.items[i];
        Lines members = {0};
        for (int j = 1; j < count; ++j) {
            Timeline *timeline = &values[j].zone->timeline;
            Period period = timeline->items[period_index(timeline, interval.low)];
            add_line(&members, "%s %s %s", words[j], local_text(interval.low + period.offset), period.abbreviation);
        }
        add_line(&parts, "%s to %s (%s) [%s]", ut_text(interval.low), ut_text(interval.high), duration_text(interval.high - interval.low), join(members, ", "));
    }
    return join(parts, "; ");
}
static char *query_answer(QueryRunner *runner, const char *line) {
    Lines fields = split_fields(line);
    char *command = fields.items[0], **words = fields.items + 1, *option = NULL;
    int count = fields.count - 1;
    if ((!strcmp(command, "TOUTC") || !strcmp(command, "CONVERT")) && (!strcmp(words[count - 1], "EARLIER") || !strcmp(words[count - 1], "LATER"))) option = words[--count];
    enum ArgumentKind kinds[100];
    if (!strcmp(command, "MEETING")) {
        kinds[0] = ARG_DATE;
        for (int i = 1; i < count; ++i) kinds[i] = ARG_ZONE;
    } else {
        kinds[0] = ARG_ZONE;
        if (!strcmp(command, "CONVERT")) { kinds[1] = ARG_ZONE; kinds[2] = ARG_LOCAL; }
        else if (!strcmp(command, "TRANSITIONS")) { kinds[1] = ARG_YEAR; kinds[2] = ARG_YEAR; }
        else if (!strcmp(command, "DURATION")) { kinds[1] = ARG_LOCAL; kinds[2] = ARG_LOCAL; }
        else kinds[1] = !strcmp(command, "TOUTC") ? ARG_LOCAL : ARG_UT;
    }
    Argument values[100] = {{0}};
    for (int i = 0; i < count; ++i) {
        if (kinds[i] == ARG_ZONE) {
            values[i].zone = find_zone(runner->database, words[i], true);
            if (!values[i].zone) return format("ERROR unknown zone %s", words[i]);
        } else if (!parse_value(kinds[i], words[i], &values[i].value)) return format("ERROR invalid value %s", words[i]);
    }
    if (!strcmp(command, "MEETING")) return meeting(values, words, count, runner->work_start, runner->work_end);
    Timeline *timeline = &values[0].zone->timeline;
    Integer time = values[1].value;
    if (!strcmp(command, "TOLOCAL")) {
        Period period = timeline->items[period_index(timeline, time)];
        return format("%s (%s)", local_text(time + period.offset), state_text(&period));
    }
    if (!strcmp(command, "OFFSET")) {
        int index = period_index(timeline, time);
        Text text = {0};
        text_add(&text, "%s", state_text(&timeline->items[index]));
        if (index) text_add(&text, " since %s", ut_text(timeline->items[index].start));
        if (index + 1 < timeline->count) text_add(&text, " until %s", ut_text(timeline->items[index + 1].start));
        return text.data;
    }
    if (!strcmp(command, "TRANSITIONS")) {
        if (values[1].value > values[2].value) return "ERROR invalid range";
        Integer low = year_start((int)values[1].value), high = year_start((int)values[2].value + 1);
        Lines block = {0};
        add_line(&block, "%s", line);
        for (int i = 1; i < timeline->count; ++i) if (timeline->items[i].start >= low && timeline->items[i].start < high) add_line(&block, "%s", transition_line(timeline, i));
        add_line(&block, "%s", shifts_text(timeline, low, high));
        paragraph(&runner->transitions, block);
        return format("transitions: %d", transition_count(timeline, low, high));
    }
    if (!strcmp(command, "DURATION")) {
        Period periods[2];
        for (int i = 0; i < 2; ++i) {
            Candidates found = candidates(timeline, values[i + 1].value);
            if (found.count != 1) return format("%s %s", found.count ? "AMBIGUOUS" : "NONEXISTENT", words[i + 1]);
            periods[i] = timeline->items[found.indices[0]];
        }
        Integer elapsed = (values[2].value - periods[1].offset) - (values[1].value - periods[0].offset);
        return format("%lld s (%s), wall clock %s, offset change %s", elapsed, duration_text(elapsed), duration_text(values[2].value - values[1].value), offset_text(periods[1].offset - periods[0].offset));
    }
    bool convert = !strcmp(command, "CONVERT");
    Integer local = values[convert ? 2 : 1].value;
    Candidates found = candidates(timeline, local);
    int index = chosen_candidate(found, option);
    if (index < 0) return unresolved_text(timeline, local, found);
    if (!convert) return candidate_text(timeline, local, index);
    Integer utc = local - timeline->items[index].offset;
    Timeline *target = &values[1].zone->timeline;
    Period period = target->items[period_index(target, utc)];
    Integer target_local = utc + period.offset, shift = floor_divide(target_local, 86400) - floor_divide(local, 86400);
    return format("%s (%s) at %s, day shift %s%lld", local_text(target_local), state_text(&period), ut_text(utc), shift > 0 ? "+" : "", shift);
}

static Lines error_lines(const Database *database) {
    Lines lines = {0};
    for (int i = 0; i < database->line_count; ++i) if (database->lines[i].error) add_line(&lines, "line %d: %s", database->lines[i].number, database->lines[i].error);
    return lines;
}
static Lines zone_rule_sets(const Zone *zone) {
    Lines names = {0};
    for (int i = 0; i < zone->count; ++i) {
        char *name = zone->lines[i]->rule_set;
        if (!name) continue;
        bool present = false;
        for (int j = 0; j < names.count; ++j) if (!strcmp(names.items[j], name)) present = true;
        if (!present) add_line(&names, "%s", name);
    }
    return names;
}
static bool uses_rule_set(const Zone *zone, const char *name) {
    for (int i = 0; i < zone->count; ++i) if (zone->lines[i]->rule_set && !strcmp(zone->lines[i]->rule_set, name)) return true;
    return false;
}
static Lines database_block(const Database *database) {
    int rule_count = 0, valid_rules = 0, link_count = 0, valid_links = 0, zone_lines = 0;
    for (int i = 0; i < database->line_count; ++i) {
        SourceLine line = database->lines[i];
        if (line.kind == RULE_LINE) { ++rule_count; valid_rules += !line.error; }
        if (line.kind == LINK_LINE) { ++link_count; valid_links += !line.error; }
    }
    for (int i = 0; i < database->zone_count; ++i) zone_lines += database->zones[i]->count;
    Lines unused = {0}, invalid = {0};
    int zone_counts[400] = {0};
    for (int i = 0; i < database->set_count; ++i) {
        for (int j = 0; j < database->zone_count; ++j) zone_counts[i] += uses_rule_set(database->zones[j], database->sets[i].name);
        if (!zone_counts[i]) add_line(&unused, "%s", database->sets[i].name);
    }
    for (int i = 0; i < database->block_count; ++i) if (!database->blocks[i]->defined) add_line(&invalid, "%s (line %d)", database->blocks[i]->name, database->blocks[i]->number);
    Lines lines = {0};
    add_line(&lines, "DATABASE");
    add_line(&lines, "rule lines: %d valid, %d invalid", valid_rules, rule_count - valid_rules);
    add_line(&lines, "zones: %d defined, %d invalid", database->zone_count, database->block_count - database->zone_count);
    add_line(&lines, "zone lines: %d in defined zones", zone_lines);
    add_line(&lines, "links: %d defined, %d invalid", valid_links, link_count - valid_links);
    add_line(&lines, "errors: %d", error_lines(database).count);
    add_line(&lines, "unused rules: %s", names_or_none(unused, " "));
    add_line(&lines, "invalid zones: %s", names_or_none(invalid, ", "));
    for (int i = 0; i < database->set_count; ++i) {
        const RuleSet *set = &database->sets[i];
        int first = 2099, last = 1800;
        bool has_max = false;
        for (int j = 0; j < set->count; ++j) {
            Rule *rule = set->rules[j];
            if (rule->from < first) first = rule->from;
            if (rule->to > last) last = rule->to;
            has_max |= !strcmp(rule->fields.items[3], "max");
        }
        add_line(&lines, "rule set %s: lines %d, years %d-%s, zones %d", set->name, set->count, first, has_max ? "max" : format("%d", last), zone_counts[i]);
    }
    return lines;
}
static void dst_lines(Lines *lines, const Timeline *timeline, Integer reference) {
    int first_year = 0, last_year = 0;
    int year = split_time(reference).year;
    Integer low = year_start(year), high = year_start(year + 1);
    Intervals pieces = {0};
    for (int i = 0; i < timeline->count; ++i) {
        Period period = timeline->items[i];
        if (!period.dst) continue;
        int start_year = split_time(period.start).year;
        if (!first_year || start_year < first_year) first_year = start_year;
        if (!last_year || start_year > last_year) last_year = start_year;
        Integer start = period.start > low ? period.start : low, end = period_end(timeline, i) < high ? period_end(timeline, i) : high;
        if (start < end) interval_add(&pieces, start, end);
    }
    if (first_year) add_line(lines, "dst years: %d-%d", first_year, last_year);
    else add_line(lines, "dst years: none");
    Intervals merged = merge_intervals(pieces);
    Integer total = 0;
    for (int i = 0; i < merged.count; ++i) {
        Interval piece = merged.items[i];
        add_line(lines, "dst period: %s to %s (%s)", ut_text(piece.low), ut_text(piece.high), duration_text(piece.high - piece.low));
        total += piece.high - piece.low;
    }
    add_line(lines, "dst total %d: %s", year, duration_text(total));
}
static unsigned long long state_hash(Period period) {
    unsigned long long hash = (unsigned long long)period.offset;
    hash = (hash ^ (unsigned long long)period.dst) * 1099511628211ULL;
    for (const unsigned char *p = (const unsigned char *)period.abbreviation; *p; ++p) hash = (hash ^ *p) * 1099511628211ULL;
    return hash;
}
static void state_lines(Lines *lines, const Timeline *timeline) {
    size_t capacity = 1;
    while (capacity < 2 * (size_t)timeline->count) capacity *= 2;
    int *buckets = malloc(capacity * sizeof(*buckets));
    int *firsts = malloc((size_t)timeline->count * sizeof(*firsts));
    int *counts = calloc((size_t)timeline->count, sizeof(*counts));
    if (!buckets || !firsts || !counts) exit(1);
    for (size_t i = 0; i < capacity; ++i) buckets[i] = -1;
    int distinct = 0;
    for (int i = 0; i < timeline->count; ++i) {
        size_t bucket = (size_t)(state_hash(timeline->items[i]) & (capacity - 1));
        while (buckets[bucket] >= 0 && !same_state(timeline->items[i], timeline->items[firsts[buckets[bucket]]])) bucket = (bucket + 1) & (capacity - 1);
        if (buckets[bucket] < 0) {
            buckets[bucket] = distinct;
            firsts[distinct++] = i;
        }
        ++counts[buckets[bucket]];
    }
    for (int i = 0; i < distinct; ++i) add_line(lines, "state %s, periods %d", state_text(&timeline->items[firsts[i]]), counts[i]);
    free(counts);
    free(firsts);
    free(buckets);
}
static Lines zone_block(Database *database, Zone *zone, Integer reference) {
    Timeline *timeline = &zone->timeline;
    Lines lines = {0};
    add_line(&lines, "ZONE %s", zone->name);
    add_line(&lines, "aliases: %s", names_or_none(zone->aliases, " "));
    for (int i = 0; i < zone->count; ++i) {
        ZoneLine *line = zone->lines[i];
        Text text = {0};
        const char *rules = line->rule_set ? line->rule_set : !strcmp(line->rules_text, "-") ? "-" : clock_text(line->save);
        text_add(&text, "line %d: %s %s %s", i + 1, offset_text(line->offset), rules, line->format_text);
        if (i) text_add(&text, " from %s", ut_text(line->start));
        if (line->until) {
            Until *until = line->until;
            text_add(&text, " until %s %s %s %s%c = %s", until->year_text, until->month_text, until->day_text, clock_text(until->time), until->type, ut_text(line->end));
        }
        text_add(&text, ", transitions %d", transition_count(timeline, line->start, line->end));
        add_line(&lines, "%s", text.data);
    }
    Lines sets = zone_rule_sets(zone);
    for (int i = 0; i < sets.count; ++i) {
        RuleSet *set = find_set(database, sets.items[i]);
        for (int j = 0; j < set->count; ++j) {
            Rule *rule = set->rules[j];
            char **fields = rule->fields.items;
            add_line(&lines, "rule %s %s %s %s %s %s%c %s %s, applied %d", rule->name, fields[2], fields[3], fields[5], fields[6], clock_text(rule->at), rule->type, clock_text(rule->save), fields[9], zone->applied[rule->number]);
        }
    }
    Integer minimum = timeline->items[0].offset, maximum = minimum;
    for (int i = 1; i < timeline->count; ++i) {
        if (timeline->items[i].offset < minimum) minimum = timeline->items[i].offset;
        if (timeline->items[i].offset > maximum) maximum = timeline->items[i].offset;
    }
    add_line(&lines, "offset range: %s to %s", offset_text(minimum), offset_text(maximum));
    state_lines(&lines, timeline);
    int index = period_index(timeline, reference), line_number = 0;
    for (int i = 0; i < zone->count; ++i) if (zone->lines[i]->start <= reference && reference < zone->lines[i]->end) { line_number = i + 1; break; }
    Period period = timeline->items[index];
    add_line(&lines, "reference: %s (%s), line %d", local_text(reference + period.offset), state_text(&period), line_number);
    add_line(&lines, "previous transition: %s", index ? change_text(timeline, index) : "none");
    add_line(&lines, "next transition: %s", index + 1 < timeline->count ? change_text(timeline, index + 1) : "none");
    add_line(&lines, "transitions: %d, %s", timeline->count - 1, shifts_text(timeline, NEG_INFINITY, POS_INFINITY));
    dst_lines(&lines, timeline, reference);
    return lines;
}
static Lines indented(Lines source) {
    Lines result = {0};
    for (int i = 0; i < source.count; ++i) add_line(&result, "%s%s", i ? "  " : "", source.items[i]);
    return result;
}
static int zone_order(const void *first, const void *second) { return strcmp((*(Zone *const *)first)->name, (*(Zone *const *)second)->name); }
static Integer clock_seconds(const char *text) { return atoi(slice(text, 0, 2)) * 3600 + atoi(text + 3) * 60; }

int main(void) {
    Database *database = load_database(read_lines("tzdata.txt"));
    Lines parameters = read_lines("params.txt"), reference_fields = split_fields(parameters.items[0]), workday = split_fields(parameters.items[1]);
    Integer reference;
    parse_value(ARG_UT, reference_fields.items[1], &reference);
    QueryRunner runner = {database, clock_seconds(workday.items[1]), clock_seconds(workday.items[2]), {0}, {0}};
    Lines queries = read_lines("queries.txt");
    for (int i = 0; i < queries.count; ++i) add_line(&runner.answers, "%s => %s", queries.items[i], query_answer(&runner, queries.items[i]));
    Lines summary = {0};
    paragraph(&summary, indented(database_block(database)));
    Zone *ordered[400];
    memcpy(ordered, database->zones, (size_t)database->zone_count * sizeof(Zone *));
    if (database->zone_count > 1) qsort(ordered, (size_t)database->zone_count, sizeof(Zone *), zone_order);
    for (int i = 0; i < database->zone_count; ++i) paragraph(&summary, indented(zone_block(database, ordered[i], reference)));
    write_lines("answers.txt", runner.answers);
    write_lines("errors.txt", error_lines(database));
    write_lines("transitions.txt", runner.transitions);
    write_lines("zone_summary.txt", summary);
    return 0;
}
