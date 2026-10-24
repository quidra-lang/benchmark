#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef enum { NIL, NUMBER, STRING, BOOLEAN, ARRAY, OBJECT, MISSING } Kind;
typedef struct Value Value;
typedef struct {
    char *key;
    Value *value;
} Entry;
struct Value {
    Kind kind;
    int number;
    char *text;
    Value **items;
    Entry *entries;
    size_t count;
};
typedef struct {
    const char *text;
    size_t position, length;
    const char *path_error;
} Parser;
typedef struct {
    char kind;
    char *key;
    int first, last;
    bool has_first, has_last, descendant;
} Selector;
typedef struct {
    Selector *items;
    size_t count;
} Path;
typedef struct {
    char *key;
    size_t index, position;
    bool member;
} Step;
typedef struct {
    Value *value;
    Step *steps;
    size_t count;
} Match;
typedef struct {
    Match *items;
    size_t count;
} Matches;
static Value nil = { .kind = NIL }, missing = { .kind = MISSING }, *document = &nil;
static Value **history;
static size_t history_count;
static jmp_buf failure;
static char *error_reason;
static size_t error_position;
static bool parse_error;
static void *allocate(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}

static char *copy_text(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, pattern, saved);
    va_end(saved);
    return s;
}

static void fail(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)n + 1);
    vsnprintf(error_reason, (size_t)n + 1, pattern, saved);
    va_end(saved);
    parse_error = false;
    longjmp(failure, 1);
}

static void parser_fail(Parser *p, size_t position, const char *reason) {
    if (p->path_error) fail("%s", p->path_error);
    error_reason = copy_text(reason);
    error_position = position;
    parse_error = true;
    longjmp(failure, 1);
}

static void append_n(Buffer *b, const char *text, size_t n) {
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, text, n);
    b->length += n;
    b->data[b->length] = 0;
}

static void append(Buffer *b, const char *text) {
    append_n(b, text, strlen(text));
}

static void character(Buffer *b, char c) {
    append_n(b, &c, 1);
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy_text("");
}

static bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

static bool digit(char c) {
    return c >= '0' && c <= '9';
}

static bool identifier(const char *s) {
    if (!letter(*s) && *s != '_') return false;
    for (s++; *s; s++) if (!letter(*s) && !digit(*s) && *s != '_') return false;
    return true;
}

static bool integer_notation(const char *s) {
    if (!strcmp(s, "0")) return true;
    if (*s == '-') s++;
    size_t n = strlen(s);
    if (!n || n > 9 || *s == '0') return false;
    for (; *s; s++) if (!digit(*s)) return false;
    return true;
}

static int hex(char c) {
    return digit(c) ? c - '0' : c >= 'A' && c <= 'F' ? c - 'A' + 10 : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}

static char *quote(const char *s, char delimiter) {
    Buffer b = {0};
    character(&b, delimiter);
    for (; *s; s++) {
        if (*s == delimiter || *s == '\\') {
            character(&b, '\\');
            character(&b, *s);
        } else switch (*s) {
            case '\b':
                append(&b, "\\b");
                break;
            case '\f':
                append(&b, "\\f");
                break;
            case '\n':
                append(&b, "\\n");
                break;
            case '\r':
                append(&b, "\\r");
                break;
            case '\t':
                append(&b, "\\t");
                break;
            default:
                if ((unsigned char)*s < 32 || *s == 127) append(&b, format("\\u%04x", (unsigned char)*s));
                else character(&b, *s);
        }
    }
    character(&b, delimiter);
    return finish(&b);
}

static Value *make(Kind kind) {
    Value *v = allocate(sizeof(*v));
    v->kind = kind;
    return v;
}

static Value *string_value(char *s) {
    Value *v = make(STRING);
    v->text = s;
    return v;
}

static Value *number_value(int n) {
    Value *v = make(NUMBER);
    v->number = n;
    return v;
}

static int entry_index(Value *v, const char *key) {
    if (v->kind == OBJECT) for (size_t i = 0; i < v->count; i++) if (!strcmp(v->entries[i].key, key)) return (int)i;
    return -1;
}

static void push(Value *v, Value *item) {
    APPEND(v->items, v->count, item);
}

static void put(Value *v, char *key, Value *item) {
    int i = entry_index(v, key);
    if (i >= 0) v->entries[i].value = item;
    else APPEND(v->entries, v->count, ((Entry){key, item}));
}

