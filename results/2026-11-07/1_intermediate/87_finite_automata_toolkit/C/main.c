#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>

#define MAX_STATES 200
#define SET_WORDS 4
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *permanent, *temporary;

static void *take(Allocation **arena, size_t size) {
    Allocation *a = malloc(sizeof *a);
    void *p = calloc(1, size ? size : 1);
    if (!a || !p) exit(EXIT_FAILURE);
    *a = (Allocation){p, *arena};
    *arena = a;
    return p;
}

static void *allocate(size_t size) {
    return take(&temporary, size);
}

static void *persist(size_t size) {
    return take(&permanent, size);
}

static void clear(Allocation **arena) {
    while (*arena) {
        Allocation *next = (*arena)->next;
        free((*arena)->pointer);
        free(*arena);
        *arena = next;
    }
}

static char *part(const char *s, size_t n) {
    char *out = allocate(n + 1);
    memcpy(out, s, n);
    return out;
}

static bool equal(const char *a, const char *b) {
    return strcmp(a, b) == 0;
}

static bool listed(const char *s, const char *list) {
    size_t length = strlen(s);
    for (const char *p = list; *p;) {
        const char *end = strchr(p, ' ');
        size_t n = end ? (size_t)(end - p) : strlen(p);
        if (length == n && !memcmp(p, s, n)) return true;
        if (!end) break;
        p = end + 1;
    }
    return false;
}
static jmp_buf command_error;

static void fail(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    fputs("error: ", stdout);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    longjmp(command_error, 1);
}
typedef struct {
    char *text;
    size_t length, capacity;
} Buffer;

static void append(Buffer *b, const char *text) {
    size_t n = strlen(text);
    if (b->length + n + 1 > b->capacity) {
        size_t capacity = b->capacity ? b->capacity : 64;
        while (capacity < b->length + n + 1) capacity *= 2;
        char *p = realloc(b->text, capacity);
        if (!p) exit(EXIT_FAILURE);
        b->text = p;
        b->capacity = capacity;
    }
    memcpy(b->text + b->length, text, n + 1);
    b->length += n;
}

static void append_char(Buffer *b, char c) {
    char text[2] = {c, '\0'};
    append(b, text);
}

static char *finish(Buffer *b) {
    char *out = part(b->text ? b->text : "", b->length);
    free(b->text);
    return out;
}

static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)n + 1);
    vsnprintf(out, (size_t)n + 1, pattern, args);
    va_end(args);
    return out;
}
typedef struct {
    const char **items;
    int count, capacity;
} Lines;

static void add_line(Lines *lines, const char *line) {
    if (lines->count == lines->capacity) {
        int next = lines->capacity ? lines->capacity * 2 : 8;
        const char **items = allocate((size_t)next * sizeof(char *));
        if (lines->count) memcpy(items, lines->items, (size_t)lines->count * sizeof(char *));
        lines->items = items;
        lines->capacity = next;
    }
    lines->items[lines->count++] = line;
}
typedef struct {
    uint64_t words[SET_WORDS];
} Set;

static bool has(Set s, int i) {
    return !!(s.words[i / 64] & (UINT64_C(1) << (i % 64)));
}

static bool insert(Set *s, int i) {
    bool old = has(*s, i);
    s->words[i / 64] |= UINT64_C(1) << (i % 64);
    return !old;
}

static Set singleton(int i) {
    Set s = {
        {0}
    };
    insert(&s, i);
    return s;
}

static void unite(Set *a, Set b) {
    for (int i = 0; i < SET_WORDS; i++) a->words[i] |= b.words[i];
}

static bool intersects(Set a, Set b) {
    for (int i = 0; i < SET_WORDS; i++) if (a.words[i] & b.words[i]) return true;
    return false;
}

static bool same_set(Set a, Set b) {
    for (int i = 0; i < SET_WORDS; i++) if (a.words[i] != b.words[i]) return false;
    return true;
}

static int set_count(Set s) {
    int count = 0;
    for (int i = 0; i < SET_WORDS; i++) {
        uint64_t v = s.words[i];
        while (v) {
            v &= v - 1;
            count++;
        }
    }
    return count;
}

static int first(Set s) {
    for (int i = 0; i < MAX_STATES; i++) if (has(s, i)) return i;
    return -1;
}
typedef struct {
    bool dfa;
    char alphabet[11], states[MAX_STATES][9];
    int symbols, count, start;
    Set accepting, transitions[MAX_STATES][11];
} Automaton;

static int character_compare(const void *a, const void *b) {
    return (unsigned char)*(const char *)a - (unsigned char)*(const char *)b;
}

static Automaton *automaton(bool dfa, const char *alphabet) {
    Automaton *a = allocate(sizeof *a);
    a->dfa = dfa;
    strcpy(a->alphabet, alphabet);
    a->symbols = (int)strlen(alphabet);
    qsort(a->alphabet, (size_t)a->symbols, sizeof(char), character_compare);
    return a;
}

static int add_state(Automaton *a, const char *name) {
    int id = a->count++;
    strcpy(a->states[id], name);
    return id;
}

