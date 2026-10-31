#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>

typedef struct { uint64_t id; char text[81]; } Line;
typedef struct { int refs, count, capacity; Line *items; } Buffer;
typedef struct { int refs, count, capacity; char (*items)[81]; } Texts;
typedef struct Record Record;
struct Record {
    int refs, count, current;
    char command[81];
    Buffer *buffer;
    Record *next;
};
typedef struct { char text[81]; bool amp[80]; int length; } Replacement;
typedef struct { char name[9]; Texts *text; } File;
typedef struct {
    Buffer *buffer;
    int current, display, file_count;
    uint64_t marks[26], next_id;
    Texts *cut;
    bool has_pattern, has_replacement;
    char pattern[81];
    Replacement replacement;
    Record *undo, *redo;
    File *files;
} Editor;
typedef struct { char *data; size_t length, capacity; } Output;
typedef struct {
    Editor editor;
    Output output;
    jmp_buf jump;
    const char *error;
} Execution;

static void *allocate(size_t size) {
    void *p = malloc(size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t size) {
    void *result = realloc(p, size ? size : 1);
    if (!result) exit(EXIT_FAILURE);
    return result;
}

static Buffer *buffer_new(void) {
    Buffer *b = allocate(sizeof *b);
    *b = (Buffer){.refs = 1};
    return b;
}

static Buffer *buffer_retain(Buffer *b) { ++b->refs; return b; }
static void buffer_release(Buffer *b) {
    if (--b->refs == 0) { free(b->items); free(b); }
}

static void buffer_reserve(Buffer *b, int count) {
    if (count > b->capacity) {
        b->capacity = count > 2 * b->capacity ? count : 2 * b->capacity;
        b->items = resize(b->items, (size_t)b->capacity * sizeof *b->items);
    }
}

static Buffer *buffer_copy(const Buffer *source) {
    Buffer *b = buffer_new();
    buffer_reserve(b, source->count);
    b->count = source->count;
    if (b->count) memcpy(b->items, source->items, (size_t)b->count * sizeof *b->items);
    return b;
}

static Texts *texts_new(int count) {
    Texts *t = allocate(sizeof *t);
    *t = (Texts){.refs = 1, .count = count, .capacity = count};
    t->items = allocate((size_t)count * sizeof *t->items);
    return t;
}
static Texts *texts_retain(Texts *t) { ++t->refs; return t; }
static void texts_release(Texts *t) {
    if (--t->refs == 0) { free(t->items); free(t); }
}

static Texts *contents(const Buffer *b, int first, int last) {
    Texts *t = texts_new(last - first + 1);
    for (int i = 0; i < t->count; ++i) strcpy(t->items[i], b->items[first - 1 + i].text);
    return t;
}

static Record *record_retain(Record *r) { if (r) ++r->refs; return r; }
static void record_release(Record *r) {
    while (r && --r->refs == 0) {
        Record *next = r->next;
        buffer_release(r->buffer);
        free(r);
        r = next;
    }
}
static Record *record_new(const char *command, Buffer *b, int current, Record *next) {
    Record *r = allocate(sizeof *r);
    *r = (Record){.refs = 1, .count = next ? next->count + 1 : 1,
                  .current = current, .buffer = buffer_retain(b), .next = record_retain(next)};
    strcpy(r->command, command);
    return r;
}

static Editor editor_copy(const Editor *source) {
    Editor e = *source;
    e.buffer = buffer_copy(source->buffer);
    e.cut = texts_retain(source->cut);
    e.undo = record_retain(source->undo);
    e.redo = record_retain(source->redo);
    e.files = allocate((size_t)e.file_count * sizeof *e.files);
    for (int i = 0; i < e.file_count; ++i) {
        e.files[i] = source->files[i];
        texts_retain(e.files[i].text);
    }
    return e;
}

static void editor_destroy(Editor *e) {
    buffer_release(e->buffer);
    texts_release(e->cut);
    record_release(e->undo);
    record_release(e->redo);
    for (int i = 0; i < e->file_count; ++i) texts_release(e->files[i].text);
    free(e->files);
}

static _Noreturn void fail(Execution *x, const char *reason) {
    x->error = reason;
    longjmp(x->jump, 1);
}

static void emit(Execution *x, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    Output *out = &x->output;
    size_t needed = out->length + (size_t)length + 1;
    if (needed > out->capacity) {
        out->capacity = needed > 2 * out->capacity ? needed : 2 * out->capacity;
        out->data = resize(out->data, out->capacity);
    }
    vsnprintf(out->data + out->length, out->capacity - out->length, format, args);
    va_end(args);
    out->length += (size_t)length;
}

static bool digit(char c) { return c >= '0' && c <= '9'; }
static bool lower(char c) { return c >= 'a' && c <= 'z'; }
static bool upper(char c) { return c >= 'A' && c <= 'Z'; }
static char lowercase(char c) { return upper(c) ? (char)(c + 'a' - 'A') : c; }
static bool one_of(char c, const char *set) { return c && strchr(set, c); }
static bool digits(const char *s) {
    if (!*s) return false;
    for (; *s; ++s) if (!digit(*s)) return false;
    return true;
}

static bool delimited(const char *s, int *position, char delimiter, Replacement *value) {
    *value = (Replacement){0};
    while (s[*position]) {
        char c = s[(*position)++];
        if (c == delimiter) return true;
        bool escaped = c == '\\';
        if (escaped) {
            if (!s[*position]) return false;
            c = s[(*position)++];
        }
        value->amp[value->length] = c == '&' && !escaped;
        value->text[value->length++] = c;
    }
    return false;
}

typedef struct { char kind, name; int number; char text[81]; } Token;
typedef struct { Token items[80]; int count, end; } Tokens;
typedef struct { Token items[80]; int count; } Address;
typedef struct { Address left, right; int count; char separator; } Addresses;

static bool lex_addresses(const char *s, Tokens *tokens) {
    *tokens = (Tokens){0};
    int p = 0;
    while (s[p]) {
        Token token = {0};
        char c = s[p];
        if (digit(c)) {
            token.kind = 'N';
            while (digit(s[p])) token.number = token.number * 10 + s[p++] - '0';
        } else if (c == '+' || c == '-') {
            token.kind = 'O';
            ++p;
            if (!digit(s[p])) token.number = 1;
            else while (digit(s[p])) token.number = token.number * 10 + s[p++] - '0';
            if (c == '-') token.number = -token.number;
        } else if (one_of(c, ".$,;%")) {
            token.kind = c;
            ++p;
        } else if (c == '\'') {
            token.kind = c;
            ++p;
            token.name = s[p];
            if (s[p]) ++p;
        } else if (c == '/' || c == '?') {
            token.kind = c;
            Replacement value;
            ++p;
            if (!delimited(s, &p, c, &value)) return false;
            strcpy(token.text, value.text);
        } else break;
        tokens->items[tokens->count++] = token;
    }
    tokens->end = p;
    return true;
}

static bool with_text(const char *line) {
    Tokens tokens;
    if (!lex_addresses(line, &tokens)) return false;
    const char *part = line + tokens.end;
    if (one_of(part[0], "aic") && part[1] == '\0') return true;
    if (one_of(part[0], "gv") && part[1] && !one_of(part[1], " \\")) {
        int p = 2;
        Replacement value;
        if (delimited(part, &p, part[1], &value))
            return one_of(part[p], "aic") && part[p + 1] == '\0';
    }
    return false;
}

static bool valid_address(const Address *a) {
    for (int i = 0; i < a->count; ++i) {
        char kind = a->items[i].kind;
        if (kind != 'O' && (i != 0 || !one_of(kind, "N.$'/?"))) return false;
    }
    return true;
}

static Address address_slice(const Tokens *t, int first, int end) {
    Address result = {.count = end - first};
    if (result.count) memcpy(result.items, t->items + first, (size_t)result.count * sizeof *result.items);
    return result;
}

static Addresses parse_addresses(Execution *x, const Tokens *tokens) {
    Addresses a = {0};
    if (!tokens->count) return a;
    if (tokens->count == 1 && tokens->items[0].kind == '%') {
        a.count = 2;
        a.separator = ',';
        a.left.count = a.right.count = 1;
        a.left.items[0] = (Token){.kind = 'N', .number = 1};
        a.right.items[0] = (Token){.kind = '$'};
        return a;
    }
    int separator = -1;
    for (int i = 0; i < tokens->count; ++i) {
        if (one_of(tokens->items[i].kind, ",;")) {
            if (separator >= 0) fail(x, "bad address");
            separator = i;
        }
    }
    a.count = separator < 0 ? 1 : 2;
    a.left = address_slice(tokens, 0, separator < 0 ? tokens->count : separator);
    if (separator >= 0) {
        a.separator = tokens->items[separator].kind;
        a.right = address_slice(tokens, separator + 1, tokens->count);
    }
    if (!valid_address(&a.left) || !valid_address(&a.right)) fail(x, "bad address");
    return a;
}

typedef enum {
    C_EMPTY, C_APPEND, C_INSERT, C_CHANGE, C_PRINT, C_NUMBER, C_LIST, C_EQUALS, C_COUNT,
    C_YANK, C_MARKS, C_HISTORY, C_FILES, C_DELETE, C_PUT, C_JOIN, C_JOIN_SPACE,
    C_PAGE, C_INDENT, C_UNINDENT, C_UNDO, C_REDO, C_CASE, C_READ, C_WRITE,
    C_WRITE_APPEND, C_EDIT, C_WRITE_PRINT, C_MARK, C_MOVE, C_COPY, C_SUBSTITUTE,
    C_GLOBAL, C_INVERSE, C_SORT
} Kind;
typedef struct {
    Kind kind;
    int number;
    char suffix, option, filename[9], search[81];
    Address destination;
    Replacement replacement;
    bool previous, all, reverse, unique, insensitive, numeric;
} Command;
typedef struct { Command main, sub; } Parsed;

static char print_suffix(Execution *x, const char *s) {
    if (!*s) return 0;
    if (!one_of(s[0], "pnl") || s[1]) fail(x, "invalid suffix");
    return *s;
}
static int positive(Execution *x, const char *s) {
    if (!*s) return 0;
    if (!digits(s) || atoi(s) == 0) fail(x, "invalid suffix");
    return atoi(s);
}
static void filename(Execution *x, const char *s, char name[9]) {
    size_t length = strlen(s);
    if (length < 2 || length > 9 || s[0] != ' ') fail(x, "invalid file name");
    for (size_t i = 1; i < length; ++i)
        if (!lower(s[i]) && !digit(s[i])) fail(x, "invalid file name");
    strcpy(name, s + 1);
}
static bool sort_form(const char *s) { return !strcmp(s, "sort") || !strncmp(s, "sort ", 5); }

static Command parse_command(Execution *x, const char *part, Command *sub) {
    Command c = {0};
    const char *arg = *part ? part + 1 : part;
    if (sort_form(part)) {
        c.kind = C_SORT;
        if (part[4] && !part[5]) fail(x, "invalid suffix");
        for (const char *p = part + (part[4] ? 5 : 4); *p; ++p) {
            bool *flag = *p == 'r' ? &c.reverse : *p == 'u' ? &c.unique :
                         *p == 'i' ? &c.insensitive : *p == 'n' ? &c.numeric : NULL;
            if (!flag || *flag) fail(x, "invalid suffix");
            *flag = true;
        }
        if (c.insensitive && c.numeric) fail(x, "invalid suffix");
        return c;
    }
    const char *simple = "aicpnl=#yKhf";
    const Kind simple_kinds[] = {C_APPEND, C_INSERT, C_CHANGE, C_PRINT, C_NUMBER, C_LIST,
                                C_EQUALS, C_COUNT, C_YANK, C_MARKS, C_HISTORY, C_FILES};
    const char *found = *part ? strchr(simple, *part) : NULL;
    if (!*part || found) {
        c.kind = found ? simple_kinds[found - simple] : C_EMPTY;
        if (*arg) fail(x, "invalid suffix");
        return c;
    }
    switch (*part) {
    case 'd': case 'x': case 'j': case 'J':
        c.kind = *part == 'd' ? C_DELETE : *part == 'x' ? C_PUT : *part == 'j' ? C_JOIN : C_JOIN_SPACE;
        c.suffix = print_suffix(x, arg);
        break;
    case 'z': case '>': case '<': case 'u':
        c.kind = *part == 'z' ? C_PAGE : *part == '>' ? C_INDENT : *part == '<' ? C_UNINDENT : C_UNDO;
        c.number = positive(x, arg);
        break;
    case '~':
        c.kind = C_CASE;
        if (*arg && (!one_of(*arg, "ul") || arg[1])) fail(x, "invalid suffix");
        c.option = *arg;
        break;
    case 'r':
        if (!*arg || digits(arg)) { c.kind = C_REDO; c.number = positive(x, arg); }
        else { c.kind = C_READ; filename(x, arg, c.filename); }
        break;
    case 'w': case 'W': case 'e':
        c.kind = *part == 'w' ? (*arg ? C_WRITE : C_WRITE_PRINT) : *part == 'W' ? C_WRITE_APPEND : C_EDIT;
        if (c.kind != C_WRITE_PRINT) filename(x, arg, c.filename);
        break;
    case 'k':
        c.kind = C_MARK;
        if (!lower(arg[0]) || arg[1]) fail(x, "invalid mark");
        c.option = *arg;
        break;
    case 'm': case 't': {
        c.kind = *part == 'm' ? C_MOVE : C_COPY;
        Tokens destination;
        if (!lex_addresses(arg, &destination)) fail(x, "missing delimiter");
        c.destination = address_slice(&destination, 0, destination.count);
        if (!c.destination.count || !valid_address(&c.destination)) fail(x, "invalid destination");
        c.suffix = print_suffix(x, arg + destination.end);
        break;
    }
    case 's': {
        c.kind = C_SUBSTITUTE;
        c.number = 1;
        bool repeated = true;
        for (const char *p = arg; *p; ++p)
            if (!one_of(*p, "gpnl") && !digit(*p)) repeated = false;
        int p = 0;
        if (repeated) c.previous = true;
        else {
            char delimiter = arg[p++];
            if (one_of(delimiter, " \\")) fail(x, "missing delimiter");
            Replacement search;
            if (!delimited(arg, &p, delimiter, &search)) fail(x, "missing delimiter");
            strcpy(c.search, search.text);
            int start = p;
            if (!delimited(arg, &p, delimiter, &c.replacement)) fail(x, "missing delimiter");
            c.previous = p - start == 2 && arg[start] == '%';
        }
        bool counted = false;
        while (arg[p]) {
            char flag = arg[p++];
            if (flag == 'g') {
                if (c.all) fail(x, "invalid suffix");
                c.all = true;
            } else if (one_of(flag, "pnl")) {
                if (c.suffix) fail(x, "invalid suffix");
                c.suffix = flag;
            } else if (digit(flag)) {
                if (counted) fail(x, "invalid suffix");
                counted = true;
                c.number = flag - '0';
                while (digit(arg[p])) c.number = c.number * 10 + arg[p++] - '0';
                if (!c.number) fail(x, "invalid suffix");
            } else fail(x, "invalid suffix");
        }
        break;
    }
    case 'g': case 'v': {
        c.kind = *part == 'g' ? C_GLOBAL : C_INVERSE;
        if (!*arg || one_of(*arg, " \\")) fail(x, "missing delimiter");
        int p = 1;
        Replacement pattern;
        if (!delimited(arg, &p, *arg, &pattern)) fail(x, "missing delimiter");
        strcpy(c.search, pattern.text);
        const char *body = arg[p] ? arg + p : "p";
        if (!one_of(*body, "pnldmtjJs><~aicx") || sort_form(body)) fail(x, "invalid global command");
        *sub = parse_command(x, body, NULL);
        break;
    }
    default: fail(x, "unknown command");
    }
    return c;
}

static const char *pattern(Execution *x, const char *search) {
    Editor *e = &x->editor;
    if (*search) { strcpy(e->pattern, search); e->has_pattern = true; }
    else if (!e->has_pattern) fail(x, "no previous pattern");
    return e->pattern;
}

static int locate(const Buffer *b, uint64_t id) {
    if (id) for (int i = 0; i < b->count; ++i) if (b->items[i].id == id) return i + 1;
    return 0;
}

static int address_value(Execution *x, const Address *address) {
    Editor *e = &x->editor;
    int value = e->current;
    for (int i = 0; i < address->count; ++i) {
        const Token *t = &address->items[i];
        switch (t->kind) {
        case 'O': value += t->number; break;
        case 'N': value = t->number; break;
        case '.': value = e->current; break;
        case '$': value = e->buffer->count; break;
        case '\'':
            if (!lower(t->name)) fail(x, "invalid mark");
            value = locate(e->buffer, e->marks[t->name - 'a']);
            if (!value) fail(x, "mark not set");
            break;
        case '/': case '?': {
            const char *p = pattern(x, t->text);
            int count = e->buffer->count;
            value = 0;
            for (int step = 1; step <= count; ++step) {
                int index = t->kind == '/' ? (e->current + step - 1) % count :
                            ((e->current ? e->current : count + 1) - step - 1 + count) % count;
                if (strstr(e->buffer->items[index].text, p)) { value = index + 1; break; }
            }
            if (!value) fail(x, "no match");
            break;
        }
        }
    }
    return value;
}

static int address_kind(Kind kind) {
    switch (kind) {
    case C_UNDO: case C_REDO: case C_HISTORY: case C_MARKS: case C_FILES: case C_EDIT: return 0;
    case C_APPEND: case C_INSERT: case C_PUT: case C_EQUALS: case C_READ: case C_MARK: case C_PAGE: return 1;
    default: return 2;
    }
}

typedef struct { int first, last; } Range;
static Range checked_range(Execution *x, const Command *c, int count, Range values) {
    Editor *e = &x->editor;
    int kind = address_kind(c->kind), size = e->buffer->count;
    if (kind == 0) return (Range){0};
    if (kind == 1) {
        int value = values.first;
        if (!count) value = c->kind == C_EQUALS || c->kind == C_READ ? size :
                            c->kind == C_PAGE ? e->current + 1 : e->current;
        int minimum = c->kind == C_MARK || c->kind == C_PAGE ? 1 : 0;
        if (value < minimum || value > size) fail(x, "address out of range");
        return (Range){value, value};
    }
    if (!count) {
        bool whole = c->kind == C_WRITE_PRINT || c->kind == C_WRITE ||
                     c->kind == C_WRITE_APPEND || c->kind == C_COUNT;
        if (whole) return (Range){1, size};
        if (c->kind == C_GLOBAL || c->kind == C_INVERSE || c->kind == C_SORT) values = (Range){1, size};
        else values = (Range){e->current, e->current + (c->kind == C_JOIN || c->kind == C_JOIN_SPACE)};
    } else if (count == 1) values.last = values.first;
    if (values.first < 1 || values.first > size || values.last < 1 || values.last > size)
        fail(x, "address out of range");
    if (values.first > values.last || (values.first == values.last && (c->kind == C_JOIN || c->kind == C_JOIN_SPACE)))
        fail(x, "invalid range");
    return values;
}

static void print_line(Execution *x, int number, char form) {
    const char *s = x->editor.buffer->items[number - 1].text;
    if (form == 'n') emit(x, "%3d %s\n", number, s);
    else if (form == 'l') {
        char escaped[162];
        int length = 0;
        for (; *s; ++s) {
            if (*s == '\\') escaped[length++] = '\\';
            escaped[length++] = *s;
        }
        escaped[length++] = '$';
        escaped[length] = '\0';
        int offset = 0;
        while (length - offset > 40) { emit(x, "%.39s\\\n", escaped + offset); offset += 39; }
        emit(x, "%s\n", escaped + offset);
    } else emit(x, "%s\n", s);
}

static void erase(Buffer *b, int first, int count) {
    if (!count) return;
    memmove(b->items + first, b->items + first + count,
            (size_t)(b->count - first - count) * sizeof *b->items);
    b->count -= count;
}

static void insert_lines(Buffer *b, int after, const Line *lines, int count) {
    if (!count) return;
    buffer_reserve(b, b->count + count);
    memmove(b->items + after + count, b->items + after, (size_t)(b->count - after) * sizeof *b->items);
    memcpy(b->items + after, lines, (size_t)count * sizeof *lines);
    b->count += count;
}

static void insert_text(Editor *e, int after, const Texts *text) {
    Buffer *b = e->buffer;
    int count = text->count;
    if (!count) return;
    buffer_reserve(b, b->count + count);
    memmove(b->items + after + count, b->items + after, (size_t)(b->count - after) * sizeof *b->items);
    for (int i = 0; i < count; ++i) {
        b->items[after + i].id = e->next_id++;
        strcpy(b->items[after + i].text, text->items[i]);
    }
    b->count += count;
}

static void set_cut(Editor *e, int first, int last) {
    Texts *copy = contents(e->buffer, first, last);
    texts_release(e->cut);
    e->cut = copy;
}

static void line_append(Execution *x, char result[81], int *length, const char *s, int count) {
    if (*length + count > 80) fail(x, "line too long");
    memcpy(result + *length, s, (size_t)count);
    *length += count;
    result[*length] = '\0';
}

static bool substitute(Execution *x, const Command *c, Range range, bool in_global) {
    Editor *e = &x->editor;
    const char *p = pattern(x, c->search);
    if (c->previous && !e->has_replacement) fail(x, "no previous substitution");
    if (!c->previous) e->replacement = c->replacement;
    e->has_replacement = true;
    Replacement *replacement = &e->replacement;
    int pattern_length = (int)strlen(p), last = 0;
    for (int i = range.first; i <= range.last; ++i) {
        const char *cursor = e->buffer->items[i - 1].text;
        char result[81] = "";
        int length = 0, occurrence = 0;
        bool changed = false;
        const char *found;
        while ((found = strstr(cursor, p))) {
            line_append(x, result, &length, cursor, (int)(found - cursor));
            ++occurrence;
            if (occurrence == c->number || (c->all && occurrence > c->number)) {
                changed = true;
                for (int j = 0; j < replacement->length; ++j) {
                    if (replacement->amp[j]) line_append(x, result, &length, p, pattern_length);
                    else line_append(x, result, &length, replacement->text + j, 1);
                }
            } else line_append(x, result, &length, p, pattern_length);
            cursor = found + pattern_length;
        }
        line_append(x, result, &length, cursor, (int)strlen(cursor));
        if (changed) {
            if (!length || result[length - 1] == ' ') fail(x, "bad line");
            strcpy(e->buffer->items[i - 1].text, result);
            last = i;
        }
    }
    if (!last && !in_global) fail(x, "no match");
    if (last) { e->current = last; if (c->suffix) print_line(x, last, c->suffix); }
    return last != 0;
}

static int64_t leading_integer(const char *s) {
    bool negative = *s == '-';
    if (negative) ++s;
    int64_t value = 0;
    while (digit(*s)) value = value * 10 + *s++ - '0';
    return negative ? -value : value;
}

static int compare_lines(const Line *a, const Line *b, const Command *c) {
    if (c->numeric) {
        int64_t x = leading_integer(a->text), y = leading_integer(b->text);
        return (x > y) - (x < y);
    }
    const char *x = a->text, *y = b->text;
    while (*x || *y) {
        char left = c->insensitive ? lowercase(*x) : *x;
        char right = c->insensitive ? lowercase(*y) : *y;
        if (left != right) return left < right ? -1 : 1;
        ++x; ++y;
    }
    return 0;
}

static void sort_lines(Editor *e, const Command *c, Range range) {
    Buffer *b = e->buffer;
    for (int i = range.first; i < range.last; ++i) {
        Line value = b->items[i];
        int j = i;
        while (j >= range.first) {
            int order = compare_lines(&b->items[j - 1], &value, c);
            if ((c->reverse ? -order : order) <= 0) break;
            b->items[j] = b->items[j - 1];
            --j;
        }
        b->items[j] = value;
    }
    int end = range.first - 1;
    for (int i = range.first - 1; i < range.last; ++i)
        if (!c->unique || end == range.first - 1 || compare_lines(&b->items[end - 1], &b->items[i], c))
            b->items[end++] = b->items[i];
    erase(b, end, range.last - end);
    e->current = end;
}

static int find_file(const Editor *e, const char *name) {
    for (int i = 0; i < e->file_count; ++i) if (!strcmp(e->files[i].name, name)) return i;
    return -1;
}

static int store_file(Editor *e, const char *name, Texts *text) {
    int index = find_file(e, name);
    if (index >= 0) texts_release(e->files[index].text);
    else {
        index = 0;
        while (index < e->file_count && strcmp(e->files[index].name, name) < 0) ++index;
        e->files = resize(e->files, (size_t)(e->file_count + 1) * sizeof *e->files);
        memmove(e->files + index + 1, e->files + index, (size_t)(e->file_count - index) * sizeof *e->files);
        ++e->file_count;
        strcpy(e->files[index].name, name);
    }
    e->files[index].text = text;
    return index;
}

static void file_command(Execution *x, const Command *c, Range range) {
    Editor *e = &x->editor;
    int index = find_file(e, c->filename);
    if (c->kind == C_WRITE || c->kind == C_WRITE_APPEND) {
        int old_count = c->kind == C_WRITE_APPEND && index >= 0 ? e->files[index].text->count : 0;
        int added = range.last - range.first + 1;
        Texts *t = texts_new(old_count + added);
        if (old_count) memcpy(t->items, e->files[index].text->items, (size_t)old_count * sizeof *t->items);
        for (int i = 0; i < added; ++i) strcpy(t->items[old_count + i], e->buffer->items[range.first - 1 + i].text);
        index = store_file(e, c->filename, t);
    } else {
        if (index < 0) fail(x, "no such file");
        Texts *t = e->files[index].text;
        int after = c->kind == C_EDIT ? 0 : range.first;
        if (c->kind == C_EDIT) e->buffer->count = 0;
        insert_text(e, after, t);
        e->current = after + t->count;
    }
    Texts *t = e->files[index].text;
    int bytes = 0;
    for (int i = 0; i < t->count; ++i) bytes += (int)strlen(t->items[i]) + 1;
    emit(x, "file %s lines=%d bytes=%d\n", c->filename, t->count, bytes);
}

static void transfer_history(Execution *x, bool redo, int count) {
    Editor *e = &x->editor;
    Record **from = redo ? &e->redo : &e->undo, **to = redo ? &e->undo : &e->redo;
    if (!*from || (*from)->count < count) fail(x, redo ? "nothing to redo" : "nothing to undo");
    for (int i = 0; i < count; ++i) {
        Record *record = *from;
        Record *added = record_new(record->command, e->buffer, e->current, *to);
        record_release(*to);
        *to = added;
        buffer_release(e->buffer);
        e->buffer = buffer_retain(record->buffer);
        e->current = record->current;
        *from = record_retain(record->next);
        record_release(record);
    }
}

static bool execute_simple(Execution *x, const Command *c, Range range, const Texts *text, bool in_global) {
    Editor *e = &x->editor;
    Buffer *b = e->buffer;
    int a = range.first, last = range.last, count = last - a + 1;
    switch (c->kind) {
    case C_EMPTY: print_line(x, last, 'p'); e->current = last; break;
    case C_PRINT: case C_NUMBER: case C_LIST:
        for (int i = a; i <= last; ++i) print_line(x, i, c->kind == C_PRINT ? 'p' : c->kind == C_NUMBER ? 'n' : 'l');
        e->current = last;
        break;
    case C_PAGE:
        if (c->number) e->display = c->number;
        last = a + e->display - 1 < b->count ? a + e->display - 1 : b->count;
        for (int i = a; i <= last; ++i) print_line(x, i, 'p');
        e->current = last;
        break;
    case C_EQUALS: emit(x, "%d\n", a); break;
    case C_COUNT: case C_WRITE_PRINT: {
        int words = 0, chars = 0;
        for (int i = a; i <= last; ++i) {
            const char *s = b->items[i - 1].text;
            chars += (int)strlen(s);
            for (int j = 0; s[j]; ++j) if (s[j] != ' ' && (!j || s[j - 1] == ' ')) ++words;
            if (c->kind == C_WRITE_PRINT) print_line(x, i, 'p');
        }
        if (c->kind == C_COUNT) emit(x, "count lines=%d words=%d chars=%d\n", count, words, chars);
        else emit(x, "lines=%d bytes=%d\n", count, chars + count);
        break;
    }
    case C_APPEND: case C_INSERT: {
        int after = c->kind == C_APPEND ? a : (a > 0 ? a - 1 : 0);
        insert_text(e, after, text);
        e->current = after + text->count;
        break;
    }
    case C_CHANGE: case C_DELETE:
        set_cut(e, a, last);
        erase(b, a - 1, count);
        if (c->kind == C_CHANGE) insert_text(e, a - 1, text);
        e->current = c->kind == C_CHANGE && text->count ? a + text->count - 1 : (a < b->count ? a : b->count);
        break;
    case C_YANK: set_cut(e, a, last); break;
    case C_PUT:
        if (!e->cut->count) fail(x, "nothing to put");
        insert_text(e, a, e->cut);
        e->current = a + e->cut->count;
        break;
    case C_MOVE: case C_COPY: {
        int destination = address_value(x, &c->destination);
        if (destination < 0 || destination > b->count) fail(x, "address out of range");
        if (c->kind == C_MOVE && a <= destination && destination < last) fail(x, "invalid destination");
        Line saved[200];
        memcpy(saved, b->items + a - 1, (size_t)count * sizeof *saved);
        if (c->kind == C_MOVE) {
            erase(b, a - 1, count);
            if (destination >= last) destination -= count;
        } else for (int i = 0; i < count; ++i) saved[i].id = e->next_id++;
        insert_lines(b, destination, saved, count);
        e->current = destination + count;
        break;
    }
    case C_JOIN: case C_JOIN_SPACE: {
        char joined[81] = "";
        int length = 0;
        for (int i = a; i <= last; ++i) {
            const char *s = b->items[i - 1].text;
            if (c->kind == C_JOIN_SPACE && i > a) {
                while (*s == ' ') ++s;
                line_append(x, joined, &length, " ", 1);
            }
            line_append(x, joined, &length, s, (int)strlen(s));
        }
        strcpy(b->items[a - 1].text, joined);
        erase(b, a, count - 1);
        e->current = a;
        break;
    }
    case C_INDENT: case C_UNINDENT: case C_CASE:
        for (int i = a; i <= last; ++i) {
            char *s = b->items[i - 1].text;
            int length = (int)strlen(s), width = c->number ? c->number : 4;
            if (c->kind == C_INDENT) {
                if (length + width > 80) fail(x, "line too long");
                memmove(s + width, s, (size_t)length + 1);
                memset(s, ' ', (size_t)width);
            } else if (c->kind == C_UNINDENT) {
                int removed = 0;
                while (removed < width && s[removed] == ' ') ++removed;
                memmove(s, s + removed, (size_t)(length - removed) + 1);
            } else for (int j = 0; j < length; ++j) {
                if (lower(s[j]) && c->option != 'l') s[j] = (char)(s[j] - 'a' + 'A');
                else if (upper(s[j]) && c->option != 'u') s[j] = lowercase(s[j]);
            }
        }
        e->current = last;
        break;
    case C_SORT: sort_lines(e, c, range); break;
    case C_SUBSTITUTE: return substitute(x, c, range, in_global);
    case C_MARK: e->marks[c->option - 'a'] = b->items[a - 1].id; break;
    case C_MARKS: {
        emit(x, "marks");
        bool any = false;
        for (int i = 0; i < 26; ++i) {
            int number = locate(b, e->marks[i]);
            if (number) { emit(x, " %c=%d", 'a' + i, number); any = true; }
        }
        emit(x, "%s\n", any ? "" : " none");
        break;
    }
    case C_UNDO: case C_REDO: transfer_history(x, c->kind == C_REDO, c->number ? c->number : 1); break;
    case C_HISTORY:
        emit(x, "history undo=%d redo=%d\n", e->undo ? e->undo->count : 0, e->redo ? e->redo->count : 0);
        for (int side = 0; side < 2; ++side) {
            int index = 0;
            for (Record *r = side ? e->redo : e->undo; r; r = r->next)
                emit(x, "%s %d: %s\n", side ? "redo" : "undo", ++index, r->command);
        }
        break;
    case C_READ: case C_WRITE: case C_WRITE_APPEND: case C_EDIT: file_command(x, c, range); break;
    case C_FILES:
        emit(x, "files");
        for (int i = 0; i < e->file_count; ++i) emit(x, " %s=%d", e->files[i].name, e->files[i].text->count);
        emit(x, "%s\n", e->file_count ? "" : " none");
        break;
    case C_GLOBAL: case C_INVERSE: break;
    }
    if (c->suffix && e->current >= 1) print_line(x, e->current, c->suffix);
    return false;
}

static bool modifying(Kind kind) {
    switch (kind) {
    case C_APPEND: case C_INSERT: case C_CHANGE: case C_DELETE: case C_PUT:
    case C_JOIN: case C_JOIN_SPACE: case C_MOVE: case C_COPY: case C_SUBSTITUTE:
    case C_INDENT: case C_UNINDENT: case C_CASE: case C_SORT: case C_READ: case C_EDIT: return true;
    default: return false;
    }
}

static bool process(Execution *x, const char *line, const Texts *text) {
    Tokens tokens;
    if (!lex_addresses(line, &tokens)) fail(x, "missing delimiter");
    Addresses addresses = parse_addresses(x, &tokens);
    Parsed parsed = {0};
    parsed.main = parse_command(x, line + tokens.end, &parsed.sub);
    Command *c = &parsed.main;
    int kind = address_kind(c->kind);
    if (!kind && addresses.count) fail(x, "unexpected address");
    if (kind == 1 && addresses.count == 2) fail(x, "too many addresses");
    Editor *e = &x->editor;
    Range values = {0};
    if (addresses.count) {
        values.first = addresses.left.count ? address_value(x, &addresses.left) :
                       addresses.separator == ';' ? e->current : 1;
        if (addresses.count == 2) {
            if (addresses.separator == ';') {
                if (values.first < 0 || values.first > e->buffer->count) fail(x, "address out of range");
                e->current = values.first;
            }
            values.last = addresses.right.count ? address_value(x, &addresses.right) : e->buffer->count;
        }
    }
    Range range = checked_range(x, c, addresses.count, values);
    if (c->kind != C_GLOBAL && c->kind != C_INVERSE) {
        execute_simple(x, c, range, text, false);
        return modifying(c->kind);
    }
    const char *p = pattern(x, c->search);
    uint64_t selected[200];
    int selected_count = 0;
    for (int i = range.first; i <= range.last; ++i) {
        bool found = strstr(e->buffer->items[i - 1].text, p) != NULL;
        if (found == (c->kind == C_GLOBAL)) selected[selected_count++] = e->buffer->items[i - 1].id;
    }
    if (!selected_count) fail(x, "no match");
    bool substituted = false;
    for (int i = 0; i < selected_count; ++i) {
        int position = locate(e->buffer, selected[i]);
        if (position) {
            e->current = position;
            Range subrange = checked_range(x, &parsed.sub, 0, (Range){0});
            bool changed = execute_simple(x, &parsed.sub, subrange, text, true);
            substituted = substituted || changed;
        }
    }
    if (parsed.sub.kind == C_SUBSTITUTE && !substituted) fail(x, "no match");
    return modifying(parsed.sub.kind);
}

static bool read_line(char line[128]) {
    if (!fgets(line, 128, stdin)) return false;
    line[strcspn(line, "\r\n")] = '\0';
    return true;
}

int main(void) {
    Editor editor = {.buffer = buffer_new(), .cut = texts_new(0), .display = 5, .next_id = 1};
    char line[128];
    while (read_line(line) && strcmp(line, "Q")) {
        Texts *text = texts_new(0);
        if (with_text(line)) {
            char entered[128];
            while (read_line(entered) && strcmp(entered, ".")) {
                if (text->count == text->capacity) {
                    text->capacity = text->capacity ? 2 * text->capacity : 8;
                    text->items = resize(text->items, (size_t)text->capacity * sizeof *text->items);
                }
                strcpy(text->items[text->count++], entered);
            }
        }
        Execution *x = allocate(sizeof *x);
        *x = (Execution){.editor = editor_copy(&editor)};
        if (setjmp(x->jump) == 0) {
            bool changes = process(x, line, text);
            if (x->editor.buffer->count > 200) fail(x, "buffer full");
            if (changes) {
                Record *added = record_new(line, editor.buffer, editor.current, x->editor.undo);
                record_release(x->editor.undo);
                x->editor.undo = added;
                record_release(x->editor.redo);
                x->editor.redo = NULL;
            }
            editor_destroy(&editor);
            editor = x->editor;
            if (x->output.length) fwrite(x->output.data, 1, x->output.length, stdout);
        } else {
            printf("? %s\n", x->error);
            editor_destroy(&x->editor);
        }
        free(x->output.data);
        free(x);
        texts_release(text);
    }
    editor_destroy(&editor);
    return 0;
}
