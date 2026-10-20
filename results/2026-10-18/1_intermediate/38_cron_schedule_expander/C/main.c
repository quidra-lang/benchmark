#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

enum { DAY_COUNT = 36526, MINUTES_PER_DAY = 1440, MAX_WINDOW = 44640 };
static const char *field_names[] = {"minute", "hour", "day-of-month", "month", "day-of-week"};
static const int lower[] = {0, 0, 1, 1, 0}, upper[] = {59, 23, 31, 12, 7};
static const char *month_names[] = {"", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
static const char *week_names[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
static const char *week_short[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
static const char *month_codes[] = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"};
static const char *week_codes[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};

typedef struct Allocation {
    struct Allocation *next;
    max_align_t alignment;
    unsigned char data[];
} Allocation;
static Allocation *allocations;
static jmp_buf command_error;
static char error_message[128];

static void *temporary(size_t bytes) {
    Allocation *block = malloc(sizeof(*block) + bytes);
    if (!block) exit(EXIT_FAILURE);
    block->next = allocations;
    allocations = block;
    return block->data;
}
static void clear_temporaries(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations);
        allocations = next;
    }
}
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *result = temporary((size_t)length + 1);
    vsnprintf(result, (size_t)length + 1, pattern, args);
    va_end(args);
    return result;
}
static void fail(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    vsnprintf(error_message, sizeof(error_message), pattern, args);
    va_end(args);
    longjmp(command_error, 1);
}
static char *slice(const char *text, size_t length) {
    char *result = temporary(length + 1);
    memcpy(result, text, length);
    result[length] = '\0';
    return result;
}
static bool digits(const char *text, int least, int most) {
    size_t length = strlen(text);
    if (length < (size_t)least || length > (size_t)most) return false;
    for (size_t i = 0; i < length; i++) if (text[i] < '0' || text[i] > '9') return false;
    return true;
}
static char *join(const char *const *parts, int count, const char *separator) {
    size_t length = 1;
    for (int i = 0; i < count; i++) length += strlen(parts[i]) + strlen(separator);
    char *result = temporary(length), *at = result;
    for (int i = 0; i < count; i++) {
        if (i) { size_t n = strlen(separator); memcpy(at, separator, n); at += n; }
        size_t n = strlen(parts[i]); memcpy(at, parts[i], n); at += n;
    }
    *at = '\0';
    return result;
}
static char *word_list(const char *const *parts, int count, bool disjunction) {
    if (count < 2) return join(parts, count, "");
    const char *prefix = join(parts, count - 1, ", ");
    return format("%s %s %s", prefix, disjunction ? "or" : "and", parts[count - 1]);
}

typedef struct { int year, month, day, weekday, length; } Date;
static Date calendar[DAY_COUNT];
static bool holidays[DAY_COUNT];
static int holiday_count;
static bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
static int month_length(int year, int month) {
    static const int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[month - 1] + (month == 2 && leap(year));
}
static int day_number(int year, int month, int day) {
    int result = day - 1;
    for (int y = 2000; y < year; y++) result += leap(y) ? 366 : 365;
    for (int m = 1; m < month; m++) result += month_length(year, m);
    return result;
}
static void init_calendar(void) {
    int index = 0;
    for (int year = 2000; index < DAY_COUNT; year++) {
        for (int month = 1; month <= 12 && index < DAY_COUNT; month++) {
            int length = month_length(year, month);
            for (int day = 1; day <= length && index < DAY_COUNT; day++, index++)
                calendar[index] = (Date){year, month, day, (index + 6) % 7, length};
        }
    }
}
static bool numeric_pattern(const char *text, const char *pattern) {
    if (strlen(text) != strlen(pattern)) return false;
    for (int i = 0; pattern[i]; i++) {
        if (pattern[i] == '#') { if (text[i] < '0' || text[i] > '9') return false; }
        else if (text[i] != pattern[i]) return false;
    }
    return true;
}
static int date_argument(const char *text, const char *reason) {
    if (!numeric_pattern(text, "####-##-##")) fail("%s", reason);
    int year = atoi(text), month = atoi(text + 5), day = atoi(text + 8);
    if (year < 2001 || year > 2098 || month < 1 || month > 12 || day < 1 || day > month_length(year, month)) fail("%s", reason);
    return day_number(year, month, day);
}
static int datetime_argument(char **words, int at) {
    int day = date_argument(words[at], "invalid datetime");
    const char *time = words[at + 1];
    if (!numeric_pattern(time, "##:##")) fail("invalid datetime");
    int hour = atoi(time), minute = atoi(time + 3);
    if (hour > 23 || minute > 59) fail("invalid datetime");
    return day * MINUTES_PER_DAY + hour * 60 + minute;
}
static int month_argument(const char *text) {
    if (!numeric_pattern(text, "####-##")) fail("invalid month");
    int year = atoi(text), month = atoi(text + 5);
    if (year < 2001 || year > 2098 || month < 1 || month > 12) fail("invalid month");
    return day_number(year, month, 1);
}
static const char *date_text(int day) {
    Date date = calendar[day];
    return format("%04d-%02d-%02d %s", date.year, date.month, date.day, week_short[date.weekday]);
}
static const char *datetime_text(int minute) {
    Date date = calendar[minute / MINUTES_PER_DAY];
    return format("%04d-%02d-%02d %02d:%02d %s", date.year, date.month, date.day, minute % MINUTES_PER_DAY / 60, minute % 60, week_short[date.weekday]);
}
static const char *span_text(int value) { return format("%dd%02dh%02dm", value / MINUTES_PER_DAY, value % MINUTES_PER_DAY / 60, value % 60); }