static void series(Automaton *a, char prefix, int count) {
    for (int i = 0; i < count; i++) {
        char name[9];
        snprintf(name, sizeof name, "%c%d", prefix, i);
        add_state(a, name);
    }
}

static void edge(Automaton *a, int p, int c, int q) {
    insert(&a->transitions[p][c], q);
}

static int delta(const Automaton *a, int p, int c) {
    return first(a->transitions[p][c]);
}

static int state_index(const Automaton *a, const char *name) {
    for (int i = 0; i < a->count; i++) if (equal(a->states[i], name)) return i;
    return -1;
}

static int symbol_index(const Automaton *a, char c) {
    const char *p = strchr(a->alphabet, c);
    return p ? (int)(p - a->alphabet) : -1;
}

static int transition_count(const Automaton *a) {
    int count = 0;
    for (int p = 0; p < a->count; p++) for (int c = 0; c <= a->symbols; c++) count += set_count(a->transitions[p][c]);
    return count;
}

static int epsilon_count(const Automaton *a) {
    int count = 0;
    for (int p = 0; p < a->count; p++) count += set_count(a->transitions[p][a->symbols]);
    return count;
}

static char *summary(const Automaton *a, const char *name) {
    return format("%s %s: alphabet=%s states=%d accepting=%d transitions=%d", a->dfa ? "DFA" : "NFA", name, a->alphabet, a->count, set_count(a->accepting), transition_count(a));
}

static char *set_text(const Automaton *a, Set s) {
    Buffer b = {0};
    append(&b, "{");
    bool initial = true;
    for (int i = 0; i < a->count; i++) if (has(s, i)) {
        if (!initial) append(&b, ",");
        append(&b, a->states[i]);
        initial = false;
    }
    append(&b, "}");
    return finish(&b);
}

static char *list_text(const Automaton *a, Set s) {
    if (!set_count(s)) return "none";
    char *text = set_text(a, s);
    return part(text + 1, strlen(text) - 2);
}

static Set closure(const Automaton *a, Set s) {
    int queue[MAX_STATES], count = 0;
    for (int i = 0; i < a->count; i++) if (has(s, i)) queue[count++] = i;
    for (int at = 0; at < count; at++) {
        Set edges = a->transitions[queue[at]][a->symbols];
        for (int q = 0; q < a->count; q++) if (has(edges, q) && insert(&s, q)) queue[count++] = q;
    }
    return s;
}

static Set initial(const Automaton *a) {
    return closure(a, singleton(a->start));
}

static Set move(const Automaton *a, Set s, int c) {
    Set out = {
        {0}
    };
    for (int p = 0; p < a->count; p++) if (has(s, p)) unite(&out, a->transitions[p][c]);
    return closure(a, out);
}

static Set graph_reach(const Automaton *a, bool reverse) {
    Set out = reverse ? a->accepting : singleton(a->start);
    bool changed;
    do {
        int before = set_count(out);
        for (int p = 0; p < a->count; p++) for (int c = 0; c <= a->symbols; c++) {
            if (reverse) {
                if (intersects(a->transitions[p][c], out)) insert(&out, p);
            } else if (has(out, p)) unite(&out, a->transitions[p][c]);
        }
        changed = before != set_count(out);
    } while (changed);
    return out;
}
typedef struct {
    char name[9];
    Automaton *automaton;
} Entry;
static Entry *entries;
static int entry_count, entry_capacity;

static int find(const char *name) {
    for (int i = 0; i < entry_count; i++) if (equal(entries[i].name, name)) return i;
    return -1;
}

static Automaton *get(const char *name) {
    int at = find(name);
    if (at < 0) fail("unknown automaton %s", name);
    return entries[at].automaton;
}

static void register_automaton(const char *name, Automaton *a, Lines details) {
    if (entry_count == entry_capacity) {
        int next = entry_capacity ? entry_capacity * 2 : 8;
        Entry *items = persist((size_t)next * sizeof(Entry));
        if (entry_count) memcpy(items, entries, (size_t)entry_count * sizeof(Entry));
        entries = items;
        entry_capacity = next;
    }
    Automaton *stored = persist(sizeof *stored);
    *stored = *a;
    Entry *entry = &entries[entry_count++];
    strcpy(entry->name, name);
    entry->automaton = stored;
    puts(summary(a, name));
    for (int i = 0; i < details.count; i++) puts(details.items[i]);
}

static Automaton *determinize(const Automaton *a, Lines *details) {
    Automaton *d = automaton(true, a->alphabet);
    Set sets[MAX_STATES];
    int count = 1;
    sets[0] = initial(a);
    add_state(d, "D0");
    for (int i = 0; i < count; i++) {
        if (intersects(sets[i], a->accepting)) insert(&d->accepting, i);
        if (details) add_line(details, format("  D%d = %s", i, set_text(a, sets[i])));
        for (int c = 0; c < a->symbols; c++) {
            Set next = move(a, sets[i], c);
            int id = -1;
            for (int j = 0; j < count; j++) if (same_set(sets[j], next)) {
                id = j;
                break;
            }
            if (id < 0) {
                id = count;
                sets[count++] = next;
                add_state(d, format("D%d", id));
            }
            edge(d, i, c, id);
        }
    }
    return d;
}
typedef struct {
    Set blocks[MAX_STATES];
    int which[MAX_STATES], count;
} Partition;

