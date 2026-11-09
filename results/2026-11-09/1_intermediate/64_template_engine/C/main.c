#include <ctype.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef enum { ABSENT, INTEGER, STRING, BOOLEAN, LIST, MAP } Kind;
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
    char *text;
    int line;
} SourceLine;
typedef struct {
    char *name;
    SourceLine *lines;
    size_t count;
} Source;
typedef struct {
    char *key, *prefix;
    int index;
    bool numeric;
} Part;
typedef struct {
    char *name;
    Value **args;
    size_t count;
} Filter;
typedef struct {
    char *name;
    Filter *filters;
    size_t count;
} Expression;
typedef struct Node Node;
struct Node {
    char kind;
    int line;
    char *text, *indent;
    Expression expression;
    Node **children;
    size_t count;
};
typedef struct {
    int index, count;
} Loop;
static Value absent = { .kind = ABSENT }, *root;
static Source *partials, *templates;
static size_t partial_count, template_count;
static bool strict;
static jmp_buf failure;
static char *error_reason;
static int error_line, active_line;
static void *allocate(size_t size) {
    void *p = calloc(1, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t size) {
    p = realloc(p, size ? size : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}

static char *duplicate(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *result = allocate((size_t)n + 1);
    vsnprintf(result, (size_t)n + 1, pattern, copy);
    va_end(copy);
    return result;
}

static void fail(int line, const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)n + 1);
    vsnprintf(error_reason, (size_t)n + 1, pattern, copy);
    va_end(copy);
    error_line = line ? line : active_line;
    longjmp(failure, 1);
}

static void append_n(Buffer *b, const char *s, size_t n) {
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, s, n);
    b->length += n;
    b->data[b->length] = '\0';
}

static void append(Buffer *b, const char *s) {
    append_n(b, s, strlen(s));
}

static void character(Buffer *b, char c) {
    append_n(b, &c, 1);
}

static char *finish(Buffer *b) {
    return b->data ? b->data : duplicate("");
}

