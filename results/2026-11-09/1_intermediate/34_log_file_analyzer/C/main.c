#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_RECORDS 2000
#define MAX_LINE 200
#define PATH_SIZE (4 * MAX_LINE + 2)

typedef enum {
    SUMMARY, MALFORMED, STATUS, METHODS, TOP, HOURLY, TIMELINE,
    BANDWIDTH, VISITORS, LATENCY, HISTOGRAM, APDEX, ERRORS, SLOWEST,
    SESSIONS, BURST, PEAK, GAPS, IP, RANGE, FILTER, UNFILTER, RESET, STATE
} Query;

typedef enum {
    LIMIT_ARG, MINUTES_ARG, WIDTH_ARG, THRESHOLD_ARG, LENGTH_ARG, TIMES_ARG,
    KIND_ARG, PATH_ARG, IP_ARG, DATE_ARG, TIME_ARG, KEY_ARG, SUBJECT_ARG, VALUE_ARG
} Argument;

typedef enum { BY_PATH, BY_IP, BY_METHOD, BY_DATE, BY_ENDPOINT } GroupKey;

typedef struct {
    const char *name;
    int minimum, maximum;
    Argument arguments[4];
    bool needs_records;
} QueryForm;

static const QueryForm forms[] = {
    {"SUMMARY", 0, 0, {0}, false},
    {"MALFORMED", 0, 0, {0}, false},
    {"STATUS", 0, 0, {0}, true},
    {"METHODS", 0, 0, {0}, true},
    {"TOP", 2, 2, {KIND_ARG, LIMIT_ARG}, true},
    {"HOURLY", 0, 0, {0}, true},
    {"TIMELINE", 1, 1, {MINUTES_ARG}, true},
    {"BANDWIDTH", 0, 0, {0}, true},
    {"VISITORS", 0, 0, {0}, true},
    {"LATENCY", 0, 1, {PATH_ARG}, false},
    {"HISTOGRAM", 1, 1, {WIDTH_ARG}, true},
    {"APDEX", 1, 1, {THRESHOLD_ARG}, true},
    {"ERRORS", 0, 0, {0}, true},
    {"SLOWEST", 1, 1, {LIMIT_ARG}, true},
    {"SESSIONS", 1, 2, {IP_ARG, MINUTES_ARG}, false},
    {"BURST", 2, 2, {LENGTH_ARG, TIMES_ARG}, true},
    {"PEAK", 1, 1, {LENGTH_ARG}, true},
    {"GAPS", 1, 1, {LENGTH_ARG}, true},
    {"IP", 1, 1, {IP_ARG}, false},
    {"RANGE", 4, 4, {DATE_ARG, TIME_ARG, DATE_ARG, TIME_ARG}, false},
    {"FILTER", 2, 2, {KEY_ARG, VALUE_ARG}, false},
    {"UNFILTER", 1, 1, {SUBJECT_ARG}, false},
    {"RESET", 0, 0, {0}, false},
    {"STATE", 0, 0, {0}, false}
};
static const char *methods[] = {"GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"};
static const char *reasons[] = {"fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"};
static const char *filter_keys[] = {"METHOD", "STATUS", "IP", "PATH"};
static const char *lower_keys[] = {"method", "status", "ip", "path"};
static const char *argument_errors[] = {
    "invalid number", "invalid number", "invalid number", "invalid number",
    "invalid number", "invalid number", "invalid kind", "invalid path",
    "invalid ip", "invalid timestamp", "invalid timestamp", "invalid key",
    "invalid key", "invalid value"
};

typedef struct {
    int line, hour, status, latency;
    int64_t seconds, bytes;
    uint32_t ip_number;
    char date[11], timestamp[20], ip[16], method[8], path[PATH_SIZE];
} Record;

typedef struct { int line, reason; } Malformed;

typedef struct {
    Record records[MAX_RECORDS];
    Malformed malformed[MAX_RECORDS];
    int line_count, record_count, malformed_count;
    char filters[4][PATH_SIZE];
    bool has_range;
    int64_t first_second, last_second;
    char first_timestamp[20], last_timestamp[20];
} Analyzer;

typedef struct {
    Record *sample;
    int begin, count, maximum, client, server, satisfied, tolerating;
    int64_t bytes, latency;
} Group;

typedef struct { int count, first, last; } Window;
typedef struct { const char *ip; uint32_t number; Window window; Record *first, *last; } Burst;

static int compare_integer(int64_t a, int64_t b) {
    return (a > b) - (a < b);
}