static void index_partition(Partition *p, int count) {
    for (int i = 0; i < count; i++) p->which[i] = -1;
    for (int i = 0; i < p->count; i++) for (int s = 0; s < count; s++) if (has(p->blocks[i], s)) p->which[s] = i;
}

static char *partition_text(const Automaton *a, const Partition *p) {
    Buffer b = {0};
    for (int i = 0; i < p->count; i++) {
        if (i) append(&b, " ");
        append(&b, set_text(a, p->blocks[i]));
    }
    return finish(&b);
}

static Automaton *minimize(const Automaton *a, Lines *details) {
    Set reached = graph_reach(a, false), missing = {
        {0}
    };
    for (int p = 0; p < a->count; p++) if (!has(reached, p)) insert(&missing, p);
    if (details) add_line(details, format("  unreachable: %s", list_text(a, missing)));
    Partition current = {0};
    for (int p = 0; p < a->count; p++) if (has(reached, p)) {
        int id = -1;
        for (int i = 0; i < current.count; i++) if (has(a->accepting, first(current.blocks[i])) == has(a->accepting, p)) {
            id = i;
            break;
        }
        if (id < 0) id = current.count++;
        insert(&current.blocks[id], p);
    }
    index_partition(&current, a->count);
    int round = 0;
    if (details) add_line(details, format("  round 0: %s", partition_text(a, &current)));
    while (true) {
        Partition next = {0};
        for (int p = 0; p < a->count; p++) if (has(reached, p)) {
            int id = -1;
            for (int i = 0; i < next.count; i++) {
                int q = first(next.blocks[i]);
                if (current.which[p] != current.which[q]) continue;
                bool same = true;
                for (int c = 0; c < a->symbols; c++) if (current.which[delta(a, p, c)] != current.which[delta(a, q, c)]) {
                    same = false;
                    break;
                }
                if (same) {
                    id = i;
                    break;
                }
            }
            if (id < 0) id = next.count++;
            insert(&next.blocks[id], p);
        }
        if (next.count == current.count) break;
        current = next;
        index_partition(&current, a->count);
        if (details) add_line(details, format("  round %d: %s", ++round, partition_text(a, &current)));
    }
    Automaton *m = automaton(true, a->alphabet);
    int ids[MAX_STATES], queue[MAX_STATES], count = 1;
    for (int i = 0; i < current.count; i++) ids[i] = -1;
    queue[0] = current.which[a->start];
    ids[queue[0]] = 0;
    add_state(m, "M0");
    for (int i = 0; i < count; i++) {
        Set block = current.blocks[queue[i]];
        int p = first(block);
        if (has(a->accepting, p)) insert(&m->accepting, i);
        if (details) add_line(details, format("  M%d = %s", i, set_text(a, block)));
        for (int c = 0; c < a->symbols; c++) {
            int b = current.which[delta(a, p, c)];
            if (ids[b] < 0) {
                ids[b] = count;
                queue[count++] = b;
                add_state(m, format("M%d", ids[b]));
            }
            edge(m, i, c, ids[b]);
        }
    }
    return m;
}

static void copy_edges(const Automaton *source, Automaton *target, int offset, bool reverse) {
    for (int p = 0; p < source->count; p++) for (int c = 0; c <= source->symbols; c++) for (int q = 0; q < source->count; q++) if (has(source->transitions[p][c], q)) edge(target, (reverse ? q : p) + offset, c, (reverse ? p : q) + offset);
}

static Automaton *epsilon_free(const Automaton *a) {
    Automaton *n = automaton(false, a->alphabet);
    for (int p = 0; p < a->count; p++) add_state(n, a->states[p]);
    n->start = a->start;
    for (int p = 0; p < a->count; p++) {
        Set set = closure(a, singleton(p));
        if (intersects(set, a->accepting)) insert(&n->accepting, p);
        for (int c = 0; c < a->symbols; c++) n->transitions[p][c] = move(a, set, c);
    }
    return n;
}

static Automaton *unary_construction(const Automaton *a, const char *command) {
    if (equal(command, "COMPLEMENT")) {
        Automaton *n = allocate(sizeof *n);
        *n = *a;
        n->accepting = (Set) {
            {0}
        };
        for (int p = 0; p < a->count; p++) if (!has(a->accepting, p)) insert(&n->accepting, p);
        return n;
    }
    Automaton *n = automaton(false, a->alphabet);
    series(n, 'N', a->count + 1);
    copy_edges(a, n, 1, equal(command, "REVERSE"));
    if (equal(command, "REVERSE")) {
        insert(&n->accepting, a->start + 1);
        for (int p = 0; p < a->count; p++) if (has(a->accepting, p)) edge(n, 0, a->symbols, p + 1);
    } else {
        insert(&n->accepting, 0);
        edge(n, 0, a->symbols, a->start + 1);
        for (int p = 0; p < a->count; p++) if (has(a->accepting, p)) {
            insert(&n->accepting, p + 1);
            edge(n, p + 1, a->symbols, a->start + 1);
        }
    }
    return n;
}