static char peek(Parser *p) {
    return p->text[p->position];
}

static void whitespace(Parser *p) {
    while (peek(p) == ' ' || peek(p) == '\n') p->position++;
}

static void need_character(Parser *p) {
    if (p->position == p->length) parser_fail(p, p->position, "unexpected end of input");
}

static char *read_string(Parser *p, char delimiter) {
    p->position++;
    Buffer b = {0};
    while (true) {
        if (p->position == p->length || peek(p) == '\n') parser_fail(p, p->position, "unterminated string");
        char c = peek(p);
        if (c == delimiter) {
            p->position++;
            return finish(&b);
        }
        if (c != '\\') {
            character(&b, c);
            p->position++;
            continue;
        }
        size_t start = p->position++;
        if (p->position == p->length || peek(p) == '\n') parser_fail(p, p->position, "unterminated string");
        char escaped = peek(p);
        if (escaped == 'u') {
            if (p->position + 4 >= p->length) parser_fail(p, start, "bad unicode escape");
            int value = 0;
            for (size_t i = 1; i <= 4; i++) {
                int h = hex(p->text[p->position + i]);
                if (h < 0) parser_fail(p, start, "bad unicode escape");
                value = value * 16 + h;
            }
            if (value > 127) parser_fail(p, start, "non-ascii escape");
            character(&b, (char)value);
            p->position += 5;
        } else {
            char value = 0;
            switch (escaped) {
                case '\\':
                case '/':
                    value = escaped;
                    break;
                case 'b':
                    value = '\b';
                    break;
                case 'f':
                    value = '\f';
                    break;
                case 'n':
                    value = '\n';
                    break;
                case 'r':
                    value = '\r';
                    break;
                case 't':
                    value = '\t';
                    break;
                default:
                    if (escaped == delimiter) value = delimiter;
            }
            if (!value) parser_fail(p, start, format("invalid escape '\\%c'", escaped));
            character(&b, value);
            p->position++;
        }
    }
}

static Value *read_value(Parser *p) {
    whitespace(p);
    need_character(p);
    char c = peek(p);
    if (c == '"') return string_value(read_string(p, '"'));
    if (c == '{') {
        p->position++;
        whitespace(p);
        Value *v = make(OBJECT);
        if (peek(p) == '}') {
            p->position++;
            return v;
        }
        while (true) {
            whitespace(p);
            need_character(p);
            if (peek(p) != '"') parser_fail(p, p->position, "expected key");
            size_t start = p->position;
            char *key = read_string(p, '"');
            if (entry_index(v, key) >= 0) parser_fail(p, start, format("duplicate key %s", quote(key, '"')));
            whitespace(p);
            need_character(p);
            if (peek(p) != ':') parser_fail(p, p->position, "expected ':'");
            p->position++;
            put(v, key, read_value(p));
            whitespace(p);
            if (peek(p) == '}') {
                p->position++;
                return v;
            }
            need_character(p);
            if (peek(p) != ',') parser_fail(p, p->position, "expected ',' or '}'");
            p->position++;
            whitespace(p);
            if (peek(p) == '}') parser_fail(p, p->position, "trailing comma");
        }
    }
    if (c == '[') {
        p->position++;
        whitespace(p);
        Value *v = make(ARRAY);
        if (peek(p) == ']') {
            p->position++;
            return v;
        }
        while (true) {
            push(v, read_value(p));
            whitespace(p);
            if (peek(p) == ']') {
                p->position++;
                return v;
            }
            need_character(p);
            if (peek(p) != ',') parser_fail(p, p->position, "expected ',' or ']'");
            p->position++;
            whitespace(p);
            if (peek(p) == ']') parser_fail(p, p->position, "trailing comma");
        }
    }
    if (c == '-' || digit(c)) {
        size_t start = p->position;
        if (c == '-') p->position++;
        size_t digits = p->position;
        while (digit(peek(p))) p->position++;
        size_t n = p->position - digits;
        if (!n) parser_fail(p, start, "invalid number");
        if (n >= 2 && p->text[digits] == '0') parser_fail(p, digits, "leading zero");
        if (peek(p) == '.') parser_fail(p, p->position, "fraction not allowed");
        if (peek(p) == 'e' || peek(p) == 'E') parser_fail(p, p->position, "exponent not allowed");
        if (n >= 10) parser_fail(p, start, "number out of range");
        return number_value(atoi(slice(p->text + start, p->position - start)));
    }
    if (letter(c)) {
        size_t start = p->position;
        while (letter(peek(p))) p->position++;
        char *word = slice(p->text + start, p->position - start);
        if (!strcmp(word, "null")) return make(NIL);
        if (!strcmp(word, "true") || !strcmp(word, "false")) {
            Value *v = make(BOOLEAN);
            v->number = !strcmp(word, "true");
            return v;
        }
        parser_fail(p, start, format("invalid literal '%s'", word));
    }
    parser_fail(p, p->position, format("unexpected character '%c'", c));
    return NULL;
}