typedef enum { LAST_DAY, LAST_WORKDAY, OFFSET_DAY, NEAREST_WORKDAY, NTH_WEEKDAY, LAST_WEEKDAY } SpecialKind;
typedef struct { SpecialKind kind; int value, n; } Special;
typedef struct {
    bool values[60];
    int count, special_count;
    Special special[50];
    bool restricted;
} Field;
typedef struct {
    Field fields[5];
    int times[MINUTES_PER_DAY], time_count;
    bool disjunction;
    char text[101], expanded[101];
} Cron;
typedef enum { ALLOW, FORBID, REPLACE } Policy;
static const char *policy_names[] = {"ALLOW", "FORBID", "REPLACE"};
typedef struct { char id[17]; Cron cron; bool enabled; int duration; Policy policy; } Job;
static Job jobs[40];
static int job_count;

static void field_error(int field, const char *reason) { fail("%s %s", field_names[field], reason); }
static int field_value(int field, const char *text) {
    if (field == 3) for (int i = 0; i < 12; i++) if (strcmp(text, month_codes[i]) == 0) return i + 1;
    if (field == 4) for (int i = 0; i < 7; i++) if (strcmp(text, week_codes[i]) == 0) return i;
    if (!digits(text, 1, 2)) field_error(field, "invalid value");
    int value = atoi(text);
    if (value < lower[field] || value > upper[field]) field_error(field, "out of range");
    return value;
}
static int special_number(int field, const char *text, int width, int maximum) {
    if (!digits(text, 1, width)) field_error(field, "invalid value");
    int value = atoi(text);
    if (value < 1 || value > maximum) field_error(field, "out of range");
    return value;
}
static void add_special(Field *field, Special item) {
    for (int i = 0; i < field->special_count; i++) {
        Special old = field->special[i];
        if (old.kind == item.kind && old.value == item.value && old.n == item.n) return;
    }
    field->special[field->special_count++] = item;
}
static void parse_item(Field *result, int field, char *item) {
    size_t length = strlen(item);
    if (!length) field_error(field, "empty item");
    if (field == 2 && (item[0] == 'L' || item[length - 1] == 'W')) {
        Special special = {LAST_DAY, 0, 0};
        if (strcmp(item, "L") == 0) special.kind = LAST_DAY;
        else if (strcmp(item, "LW") == 0) special.kind = LAST_WORKDAY;
        else if (strncmp(item, "L-", 2) == 0) { special.kind = OFFSET_DAY; special.value = special_number(field, item + 2, 2, 30); }
        else if (item[length - 1] == 'W') { special.kind = NEAREST_WORKDAY; special.value = special_number(field, slice(item, length - 1), 2, 31); }
        else field_error(field, "invalid value");
        add_special(result, special);
        return;
    }
    char *hash = strchr(item, '#');
    if (field == 4 && hash) {
        int value = field_value(field, slice(item, (size_t)(hash - item)));
        int n = special_number(field, hash + 1, 1, 5);
        add_special(result, (Special){NTH_WEEKDAY, value % 7, n});
        return;
    }
    if (field == 4 && length >= 2 && item[length - 1] == 'L') {
        int value = field_value(field, slice(item, length - 1));
        add_special(result, (Special){LAST_WEEKDAY, value % 7, 0});
        return;
    }
    char *slash = strchr(item, '/');
    char *base = slash ? slice(item, (size_t)(slash - item)) : item;
    int first, last, step = 1;
    if (strcmp(base, "*") == 0) { first = lower[field]; last = upper[field]; }
    else {
        char *dash = strchr(base, '-');
        if (dash) {
            first = field_value(field, slice(base, (size_t)(dash - base)));
            last = field_value(field, dash + 1);
            if (first > last) field_error(field, "invalid range");
        } else { first = field_value(field, base); last = slash ? upper[field] : first; }
    }
    if (slash) {
        if (!digits(slash + 1, 1, 2) || atoi(slash + 1) < 1) field_error(field, "invalid step");
        step = atoi(slash + 1);
    }
    for (int value = first; value <= last; value += step) {
        int normalized = field == 4 ? value % 7 : value;
        if (!result->values[normalized]) { result->values[normalized] = true; result->count++; }
    }
}
static void parse_field(Field *result, int field, const char *text) {
    result->restricted = text[0] != '*';
    const char *at = text;
    for (;;) {
        const char *comma = strchr(at, ',');
        size_t length = comma ? (size_t)(comma - at) : strlen(at);
        parse_item(result, field, slice(at, length));
        if (!comma) break;
        at = comma + 1;
    }
}
static Cron parse_cron(char **words, int count) {
    Cron cron = {0};
    strcpy(cron.text, join((const char *const *)words, count, " "));
    const char *fields[5];
    if (count == 1 && words[0][0] == '@') {
        static const char *macros[] = {"@yearly", "@annually", "@monthly", "@weekly", "@daily", "@midnight", "@hourly"};
        static const char *expansions[][5] = {
            {"0", "0", "1", "1", "*"}, {"0", "0", "1", "1", "*"}, {"0", "0", "1", "*", "*"},
            {"0", "0", "*", "*", "0"}, {"0", "0", "*", "*", "*"}, {"0", "0", "*", "*", "*"}, {"0", "*", "*", "*", "*"}
        };
        int found = -1;
        for (int i = 0; i < 7; i++) if (strcmp(words[0], macros[i]) == 0) found = i;
        if (found < 0) fail("unknown macro");
        for (int i = 0; i < 5; i++) fields[i] = expansions[found][i];
    } else {
        if (count != 5) fail("field count");
        for (int i = 0; i < 5; i++) fields[i] = words[i];
    }
    strcpy(cron.expanded, join(fields, 5, " "));
    for (int i = 0; i < 5; i++) parse_field(&cron.fields[i], i, fields[i]);
    cron.disjunction = cron.fields[2].restricted && cron.fields[4].restricted;
    for (int hour = 0; hour < 24; hour++) if (cron.fields[1].values[hour])
        for (int minute = 0; minute < 60; minute++) if (cron.fields[0].values[minute]) cron.times[cron.time_count++] = hour * 60 + minute;
    return cron;
}