static Automaton *concatenate(const Automaton *a, const Automaton *b) {
    Automaton *n = automaton(false, a->alphabet);
    int offset = a->count;
    series(n, 'N', offset + b->count);
    n->start = a->start;
    copy_edges(a, n, 0, false);
    copy_edges(b, n, offset, false);
    for (int p = 0; p < a->count; p++) if (has(a->accepting, p)) edge(n, p, a->symbols, offset + b->start);
    for (int p = 0; p < b->count; p++) if (has(b->accepting, p)) insert(&n->accepting, offset + p);
    return n;
}
typedef struct {
    int a, b;
} Pair;

static Automaton *product(const Automaton *a, const Automaton *b, const char *command, Lines *details) {
    Automaton *p = automaton(true, a->alphabet);
    Pair pairs[MAX_STATES] = {
        {a->start, b->start}
    };
    int count = 1;
    add_state(p, "P0");
    for (int i = 0; i < count; i++) {
        Pair pair = pairs[i];
        bool x = has(a->accepting, pair.a), y = has(b->accepting, pair.b);
        if (equal(command, "UNION") ? x || y : equal(command, "INTERSECT") ? x && y : x && !y) insert(&p->accepting, i);
        add_line(details, format("  P%d = (%s,%s)", i, a->states[pair.a], b->states[pair.b]));
        for (int c = 0; c < a->symbols; c++) {
            Pair next = {delta(a, pair.a, c), delta(b, pair.b, c)};
            int id = -1;
            for (int j = 0; j < count; j++) if (pairs[j].a == next.a && pairs[j].b == next.b) {
                id = j;
                break;
            }
            if (id < 0) {
                id = count;
                pairs[count++] = next;
                add_state(p, format("P%d", id));
            }
            edge(p, i, c, id);
        }
    }
    return p;
}
typedef struct {
    int a, b, parent;
    char incoming;
} Search;

static char *word(const Search *queue, int at) {
    int length = 0;
    for (int p = at; queue[p].parent >= 0; p = queue[p].parent) length++;
    char *out = allocate((size_t)length + 1);
    for (int i = length - 1; i >= 0; i--) {
        out[i] = queue[at].incoming;
        at = queue[at].parent;
    }
    return out;
}

static const char *visible(const char *text) {
    return *text ? text : "e";
}

static char *equivalent(const Automaton *x, const Automaton *z, const char *xname, const char *zname) {
    Automaton *a = determinize(x, NULL), *b = determinize(z, NULL);
    int maximum = a->count * b->count;
    Search *queue = allocate((size_t)maximum * sizeof(Search));
    int *ids = allocate((size_t)maximum * sizeof(int));
    for (int i = 0; i < maximum; i++) ids[i] = -1;
    queue[0] = (Search){a->start, b->start, -1, ' '};
    ids[a->start * b->count + b->start] = 0;
    int count = 1;
    for (int i = 0; i < count; i++) {
        Search pair = queue[i];
        bool accepted = has(a->accepting, pair.a);
        if (accepted != has(b->accepting, pair.b)) return format("NOT EQUIVALENT: %s is accepted only by %s", visible(word(queue, i)), accepted ? xname : zname);
        for (int c = 0; c < a->symbols; c++) {
            int p = delta(a, pair.a, c), q = delta(b, pair.b, c), key = p * b->count + q;
            if (ids[key] < 0) {
                ids[key] = count;
                queue[count++] = (Search){p, q, i, a->alphabet[c]};
            }
        }
    }
    return "EQUIVALENT";
}

static char *smallest(const Automaton *d) {
    Search queue[MAX_STATES] = {
        {d->start, 0, -1, ' '}
    };
    bool seen[MAX_STATES] = {false};
    seen[d->start] = true;
    int count = 1;
    for (int i = 0; i < count; i++) {
        int p = queue[i].a;
        if (has(d->accepting, p)) return word(queue, i);
        for (int c = 0; c < d->symbols; c++) {
            int q = delta(d, p, c);
            if (!seen[q]) {
                seen[q] = true;
                queue[count++] = (Search){q, 0, i, d->alphabet[c]};
            }
        }
    }
    return NULL;
}
typedef enum { EMPTY_LANGUAGE, FINITE_LANGUAGE, INFINITE_LANGUAGE } Language;