static int name_index(const char *name, const char *const *names, int n) {
    for (int i = 0; i < n; ++i)
        if (strcmp(name, names[i]) == 0) return i;
    return -1;
}

static int words(char *line, char **parts) {
    int n = 0;
    for (char *part = strtok(line, " "); part; part = strtok(NULL, " "))
        parts[n++] = part;
    return n;
}

static bool digits(const char *text) {
    if (!*text) return false;
    for (; *text; ++text)
        if (*text < '0' || *text > '9') return false;
    return true;
}

static bool canonical(const char *text, size_t limit) {
    size_t n = strlen(text);
    return n > 0 && n <= limit && digits(text) && (n == 1 || text[0] != '0');
}

static bool leap(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static int month_days(int year, int month) {
    static const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return month == 2 && leap(year) ? 29 : days[month - 1];
}

static bool valid_date(const char *text) {
    if (strlen(text) != 10 || text[4] != '-' || text[7] != '-') return false;
    for (int i = 0; i < 10; ++i)
        if (i != 4 && i != 7 && (text[i] < '0' || text[i] > '9')) return false;
    int year = atoi(text), month = atoi(text + 5), day = atoi(text + 8);
    return year >= 2000 && year <= 2059 && month >= 1 && month <= 12 &&
        day >= 1 && day <= month_days(year, month);
}

static bool valid_time(const char *text) {
    if (strlen(text) != 8 || text[2] != ':' || text[5] != ':') return false;
    for (int i = 0; i < 8; ++i)
        if (i != 2 && i != 5 && (text[i] < '0' || text[i] > '9')) return false;
    return atoi(text) < 24 && atoi(text + 3) < 60 && atoi(text + 6) < 60;
}

static bool parse_ip(const char *text, uint32_t *number) {
    uint32_t result = 0;
    for (int i = 0; i < 4; ++i) {
        const char *start = text;
        int value = 0;
        while (*text >= '0' && *text <= '9') {
            if (text - start >= 3) return false;
            value = value * 10 + *text++ - '0';
        }
        if (text == start || (text - start > 1 && *start == '0') || value > 255)
            return false;
        result = result * 256 + (uint32_t)value;
        if (i < 3) {
            if (*text != '.') return false;
            ++text;
        } else if (*text) return false;
    }
    *number = result;
    return true;
}

static bool valid_status(const char *text) {
    return strlen(text) == 3 && digits(text) && atoi(text) >= 100 && atoi(text) <= 599;
}

static bool status_class(const char *text) {
    return strlen(text) == 3 && text[0] >= '1' && text[0] <= '5' &&
        text[1] == 'x' && text[2] == 'x';
}

static bool status_matches(const char *text, int status) {
    return status_class(text) ? status / 100 == text[0] - '0' : status == atoi(text);
}

static bool filter_value(const char *key, const char *value) {
    uint32_t ip;
    switch (name_index(key, filter_keys, 4)) {
        case 0: return name_index(value, methods, 7) >= 0;
        case 1: return status_class(value) || valid_status(value);
        case 2: return parse_ip(value, &ip);
        case 3: return value[0] == '/';
        default: return false;
    }
}

static bool valid_argument(Argument kind, const char *value, char **args) {
    static const int upper[] = {100, 1440, 100000, 100000, 86400, 1000};
    if (kind <= TIMES_ARG)
        return canonical(value, 6) && atoi(value) >= 1 && atoi(value) <= upper[kind];
    uint32_t ip;
    switch (kind) {
        case KIND_ARG: return strcmp(value, "PATHS") == 0 || strcmp(value, "IPS") == 0;
        case PATH_ARG: return value[0] == '/';
        case IP_ARG: return parse_ip(value, &ip);
        case DATE_ARG: return valid_date(value);
        case TIME_ARG: return valid_time(value);
        case KEY_ARG: return name_index(value, filter_keys, 4) >= 0;
        case SUBJECT_ARG: return strcmp(value, "RANGE") == 0 || name_index(value, filter_keys, 4) >= 0;
        case VALUE_ARG: return filter_value(args[0], value);
        default: return false;
    }
}

static int malformed_reason(char **parts, int n) {
    uint32_t ip;
    if (n != 8) return 0;
    if (!valid_date(parts[0])) return 1;
    if (!valid_time(parts[1])) return 2;
    if (!parse_ip(parts[2], &ip)) return 3;
    if (name_index(parts[3], methods, 7) < 0) return 4;
    if (parts[4][0] != '/') return 5;
    if (!valid_status(parts[5])) return 6;
    if (!canonical(parts[6], 8)) return 7;
    if (!canonical(parts[7], 6)) return 8;
    return -1;
}

static int64_t seconds_of(const char *date, const char *clock) {
    int year = atoi(date), month = atoi(date + 5);
    int64_t days = atoi(date + 8) - 1;
    for (int y = 2000; y < year; ++y) days += leap(y) ? 366 : 365;
    for (int m = 1; m < month; ++m) days += month_days(year, m);
    return days * 86400 + atoi(clock) * 3600 + atoi(clock + 3) * 60 + atoi(clock + 6);
}

static void interval_label(int64_t seconds, char *text) {
    int days = (int)(seconds / 86400), year = 2000, month = 1;
    int minutes = (int)(seconds % 86400 / 60);
    while (days >= (leap(year) ? 366 : 365)) {
        days -= leap(year) ? 366 : 365;
        ++year;
    }
    while (days >= month_days(year, month)) days -= month_days(year, month++);
    sprintf(text, "%04d-%02d-%02d %02d:%02d", year, month, days + 1, minutes / 60, minutes % 60);
}

static void normalize_path(const char *raw, char *result) {
    char copy[MAX_LINE + 1], *parts[MAX_LINE], *p;
    strcpy(copy, raw);
    p = strchr(copy, '?');
    if (p) *p = '\0';
    int n = 0;
    for (p = strtok(copy, "/"); p; p = strtok(NULL, "/")) {
        if (strcmp(p, "..") == 0) {
            if (n) --n;
        } else if (strcmp(p, ".") != 0) parts[n++] = p;
    }
    strcpy(result, "/");
    for (int i = 0; i < n; ++i) {
        p = parts[i];
        bool hex = strlen(p) >= 8, has_digit = false;
        for (const char *c = p; *c; ++c) {
            bool digit = *c >= '0' && *c <= '9';
            has_digit |= digit;
            hex &= digit || (*c >= 'a' && *c <= 'f');
        }
        if (i) strcat(result, "/");
        strcat(result, digits(p) ? "{id}" : hex && has_digit ? "{hex}" : p);
    }
}

static const char *decimal(int64_t numerator, int64_t denominator, int places, char *buffer) {
    int64_t scale = places == 1 ? 10 : places == 2 ? 100 : 1000;
    int64_t value = numerator * scale / denominator;
    sprintf(buffer, "%" PRId64 ".%0*" PRId64, value / scale, places, value % scale);
    return buffer;
}

static const char *percentage(int count, int total, char *buffer) {
    decimal((int64_t)count * 100, total, 2, buffer);
    strcat(buffer, "%");
    return buffer;
}

static const char *bytes_text(int64_t bytes, char *buffer) {
    int64_t unit = bytes >= 1073741824 ? 1073741824 : bytes >= 1048576 ? 1048576 : 1024;
    if (bytes < 1024) sprintf(buffer, "%" PRId64 "B", bytes);
    else {
        decimal(bytes, unit, 1, buffer);
        strcat(buffer, unit == 1073741824 ? "GB" : unit == 1048576 ? "MB" : "KB");
    }
    return buffer;
}

static void bar_line(const char *label, int count, int maximum) {
    printf("%s %d", label, count);
    if (count) {
        putchar(' ');
        for (int i = 0, width = (count * 30 + maximum - 1) / maximum; i < width; ++i)
            putchar('#');
    }
    putchar('\n');
}

static int record_order(const void *left, const void *right) {
    const Record *a = left, *b = right;
    int order = compare_integer(a->seconds, b->seconds);
    return order ? order : compare_integer(a->line, b->line);
}

static GroupKey group_key;

static int key_order(const Record *a, const Record *b, GroupKey key) {
    if (key == BY_IP) return compare_integer(a->ip_number, b->ip_number);
    if (key == BY_METHOD) return strcmp(a->method, b->method);
    if (key == BY_DATE) return strcmp(a->date, b->date);
    int order = strcmp(a->path, b->path);
    return order || key != BY_ENDPOINT ? order : strcmp(a->method, b->method);
}

static int grouped_record_order(const void *left, const void *right) {
    const Record *a = *(Record *const *)left, *b = *(Record *const *)right;
    int order = key_order(a, b, group_key);
    return order ? order : record_order(a, b);
}

static void accumulate(Group *group, Record *row, int threshold) {
    ++group->count;
    group->bytes += row->bytes;
    group->latency += row->latency;
    if (row->latency > group->maximum) group->maximum = row->latency;
    group->client += row->status / 100 == 4;
    group->server += row->status / 100 == 5;
    if (row->status < 500) {
        group->satisfied += row->latency <= threshold;
        group->tolerating += row->latency > threshold && row->latency <= 4 * threshold;
    }
}

static int group_rows(Record **rows, int n, GroupKey key, int threshold,
                      Group *groups, Record **ordered) {
    memcpy(ordered, rows, (size_t)n * sizeof(*rows));
    group_key = key;
    qsort(ordered, n, sizeof(*ordered), grouped_record_order);
    int count = 0;
    for (int i = 0; i < n; ++i) {
        if (i == 0 || key_order(ordered[i - 1], ordered[i], key))
            groups[count++] = (Group){.sample = ordered[i], .begin = i};
        accumulate(&groups[count - 1], ordered[i], threshold);
    }
    return count;
}

static int unique_count(Record **rows, int n, GroupKey key) {
    Record *ordered[MAX_RECORDS];
    memcpy(ordered, rows, (size_t)n * sizeof(*rows));
    group_key = key;
    qsort(ordered, n, sizeof(*ordered), grouped_record_order);
    int count = 0;
    for (int i = 0; i < n; ++i)
        count += i == 0 || key_order(ordered[i - 1], ordered[i], key) != 0;
    return count;
}

static int count_order(const void *left, const void *right) {
    const Group *a = left, *b = right;
    int order = compare_integer(b->count, a->count);
    return order ? order : key_order(a->sample, b->sample, group_key);
}

static int error_order(const void *left, const void *right) {
    const Group *a = left, *b = right;
    int64_t x = a->client + a->server, y = b->client + b->server;
    int order = compare_integer(y * a->count, x * b->count);
    if (!order) order = compare_integer(y, x);
    return order ? order : strcmp(a->sample->path, b->sample->path);
}

static int slow_order(const void *left, const void *right) {
    const Group *a = left, *b = right;
    int order = compare_integer(b->latency * a->count, a->latency * b->count);
    if (!order) order = compare_integer(b->maximum, a->maximum);
    return order ? order : key_order(a->sample, b->sample, BY_ENDPOINT);
}

static int score_order(const void *left, const void *right) {
    const Group *a = left, *b = right;
    int64_t x = 2 * a->satisfied + a->tolerating, y = 2 * b->satisfied + b->tolerating;
    int order = compare_integer(x * b->count, y * a->count);
    if (!order) order = compare_integer(b->count, a->count);
    return order ? order : strcmp(a->sample->path, b->sample->path);
}

static const char *rating(const Group *group) {
    int64_t points = 100 * (2 * group->satisfied + group->tolerating);
    int64_t total = 2 * group->count;
    if (points >= 94 * total) return "excellent";
    if (points >= 85 * total) return "good";
    if (points >= 70 * total) return "fair";
    if (points >= 50 * total) return "poor";
    return "unacceptable";
}

static Window peak(Record **rows, int n, int length) {
    Window best = {0};
    int first = 0;
    for (int last = 0; last < n; ++last) {
        while (rows[last]->seconds - rows[first]->seconds >= length) ++first;
        if (last - first + 1 > best.count)
            best = (Window){last - first + 1, first, last};
    }
    return best;
}

static int burst_order(const void *left, const void *right) {
    const Burst *a = left, *b = right;
    int order = compare_integer(b->window.count, a->window.count);
    return order ? order : compare_integer(a->number, b->number);
}

static int selected(Analyzer *analyzer, Record **rows) {
    int count = 0;
    for (int i = 0; i < analyzer->record_count; ++i) {
        Record *r = &analyzer->records[i];
        if (analyzer->has_range && (r->seconds < analyzer->first_second || r->seconds > analyzer->last_second)) continue;
        if (*analyzer->filters[0] && strcmp(r->method, analyzer->filters[0])) continue;
        if (*analyzer->filters[1] && !status_matches(analyzer->filters[1], r->status)) continue;
        if (*analyzer->filters[2] && strcmp(r->ip, analyzer->filters[2])) continue;
        if (*analyzer->filters[3] && strcmp(r->path, analyzer->filters[3])) continue;
        rows[count++] = r;
    }
    return count;
}

static int latency_order(const void *left, const void *right) {
    return compare_integer(*(const int *)left, *(const int *)right);
}

static void run_query(Analyzer *analyzer, Query query, int argc, char **args, Record **rows, int n) {
    Group groups[MAX_RECORDS];
    Record *ordered[MAX_RECORDS];
    char first[64], second[64], label[PATH_SIZE];
    switch (query) {
        case SUMMARY: {
            int64_t bytes = 0;
            for (int i = 0; i < n; ++i) bytes += rows[i]->bytes;
            printf("SUMMARY lines %d valid %d malformed %d\n", analyzer->line_count, analyzer->record_count, analyzer->malformed_count);
            printf("requests %d bytes %" PRId64 " ips %d paths %d\n", n, bytes,
                unique_count(rows, n, BY_IP), unique_count(rows, n, BY_PATH));
            if (!n) puts("span none");
            else printf("span %s %s %" PRId64 "\n", rows[0]->timestamp, rows[n - 1]->timestamp, rows[n - 1]->seconds - rows[0]->seconds);
            break;
        }
        case MALFORMED:
            printf("MALFORMED %d\n", analyzer->malformed_count);
            for (int reason = 0; reason < 9; ++reason) {
                int count = 0;
                for (int i = 0; i < analyzer->malformed_count; ++i) count += analyzer->malformed[i].reason == reason;
                if (!count) continue;
                printf("%s %d", reasons[reason], count);
                for (int i = 0; i < analyzer->malformed_count; ++i)
                    if (analyzer->malformed[i].reason == reason) printf(" %d", analyzer->malformed[i].line);
                putchar('\n');
            }
            break;
        case STATUS: {
            int classes[5] = {0}, statuses[600] = {0};
            for (int i = 0; i < n; ++i) { ++classes[rows[i]->status / 100 - 1]; ++statuses[rows[i]->status]; }
            printf("STATUS %d\n", n);
            for (int i = 0; i < 5; ++i) printf("%dxx %d %s\n", i + 1, classes[i], percentage(classes[i], n, first));
            for (int i = 100; i < 600; ++i)
                if (statuses[i]) printf("%d %d %s\n", i, statuses[i], percentage(statuses[i], n, first));
            break;
        }
        case METHODS:
        case TOP: {
            GroupKey key = query == METHODS ? BY_METHOD : strcmp(args[0], "IPS") == 0 ? BY_IP : BY_PATH;
            int count = group_rows(rows, n, key, 0, groups, ordered);
            qsort(groups, count, sizeof(*groups), count_order);
            int limit = query == METHODS ? count : atoi(args[1]);
            if (limit > count) limit = count;
            if (query == METHODS) printf("METHODS %d\n", n);
            else printf("TOP %s %d of %d\n", args[0], limit, count);
            int rank = 0;
            for (int i = 0; i < limit; ++i) {
                Group *g = &groups[i];
                const char *text = key == BY_IP ? g->sample->ip : key == BY_METHOD ? g->sample->method : g->sample->path;
                if (i == 0 || g->count != groups[i - 1].count) rank = i + 1;
                if (query == TOP) printf("%d ", rank);
                printf("%s %d %s\n", text, g->count, percentage(g->count, n, first));
            }
            break;
        }
        case HOURLY: {
            int counts[24] = {0}, maximum = 0, hour = 0;
            for (int i = 0; i < n; ++i) ++counts[rows[i]->hour];
            for (int i = 0; i < 24; ++i)
                if (counts[i] > maximum) { maximum = counts[i]; hour = i; }
            printf("HOURLY %d peak %02d %d\n", n, hour, maximum);
            for (int i = 0; i < 24; ++i) { sprintf(label, "%02d", i); bar_line(label, counts[i], maximum); }
            break;
        }
        case TIMELINE:
        case HISTOGRAM: {
            int parameter = atoi(args[0]), width = query == TIMELINE ? parameter * 60 : parameter;
            int64_t low = INT64_MAX, high = 0, values[MAX_RECORDS];
            for (int i = 0; i < n; ++i) {
                values[i] = (query == TIMELINE ? rows[i]->seconds : rows[i]->latency) / width;
                if (values[i] < low) low = values[i];
                if (values[i] > high) high = values[i];
            }
            if (high - low + 1 > 60) { puts("ERROR too many buckets"); break; }
            int counts[60] = {0}, maximum = 0, count = (int)(high - low + 1);
            for (int i = 0; i < n; ++i) ++counts[values[i] - low];
            for (int i = 0; i < count; ++i) if (counts[i] > maximum) maximum = counts[i];
            printf("%s %d %d\n", forms[query].name, parameter, count);
            for (int i = 0; i < count; ++i) {
                int64_t start = (low + i) * width;
                if (query == TIMELINE) interval_label(start, label);
                else sprintf(label, "%" PRId64 "-%" PRId64, start, start + width - 1);
                bar_line(label, counts[i], maximum);
            }
            break;
        }
        case BANDWIDTH: {
            int count = group_rows(rows, n, BY_DATE, 0, groups, ordered);
            int64_t total = 0;
            for (int i = 0; i < count; ++i) total += groups[i].bytes;
            printf("BANDWIDTH %d %" PRId64 " %s\n", count, total, bytes_text(total, first));
            for (int i = 0; i < count; ++i)
                printf("%s %d %" PRId64 " %s\n", groups[i].sample->date, groups[i].count, groups[i].bytes, bytes_text(groups[i].bytes, first));
            break;
        }
        case VISITORS: {
            Group ips[MAX_RECORDS];
            Record *ip_rows[MAX_RECORDS];
            int ip_count = group_rows(rows, n, BY_IP, 0, ips, ip_rows);
            int count = group_rows(rows, n, BY_DATE, 0, groups, ordered);
            printf("VISITORS %d %d\n", count, ip_count);
            for (int i = 0; i < count; ++i) {
                Group *g = &groups[i];
                int fresh = 0;
                for (int j = 0; j < ip_count; ++j) fresh += strcmp(ips[j].sample->date, g->sample->date) == 0;
                int unique = unique_count(ordered + g->begin, g->count, BY_IP);
                printf("%s unique %d new %d returning %d\n", g->sample->date, unique, fresh, unique - fresh);
            }
            break;
        }
        case LATENCY: {
            if (argc) normalize_path(args[0], label); else strcpy(label, "all");
            int values[MAX_RECORDS], count = 0;
            for (int i = 0; i < n; ++i)
                if (!argc || strcmp(rows[i]->path, label) == 0) values[count++] = rows[i]->latency;
            if (!count) { puts("LATENCY no records"); break; }
            qsort(values, count, sizeof(*values), latency_order);
            int trim = count / 10;
            int64_t sum = 0, trimmed = 0;
            for (int i = 0; i < count; ++i) {
                sum += values[i];
                if (i >= trim && i < count - trim) trimmed += values[i];
            }
            printf("LATENCY %s count %d min %d p50 %d p90 %d p99 %d max %d mean %s trimmed %s\n",
                label, count, values[0], values[(50 * count + 99) / 100 - 1],
                values[(90 * count + 99) / 100 - 1], values[(99 * count + 99) / 100 - 1], values[count - 1],
                decimal(sum, count, 2, first), decimal(trimmed, count - 2 * trim, 2, second));
            break;
        }
        case APDEX: {
            int threshold = atoi(args[0]);
            Group overall = {0};
            for (int i = 0; i < n; ++i) accumulate(&overall, rows[i], threshold);
            printf("APDEX %d %s %s satisfied %d tolerating %d frustrated %d\n", threshold,
                decimal(2 * overall.satisfied + overall.tolerating, 2 * n, 3, first), rating(&overall),
                overall.satisfied, overall.tolerating, n - overall.satisfied - overall.tolerating);
            int count = group_rows(rows, n, BY_PATH, threshold, groups, ordered);
            qsort(groups, count, sizeof(*groups), score_order);
            for (int i = 0; i < count; ++i) {
                Group *g = &groups[i];
                printf("%s %s %s %d\n", g->sample->path,
                    decimal(2 * g->satisfied + g->tolerating, 2 * g->count, 3, first), rating(g), g->count);
            }
            break;
        }
        case ERRORS: {
            int count = group_rows(rows, n, BY_PATH, 0, groups, ordered), failed = 0;
            for (int i = 0; i < count; ++i) failed += groups[i].client + groups[i].server;
            printf("ERRORS %d of %d %s\n", failed, n, percentage(failed, n, first));
            qsort(groups, count, sizeof(*groups), error_order);
            for (int i = 0; i < count; ++i) {
                Group *g = &groups[i];
                if (g->client + g->server)
                    printf("%s %d %d %d %s\n", g->sample->path, g->count, g->client, g->server, percentage(g->client + g->server, g->count, first));
            }
            break;
        }
        case SLOWEST: {
            int count = group_rows(rows, n, BY_ENDPOINT, 0, groups, ordered);
            qsort(groups, count, sizeof(*groups), slow_order);
            int limit = atoi(args[0]);
            if (limit > count) limit = count;
            printf("SLOWEST %d of %d\n", limit, count);
            for (int i = 0; i < limit; ++i) {
                Group *g = &groups[i];
                printf("%d %s %s count %d avg %s max %d\n", i + 1, g->sample->method, g->sample->path,
                    g->count, decimal(g->latency, g->count, 2, first), g->maximum);
            }
            break;
        }
        case SESSIONS: {
            int count = 0, timeout = argc == 2 ? atoi(args[1]) : 30;
            for (int i = 0; i < n; ++i) if (strcmp(rows[i]->ip, args[0]) == 0) ordered[count++] = rows[i];
            if (!count) { puts("SESSIONS no records"); break; }
            int starts[MAX_RECORDS + 1], sessions = 1;
            starts[0] = 0;
            for (int i = 1; i < count; ++i)
                if (ordered[i]->seconds - ordered[i - 1]->seconds > timeout * 60) starts[sessions++] = i;
            starts[sessions] = count;
            int64_t duration = 0;
            for (int i = 0; i < sessions; ++i) duration += ordered[starts[i + 1] - 1]->seconds - ordered[starts[i]]->seconds;
            printf("SESSIONS %s timeout %d count %d requests %d avg_duration %s avg_requests %s\n",
                args[0], timeout, sessions, count, decimal(duration, sessions, 1, first), decimal(count, sessions, 1, second));
            for (int i = 0; i < sessions; ++i) {
                Record *begin = ordered[starts[i]], *end = ordered[starts[i + 1] - 1];
                int length = starts[i + 1] - starts[i];
                printf("%d %s %s %" PRId64 " %d %d\n", i + 1, begin->timestamp, end->timestamp,
                    end->seconds - begin->seconds, length, unique_count(ordered + starts[i], length, BY_PATH));
            }
            break;
        }
        case BURST: {
            Record *failed[MAX_RECORDS];
            Burst bursts[MAX_RECORDS];
            int length = atoi(args[0]), minimum = atoi(args[1]), failure_count = 0, count = 0;
            for (int i = 0; i < n; ++i) if (rows[i]->status >= 400) failed[failure_count++] = rows[i];
            int group_count = group_rows(failed, failure_count, BY_IP, 0, groups, ordered);
            for (int i = 0; i < group_count; ++i) {
                Group *g = &groups[i];
                Window window = peak(ordered + g->begin, g->count, length);
                if (window.count >= minimum)
                    bursts[count++] = (Burst){g->sample->ip, g->sample->ip_number, window,
                        ordered[g->begin + window.first], ordered[g->begin + window.last]};
            }
            qsort(bursts, count, sizeof(*bursts), burst_order);
            printf("BURST %d %d %d\n", length, minimum, count);
            for (int i = 0; i < count; ++i)
                printf("%s %d %s %s\n", bursts[i].ip, bursts[i].window.count, bursts[i].first->timestamp, bursts[i].last->timestamp);
            break;
        }
        case PEAK: {
            int length = atoi(args[0]);
            Window window = peak(rows, n, length);
            printf("PEAK %d %d %s %s\n", length, window.count, rows[window.first]->timestamp, rows[window.last]->timestamp);
            break;
        }
        case GAPS: {
            int length = atoi(args[0]), count = 0;
            for (int i = 1; i < n; ++i) count += rows[i]->seconds - rows[i - 1]->seconds >= length;
            printf("GAPS %d %d\n", length, count);
            for (int i = 1; i < n; ++i)
                if (rows[i]->seconds - rows[i - 1]->seconds >= length)
                    printf("%s %s %" PRId64 "\n", rows[i - 1]->timestamp, rows[i]->timestamp, rows[i]->seconds - rows[i - 1]->seconds);
            break;
        }
        case IP: {
            Record *found[MAX_RECORDS];
            int count = 0, failures = 0, classes[5] = {0};
            int64_t bytes = 0;
            for (int i = 0; i < n; ++i) if (strcmp(rows[i]->ip, args[0]) == 0) {
                found[count++] = rows[i];
                bytes += rows[i]->bytes;
                failures += rows[i]->status >= 400;
                ++classes[rows[i]->status / 100 - 1];
            }
            if (!count) { puts("IP no records"); break; }
            printf("IP %s requests %d bytes %" PRId64 " errors %d paths %d\n", args[0], count, bytes, failures, unique_count(found, count, BY_PATH));
            printf("first %s last %s\n", found[0]->timestamp, found[count - 1]->timestamp);
            int size = group_rows(found, count, BY_METHOD, 0, groups, ordered);
            qsort(groups, size, sizeof(*groups), count_order);
            printf("methods");
            for (int i = 0; i < size; ++i) printf(" %s %d", groups[i].sample->method, groups[i].count);
            printf("\nclasses");
            for (int i = 0; i < 5; ++i) printf(" %dxx %d", i + 1, classes[i]);
            putchar('\n');
            size = group_rows(found, count, BY_PATH, 0, groups, ordered);
            qsort(groups, size, sizeof(*groups), count_order);
            for (int i = 0; i < size && i < 3; ++i) printf("path %s %d\n", groups[i].sample->path, groups[i].count);
            break;
        }
        case RANGE: {
            int64_t start = seconds_of(args[0], args[1]), end = seconds_of(args[2], args[3]);
            if (start > end) { puts("ERROR invalid range"); break; }
            analyzer->has_range = true;
            analyzer->first_second = start;
            analyzer->last_second = end;
            sprintf(analyzer->first_timestamp, "%s %s", args[0], args[1]);
            sprintf(analyzer->last_timestamp, "%s %s", args[2], args[3]);
            printf("RANGE %s %s active %d\n", analyzer->first_timestamp, analyzer->last_timestamp, selected(analyzer, ordered));
            break;
        }
        case FILTER: {
            int key = name_index(args[0], filter_keys, 4);
            if (key == 3) normalize_path(args[1], analyzer->filters[key]);
            else strcpy(analyzer->filters[key], args[1]);
            printf("FILTER %s %s active %d\n", args[0], analyzer->filters[key], selected(analyzer, ordered));
            break;
        }
        case UNFILTER: {
            int key = name_index(args[0], filter_keys, 4);
            if (key < 0) {
                if (!analyzer->has_range) { puts("ERROR not filtered"); break; }
                analyzer->has_range = false;
            } else {
                if (!*analyzer->filters[key]) { puts("ERROR not filtered"); break; }
                analyzer->filters[key][0] = '\0';
            }
            printf("UNFILTER %s active %d\n", args[0], selected(analyzer, ordered));
            break;
        }
        case RESET:
            analyzer->has_range = false;
            for (int i = 0; i < 4; ++i) analyzer->filters[i][0] = '\0';
            printf("RESET active %d\n", selected(analyzer, ordered));
            break;
        case STATE:
            printf("STATE active %d range ", n);
            if (analyzer->has_range) printf("%s %s", analyzer->first_timestamp, analyzer->last_timestamp);
            else putchar('-');
            for (int i = 0; i < 4; ++i) printf(" %s %s", lower_keys[i], *analyzer->filters[i] ? analyzer->filters[i] : "-");
            putchar('\n');
            break;
    }
}

static void execute(Analyzer *analyzer, char *line) {
    char *parts[MAX_LINE];
    int count = words(line, parts), query = -1;
    if (count) for (int i = 0; i <= STATE; ++i)
        if (strcmp(parts[0], forms[i].name) == 0) { query = i; break; }
    if (query < 0) { puts("ERROR unknown query"); return; }
    const QueryForm *form = &forms[query];
    int argc = count - 1;
    char **args = parts + 1;
    if (argc < form->minimum || argc > form->maximum) { puts("ERROR wrong arguments"); return; }
    for (int i = 0; i < argc; ++i) {
        Argument kind = form->arguments[i];
        if (!valid_argument(kind, args[i], args)) { printf("ERROR %s\n", argument_errors[kind]); return; }
    }
    Record *rows[MAX_RECORDS];
    int n = selected(analyzer, rows);
    if (!n && form->needs_records) { printf("%s no records\n", form->name); return; }
    run_query(analyzer, (Query)query, argc, args, rows, n);
}

int main(void) {
    static Analyzer analyzer;
    char line[MAX_LINE + 3];
    bool queries = false;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = '\0';
        if (queries) {
            if (strcmp(line, "END") == 0) break;
            execute(&analyzer, line);
        } else if (strcmp(line, "---") == 0) {
            queries = true;
            qsort(analyzer.records, analyzer.record_count, sizeof(Record), record_order);
        } else {
            ++analyzer.line_count;
            char *parts[MAX_LINE];
            int count = words(line, parts), reason = malformed_reason(parts, count);
            if (reason >= 0) {
                analyzer.malformed[analyzer.malformed_count++] = (Malformed){analyzer.line_count, reason};
                continue;
            }
            Record *r = &analyzer.records[analyzer.record_count++];
            r->line = analyzer.line_count;
            strcpy(r->date, parts[0]);
            sprintf(r->timestamp, "%s %s", parts[0], parts[1]);
            r->hour = atoi(parts[1]);
            r->seconds = seconds_of(parts[0], parts[1]);
            strcpy(r->ip, parts[2]);
            parse_ip(parts[2], &r->ip_number);
            strcpy(r->method, parts[3]);
            normalize_path(parts[4], r->path);
            r->status = atoi(parts[5]);
            r->bytes = strtoll(parts[6], NULL, 10);
            r->latency = atoi(parts[7]);
        }
    }
    return ferror(stdin) ? EXIT_FAILURE : EXIT_SUCCESS;
}