static Value *json(const char *text) {
    Parser p = {text, 0, strlen(text), NULL};
    Value *v = read_value(&p);
    whitespace(&p);
    if (p.position != p.length) parser_fail(&p, p.position, "trailing characters");
    return v;
}

static Value *clone(Value *v) {
    Value *out = make(v->kind);
    out->number = v->number;
    if (v->kind == STRING) out->text = copy_text(v->text);
    if (v->kind == ARRAY) for (size_t i = 0; i < v->count; i++) push(out, clone(v->items[i]));
    if (v->kind == OBJECT) for (size_t i = 0; i < v->count; i++) put(out, copy_text(v->entries[i].key), clone(v->entries[i].value));
    return out;
}

static char *compact(Value *v) {
    if (v->kind == NIL) return "null";
    if (v->kind == BOOLEAN) return v->number ? "true" : "false";
    if (v->kind == NUMBER) return format("%d", v->number);
    if (v->kind == STRING) return quote(v->text, '"');
    Buffer b = {0};
    character(&b, v->kind == OBJECT ? '{' : '[');
    for (size_t i = 0; i < v->count; i++) {
        if (i) character(&b, ',');
        if (v->kind == OBJECT) {
            append(&b, quote(v->entries[i].key, '"'));
            character(&b, ':');
        }
        append(&b, compact(v->kind == OBJECT ? v->entries[i].value : v->items[i]));
    }
    character(&b, v->kind == OBJECT ? '}' : ']');
    return finish(&b);
}

static char *pretty(Value *v, const char *indent) {
    if ((v->kind != ARRAY && v->kind != OBJECT) || !v->count) return compact(v);
    Buffer b = {0};
    char *child = format("%s  ", indent);
    character(&b, v->kind == OBJECT ? '{' : '[');
    character(&b, '\n');
    for (size_t i = 0; i < v->count; i++) {
        if (i) append(&b, ",\n");
        append(&b, child);
        if (v->kind == OBJECT) append(&b, format("%s: ", quote(v->entries[i].key, '"')));
        append(&b, pretty(v->kind == OBJECT ? v->entries[i].value : v->items[i], child));
    }
    append(&b, format("\n%s%c", indent, v->kind == OBJECT ? '}' : ']'));
    return finish(&b);
}

static const char *type(Value *v) {
    switch (v->kind) {
        case NIL:
            return "null";
        case NUMBER:
            return "number";
        case STRING:
            return "string";
        case BOOLEAN:
            return "boolean";
        case ARRAY:
            return "array";
        default:
            return "object";
    }
}

static char *read_identifier(Parser *p) {
    size_t start = p->position;
    if (!letter(peek(p)) && peek(p) != '_') fail("%s", p->path_error);
    p->position++;
    while (letter(peek(p)) || digit(peek(p)) || peek(p) == '_') p->position++;
    return slice(p->text + start, p->position - start);
}

