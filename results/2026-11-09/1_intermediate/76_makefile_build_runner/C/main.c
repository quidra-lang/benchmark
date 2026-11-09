#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;

typedef struct {
    Allocation *head;
} Arena;
static Arena permanent, makefile_memory, temporary;
static jmp_buf command_error;
static const char *location = "make";

static void *memory(Arena *arena, size_t size) {
    void *p = calloc(1, size ? size : 1);
    Allocation *a = malloc(sizeof *a);
    if (!p || !a) exit(EXIT_FAILURE);
    *a = (Allocation){p, arena->head};
    arena->head = a;
    return p;
}

static void clear_arena(Arena *arena) {
    while (arena->head) {
        Allocation *next = arena->head->next;
        free(arena->head->pointer);
        free(arena->head);
        arena->head = next;
    }
}

static char *copy(Arena *arena, const char *text) {
    char *p = memory(arena, strlen(text) + 1);
    strcpy(p, text);
    return p;
}

static char *part(const char *text, size_t length) {
    char *p = memory(&temporary, length + 1);
    memcpy(p, text, length);
    return p;
}

static char *format(const char *text, ...) {
    va_list args, other;
    va_start(args, text);
    va_copy(other, args);
    int length = vsnprintf(NULL, 0, text, other);
    va_end(other);
    char *p = memory(&temporary, (size_t)length + 1);
    vsnprintf(p, (size_t)length + 1, text, args);
    va_end(args);
    return p;
}

static void expansion_error(const char *reason) {
    printf("%s: *** %s.  Stop.\n", location, reason);
    longjmp(command_error, 1);
}

static char *left_trim(const char *text) {
    while (*text == ' ') text++;
    return (char *)text;
}

static char *right_trim(const char *text) {
    size_t n = strlen(text);
    while (n && text[n - 1] == ' ') n--;
    return part(text, n);
}

static char *trim(const char *text) {
    return right_trim(left_trim(text));
}

static bool numeric(const char *text) {
    if (!*text) return false;
    for (const char *p = text; *p; p++) if (*p < '0' || *p > '9') return false;
    return true;
}

typedef struct {
    char **items;
    int count, capacity;
} Strings;

static void add_string(Strings *s, char *text, Arena *arena) {
    if (s->count == s->capacity) {
        int capacity = s->capacity ? 2 * s->capacity : 4;
        char **items = memory(arena, (size_t)capacity * sizeof *items);
        if (s->count) memcpy(items, s->items, (size_t)s->count * sizeof *items);
        s->items = items;
        s->capacity = capacity;
    }
    s->items[s->count++] = text;
}

static bool contains(const Strings *s, const char *text) {
    for (int i = 0; i < s->count; i++) if (!strcmp(s->items[i], text)) return true;
    return false;
}

static void add_unique(Strings *s, char *text, Arena *arena) {
    if (!contains(s, text)) add_string(s, text, arena);
}

static Strings words(const char *text) {
    Strings result = {0};
    while (*text) {
        while (*text == ' ') text++;
        const char *end = text;
        while (*end && *end != ' ') end++;
        if (end != text) add_string(&result, part(text, (size_t)(end - text)), &temporary);
        text = end;
    }
    return result;
}