static Language classify(const Automaton *d, long long *total) {
    Set reached = graph_reach(d, false), live = graph_reach(d, true);
    for (int i = 0; i < SET_WORDS; i++) live.words[i] &= reached.words[i];
    if (!has(live, d->start)) {
        if (total) *total = 0;
        return EMPTY_LANGUAGE;
    }
    int indegree[MAX_STATES] = {0}, order[MAX_STATES], count = 0;
    for (int p = 0; p < d->count; p++) if (has(live, p)) for (int c = 0; c < d->symbols; c++) {
        int q = delta(d, p, c);
        if (has(live, q)) indegree[q]++;
    }
    for (int p = 0; p < d->count; p++) if (has(live, p) && !indegree[p]) order[count++] = p;
    for (int i = 0; i < count; i++) for (int c = 0; c < d->symbols; c++) {
        int q = delta(d, order[i], c);
        if (has(live, q) && --indegree[q] == 0) order[count++] = q;
    }
    if (count != set_count(live)) return INFINITE_LANGUAGE;
    if (total) {
        long long values[MAX_STATES] = {0};
        for (int i = count - 1; i >= 0; i--) {
            int p = order[i];
            values[p] = has(d->accepting, p);
            for (int c = 0; c < d->symbols; c++) values[p] += values[delta(d, p, c)];
        }
        *total = values[d->start];
    }
    return FINITE_LANGUAGE;
}

static long long count_words(const Automaton *d, int length) {
    long long values[MAX_STATES] = {0};
    values[d->start] = 1;
    for (int i = 0; i < length; i++) {
        long long next[MAX_STATES] = {0};
        for (int p = 0; p < d->count; p++) for (int c = 0; c < d->symbols; c++) next[delta(d, p, c)] += values[p];
        memcpy(values, next, sizeof values);
    }
    long long total = 0;
    for (int p = 0; p < d->count; p++) if (has(d->accepting, p)) total += values[p];
    return total;
}
typedef struct {
    char text[31];
    int state;
} Enumeration;

static char *enumerate(const Automaton *d, int maximum) {
    Enumeration *level = allocate(sizeof(Enumeration));
    level[0].state = d->start;
    int count = 1, first_count = 0;
    const char *first_words[50];
    long long total = 0;
    for (int length = 0; length <= maximum; length++) {
        Enumeration *next = length < maximum ? allocate((size_t)count * (size_t)d->symbols * sizeof(Enumeration)) : NULL;
        int next_count = 0;
        for (int i = 0; i < count; i++) {
            Enumeration item = level[i];
            if (has(d->accepting, item.state)) {
                total++;
                if (first_count < 50) first_words[first_count++] = *item.text ? part(item.text, (size_t)length) : "e";
            }
            if (length < maximum) for (int c = 0; c < d->symbols; c++) {
                Enumeration *entry = &next[next_count++];
                memcpy(entry->text, item.text, (size_t)length);
                entry->text[length] = d->alphabet[c];
                entry->state = delta(d, item.state, c);
            }
        }
        level = next;
        count = next_count;
    }
    Buffer out = {0};
    append(&out, format("%lld", total));
    for (int i = 0; i < first_count; i++) {
        append(&out, " ");
        append(&out, first_words[i]);
    }
    if (total > 50) append(&out, " ...");
    return finish(&out);
}

static char *synchronize(const Automaton *d) {
    unsigned start = (1u << d->count) - 1;
    int ids[1024], count = 1;
    for (int i = 0; i < 1024; i++) ids[i] = -1;
    Search queue[1024] = {
        {(int)start, 0, -1, ' '}
    };
    ids[start] = 0;
    for (int i = 0; i < count; i++) {
        unsigned set = (unsigned)queue[i].a;
        if (!(set & (set - 1))) {
            int p = 0;
            while (!(set & 1u << p)) p++;
            return format("SYNCHRONIZING %s -> %s", visible(word(queue, i)), d->states[p]);
        }
        for (int c = 0; c < d->symbols; c++) {
            unsigned next = 0;
            for (int p = 0; p < d->count; p++) if (set & 1u << p) next |= 1u << delta(d, p, c);
            if (ids[next] < 0) {
                ids[next] = count;
                queue[count++] = (Search){(int)next, 0, i, d->alphabet[c]};
            }
        }
    }
    return "NOT SYNCHRONIZING";
}
typedef struct Regex Regex;
struct Regex {
    char kind;
    Regex **children;
    int count;
};
typedef struct {
    const char *text;
    int at;
} RegexParser;

static char regex_peek(const RegexParser *p) {
    return p->text[p->at];
}

static bool regex_symbol(char c) {
    return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
}

static Regex *regex_node(char kind, Regex **children, int count) {
    Regex *r = allocate(sizeof *r);
    r->kind = kind;
    r->count = count;
    r->children = allocate((size_t)count * sizeof(Regex *));
    if (count) memcpy(r->children, children, (size_t)count * sizeof(Regex *));
    return r;
}
static Regex *alternation(RegexParser *p);

static Regex *regex_atom(RegexParser *p) {
    char c = regex_peek(p);
    if (regex_symbol(c)) {
        p->at++;
        return regex_node(c, NULL, 0);
    }
    if (c == '(') {
        p->at++;
        Regex *r = alternation(p);
        if (regex_peek(p) != ')') fail("syntax error at %d", p->at + 1);
        p->at++;
        return r;
    }
    fail("syntax error at %d", p->at + 1);
    return NULL;
}