static Path path(const char *text, bool field) {
    Parser p = {text, 0, strlen(text), field ? "ERROR bad field" : "ERROR bad path"};
    Path out = {0};
    if (peek(&p) != (field ? '@' : '$')) fail("%s", p.path_error);
    p.position++;
    while (p.position < p.length) {
        Selector s = {0};
        if (peek(&p) == '.') {
            p.position++;
            if (peek(&p) == '.') {
                if (field) fail("%s", p.path_error);
                s.descendant = true;
                p.position++;
            }
            if (peek(&p) == '*') {
                if (field) fail("%s", p.path_error);
                p.position++;
                s.kind = 'A';
                APPEND(out.items, out.count, s);
                continue;
            }
            if (!(s.descendant && peek(&p) == '[')) {
                s.kind = 'K';
                s.key = read_identifier(&p);
                APPEND(out.items, out.count, s);
                continue;
            }
        } else if (peek(&p) != '[') fail("%s", p.path_error);
        if (peek(&p) != '[') fail("%s", p.path_error);
        p.position++;
        if (peek(&p) == '\'') {
            s.kind = 'K';
            s.key = read_string(&p, '\'');
            if (peek(&p) != ']') fail("%s", p.path_error);
            p.position++;
            APPEND(out.items, out.count, s);
            continue;
        }
        const char *end = strchr(text + p.position, ']');
        if (!end) fail("%s", p.path_error);
        char *content = slice(text + p.position, (size_t)(end - text) - p.position);
        p.position = (size_t)(end - text) + 1;
        if (!strcmp(content, "*") && !field) s.kind = 'A';
        else if (integer_notation(content)) {
            s.kind = 'I';
            s.first = atoi(content);
            s.has_first = true;
        } else if (!field && strchr(content, ':')) {
            char *colon = strchr(content, ':'), *first = slice(content, (size_t)(colon - content)), *last = colon + 1;
            if (strchr(last, ':') || (*first && !integer_notation(first)) || (*last && !integer_notation(last))) fail("%s", p.path_error);
            s.kind = 'S';
            s.has_first = *first;
            s.has_last = *last;
            s.first = atoi(first);
            s.last = atoi(last);
        } else fail("%s", p.path_error);
        APPEND(out.items, out.count, s);
    }
    return out;
}

static char *rename_key(const char *text) {
    if (identifier(text)) return copy_text(text);
    Parser p = {text, 0, strlen(text), "ERROR bad key"};
    if (peek(&p) != '\'') fail("ERROR bad key");
    char *key = read_string(&p, '\'');
    if (p.position != p.length) fail("ERROR bad key");
    return key;
}

static Match child(Match parent, Step step) {
    Match out = { .count = parent.count + 1 };
    out.steps = allocate(out.count * sizeof(*out.steps));
    if (parent.count) memcpy(out.steps, parent.steps, parent.count * sizeof(*out.steps));
    out.steps[parent.count] = step;
    out.value = step.member ? parent.value->entries[step.position].value : parent.value->items[step.index];
    return out;
}

static Matches children(Match parent) {
    Matches out = {0};
    Value *v = parent.value;
    if (v->kind == OBJECT || v->kind == ARRAY) for (size_t i = 0; i < v->count; i++) {
        Step step = {.key = v->kind == OBJECT ? v->entries[i].key : NULL, .index = i, .position = i, .member = v->kind == OBJECT};
        APPEND(out.items, out.count, child(parent, step));
    }
    return out;
}

static void preorder(Match match, Matches *out) {
    APPEND(out->items, out->count, match);
    Matches kids = children(match);
    for (size_t i = 0; i < kids.count; i++) preorder(kids.items[i], out);
}

static Matches select_values(Match match, Selector s) {
    Matches out = {0};
    Value *v = match.value;
    if (s.kind == 'K' && v->kind == OBJECT) {
        int index = entry_index(v, s.key);
        if (index >= 0) APPEND(out.items, out.count, child(match, ((Step){s.key, 0, (size_t)index, true})));
    } else if (s.kind == 'A') out = children(match);
    else if (v->kind == ARRAY && (s.kind == 'I' || s.kind == 'S')) {
        int n = (int)v->count;
        if (s.kind == 'I') {
            int i = s.first < 0 ? n + s.first : s.first;
            if (i >= 0 && i < n) APPEND(out.items, out.count, child(match, ((Step){NULL, (size_t)i, (size_t)i, false})));
        } else {
            int a = s.has_first ? s.first : 0, b = s.has_last ? s.last : n;
            if (a < 0) a += n;
            if (b < 0) b += n;
            if (a < 0) a = 0;
            if (a > n) a = n;
            if (b < 0) b = 0;
            if (b > n) b = n;
            for (int i = a; i < b; i++) APPEND(out.items, out.count, child(match, ((Step){NULL, (size_t)i, (size_t)i, false})));
        }
    }
    return out;
}