static int string_compare(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static Strings sorted(const Strings *s) {
    Strings result = {0};
    for (int i = 0; i < s->count; i++) add_string(&result, s->items[i], &temporary);
    if (result.count > 1) qsort(result.items, (size_t)result.count, sizeof *result.items, string_compare);
    return result;
}

typedef struct {
    char *text;
    size_t length, capacity;
} Buffer;

static void append_n(Buffer *b, const char *text, size_t length) {
    if (b->length + length + 1 > b->capacity) {
        size_t capacity = b->capacity ? 2 * b->capacity : 32;
        while (capacity < b->length + length + 1) capacity *= 2;
        char *p = memory(&temporary, capacity);
        if (b->length) memcpy(p, b->text, b->length);
        b->text = p;
        b->capacity = capacity;
    }
    memcpy(b->text + b->length, text, length);
    b->length += length;
    b->text[b->length] = '\0';
}

static void append(Buffer *b, const char *text) {
    append_n(b, text, strlen(text));
}

static char *finish(Buffer *b) {
    return b->text ? b->text : "";
}

static char *join(const Strings *s) {
    Buffer b = {0};
    for (int i = 0; i < s->count; i++) {
        if (i) append(&b, " ");
        append(&b, s->items[i]);
    }
    return finish(&b);
}

static char *stem(const char *pattern, const char *word) {
    const char *percent = strchr(pattern, '%');
    if (!percent) return !strcmp(pattern, word) ? "" : NULL;
    size_t prefix = (size_t)(percent - pattern), suffix = strlen(percent + 1), length = strlen(word);
    if (length < prefix + suffix || strncmp(pattern, word, prefix) || strcmp(percent + 1, word + length - suffix)) return NULL;
    return part(word + prefix, length - prefix - suffix);
}

static char *substitute(const char *pattern, const char *value) {
    const char *p = strchr(pattern, '%');
    if (!p) return (char *)pattern;
    return format("%s%s%s", part(pattern, (size_t)(p - pattern)), value, p + 1);
}

static char *replacement(const char *word, const char *pattern, const char *value) {
    char *s = stem(pattern, word);
    return !s ? (char *)word : strchr(pattern, '%') ? substitute(value, s) : (char *)value;
}

static bool wildcard(const char *pattern, const char *name) {
    size_t n = strlen(name);
    bool *previous = calloc(n + 1, sizeof *previous), *next = calloc(n + 1, sizeof *next);
    if (!previous || !next) exit(EXIT_FAILURE);
    previous[0] = true;
    for (const char *p = pattern; *p; p++) {
        memset(next, 0, (n + 1) * sizeof *next);
        for (size_t j = 0; j <= n; j++) {
            if (*p == '*') next[j] = previous[j] || (j && name[j - 1] != '/' && next[j - 1]);
            else if (j) next[j] = previous[j - 1] && (*p == '?' ? name[j - 1] != '/' : *p == name[j - 1]);
        }
        bool *swap = previous;
        previous = next;
        next = swap;
    }
    bool result = previous[n];
    free(previous);
    free(next);
    return result;
}

typedef struct {
    char *name;
    int time;
} File;
static File *files, *saved_files;
static int file_count, file_capacity, clock_value, saved_count, saved_clock;
static bool dry_saved;

static int file_index(const char *name) {
    int lo = 0, hi = file_count;
    while (lo < hi) {
        int middle = lo + (hi - lo) / 2;
        if (strcmp(files[middle].name, name) < 0) lo = middle + 1;
        else hi = middle;
    }
    return lo < file_count && !strcmp(files[lo].name, name) ? lo : -1;
}

static void put_file(const char *name, int time) {
    int i = file_index(name);
    if (i >= 0) {
        files[i].time = time;
        return;
    }
    if (file_count == file_capacity) {
        file_capacity = file_capacity ? 2 * file_capacity : 8;
        File *p = realloc(files, (size_t)file_capacity * sizeof *p);
        if (!p) exit(EXIT_FAILURE);
        files = p;
    }
    i = 0;
    while (i < file_count && strcmp(files[i].name, name) < 0) i++;
    memmove(files + i + 1, files + i, (size_t)(file_count - i) * sizeof *files);
    files[i] = (File){copy(&permanent, name), time};
    file_count++;
}

static void new_time(const char *name) {
    put_file(name, ++clock_value);
}

static bool remove_file(const char *name) {
    int i = file_index(name);
    if (i < 0) return false;
    memmove(files + i, files + i + 1, (size_t)(file_count - i - 1) * sizeof *files);
    file_count--;
    return true;
}

static Strings wildcard_expansion(const char *pattern) {
    Strings result = {0};
    if (!strchr(pattern, '*') && !strchr(pattern, '?')) {
        int i = file_index(pattern);
        if (i >= 0) add_string(&result, files[i].name, &temporary);
        return result;
    }
    for (int i = 0; i < file_count; i++) if (wildcard(pattern, files[i].name)) add_string(&result, files[i].name, &temporary);
    return result;
}

typedef struct Variable {
    char *name, *value;
    bool simple;
    struct Variable *next;
} Variable;

typedef struct RecipeLine {
    int number;
    char *text;
    struct RecipeLine *next;
} RecipeLine;

typedef struct {
    RecipeLine *first, *last;
} Recipe;

typedef struct Rule {
    char *name, *stem;
    bool pattern;
    Strings prerequisites;
    Recipe *recipe;
    struct Rule *next;
} Rule;

typedef struct {
    Rule **rules;
    int count, capacity;
    Recipe *recipe;
} Group;

typedef struct {
    bool outer, value, alternative;
    int line;
} Condition;

typedef struct Scope {
    char *name, *value;
    Strings *arguments;
    struct Scope *previous;
} Scope;

typedef struct Active {
    const char *name;
    struct Active *previous;
} Active;
static Variable *variables;
static Rule *rules, *patterns, *pattern_tail;
static Strings phony;
static bool loaded, has_automatic;
static char *default_goal, *automatic[5];
static int variable_count, target_count;
static Scope *scopes;
static Active *expanding;
static const char *auto_names[] = {"@", "<", "^", "?", "*"};

static Variable *find_variable(const char *name) {
    for (Variable *v = variables; v; v = v->next) if (!strcmp(v->name, name)) return v;
    return NULL;
}

static void set_variable(const char *name, bool simple, const char *value) {
    Variable *v = find_variable(name);
    if (!v) {
        v = memory(&makefile_memory, sizeof *v);
        v->name = copy(&makefile_memory, name);
        variable_count++;
        Variable **p = &variables;
        while (*p && strcmp((*p)->name, name) < 0) p = &(*p)->next;
        v->next = *p;
        *p = v;
    }
    v->simple = simple;
    v->value = copy(&makefile_memory, value);
}

static Rule *find_rule(const char *name) {
    for (Rule *r = rules; r; r = r->next) if (!strcmp(r->name, name)) return r;
    return NULL;
}

static void discard(void) {
    variables = NULL;
    rules = patterns = pattern_tail = NULL;
    phony = (Strings){0};
    default_goal = NULL;
    loaded = false;
    variable_count = target_count = 0;
    clear_arena(&makefile_memory);
}

static void clean_expansion(void) {
    scopes = NULL;
    expanding = NULL;
    has_automatic = false;
    location = "make";
}
static char *expand(const char *text);
static char *reference(const char *content, char opening);

static int bracket_end(const char *text, int opening) {
    char open = text[opening], close = open == '(' ? ')' : '}';
    int depth = 0;
    for (int i = opening; text[i]; i++) {
        if (text[i] == open) depth++;
        else if (text[i] == close && --depth == 0) return i;
    }
    expansion_error("unterminated variable reference");
    return -1;
}

static char *value(const char *name) {
    for (Scope *s = scopes; s; s = s->previous) {
        if (!s->arguments) {
            if (!strcmp(s->name, name)) return s->value;
        } else if (numeric(name)) {
            int i = atoi(name);
            return i < s->arguments->count ? s->arguments->items[i] : "";
        }
    }
    if (has_automatic) for (int i = 0; i < 5; i++) if (!strcmp(name, auto_names[i])) return automatic[i];
    Variable *v = find_variable(name);
    if (!v) return "";
    if (v->simple) return v->value;
    for (Active *a = expanding; a; a = a->previous) if (!strcmp(a->name, name)) expansion_error(format("Recursive variable '%s' references itself (eventually)", name));
    Active active = {name, expanding};
    expanding = &active;
    char *result = expand(v->value);
    expanding = active.previous;
    return result;
}

static char *expand(const char *text) {
    Buffer result = {0};
    for (int i = 0; text[i];) {
        char c = text[i++];
        if (c != '$') {
            append_n(&result, &c, 1);
            continue;
        }
        if (!text[i]) break;
        c = text[i++];
        if (c == '$') append(&result, "$");
        else if (c == '(' || c == '{') {
            int end = bracket_end(text, i - 1);
            append(&result, reference(part(text + i, (size_t)(end - i)), c));
            i = end + 1;
        } else {
            char name[2] = {c, '\0'};
            append(&result, value(name));
        }
    }
    return finish(&result);
}
enum { SUBST, PATSUBST, STRIP, FINDSTRING, FILTER, FILTER_OUT, SORT, WORD, WORDLIST, WORDS, FIRSTWORD, LASTWORD, DIR, NOTDIR, SUFFIX, BASENAME, ADDSUFFIX, ADDPREFIX, WILDCARD, FOREACH, IF, CALL, VALUE, INFO, WARNING, ERROR_FUNCTION };

typedef struct {
    const char *name;
    int minimum, maximum;
} Function;
static const Function functions[] = {
    {"subst", 3, 3},
    {"patsubst", 3, 3},
    {"strip", 1, 1},
    {"findstring", 2, 2},
    {"filter", 2, 2},
    {"filter-out", 2, 2},
    {"sort", 1, 1},
    {"word", 2, 2},
    {"wordlist", 3, 3},
    {"words", 1, 1},
    {"firstword", 1, 1},
    {"lastword", 1, 1},
    {"dir", 1, 1},
    {"notdir", 1, 1},
    {"suffix", 1, 1},
    {"basename", 1, 1},
    {"addsuffix", 2, 2},
    {"addprefix", 2, 2},
    {"wildcard", 1, 1},
    {"foreach", 3, 3},
    {"if", 2, 3},
    {"call", 1, 2147483647},
    {"value", 1, 1},
    {"info", 1, 1},
    {"warning", 1, 1},
    {"error", 1, 1}
};

static int function_index(const char *name) {
    for (int i = 0; i < (int)(sizeof functions / sizeof *functions); i++) if (!strcmp(functions[i].name, name)) return i;
    return -1;
}

static Strings arguments(const char *text, int maximum, char opening) {
    char closing = opening == '(' ? ')' : '}';
    int depth = 0, start = 0;
    Strings result = {0};
    int i;
    for (i = 0; text[i]; i++) {
        char c = text[i];
        if (c == opening) depth++;
        else if (c == closing) depth--;
        else if (c == ',' && depth == 0 && result.count < maximum - 1) {
            add_string(&result, part(text + start, (size_t)(i - start)), &temporary);
            start = i + 1;
        }
    }
    add_string(&result, part(text + start, (size_t)(i - start)), &temporary);
    return result;
}

static char *function(int f, const char *text, char opening) {
    const Function *fn = &functions[f];
    Strings raw = arguments(text, fn->maximum, opening);
    if (raw.count < fn->minimum) expansion_error(format("insufficient number of arguments (%d) to function '%s'", raw.count, fn->name));
    if (f == FOREACH) {
        char *name = trim(expand(raw.items[0]));
        Strings list = words(expand(raw.items[1])), result = {0};
        for (int i = 0; i < list.count; i++) {
            Scope scope = {name, list.items[i], NULL, scopes};
            scopes = &scope;
            add_string(&result, expand(raw.items[2]), &temporary);
            scopes = scope.previous;
        }
        return join(&result);
    }
    if (f == IF) {
        bool condition = *trim(expand(raw.items[0])) != '\0';
        return condition ? expand(raw.items[1]) : raw.count == 3 ? expand(raw.items[2]) : "";
    }
    Strings a = {0};
    for (int i = 0; i < raw.count; i++) {
        char *v = expand(raw.items[i]);
        add_string(&a, f == SUBST || f == CALL ? v : trim(v), &temporary);
    }
    if (f == CALL) {
        char *name = trim(a.items[0]);
        Variable *v = find_variable(name);
        if (!v) return "";
        if (v->simple) return v->value;
        a.items[0] = name;
        Scope scope = {NULL, NULL, &a, scopes};
        scopes = &scope;
        char *result = expand(v->value);
        scopes = scope.previous;
        return result;
    }
    if (f == VALUE) {
        Variable *v = find_variable(a.items[0]);
        return v ? v->value : "";
    }
    if (f == INFO) {
        puts(a.items[0]);
        return "";
    }
    if (f == WARNING) {
        printf("%s: %s\n", location, a.items[0]);
        return "";
    }
    if (f == ERROR_FUNCTION) {
        expansion_error(a.items[0]);
        return "";
    }
    if (f == SUBST) {
        if (!*a.items[0]) return a.items[2];
        Buffer b = {0};
        const char *p = a.items[2], *next;
        while ((next = strstr(p, a.items[0])) != NULL) {
            append_n(&b, p, (size_t)(next - p));
            append(&b, a.items[1]);
            p = next + strlen(a.items[0]);
        }
        append(&b, p);
        return finish(&b);
    }
    if (f == FINDSTRING) return strstr(a.items[1], a.items[0]) ? a.items[0] : "";
    if (f == WORD) {
        if (!numeric(a.items[0])) expansion_error(format("non-numeric first argument to 'word' function: '%s'", a.items[0]));
        int n = atoi(a.items[0]);
        if (!n) expansion_error("first argument to 'word' function must be greater than 0");
        Strings list = words(a.items[1]);
        return n <= list.count ? list.items[n - 1] : "";
    }
    if (f == WORDLIST) {
        if (!numeric(a.items[0])) expansion_error(format("non-numeric first argument to 'wordlist' function: '%s'", a.items[0]));
        if (!numeric(a.items[1])) expansion_error(format("non-numeric second argument to 'wordlist' function: '%s'", a.items[1]));
        int start = atoi(a.items[0]), end = atoi(a.items[1]);
        if (!start) expansion_error(format("invalid first argument to 'wordlist' function: '%s'", a.items[0]));
        Strings list = words(a.items[2]), result = {0};
        for (int i = start - 1; i < end && i < list.count; i++) add_string(&result, list.items[i], &temporary);
        return join(&result);
    }
    Strings list = words(a.items[a.count - 1]), result = {0};
    if (f == WORDS) return format("%d", list.count);
    if (f == FIRSTWORD) return list.count ? list.items[0] : "";
    if (f == LASTWORD) return list.count ? list.items[list.count - 1] : "";
    Strings filters = {0};
    if (f == FILTER || f == FILTER_OUT) filters = words(a.items[0]);
    for (int i = 0; i < list.count; i++) {
        char *word = list.items[i], *v = NULL;
        if (f == PATSUBST) v = replacement(word, a.items[0], a.items[1]);
        else if (f == FILTER || f == FILTER_OUT) {
            bool found = false;
            for (int j = 0; j < filters.count; j++) if (stem(filters.items[j], word)) {
                found = true;
                break;
            }
            if (found == (f == FILTER)) v = word;
        } else if (f == STRIP) v = word;
        else if (f == SORT) {
            add_unique(&result, word, &temporary);
            continue;
        } else if (f == ADDSUFFIX) v = format("%s%s", word, a.items[0]);
        else if (f == ADDPREFIX) v = format("%s%s", a.items[0], word);
        else if (f == WILDCARD) {
            Strings matches = wildcard_expansion(word);
            for (int j = 0; j < matches.count; j++) add_string(&result, matches.items[j], &temporary);
            continue;
        } else {
            char *slash = strrchr(word, '/'), *dot = strrchr(word, '.');
            bool extension = dot && (!slash || dot > slash);
            if (f == DIR) v = slash ? part(word, (size_t)(slash - word + 1)) : "./";
            else if (f == NOTDIR) v = slash ? slash + 1 : word;
            else if (f == SUFFIX) {
                if (extension) v = dot;
            } else if (f == BASENAME) v = extension ? part(word, (size_t)(dot - word)) : word;
        }
        if (v) add_string(&result, v, &temporary);
    }
    if (f == SORT) result = sorted(&result);
    return join(&result);
}

static char *reference(const char *content, char opening) {
    const char *space = strchr(content, ' ');
    if (space) {
        int f = function_index(part(content, (size_t)(space - content)));
        if (f >= 0) return function(f, left_trim(space + 1), opening);
    }
    char *name = expand(content), *colon = strchr(name, ':'), *equal = colon ? strchr(colon + 1, '=') : NULL;
    if (equal) {
        char *pattern = part(colon + 1, (size_t)(equal - colon - 1)), *repl = equal + 1;
        if (!strchr(pattern, '%')) {
            pattern = format("%%%s", pattern);
            repl = format("%%%s", repl);
        }
        Strings list = words(value(part(name, (size_t)(colon - name)))), result = {0};
        for (int i = 0; i < list.count; i++) add_string(&result, replacement(list.items[i], pattern, repl), &temporary);
        return join(&result);
    }
    return value(name);
}

typedef struct {
    int equal, colon, semicolon;
} Positions;

static Positions outside(const char *text) {
    Positions p = {-1, -1, -1};
    for (int i = 0; text[i];) {
        char c = text[i];
        if (c == '$') {
            if (text[i + 1] == '(' || text[i + 1] == '{') i = bracket_end(text, i + 1) + 1;
            else i += text[i + 1] ? 2 : 1;
        } else {
            if (c == '=' && p.equal < 0) p.equal = i;
            if (c == ':' && p.colon < 0) p.colon = i;
            if (c == ';' && p.semicolon < 0) p.semicolon = i;
            i++;
        }
    }
    return p;
}

static Rule *register_rule(const char *name, const Strings *prerequisites) {
    Rule *r = find_rule(name);
    if (!r) {
        r = memory(&makefile_memory, sizeof *r);
        r->name = copy(&makefile_memory, name);
        r->stem = "";
        target_count++;
        Rule **p = &rules;
        while (*p && strcmp((*p)->name, name) < 0) p = &(*p)->next;
        r->next = *p;
        *p = r;
    }
    for (int i = 0; i < prerequisites->count; i++) if (!contains(&r->prerequisites, prerequisites->items[i])) add_string(&r->prerequisites, copy(&makefile_memory, prerequisites->items[i]), &makefile_memory);
    if (!default_goal && *name != '.') default_goal = r->name;
    return r;
}

static void group_add(Group *g, Rule *r) {
    if (g->count == g->capacity) {
        int capacity = g->capacity ? 2 * g->capacity : 4;
        Rule **p = memory(&temporary, (size_t)capacity * sizeof *p);
        if (g->count) memcpy(p, g->rules, (size_t)g->count * sizeof *p);
        g->rules = p;
        g->capacity = capacity;
    }
    g->rules[g->count++] = r;
}

static void add_recipe(Group *g, int number, const char *text) {
    if (!g->count) return;
    if (!g->recipe) {
        g->recipe = memory(&makefile_memory, sizeof *g->recipe);
        for (int i = 0; i < g->count; i++) {
            Rule *r = g->rules[i];
            if (!r->pattern && r->recipe) {
                printf("Makefile:%d: warning: overriding recipe for target '%s'\n", number, r->name);
                printf("Makefile:%d: warning: ignoring old recipe for target '%s'\n", r->recipe->first->number, r->name);
            }
            r->recipe = g->recipe;
        }
    }
    RecipeLine *line = memory(&makefile_memory, sizeof *line);
    line->number = number;
    line->text = copy(&makefile_memory, text);
    if (g->recipe->last) g->recipe->last->next = line;
    else g->recipe->first = line;
    g->recipe->last = line;
}

static bool active(Condition *conditions, int count) {
    return !count || (conditions[count - 1].outer && conditions[count - 1].value);
}

static void conditional(const char *name, const char *rest, int line, Condition *conditions, int *count) {
    if (!strcmp(name, "else")) {
        if (!*count) expansion_error("extraneous 'else'");
        Condition *top = &conditions[*count - 1];
        if (top->alternative) expansion_error("only one 'else' per conditional");
        top->value = !top->value;
        top->alternative = true;
        return;
    }
    if (!strcmp(name, "endif")) {
        if (!*count) expansion_error("extraneous 'endif'");
        (*count)--;
        return;
    }
    bool outer = active(conditions, *count), condition = false;
    if (outer) {
        if (!strcmp(name, "ifdef") || !strcmp(name, "ifndef")) {
            Variable *v = find_variable(trim(expand(rest)));
            condition = v && *v->value;
            if (!strcmp(name, "ifndef")) condition = !condition;
        } else {
            size_t n = strlen(rest);
            if (n < 2 || rest[0] != '(' || rest[n - 1] != ')') expansion_error("invalid syntax in conditional");
            char *inside = part(rest + 1, n - 2);
            int depth = 0, comma = -1;
            for (int i = 0; inside[i]; i++) {
                if (inside[i] == '(') depth++;
                else if (inside[i] == ')') depth--;
                else if (inside[i] == ',' && !depth) {
                    comma = i;
                    break;
                }
            }
            if (comma < 0) expansion_error("invalid syntax in conditional");
            char *a = trim(expand(part(inside, (size_t)comma)));
            char *b = trim(expand(inside + comma + 1));
            condition = !strcmp(a, b);
            if (!strcmp(name, "ifneq")) condition = !condition;
        }
    }
    conditions[(*count)++] = (Condition){outer, condition, false, line};
}

static void load(const Strings *body) {
    discard();
    Group *current = NULL;
    Condition *conditions = memory(&temporary, (size_t)(body->count + 1) * sizeof *conditions);
    int condition_count = 0;
    for (int i = 0; i < body->count; i++) {
        int number = i + 1;
        location = format("Makefile:%d", number);
        char *line = body->items[i];
        if (*line == '>') {
            if (!active(conditions, condition_count)) continue;
            if (!current) expansion_error("recipe commences before first target");
            add_recipe(current, number, left_trim(line + 1));
            continue;
        }
        while (*line && line[strlen(line) - 1] == '\\' && i + 1 < body->count) line = format("%s %s", right_trim(part(line, strlen(line) - 1)), left_trim(body->items[++i]));
        char *comment = strchr(line, '#'), *t = trim(comment ? part(line, (size_t)(comment - line)) : line), *space = strchr(t, ' ');
        char *first = space ? part(t, (size_t)(space - t)) : t, *rest = space ? trim(space + 1) : "";
        if (!strcmp(first, "ifeq") || !strcmp(first, "ifneq") || !strcmp(first, "ifdef") || !strcmp(first, "ifndef") || !strcmp(first, "else") || !strcmp(first, "endif")) {
            conditional(first, rest, number, conditions, &condition_count);
            continue;
        }
        if (!*t || !active(conditions, condition_count)) continue;
        Positions positions = outside(t);
        int equal = positions.equal, colon = positions.colon;
        if (equal >= 0 && (colon < 0 || colon >= equal - 1)) {
            char op = equal > 0 && strchr(":+?", t[equal - 1]) ? t[equal - 1] : '=';
            char *name = trim(part(t, (size_t)(equal - (op == '=' ? 0 : 1)))), *rhs = trim(t + equal + 1);
            if (!*name) expansion_error("empty variable name");
            Variable *old = find_variable(name);
            if (op == ':') set_variable(name, true, expand(rhs));
            else if (op == '+' && old) {
                char *add = old->simple ? expand(rhs) : rhs;
                set_variable(name, old->simple, *old->value ? format("%s %s", old->value, add) : add);
            } else if (op != '?' || !old) set_variable(name, false, rhs);
            current = NULL;
        } else if (colon >= 0) {
            Strings expanded = words(expand(part(t, (size_t)colon))), targets = {0};
            for (int j = 0; j < expanded.count; j++) add_unique(&targets, expanded.items[j], &temporary);
            char *r = t + colon + 1, *inline_recipe = NULL, *target_pattern = NULL;
            int semicolon = outside(r).semicolon;
            if (semicolon >= 0) {
                inline_recipe = left_trim(r + semicolon + 1);
                r = part(r, (size_t)semicolon);
            }
            int static_colon = outside(r).colon;
            if (static_colon >= 0) {
                target_pattern = trim(expand(part(r, (size_t)static_colon)));
                r += static_colon + 1;
            }
            Strings prerequisites = words(expand(r));
            current = memory(&temporary, sizeof *current);
            if (targets.count == 1 && !strcmp(targets.items[0], ".PHONY")) {
                for (int j = 0; j < prerequisites.count; j++) if (!contains(&phony, prerequisites.items[j])) add_string(&phony, copy(&makefile_memory, prerequisites.items[j]), &makefile_memory);
            } else if (target_pattern) {
                if (!strchr(target_pattern, '%')) expansion_error("target pattern contains no '%'");
                for (int j = 0; j < targets.count; j++) {
                    char *s = stem(target_pattern, targets.items[j]);
                    if (!s || !*s) printf("%s: target '%s' doesn't match the target pattern\n", location, targets.items[j]);
                    else {
                        Strings p = {0};
                        for (int k = 0; k < prerequisites.count; k++) add_string(&p, substitute(prerequisites.items[k], s), &temporary);
                        Rule *rule = register_rule(targets.items[j], &p);
                        rule->stem = copy(&makefile_memory, s);
                        group_add(current, rule);
                    }
                }
            } else {
                bool has_pattern = false, has_normal = false;
                for (int j = 0; j < targets.count; j++) {
                    if (strchr(targets.items[j], '%')) has_pattern = true;
                    else has_normal = true;
                }
                if (has_pattern && has_normal) expansion_error("mixed implicit and normal rules");
                for (int j = 0; j < targets.count; j++) {
                    Rule *rule;
                    if (has_pattern) {
                        rule = memory(&makefile_memory, sizeof *rule);
                        rule->name = copy(&makefile_memory, targets.items[j]);
                        rule->pattern = true;
                        rule->stem = "";
                        for (int k = 0; k < prerequisites.count; k++) add_string(&rule->prerequisites, copy(&makefile_memory, prerequisites.items[k]), &makefile_memory);
                        if (pattern_tail) pattern_tail->next = rule;
                        else patterns = rule;
                        pattern_tail = rule;
                    } else rule = register_rule(targets.items[j], &prerequisites);
                    group_add(current, rule);
                }
            }
            if (inline_recipe) add_recipe(current, number, inline_recipe);
        } else if (*trim(expand(t))) expansion_error("missing separator");
    }
    if (condition_count) {
        location = format("Makefile:%d", conditions[condition_count - 1].line);
        expansion_error("missing 'endif'");
    }
    int pattern_count = 0;
    for (Rule *r = patterns; r; r = r->next) pattern_count += r->recipe != NULL;
    loaded = true;
    printf("Makefile loaded: lines=%d variables=%d targets=%d patterns=%d goal=%s\n", body->count, variable_count, target_count, pattern_count, default_goal ? default_goal : "(none)");
}

typedef struct {
    Strings prerequisites;
    Recipe *recipe;
    char *stem;
    bool source, missing;
} Choice;

static Choice determine(const char *target) {
    Rule *explicit = find_rule(target);
    Choice choice = {0};
    choice.stem = "";
    if (explicit && explicit->recipe) {
        choice.prerequisites = explicit->prerequisites;
        choice.recipe = explicit->recipe;
        choice.stem = explicit->stem;
        return choice;
    }
    if (!contains(&phony, target)) {
        Rule *best = NULL;
        char *best_stem = NULL;
        for (Rule *r = patterns; r; r = r->next) if (r->recipe) {
            char *s = stem(r->name, target);
            if (!s || !*s || (best_stem && strlen(s) >= strlen(best_stem))) continue;
            bool usable = true;
            for (int i = 0; i < r->prerequisites.count; i++) {
                char *name = substitute(r->prerequisites.items[i], s);
                if (file_index(name) < 0 && !find_rule(name)) {
                    usable = false;
                    break;
                }
            }
            if (usable) {
                best = r;
                best_stem = s;
            }
        }
        if (best) {
            for (int i = 0; i < best->prerequisites.count; i++) add_unique(&choice.prerequisites, substitute(best->prerequisites.items[i], best_stem), &temporary);
            if (explicit) for (int i = 0; i < explicit->prerequisites.count; i++) add_unique(&choice.prerequisites, explicit->prerequisites.items[i], &temporary);
            choice.recipe = best->recipe;
            choice.stem = best_stem;
            return choice;
        }
    }
    if (explicit || contains(&phony, target)) {
        if (explicit) {
            choice.prerequisites = explicit->prerequisites;
            choice.stem = explicit->stem;
        }
        return choice;
    }
    if (file_index(target) >= 0) choice.source = true;
    else choice.missing = true;
    return choice;
}

static int target_time(const char *target) {
    int i = file_index(target);
    return contains(&phony, target) || i < 0 ? -1 : files[i].time;
}

static int execute(const char *command) {
    Strings w = words(command);
    char *c = w.items[0];
    if (!strcmp(c, "echo")) {
        Strings rest = {w.items + 1, w.count - 1, w.count - 1};
        puts(join(&rest));
        return 0;
    }
    if (!strcmp(c, "touch")) {
        for (int i = 1; i < w.count; i++) new_time(w.items[i]);
        return 0;
    }
    if (!strcmp(c, "rm")) {
        bool forced = w.count > 1 && !strcmp(w.items[1], "-f");
        int status = 0;
        for (int i = forced ? 2 : 1; i < w.count; i++) {
            Strings names = wildcard_expansion(w.items[i]);
            if (!names.count) add_string(&names, w.items[i], &temporary);
            for (int j = 0; j < names.count; j++) if (!remove_file(names.items[j]) && !forced) {
                printf("rm: cannot remove '%s': No such file or directory\n", names.items[j]);
                status = 1;
            }
        }
        return status;
    }
    if (!strcmp(c, "false")) return 1;
    if (!strcmp(c, "exit")) return w.count > 1 ? atoi(w.items[1]) : 0;
    return 0;
}

typedef struct Result {
    char *name;
    int status;
    Choice choice;
    struct Result *next;
} Result;

typedef struct Building {
    const char *name;
    struct Building *previous;
} Building;

typedef struct {
    bool options[128];
    int runs;
    Result *results;
    Building *building;
} Build;

static bool being_built(Build *b, const char *name) {
    for (Building *p = b->building; p; p = p->previous) if (!strcmp(p->name, name)) return true;
    return false;
}

static Result *find_result(Build *b, const char *name) {
    for (Result *r = b->results; r; r = r->next) if (!strcmp(r->name, name)) return r;
    return NULL;
}

static int update_target(Build *build, const char *target, Choice *choice) {
    int old = target_time(target);
    Strings fresh = {0};
    for (int i = 0; i < choice->prerequisites.count; i++) {
        char *p = choice->prerequisites.items[i];
        int time = target_time(p);
        if (build->options['B'] || old < 0 || time < 0 || time > old) add_string(&fresh, p, &temporary);
    }
    if (!choice->recipe || (!build->options['B'] && old >= 0 && !fresh.count)) return 0;
    build->runs++;
    RecipeLine *first = NULL, *last = NULL;
    has_automatic = true;
    automatic[0] = (char *)target;
    automatic[1] = choice->prerequisites.count ? choice->prerequisites.items[0] : "";
    automatic[2] = join(&choice->prerequisites);
    automatic[3] = join(&fresh);
    automatic[4] = choice->stem;
    for (RecipeLine *line = choice->recipe->first; line; line = line->next) {
        location = format("Makefile:%d", line->number);
        RecipeLine *expanded = memory(&temporary, sizeof *expanded);
        expanded->number = line->number;
        expanded->text = expand(line->text);
        if (last) last->next = expanded;
        else first = expanded;
        last = expanded;
    }
    has_automatic = false;
    for (RecipeLine *line = first; line; line = line->next) {
        int i = 0;
        bool silent = false, ignore = false;
        while (line->text[i] && strchr(" @-", line->text[i])) {
            silent |= line->text[i] == '@';
            ignore |= line->text[i] == '-';
            i++;
        }
        char *command = right_trim(line->text + i);
        if (!*command) continue;
        if (build->options['n'] || (!silent && !build->options['s'])) puts(command);
        if (build->options['n']) continue;
        int status = execute(command);
        if (status) {
            if (ignore || build->options['i']) printf("make: [Makefile:%d: %s] Error %d (ignored)\n", line->number, target, status);
            else {
                printf("make: *** [Makefile:%d: %s] Error %d\n", line->number, target, status);
                if (!build->options['k']) longjmp(command_error, 2);
                return 1;
            }
        }
    }
    if (!contains(&phony, target)) new_time(target);
    return 0;
}

static int build_target(Build *build, const char *target, const char *parent) {
    Result *result = find_result(build, target);
    if (result && result->status >= 0) return result->status;
    if (!result) {
        result = memory(&temporary, sizeof *result);
        result->name = (char *)target;
        result->status = -1;
        result->next = build->results;
        build->results = result;
    }
    result->choice = determine(target);
    Choice *choice = &result->choice;
    if (choice->missing) {
        result->status = 1;
        printf("make: *** No rule to make target '%s'", target);
        if (parent) printf(", needed by '%s'.", parent);
        else putchar('.');
        puts(build->options['k'] ? "" : "  Stop.");
        if (!build->options['k']) longjmp(command_error, 2);
        return 1;
    }
    if (choice->source) return result->status = 0;
    Building building = {target, build->building};
    build->building = &building;
    bool failed = false;
    Strings kept = {0};
    for (int i = 0; i < choice->prerequisites.count; i++) {
        char *p = choice->prerequisites.items[i];
        if (being_built(build, p)) printf("make: Circular %s <- %s dependency dropped.\n", target, p);
        else {
            add_string(&kept, p, &temporary);
            if (build_target(build, p, target) != 0) failed = true;
        }
    }
    choice->prerequisites = kept;
    build->building = building.previous;
    return result->status = failed ? 2 : update_target(build, target, choice);
}

static void make(const char *args) {
    Strings w = words(args), goals = {0};
    Build build = {0};
    for (int i = 0; i < w.count; i++) {
        char *word = w.items[i];
        if (*word == '-') for (int j = 1; word[j]; j++) {
            if (!strchr("nBkis", word[j])) {
                printf("make: invalid option -- '%c'\n", word[j]);
                return;
            }
            build.options[(unsigned char)word[j]] = true;
        } else add_string(&goals, word, &temporary);
    }
    if (!goals.count) {
        if (!loaded) {
            puts("make: *** No targets specified and no makefile found.  Stop.");
            return;
        }
        if (!default_goal) {
            puts("make: *** No targets.  Stop.");
            return;
        }
        add_string(&goals, default_goal, &temporary);
    }
    if (build.options['n']) {
        saved_files = malloc((size_t)(file_count ? file_count : 1) * sizeof *saved_files);
        if (!saved_files) exit(EXIT_FAILURE);
        if (file_count) memcpy(saved_files, files, (size_t)file_count * sizeof *files);
        saved_count = file_count;
        saved_clock = clock_value;
        dry_saved = true;
    }
    for (int i = 0; i < goals.count; i++) {
        char *name = goals.items[i];
        int previous = build.runs, result = build_target(&build, name, NULL);
        if (result == 0 && previous == build.runs) {
            if (contains(&phony, name) || !find_result(&build, name)->choice.recipe) printf("make: Nothing to be done for '%s'.\n", name);
            else printf("make: '%s' is up to date.\n", name);
        } else if (result == 2) printf("make: Target '%s' not remade because of errors.\n", name);
    }
}

static void show_rule(Rule *rule) {
    printf("%s:", rule->name);
    for (int i = 0; i < rule->prerequisites.count; i++) printf(" %s", rule->prerequisites.items[i]);
    putchar('\n');
    if (rule->recipe) for (RecipeLine *line = rule->recipe->first; line; line = line->next) printf(">%s\n", line->text);
}

static void command(const char *line, const Strings *body) {
    printf("$ %s\n", line);
    const char *space = strchr(line, ' ');
    char *c = space ? part(line, (size_t)(space - line)) : (char *)line;
    const char *rest = space ? space + 1 : "";
    int status = setjmp(command_error);
    if (status == 0) {
        if (!strcmp(c, "MAKEFILE")) load(body);
        else if (!strcmp(c, "MAKE")) make(rest);
        else if (!strcmp(c, "TOUCH")) {
            Strings names = words(rest);
            for (int i = 0; i < names.count; i++) new_time(names.items[i]);
        } else if (!strcmp(c, "RM")) {
            Strings names = words(rest);
            for (int i = 0; i < names.count; i++) if (!remove_file(names.items[i])) printf("rm: cannot remove '%s': No such file or directory\n", names.items[i]);
        } else if (!strcmp(c, "FILES")) {
            printf("clock %d\n", clock_value);
            for (int i = 0; i < file_count; i++) printf("%s %d\n", files[i].name, files[i].time);
        } else if (!strcmp(c, "VARS")) {
            if (loaded) for (Variable *v = variables; v; v = v->next) {
                char *s = trim(value(v->name));
                printf("%s %s%s%s\n", v->name, v->simple ? ":=" : "=", *s ? " " : "", s);
            }
        } else if (!strcmp(c, "RULES")) {
            if (loaded) {
                for (Rule *r = rules; r; r = r->next) show_rule(r);
                for (Rule *r = patterns; r; r = r->next) if (r->recipe) show_rule(r);
                if (phony.count) {
                    Strings names = sorted(&phony);
                    printf(".PHONY: %s\n", join(&names));
                }
            }
        } else if (!strcmp(c, "EXPAND")) {
            char *text = expand(rest);
            printf("[%s]\n", text);
        }
    } else if (!strcmp(c, "MAKEFILE")) discard();
    if (dry_saved) {
        free(files);
        files = saved_files;
        file_count = saved_count;
        file_capacity = saved_count;
        clock_value = saved_clock;
        saved_files = NULL;
        dry_saved = false;
    }
    clean_expansion();
}

static char *read_line(void) {
    size_t length = 0, capacity = 128;
    char *line = malloc(capacity);
    int ch;
    if (!line) exit(EXIT_FAILURE);
    while ((ch = getchar()) != EOF && ch != '\n') {
        if (length + 1 == capacity) {
            capacity *= 2;
            char *p = realloc(line, capacity);
            if (!p) exit(EXIT_FAILURE);
            line = p;
        }
        line[length++] = (char)ch;
    }
    line[length] = '\0';
    return line;
}

int main(void) {
    char *line = read_line();
    free(line);
    for (;;) {
        line = read_line();
        if (!strcmp(line, "END FILES")) {
            free(line);
            break;
        }
        char *space = strchr(line, ' ');
        *space = '\0';
        int time = atoi(space + 1);
        put_file(line, time);
        if (time > clock_value) clock_value = time;
        free(line);
    }
    for (;;) {
        line = read_line();
        if (!strcmp(line, "QUIT")) {
            free(line);
            break;
        }
        Strings body = {0};
        if (!strcmp(line, "MAKEFILE")) for (;;) {
            char *row = read_line();
            if (!strcmp(row, "END MAKEFILE")) {
                free(row);
                break;
            }
            add_string(&body, copy(&temporary, row), &temporary);
            free(row);
        }
        command(line, &body);
        free(line);
        clear_arena(&temporary);
    }
    free(files);
    clear_arena(&temporary);
    clear_arena(&makefile_memory);
    clear_arena(&permanent);
    return 0;
}