static Regex *regex_factor(RegexParser *p) {
    Regex *r = regex_atom(p);
    while (regex_peek(p) && strchr("*+?", regex_peek(p))) {
        char kind = p->text[p->at++];
        Regex *child[] = {r};
        r = regex_node(kind, child, 1);
    }
    return r;
}

static Regex *regex_concatenation(RegexParser *p) {
    Regex *children[41];
    int count = 0;
    children[count++] = regex_factor(p);
    while (regex_symbol(regex_peek(p)) || regex_peek(p) == '(') children[count++] = regex_factor(p);
    return count == 1 ? children[0] : regex_node('.', children, count);
}

static Regex *alternation(RegexParser *p) {
    Regex *children[41];
    int count = 0;
    children[count++] = regex_concatenation(p);
    while (regex_peek(p) == '|') {
        p->at++;
        children[count++] = regex_concatenation(p);
    }
    return count == 1 ? children[0] : regex_node('|', children, count);
}
typedef struct {
    int entry, exit;
} Fragment;

static int add_regex_state(Automaton *a) {
    char name[9];
    snprintf(name, sizeof name, "N%d", a->count);
    return add_state(a, name);
}

static Fragment build(Regex *r, Automaton *a) {
    if (r->kind == '.') {
        Fragment first_part = {0}, last = {0};
        for (int i = 0; i < r->count; i++) {
            Fragment next = build(r->children[i], a);
            if (i) edge(a, last.exit, a->symbols, next.entry);
            else first_part = next;
            last = next;
        }
        return (Fragment){first_part.entry, last.exit};
    }
    int entry = add_regex_state(a);
    if (!r->count) {
        int final = add_regex_state(a);
        edge(a, entry, r->kind == 'e' ? a->symbols : symbol_index(a, r->kind), final);
        return (Fragment){entry, final};
    }
    Fragment parts[41];
    for (int i = 0; i < r->count; i++) parts[i] = build(r->children[i], a);
    int final = add_regex_state(a);
    for (int i = 0; i < r->count; i++) {
        edge(a, entry, a->symbols, parts[i].entry);
        edge(a, parts[i].exit, a->symbols, final);
    }
    if (r->kind != '|') {
        if (r->kind != '?') edge(a, parts[0].exit, a->symbols, parts[0].entry);
        if (r->kind != '+') edge(a, entry, a->symbols, final);
    }
    return (Fragment){entry, final};
}
typedef struct {
    const char *items[1001];
    int count;
} Words;

static Words split_words(const char *text, char separator) {
    Words out = {0};
    const char *p = text;
    while (*p) {
        const char *first_word = p;
        while (*p && *p != separator) p++;
        out.items[out.count++] = part(first_word, (size_t)(p - first_word));
        if (*p) p++;
    }
    return out;
}

static Automaton *explicit_automaton(Words words) {
    const char **w = words.items;
    if (words.count < 6) fail("wrong number of arguments");
    if (find(w[1]) >= 0) fail("%s already exists", w[1]);
    Automaton *a = automaton(equal(w[0], "DFA"), w[3]);
    Words states = split_words(w[2], ',');
    for (int i = 0; i < states.count; i++) {
        if (state_index(a, states.items[i]) >= 0) fail("duplicate state %s", states.items[i]);
        add_state(a, states.items[i]);
    }
    a->start = state_index(a, w[4]);
    if (a->start < 0) fail("unknown state %s", w[4]);
    if (!equal(w[5], "-")) {
        Words accepting = split_words(w[5], ',');
        for (int i = 0; i < accepting.count; i++) {
            int p = state_index(a, accepting.items[i]);
            if (p < 0) fail("unknown state %s", accepting.items[i]);
            if (!insert(&a->accepting, p)) fail("duplicate state %s", accepting.items[i]);
        }
    }
    for (int i = 6; i < words.count; i++) {
        Words t = split_words(w[i], ':');
        int p = state_index(a, t.items[0]);
        char c = *t.items[1];
        if (p < 0) fail("unknown state %s", t.items[0]);
        if (c == 'e' && a->dfa) fail("epsilon transition in DFA");
        int symbol = c == 'e' ? a->symbols : symbol_index(a, c);
        if (symbol < 0) fail("unknown symbol %c", c);
        int q = state_index(a, t.items[2]);
        if (q < 0) fail("unknown state %s", t.items[2]);
        Set existing = a->transitions[p][symbol];
        if (has(existing, q)) fail("duplicate transition %s", w[i]);
        if (a->dfa && set_count(existing)) fail("conflicting transition %s", w[i]);
        edge(a, p, symbol, q);
    }
    if (a->dfa) for (int p = 0; p < a->count; p++) for (int c = 0; c < a->symbols; c++) if (!set_count(a->transitions[p][c])) fail("missing transition %s:%c", a->states[p], a->alphabet[c]);
    return a;
}

