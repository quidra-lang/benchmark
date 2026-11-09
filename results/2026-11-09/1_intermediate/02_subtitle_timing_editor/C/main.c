#include <inttypes.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Integer;
typedef struct {
    char **items;
    int count, capacity;
} Strings;
typedef struct {
    Integer index, start, end;
    Strings text;
} Cue;
typedef struct {
    Cue *items;
    int count, capacity;
} Cues;
typedef struct {
    char name[16];
    Cues cues;
} Record;
typedef struct {
    char name[16], schema[8];
    Strings raw;
    Integer values[4], denominator;
} Arguments;
typedef struct { int kind, size, digit, tag; } Markup;
static Cues cues;
static Record history[1000];
static int history_count;
static jmp_buf recovery;
static char error_message[128];
static Arguments arguments;

static void *allocate(size_t size) {
    void *p = malloc(size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}
static char *slice(const char *s, size_t n) {
    char *copy = allocate(n + 1);
    memcpy(copy, s, n);
    copy[n] = '\0';
    return copy;
}
static char *copy_string(const char *s) { return slice(s, strlen(s)); }
static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *s = allocate((size_t)length + 1);
    vsnprintf(s, (size_t)length + 1, pattern, args);
    va_end(args);
    return s;
}
static void push_owned(Strings *s, char *item) {
    if (s->count == s->capacity) {
        s->capacity = s->capacity ? s->capacity * 2 : 8;
        s->items = realloc(s->items, (size_t)s->capacity * sizeof *s->items);
        if (!s->items) exit(EXIT_FAILURE);
    }
    s->items[s->count++] = item;
}
static void push(Strings *s, const char *item) { push_owned(s, copy_string(item)); }
static void free_strings(Strings *s) {
    for (int i = 0; i < s->count; ++i) free(s->items[i]);
    free(s->items);
    *s = (Strings){0};
}
static Strings clone_strings(const Strings *s) {
    Strings result = {0};
    for (int i = 0; i < s->count; ++i) push(&result, s->items[i]);
    return result;
}
static Strings split(const char *s, char delimiter, int limit) {
    Strings result = {0};
    const char *start = s;
    for (const char *p = s;; ++p) {
        if (!*p || (*p == delimiter && (!limit || result.count + 1 < limit))) {
            push_owned(&result, slice(start, (size_t)(p - start)));
            start = p + 1;
            if (!*p) break;
        }
    }
    return result;
}
static char *join(const Strings *s, const char *separator) {
    size_t size = 1, sep = strlen(separator);
    for (int i = 0; i < s->count; ++i) size += strlen(s->items[i]) + (i ? sep : 0);
    char *result = allocate(size), *p = result;
    for (int i = 0; i < s->count; ++i) {
        if (i) {
            memcpy(p, separator, sep);
            p += sep;
        }
        size_t n = strlen(s->items[i]);
        memcpy(p, s->items[i], n);
        p += n;
    }
    *p = '\0';
    return result;
}
static void append_char(Strings *parts, char c) {
    char s[] = {c, '\0'};
    push(parts, s);
}
static char *trim(const char *s) {
    while (*s == ' ') ++s;
    size_t length = strlen(s);
    while (length && s[length - 1] == ' ') --length;
    return slice(s, length);
}
static void push_cue(Cues *list, Cue c) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 8;
        list->items = realloc(list->items, (size_t)list->capacity * sizeof *list->items);
        if (!list->items) exit(EXIT_FAILURE);
    }
    list->items[list->count++] = c;
}
static Cue clone_cue(const Cue *c) {
    Cue result = *c;
    result.text = clone_strings(&c->text);
    return result;
}
static Cues clone_cues(const Cues *list) {
    Cues result = {0};
    for (int i = 0; i < list->count; ++i) push_cue(&result, clone_cue(&list->items[i]));
    return result;
}
static void free_cues(Cues *list) {
    for (int i = 0; i < list->count; ++i) free_strings(&list->items[i].text);
    free(list->items);
    *list = (Cues){0};
}
static void fail(const char *message) {
    snprintf(error_message, sizeof error_message, "%s", message);
    longjmp(recovery, 1);
}
static bool unsigned_value(const char *s, Integer *value) {
    size_t n = strlen(s);
    if (!n || n > 9) return false;
    *value = 0;
    for (size_t i = 0; i < n; ++i) {
        if (s[i] < '0' || s[i] > '9') return false;
        *value = *value * 10 + s[i] - '0';
    }
    return true;
}
static bool time_value(const char *s, Integer *value) {
    if (strlen(s) != 12 || s[2] != ':' || s[5] != ':' || s[8] != ',') return false;
    for (int i = 0; i < 12; ++i) {
        if (i != 2 && i != 5 && i != 8 && (s[i] < '0' || s[i] > '9')) return false;
    }
    int h = (s[0] - '0') * 10 + s[1] - '0';
    int m = (s[3] - '0') * 10 + s[4] - '0';
    int sec = (s[6] - '0') * 10 + s[7] - '0';
    int ms = (s[9] - '0') * 100 + (s[10] - '0') * 10 + s[11] - '0';
    *value = (Integer)h * 3600000 + m * 60000 + sec * 1000 + ms;
    return m <= 59 && sec <= 59;
}
static char *time_text(Integer t, int kind) {
    if (kind == 2) {
        Integer c = (t + 5) / 10;
        return format("%" PRId64 ":%02" PRId64 ":%02" PRId64 ".%02" PRId64, c / 360000, c / 6000 % 60, c / 100 % 60, c % 100);
    }
    return format("%02" PRId64 ":%02" PRId64 ":%02" PRId64 "%c%03" PRId64, t / 3600000, t / 60000 % 60, t / 1000 % 60, kind == 1 ? '.' : ',', t % 1000);
}
static char *decimal(Integer v) { return format("%" PRId64 ".%02" PRId64, v / 100, v % 100); }
static Integer floor_ratio(Integer a, Integer b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    Integer q = a / b;
    if (a % b < 0) --q;
    return q;
}
static Integer half_up(Integer a, Integer b) {
    if (b < 0) {
        a = -a;
        b = -b;
    }
    return floor_ratio(2 * a + b, 2 * b);
}
static Integer count_chars(const Cue *c) {
    Integer result = 0;
    for (int i = 0; i < c->text.count; ++i) result += (Integer)strlen(c->text.items[i]);
    return result;
}
static bool dialogue(const Cue *c) {
    for (int i = 0; i < c->text.count; ++i) if (!strncmp(c->text.items[i], "- ", 2)) return true;
    return false;
}
static Strings words(const Strings *lines) {
    Strings result = {0};
    for (int i = 0; i < lines->count; ++i) {
        Strings parts = split(lines->items[i], ' ', 0);
        for (int j = 0; j < parts.count; ++j) if (*parts.items[j]) push(&result, parts.items[j]);
        free_strings(&parts);
    }
    return result;
}
static Strings wrap(const Strings *lines, int width) {
    Strings w = words(lines), result = {0};
    for (int i = 0; i < w.count; ++i) {
        if (!result.count || strlen(result.items[result.count - 1]) + 1 + strlen(w.items[i]) > (size_t)width) push(&result, w.items[i]);
        else {
            char **last = &result.items[result.count - 1];
            char *replacement = format("%s %s", *last, w.items[i]);
            free(*last);
            *last = replacement;
        }
    }
    free_strings(&w);
    return result;
}
static bool same_text(const Strings *a, const Strings *b) {
    if (a->count != b->count) return false;
    for (int i = 0; i < a->count; ++i) if (strcmp(a->items[i], b->items[i])) return false;
    return true;
}
static Markup markup_at(const char *line) {
    const char *tags[] = {"<i>", "</i>", "<b>", "</b>", "<u>", "</u>"};
    for (int i = 0; i < 6; ++i) {
        if (!strncmp(line, tags[i], strlen(tags[i]))) return (Markup){1, (int)strlen(tags[i]), 0, i};
    }
    if (!strncmp(line, "</font>", 7)) return (Markup){2, 7, 0, 0};
    if (!strncmp(line, "<font", 5) && (line[5] == ' ' || line[5] == '>')) {
        const char *end = strchr(line + 5, '>');
        if (end) return (Markup){2, (int)(end - line + 1), 0, 0};
    }
    if (strlen(line) >= 6 && !strncmp(line, "{\\an", 4) && line[4] >= '1' && line[4] <= '9' && line[5] == '}') return (Markup){3, 6, line[4] - '0', 0};
    return (Markup){0, 1, 0, 0};
}
static Strings converted(const Strings *lines, int mode, int *first, int *removed) {
    const char *ass[] = {"{\\i1}", "{\\i0}", "{\\b1}", "{\\b0}", "{\\u1}", "{\\u0}"};
    Strings result = {0};
    *first = *removed = 0;
    for (int i = 0; i < lines->count; ++i) {
        Strings pieces = {0};
        for (const char *p = lines->items[i]; *p;) {
            Markup m = markup_at(p);
            if (m.kind == 3 && !*first) *first = m.digit;
            if (mode == 0) {
                if (!m.kind) append_char(&pieces, *p);
                else ++*removed;
            } else if (mode == 1) {
                if (m.kind == 1) push_owned(&pieces, slice(p, m.size));
                if (!m.kind) {
                    if (*p == '&') push(&pieces, "&amp;");
                    else if (*p == '<') push(&pieces, "&lt;");
                    else if (*p == '>') push(&pieces, "&gt;");
                    else append_char(&pieces, *p);
                }
            } else {
                if (m.kind == 1) push(&pieces, ass[m.tag]);
                if (m.kind == 0 || m.kind == 3) push_owned(&pieces, slice(p, m.size));
            }
            p += m.size;
        }
        char *raw = join(&pieces, "");
        char *text = mode == 2 ? raw : trim(raw);
        if (mode != 2) free(raw);
        if (mode == 2 || *text) push_owned(&result, text);
        else free(text);
        free_strings(&pieces);
    }
    return result;
}
static char *normalize(const char *s) {
    Strings lines = {0};
    push(&lines, s);
    Strings w = words(&lines);
    char *result = join(&w, " ");
    free_strings(&lines);
    free_strings(&w);
    return result;
}
static char *clean_hi(const char *line, int *segments, int *labels) {
    Strings parts = {0};
    *segments = *labels = 0;
    for (const char *p = line; *p;) {
        const char *end = *p == '[' ? strchr(p + 1, ']') : *p == '(' ? strchr(p + 1, ')') : NULL;
        if (end) {
            ++*segments;
            p = end + 1;
        }
        else append_char(&parts, *p++);
    }
    char *joined = join(&parts, ""), *text = normalize(joined);
    free(joined);
    free_strings(&parts);
    const char *prefix = "", *body = text;
    if (!strncmp(body, "- ", 2)) {
        prefix = "- ";
        body += 2;
    }
    const char *colon = strchr(body, ':');
    if (colon && colon > body) {
        bool valid = *body >= 'A' && *body <= 'Z';
        for (const char *p = body; p < colon; ++p) {
            if (!((*p >= 'A' && *p <= 'Z') || (*p >= '0' && *p <= '9') || *p == ' ')) valid = false;
        }
        if (valid) {
            *labels = 1;
            char *raw = format("%s%s", prefix, colon + 1), *replacement = normalize(raw);
            free(raw);
            free(text);
            text = replacement;
        }
    }
    return text;
}
static int parse_arguments(const char *line) {
    const char *names[] = {"LIST", "VALIDATE", "SEARCH", "AT", "GAPS", "STATS", "PRINT", "TOVTT", "TOASS", "FRAMES", "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP", "FIXOVERLAP", "EXTEND", "TIME", "SORT", "RENUMBER", "MERGE", "SPLIT", "INSERT", "DELETE", "TEXT", "BALANCE", "STRIP", "CLEANHI", "REPLACE", "UNDO"};
    const char *schemas[] = {"", "", "S", "T", "U", "", "", "", "", "F", "I", "PI", "UU", "PTPT", "F", "U", "U", "PTT", "", "", "U", "U", "PTTX", "P", "PX", "", "", "", "R", ""};
    const char *space = strchr(line, ' ');
    size_t length = space ? (size_t)(space - line) : strlen(line);
    int cmd = -1;
    for (int i = 0; i < 30; ++i) if (strlen(names[i]) == length && !strncmp(line, names[i], length)) cmd = i;
    if (cmd < 0) fail("unknown command");
    Arguments *a = &arguments;
    strcpy(a->name, names[cmd]);
    strcpy(a->schema, schemas[cmd]);
    a->denominator = 1;
    if (space) a->raw = split(space + 1, ' ', strpbrk(a->schema, "SXR") ? (int)strlen(a->schema) : 0);
    if (cmd == 23 && a->raw.count == 2) strcpy(a->schema, "PP");
    if (a->raw.count != (int)strlen(a->schema)) fail("bad arguments");
    for (int i = 0; i < a->raw.count; ++i) {
        const char *s = a->raw.items[i];
        char kind = a->schema[i];
        Integer value = 0;
        bool valid = true;
        if (kind == 'P' || kind == 'U') {
            valid = unsigned_value(s, &value);
            if (kind == 'P' && value == 0) valid = false;
        } else if (kind == 'I') {
            bool negative = *s == '-';
            valid = unsigned_value(s + (negative ? 1 : 0), &value);
            if (negative) value = -value;
        } else if (kind == 'T') valid = time_value(s, &value);
        else if (kind == 'F') {
            Strings parts = split(s, '/', 0);
            if (parts.count > 2) valid = false;
            else {
                valid = unsigned_value(parts.items[0], &value);
                if (parts.count == 2) valid = unsigned_value(parts.items[1], &a->denominator) && valid;
                valid = valid && value >= 1 && value <= 100000 && a->denominator >= 1 && a->denominator <= 100000;
            }
            free_strings(&parts);
        } else if (kind == 'X') {
            Strings parts = split(s, '|', 0);
            for (int j = 0; j < parts.count; ++j) if (!*parts.items[j]) valid = false;
            free_strings(&parts);
        } else if (kind == 'R') {
            Strings parts = split(s, '|', 0);
            valid = parts.count == 2 && *parts.items[0] && *parts.items[1];
            free_strings(&parts);
        } else if (kind == 'S') valid = *s != '\0';
        if (!valid) fail("bad arguments");
        a->values[i] = value;
    }
    Integer *v = a->values;
    if (cmd == 12 && (v[0] < 1 || v[0] > 100000 || v[1] < 1 || v[1] > 100000)) fail("bad arguments");
    if (cmd == 4 || cmd == 15 || cmd == 16 || cmd == 20) {
        if (v[0] < (cmd == 16 ? 1 : 0) || v[0] > 60000) fail("bad arguments");
    }
    if (cmd == 21 && (v[0] < 10 || v[0] > 80)) fail("bad arguments");
    if (cmd == 23 && a->raw.count == 2 && v[1] < v[0]) fail("bad arguments");
    Integer limit = cues.count + (cmd == 22 ? 1 : 0);
    for (int i = 0; i < a->raw.count; ++i) {
        if (a->schema[i] == 'P' && v[i] > limit) {
            char message[64];
            snprintf(message, sizeof message, "no cue %" PRId64, v[i]);
            fail(message);
        }
    }
    return cmd;
}
static char *cue_line(int position, const Cue *c) {
    char *start = time_text(c->start, 0), *end = time_text(c->end, 0), *joined = join(&c->text, "|");
    char *result = format("%d %" PRId64 " %s %s %s", position, c->index, start, end, joined);
    free(start);
    free(end);
    free(joined);
    return result;
}
static int compare_order(const void *left, const void *right) {
    int i = *(const int *)left, j = *(const int *)right;
    const Cue *a = &cues.items[i], *b = &cues.items[j];
    if (a->start != b->start) return a->start < b->start ? -1 : 1;
    if (a->end != b->end) return a->end < b->end ? -1 : 1;
    return i < j ? -1 : i > j;
}
static void execute(const char *line, Strings *out) {
    int cmd = parse_arguments(line), n = cues.count;
    Arguments *a = &arguments;
    Integer *v = a->values;
    if (cmd == 29) {
        if (!history_count) fail("nothing to undo");
        Record *previous = &history[--history_count];
        free_cues(&cues);
        cues = previous->cues;
        previous->cues = (Cues){0};
        push_owned(out, format("UNDO command=%s", previous->name));
        return;
    }
    if (cmd == 13 && cues.items[v[0] - 1].start == cues.items[v[2] - 1].start) fail("sync points coincide");
    if (cmd >= 10 && cmd <= 28) {
        Record *r = &history[history_count++];
        strcpy(r->name, a->name);
        r->cues = clone_cues(&cues);
    }
    if (cmd == 0 || cmd == 3) {
        int matches = 0;
        for (int i = 0; i < n; ++i) {
            const Cue *c = &cues.items[i];
            if (cmd == 0 || (c->start <= v[0] && v[0] < c->end)) {
                push_owned(out, cue_line(i + 1, c));
                ++matches;
            }
        }
        if (cmd == 3) push_owned(out, format("AT active=%d", matches));
    } else if (cmd == 1) {
        for (int i = 0; i < n; ++i) {
            const Cue *c = &cues.items[i];
            Integer d = c->end - c->start;
            if (c->index != i + 1) push_owned(out, format("cue %d: index %" PRId64 " (expected %d)", i + 1, c->index, i + 1));
            if (d <= 0) push_owned(out, format("cue %d: end not after start", i + 1));
            if (i && c->start < cues.items[i - 1].end) push_owned(out, format("cue %d: overlaps previous by %" PRId64 " ms", i + 1, cues.items[i - 1].end - c->start));
            if (d >= 1 && d < 700) push_owned(out, format("cue %d: too short (%" PRId64 " ms)", i + 1, d));
            if (d > 7000) push_owned(out, format("cue %d: too long (%" PRId64 " ms)", i + 1, d));
            for (int j = 0; j < c->text.count; ++j) {
                size_t length = strlen(c->text.items[j]);
                if (length > 42) push_owned(out, format("cue %d: line %d too long (%zu chars)", i + 1, j + 1, length));
            }
            if (c->text.count >= 3) push_owned(out, format("cue %d: too many lines (%d)", i + 1, c->text.count));
            Integer chars = count_chars(c);
            if (d >= 1 && chars * 1000 > 21 * d) {
                char *speed = decimal(chars * 100000 / d);
                push_owned(out, format("cue %d: too fast (%s cps)", i + 1, speed));
                free(speed);
            }
        }
        push_owned(out, format("VALIDATE problems=%d", out->count));
    } else if (cmd == 2) {
        for (int i = 0; i < n; ++i) {
            const Cue *c = &cues.items[i];
            for (int j = 0; j < c->text.count; ++j) {
                if (strstr(c->text.items[j], a->raw.items[0])) {
                    char *start = time_text(c->start, 0);
                    push_owned(out, format("%d %s %s", i + 1, start, c->text.items[j]));
                    free(start);
                    break;
                }
            }
        }
        push_owned(out, format("SEARCH found=%d", out->count));
    } else if (cmd == 4) {
        for (int i = 0; i + 1 < n; ++i) {
            Integer gap = cues.items[i + 1].start - cues.items[i].end;
            if (gap < v[0]) push_owned(out, format("%d %d %" PRId64, i + 1, i + 2, gap));
        }
        push_owned(out, format("GAPS count=%d", out->count));
    } else if (cmd == 5) {
        push_owned(out, format("STATS cues=%d", n));
        if (!n) return;
        Integer total = 0, chars = 0, longest = 0;
        int position = 1;
        for (int i = 0; i < n; ++i) {
            Integer d = cues.items[i].end - cues.items[i].start;
            if (d < 0) d = 0;
            total += d;
            if (d) chars += count_chars(&cues.items[i]);
            if (d > longest) {
                longest = d;
                position = i + 1;
            }
        }
        char *total_text = time_text(total, 0), *mean = time_text(total / n, 0);
        push_owned(out, format("duration total=%s mean=%s", total_text, mean));
        free(total_text);
        free(mean);
        char *speed = total ? decimal(chars * 100000 / total) : copy_string("-");
        push_owned(out, format("speed %s", speed));
        free(speed);
        char *long_text = time_text(longest, 0);
        push_owned(out, format("longest cue=%d duration=%s", position, long_text));
        free(long_text);
        if (n == 1) push(out, "gap none");
        else {
            position = 1;
            Integer gap = cues.items[1].start - cues.items[0].end;
            for (int i = 1; i + 1 < n; ++i) {
                Integer candidate = cues.items[i + 1].start - cues.items[i].end;
                if (candidate > gap) {
                    gap = candidate;
                    position = i + 1;
                }
            }
            push_owned(out, format("gap cue=%d ms=%" PRId64, position, gap));
        }
    } else if (cmd == 6 || cmd == 7) {
        if (cmd == 7) {
            push(out, "WEBVTT");
            push(out, "");
        }
        for (int i = 0; i < n; ++i) {
            const Cue *c = &cues.items[i];
            int code = 0, removed = 0;
            Strings lines = cmd == 7 ? converted(&c->text, 1, &code, &removed) : c->text;
            if (!lines.count) {
                if (cmd == 7) free_strings(&lines);
                continue;
            }
            char setting[64] = "";
            if (code >= 7) strcat(setting, " line:0");
            else if (code >= 4) strcat(setting, " line:50%");
            if (code && code % 3 == 1) strcat(setting, " align:start");
            if (code && code % 3 == 0) strcat(setting, " align:end");
            char *start = time_text(c->start, cmd == 7), *end = time_text(c->end, cmd == 7);
            push_owned(out, format("%" PRId64, c->index));
            push_owned(out, format("%s --> %s%s", start, end, setting));
            free(start);
            free(end);
            for (int j = 0; j < lines.count; ++j) push(out, lines.items[j]);
            push(out, "");
            if (cmd == 7) free_strings(&lines);
        }
    } else if (cmd == 8) {
        push(out, "[Events]");
        push(out, "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text");
        for (int i = 0; i < n; ++i) {
            Cue *c = &cues.items[i];
            int first, removed;
            Strings lines = converted(&c->text, 2, &first, &removed);
            char *joined = join(&lines, "\\N"), *start = time_text(c->start, 2), *end = time_text(c->end, 2);
            push_owned(out, format("Dialogue: 0,%s,%s,Default,,0,0,0,,%s", start, end, joined));
            free(joined);
            free(start);
            free(end);
            free_strings(&lines);
        }
    } else if (cmd == 9) {
        for (int i = 0; i < n; ++i) push_owned(out, format("%d %" PRId64 " %" PRId64, i + 1, cues.items[i].start * v[0] / (1000 * a->denominator), cues.items[i].end * v[0] / (1000 * a->denominator)));
    } else if (cmd >= 10 && cmd <= 14) {
        int start = cmd == 11 ? (int)v[0] - 1 : 0, clamped = 0, changed = 0;
        Integer shift = cmd == 10 ? v[0] : cmd == 11 ? v[1] : 0;
        Integer s1 = 0, s2 = 0;
        if (cmd == 13) {
            s1 = cues.items[v[0] - 1].start;
            s2 = cues.items[v[2] - 1].start;
        }
        for (int i = start; i < n; ++i) {
            bool cue_clamped = false;
            Integer *times[] = {&cues.items[i].start, &cues.items[i].end};
            for (int j = 0; j < 2; ++j) {
                Integer old = *times[j], value = old;
                if (cmd == 10 || cmd == 11) value += shift;
                if (cmd == 12) value = half_up(value * v[0], v[1]);
                if (cmd == 13) value = half_up(v[1] * (s2 - s1) + (value - s1) * (v[3] - v[1]), s2 - s1);
                if (cmd == 14) {
                    Integer frame = half_up(value * v[0], 1000 * a->denominator);
                    value = half_up(frame * 1000 * a->denominator, v[0]);
                }
                if (value < 0) {
                    value = 0;
                    cue_clamped = true;
                }
                if (value != old) ++changed;
                *times[j] = value;
            }
            if (cue_clamped) ++clamped;
        }
        if (cmd == 14) push_owned(out, format("SNAP changed=%d", changed));
        else if (cmd == 12) push_owned(out, format("SCALE cues=%d", n));
        else push_owned(out, format("%s cues=%d clamped=%d", a->name, n - start, clamped));
    } else if (cmd == 15) {
        int fixed = 0, failed = 0;
        for (int i = 0; i + 1 < n; ++i) {
            Integer candidate = cues.items[i + 1].start - v[0];
            if (cues.items[i].end > candidate) {
                if (candidate > cues.items[i].start) {
                    cues.items[i].end = candidate;
                    ++fixed;
                } else {
                    ++failed;
                    push_owned(out, format("cue %d: cannot fix", i + 1));
                }
            }
        }
        push_owned(out, format("FIXOVERLAP fixed=%d failed=%d", fixed, failed));
    } else if (cmd == 16) {
        int extended = 0, short_count = 0;
        for (int i = 0; i < n; ++i) {
            Cue *c = &cues.items[i];
            if (c->end - c->start < v[0]) {
                Integer candidate = c->start + v[0];
                if (i + 1 < n && cues.items[i + 1].start < candidate) candidate = cues.items[i + 1].start;
                if (candidate > c->end) {
                    c->end = candidate;
                    ++extended;
                }
            }
            if (c->end - c->start < v[0]) ++short_count;
        }
        push_owned(out, format("EXTEND extended=%d short=%d", extended, short_count));
    } else if (cmd == 17) {
        cues.items[v[0] - 1].start = v[1];
        cues.items[v[0] - 1].end = v[2];
        push_owned(out, format("TIME cue=%" PRId64, v[0]));
    } else if (cmd == 18) {
        int *order = allocate((size_t)n * sizeof *order), moved = 0;
        for (int i = 0; i < n; ++i) order[i] = i;
        qsort(order, n, sizeof *order, compare_order);
        Cues sorted = {0};
        for (int i = 0; i < n; ++i) {
            push_cue(&sorted, cues.items[order[i]]);
            if (i != order[i]) ++moved;
        }
        free(order);
        free(cues.items);
        cues = sorted;
        push_owned(out, format("SORT moved=%d", moved));
    } else if (cmd == 19) {
        int changed = 0;
        for (int i = 0; i < n; ++i) {
            if (cues.items[i].index != i + 1) ++changed;
            cues.items[i].index = i + 1;
        }
        push_owned(out, format("RENUMBER changed=%d", changed));
    } else if (cmd == 20) {
        Cues result = {0};
        int merged = 0;
        for (int i = 0; i < n; ++i) {
            Cue c = cues.items[i];
            if (result.count) {
                Cue *previous = &result.items[result.count - 1];
                if (c.start - previous->end < v[0] && !dialogue(previous) && !dialogue(&c)) {
                    Strings lines = clone_strings(&previous->text);
                    for (int j = 0; j < c.text.count; ++j) push(&lines, c.text.items[j]);
                    Strings wrapped = wrap(&lines, 42);
                    free_strings(&lines);
                    if (wrapped.count <= 2) {
                        if (c.end > previous->end) previous->end = c.end;
                        free_strings(&previous->text);
                        previous->text = wrapped;
                        free_strings(&c.text);
                        ++merged;
                        continue;
                    }
                    free_strings(&wrapped);
                }
            }
            push_cue(&result, c);
        }
        free(cues.items);
        cues = result;
        push_owned(out, format("MERGE merged=%d cues=%d", merged, cues.count));
    } else if (cmd == 21) {
        Cues result = {0};
        int split_count = 0;
        for (int i = 0; i < n; ++i) {
            Cue c = cues.items[i];
            Integer d = c.end - c.start;
            if (d < 1 || dialogue(&c)) {
                push_cue(&result, c);
                continue;
            }
            Strings wrapped = wrap(&c.text, (int)v[0]);
            free_strings(&c.text);
            if (wrapped.count <= 2) {
                c.text = wrapped;
                push_cue(&result, c);
                continue;
            }
            ++split_count;
            int count = (wrapped.count + 1) / 2;
            Integer *lengths = allocate((size_t)count * sizeof *lengths);
            Integer *remainders = allocate((size_t)count * sizeof *remainders);
            int *order = allocate((size_t)count * sizeof *order);
            Cues parts = {0};
            Integer total = 0;
            for (int j = 0; j < wrapped.count; j += 2) {
                Cue part = {c.index, 0, 0, {0}};
                push(&part.text, wrapped.items[j]);
                if (j + 1 < wrapped.count) push(&part.text, wrapped.items[j + 1]);
                total += count_chars(&part);
                push_cue(&parts, part);
            }
            free_strings(&wrapped);
            Integer remaining = d;
            for (int j = 0; j < count; ++j) {
                Integer product = d * count_chars(&parts.items[j]);
                lengths[j] = product / total;
                remainders[j] = product % total;
                remaining -= lengths[j];
                order[j] = j;
            }
            for (int j = 1; j < count; ++j) {
                int part = order[j], k = j;
                while (k > 0 && remainders[order[k - 1]] < remainders[part]) {
                    order[k] = order[k - 1];
                    --k;
                }
                order[k] = part;
            }
            for (int j = 0; j < remaining; ++j) ++lengths[order[j]];
            Integer start = c.start;
            for (int j = 0; j < count; ++j) {
                parts.items[j].start = start;
                parts.items[j].end = start + lengths[j];
                start += lengths[j];
                push_cue(&result, parts.items[j]);
            }
            free(parts.items);
            free(lengths);
            free(remainders);
            free(order);
        }
        free(cues.items);
        cues = result;
        push_owned(out, format("SPLIT split=%d cues=%d", split_count, cues.count));
    } else if (cmd == 22) {
        Cue c = {v[0], v[1], v[2], split(a->raw.items[3], '|', 0)};
        int p = (int)v[0] - 1;
        push_cue(&cues, c);
        memmove(cues.items + p + 1, cues.items + p, (size_t)(n - p) * sizeof c);
        cues.items[p] = c;
        push_owned(out, format("INSERT cue=%" PRId64 " cues=%d", v[0], cues.count));
    } else if (cmd == 23) {
        int p = (int)v[0] - 1, q = (int)(a->raw.count == 2 ? v[1] : v[0]);
        for (int i = p; i < q; ++i) free_strings(&cues.items[i].text);
        memmove(cues.items + p, cues.items + q, (size_t)(n - q) * sizeof *cues.items);
        cues.count -= q - p;
        push_owned(out, format("DELETE removed=%d cues=%d", q - p, cues.count));
    } else if (cmd == 24) {
        Cue *c = &cues.items[v[0] - 1];
        free_strings(&c->text);
        c->text = split(a->raw.items[1], '|', 0);
        push_owned(out, format("TEXT cue=%" PRId64 " lines=%d", v[0], c->text.count));
    } else if (cmd == 25) {
        int changed = 0, skipped = 0, dialogues = 0;
        for (int i = 0; i < n; ++i) {
            Cue *c = &cues.items[i];
            if (dialogue(c)) {
                ++dialogues;
                continue;
            }
            Strings w = words(&c->text), candidate = {0};
            char *all = join(&w, " ");
            if (strlen(all) <= 42) push(&candidate, all);
            else if (strlen(all) <= 85) {
                size_t best_difference = SIZE_MAX, best_first = SIZE_MAX;
                for (int j = 1; j < w.count; ++j) {
                    Strings left = {w.items, j, j}, right = {w.items + j, w.count - j, w.count - j};
                    char *first = join(&left, " "), *second = join(&right, " ");
                    size_t a_length = strlen(first), b_length = strlen(second);
                    size_t difference = a_length > b_length ? a_length - b_length : b_length - a_length;
                    if (a_length <= 42 && b_length <= 42 && (difference < best_difference || (difference == best_difference && a_length < best_first))) {
                        free_strings(&candidate);
                        push(&candidate, first);
                        push(&candidate, second);
                        best_difference = difference;
                        best_first = a_length;
                    }
                    free(first);
                    free(second);
                }
            }
            if (!candidate.count) ++skipped;
            else {
                if (!same_text(&candidate, &c->text)) ++changed;
                free_strings(&c->text);
                c->text = candidate;
            }
            free(all);
            free_strings(&w);
        }
        push_owned(out, format("BALANCE changed=%d skipped=%d dialogue=%d", changed, skipped, dialogues));
    } else if (cmd == 26 || cmd == 27) {
        int removed_items = 0, labels = 0, removed_lines = 0, removed_cues = 0;
        Cues result = {0};
        for (int i = 0; i < n; ++i) {
            Cue c = cues.items[i];
            Strings lines = {0};
            if (cmd == 26) {
                int first, tags;
                lines = converted(&c.text, 0, &first, &tags);
                removed_items += tags;
                removed_lines += c.text.count - lines.count;
            } else {
                for (int j = 0; j < c.text.count; ++j) {
                    int segments, names;
                    char *cleaned = clean_hi(c.text.items[j], &segments, &names);
                    removed_items += segments;
                    labels += names;
                    if (!*cleaned || !strcmp(cleaned, "-")) {
                        ++removed_lines;
                        free(cleaned);
                    }
                    else push_owned(&lines, cleaned);
                }
            }
            free_strings(&c.text);
            if (!lines.count) {
                ++removed_cues;
                free_strings(&lines);
            } else {
                c.text = lines;
                push_cue(&result, c);
            }
        }
        free(cues.items);
        cues = result;
        if (cmd == 26) push_owned(out, format("STRIP tags=%d removed_lines=%d removed_cues=%d", removed_items, removed_lines, removed_cues));
        else push_owned(out, format("CLEANHI segments=%d labels=%d removed_lines=%d removed_cues=%d", removed_items, labels, removed_lines, removed_cues));
    } else if (cmd == 28) {
        Strings pair = split(a->raw.items[0], '|', 0);
        const char *old = pair.items[0], *replacement = pair.items[1];
        int count = 0, matching_cues = 0;
        for (int i = 0; i < n; ++i) {
            int matches = 0;
            for (int j = 0; j < cues.items[i].text.count; ++j) {
                char **line = &cues.items[i].text.items[j];
                const char *p = *line, *found;
                Strings pieces = {0};
                while ((found = strstr(p, old)) != NULL) {
                    push_owned(&pieces, slice(p, (size_t)(found - p)));
                    push(&pieces, replacement);
                    p = found + strlen(old);
                    ++matches;
                }
                push(&pieces, p);
                char *result = join(&pieces, "");
                free_strings(&pieces);
                free(*line);
                *line = result;
            }
            count += matches;
            if (matches) ++matching_cues;
        }
        free_strings(&pair);
        push_owned(out, format("REPLACE count=%d cues=%d", count, matching_cues));
    }
}
static bool load_block(const Strings *block, int position) {
    Integer index = 0, start = 0, end = 0;
    if (!unsigned_value(block->items[0], &index) || strlen(block->items[0]) > 6) {
        printf("BAD CUE %d: index\n", position);
        return false;
    }
    bool valid = block->count >= 2 && strlen(block->items[1]) == 29 && !strncmp(block->items[1] + 12, " --> ", 5);
    if (valid) {
        char time[13];
        memcpy(time, block->items[1], 12);
        time[12] = '\0';
        valid = time_value(time, &start) && time_value(block->items[1] + 17, &end);
    }
    if (!valid) {
        printf("BAD CUE %d: time\n", position);
        return false;
    }
    if (block->count < 3) {
        printf("BAD CUE %d: no text\n", position);
        return false;
    }
    Cue c = {index, start, end, {0}};
    for (int i = 2; i < block->count; ++i) push(&c.text, block->items[i]);
    push_cue(&cues, c);
    return true;
}
int main(void) {
    char line[256];
    Strings block = {0};
    int blocks = 0, bad = 0;
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\n")] = '\0';
        bool terminator = !strcmp(line, "###");
        if (!*line || terminator) {
            if (block.count) {
                if (!load_block(&block, ++blocks)) ++bad;
                free_strings(&block);
            }
            if (terminator) break;
        } else push(&block, line);
    }
    printf("LOAD cues=%d bad=%d\n", cues.count, bad);
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        line[strcspn(line, "\n")] = '\0';
        arguments = (Arguments){0};
        if (setjmp(recovery) == 0) {
            Strings output = {0};
            execute(line, &output);
            for (int j = 0; j < output.count; ++j) puts(output.items[j]);
            free_strings(&output);
        } else printf("ERROR %s\n", error_message);
        free_strings(&arguments.raw);
    }
    free_cues(&cues);
    for (int i = 0; i < history_count; ++i) free_cues(&history[i].cues);
    return 0;
}