static Matches apply(Matches matches, Selector s) {
    Matches out = {0};
    for (size_t i = 0; i < matches.count; i++) {
        Matches bases = {0};
        if (s.descendant) preorder(matches.items[i], &bases);
        else APPEND(bases.items, bases.count, matches.items[i]);
        for (size_t j = 0; j < bases.count; j++) {
            Matches values = select_values(bases.items[j], s);
            for (size_t k = 0; k < values.count; k++) APPEND(out.items, out.count, values.items[k]);
        }
    }
    return out;
}

static Matches evaluate(Path path) {
    Matches out = {0};
    APPEND(out.items, out.count, ((Match){.value = document}));
    for (size_t i = 0; i < path.count; i++) out = apply(out, path.items[i]);
    return out;
}

static char *location(Match match) {
    Buffer b = {0};
    character(&b, '$');
    for (size_t i = 0; i < match.count; i++) {
        Step s = match.steps[i];
        if (s.member) append(&b, identifier(s.key) ? format(".%s", s.key) : format("[%s]", quote(s.key, '\'')));
        else append(&b, format("[%zu]", s.index));
    }
    return finish(&b);
}

static Value *at(Value *root, Step *steps, size_t count) {
    Value *v = root;
    for (size_t i = 0; i < count; i++) v = steps[i].member ? v->entries[entry_index(v, steps[i].key)].value : v->items[steps[i].index];
    return v;
}

static Value *field(Value *value, Path p) {
    for (size_t i = 0; i < p.count; i++) {
        Matches selected = select_values((Match){.value = value}, p.items[i]);
        if (!selected.count) return &missing;
        value = selected.items[0].value;
    }
    return value;
}

static bool equal(Value *a, Value *b) {
    if (a->kind != b->kind) return false;
    if (a->kind == NIL) return true;
    if (a->kind == NUMBER || a->kind == BOOLEAN) return a->number == b->number;
    if (a->kind == STRING) return !strcmp(a->text, b->text);
    if (a->count != b->count) return false;
    for (size_t i = 0; i < a->count; i++) {
        if (a->kind == ARRAY) {
            if (!equal(a->items[i], b->items[i])) return false;
        } else {
            int j = entry_index(b, a->entries[i].key);
            if (j < 0 || !equal(a->entries[i].value, b->entries[j].value)) return false;
        }
    }
    return true;
}

static int rank(Value *v) {
    return v->kind == NIL ? 0 : v->kind == NUMBER ? 1 : v->kind == STRING ? 2 : 3;
}

static int compare(Value *a, Value *b) {
    int d = rank(a) - rank(b);
    if (d) return d;
    if (a->kind == NUMBER) return (a->number > b->number) - (a->number < b->number);
    return a->kind == STRING ? strcmp(a->text, b->text) : 0;
}

static void merge(Value *target, Value *source) {
    for (size_t i = 0; i < source->count; i++) {
        Entry e = source->entries[i];
        int j = entry_index(target, e.key);
        if (j >= 0 && target->entries[j].value->kind == OBJECT && e.value->kind == OBJECT) merge(target->entries[j].value, e.value);
        else put(target, e.key, clone(e.value));
    }
}

static int compare_locations(const Match *a, const Match *b) {
    size_t n = a->count < b->count ? a->count : b->count;
    for (size_t i = 0; i < n; i++) if (a->steps[i].position != b->steps[i].position) return a->steps[i].position > b->steps[i].position ? 1 : -1;
    return (a->count > b->count) - (a->count < b->count);
}

static int reverse_locations(const void *a, const void *b) {
    return compare_locations(b, a);
}

static Matches targets(Matches matches) {
    Matches out = {0};
    if (matches.count) qsort(matches.items, matches.count, sizeof(*matches.items), reverse_locations);
    for (size_t i = 0; i < matches.count; i++) if (!i || compare_locations(matches.items + i, matches.items + i - 1)) APPEND(out.items, out.count, matches.items[i]);
    return out;
}

static void require_type(Matches matches, Kind kind) {
    for (size_t i = 0; i < matches.count; i++) if (matches.items[i].value->kind != kind) fail("ERROR not an %s at %s", kind == ARRAY ? "array" : "object", location(matches.items[i]));
}

static bool one_of(const char *word, const char *words) {
    if (!*word || strchr(word, ' ')) return false;
    return strstr(words, format(" %s ", word)) != NULL;
}

