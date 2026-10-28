#include "parser.h"
Arena *arena;
void *allocate(size_t size) {
    void *out = calloc(1, size ? size : 1);
    Allocation *record = malloc(sizeof *record);
    record->pointer = out;
    record->next = arena->head;
    arena->head = record;
    return out;
}
void *grow(const void *old, size_t old_size, size_t new_size) {
    void *out = allocate(new_size);
    if (old_size)
        memcpy(out, old, old_size);
    return out;
}
void arena_free(Arena *values) {
    Allocation *record = values->head;
    while (record) {
        Allocation *next = record->next;
        free(record->pointer);
        free(record);
        record = next;
    }
    values->head = NULL;
}
const char *copy_string(const char *text) {
    const size_t size = strlen(text) + 1;
    char *out = allocate(size);
    memcpy(out, text, size);
    return out;
}
const char *substring(const char *text, size_t start, size_t length) {
    char *out = allocate(length + 1);
    memcpy(out, text + start, length);
    return out;
}
const char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    const int size = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)size + 1);
    vsnprintf(out, (size_t)size + 1, pattern, args);
    va_end(args);
    return out;
}
void strings_add(Strings *values, const char *value) {
    if (values->n == values->capacity) {
        const int capacity = values->capacity ? values->capacity * 2 : 8;
        values->v =
            grow(values->v, (size_t)values->n * sizeof *values->v, (size_t)capacity * sizeof *values->v);
        values->capacity = capacity;
    }
    values->v[values->n++] = value;
}
bool strings_has(Strings values, const char *value) {
    for (int i = 0; i < values.n; ++i)
        if (strcmp(values.v[i], value) == 0)
            return true;
    return false;
}
bool strings_unique(Strings *values, const char *value) {
    if (strings_has(*values, value))
        return false;
    strings_add(values, value);
    return true;
}
Strings strings_slice(Strings values, int start, int end) {
    Strings out = {0};
    for (int i = start; i < end; ++i)
        strings_add(&out, values.v[i]);
    return out;
}
Strings strings_concat(Strings first, Strings second) {
    Strings out = strings_slice(first, 0, first.n);
    for (int i = 0; i < second.n; ++i)
        strings_add(&out, second.v[i]);
    return out;
}
bool strings_equal(Strings first, Strings second) {
    if (first.n != second.n)
        return false;
    for (int i = 0; i < first.n; ++i)
        if (strcmp(first.v[i], second.v[i]) != 0)
            return false;
    return true;
}
static int compare_terminals(const void *left, const void *right) {
    const char *a = *(const char *const *)left, *b = *(const char *const *)right;
    if (strcmp(a, "$") == 0)
        return strcmp(b, "$") == 0 ? 0 : 1;
    if (strcmp(b, "$") == 0)
        return -1;
    return strcmp(a, b);
}
void terminal_sort(Strings values) {
    if (values.n > 1)
        qsort(values.v, (size_t)values.n, sizeof *values.v, compare_terminals);
}
void ints_add(Ints *values, int value) {
    if (values->n == values->capacity) {
        const int capacity = values->capacity ? values->capacity * 2 : 8;
        values->v =
            grow(values->v, (size_t)values->n * sizeof *values->v, (size_t)capacity * sizeof *values->v);
        values->capacity = capacity;
    }
    values->v[values->n++] = value;
}
bool ints_has(Ints values, int value) {
    for (int i = 0; i < values.n; ++i)
        if (values.v[i] == value)
            return true;
    return false;
}
void alternatives_add(Alternatives *values, Strings alternative) {
    if (values->n == values->capacity) {
        const int capacity = values->capacity ? values->capacity * 2 : 4;
        values->v =
            grow(values->v, (size_t)values->n * sizeof *values->v, (size_t)capacity * sizeof *values->v);
        values->capacity = capacity;
    }
    values->v[values->n++] = alternative;
}
void alternatives_unique(Alternatives *values, Strings alternative) {
    for (int i = 0; i < values->n; ++i)
        if (strings_equal(values->v[i], alternative))
            return;
    alternatives_add(values, alternative);
}
bool nonterminal(const char *symbol) {
    const size_t size = strlen(symbol);
    return size >= 2 && symbol[0] == '<' && symbol[size - 1] == '>';
}
const char *notation(Strings sequence) {
    if (!sequence.n)
        return "%empty";
    Text out = {0};
    for (int i = 0; i < sequence.n; ++i)
        add(&out, "%s%s", i ? " " : "", sequence.v[i]);
    return out.data;
}
const char *production_text(const char *lhs, Strings rhs) {
    return format("%s -> %s", lhs, notation(rhs));
}
int rule_index(const Grammar *grammar, const char *name) {
    for (int i = 0; i < grammar->n; ++i)
        if (strcmp(grammar->v[i].name, name) == 0)
            return i;
    return -1;
}
void rule_add(Grammar *grammar, Rule rule, int position) {
    if (grammar->n == grammar->capacity) {
        const int capacity = grammar->capacity ? grammar->capacity * 2 : 8;
        grammar->v =
            grow(grammar->v, (size_t)grammar->n * sizeof *grammar->v, (size_t)capacity * sizeof *grammar->v);
        grammar->capacity = capacity;
    }
    memmove(grammar->v + position + 1, grammar->v + position,
            (size_t)(grammar->n - position) * sizeof *grammar->v);
    grammar->v[position] = rule;
    ++grammar->n;
}
Grammar grammar_clone(const Grammar *grammar) {
    Grammar out = {.start = grammar->start};
    for (int i = 0; i < grammar->n; ++i)
        rule_add(&out, grammar->v[i], out.n);
    return out;
}
static void append_format(Text *out, const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    const int needed = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    const size_t size = out->size + (size_t)needed + 1;
    if (size > out->capacity) {
        const size_t capacity = size * 2;
        out->data = grow(out->data, out->size, capacity);
        out->capacity = capacity;
    }
    vsnprintf(out->data + out->size, out->capacity - out->size, pattern, args);
    out->size += (size_t)needed;
}
void add(Text *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    append_format(out, pattern, args);
    va_end(args);
}
void line(Text *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    append_format(out, pattern, args);
    va_end(args);
    add(out, "\n");
}
typedef enum { NT, WORD, QUOTED, DEFINITION, BAR, START, DECLARATION, EMPTY, INVALID } Kind;
typedef struct {
    Kind kind;
    const char *text;
    int start, end;
} Token;
typedef struct {
    Token *v;
    int n, capacity;
} Tokens;
static bool letter(char ch) {
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z');
}
static bool word_character(char ch) {
    return letter(ch) || (ch >= '0' && ch <= '9') || ch == '_';
}
static Tokens lex(const char *text) {
    Tokens out = {0};
    const int length = (int)strlen(text);
    int i = 0;
    while (i < length) {
        if (text[i] == ' ') {
            ++i;
            continue;
        }
        if (text[i] == '#')
            break;
        const int start = i;
        Token token = {.kind = INVALID, .text = "", .start = start + 1, .end = start + 1};
        if (text[i] == '<') {
            int j = i + 1;
            if (j < length && letter(text[j])) {
                ++j;
                while (j < length && word_character(text[j]))
                    ++j;
                if (j < length && text[j] == '>') {
                    i = j + 1;
                    token.kind = NT;
                    token.text = substring(text, (size_t)start, (size_t)(i - start));
                }
            }
        } else if (text[i] == '"') {
            int j = i + 1;
            while (j < length && text[j] != ' ' && text[j] != '"')
                ++j;
            if (j > i + 1 && j < length && text[j] == '"') {
                token.kind = QUOTED;
                token.text = substring(text, (size_t)i + 1, (size_t)(j - i - 1));
                i = j + 1;
            }
        } else if (letter(text[i])) {
            ++i;
            while (i < length && word_character(text[i]))
                ++i;
            token.kind = WORD;
            token.text = substring(text, (size_t)start, (size_t)(i - start));
        } else if (strncmp(text + i, "::=", 3) == 0) {
            token.kind = DEFINITION;
            token.text = "::=";
            i += 3;
        } else if (text[i] == '|') {
            token.kind = BAR;
            token.text = "|";
            ++i;
        } else if (text[i] == '%') {
            int j = i + 1;
            while (j < length && letter(text[j]))
                ++j;
            const char *directive = substring(text, (size_t)i + 1, (size_t)(j - i - 1));
            if (strcmp(directive, "empty") == 0 || strcmp(directive, "start") == 0 ||
                strcmp(directive, "token") == 0) {
                token.kind = strcmp(directive, "empty") == 0   ? EMPTY
                             : strcmp(directive, "start") == 0 ? START
                                                               : DECLARATION;
                token.text = format("%%%s", directive);
                i = j;
            }
        }
        if (token.kind != INVALID)
            token.end = i;
        if (out.n == out.capacity) {
            const int capacity = out.capacity ? out.capacity * 2 : 8;
            out.v = grow(out.v, (size_t)out.n * sizeof *out.v, (size_t)capacity * sizeof *out.v);
            out.capacity = capacity;
        }
        out.v[out.n++] = token;
        if (token.kind == INVALID)
            break;
    }
    return out;
}
static int transition(int state, Kind kind) {
    if (state == 0) {
        if (kind == NT)
            return 1;
        if (kind == BAR)
            return 2;
        if (kind == START)
            return 5;
        if (kind == DECLARATION)
            return 7;
    } else if (state == 1) {
        if (kind == DEFINITION)
            return 2;
    } else if (state == 2) {
        if (kind == NT || kind == WORD || kind == QUOTED)
            return 3;
        if (kind == EMPTY)
            return 4;
    } else if (state == 3) {
        if (kind == NT || kind == WORD || kind == QUOTED)
            return 3;
        if (kind == BAR)
            return 2;
    } else if (state == 4) {
        if (kind == BAR)
            return 2;
    } else if (state == 5) {
        if (kind == NT)
            return 6;
    } else if (state == 7 || state == 8) {
        if (kind == WORD)
            return 8;
    }
    return -1;
}
static void append_alternative(Parsed *out, int lhs, Strings alternative, int line_number) {
    Alternatives *values = &out->grammar.v[lhs].alternatives;
    for (int i = 0; i < values->n; ++i)
        if (strings_equal(values->v[i], alternative)) {
            strings_add(&out->diagnostics, format("line %d: duplicate alternative %s", line_number,
                                                  production_text(out->grammar.v[lhs].name, alternative)));
            return;
        }
    alternatives_add(values, alternative);
}
Parsed read_grammar(Strings lines) {
    Parsed out = {0};
    const char *attached = NULL;
    bool start_seen = false;
    for (int index = 0; index < lines.n; ++index) {
        const Tokens tokens = lex(lines.v[index]);
        if (!tokens.n)
            continue;
        const int line_number = index + 1;
        int state = 0, column = 0;
        for (int i = 0; i < tokens.n; ++i) {
            state = transition(state, tokens.v[i].kind);
            if (state < 0) {
                column = tokens.v[i].start;
                break;
            }
        }
        if (!column && state != 3 && state != 4 && state != 6 && state != 8)
            column = tokens.v[tokens.n - 1].end + 1;
        if (column) {
            strings_add(&out.diagnostics, format("line %d: syntax error at column %d", line_number, column));
            attached = NULL;
            continue;
        }
        const Kind first = tokens.v[0].kind;
        if (first == START) {
            if (start_seen)
                strings_add(&out.diagnostics, format("line %d: duplicate %%start", line_number));
            else {
                out.grammar.start = tokens.v[1].text;
                start_seen = true;
            }
            attached = NULL;
            continue;
        }
        if (first == DECLARATION) {
            out.declarations = true;
            for (int i = 1; i < tokens.n; ++i)
                strings_unique(&out.declared, tokens.v[i].text);
            attached = NULL;
            continue;
        }
        int begin;
        if (first == NT) {
            attached = tokens.v[0].text;
            if (rule_index(&out.grammar, attached) < 0)
                rule_add(&out.grammar, (Rule){.name = attached}, out.grammar.n);
            begin = 2;
        } else {
            if (!attached) {
                strings_add(&out.diagnostics, format("line %d: continuation without a rule", line_number));
                continue;
            }
            begin = 1;
        }
        const int lhs = rule_index(&out.grammar, attached);
        Strings alternative = {0};
        for (int i = begin; i < tokens.n; ++i) {
            const Token token = tokens.v[i];
            if (token.kind == BAR) {
                append_alternative(&out, lhs, alternative, line_number);
                alternative = (Strings){0};
                continue;
            }
            if (token.kind == WORD) {
                bool known = false;
                for (int j = 0; j < out.nwords; ++j)
                    if (strcmp(out.words[j].name, token.text) == 0)
                        known = true;
                if (!known) {
                    if (out.nwords == out.word_capacity) {
                        const int capacity = out.word_capacity ? out.word_capacity * 2 : 8;
                        out.words = grow(out.words, (size_t)out.nwords * sizeof *out.words,
                                         (size_t)capacity * sizeof *out.words);
                        out.word_capacity = capacity;
                    }
                    out.words[out.nwords++] = (Occurrence){token.text, line_number};
                }
            }
            if (token.kind != EMPTY)
                strings_add(&alternative, token.text);
        }
        append_alternative(&out, lhs, alternative, line_number);
    }
    if (!start_seen)
        out.grammar.start = out.grammar.v[0].name;
    return out;
}