static void table(const Automaton *a) {
    int columns = a->symbols + 1 + (!a->dfa && epsilon_count(a) ? 1 : 0);
    char *(*cells)[12] = allocate((size_t)(a->count + 1) * sizeof *cells);
    int widths[12] = {0};
    cells[0][0] = "";
    for (int c = 1; c < columns; c++) cells[0][c] = format("%c", c <= a->symbols ? a->alphabet[c - 1] : 'e');
    for (int p = 0; p < a->count; p++) {
        cells[p + 1][0] = format("%s%c%s", p == a->start ? "->" : "  ", has(a->accepting, p) ? '*' : ' ', a->states[p]);
        for (int c = 1; c < columns; c++) {
            Set edges = a->transitions[p][c - 1];
            cells[p + 1][c] = a->dfa ? (char *)a->states[first(edges)] : !set_count(edges) ? "-" : set_text(a, edges);
        }
    }
    for (int r = 0; r <= a->count; r++) for (int c = 0; c < columns; c++) {
        int length = (int)strlen(cells[r][c]);
        if (length > widths[c]) widths[c] = length;
    }
    for (int r = 0; r <= a->count; r++) {
        Buffer line = {0};
        for (int c = 0; c < columns; c++) {
            if (c) append(&line, "  ");
            append(&line, cells[r][c]);
            for (int j = (int)strlen(cells[r][c]); j < widths[c]; j++) append(&line, " ");
        }
        while (line.length && line.text[line.length - 1] == ' ') line.text[--line.length] = '\0';
        puts(line.text);
        free(line.text);
    }
}

static char *show(const Automaton *a, const char *name) {
    Buffer b = {0};
    append(&b, a->dfa ? "DFA " : "NFA ");
    append(&b, name);
    append(&b, " ");
    for (int p = 0; p < a->count; p++) {
        if (p) append(&b, ",");
        append(&b, a->states[p]);
    }
    append(&b, " ");
    append(&b, a->alphabet);
    append(&b, " ");
    append(&b, a->states[a->start]);
    append(&b, " ");
    append(&b, set_count(a->accepting) ? list_text(a, a->accepting) : "-");
    for (int p = 0; p < a->count; p++) for (int c = 0; c <= a->symbols; c++) for (int q = 0; q < a->count; q++) if (has(a->transitions[p][c], q)) append(&b, format(" %s:%c:%s", a->states[p], c == a->symbols ? 'e' : a->alphabet[c], a->states[q]));
    return finish(&b);
}
typedef struct {
    const char *name, *roles;
} Command;
static const Command commands[] = {
    {"ACCEPT", "RO"},
    {"CLOSURE", "RO"},
    {"ENUM", "RO"},
    {"COUNT", "RO"},
    {"TODFA", "RN"},
    {"EPSFREE", "RN"},
    {"REVERSE", "RN"},
    {"STAR", "RN"},
    {"MINIMIZE", "DN"},
    {"COMPLEMENT", "DN"},
    {"EQUIV", "RR"},
    {"UNION", "DDN"},
    {"INTERSECT", "DDN"},
    {"DIFF", "DDN"},
    {"CONCAT", "RRN"},
    {"EMPTY", "R"},
    {"FINITE", "R"},
    {"INFO", "R"},
    {"TABLE", "R"},
    {"SHOW", "R"},
    {"DELETE", "R"},
    {"SYNC", "D"},
    {"LIST", ""}
};