static char **arguments(const char *text, size_t limit, size_t *count) {
    char **out = NULL;
    *count = 0;
    if (!text) return out;
    size_t start = 0;
    for (size_t i = 0;; i++) if (!text[i] || (text[i] == ' ' && *count + 1 < limit)) {
        APPEND(out, *count, slice(text + start, i - start));
        start = i + 1;
        if (!text[i]) break;
    }
    return out;
}

static void add_output(Buffer *out, const char *line) {
    append(out, line);
    character(out, '\n');
}

static char *execute(const char *line) {
    const char *space = strchr(line, ' '), *argument = space ? space + 1 : NULL;
    char *command = space ? slice(line, (size_t)(space - line)) : copy_text(line);
    if (!one_of(command, " GET  COMPACT  PRETTY  TYPE  LENGTH  KEYS  FLATTEN  COUNT  SUM  MIN  MAX  AVG  FILTER  SET  DELETE  INSERT  MERGE  SORT  RENAME  UNDO ")) fail("ERROR unknown command '%s'", command);
    size_t argc, limit = one_of(command, " SET  MERGE ") ? 2 : !strcmp(command, "INSERT") ? 3 : !strcmp(command, "FILTER") ? 4 : SIZE_MAX;
    char **args = arguments(argument, limit, &argc);
    bool shape = one_of(command, " SET  MERGE  RENAME ") ? argc == 2 : !strcmp(command, "INSERT") ? argc == 3 : !strcmp(command, "FILTER") ? argc >= 3 && (!strcmp(args[2], "EXISTS") ? argc == 3 : argc == 4) : one_of(command, " COMPACT  PRETTY  FLATTEN ") ? argc <= 1 : !strcmp(command, "UNDO") ? argc == 0 : !strcmp(command, "SORT") ? argc >= 1 && argc <= 3 && (argc < 3 || (strcmp(args[1], "DESC") && !strcmp(args[2], "DESC"))) : argc == 1;
    if (!shape) fail("ERROR bad arguments");
    if (!strcmp(command, "UNDO")) {
        if (!history_count) fail("ERROR nothing to undo");
        document = history[--history_count];
        return format("UNDO %zu\n", history_count);
    }
    Path p = path(argc ? args[0] : "$", false), fields = {0};
    Value *value = &nil;
    int index = 0;
    char *rename = NULL, *op = NULL;
    if (!strcmp(command, "FILTER")) {
        fields = path(args[1], true);
        op = args[2];
        if (!one_of(op, " ==  !=  <  <=  >  >=  EXISTS ")) fail("ERROR bad operator");
        if (strcmp(op, "EXISTS")) value = json(args[3]);
    } else if (!strcmp(command, "SORT")) fields = path(argc >= 2 && strcmp(args[1], "DESC") ? args[1] : "@", true);
    else if (!strcmp(command, "RENAME")) rename = rename_key(args[1]);
    else if (!strcmp(command, "INSERT")) {
        if (!integer_notation(args[1])) fail("ERROR bad index");
        index = atoi(args[1]);
        value = json(args[2]);
    } else if (one_of(command, " SET  MERGE ")) value = json(args[1]);
    if (!strcmp(command, "MERGE") && value->kind != OBJECT) fail("ERROR merge value is not an object");
    if (!strcmp(command, "DELETE") && !p.count) fail("ERROR cannot delete root");
    Matches matches = evaluate(p);
    if (one_of(command, " FILTER  INSERT  SORT ")) require_type(matches, ARRAY);
    if (one_of(command, " KEYS  MERGE ")) require_type(matches, OBJECT);
    if (!strcmp(command, "LENGTH")) for (size_t i = 0; i < matches.count; i++) {
        Kind kind = matches.items[i].value->kind;
        if (kind != OBJECT && kind != ARRAY && kind != STRING) fail("ERROR no length at %s", location(matches.items[i]));
    }
    if (!strcmp(command, "INSERT")) for (size_t i = 0; i < matches.count; i++) {
        int n = (int)matches.items[i].value->count;
        if (index < -n - 1 || index > n) fail("ERROR index out of range at %s", location(matches.items[i]));
    }
    if (!strcmp(command, "RENAME")) for (size_t i = 0; i < matches.count; i++) if (!matches.items[i].count || !matches.items[i].steps[matches.items[i].count - 1].member) fail("ERROR not a member at %s", location(matches.items[i]));
    if (one_of(command, " SET  DELETE  INSERT  MERGE  SORT  RENAME ")) {
        if (!strcmp(command, "SET") && p.count) {
            Selector last = p.items[p.count - 1];
            if (last.kind == 'K' && !last.descendant) {
                Path parents_path = p;
                parents_path.count--;
                Matches parents = evaluate(parents_path);
                matches = (Matches){0};
                for (size_t i = 0; i < parents.count; i++) {
                    Match parent = parents.items[i];
                    if (parent.value->kind != OBJECT) continue;
                    int position = entry_index(parent.value, last.key);
                    Match target = { .value = &nil, .count = parent.count + 1 };
                    target.steps = allocate(target.count * sizeof(*target.steps));
                    if (parent.count) memcpy(target.steps, parent.steps, parent.count * sizeof(*target.steps));
                    target.steps[parent.count] = (Step){last.key, 0, position < 0 ? parent.value->count : (size_t)position, true};
                    APPEND(matches.items, matches.count, target);
                }
            }
        }
        Matches places = targets(matches);
        Value *changed = clone(document);
        for (size_t i = 0; i < places.count; i++) {
            Match target = places.items[i];
            Value *current = !strcmp(command, "SET") ? NULL : at(changed, target.steps, target.count);
            if (!strcmp(command, "SET")) {
                if (!target.count) changed = clone(value);
                else {
                    Value *parent = at(changed, target.steps, target.count - 1);
                    Step s = target.steps[target.count - 1];
                    if (s.member) put(parent, s.key, clone(value));
                    else parent->items[s.index] = clone(value);
                }
            } else if (!strcmp(command, "DELETE")) {
                Value *parent = at(changed, target.steps, target.count - 1);
                Step s = target.steps[target.count - 1];
                size_t j = s.member ? (size_t)entry_index(parent, s.key) : s.index;
                if (s.member) memmove(parent->entries + j, parent->entries + j + 1, (parent->count - j - 1) * sizeof(*parent->entries));
                else memmove(parent->items + j, parent->items + j + 1, (parent->count - j - 1) * sizeof(*parent->items));
                parent->count--;
            } else if (!strcmp(command, "INSERT")) {
                size_t j = index < 0 ? (size_t)((int)current->count + 1 + index) : (size_t)index;
                current->items = resize(current->items, (current->count + 1) * sizeof(*current->items));
                memmove(current->items + j + 1, current->items + j, (current->count - j) * sizeof(*current->items));
                current->items[j] = clone(value);
                current->count++;
            } else if (!strcmp(command, "MERGE")) merge(current, value);
            else if (!strcmp(command, "SORT")) {
                int direction = !strcmp(args[argc - 1], "DESC") ? -1 : 1;
                for (size_t j = 1; j < current->count; j++) {
                    Value *item = current->items[j], *key = field(item, fields);
                    size_t k = j;
                    while (k && direction * compare(field(current->items[k - 1], fields), key) > 0) {
                        current->items[k] = current->items[k - 1];
                        k--;
                    }
                    current->items[k] = item;
                }
            } else {
                Value *parent = at(changed, target.steps, target.count - 1);
                char *old = target.steps[target.count - 1].key;
                if (strcmp(old, rename) && entry_index(parent, rename) >= 0) fail("ERROR key exists at %s", location(target));
                parent->entries[entry_index(parent, old)].key = rename;
            }
        }
        APPEND(history, history_count, clone(document));
        document = changed;
        return format("%s %zu\n", command, places.count);
    }
    if (!strcmp(command, "COUNT")) return format("COUNT %zu\n", matches.count);
    if (one_of(command, " SUM  MIN  MAX  AVG ")) {
        int64_t total = 0;
        int minimum = 0, maximum = 0;
        size_t count = 0;
        for (size_t i = 0; i < matches.count; i++) if (matches.items[i].value->kind == NUMBER) {
            int n = matches.items[i].value->number;
            total += n;
            if (!count || n < minimum) minimum = n;
            if (!count || n > maximum) maximum = n;
            count++;
        }
        char *result = !strcmp(command, "SUM") ? format("%lld", (long long)total) : !count ? "null" : format("%d", !strcmp(command, "MIN") ? minimum : maximum);
        if (!strcmp(command, "AVG")) {
            if (!count) result = "null";
            else {
                int64_t q = ((total < 0 ? -total : total) * 200 + (int64_t)count) / (2 * (int64_t)count);
                result = format("%s%lld.%02lld", total < 0 && q ? "-" : "", (long long)(q / 100), (long long)(q % 100));
            }
        }
        return format("%s %s\n", command, result);
    }
    Buffer out = {0};
    if (!strcmp(command, "FILTER")) {
        for (size_t i = 0; i < matches.count; i++) {
            Matches kids = children(matches.items[i]);
            for (size_t j = 0; j < kids.count; j++) {
                Match child = kids.items[j];
                Value *f = field(child.value, fields);
                bool equality = f != &missing && equal(f, value), pass;
                if (!strcmp(op, "EXISTS")) pass = f != &missing;
                else if (!strcmp(op, "==") || !strcmp(op, "!=")) pass = (!strcmp(op, "==")) == equality;
                else {
                    bool comparable = (f->kind == NUMBER && value->kind == NUMBER) || (f->kind == STRING && value->kind == STRING);
                    int order = comparable ? compare(f, value) : 0;
                    pass = comparable && (!strcmp(op, "<") ? order < 0 : !strcmp(op, "<=") ? order <= 0 : !strcmp(op, ">") ? order > 0 : order >= 0);
                }
                if (pass) add_output(&out, format("%s = %s", location(child), compact(child.value)));
            }
        }
    } else for (size_t i = 0; i < matches.count; i++) {
        Match match = matches.items[i];
        Value *v = match.value;
        char *place = location(match);
        if (!strcmp(command, "GET")) add_output(&out, format("%s = %s", place, compact(v)));
        else if (!strcmp(command, "COMPACT")) add_output(&out, compact(v));
        else if (!strcmp(command, "PRETTY")) add_output(&out, pretty(v, ""));
        else if (!strcmp(command, "TYPE")) add_output(&out, format("%s %s", place, type(v)));
        else if (!strcmp(command, "LENGTH")) add_output(&out, format("%s %zu", place, v->kind == STRING ? strlen(v->text) : v->count));
        else if (!strcmp(command, "KEYS")) {
            Value *keys = make(ARRAY);
            for (size_t j = 0; j < v->count; j++) push(keys, string_value(v->entries[j].key));
            add_output(&out, format("%s %s", place, compact(keys)));
        } else {
            Matches leaves = {0};
            preorder(match, &leaves);
            for (size_t j = 0; j < leaves.count; j++) if (!children(leaves.items[j]).count) add_output(&out, format("%s = %s", location(leaves.items[j]), compact(leaves.items[j].value)));
        }
    }
    return out.length ? finish(&out) : "no match\n";
}