static int nearest_workday(int first, int day, int length) {
    int weekday = (first + day + 5) % 7;
    if (weekday == 6) return day == 1 ? 3 : day - 1;
    if (weekday == 0) return day == length ? day - 2 : day + 1;
    return day;
}
static bool day_condition(const Cron *cron, int day, bool *dom, bool *dow) {
    Date date = calendar[day];
    const Field *d = &cron->fields[2], *w = &cron->fields[4];
    *dom = d->values[date.day];
    *dow = w->values[date.weekday];
    int first = day - date.day + 1;
    for (int i = 0; i < d->special_count; i++) {
        Special item = d->special[i];
        int target = 0;
        switch (item.kind) {
            case LAST_DAY: target = date.length; break;
            case LAST_WORKDAY: target = nearest_workday(first, date.length, date.length); break;
            case OFFSET_DAY: target = date.length - item.value; break;
            case NEAREST_WORKDAY:
                if (item.value <= date.length) target = nearest_workday(first, item.value, date.length);
                break;
            default: break;
        }
        if (target == date.day) *dom = true;
    }
    for (int i = 0; i < w->special_count; i++) {
        Special item = w->special[i];
        if (item.value == date.weekday &&
            (item.kind == NTH_WEEKDAY ? (date.day - 1) / 7 + 1 == item.n : date.day + 7 > date.length)) *dow = true;
    }
    return cron->disjunction ? *dom || *dow : *dom && *dow;
}
static bool scheduled_day(const Cron *cron, int day) {
    bool dom, dow;
    return cron->fields[3].values[calendar[day].month] && day_condition(cron, day, &dom, &dow);
}
typedef struct { int *items, count; } Times;
static Times fire_times(const Job *job, int lo, int hi, int limit, bool reverse) {
    int capacity = limit ? limit : hi - lo + 1;
    Times result = {temporary((size_t)capacity * sizeof(int)), 0};
    int first_day = lo / MINUTES_PER_DAY, last_day = hi / MINUTES_PER_DAY;
    int step = reverse ? -1 : 1;
    for (int day = reverse ? last_day : first_day; day >= first_day && day <= last_day; day += step) {
        if (holidays[day] || !scheduled_day(&job->cron, day)) continue;
        for (int i = reverse ? job->cron.time_count - 1 : 0; i >= 0 && i < job->cron.time_count; i += step) {
            int time = day * MINUTES_PER_DAY + job->cron.times[i];
            if (time < lo || time > hi) continue;
            result.items[result.count++] = time;
            if (limit && result.count == limit) return result;
        }
    }
    return result;
}
static const char *special_text(Special item) {
    switch (item.kind) {
        case LAST_DAY: return "L";
        case LAST_WORKDAY: return "LW";
        case OFFSET_DAY: return format("L-%d", item.value);
        case NEAREST_WORKDAY: return format("%dW", item.value);
        case NTH_WEEKDAY: return format("%d#%d", item.value, item.n);
        case LAST_WEEKDAY: return format("%dL", item.value);
    }
    return "";
}
static const char *value_name(int field, int value) {
    if (field == 3) return month_names[value];
    if (field == 4) return week_names[value];
    return format("%d", value);
}
static const char *value_list(const Field *field, int index, bool disjunction) {
    const char *parts[60];
    int count = 0, maximum = index == 4 ? 6 : upper[index];
    for (int first = lower[index]; first <= maximum; first++) {
        if (!field->values[first]) continue;
        int last = first;
        while (last < maximum && field->values[last + 1]) last++;
        if (last - first >= 2) parts[count++] = format("%s through %s", value_name(index, first), value_name(index, last));
        else for (int value = first; value <= last; value++) parts[count++] = value_name(index, value);
        first = last;
    }
    return word_list(parts, count, disjunction);
}
static int stepped(const Field *field, int maximum) {
    if (field->count < 2 || !field->values[0]) return 0;
    int step = 1;
    while (!field->values[step]) step++;
    if (step < 2) return 0;
    for (int i = 0; i <= maximum; i++) if (field->values[i] != (i % step == 0)) return 0;
    return step;
}
static const char *dom_phrase(const Field *field) {
    const char *parts[51];
    int count = 0;
    if (field->count) parts[count++] = format("%s %s", field->count == 1 ? "day" : "days", value_list(field, 2, false));
    for (int i = 0; i < field->special_count; i++) {
        Special item = field->special[i];
        switch (item.kind) {
            case LAST_DAY: parts[count++] = "the last day"; break;
            case LAST_WORKDAY: parts[count++] = "the last weekday"; break;
            case OFFSET_DAY: parts[count++] = format("%d %s before the last day", item.value, item.value == 1 ? "day" : "days"); break;
            case NEAREST_WORKDAY: parts[count++] = format("the weekday nearest day %d", item.value); break;
            default: break;
        }
    }
    return format("%s of the month", word_list(parts, count, false));
}
static const char *dow_phrase(const Field *field, bool disjunction) {
    static const char *ordinals[] = {"", "1st", "2nd", "3rd", "4th", "5th"};
    const char *parts[51];
    int count = 0;
    if (field->count) parts[count++] = value_list(field, 4, disjunction);
    for (int i = 0; i < field->special_count; i++) {
        Special item = field->special[i];
        parts[count++] = item.kind == NTH_WEEKDAY
            ? format("the %s %s", ordinals[item.n], week_names[item.value])
            : format("the last %s", week_names[item.value]);
    }
    return format("%s%s", word_list(parts, count, disjunction), field->special_count ? " of the month" : "");
}
static const char *description(const Cron *cron) {
    const Field *minute = &cron->fields[0], *hour = &cron->fields[1], *dom = &cron->fields[2], *month = &cron->fields[3], *dow = &cron->fields[4];
    const char *time, *day = "", *months = "";
    if (cron->time_count <= 4) {
        const char *parts[4];
        for (int i = 0; i < cron->time_count; i++) parts[i] = format("%02d:%02d", cron->times[i] / 60, cron->times[i] % 60);
        time = format("At %s", word_list(parts, cron->time_count, false));
    } else {
        int step = stepped(minute, 59);
        if (minute->count == 60) time = "Every minute";
        else if (step) time = format("Every %d minutes", step);
        else time = format("At %s %s", minute->count == 1 ? "minute" : "minutes", value_list(minute, 0, false));
        if (hour->count == 24) {
            if (strncmp(time, "At minute", 9) == 0) time = format("%s of every hour", time);
        } else {
            step = stepped(hour, 23);
            int first = 0, last = 23;
            while (!hour->values[first]) first++;
            while (!hour->values[last]) last--;
            if (step) time = format("%s, every %d hours", time, step);
            else if (last - first + 1 == hour->count) time = format("%s, between %02d:00 and %02d:59", time, first, last);
            else time = format("%s, during hours %s", time, value_list(hour, 1, false));
        }
    }
    bool full_dom = dom->count == 31, full_dow = dow->count == 7;
    if (cron->disjunction) {
        if (!full_dom && !full_dow) day = format(", on %s or on %s", dom_phrase(dom), dow_phrase(dow, false));
    } else if (!full_dom && !full_dow) day = format(", on %s if it is %s", dom_phrase(dom), dow_phrase(dow, true));
    else if (!full_dom) day = format(", on %s", dom_phrase(dom));
    else if (!full_dow) day = format(", on %s", dow_phrase(dow, false));
    if (month->count != 12) months = format(", in %s", value_list(month, 3, false));
    return format("%s%s%s", time, day, months);
}