static void command(const char *line) {
    Words words = split_words(line, ' ');
    const char **w = words.items, *c = w[0], *roles = NULL;
    for (size_t i = 0; i < sizeof commands / sizeof commands[0]; i++) if (equal(commands[i].name, c)) roles = commands[i].roles;
    if (!roles && !listed(c, "DFA NFA REGEX")) fail("unknown command %s", c);
    Lines details = {0};
    if (equal(c, "DFA") || equal(c, "NFA")) {
        Automaton *created = explicit_automaton(words);
        register_automaton(w[1], created, details);
        return;
    }
    if (equal(c, "REGEX")) {
        if (words.count != 4) fail("wrong number of arguments");
        if (find(w[1]) >= 0) fail("%s already exists", w[1]);
        for (const char *p = w[3]; *p; p++) if (regex_symbol(*p) && *p != 'e' && !strchr(w[2], *p)) fail("unknown symbol %c", *p);
        RegexParser parser = {w[3], 0};
        Regex *r = alternation(&parser);
        if (regex_peek(&parser)) fail("syntax error at %d", parser.at + 1);
        Automaton *created = automaton(false, w[2]);
        Fragment fragment = build(r, created);
        created->start = fragment.entry;
        insert(&created->accepting, fragment.exit);
        register_automaton(w[1], created, details);
        return;
    }
    int count = (int)strlen(roles);
    if (words.count != count + 1) fail("wrong number of arguments");
    for (int i = 0; i < count; i++) if (roles[i] == 'R' || roles[i] == 'D') get(w[i + 1]);
    for (int i = 0; i < count; i++) if (roles[i] == 'N' && find(w[i + 1]) >= 0) fail("%s already exists", w[i + 1]);
    for (int i = 0; i < count; i++) if (roles[i] == 'D' && !get(w[i + 1])->dfa) fail("%s is not a DFA", w[i + 1]);
    if (listed(c, "EQUIV UNION INTERSECT DIFF CONCAT") && !equal(get(w[1])->alphabet, get(w[2])->alphabet)) fail("alphabets differ");
    if (equal(c, "LIST")) {
        if (!entry_count) puts("(none)");
        for (int i = 0; i < entry_count; i++) puts(summary(entries[i].automaton, entries[i].name));
        return;
    }
    Automaton *a = get(w[1]);
    if (equal(c, "DELETE")) {
        int at = find(w[1]);
        memmove(entries + at, entries + at + 1, (size_t)(entry_count - at - 1) * sizeof(Entry));
        entry_count--;
        printf("deleted %s\n", w[1]);
        return;
    }
    if (equal(c, "ACCEPT")) {
        const char *text = equal(w[2], "e") ? "" : w[2];
        for (const char *p = text; *p; p++) if (symbol_index(a, *p) < 0) fail("unknown symbol %c", *p);
        Set set = initial(a);
        Buffer path = {0};
        append(&path, a->dfa ? a->states[first(set)] : set_text(a, set));
        for (const char *p = text; *p; p++) {
            set = move(a, set, symbol_index(a, *p));
            append(&path, format(" -%c-> %s", *p, a->dfa ? a->states[first(set)] : set_text(a, set)));
        }
        printf("%s %s\n", intersects(set, a->accepting) ? "ACCEPT" : "REJECT", path.text);
        free(path.text);
        return;
    }
    if (equal(c, "CLOSURE")) {
        Words states = split_words(w[2], ',');
        Set set = {
            {0}
        };
        for (int i = 0; i < states.count; i++) {
            int p = state_index(a, states.items[i]);
            if (p < 0) fail("unknown state %s", states.items[i]);
            insert(&set, p);
        }
        puts(set_text(a, closure(a, set)));
        return;
    }
    if (equal(c, "TODFA")) {
        Automaton *created = determinize(a, &details);
        register_automaton(w[2], created, details);
        return;
    }
    if (equal(c, "EPSFREE")) {
        register_automaton(w[2], epsilon_free(a), details);
        return;
    }
    if (equal(c, "MINIMIZE")) {
        Automaton *created = minimize(a, &details);
        register_automaton(w[2], created, details);
        return;
    }
    if (listed(c, "COMPLEMENT REVERSE STAR")) {
        register_automaton(w[2], unary_construction(a, c), details);
        return;
    }
    if (equal(c, "CONCAT")) {
        register_automaton(w[3], concatenate(a, get(w[2])), details);
        return;
    }
    if (listed(c, "UNION INTERSECT DIFF")) {
        Automaton *created = product(a, get(w[2]), c, &details);
        register_automaton(w[3], created, details);
        return;
    }
    if (equal(c, "EQUIV")) {
        puts(equivalent(a, get(w[2]), w[1], w[2]));
        return;
    }
    if (equal(c, "TABLE")) {
        table(a);
        return;
    }
    if (equal(c, "SHOW")) {
        puts(show(a, w[1]));
        return;
    }
    if (equal(c, "SYNC")) {
        puts(synchronize(a));
        return;
    }
    Automaton *d = determinize(a, NULL);
    if (equal(c, "COUNT")) printf("%lld\n", count_words(d, atoi(w[2])));
    else if (equal(c, "ENUM")) puts(enumerate(d, atoi(w[2])));
    else if (equal(c, "EMPTY")) {
        const char *text = smallest(d);
        if (text) printf("NOT EMPTY %s\n", visible(text));
        else puts("EMPTY");
    } else if (equal(c, "FINITE")) {
        long long total = 0;
        Language language = classify(d, &total);
        if (language == INFINITE_LANGUAGE) puts("INFINITE");
        else printf("FINITE %lld\n", total);
    } else if (equal(c, "INFO")) {
        bool deterministic = !epsilon_count(a), complete = true;
        for (int p = 0; p < a->count; p++) for (int c = 0; c < a->symbols; c++) {
            int n = set_count(a->transitions[p][c]);
            deterministic = deterministic && n <= 1;
            complete = complete && n > 0;
        }
        Language language = classify(d, NULL);
        puts(summary(a, w[1]));
        printf("  epsilon transitions: %d\n", epsilon_count(a));
        printf("  reachable: %s\n", list_text(a, graph_reach(a, false)));
        printf("  live: %s\n", list_text(a, graph_reach(a, true)));
        printf("  deterministic: %s\n  complete: %s\n", deterministic ? "yes" : "no", complete ? "yes" : "no");
        printf("  language: %s\n", language == EMPTY_LANGUAGE ? "empty" : language == FINITE_LANGUAGE ? "finite" : "infinite");
        printf("  minimal DFA states: %d\n", minimize(d, NULL)->count);
    }
}

int main(void) {
    char line[1002];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; i++) {
        if (!fgets(line, sizeof line, stdin)) break;
        size_t length = strlen(line);
        if (length && line[length - 1] == '\n') line[--length] = '\0';
        if (length && line[length - 1] == '\r') line[--length] = '\0';
        if (*line != '#' && setjmp(command_error) == 0) command(line);
        clear(&temporary);
    }
    clear(&permanent);
    return 0;
}