static void size(Value *v, size_t *count, size_t *depth, size_t level) {
    (*count)++;
    if (level > *depth) *depth = level;
    if (v->kind == ARRAY || v->kind == OBJECT) for (size_t i = 0; i < v->count; i++) size(v->kind == ARRAY ? v->items[i] : v->entries[i].value, count, depth, level + 1);
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') character(&b, (char)c);
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}

static void load(void) {
    Buffer text = {0};
    char *line;
    bool first = true;
    while ((line = read_line()) && strcmp(line, "%%")) {
        if (!first) character(&text, '\n');
        append(&text, line);
        first = false;
    }
    char *source = finish(&text);
    if (setjmp(failure)) {
        size_t line_number = 1, column = 1;
        for (size_t i = 0; i < error_position; i++) if (source[i] == '\n') {
            line_number++;
            column = 1;
        } else column++;
        printf("PARSE ERROR line %zu col %zu: %s\n", line_number, column, error_reason);
        return;
    }
    Value *value = json(source);
    APPEND(history, history_count, clone(document));
    document = value;
    size_t count = 0, depth = 0;
    size(value, &count, &depth, 1);
    printf("LOADED nodes=%zu depth=%zu\n", count, depth);
}

int main(void) {
    load();
    char *line;
    while ((line = read_line()) && strcmp(line, "END")) {
        if (!strcmp(line, "LOAD")) load();
        else if (setjmp(failure)) {
            if (parse_error) printf("PARSE ERROR col %zu: %s\n", error_position + 1, error_reason);
            else puts(error_reason);
        } else fputs(execute(line), stdout);
    }
    return 0;
}
