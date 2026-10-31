#include "parser.h"
#include <stdint.h>
static Strings read_lines(const char *path) {
    FILE *file = fopen(path, "r");
    Strings out = {0};
    Text current = {0};
    int ch;
    while ((ch = fgetc(file)) != EOF) {
        if (ch == '\n') {
            strings_add(&out, current.data ? current.data : "");
            current = (Text){0};
        } else
            add(&current, "%c", ch);
    }
    fclose(file);
    return out;
}
static Strings words(const char *text) {
    Strings out = {0};
    size_t i = 0;
    while (text[i]) {
        while (text[i] == ' ')
            ++i;
        const size_t start = i;
        while (text[i] && text[i] != ' ')
            ++i;
        if (i > start)
            strings_add(&out, substring(text, start, i - start));
    }
    return out;
}
static const char *join(Strings values, const char *separator) {
    Text out = {0};
    for (int i = 0; i < values.n; ++i)
        add(&out, "%s%s", i ? separator : "", values.v[i]);
    return out.data ? out.data : "";
}
static void heading_list(Text *out, const char *heading, Strings values) {
    add(out, "%s", heading);
    for (int i = 0; i < values.n; ++i)
        add(out, " %s", values.v[i]);
    line(out, "");
}
static void number_heading(Text *out, const char *heading, Ints values, bool productions) {
    add(out, "%s", heading);
    for (int i = 0; i < values.n; ++i)
        add(out, " %d", values.v[i] + (productions ? 1 : 0));
    line(out, "");
}
static void reverse_ints(Ints values) {
    for (int i = 0; i < values.n / 2; ++i) {
        const int temporary = values.v[i];
        values.v[i] = values.v[values.n - 1 - i];
        values.v[values.n - 1 - i] = temporary;
    }
}
static void remove_names(Grammar *grammar, Strings removed) {
    Grammar out = {.start = grammar->start};
    for (int i = 0; i < grammar->n; ++i)
        if (!strings_has(removed, grammar->v[i].name))
            rule_add(&out, grammar->v[i], out.n);
    *grammar = out;
}
static bool *reachable(const Grammar *grammar) {
    bool *seen = allocate((size_t)grammar->n * sizeof *seen);
    int *queue = allocate((size_t)grammar->n * sizeof *queue);
    int head = 0, tail = 0;
    const int start = rule_index(grammar, grammar->start);
    seen[start] = true;
    queue[tail++] = start;
    while (head < tail) {
        const Rule *rule = &grammar->v[queue[head++]];
        for (int a = 0; a < rule->alternatives.n; ++a) {
            const Strings rhs = rule->alternatives.v[a];
            for (int j = 0; j < rhs.n; ++j)
                if (nonterminal(rhs.v[j])) {
                    const int next = rule_index(grammar, rhs.v[j]);
                    if (!seen[next]) {
                        seen[next] = true;
                        queue[tail++] = next;
                    }
                }
        }
    }
    return seen;
}
static int inner_compare(const void *left, const void *right) {
    const char *a = *(const char *const *)left, *b = *(const char *const *)right;
    const size_t na = strlen(a) - 2, nb = strlen(b) - 2, length = na < nb ? na : nb;
    const int comparison = strncmp(a + 1, b + 1, length);
    return comparison ? comparison : (na > nb) - (na < nb);
}
static void remove_alternatives(Grammar *grammar, Strings removed, const char *kind, Strings *diagnostics) {
    for (int a = 0; a < grammar->n; ++a) {
        const Alternatives old = grammar->v[a].alternatives;
        Alternatives kept = {0};
        for (int i = 0; i < old.n; ++i) {
            const Strings rhs = old.v[i];
            const char *first = NULL;
            for (int j = 0; j < rhs.n; ++j)
                if (strings_has(removed, rhs.v[j])) {
                    first = rhs.v[j];
                    break;
                }
            if (first)
                strings_add(diagnostics, format("removed %s (%s %s)",
                                                production_text(grammar->v[a].name, rhs), kind, first));
            else
                alternatives_add(&kept, rhs);
        }
        grammar->v[a].alternatives = kept;
    }
}
static void clean(Grammar *grammar, Strings *diagnostics) {
    Strings undefined = {0};
    for (int a = 0; a < grammar->n; ++a) {
        const Alternatives values = grammar->v[a].alternatives;
        for (int i = 0; i < values.n; ++i)
            for (int j = 0; j < values.v[i].n; ++j) {
                const char *symbol = values.v[i].v[j];
                if (nonterminal(symbol) && rule_index(grammar, symbol) < 0)
                    strings_unique(&undefined, symbol);
            }
    }
    if (undefined.n > 1)
        qsort(undefined.v, (size_t)undefined.n, sizeof *undefined.v, inner_compare);
    for (int i = 0; i < undefined.n; ++i)
        strings_add(diagnostics, format("undefined nonterminal %s", undefined.v[i]));
    remove_alternatives(grammar, undefined, "undefined", diagnostics);
    bool *productive = allocate((size_t)grammar->n * sizeof *productive);
    bool changed;
    do {
        changed = false;
        for (int a = 0; a < grammar->n; ++a) {
            const Alternatives values = grammar->v[a].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const Strings rhs = values.v[i];
                bool possible = true;
                for (int j = 0; j < rhs.n; ++j)
                    if (nonterminal(rhs.v[j]) && !productive[rule_index(grammar, rhs.v[j])]) {
                        possible = false;
                        break;
                    }
                if (possible && !productive[a]) {
                    productive[a] = true;
                    changed = true;
                }
            }
        }
    } while (changed);
    Strings unproductive = {0};
    for (int a = 0; a < grammar->n; ++a)
        if (!productive[a]) {
            strings_add(&unproductive, grammar->v[a].name);
            strings_add(diagnostics, format("unproductive nonterminal %s", grammar->v[a].name));
        }
    remove_names(grammar, unproductive);
    remove_alternatives(grammar, unproductive, "unproductive", diagnostics);
    const bool *seen = reachable(grammar);
    Strings unreachable = {0};
    for (int a = 0; a < grammar->n; ++a)
        if (!seen[a]) {
            strings_add(&unreachable, grammar->v[a].name);
            strings_add(diagnostics, format("unreachable nonterminal %s", grammar->v[a].name));
        }
    remove_names(grammar, unreachable);
}
static void report_recursion(const Grammar *grammar, Strings *diagnostics) {
    for (int start = 0; start < grammar->n; ++start) {
        bool *seen = allocate((size_t)grammar->n * sizeof *seen);
        int *parent = allocate((size_t)grammar->n * sizeof *parent),
            *queue = allocate((size_t)grammar->n * sizeof *queue);
        int head = 0, tail = 0, last = -1;
        seen[start] = true;
        queue[tail++] = start;
        while (head < tail && last < 0) {
            const int current = queue[head++];
            const Alternatives values = grammar->v[current].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const Strings rhs = values.v[i];
                if (!rhs.n || !nonterminal(rhs.v[0]))
                    continue;
                const int next = rule_index(grammar, rhs.v[0]);
                if (next == start) {
                    last = current;
                    break;
                }
                if (!seen[next]) {
                    seen[next] = true;
                    parent[next] = current;
                    queue[tail++] = next;
                }
            }
        }
        if (last >= 0) {
            Ints reverse = {0};
            int current = last;
            while (current != start) {
                ints_add(&reverse, current);
                current = parent[current];
            }
            reverse_ints(reverse);
            Strings path = {0};
            strings_add(&path, grammar->v[start].name);
            for (int i = 0; i < reverse.n; ++i)
                strings_add(&path, grammar->v[reverse.v[i]].name);
            strings_add(&path, grammar->v[start].name);
            strings_add(diagnostics, format("left recursion: %s", join(path, " -> ")));
        }
    }
}
static const char *summary_line(const Grammar *grammar) {
    Strings terminals = {0};
    int productions = 0, empty = 0, unit = 0;
    for (int a = 0; a < grammar->n; ++a) {
        const Alternatives values = grammar->v[a].alternatives;
        for (int i = 0; i < values.n; ++i) {
            const Strings rhs = values.v[i];
            ++productions;
            empty += rhs.n == 0;
            unit += rhs.n == 1 && nonterminal(rhs.v[0]);
            for (int j = 0; j < rhs.n; ++j)
                if (!nonterminal(rhs.v[j]))
                    strings_unique(&terminals, rhs.v[j]);
        }
    }
    return format("start=%s nonterminals=%d terminals=%d productions=%d empty=%d unit=%d", grammar->start,
                  grammar->n, terminals.n, productions, empty, unit);
}
static void listing(Text *out, const Grammar *grammar, bool numbered) {
    int total = 0;
    for (int a = 0; a < grammar->n; ++a)
        total += grammar->v[a].alternatives.n;
    const int width = (int)strlen(format("%d", total));
    int number = 0;
    for (int a = 0; a < grammar->n; ++a) {
        const Rule *rule = &grammar->v[a];
        for (int i = 0; i < rule->alternatives.n; ++i) {
            ++number;
            if (numbered)
                add(out, "%*d  ", width, number);
            if (!i)
                line(out, "%s -> %s", rule->name, notation(rule->alternatives.v[i]));
            else
                line(out, "%*s | %s", (int)strlen(rule->name), "", notation(rule->alternatives.v[i]));
        }
    }
}
static void logs(Text *out, Strings values) {
    if (!values.n)
        line(out, "none");
    else
        for (int i = 0; i < values.n; ++i)
            line(out, "%s", values.v[i]);
}
typedef struct {
    int length, height;
} Cost;
static const Cost infinity = {1000000000, 1000000000};
static bool cost_less(Cost a, Cost b) {
    return a.length < b.length || (a.length == b.length && a.height < b.height);
}
static bool cost_equal(Cost a, Cost b) {
    return a.length == b.length && a.height == b.height;
}
typedef struct {
    const Grammar *grammar;
    const Table *table;
    Cost *length, *context;
    Strings *shortest, *left, *right;
    bool *short_built, *context_built;
} Sentences;
static Cost alternative_cost(Strings sequence, const Sentences *sentences) {
    int terminals = 0, height = 0;
    for (int i = 0; i < sequence.n; ++i) {
        const char *symbol = sequence.v[i];
        if (nonterminal(symbol)) {
            const Cost value = sentences->length[rule_index(sentences->grammar, symbol)];
            if (cost_equal(value, infinity))
                return infinity;
            terminals += value.length;
            if (value.height > height)
                height = value.height;
        } else
            ++terminals;
    }
    return (Cost){terminals, height + 1};
}
static Strings build_shortest(Sentences *sentences, int index) {
    if (sentences->short_built[index])
        return sentences->shortest[index];
    const Alternatives values = sentences->grammar->v[index].alternatives;
    for (int a = 0; a < values.n; ++a)
        if (cost_equal(alternative_cost(values.v[a], sentences), sentences->length[index])) {
            Strings out = {0};
            for (int j = 0; j < values.v[a].n; ++j) {
                const char *symbol = values.v[a].v[j];
                if (nonterminal(symbol)) {
                    const Strings child = build_shortest(sentences, rule_index(sentences->grammar, symbol));
                    for (int k = 0; k < child.n; ++k)
                        strings_add(&out, child.v[k]);
                } else
                    strings_add(&out, symbol);
            }
            sentences->shortest[index] = out;
            sentences->short_built[index] = true;
            return out;
        }
    return (Strings){0};
}
static Strings sentence_of(Strings sequence, const Sentences *sentences) {
    Strings out = {0};
    for (int i = 0; i < sequence.n; ++i) {
        const char *symbol = sequence.v[i];
        if (nonterminal(symbol)) {
            const Strings value = sentences->shortest[rule_index(sentences->grammar, symbol)];
            for (int j = 0; j < value.n; ++j)
                strings_add(&out, value.v[j]);
        } else
            strings_add(&out, symbol);
    }
    return out;
}
static Cost occurrence_cost(const Sentences *sentences, Production production, int position) {
    const Cost context = sentences->context[production.lhs];
    if (cost_equal(context, infinity))
        return infinity;
    int size = context.length;
    for (int i = 0; i < production.rhs.n; ++i)
        if (i != position)
            size += nonterminal(production.rhs.v[i])
                        ? sentences->length[rule_index(sentences->grammar, production.rhs.v[i])].length
                        : 1;
    return (Cost){size, context.height + 1};
}
static void build_context(Sentences *sentences, int index) {
    if (sentences->context_built[index])
        return;
    const char *name = sentences->grammar->v[index].name;
    for (int p = 0; p < sentences->table->nproductions; ++p) {
        const Production production = sentences->table->productions[p];
        for (int i = 0; i < production.rhs.n; ++i)
            if (strcmp(production.rhs.v[i], name) == 0 &&
                cost_equal(occurrence_cost(sentences, production, i), sentences->context[index])) {
                build_context(sentences, production.lhs);
                const Strings before = strings_slice(production.rhs, 0, i),
                              after = strings_slice(production.rhs, i + 1, production.rhs.n);
                sentences->left[index] =
                    strings_concat(sentences->left[production.lhs], sentence_of(before, sentences));
                sentences->right[index] =
                    strings_concat(sentence_of(after, sentences), sentences->right[production.lhs]);
                sentences->context_built[index] = true;
                return;
            }
    }
}
static Sentences sentences(const Grammar *grammar, const Table *table) {
    Sentences out = {.grammar = grammar, .table = table};
    const size_t n = (size_t)grammar->n;
    out.length = allocate(n * sizeof *out.length);
    out.context = allocate(n * sizeof *out.context);
    out.shortest = allocate(n * sizeof *out.shortest);
    out.left = allocate(n * sizeof *out.left);
    out.right = allocate(n * sizeof *out.right);
    out.short_built = allocate(n * sizeof *out.short_built);
    out.context_built = allocate(n * sizeof *out.context_built);
    for (int i = 0; i < grammar->n; ++i)
        out.length[i] = out.context[i] = infinity;
    bool changed;
    do {
        changed = false;
        for (int a = 0; a < grammar->n; ++a) {
            const Alternatives values = grammar->v[a].alternatives;
            for (int i = 0; i < values.n; ++i) {
                const Cost value = alternative_cost(values.v[i], &out);
                if (cost_less(value, out.length[a])) {
                    out.length[a] = value;
                    changed = true;
                }
            }
        }
    } while (changed);
    for (int a = 0; a < grammar->n; ++a)
        build_shortest(&out, a);
    const int start = rule_index(grammar, grammar->start);
    out.context[start] = (Cost){0, 0};
    do {
        changed = false;
        for (int p = 0; p < table->nproductions; ++p) {
            const Production production = table->productions[p];
            for (int i = 0; i < production.rhs.n; ++i)
                if (nonterminal(production.rhs.v[i])) {
                    const int index = rule_index(grammar, production.rhs.v[i]);
                    const Cost value = occurrence_cost(&out, production, i);
                    if (cost_less(value, out.context[index])) {
                        out.context[index] = value;
                        changed = true;
                    }
                }
        }
    } while (changed);
    out.context_built[start] = true;
    for (int a = 0; a < grammar->n; ++a)
        build_context(&out, a);
    return out;
}
static Ints ints_clone(Ints values) {
    Ints out = {0};
    for (int i = 0; i < values.n; ++i)
        ints_add(&out, values.v[i]);
    return out;
}
static Ints conflict_path(const Grammar *grammar, const Sets *sets, const Table *table, int number,
                          const char *terminal) {
    if (strcmp(reason(table, number, terminal), "FIRST") == 0) {
        bool *seen = allocate((size_t)table->nproductions * sizeof *seen);
        int *parent = allocate((size_t)table->nproductions * sizeof *parent),
            *queue = allocate((size_t)table->nproductions * sizeof *queue);
        int head = 0, tail = 0;
        seen[number] = true;
        queue[tail++] = number;
        while (head < tail) {
            const int current = queue[head++];
            const Strings rhs = table->productions[current].rhs;
            for (int i = 0; i < rhs.n; ++i) {
                const char *symbol = rhs.v[i];
                if (strcmp(symbol, terminal) == 0) {
                    Ints out = {0};
                    int at = current;
                    while (at != number) {
                        ints_add(&out, at);
                        at = parent[at];
                    }
                    reverse_ints(out);
                    return out;
                }
                if (nonterminal(symbol)) {
                    const int lhs = rule_index(grammar, symbol);
                    for (int p = 0; p < table->nproductions; ++p)
                        if (table->productions[p].lhs == lhs && !seen[p]) {
                            seen[p] = true;
                            parent[p] = current;
                            queue[tail++] = p;
                        }
                }
                if (!nonterminal(symbol) || !sets->nullable[rule_index(grammar, symbol)])
                    break;
            }
        }
        return (Ints){0};
    }
    bool *known = allocate((size_t)grammar->n * sizeof *known);
    Ints *paths = allocate((size_t)grammar->n * sizeof *paths);
    int *queue = allocate((size_t)grammar->n * sizeof *queue);
    int head = 0, tail = 0;
    const int start = table->productions[number].lhs;
    known[start] = true;
    queue[tail++] = start;
    while (head < tail) {
        const int current = queue[head++];
        if (strcmp(grammar->v[current].name, grammar->start) == 0 && strcmp(terminal, "$") == 0)
            return paths[current];
        for (int p = 0; p < table->nproductions; ++p) {
            const Production production = table->productions[p];
            for (int i = 0; i < production.rhs.n; ++i)
                if (strcmp(production.rhs.v[i], grammar->v[current].name) == 0) {
                    const First first =
                        first_sequence(strings_slice(production.rhs, i + 1, production.rhs.n), sets);
                    Ints path = ints_clone(paths[current]);
                    ints_add(&path, p);
                    if (strings_has(first.terminals, terminal))
                        return path;
                    if (first.nullable && !known[production.lhs]) {
                        known[production.lhs] = true;
                        paths[production.lhs] = path;
                        queue[tail++] = production.lhs;
                    }
                }
        }
    }
    return (Ints){0};
}
typedef struct {
    int production, dot, origin;
} EarleyItem;
typedef struct {
    EarleyItem *v;
    int n, capacity;
    int *slots, nslots;
} Chart;
static uint64_t item_hash(EarleyItem item) {
    return (uint64_t)(item.production + 1) * 11400714819323198485ULL ^
           (uint64_t)(item.dot + 1) * 14029467366897019727ULL ^
           (uint64_t)(item.origin + 1) * 1609587929392839161ULL;
}
static bool item_equal(EarleyItem a, EarleyItem b) {
    return a.production == b.production && a.dot == b.dot && a.origin == b.origin;
}
static void rehash(Chart *chart, int size) {
    chart->nslots = size;
    chart->slots = allocate((size_t)size * sizeof *chart->slots);
    for (int i = 0; i < chart->n; ++i) {
        size_t position = (size_t)(item_hash(chart->v[i]) & (uint64_t)(size - 1));
        while (chart->slots[position])
            position = (position + 1) & (size_t)(size - 1);
        chart->slots[position] = i + 1;
    }
}
static void chart_add(Chart *chart, EarleyItem item) {
    if (!chart->nslots)
        rehash(chart, 32);
    else if ((chart->n + 1) * 10 > chart->nslots * 7)
        rehash(chart, chart->nslots * 2);
    size_t position = (size_t)(item_hash(item) & (uint64_t)(chart->nslots - 1));
    while (chart->slots[position]) {
        if (item_equal(chart->v[chart->slots[position] - 1], item))
            return;
        position = (position + 1) & (size_t)(chart->nslots - 1);
    }
    if (chart->n == chart->capacity) {
        const int capacity = chart->capacity ? chart->capacity * 2 : 16;
        chart->v = grow(chart->v, (size_t)chart->n * sizeof *chart->v, (size_t)capacity * sizeof *chart->v);
        chart->capacity = capacity;
    }
    chart->v[chart->n] = item;
    chart->slots[position] = ++chart->n;
}
static bool language(const Grammar *grammar, Strings tokens) {
    int total = 0;
    for (int a = 0; a < grammar->n; ++a)
        total += grammar->v[a].alternatives.n;
    Production *productions = allocate((size_t)(total + 1) * sizeof *productions);
    int p = 0;
    for (int a = 0; a < grammar->n; ++a) {
        const Alternatives values = grammar->v[a].alternatives;
        for (int i = 0; i < values.n; ++i)
            productions[p++] = (Production){a, values.v[i]};
    }
    Strings root = {0};
    strings_add(&root, grammar->start);
    productions[total] = (Production){-1, root};
    Chart *chart = allocate((size_t)(tokens.n + 1) * sizeof *chart);
    chart_add(&chart[0], (EarleyItem){total, 0, 0});
    for (int position = 0; position <= tokens.n; ++position) {
        int previous;
        do {
            previous = chart[position].n;
            for (int index = 0; index < chart[position].n; ++index) {
                const EarleyItem item = chart[position].v[index];
                const Production production = productions[item.production];
                if (item.dot == production.rhs.n) {
                    const int count = chart[item.origin].n;
                    for (int i = 0; i < count; ++i) {
                        const EarleyItem waiting = chart[item.origin].v[i];
                        const Production source = productions[waiting.production];
                        if (waiting.dot < source.rhs.n && production.lhs >= 0 &&
                            strcmp(source.rhs.v[waiting.dot], grammar->v[production.lhs].name) == 0)
                            chart_add(&chart[position],
                                      (EarleyItem){waiting.production, waiting.dot + 1, waiting.origin});
                    }
                } else {
                    const char *symbol = production.rhs.v[item.dot];
                    if (nonterminal(symbol)) {
                        const int lhs = rule_index(grammar, symbol);
                        for (int next = 0; next < total; ++next)
                            if (productions[next].lhs == lhs)
                                chart_add(&chart[position], (EarleyItem){next, 0, position});
                    } else if (position < tokens.n && strcmp(symbol, tokens.v[position]) == 0)
                        chart_add(&chart[position + 1],
                                  (EarleyItem){item.production, item.dot + 1, item.origin});
                }
            }
        } while (chart[position].n != previous);
    }
    for (int i = 0; i < chart[tokens.n].n; ++i)
        if (item_equal(chart[tokens.n].v[i], (EarleyItem){total, 1, 0}))
            return true;
    return false;
}
static bool unmarked(const Tree *node) {
    return !node->mark || !node->mark[0];
}
static Tree *compact(const Tree *node) {
    Tree **children = NULL;
    int count = 0;
    for (int i = 0; i < node->nchildren; ++i) {
        const Tree *child = node->children[i];
        if (strcmp(child->symbol, "%empty") == 0)
            continue;
        Tree *value = compact(child);
        if (unmarked(value) && nonterminal(value->symbol) && !value->nchildren)
            continue;
        if (unmarked(value) && nonterminal(value->symbol) && strchr(value->symbol, '\'')) {
            for (int j = 0; j < value->nchildren; ++j) {
                children =
                    grow(children, (size_t)count * sizeof *children, (size_t)(count + 1) * sizeof *children);
                children[count++] = value->children[j];
            }
        } else {
            children =
                grow(children, (size_t)count * sizeof *children, (size_t)(count + 1) * sizeof *children);
            children[count++] = value;
        }
    }
    if (count == 1 && unmarked(node))
        return children[0];
    Tree *out = allocate(sizeof *out);
    out->symbol = node->symbol;
    out->mark = node->mark;
    out->children = children;
    out->nchildren = count;
    return out;
}
static const char *label(const Tree *node) {
    return unmarked(node) ? node->symbol : format("%s (%s)", node->symbol, node->mark);
}
static void tree_children(Text *out, const Tree *node, const char *prefix) {
    for (int i = 0; i < node->nchildren; ++i) {
        const bool last = i + 1 == node->nchildren;
        line(out, "%s%s%s", prefix, last ? "`-- " : "|-- ", label(node->children[i]));
        tree_children(out, node->children[i], format("%s%s", prefix, last ? "    " : "|   "));
    }
}
static void print_tree(Text *out, const Tree *tree) {
    line(out, "%s", label(tree));
    tree_children(out, tree, "");
}
static const char *action_text(const Step *step, const Table *table) {
    switch (step->action) {
    case ACCEPT:
        return "accept";
    case MATCH:
        return format("match %s", step->current);
    case PREDICT: {
        const Production production = table->productions[step->production];
        return format("predict %d: %s", step->production + 1,
                      production_text(table->grammar->v[production.lhs].name, production.rhs));
    }
    case SKIP:
        return format("error: skip %s", step->current);
    case POP:
        return format("error: pop %s", step->top);
    case MISSING:
        return format("error: missing %s", step->top);
    }
    return "";
}
static const char *error_text(const Step *step, int number, const Table *table) {
    const char *unexpected = strcmp(step->current, "$") == 0
                                 ? "end of input"
                                 : format("\"%s\" at token %d", step->current, step->position);
    Strings expected = {0};
    if (nonterminal(step->top)) {
        const int lhs = rule_index(table->grammar, step->top);
        for (int t = 0; t < table->terminals.n; ++t)
            if (table->cells[lhs * table->terminals.n + t].n) {
                const char *terminal = table->terminals.v[t];
                strings_add(&expected, strcmp(terminal, "$") == 0 ? terminal : format("\"%s\"", terminal));
            }
    } else
        strings_add(&expected, strcmp(step->top, "$") == 0 ? step->top : format("\"%s\"", step->top));
    const char *recovery = step->action == SKIP  ? format("skipped \"%s\"", step->current)
                           : step->action == POP ? format("popped %s", step->top)
                                                 : format("inserted \"%s\"", step->top);
    return format("step %d: unexpected %s; expected %s; %s", number, unexpected, join(expected, " "),
                  recovery);
}
static void trace(Text *out, const Parse *parse, const Table *table) {
    const int count = parse->nsteps + 1;
    const char *(*rows)[4] = allocate((size_t)count * sizeof *rows);
    rows[0][0] = "step";
    rows[0][1] = "stack";
    rows[0][2] = "input";
    rows[0][3] = "action";
    for (int i = 0; i < parse->nsteps; ++i) {
        rows[i + 1][0] = format("%d", i + 1);
        rows[i + 1][1] = notation(parse->steps[i].stack);
        rows[i + 1][2] = notation(parse->steps[i].input);
        rows[i + 1][3] = action_text(&parse->steps[i], table);
    }
    int widths[3] = {0};
    for (int i = 0; i < count; ++i)
        for (int j = 0; j < 3; ++j) {
            const int size = (int)strlen(rows[i][j]);
            if (size > widths[j])
                widths[j] = size;
        }
    for (int i = 0; i < count; ++i)
        line(out, "%-*s  %-*s  %-*s  %s", widths[0], rows[i][0], widths[1], rows[i][1], widths[2], rows[i][2],
             rows[i][3]);
}
static int occurrence_compare(const void *left, const void *right) {
    return strcmp(((const Occurrence *)left)->name, ((const Occurrence *)right)->name);
}
static void write_report(const char *name, Text text) {
    FILE *file = fopen(format("output/%s", name), "wb");
    if (text.size)
        fwrite(text.data, 1, text.size, file);
    fclose(file);
}
int main(void) {
    mkdir("output", 0777);
    Arena permanent = {0};
    arena = &permanent;
    Parsed parsed = read_grammar(read_lines("input/grammar.bnf"));
    Grammar grammar = parsed.grammar;
    Strings diagnostics = strings_slice(parsed.diagnostics, 0, parsed.diagnostics.n);
    if (parsed.declarations) {
        if (parsed.nwords > 1)
            qsort(parsed.words, (size_t)parsed.nwords, sizeof *parsed.words, occurrence_compare);
        for (int i = 0; i < parsed.nwords; ++i)
            if (!strings_has(parsed.declared, parsed.words[i].name))
                strings_add(&diagnostics, format("undeclared terminal %s at line %d", parsed.words[i].name,
                                                 parsed.words[i].line));
    }
    clean(&grammar, &diagnostics);
    const Grammar cleaned = grammar_clone(&grammar);
    report_recursion(&cleaned, &diagnostics);
    const Sets before_sets = first_follow(&cleaned);
    const Table before_table = build_table(&cleaned, &before_sets);
    const int before = before_table.conflicts;
    const Strings elimination = eliminate_recursion(&grammar);
    const Grammar eliminated = grammar_clone(&grammar);
    const Strings factoring = left_factor(&grammar);
    const Grammar factored = grammar_clone(&grammar);
    const bool *seen = reachable(&grammar);
    Strings removed = {0}, removal = {0};
    for (int a = 0; a < grammar.n; ++a)
        if (!seen[a]) {
            strings_add(&removed, grammar.v[a].name);
            strings_add(&removal, format("remove unreachable %s", grammar.v[a].name));
            strings_add(&diagnostics, format("unreachable after transformation %s", grammar.v[a].name));
        }
    remove_names(&grammar, removed);
    const Sets sets = first_follow(&grammar);
    const Table table = build_table(&grammar, &sets);
    Sentences sentence = sentences(&grammar, &table);
    Strings known = {0};
    for (int t = 0; t < table.terminals.n; ++t)
        if (strcmp(table.terminals.v[t], "$") != 0)
            strings_add(&known, table.terminals.v[t]);
    if (parsed.declarations) {
        terminal_sort(parsed.declared);
        for (int t = 0; t < parsed.declared.n; ++t)
            if (!strings_has(known, parsed.declared.v[t]))
                strings_add(&diagnostics, format("unused token %s", parsed.declared.v[t]));
    }
    Text grammar_file = {0}, sets_file = {0}, table_file = {0}, parses_file = {0}, diagnostics_file = {0};
    line(&grammar_file, "== cleaned grammar ==");
    line(&grammar_file, "%s", summary_line(&cleaned));
    listing(&grammar_file, &cleaned, false);
    line(&grammar_file, "");
    line(&grammar_file, "== left recursion elimination ==");
    logs(&grammar_file, elimination);
    line(&grammar_file, "%s", summary_line(&eliminated));
    listing(&grammar_file, &eliminated, false);
    line(&grammar_file, "");
    line(&grammar_file, "== left factoring ==");
    logs(&grammar_file, factoring);
    line(&grammar_file, "%s", summary_line(&factored));
    listing(&grammar_file, &factored, false);
    line(&grammar_file, "");
    line(&grammar_file, "== final grammar ==");
    logs(&grammar_file, removal);
    line(&grammar_file, "%s", summary_line(&grammar));
    listing(&grammar_file, &grammar, true);
    line(&grammar_file, "");
    line(&grammar_file, "== cross reference ==");
    Strings symbols = {0};
    for (int a = 0; a < grammar.n; ++a)
        strings_add(&symbols, grammar.v[a].name);
    for (int t = 0; t < known.n; ++t)
        strings_add(&symbols, known.v[t]);
    for (int i = 0; i < symbols.n; ++i) {
        const char *symbol = symbols.v[i];
        Ints used = {0};
        for (int p = 0; p < table.nproductions; ++p)
            if (strings_has(table.productions[p].rhs, symbol))
                ints_add(&used, p);
        const char *name = nonterminal(symbol) ? symbol : format("\"%s\"", symbol);
        if (!used.n)
            line(&grammar_file, "%s not used", name);
        else
            number_heading(&grammar_file, format("%s used in", name), used, true);
    }
    line(&sets_file, "passes: nullable=%d first=%d follow=%d", sets.nullable_passes, sets.first_passes,
         sets.follow_passes);
    line(&sets_file, "");
    for (int a = 0; a < grammar.n; ++a) {
        line(&sets_file, "%s", grammar.v[a].name);
        line(&sets_file, "  nullable: %s", sets.nullable[a] ? "yes" : "no");
        terminal_sort(sets.first[a]);
        terminal_sort(sets.follow[a]);
        heading_list(&sets_file, "  first:", sets.first[a]);
        heading_list(&sets_file, "  follow:", sets.follow[a]);
        heading_list(&sets_file, "  shortest:", sentence.shortest[a]);
    }
    line(&table_file, "== predict sets ==");
    for (int p = 0; p < table.nproductions; ++p) {
        const Production production = table.productions[p];
        line(&table_file, "%d: %s", p + 1, production_text(grammar.v[production.lhs].name, production.rhs));
        terminal_sort(table.predict[p]);
        heading_list(&table_file, "  predict:", table.predict[p]);
    }
    line(&table_file, "");
    line(&table_file, "== parse table ==");
    Strings *rows = allocate((size_t)(grammar.n + 1) * sizeof *rows);
    strings_add(&rows[0], "");
    for (int t = 0; t < table.terminals.n; ++t)
        strings_add(&rows[0], table.terminals.v[t]);
    for (int a = 0; a < grammar.n; ++a) {
        strings_add(&rows[a + 1], grammar.v[a].name);
        for (int t = 0; t < table.terminals.n; ++t) {
            const Ints cell = table.cells[a * table.terminals.n + t];
            if (!cell.n)
                strings_add(&rows[a + 1], ".");
            else {
                Strings values = {0};
                for (int i = 0; i < cell.n; ++i)
                    strings_add(&values, format("%d", cell.v[i] + 1));
                strings_add(&rows[a + 1], join(values, "/"));
            }
        }
    }
    int *widths = allocate((size_t)rows[0].n * sizeof *widths);
    for (int i = 0; i <= grammar.n; ++i)
        for (int j = 0; j < rows[i].n; ++j) {
            const int size = (int)strlen(rows[i].v[j]);
            if (size > widths[j])
                widths[j] = size;
        }
    for (int i = 0; i <= grammar.n; ++i) {
        add(&table_file, "%-*s", widths[0], rows[i].v[0]);
        for (int j = 1; j < rows[i].n; ++j)
            add(&table_file, "  %*s", widths[j], rows[i].v[j]);
        line(&table_file, "");
    }
    line(&table_file, "");
    line(&table_file, "== conflicts ==");
    if (!table.conflicts)
        line(&table_file, "none");
    for (int a = 0; a < grammar.n; ++a)
        for (int t = 0; t < table.terminals.n; ++t) {
            const Ints cell = table.cells[a * table.terminals.n + t];
            if (cell.n < 2)
                continue;
            const char *terminal = table.terminals.v[t];
            line(&table_file, "conflict %s on %s: %s, chosen %d", grammar.v[a].name, terminal,
                 conflict_kind(&table, cell, terminal), table.chosen[a * table.terminals.n + t] + 1);
            for (int i = 0; i < cell.n; ++i) {
                const int number = cell.v[i];
                const Production production = table.productions[number];
                const Ints path = conflict_path(&grammar, &sets, &table, number, terminal);
                add(&table_file, "  %d: %s (%s", number + 1,
                    production_text(grammar.v[production.lhs].name, production.rhs),
                    reason(&table, number, terminal));
                if (path.n) {
                    add(&table_file, " via");
                    for (int j = 0; j < path.n; ++j)
                        add(&table_file, " %d", path.v[j] + 1);
                }
                line(&table_file, ")");
            }
        }
    line(&table_file, "LL(1): %s", table.conflicts ? "no" : "yes");
    line(&table_file, "conflicts before transformation: %d", before);
    const Strings inputs = read_lines("input/inputs.txt");
    bool *used = allocate((size_t)table.nproductions * sizeof *used);
    int mismatches[50], nmismatches = 0, accepted_count = 0, in_language = 0, unknown_total = 0,
                        skip_total = 0, pop_total = 0, missing_total = 0;
    for (int input = 0; input < inputs.n; ++input) {
        Arena temporary = {0};
        arena = &temporary;
        const Strings original = words(inputs.v[input]);
        InputToken *tokens = allocate((size_t)original.n * sizeof *tokens);
        int ntokens = 0;
        Strings errors = {0};
        for (int i = 0; i < original.n; ++i)
            if (!strings_has(known, original.v[i])) {
                strings_add(&errors, format("unknown \"%s\" at token %d; removed", original.v[i], i + 1));
                ++unknown_total;
            } else
                tokens[ntokens++] = (InputToken){original.v[i], i + 1};
        const Parse parse = drive(&grammar, &sets, &table, tokens, ntokens);
        for (int i = 0; i < parse.nsteps; ++i)
            if (parse.steps[i].action == SKIP || parse.steps[i].action == POP ||
                parse.steps[i].action == MISSING)
                strings_add(&errors, error_text(&parse.steps[i], i + 1, &table));
        const bool accepted = errors.n == 0, belongs = language(&cleaned, original);
        accepted_count += accepted;
        in_language += belongs;
        if (accepted != belongs)
            mismatches[nmismatches++] = input + 1;
        skip_total += parse.skip;
        pop_total += parse.pop;
        missing_total += parse.missing;
        for (int i = 0; i < parse.left_parse.n; ++i)
            used[parse.left_parse.v[i]] = true;
        Text rendered = {0};
        line(&rendered, "== input %d ==", input + 1);
        heading_list(&rendered, "tokens:", original);
        trace(&rendered, &parse, &table);
        number_heading(&rendered, "left parse:", parse.left_parse, true);
        line(&rendered, "stats: steps=%d predicts=%d matches=%d max_stack=%d", parse.nsteps,
             parse.left_parse.n, parse.matches, parse.max_stack);
        if (errors.n) {
            line(&rendered, "errors:");
            for (int i = 0; i < errors.n; ++i)
                line(&rendered, "  %s", errors.v[i]);
        }
        if (accepted)
            line(&rendered, "result: accepted");
        else
            line(&rendered, "result: rejected (errors: %d)", errors.n);
        line(&rendered, "language: %s", belongs ? "yes" : "no");
        if (accepted) {
            line(&rendered, "derivation:");
            line(&rendered, "  %s", grammar.start);
            Strings form = {0};
            strings_add(&form, grammar.start);
            for (int i = 0; i < parse.left_parse.n; ++i) {
                const Production production = table.productions[parse.left_parse.v[i]];
                int position = 0;
                while (!nonterminal(form.v[position]))
                    ++position;
                Strings next = strings_slice(form, 0, position);
                next = strings_concat(next, production.rhs);
                next = strings_concat(next, strings_slice(form, position + 1, form.n));
                form = next;
                line(&rendered, "  => %s", notation(form));
            }
        }
        line(&rendered, "tree:");
        print_tree(&rendered, parse.tree);
        line(&rendered, "compact tree:");
        print_tree(&rendered, compact(parse.tree));
        line(&rendered, "");
        arena = &permanent;
        add(&parses_file, "%s", rendered.data);
        arena_free(&temporary);
    }
    line(&parses_file, "== summary ==");
    line(&parses_file, "inputs=%d accepted=%d rejected=%d in_language=%d", inputs.n, accepted_count,
         inputs.n - accepted_count, in_language);
    number_heading(&parses_file, "mismatches:", (Ints){.v = mismatches, .n = nmismatches}, false);
    line(&parses_file, "recovery: unknown=%d skip=%d pop=%d missing=%d", unknown_total, skip_total, pop_total,
         missing_total);
    int nused = 0;
    Ints unused = {0};
    for (int number = 0; number < table.nproductions; ++number)
        if (used[number])
            ++nused;
        else
            ints_add(&unused, number);
    line(&parses_file, "coverage: %d of %d productions used", nused, table.nproductions);
    number_heading(&parses_file, "unused:", unused, true);
    for (int i = 0; i < unused.n; ++i) {
        const int number = unused.v[i];
        const Production production = table.productions[number];
        Arena temporary = {0};
        arena = &temporary;
        const Strings example = strings_concat(
            strings_concat(sentence.left[production.lhs], sentence_of(production.rhs, &sentence)),
            sentence.right[production.lhs]);
        InputToken *tokens = allocate((size_t)example.n * sizeof *tokens);
        for (int j = 0; j < example.n; ++j)
            tokens[j] = (InputToken){example.v[j], j + 1};
        const Parse parse = drive(&grammar, &sets, &table, tokens, example.n);
        const int errors = parse.skip + parse.pop + parse.missing;
        Text rendered = {0};
        line(&rendered, "  %d: %s", number + 1,
             production_text(grammar.v[production.lhs].name, production.rhs));
        heading_list(&rendered, "    example:", example);
        if (errors)
            line(&rendered, "    result: rejected (errors: %d)", errors);
        else
            line(&rendered, "    result: accepted");
        line(&rendered, "    used: %s", ints_has(parse.left_parse, number) ? "yes" : "no");
        arena = &permanent;
        add(&parses_file, "%s", rendered.data);
        arena_free(&temporary);
    }
    for (int i = 0; i < diagnostics.n; ++i)
        line(&diagnostics_file, "%s", diagnostics.v[i]);
    if (table.conflicts)
        line(&diagnostics_file, "result: not LL(1) (conflicts: %d)", table.conflicts);
    else
        line(&diagnostics_file, "result: LL(1)");
    write_report("grammar.txt", grammar_file);
    write_report("sets.txt", sets_file);
    write_report("table.txt", table_file);
    write_report("parses.txt", parses_file);
    write_report("diagnostics.txt", diagnostics_file);
    arena_free(&permanent);
    return 0;
}