static char *trim(const char *s) {
    while (*s == ' ') s++;
    size_t n = strlen(s);
    while (n && s[n - 1] == ' ') n--;
    return slice(s, n);
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

static bool subscript(const char *s) {
    if (!*s || (*s == '0' && s[1])) return false;
    for (; *s; s++) if (!digit(*s)) return false;
    return true;
}

static bool numeric_text(const char *s, bool canonical) {
    if (*s == '-') {
        s++;
        if (canonical && *s == '0') return false;
    }
    size_t n = strlen(s);
    if (!n || (!canonical && n > 9) || (canonical && n > 1 && *s == '0')) return false;
    for (; *s; s++) if (!digit(*s)) return false;
    return true;
}

static Value *make(Kind kind) {
    Value *v = allocate(sizeof(*v));
    v->kind = kind;
    return v;
}

static Value *integer(int n) {
    Value *v = make(INTEGER);
    v->number = n;
    return v;
}

static Value *boolean(bool b) {
    Value *v = make(BOOLEAN);
    v->number = b;
    return v;
}

static Value *string(char *s) {
    Value *v = make(STRING);
    v->text = s;
    return v;
}

static void push(Value *list, Value *v) {
    list->items = resize(list->items, (list->count + 1) * sizeof(*list->items));
    list->items[list->count++] = v;
}

static int entry_index(Value *v, const char *key) {
    if (v->kind != MAP) return -1;
    for (size_t i = 0; i < v->count; i++) if (!strcmp(v->entries[i].key, key)) return (int)i;
    return -1;
}

static bool has(Value *v, Part p) {
    return p.numeric ? v->kind == LIST && p.index >= 0 && (size_t)p.index < v->count : entry_index(v, p.key) >= 0;
}

static Value *get(Value *v, Part p) {
    return p.numeric ? v->items[p.index] : v->entries[entry_index(v, p.key)].value;
}

static void put(Value *v, Part p, Value *item) {
    if (p.numeric) {
        if ((size_t)p.index == v->count) push(v, item);
        else v->items[p.index] = item;
    } else {
        int i = entry_index(v, p.key);
        if (i < 0) {
            v->entries = resize(v->entries, (v->count + 1) * sizeof(*v->entries));
            i = (int)v->count++;
            v->entries[i].key = p.key;
        }
        v->entries[i].value = item;
    }
}

static void map_put(Value *v, char *key, Value *item) {
    put(v, (Part){ .key = key }, item);
}

static Part *parse_key(const char *key, size_t *count) {
    Part *parts = NULL;
    size_t pos = 0;
    *count = 0;
    while (true) {
        Part part = {0};
        size_t start = pos;
        if (!*count || key[pos] == '.') {
            if (*count) start = ++pos;
            if (!letter(key[pos]) && key[pos] != '_') fail(0, "bad key '%s'", key);
            while (letter(key[pos]) || digit(key[pos]) || key[pos] == '_') pos++;
            part.key = slice(key + start, pos - start);
        } else if (key[pos] == '[') {
            start = ++pos;
            while (digit(key[pos])) pos++;
            char *number = slice(key + start, pos - start);
            if (!subscript(number) || key[pos] != ']') fail(0, "bad key '%s'", key);
            part.numeric = true;
            part.index = atoi(number);
            pos++;
        } else fail(0, "bad key '%s'", key);
        part.prefix = slice(key, pos);
        parts = resize(parts, (*count + 1) * sizeof(*parts));
        parts[(*count)++] = part;
        if (!key[pos]) return parts;
        if (key[pos] != '.' && key[pos] != '[') fail(0, "bad key '%s'", key);
    }
}

static Value *read_scalar(const char *s, size_t *pos) {
    if (s[*pos] == '"') {
        (*pos)++;
        Buffer out = {0};
        while (s[*pos]) {
            char c = s[(*pos)++];
            if (c == '"') return string(finish(&out));
            if (c == '\\') {
                c = s[(*pos)++];
                if (c == 'n') c = '\n';
                else if (c != '"' && c != '\\') return NULL;
            }
            character(&out, c);
        }
        return NULL;
    }
    size_t start = *pos;
    while (s[*pos] && s[*pos] != ',' && s[*pos] != ']') (*pos)++;
    char *word = slice(s + start, *pos - start);
    if (!strcmp(word, "true") || !strcmp(word, "false")) return boolean(!strcmp(word, "true"));
    return numeric_text(word, true) ? integer(atoi(word)) : NULL;
}

static Value *parse_value(const char *s) {
    if (!strcmp(s, "[]")) return make(LIST);
    if (!strcmp(s, "{}")) return make(MAP);
    size_t pos = 0;
    Value *v;
    if (*s == '[') {
        v = make(LIST);
        pos = 1;
        while (true) {
            Value *item = read_scalar(s, &pos);
            if (!item) fail(0, "bad value '%s'", s);
            push(v, item);
            if (!strncmp(s + pos, ", ", 2)) pos += 2;
            else if (!strcmp(s + pos, "]")) {
                pos++;
                break;
            } else fail(0, "bad value '%s'", s);
        }
    } else v = read_scalar(s, &pos);
    if (!v || s[pos]) fail(0, "bad value '%s'", s);
    return v;
}

static void change_data(char *text, bool remove) {
    char *equal = strstr(text, " = ");
    if (!remove && !equal) fail(0, "bad line");
    char *key = remove ? text + 6 : slice(text, (size_t)(equal - text));
    size_t count;
    Part *parts = parse_key(key, &count);
    Value *item = remove ? NULL : parse_value(equal + 3), *current = root;
    for (size_t i = 0; i < count; i++) {
        Part p = parts[i];
        bool found = current && has(current, p);
        if (remove) {
            if (!found) fail(0, "no value at '%s'", key);
            if (i + 1 == count) {
                size_t index = p.numeric ? (size_t)p.index : (size_t)entry_index(current, p.key);
                if (p.numeric) memmove(current->items + index, current->items + index + 1, (current->count - index - 1) * sizeof(*current->items));
                else memmove(current->entries + index, current->entries + index + 1, (current->count - index - 1) * sizeof(*current->entries));
                current->count--;
                return;
            }
            current = get(current, p);
        } else {
            size_t length = current ? current->count : 0;
            if (p.numeric && (size_t)p.index > length) fail(0, "index gap at '%s'", p.prefix);
            if (i + 1 == count) break;
            Kind needed = parts[i + 1].numeric ? LIST : MAP;
            if (found && get(current, p)->kind != needed) fail(0, "type conflict at '%s'", p.prefix);
            current = found ? get(current, p) : NULL;
        }
    }
    current = root;
    for (size_t i = 0; i < count; i++) {
        if (i + 1 == count) put(current, parts[i], item);
        else {
            if (!has(current, parts[i])) put(current, parts[i], make(parts[i + 1].numeric ? LIST : MAP));
            current = get(current, parts[i]);
        }
    }
}

static char **split_unquoted(const char *text, char separator, size_t *count) {
    char **result = NULL;
    size_t start = 0;
    bool quoted = false;
    *count = 0;
    for (size_t i = 0;; i++) {
        if (text[i] == '\'') quoted = !quoted;
        if (!text[i] || (text[i] == separator && !quoted)) {
            result = resize(result, (*count + 1) * sizeof(*result));
            result[(*count)++] = slice(text + start, i - start);
            start = i + 1;
            if (!text[i]) break;
        }
    }
    return result;
}

static bool valid_name(const char *name) {
    if (!strcmp(name, ".") || !strcmp(name, "@index") || !strcmp(name, "@number") || !strcmp(name, "@first") || !strcmp(name, "@last")) return true;
    size_t start = 0;
    for (size_t i = 0;; i++) if (!name[i] || name[i] == '.') {
        char *part = slice(name + start, i - start);
        if (!identifier(part) && !subscript(part)) return false;
        if (!name[i]) return true;
        start = i + 1;
    }
}

static bool in_words(const char *name, const char *words) {
    if (!*name || strchr(name, ' ')) return false;
    char *needle = format(" %s ", name);
    return strstr(words, needle) != NULL;
}

static bool valid_args(Filter f) {
    size_t n = f.count;
    Value **a = f.args;
    bool integer_arg = n && a[0]->kind == INTEGER, string_arg = n && a[0]->kind == STRING;
    if (in_words(f.name, " default  eq ")) return n == 1;
    if (in_words(f.name, " pad  lpad ")) return (n == 1 || n == 2) && integer_arg && a[0]->number >= 0 && (n == 1 || (a[1]->kind == STRING && strlen(a[1]->text) == 1));
    if (!strcmp(f.name, "truncate")) return n == 1 && integer_arg && a[0]->number >= 0;
    if (!strcmp(f.name, "replace")) return n == 2 && string_arg && *a[0]->text && a[1]->kind == STRING;
    if (in_words(f.name, " join  pluck ")) return n == 1 && string_arg;
    if (!strcmp(f.name, "sort")) return !n || (n == 1 && string_arg);
    if (in_words(f.name, " div  mod ")) return n == 1 && integer_arg && a[0]->number != 0;
    if (in_words(f.name, " add  sub  mul  gt  lt ")) return n == 1 && integer_arg;
    return !n;
}

static Expression parse_expression(const char *text, int line) {
    Expression expression = {0};
    size_t count;
    char **pieces = split_unquoted(text, '|', &count);
    expression.name = trim(pieces[0]);
    if (!valid_name(expression.name)) fail(line, "invalid name '%s'", expression.name);
    for (size_t i = 1; i < count; i++) {
        size_t fields;
        char **parts = split_unquoted(trim(pieces[i]), ':', &fields);
        Filter f = { .name = parts[0] };
        if (!in_words(f.name, " upper  lower  title  trim  length  first  last  reverse  items  comma  sum  min  max  default  eq  pad  lpad  truncate  replace  join  sort  pluck  add  sub  mul  div  mod  gt  lt ")) fail(line, "unknown filter '%s'", f.name);
        for (size_t j = 1; j < fields; j++) {
            char *arg = parts[j];
            size_t n = strlen(arg);
            Value *v = NULL;
            if (n >= 2 && arg[0] == '\'' && arg[n - 1] == '\'' && !memchr(arg + 1, '\'', n - 2)) v = string(slice(arg + 1, n - 2));
            else if (numeric_text(arg, false)) v = integer(atoi(arg));
            if (!v) fail(line, "bad arguments for '%s'", f.name);
            f.args = resize(f.args, (f.count + 1) * sizeof(*f.args));
            f.args[f.count++] = v;
        }
        if (!valid_args(f)) fail(line, "bad arguments for '%s'", f.name);
        expression.filters = resize(expression.filters, (expression.count + 1) * sizeof(*expression.filters));
        expression.filters[expression.count++] = f;
    }
    return expression;
}

static Node *node(char kind, int line, char *text) {
    Node *n = allocate(sizeof(*n));
    n->kind = kind;
    n->line = line;
    n->text = text;
    n->indent = "";
    return n;
}

static void add_node(Node *parent, Node *child) {
    parent->children = resize(parent->children, (parent->count + 1) * sizeof(*parent->children));
    parent->children[parent->count++] = child;
}

static bool spaces_only(const char *s) {
    for (; *s; s++) if (*s != ' ') return false;
    return true;
}

static Node *analyze(Source source, const char *indent) {
    Node *tree = node('T', 0, "");
    Node **open = NULL, **levels = allocate(sizeof(*levels));
    size_t depth = 0, level = 0;
    levels[0] = tree;
    char *opening = "{{", *closing = "}}";
    for (size_t i = 0; i < source.count; i++) {
        SourceLine line = source.lines[i];
        char *text = *line.text ? format("%s%s", indent, line.text) : "";
        size_t pos = 0, tags = 0;
        Node *line_nodes = node('T', line.line, ""), *only = NULL;
        while (true) {
            char *start = strstr(text + pos, opening);
            if (!start) {
                add_node(line_nodes, node('T', line.line, duplicate(text + pos)));
                break;
            }
            add_node(line_nodes, node('T', line.line, slice(text + pos, (size_t)(start - text) - pos)));
            char *begin = start + strlen(opening);
            bool triple = *begin == '{';
            if (triple) begin++;
            char *end_text = format("%s%s", triple ? "}" : "", closing), *end = strstr(begin, end_text);
            if (!end) fail(line.line, "unclosed tag");
            char *content = trim(slice(begin, (size_t)(end - begin)));
            char kind = triple ? 'R' : *content && strchr("#^/!>&=", *content) ? *content : 'V';
            char *arg = kind == 'V' || triple ? content : trim(content + 1);
            if (kind == '&') kind = 'R';
            Node *tag = node(kind, line.line, arg);
            only = tag;
            tags++;
            if (kind == '=') {
                size_t n = strlen(content);
                if (n < 2 || content[n - 1] != '=') fail(line.line, "invalid delimiters");
                char *middle = trim(slice(content + 1, n - 2)), *first_end = strchr(middle, ' ');
                if (!first_end) fail(line.line, "invalid delimiters");
                opening = slice(middle, (size_t)(first_end - middle));
                closing = trim(first_end);
                if (!*opening || !*closing || strchr(closing, ' ') || strchr(opening, '=') || strchr(closing, '=')) fail(line.line, "invalid delimiters");
            } else if (strchr("VR#^", kind)) {
                tag->expression = parse_expression(arg, line.line);
                if (kind == '#' || kind == '^') {
                    open = resize(open, (depth + 1) * sizeof(*open));
                    open[depth++] = tag;
                }
            } else if (kind == '/') {
                if (!valid_name(arg)) fail(line.line, "invalid name '%s'", arg);
                if (!depth) fail(line.line, "unexpected closing '%s'", arg);
                if (strcmp(arg, open[depth - 1]->expression.name)) fail(line.line, "mismatched closing '%s', expected '%s'", arg, open[depth - 1]->expression.name);
                depth--;
            } else if (kind == '>' && !identifier(arg)) fail(line.line, "invalid name '%s'", arg);
            add_node(line_nodes, tag);
            pos = (size_t)(end - text) + strlen(end_text);
        }
        bool standalone = tags == 1 && strchr("#^/!>=", only->kind);
        for (size_t j = 0; j < line_nodes->count; j++) if (line_nodes->children[j]->kind == 'T' && !spaces_only(line_nodes->children[j]->text)) standalone = false;
        if (standalone && only->kind == '>') only->indent = line_nodes->children[0]->text;
        if (!standalone) add_node(line_nodes, node('T', line.line, "\n"));
        for (size_t j = 0; j < line_nodes->count; j++) {
            Node *n = line_nodes->children[j];
            if (standalone && n->kind == 'T') continue;
            if (n->kind == '/') level--;
            else {
                add_node(levels[level], n);
                if (n->kind == '#' || n->kind == '^') {
                    levels = resize(levels, (level + 2) * sizeof(*levels));
                    levels[++level] = n;
                }
            }
        }
    }
    if (depth) fail(open[depth - 1]->line, "unclosed section '%s'", open[depth - 1]->expression.name);
    return tree;
}

static bool truth(Value *v) {
    return v->kind == STRING ? *v->text != 0 : v->kind == MAP || v->kind == LIST ? v->count != 0 : v->kind == INTEGER || v->kind == BOOLEAN ? v->number != 0 : false;
}

static char *string_value(Value *v) {
    if (v->kind == ABSENT) return "";
    if (v->kind == STRING) return v->text;
    if (v->kind == INTEGER) return format("%d", v->number);
    if (v->kind == BOOLEAN) return v->number ? "true" : "false";
    if (v->kind == MAP) fail(0, "cannot render map");
    Buffer out = {0};
    for (size_t i = 0; i < v->count; i++) {
        if (i) append(&out, ", ");
        append(&out, string_value(v->items[i]));
    }
    return finish(&out);
}

static int number(Value *v, const char *filter) {
    if (v->kind == ABSENT) return 0;
    if (v->kind == INTEGER) return v->number;
    if (v->kind == STRING && numeric_text(v->text, false)) return atoi(v->text);
    fail(0, "not a number for '%s'", filter);
    return 0;
}

static int entry_compare(const void *a, const void *b) {
    return strcmp(((const Entry *)a)->key, ((const Entry *)b)->key);
}

static Entry *sorted_entries(Value *v) {
    Entry *entries = allocate(v->count * sizeof(*entries));
    if (v->count) memcpy(entries, v->entries, v->count * sizeof(*entries));
    qsort(entries, v->count, sizeof(*entries), entry_compare);
    return entries;
}

static Value *sort_key(Value *v, Filter f) {
    int i = f.count ? entry_index(v, f.args[0]->text) : -1;
    return !f.count ? v : i >= 0 ? v->entries[i].value : &absent;
}

static int rank(Value *v) {
    return v->kind == LIST || v->kind == MAP ? 4 : v->kind == ABSENT ? 0 : v->kind == INTEGER ? 1 : v->kind == STRING ? 2 : 3;
}

static int value_compare(Value *a, Value *b) {
    int d = rank(a) - rank(b);
    if (d) return d;
    if (a->kind == STRING) return strcmp(a->text, b->text);
    if (a->kind == INTEGER || a->kind == BOOLEAN) return (a->number > b->number) - (a->number < b->number);
    return 0;
}

static Value *apply(Value *v, Filter f) {
    char *name = f.name;
    Value **a = f.args;
    if (!strcmp(name, "default")) return truth(v) ? v : a[0];
    if (!strcmp(name, "eq")) {
        char *left = string_value(v);
        char *right = string_value(a[0]);
        return boolean(!strcmp(left, right));
    }
    if (!strcmp(name, "length")) return integer((int)(v->kind == LIST || v->kind == MAP ? v->count : strlen(string_value(v))));
    if (!strcmp(name, "first") || !strcmp(name, "last")) return v->kind != LIST ? v : !v->count ? &absent : v->items[!strcmp(name, "first") ? 0 : v->count - 1];
    if (!strcmp(name, "reverse")) {
        if (v->kind == LIST) {
            Value *r = make(LIST);
            for (size_t i = v->count; i; i--) push(r, v->items[i - 1]);
            return r;
        }
        if (v->kind == STRING) {
            size_t n = strlen(v->text);
            char *s = duplicate(v->text);
            for (size_t i = 0; i < n; i++) s[i] = v->text[n - i - 1];
            return string(s);
        }
        return v;
    }
    if (!strcmp(name, "items")) {
        if (v->kind != MAP) return v;
        Value *r = make(LIST);
        Entry *entries = sorted_entries(v);
        for (size_t i = 0; i < v->count; i++) {
            Value *item = make(MAP);
            map_put(item, "key", string(entries[i].key));
            map_put(item, "value", entries[i].value);
            push(r, item);
        }
        return r;
    }
    if (!strcmp(name, "sort") || !strcmp(name, "pluck")) {
        if (v->kind != LIST) return v;
        Value *r = make(LIST);
        for (size_t i = 0; i < v->count; i++) push(r, !strcmp(name, "pluck") ? sort_key(v->items[i], f) : v->items[i]);
        if (!strcmp(name, "sort")) for (size_t i = 1; i < r->count; i++) {
            Value *item = r->items[i];
            size_t j = i;
            while (j && value_compare(sort_key(r->items[j - 1], f), sort_key(item, f)) > 0) {
                r->items[j] = r->items[j - 1];
                j--;
            }
            r->items[j] = item;
        }
        return r;
    }
    if (in_words(name, " sum  min  max ")) {
        if (v->kind != LIST) return integer(number(v, name));
        if (!v->count) return !strcmp(name, "sum") ? integer(0) : &absent;
        int result = 0;
        for (size_t i = 0; i < v->count; i++) {
            int n = number(v->items[i], name);
            if (!strcmp(name, "sum")) result += n;
            else if (!i || (!strcmp(name, "min") ? n < result : n > result)) result = n;
        }
        return integer(result);
    }
    if (in_words(name, " add  sub  mul  div  mod  gt  lt ")) {
        int n = number(v, name), x = a[0]->number;
        if (!strcmp(name, "add")) return integer(n + x);
        if (!strcmp(name, "sub")) return integer(n - x);
        if (!strcmp(name, "mul")) return integer(n * x);
        if (!strcmp(name, "gt")) return boolean(n > x);
        if (!strcmp(name, "lt")) return boolean(n < x);
        int q = n / x;
        if (n % x && (n < 0) != (x < 0)) q--;
        return integer(!strcmp(name, "div") ? q : n - x * q);
    }
    if (!strcmp(name, "comma")) {
        int n = number(v, name);
        char *digits = format("%d", n < 0 ? -n : n);
        size_t length = strlen(digits);
        Buffer out = {0};
        if (n < 0) character(&out, '-');
        for (size_t i = 0; i < length; i++) {
            if (i && (length - i) % 3 == 0) character(&out, ',');
            character(&out, digits[i]);
        }
        return string(finish(&out));
    }
    if (!strcmp(name, "join")) {
        if (v->kind != LIST) return string(string_value(v));
        Buffer out = {0};
        for (size_t i = 0; i < v->count; i++) {
            if (i) append(&out, a[0]->text);
            append(&out, string_value(v->items[i]));
        }
        return string(finish(&out));
    }
    char *text = string_value(v);
    size_t length = strlen(text);
    if (in_words(name, " upper  lower  title ")) {
        char *s = duplicate(text);
        for (size_t i = 0; i < length; i++) s[i] = !strcmp(name, "upper") || (!strcmp(name, "title") && (!i || text[i - 1] == ' ')) ? (char)toupper((unsigned char)s[i]) : (char)tolower((unsigned char)s[i]);
        return string(s);
    }
    if (!strcmp(name, "trim")) return string(trim(text));
    if (!strcmp(name, "pad") || !strcmp(name, "lpad")) {
        size_t n = (size_t)a[0]->number, count = n > length ? n - length : 0;
        char c = f.count == 1 ? ' ' : a[1]->text[0];
        Buffer out = {0};
        if (!strcmp(name, "pad")) append(&out, text);
        for (size_t i = 0; i < count; i++) character(&out, c);
        if (!strcmp(name, "lpad")) append(&out, text);
        return string(finish(&out));
    }
    if (!strcmp(name, "truncate")) return string(length > (size_t)a[0]->number ? format("%s...", slice(text, (size_t)a[0]->number)) : text);
    Buffer out = {0};
    size_t pos = 0, from = strlen(a[0]->text);
    while (text[pos]) {
        if (!strncmp(text + pos, a[0]->text, from)) {
            append(&out, a[1]->text);
            pos += from;
        } else character(&out, text[pos++]);
    }
    return string(finish(&out));
}

static Part name_part(char *text) {
    Part p = { .key = text, .index = 0, .numeric = subscript(text) };
    if (p.numeric) for (size_t i = 0; text[i]; i++) {
        if (p.index > 100000000) {
            p.index = -1;
            break;
        }
        p.index = p.index * 10 + text[i] - '0';
    }
    return p;
}

static Value *resolve(char *name, Value **contexts, size_t context_count, Loop *loops, size_t loop_count, bool *found) {
    *found = true;
    if (!strcmp(name, ".")) return contexts[context_count - 1];
    if (*name == '@') {
        if (!loop_count) {
            *found = false;
            return &absent;
        }
        Loop loop = loops[loop_count - 1];
        if (!strcmp(name, "@index")) return integer(loop.index);
        if (!strcmp(name, "@number")) return integer(loop.index + 1);
        return boolean(!strcmp(name, "@first") ? loop.index == 0 : loop.index == loop.count - 1);
    }
    size_t count;
    char **parts = split_unquoted(name, '.', &count);
    Value *current = NULL;
    Part first = name_part(parts[0]);
    for (size_t i = context_count; i; i--) if (has(contexts[i - 1], first)) {
        current = contexts[i - 1];
        break;
    }
    if (!current) {
        *found = false;
        return &absent;
    }
    for (size_t i = 0; i < count; i++) {
        Part p = name_part(parts[i]);
        if (!has(current, p)) {
            *found = false;
            return &absent;
        }
        current = get(current, p);
    }
    return current;
}

static char *html(const char *text) {
    Buffer out = {0};
    for (; *text; text++) switch (*text) {
        case '&': append(&out, "&amp;");
        break;
        case '<': append(&out, "&lt;");
        break;
        case '>': append(&out, "&gt;");
        break;
        case '"': append(&out, "&quot;");
        break;
        case '\'': append(&out, "&#39;");
        break;
        default: character(&out, *text);
    }
    return finish(&out);
}

static Source *find_source(Source *sources, size_t count, const char *name) {
    for (size_t i = 0; i < count; i++) if (!strcmp(sources[i].name, name)) return sources + i;
    return NULL;
}

static void render(Node *tree, Value **contexts, size_t context_count, Loop *loops, size_t loop_count, int depth, Buffer *out) {
    for (size_t i = 0; i < tree->count; i++) {
        Node *n = tree->children[i];
        active_line = n->line;
        if (n->kind == 'T') {
            append(out, n->text);
            continue;
        }
        if (n->kind == '>') {
            Source *partial = find_source(partials, partial_count, n->text);
            if (!partial) fail(0, "unknown partial '%s'", n->text);
            if (depth == 8) fail(0, "partial depth exceeded at '%s'", n->text);
            render(analyze(*partial, n->indent), contexts, context_count, loops, loop_count, depth + 1, out);
            continue;
        }
        if (!n->expression.name) continue;
        bool found;
        Value *v = resolve(n->expression.name, contexts, context_count, loops, loop_count, &found);
        if (strict && (n->kind == 'V' || n->kind == 'R') && !found) fail(0, "missing '%s'", n->expression.name);
        for (size_t j = 0; j < n->expression.count; j++) v = apply(v, n->expression.filters[j]);
        if (n->kind == 'V' || n->kind == 'R') {
            char *s = string_value(v);
            append(out, n->kind == 'V' ? html(s) : s);
        } else if (n->kind == '^') {
            if (!truth(v)) render(n, contexts, context_count, loops, loop_count, depth, out);
        } else if (v->kind == LIST) {
            Value **next = allocate((context_count + 1) * sizeof(*next));
            memcpy(next, contexts, context_count * sizeof(*next));
            Loop *next_loops = allocate((loop_count + 1) * sizeof(*next_loops));
            if (loop_count) memcpy(next_loops, loops, loop_count * sizeof(*next_loops));
            for (size_t j = 0; j < v->count; j++) {
                next[context_count] = v->items[j];
                next_loops[loop_count] = (Loop){(int)j, (int)v->count};
                render(n, next, context_count + 1, next_loops, loop_count + 1, depth, out);
            }
        } else if (truth(v)) {
            Value **next = allocate((context_count + 1) * sizeof(*next));
            memcpy(next, contexts, context_count * sizeof(*next));
            next[context_count] = v;
            render(n, next, context_count + 1, loops, loop_count, depth, out);
        }
    }
}

static void render_template(const char *name, int line) {
    active_line = 0;
    if (setjmp(failure)) {
        printf("TEMPLATE %s ERROR line %d: %s\n", name, error_line, error_reason);
        return;
    }
    Source *source = find_source(templates, template_count, name);
    if (!source) fail(line, "unknown template '%s'", name);
    Buffer out = {0};
    Value *contexts[] = {root};
    render(analyze(*source, ""), contexts, 1, NULL, 0, 0, &out);
    char *result = finish(&out);
    size_t lines = 0;
    for (size_t i = 0; i < out.length; i++) if (result[i] == '\n') lines++;
    if (out.length && result[out.length - 1] != '\n') lines++;
    printf("TEMPLATE %s OK lines=%zu chars=%zu\n", name, lines, out.length);
    fputs(result, stdout);
    if (out.length && result[out.length - 1] != '\n') putchar('\n');
}

static char *notation(Value *v) {
    if (v->kind == LIST) return "[]";
    if (v->kind == MAP) return "{}";
    if (v->kind != STRING) return string_value(v);
    Buffer out = {0};
    character(&out, '"');
    for (char *p = v->text; *p; p++) {
        if (*p == '\n') append(&out, "\\n");
        else {
            if (*p == '\\' || *p == '"') character(&out, '\\');
            character(&out, *p);
        }
    }
    character(&out, '"');
    return finish(&out);
}

static void leaves(Value *v, const char *path, Buffer *out, size_t *count) {
    if (v->kind == MAP && v->count) {
        Entry *entries = sorted_entries(v);
        for (size_t i = 0; i < v->count; i++) leaves(entries[i].value, *path ? format("%s.%s", path, entries[i].key) : entries[i].key, out, count);
    } else if (v->kind == LIST && v->count) for (size_t i = 0; i < v->count; i++) leaves(v->items[i], format("%s[%zu]", path, i), out, count);
    else {
        append(out, format("%s = %s\n", path, notation(v)));
        (*count)++;
    }
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') character(&b, (char)c);
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}

static bool store_source(Source **sources, size_t *count, Source source) {
    Source *old = find_source(*sources, *count, source.name);
    if (old) {
        *old = source;
        return true;
    }
    *sources = resize(*sources, (*count + 1) * sizeof(**sources));
    (*sources)[(*count)++] = source;
    return false;
}

static void data_block(Source source) {
    volatile size_t sets = 0, unsets = 0, errors = 0;
    Buffer messages = {0};
    for (size_t i = 0; i < source.count; i++) {
        char *text = source.lines[i].text;
        if (!*text || *text == '#') continue;
        active_line = 0;
        if (setjmp(failure)) {
            errors++;
            append(&messages, format("ERROR line %d: %s\n", source.lines[i].line, error_reason));
        } else {
            bool remove = !strncmp(text, "UNSET ", 6);
            change_data(text, remove);
            if (remove) unsets++;
            else sets++;
        }
    }
    printf("DATA set=%zu unset=%zu errors=%zu\n", (size_t)sets, (size_t)unsets, (size_t)errors);
    fputs(finish(&messages), stdout);
}

int main(void) {
    root = make(MAP);
    int number = 0;
    char *command;
    while ((command = read_line())) {
        number++;
        if (!strcmp(command, "END")) break;
        if (!strcmp(command, "DATA") || !strncmp(command, "PARTIAL ", 8) || !strncmp(command, "TEMPLATE ", 9)) {
            char *space = strchr(command, ' '), *type = space ? slice(command, (size_t)(space - command)) : command;
            Source source = { .name = space ? space + 1 : "" };
            char *end = format("END%s", type), *text;
            int start = number;
            while ((text = read_line())) {
                number++;
                if (!strcmp(text, end)) break;
                source.lines = resize(source.lines, (source.count + 1) * sizeof(*source.lines));
                source.lines[source.count++] = (SourceLine){text, number};
            }
            if (!strcmp(type, "DATA")) data_block(source);
            else if (!strcmp(type, "TEMPLATE")) {
                store_source(&templates, &template_count, source);
                render_template(source.name, start);
            } else {
                active_line = 0;
                if (setjmp(failure)) printf("PARTIAL %s ERROR line %d: %s\n", source.name, error_line, error_reason);
                else {
                    analyze(source, "");
                    bool replaced = store_source(&partials, &partial_count, source);
                    printf("PARTIAL %s %s lines=%zu\n", source.name, replaced ? "REPLACED" : "DEFINED", source.count);
                }
            }
        } else if (!strncmp(command, "RENDER ", 7)) render_template(command + 7, number);
        else if (!strcmp(command, "DUMP")) {
            Buffer out = {0};
            size_t count = 0;
            Entry *entries = sorted_entries(root);
            for (size_t i = 0; i < root->count; i++) leaves(entries[i].value, entries[i].key, &out, &count);
            printf("DUMP leaves=%zu\n", count);
            fputs(finish(&out), stdout);
        } else if (!strcmp(command, "RESET")) {
            root = make(MAP);
            partial_count = template_count = 0;
            puts(command);
        } else {
            strict = !strcmp(command, "STRICT ON");
            puts(command);
        }
    }
    return 0;
}