static int find_job(const char *id) {
    for (int i = 0; i < job_count; i++) if (strcmp(jobs[i].id, id) == 0) return i;
    return -1;
}
static Job *job_argument(const char *id) {
    int index = find_job(id);
    if (index < 0) fail("unknown job");
    return &jobs[index];
}
static void new_id(const char *id) {
    size_t length = strlen(id);
    if (length < 1 || length > 16 || id[0] < 'a' || id[0] > 'z') fail("invalid id");
    for (size_t i = 1; i < length; i++)
        if (!(id[i] >= 'a' && id[i] <= 'z') && !(id[i] >= '0' && id[i] <= '9') && id[i] != '_') fail("invalid id");
    if (find_job(id) >= 0) fail("duplicate job");
}
static int positive_argument(const char *text, int width, int maximum, const char *reason) {
    if (!digits(text, 1, width) || text[0] == '0') fail("%s", reason);
    int result = atoi(text);
    if (result > maximum) fail("%s", reason);
    return result;
}
static int compare_jobs(const void *left, const void *right) {
    return strcmp((*(Job *const *)left)->id, (*(Job *const *)right)->id);
}
static int ordered_jobs(Job **result, bool enabled_only) {
    int count = 0;
    for (int i = 0; i < job_count; i++) if (!enabled_only || jobs[i].enabled) result[count++] = &jobs[i];
    qsort(result, (size_t)count, sizeof(*result), compare_jobs);
    return count;
}
static int bit_count(uint64_t bits) {
    int count = 0;
    while (bits) { bits &= bits - 1; count++; }
    return count;
}
static uint64_t *timeline(Job **ordered, int count, int lo, int hi) {
    size_t bytes = (size_t)(hi - lo + 1) * sizeof(uint64_t);
    uint64_t *result = temporary(bytes);
    memset(result, 0, bytes);
    for (int i = 0; i < count; i++) {
        Times times = fire_times(ordered[i], lo, hi, 0, false);
        for (int j = 0; j < times.count; j++) result[times.items[j] - lo] |= UINT64_C(1) << i;
    }
    return result;
}

typedef enum {
    JOB, VALIDATE, REMOVE, RENAME, ENABLE, DISABLE, RUNTIME, LIST, EXPAND, DESCRIBE,
    MATCH, NEXT, PREV, COUNT, GAP, OVERLAP, TIMELINE, CONFLICTS, WEEK, CALENDAR,
    SIMULATE, EXCLUDE, INCLUDE, HOLIDAYS
} Command;
static const char *command_names[] = {
    "JOB", "VALIDATE", "REMOVE", "RENAME", "ENABLE", "DISABLE", "RUNTIME", "LIST", "EXPAND", "DESCRIBE",
    "MATCH", "NEXT", "PREV", "COUNT", "GAP", "OVERLAP", "TIMELINE", "CONFLICTS", "WEEK", "CALENDAR",
    "SIMULATE", "EXCLUDE", "INCLUDE", "HOLIDAYS"
};
static const int word_counts[] = {-3, -2, 2, 3, 2, 2, 4, 1, 3, 2, 4, 5, 5, 6, 4, 7, 5, 5, 2, 3, 5, 2, 2, 1};
static void execute(char **words, int count) {
    int code = -1;
    for (int i = 0; i < 24; i++) if (strcmp(words[0], command_names[i]) == 0) code = i;
    if (code < 0) fail("unknown command");
    int expected = word_counts[code];
    if (expected < 0 ? count < -expected : count != expected) fail("wrong arguments");
    Command command = (Command)code;
    Job *job = NULL, *second = NULL;
    int lo = 0, hi = 0, field = -1, amount = 0, day = 0;
    switch (command) {
        case REMOVE: case RENAME: case ENABLE: case DISABLE: case RUNTIME: case EXPAND: case DESCRIBE:
        case MATCH: case NEXT: case PREV: case COUNT: case GAP: case OVERLAP: case CALENDAR:
            job = job_argument(words[1]); break;
        default: break;
    }
    switch (command) {
        case RENAME: new_id(words[2]); break;
        case EXPAND:
            for (int i = 0; i < 5; i++) if (strcmp(words[2], field_names[i]) == 0) field = i;
            if (field < 0) fail("invalid field");
            break;
        case MATCH: case NEXT: case PREV: case COUNT: case GAP:
            lo = datetime_argument(words, 2);
            if (command == NEXT || command == PREV) amount = positive_argument(words[4], 2, 50, "invalid count");
            if (command == COUNT) hi = datetime_argument(words, 4);
            break;
        case OVERLAP: second = job_argument(words[2]); lo = datetime_argument(words, 3); hi = datetime_argument(words, 5); break;
        case TIMELINE: case CONFLICTS: case SIMULATE: lo = datetime_argument(words, 1); hi = datetime_argument(words, 3); break;
        case WEEK: case EXCLUDE: case INCLUDE: day = date_argument(words[1], "invalid date"); break;
        case CALENDAR: day = month_argument(words[2]); break;
        default: break;
    }
    if (command == COUNT || command == OVERLAP || command == TIMELINE || command == CONFLICTS || command == SIMULATE) {
        if (lo > hi) fail("invalid window");
        if (hi - lo > MAX_WINDOW) fail("window too long");
    }
    switch (command) {
        case JOB: {
            new_id(words[1]);
            Cron cron = parse_cron(words + 2, count - 2);
            Job added = {.cron = cron, .enabled = true, .duration = 1, .policy = ALLOW};
            strcpy(added.id, words[1]);
            jobs[job_count++] = added;
            printf("JOB %s added\n", words[1]);
            break;
        }
        case VALIDATE: {
            Cron cron = parse_cron(words + 1, count - 1);
            printf("VALID %s %s %d\n", cron.expanded, cron.disjunction ? "OR" : "AND", cron.time_count);
            break;
        }
        case REMOVE: {
            int index = (int)(job - jobs);
            memmove(jobs + index, jobs + index + 1, (size_t)(job_count - index - 1) * sizeof(Job));
            job_count--;
            printf("REMOVE %s\n", words[1]);
            break;
        }
        case RENAME: strcpy(job->id, words[2]); printf("RENAME %s %s\n", words[1], words[2]); break;
        case ENABLE: case DISABLE: {
            bool desired = command == ENABLE;
            if (job->enabled == desired) fail("already %s", desired ? "enabled" : "disabled");
            job->enabled = desired;
            printf("%s %s\n", words[0], job->id);
            break;
        }
        case RUNTIME: {
            int duration = positive_argument(words[2], 4, 1440, "invalid duration"), policy = -1;
            for (int i = 0; i < 3; i++) if (strcmp(words[3], policy_names[i]) == 0) policy = i;
            if (policy < 0) fail("invalid policy");
            job->duration = duration; job->policy = (Policy)policy;
            printf("RUNTIME %s %d %s\n", job->id, duration, policy_names[policy]);
            break;
        }
        case LIST: {
            Job *ordered[40]; int n = ordered_jobs(ordered, false);
            printf("LIST %d\n", n);
            for (int i = 0; i < n; i++) {
                Job *item = ordered[i];
                printf("%s %s %d %s %s\n", item->id, item->enabled ? "on" : "off", item->duration, policy_names[item->policy], item->cron.text);
            }
            break;
        }
        case EXPAND: {
            const Field *item = &job->cron.fields[field];
            printf("EXPAND %s %s %d", job->id, field_names[field], item->count);
            for (int value = lower[field]; value <= upper[field]; value++) if (item->values[value]) printf(" %d", value);
            for (int i = 0; i < item->special_count; i++) printf(" %s", special_text(item->special[i]));
            putchar('\n'); break;
        }
        case DESCRIBE: printf("DESCRIBE %s %s\n", job->id, description(&job->cron)); break;
        case MATCH: {
            bool dom, dow, condition = day_condition(&job->cron, lo / MINUTES_PER_DAY, &dom, &dow);
            bool minute = job->cron.fields[0].values[lo % 60], hour = job->cron.fields[1].values[lo % MINUTES_PER_DAY / 60];
            bool month = job->cron.fields[3].values[calendar[lo / MINUTES_PER_DAY].month], excluded = holidays[lo / MINUTES_PER_DAY];
            bool matches = minute && hour && condition && month && !excluded;
            printf("MATCH %s %s %s", job->id, datetime_text(lo), matches ? "yes" : "no");
            if (!minute) printf(" minute");
            if (!hour) printf(" hour");
            if (!condition && !dom) printf(" day-of-month");
            if (!month) printf(" month");
            if (!condition && !dow) printf(" day-of-week");
            if (excluded) printf(" excluded");
            putchar('\n'); break;
        }
        case NEXT: case PREV: {
            bool reverse = command == PREV;
            Times times = fire_times(job, reverse ? lo - 527040 : lo + 1, reverse ? lo - 1 : lo + 527040, amount, reverse);
            printf("%s %s %d\n", words[0], job->id, times.count);
            for (int i = 0; i < times.count; i++) printf("%s %c%s\n", datetime_text(times.items[i]), reverse ? '-' : '+', span_text(abs(times.items[i] - lo)));
            if (times.count < amount) puts("NONE");
            break;
        }
        case COUNT: {
            Times times = fire_times(job, lo, hi, 0, false);
            int days = 0, previous = -1;
            for (int i = 0; i < times.count; i++) if (times.items[i] / MINUTES_PER_DAY != previous) { previous = times.items[i] / MINUTES_PER_DAY; days++; }
            printf("COUNT %s runs %d days %d\n", job->id, times.count, days);
            break;
        }
        case GAP: {
            Times times = fire_times(job, lo, lo + MAX_WINDOW, 0, false);
            if (times.count < 2) printf("GAP %s runs %d none\n", job->id, times.count);
            else {
                int *histogram = temporary((MAX_WINDOW + 1) * sizeof(int));
                memset(histogram, 0, (MAX_WINDOW + 1) * sizeof(int));
                int shortest = MAX_WINDOW + 1, longest = 0, first = 0;
                for (int i = 0; i + 1 < times.count; i++) {
                    int gap = times.items[i + 1] - times.items[i]; histogram[gap]++;
                    if (gap < shortest) shortest = gap;
                    if (gap > longest) { longest = gap; first = i; }
                }
                printf("GAP %s runs %d shortest %s longest %s from %s to %s\n", job->id, times.count, span_text(shortest), span_text(longest), datetime_text(times.items[first]), datetime_text(times.items[first + 1]));
                for (int gap = 1; gap <= MAX_WINDOW; gap++) if (histogram[gap]) printf("%s %d\n", span_text(gap), histogram[gap]);
            }
            break;
        }
        case OVERLAP: {
            Times a = fire_times(job, lo, hi, 0, false), b = fire_times(second, lo, hi, 0, false);
            int i = 0, j = 0, n = 0, first = 0, last = 0;
            while (i < a.count && j < b.count) {
                if (a.items[i] < b.items[j]) i++;
                else if (a.items[i] > b.items[j]) j++;
                else { if (!n) first = a.items[i]; last = a.items[i]; n++; i++; j++; }
            }
            printf("OVERLAP %s %s %d", job->id, second->id, n);
            if (n) printf(" first %s last %s", datetime_text(first), datetime_text(last));
            putchar('\n'); break;
        }
        case TIMELINE: case CONFLICTS: {
            Job *ordered[40]; int n = ordered_jobs(ordered, true);
            uint64_t *masks = timeline(ordered, n, lo, hi);
            int total = 0, peak = 0;
            for (int i = 0; i <= hi - lo; i++) {
                int count_at = bit_count(masks[i]);
                if (command == TIMELINE) total += count_at;
                else if (count_at >= 2) { total++; if (count_at > peak) peak = count_at; }
            }
            if (command == TIMELINE) printf("TIMELINE %d\n", total);
            else printf("CONFLICTS %d peak %d\n", total, peak);
            int shown = 0;
            for (int i = 0; i <= hi - lo && shown < 100; i++) {
                if (command == TIMELINE) {
                    for (int j = 0; j < n && shown < 100; j++) if (masks[i] & (UINT64_C(1) << j)) { printf("%s %s\n", datetime_text(lo + i), ordered[j]->id); shown++; }
                } else if (bit_count(masks[i]) >= 2) {
                    printf("%s %d", datetime_text(lo + i), bit_count(masks[i]));
                    for (int j = 0; j < n; j++) if (masks[i] & (UINT64_C(1) << j)) printf(" %s", ordered[j]->id);
                    putchar('\n'); shown++;
                }
            }
            if (total > 100) printf("... %d more\n", total - 100);
            break;
        }
        case WEEK: {
            int counts[7][24] = {{0}}, totals[7] = {0}, total = 0;
            for (int d = 0; d < 7; d++) if (!holidays[day + d]) {
                for (int j = 0; j < job_count; j++) if (jobs[j].enabled && scheduled_day(&jobs[j].cron, day + d))
                    for (int hour = 0; hour < 24; hour++) if (jobs[j].cron.fields[1].values[hour]) counts[d][hour] += jobs[j].cron.fields[0].count;
                for (int hour = 0; hour < 24; hour++) totals[d] += counts[d][hour];
                total += totals[d];
            }
            printf("WEEK %s %d\n", words[1], total);
            for (int d = 0; d < 7; d++) {
                char heat[25]; heat[24] = '\0';
                for (int hour = 0; hour < 24; hour++) heat[hour] = counts[d][hour] == 0 ? '.' : counts[d][hour] >= 10 ? '+' : (char)('0' + counts[d][hour]);
                printf("%s %s %d\n", date_text(day + d), heat, totals[d]);
            }
            break;
        }
        case CALENDAR: {
            int length = calendar[day].length, weekday = calendar[day].weekday, days = 0;
            char marks[32];
            for (int d = 1; d <= length; d++) {
                marks[d] = !scheduled_day(&job->cron, day + d - 1) ? '-' : holidays[day + d - 1] ? 'x' : '*';
                if (marks[d] == '*') days++;
            }
            printf("CALENDAR %s %s days %d runs %d\n", job->id, words[2], days, days * job->cron.time_count);
            puts("Sun Mon Tue Wed Thu Fri Sat");
            int cells = (weekday + length + 6) / 7 * 7;
            for (int i = 0; i < cells; i++) {
                if (i % 7) putchar(' ');
                int d = i - weekday + 1;
                if (d < 1 || d > length) printf("..."); else printf("%02d%c", d, marks[d]);
                if (i % 7 == 6) putchar('\n');
            }
            break;
        }
        case SIMULATE: {
            typedef struct { int started, skipped, replaced, busy; } Statistics;
            Statistics stats[40] = {{0}};
            Job *ordered[40]; int n = ordered_jobs(ordered, true), length = hi - lo + MINUTES_PER_DAY + 1;
            int *events = temporary((size_t)length * sizeof(int)); memset(events, 0, (size_t)length * sizeof(int));
            for (int i = 0; i < n; i++) {
                Job *item = ordered[i]; int last_end = -1;
                Times times = fire_times(item, lo, hi, 0, false);
                for (int j = 0; j < times.count; j++) {
                    int time = times.items[j];
                    if (last_end > time && item->policy == FORBID) { stats[i].skipped++; continue; }
                    if (last_end > time && item->policy == REPLACE) {
                        events[last_end - lo]++; events[time - lo]--;
                        stats[i].busy -= last_end - time; stats[i].replaced++;
                    }
                    last_end = time + item->duration;
                    events[time - lo]++; events[last_end - lo]--;
                    stats[i].started++; stats[i].busy += item->duration;
                }
            }
            int active = 0, peak = 0, first = 0;
            for (int i = 0; i < length; i++) { active += events[i]; if (active > peak) { peak = active; first = lo + i; } }
            printf("SIMULATE %d peak %d", n, peak);
            if (peak) printf(" at %s", datetime_text(first));
            putchar('\n');
            for (int i = 0; i < n; i++) printf("%s %s started %d skipped %d replaced %d busy %d\n", ordered[i]->id, policy_names[ordered[i]->policy], stats[i].started, stats[i].skipped, stats[i].replaced, stats[i].busy);
            break;
        }
        case EXCLUDE: case INCLUDE:
            if (holidays[day] == (command == EXCLUDE)) fail(command == EXCLUDE ? "already excluded" : "not excluded");
            holidays[day] = command == EXCLUDE; holiday_count += command == EXCLUDE ? 1 : -1;
            printf("%s %s holidays %d\n", words[0], date_text(day), holiday_count); break;
        case HOLIDAYS:
            printf("HOLIDAYS %d\n", holiday_count);
            for (int d = 0; d < DAY_COUNT; d++) if (holidays[d]) puts(date_text(d));
            break;
    }
}

int main(void) {
    init_calendar();
    char line[104];
    if (!fgets(line, sizeof(line), stdin)) return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands; i++) {
        if (!fgets(line, sizeof(line), stdin)) break;
        line[strcspn(line, "\r\n")] = '\0';
        char *words[51]; int count = 0;
        for (char *word = strtok(line, " "); word; word = strtok(NULL, " ")) words[count++] = word;
        if (setjmp(command_error) == 0) execute(words, count);
        else printf("ERROR %s\n", error_message);
        clear_temporaries();
    }
    return 0;
}
